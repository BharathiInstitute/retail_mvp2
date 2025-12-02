import express from 'express';
import cors from 'cors';
import bodyParser from 'body-parser';
import fileUpload from 'express-fileupload';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import * as cp from 'child_process';
import { execFile, execSync } from 'child_process';
import PDFDocument from 'pdfkit';

// Get __dirname equivalent for ES modules
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Always use user's AppData for data/temp files to avoid permission issues in Program Files
// This ensures the server works whether run from development or installed location
const DATA_DIR = path.join(process.env.APPDATA || process.env.LOCALAPPDATA || process.env.HOME || __dirname, 'RetailPOS-PrintHelper');

// Ensure data directory exists
if (!fs.existsSync(DATA_DIR)) {
  fs.mkdirSync(DATA_DIR, { recursive: true });
}

// NOTE: We no longer attempt to monkey-patch child_process methods on ESM modules
// because module namespace objects are read-only in Node >= 14+, which caused
// "Cannot assign to read only property 'spawn'" errors. We rely on pdf-to-printer
// defaults and set windowsHide in our own exec wrappers where applicable.

// Dynamically import pdf-to-printer AFTER patching child_process
const ptp = await import('pdf-to-printer');
const mod = ptp.default || ptp; // ESM/CJS compatibility
const _getPrintersInternal = mod.getPrinters;
const print = mod.print;

// Safe wrapper for getPrinters that falls back to PowerShell on Windows
async function getPrinters() {
  // First try PowerShell on Windows - more reliable
  if (process.platform === 'win32') {
    try {
      const psOutput = execSync('powershell.exe -NoProfile -Command "Get-Printer | Select-Object -ExpandProperty Name | ConvertTo-Json"', 
        { encoding: 'utf8', windowsHide: true, timeout: 10000 });
      const parsed = JSON.parse(psOutput.trim());
      const names = Array.isArray(parsed) ? parsed : (parsed ? [parsed] : []);
      // Return as objects to match pdf-to-printer format
      return names.map(n => ({ name: n }));
    } catch (psError) {
      console.error('PowerShell getPrinters failed:', psError.message);
    }
  }
  
  // Fallback to pdf-to-printer
  try {
    return await _getPrintersInternal();
  } catch (e) {
    console.error('pdf-to-printer getPrinters failed:', e.message);
    return [];
  }
}

const app = express();
app.use(cors());
app.use(bodyParser.json({ limit: '5mb' }));
app.use(fileUpload());

// Simple healthcheck for connectivity debugging
app.get('/health', (req,res)=> res.json({ ok: true }));

// Diagnostics endpoint to inspect runtime flags (avoid sensitive data)
app.get('/diagnostics', (req,res)=>{
  res.json({
    platform: process.platform,
    useRaw: process.env.USE_SIMPLE_PRINT === '1' || process.env.USE_RAW_PRINT === '1',
    nodeVersion: process.version,
    pid: process.pid,
    cwd: process.cwd()
  });
});

app.get('/logs', (req,res)=>{
  try {
    if (!fs.existsSync(LOG_PATH)) return res.json({ log: '' });
    const content = fs.readFileSync(LOG_PATH, 'utf8');
    const maxLen = 2000;
    const tail = content.length > maxLen ? content.slice(-maxLen) : content;
    res.json({ log: tail });
  } catch (e) {
    res.status(500).json({ error: String(e) });
  }
});

// Enumerate printers explicitly (for debugging a failing silent print). Safe to call manually.
app.get('/debug-printers', async (req,res)=>{
  try {
    const printersRaw = await getPrinters();
    const names = Array.isArray(printersRaw)
      ? printersRaw.map(p => (p && p.name) ? p.name : (typeof p === 'string' ? p : '')).filter(Boolean)
      : [];
    logToFile('DEBUG_PRINTERS names=' + JSON.stringify(names));
    res.json({ printers: names });
  } catch (e) {
    logToFile('DEBUG_PRINTERS_ERROR: ' + e);
    res.status(500).json({ error: String(e) });
  }
});

