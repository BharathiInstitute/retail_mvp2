import express from 'express';
import cors from 'cors';
import bodyParser from 'body-parser';
import { getPrinters, print } from 'pdf-to-printer';
import fileUpload from 'express-fileupload';
import fs from 'fs';
import path from 'path';

const app = express();
app.use(cors());
app.use(bodyParser.json({ limit: '5mb' }));
app.use(fileUpload());

const CONFIG_PATH = path.join(process.cwd(), 'config.json');
function loadConfig() {
  try { return JSON.parse(fs.readFileSync(CONFIG_PATH,'utf8')); } catch { return { defaultPrinter: null, settings: {} }; }
}
function saveConfig(cfg) { fs.writeFileSync(CONFIG_PATH, JSON.stringify(cfg, null, 2)); }

// Get config
app.get('/config', (req,res)=>{ res.json(loadConfig()); });

// List printers
app.get('/printers', async (req, res) => {
  try {
    const printers = await getPrinters();
    res.json({ printers });
  } catch (e) {
    res.status(500).json({ error: String(e) });
  }
});

// Simple print text (generate temporary text file and send to printer via default shell command fallback)
app.post('/print-text', async (req, res) => {
  const { printer, text, settings } = req.body || {};
  if (!text) return res.status(400).json({ error: 'text required' });
  const cfg = loadConfig();
  const targetPrinter = printer || cfg.defaultPrinter || undefined;
  try {
    const tempFile = path.join(process.cwd(), 'temp_print.txt');
    fs.writeFileSync(tempFile, text, 'utf8');
    await print(tempFile, targetPrinter ? { printer: targetPrinter } : undefined);
    res.json({ status: 'ok', usedPrinter: targetPrinter || 'system-default' });
  } catch (e) {
    res.status(500).json({ error: String(e) });
  }
});

// Save defaults
app.post('/set-default', (req,res)=>{
  const { printer, settings } = req.body || {};
  if (!printer) return res.status(400).json({ error: 'printer required' });
  const cfg = loadConfig();
  cfg.defaultPrinter = printer;
  cfg.settings = settings || {};
  saveConfig(cfg);
  res.json({ status:'ok' });
});

// Print PDF upload
app.post('/print-pdf', async (req,res)=>{
  if (!req.files || !req.files.file) return res.status(400).json({ error: 'file field required' });
  const cfg = loadConfig();
  const printer = req.body.printer || cfg.defaultPrinter;
  const f = req.files.file;
  const tempPath = path.join(process.cwd(), 'upload_'+Date.now()+'.pdf');
  try {
    await f.mv(tempPath);
    await print(tempPath, printer ? { printer } : undefined);
    res.json({ status:'ok', usedPrinter: printer || 'system-default' });
  } catch (e) {
    res.status(500).json({ error: String(e) });
  } finally {
    setTimeout(()=>{ try { fs.unlinkSync(tempPath); } catch {} }, 5000);
  }
});

const PORT = process.env.PORT || 5005;
app.listen(PORT, () => console.log('Printer backend listening on ' + PORT));