const CONFIG_PATH = path.join(DATA_DIR, 'config.json');
const LOG_PATH = path.join(DATA_DIR, 'print_backend.log');

function loadConfig() {
  try {
    const cfg = JSON.parse(fs.readFileSync(CONFIG_PATH,'utf8'));
    if (!('rawShare' in cfg)) cfg.rawShare = null; // augment existing configs
    if (!('settings' in cfg)) cfg.settings = {};
    return cfg;
  } catch {
    return { defaultPrinter: null, settings: {}, rawShare: null };
  }
}
function saveConfig(cfg) { fs.writeFileSync(CONFIG_PATH, JSON.stringify(cfg, null, 2)); }

// Attempt to assign a default thermal printer automatically if none is set.
async function autoAssignDefaultPrinter(cfg) {
  if (cfg.defaultPrinter) return cfg; // already set
  try {
    const printers = await getPrinters();
    if (!Array.isArray(printers) || printers.length === 0) return cfg;
    // Extract names (support objects or plain strings)
    const names = printers.map(p => typeof p === 'string' ? p : (p && p.name) ? p.name : '').filter(Boolean);
    if (names.length === 1) {
      cfg.defaultPrinter = names[0];
      saveConfig(cfg);
      logToFile(`AUTO_PRINTER_SINGLE: set defaultPrinter='${cfg.defaultPrinter}'`);
      return cfg;
    }
    const patterns = [
      /^pos ?58(?:\(2\))?$/i,
      /pos[- ]?58/i,
      /58mm/i,
    ];
    for (const pat of patterns) {
      const match = names.find(n => pat.test(n));
      if (match) {
        cfg.defaultPrinter = match;
        saveConfig(cfg);
        logToFile(`AUTO_PRINTER_PATTERN: set defaultPrinter='${cfg.defaultPrinter}' using pattern ${pat}`);
        return cfg;
      }
    }
  } catch (e) {
    logToFile('AUTO_PRINTER_ERROR: ' + e);
  }
  return cfg;
}

// Get config
app.get('/config', (req,res)=>{ res.json(loadConfig()); });

// Get printer status using PowerShell (Windows only)
async function getPrinterStatus(printerName) {
  return new Promise((resolve) => {
    if (process.platform !== 'win32') {
      resolve({ status: 'unknown', connected: true });
      return;
    }
    
    // Use PowerShell to get printer status
    const psCommand = `Get-Printer -Name '${printerName.replace(/'/g, "''")}' | Select-Object -Property PrinterStatus,DeviceType | ConvertTo-Json`;
    
    execFile('powershell.exe', ['-NoProfile', '-Command', psCommand], { windowsHide: true, timeout: 3000 }, (error, stdout, stderr) => {
      if (error) {
        // Printer might not exist or PowerShell failed
        resolve({ status: 'unknown', connected: false });
        return;
      }
      
      try {
        const result = JSON.parse(stdout.trim());
        // PrinterStatus: 0=Normal, 1=Paused, 2=Error, 3=Pending Deletion, 4=Paper Jam, 5=Paper Out, 6=Manual Feed, 7=Paper Problem, etc.
        const statusCode = result.PrinterStatus || 0;
        let status = 'ready';
        let connected = true;
        
        switch (statusCode) {
          case 0: status = 'ready'; connected = true; break;
          case 1: status = 'paused'; connected = true; break;
          case 2: status = 'error'; connected = false; break;
          case 3: status = 'deleting'; connected = false; break;
          case 4: status = 'paper_jam'; connected = true; break;
          case 5: status = 'paper_out'; connected = true; break;
          case 6: status = 'manual_feed'; connected = true; break;
          case 7: status = 'paper_problem'; connected = true; break;
          case 8: status = 'offline'; connected = false; break;
          case 9: status = 'io_active'; connected = true; break;
          case 10: status = 'busy'; connected = true; break;
          case 11: status = 'printing'; connected = true; break;
          case 12: status = 'output_bin_full'; connected = true; break;
          case 13: status = 'not_available'; connected = false; break;
          case 14: status = 'waiting'; connected = true; break;
          case 15: status = 'processing'; connected = true; break;
          case 16: status = 'initializing'; connected = true; break;
          case 17: status = 'warming_up'; connected = true; break;
          case 18: status = 'toner_low'; connected = true; break;
          case 19: status = 'no_toner'; connected = true; break;
          case 20: status = 'page_punt'; connected = true; break;
          case 21: status = 'user_intervention'; connected = true; break;
          case 22: status = 'out_of_memory'; connected = true; break;
          case 23: status = 'door_open'; connected = true; break;
          case 24: status = 'server_unknown'; connected = false; break;
          case 25: status = 'power_save'; connected = true; break;
          default: status = 'unknown'; connected = true;
        }
        
        resolve({ status, connected, statusCode });
      } catch (e) {
        resolve({ status: 'unknown', connected: true });
      }
    });
  });
}

// List printers with full details
app.get('/printers', async (req, res) => {
  try {
    const printersRaw = await getPrinters();
    const cfg = loadConfig();
    
    // Build detailed printer list
    const printers = [];
    if (Array.isArray(printersRaw)) {
      for (const p of printersRaw) {
        const name = typeof p === 'string' ? p : (p && p.name) ? p.name : '';
        if (!name) continue;
        
        // Get real printer status
        const statusInfo = await getPrinterStatus(name);
        
        // Detect connection type from name patterns
        let connectionType = 'unknown';
        const nameLower = name.toLowerCase();
        if (nameLower.includes('usb') || nameLower.includes('pos') || nameLower.includes('58') || nameLower.includes('80')) {
          connectionType = 'usb';
        } else if (nameLower.includes('wifi') || nameLower.includes('network') || nameLower.includes('wireless')) {
          connectionType = 'wifi';
        } else if (name.includes('\\\\') || nameLower.includes('shared')) {
          connectionType = 'network';
        } else if (nameLower.includes('pdf') || nameLower.includes('xps') || nameLower.includes('onenote') || nameLower.includes('fax')) {
          connectionType = 'virtual';
        } else {
          connectionType = 'local';
        }
        
        // Detect printer type
        let printerType = 'standard';
        if (nameLower.includes('pos') || nameLower.includes('58') || nameLower.includes('80') || nameLower.includes('thermal') || nameLower.includes('receipt')) {
          printerType = 'thermal';
        } else if (nameLower.includes('pdf') || nameLower.includes('xps') || nameLower.includes('onenote')) {
          printerType = 'virtual';
        }
        
        printers.push({
          name: name,
          connectionType: connectionType,
          printerType: printerType,
          isDefault: name === cfg.defaultPrinter,
          status: statusInfo.status,
          connected: statusInfo.connected,
          // Include raw properties if available
          ...(typeof p === 'object' ? { raw: p } : {})
        });
      }
    }
    
    // Sort: default first, then thermal, then by name
    printers.sort((a, b) => {
      if (a.isDefault && !b.isDefault) return -1;
      if (!a.isDefault && b.isDefault) return 1;
      if (a.printerType === 'thermal' && b.printerType !== 'thermal') return -1;
      if (a.printerType !== 'thermal' && b.printerType === 'thermal') return 1;
      return a.name.localeCompare(b.name);
    });
    
    res.json({ 
      printers: printers,
      defaultPrinter: cfg.defaultPrinter,
      count: printers.length
    });
  } catch (e) {
    console.error('GET /printers error:', e);
    res.status(500).json({ error: String(e) });
  }
});

// Simple print text (generate temporary text file and send to printer via default shell command fallback)
app.post('/print-text', async (req, res) => {
  const { printer, text, settings } = req.body || {};
  if (!text) return res.status(400).json({ error: 'text required' });
  const cfg = loadConfig();
  let targetPrinter = printer || cfg.defaultPrinter || undefined;
  if (!targetPrinter) {
    try {
      const names = await listPrintersSafe();
      if (names.length === 1) {
        targetPrinter = names.first ? names[0] : names[0];
      } else if (names.length === 0) {
        return res.status(400).json({ error: 'No printers found. Please install or configure a default printer.' });
      } else {
        return res.status(400).json({ error: 'No default printer configured. Use /set-default or set config.json defaultPrinter.', availablePrinters: names });
      }
    } catch (e) {
      return res.status(500).json({ error: 'Unable to determine printers: ' + e });
    }
  }
  try {
    // Skipping live printer validation to avoid spawning PowerShell/console windows on each print.
    const tempFile = path.join(DATA_DIR, 'temp_print.txt');
    fs.writeFileSync(tempFile, text, 'utf8');
    const opts = buildPrintOptions(targetPrinter, settings || cfg.settings);
    await print(tempFile, opts);
    res.json({ status: 'ok', usedPrinter: targetPrinter || 'system-default' });
  } catch (e) {
    console.error('POST /print-text error:', e);
    res.status(500).json({ error: String(e), usedPrinter: targetPrinter || 'system-default' });
  }
});

// Save defaults
app.post('/set-default', async (req,res)=>{
  const { printer, settings } = req.body || {};
  if (!printer) return res.status(400).json({ error: 'printer required' });
  try {
    const names = await listPrintersSafe();
    if (!names.includes(printer)) {
      return res.status(400).json({ error: `Printer '${printer}' not found`, availablePrinters: names });
    }
    const cfg = loadConfig();
    cfg.defaultPrinter = printer;
    cfg.settings = settings || {};
    saveConfig(cfg);
    res.json({ status:'ok' });
  } catch (e) {
    console.error('POST /set-default error:', e);
    res.status(500).json({ error: String(e) });
  }
});

// Set or clear raw share name for ESC/POS fallback (Windows printer sharing name)
app.post('/set-raw-share', (req,res)=>{
  const { share } = req.body || {};
  const cfg = loadConfig();
  cfg.rawShare = share || null;
  saveConfig(cfg);
  logToFile('SET_RAW_SHARE share=' + (cfg.rawShare || 'null'));
  res.json({ status: 'ok', rawShare: cfg.rawShare });
});

// Print PDF upload
app.post('/print-pdf', async (req,res)=>{
  if (!req.files || !req.files.file) return res.status(400).json({ error: 'file field required' });
  const cfg = loadConfig();
  const printer = req.body.printer || cfg.defaultPrinter;
  const f = req.files.file;
  const tempPath = path.join(DATA_DIR, 'upload_'+Date.now()+'.pdf');
  try {
    // Skip validation to keep operation silent (no PowerShell window for enumeration).
    await f.mv(tempPath);
    const opts = buildPrintOptions(printer, cfg.settings);
    await print(tempPath, opts);
    res.json({ status:'ok', usedPrinter: printer || 'system-default' });
  } catch (e) {
    console.error('POST /print-pdf error:', e);
    res.status(500).json({ error: String(e), usedPrinter: printer || 'system-default' });
  } finally {
    setTimeout(()=>{ try { fs.unlinkSync(tempPath); } catch {} }, 5000);
  }
});

// Print invoice directly from JSON payload (server builds 48mm thermal style PDF)
// Payload: { invoice: { invoiceNumber, timestamp, customerName, lines:[{name,qty,unitPrice,tax,lineTotal}], subtotal, discountTotal, taxTotal, grandTotal, taxesByRate } }
app.post('/print-invoice', async (req, res) => {
  try {
    const { invoice } = req.body || {};
    if (!invoice) return res.status(400).json({ error: 'invoice object required' });
    if (!Array.isArray(invoice.lines) || invoice.lines.length === 0) {
      return res.status(400).json({ error: 'invoice.lines required' });
    }
    let cfg = loadConfig();
    cfg = await autoAssignDefaultPrinter(cfg);
    let printer = cfg.defaultPrinter;
    if (!printer) {
      try {
        const names = await getPrinters();
        if (Array.isArray(names) && names.length === 1 && names[0] && names[0].name) {
          printer = names[0].name; // auto adopt the single printer
        } else if (!names || names.length === 0) {
          return res.status(400).json({ error: 'No printers detected. Install a printer or configure defaultPrinter in config.json.' });
        } else {
          return res.status(400).json({ error: 'Multiple printers found; set defaultPrinter via /set-default.', availablePrinters: names.map(p=>p.name).filter(Boolean) });
        }
      } catch (e) {
        return res.status(500).json({ error: 'Printer enumeration failed: ' + e });
      }
    }
    // Skip validation to avoid PowerShell enumeration when printing; rely on spooler failure if invalid.
    // Build PDF into buffer
    const pdfPath = path.join(DATA_DIR, `inv_${Date.now()}.pdf`);
    await buildThermalInvoicePdf(invoice, pdfPath);
    // Raw PowerShell fallback removed to prevent any visible window. Rely solely on pdf-to-printer.
    if (process.env.PRINT_VERBOSE === '1') {
      try {
        const dbgPrinters = await getPrinters();
        logToFile('VERBOSE_PRINTERS: ' + JSON.stringify(dbgPrinters));
      } catch (e) {
        logToFile('VERBOSE_PRINTERS_ERROR: ' + e);
      }
    }
    const opts = buildPrintOptions(printer, cfg.settings);
    try {
      const st = fs.statSync(pdfPath);
      logToFile(`PRINT_INVOICE_FILE_READY path=${pdfPath} size=${st.size}`);
    } catch (e) {
      logToFile(`PRINT_INVOICE_FILE_STAT_ERROR path=${pdfPath} err=${e}`);
    }
    logToFile(`PRINT_INVOICE_ATTEMPT file=${pdfPath} printer=${printer || 'system-default'} opts=${JSON.stringify(opts)}`);
    try {
      const delayMs = Number(process.env.PRINT_DELAY_MS || '0');
      if (delayMs > 0) {
        await new Promise(r => setTimeout(r, delayMs));
        logToFile('PRINT_INVOICE_DELAY_APPLIED ms=' + delayMs);
      }
      await print(pdfPath, opts);
      logToFile('PRINT_INVOICE_SUCCESS printer=' + (printer || 'system-default'));
      res.json({ status: 'ok', message: 'Invoice print sent', usedPrinter: printer || 'system-default' });
    } catch (err) {
      let errLine = 'PRINT_INVOICE_LIB_ERROR:';
      if (err && err.message) errLine += ' message=' + err.message.replace(/\s+/g,' ');
      if (err && err.code) errLine += ' code=' + err.code;
      if (err && err.stderr) errLine += ' stderr=' + String(err.stderr).trim();
      if (err && err.stdout) errLine += ' stdout=' + String(err.stdout).trim();
      errLine += ' full=' + (err && err.stack ? err.stack.split('\n')[0] : String(err));
      logToFile(errLine);
      // Additional diagnostic: attempt one enumeration after failure (still hidden)
      try {
        const afterPrinters = await getPrinters();
        logToFile('PRINT_INVOICE_AFTER_FAIL_PRINTERS: ' + JSON.stringify(afterPrinters));
      } catch (e2) {
        logToFile('PRINT_INVOICE_AFTER_FAIL_ENUM_ERROR: ' + e2);
      }
      // Attempt fallback plain text print (best effort) if on Windows
      if (process.platform === 'win32') {
        try {
          const txtPath = path.join(DATA_DIR, `inv_${Date.now()}.txt`);
          fs.writeFileSync(txtPath, buildPlainTextInvoice(invoice), 'utf8');
          logToFile('PRINT_INVOICE_FALLBACK_TXT_ATTEMPT file=' + txtPath);
          const winPrinterArg = `/D:${(printer || '').replace(/\s+/g,' ')}`; // print cmd cannot handle quoted printer inside /D:
          // Use legacy print command; returns stdout/stderr we log.
          const result = await execFileP('cmd.exe', ['/c', 'print', winPrinterArg, txtPath]);
          logToFile('PRINT_INVOICE_FALLBACK_TXT_RESULT stdout=' + result.stdout.trim().replace(/\s+/g,' ') + ' stderr=' + result.stderr.trim().replace(/\s+/g,' '));
          logToFile('PRINT_INVOICE_FALLBACK_TXT_SUCCESS printer=' + (printer || 'system-default'));
          setTimeout(()=>{ try { fs.unlinkSync(txtPath); } catch {} }, 4000);
          return res.json({ status: 'ok', message: 'Invoice print sent (txt fallback)', usedPrinter: printer || 'system-default', fallback: 'text' });
        } catch (fe) {
          logToFile('PRINT_INVOICE_FALLBACK_TXT_ERROR: ' + fe);
          // If text fallback failed AND a raw share is configured attempt ESC/POS share fallback
          try {
            const cfg2 = loadConfig();
            if (cfg2.rawShare) {
              const escPath = path.join(DATA_DIR, `inv_${Date.now()}.esc`);
              const escBuf = buildEscPosReceipt(invoice);
              fs.writeFileSync(escPath, escBuf);
              logToFile('PRINT_INVOICE_FALLBACK_ESC_ATTEMPT file=' + escPath + ' share=' + cfg2.rawShare);
              // type binary may corrupt if codepage mismatch; most ESC/POS accepts ASCII here; use /c cmd copy
              const sharePath = `\\\\localhost\\${cfg2.rawShare}`;
              // Using powershell might reveal window; keep with cmd copy
              const escResult = await execFileP('cmd.exe', ['/c', 'copy', '/b', escPath, sharePath]);
              logToFile('PRINT_INVOICE_FALLBACK_ESC_RESULT stdout=' + escResult.stdout.trim().replace(/\s+/g,' ') + ' stderr=' + escResult.stderr.trim().replace(/\s+/g,' '));
              logToFile('PRINT_INVOICE_FALLBACK_ESC_SUCCESS share=' + cfg2.rawShare);
              setTimeout(()=>{ try { fs.unlinkSync(escPath); } catch {} }, 4000);
              return res.json({ status: 'ok', message: 'Invoice print sent (ESC fallback)', usedPrinter: printer || 'system-default', fallback: 'escpos' });
            } else {
              logToFile('PRINT_INVOICE_FALLBACK_ESC_SKIPPED no rawShare configured');
            }
          } catch (escErr) {
            logToFile('PRINT_INVOICE_FALLBACK_ESC_ERROR: ' + escErr);
          }
        }
      }
      throw err; // bubble original error if fallback failed
    }
    setTimeout(()=>{ try { fs.unlinkSync(pdfPath); } catch {} }, 5000);
  } catch (e) {
    logToFile('PRINT_INVOICE_ERROR: ' + (e && e.stack ? e.stack : String(e)));
    console.error('POST /print-invoice error:', e);
    res.status(500).json({ error: String(e) });
  }
});

const PORT = process.env.PORT || 5005;
app.listen(PORT, () => console.log('Printer backend listening on ' + PORT));

// Helpers
function buildPrintOptions(printer, settings) {
  const opts = {};
  if (printer) opts.printer = String(printer);
  // Keep only safe options to avoid library regex on undefined values
  if (settings && typeof settings.monochrome === 'boolean') {
    opts.monochrome = settings.monochrome;
  }
  return opts;
}

// ---- Helpers: safe printer listing with Windows fallback ----
function execFileP(file, args, options) {
  return new Promise((resolve, reject) => {
    execFile(file, args, options, (err, stdout, stderr) => {
      if (err) return reject(err);
      resolve({ stdout, stderr });
    });
  });
}

async function listPrintersSafe() {
  try {
    const printers = await getPrinters();
    // Some environments return undefined properties; map defensively
    const names = Array.isArray(printers) ? printers.map(p => (p && p.name ? String(p.name) : '')).filter(Boolean) : [];
    return names; // No PowerShell fallback to avoid any visible windows.
  } catch (e) {
    throw e;
  }
}

// ----- PDF Generation (48mm thermal style) -----
function buildThermalInvoicePdf(invoice, outPath) {
  return new Promise((resolve, reject) => {
    try {
      const widthPts = (48/25.4)*72; // 48mm in PDF points
      // Estimate dynamic height based on number of lines to avoid excessive blank space or truncation.
      const lineCount = (() => {
        let base = 5; // title + number + timestamp + customer + first separator
        const itemLines = Array.isArray(invoice.lines) ? invoice.lines.length * 2 : 0; // name + qty line
        let totals = 6; // subtotal, discount (maybe), tax, total, thank you, spacing
        if (!invoice.discountTotal) totals -= 1; // remove discount line if none
        return base + itemLines + totals + 4; // extra spacing lines
      })();
      const estHeight = Math.max(300, lineCount * 12); // 12pt per line approx
      const doc = new PDFDocument({ size: [ widthPts, estHeight ], margin: 6 });
      const stream = fs.createWriteStream(outPath);
      doc.pipe(stream);
      const fontSizeSmall = 8;
      const fontSizeNormal = 9;
      const fontSizeTitle = 12;
      doc.fontSize(fontSizeTitle).text('INVOICE', { align: 'center' });
      if (invoice.invoiceNumber) doc.fontSize(fontSizeSmall).text(invoice.invoiceNumber, { align: 'center' });
      if (invoice.timestamp) doc.fontSize(fontSizeSmall).text(invoice.timestamp.toString(), { align: 'center' });
      doc.moveDown(0.3);
      if (invoice.customerName) doc.fontSize(fontSizeNormal).text(invoice.customerName, { align: 'center' });
      doc.moveDown(0.4);
      doc.moveTo(doc.x, doc.y).lineTo((48/25.4)*72 - 6*2, doc.y).stroke();
      doc.moveDown(0.2);
      // Lines
      invoice.lines.forEach(l => {
        const qty = l.qty ?? 1;
        const price = Number(l.unitPrice || 0).toFixed(2);
        const total = Number(l.lineTotal || 0).toFixed(2);
        const name = (l.name || '').toString();
        doc.fontSize(fontSizeSmall).text(name, { width: (48/25.4)*72 - 12 });
        doc.fontSize(fontSizeSmall).text(`${qty} x ${price} = ${total}`);
      });
      doc.moveDown(0.2);
      doc.moveTo(doc.x, doc.y).lineTo((48/25.4)*72 - 6*2, doc.y).stroke();
      doc.moveDown(0.2);
      // Totals
      const subtotal = Number(invoice.subtotal || 0).toFixed(2);
      const discount = Number(invoice.discountTotal || 0).toFixed(2);
      const tax = Number(invoice.taxTotal || 0).toFixed(2);
      const grand = Number(invoice.grandTotal || 0).toFixed(2);
      doc.fontSize(fontSizeSmall).text(`Subtotal: ${subtotal}`);
      if (invoice.discountTotal) doc.fontSize(fontSizeSmall).text(`Discount: -${discount}`);
      doc.fontSize(fontSizeSmall).text(`Tax: ${tax}`);
      doc.fontSize(fontSizeNormal).text(`TOTAL: ${grand}`, { align: 'right' });
      doc.moveDown(0.4);
      doc.fontSize(fontSizeSmall).text('Thank you!', { align: 'center' });
      doc.end();
      stream.on('finish', resolve);
      stream.on('error', reject);
    } catch (err) {
      reject(err);
    }
  });
}

// --- Simple file logger (since backend may run fully hidden) ---
function logToFile(message) {
  try {
    const line = `[${new Date().toISOString()}] ${message}\n`;
    fs.appendFileSync(LOG_PATH, line, 'utf8');
  } catch (_) {}
}

// --- Plain text fallback builder (very compact 48mm style) ---
function buildPlainTextInvoice(invoice) {
  const pad = (s, w) => {
    s = String(s); return s.length >= w ? s.slice(0,w) : s + ' '.repeat(w - s.length);
  };
  const lines = [];
  lines.push('       INVOICE');
  if (invoice.invoiceNumber) lines.push(String(invoice.invoiceNumber));
  if (invoice.timestamp) lines.push(String(invoice.timestamp));
  if (invoice.customerName) lines.push(invoice.customerName);
  lines.push('------------------------------');
  (invoice.lines || []).forEach(l => {
    const name = (l.name || '').toString();
    const qty = l.qty || 1; const price = Number(l.unitPrice||0).toFixed(2); const tot = Number(l.lineTotal||0).toFixed(2);
    lines.push(name);
    lines.push(`${qty} x ${price} = ${tot}`);
  });
  lines.push('------------------------------');
  const subtotal = Number(invoice.subtotal||0).toFixed(2);
  const discount = Number(invoice.discountTotal||0).toFixed(2);
  const tax = Number(invoice.taxTotal||0).toFixed(2);
  const grand = Number(invoice.grandTotal||0).toFixed(2);
  lines.push(`Subtotal: ${subtotal}`);
  if (invoice.discountTotal) lines.push(`Discount: -${discount}`);
  lines.push(`Tax: ${tax}`);
  lines.push(`TOTAL: ${grand}`);
  lines.push('');
  lines.push('  Thank you!');
  return lines.join('\r\n');
}

// --- ESC/POS fallback (very basic commands, no codepage shifting) ---
function buildEscPosReceipt(invoice) {
  const ESC = (s) => Buffer.from(s, 'binary');
  const chunks = [];
  const pushTxt = (text='') => { chunks.push(Buffer.from(text + '\n', 'ascii')); };
  // Init
  chunks.push(Buffer.from([0x1B,0x40])); // Initialize
  // Center
  chunks.push(Buffer.from([0x1B,0x61,0x01]));
  pushTxt('INVOICE');
  if (invoice.invoiceNumber) pushTxt(String(invoice.invoiceNumber));
  if (invoice.timestamp) pushTxt(String(invoice.timestamp));
  if (invoice.customerName) pushTxt(String(invoice.customerName));
  // Left align
  chunks.push(Buffer.from([0x1B,0x61,0x00]));
  pushTxt('------------------------------');
  (invoice.lines||[]).forEach(l => {
    const name = (l.name||'').toString();
    const qty = l.qty || 1; const price = Number(l.unitPrice||0).toFixed(2); const tot = Number(l.lineTotal||0).toFixed(2);
    pushTxt(name);
    pushTxt(`${qty} x ${price} = ${tot}`);
  });
  pushTxt('------------------------------');
  const subtotal = Number(invoice.subtotal||0).toFixed(2);
  const discount = Number(invoice.discountTotal||0).toFixed(2);
  const tax = Number(invoice.taxTotal||0).toFixed(2);
  const grand = Number(invoice.grandTotal||0).toFixed(2);
  pushTxt(`Subtotal: ${subtotal}`);
  if (invoice.discountTotal) pushTxt(`Discount: -${discount}`);
  pushTxt(`Tax: ${tax}`);
  pushTxt(`TOTAL: ${grand}`);
  // Center thank you
  chunks.push(Buffer.from([0x1B,0x61,0x01]));
  pushTxt('Thank you!');
  // Feed & cut (partial cut if supported)
  chunks.push(Buffer.from([0x1B,0x61,0x00])); // left
  chunks.push(Buffer.from('\n\n\n', 'ascii'));
  chunks.push(Buffer.from([0x1D,0x56,0x42,0x10])); // GS V B 16 (partial cut some models)
  return Buffer.concat(chunks);
}
