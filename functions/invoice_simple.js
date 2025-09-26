const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { VertexAI } = require('@google-cloud/vertexai');

// Simple HTTPS callable that expects a file uploaded to Firebase Storage already.
// For this minimal flow, client will send base64 of image/pdf similar to existing analyzeInvoice
// but we only extract name + qty array.
exports.extractInvoiceItemsSimple = functions.region('us-central1').https.onCall(async (data) => {
  const { mimeType, bytesB64 } = data || {};
  if (!mimeType || !bytesB64) {
    throw new functions.https.HttpsError('invalid-argument', 'mimeType and bytesB64 required');
  }
  const buffer = Buffer.from(bytesB64, 'base64');
  try {
    const project = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT;
    const location = process.env.VERTEX_LOCATION || 'us-central1';
    const vertex = new VertexAI({ project, location });
    const model = vertex.getGenerativeModel({ model: 'gemini-1.5-flash' });
    const prompt = [
      'You are an OCR extraction assistant. Return ONLY strict JSON array of objects with keys name (string) and qty (number).',
      'Example: [{"name":"Air Freshener Citrus","qty":1},{"name":"Air Freshener Lavender","qty":2}]',
      'If quantity is missing assume 1. Never include other keys or narration.'
    ].join('\n');
    const parts = [{ text: prompt }, { inlineData: { mimeType, data: buffer.toString('base64') } }];
    const gen = await model.generateContent({ contents: [{ role: 'user', parts }], generationConfig: { responseMimeType: 'application/json' } });
    const response = gen.response ? (await gen.response) : gen;
    const candidate = response?.candidates?.[0];
    const jsonText = candidate?.content?.parts?.map(p => p.text).join('') || '[]';
    let arr;
    try { arr = JSON.parse(jsonText); } catch (_) { arr = []; }
    if (!Array.isArray(arr)) arr = [];
    // normalize
    arr = arr.filter(o => o && typeof o === 'object').map(o => ({
      name: String(o.name || o.itemName || '').trim(),
      qty: Number(o.qty || o.quantity || 1) || 1,
    })).filter(o => o.name);
    return arr;
  } catch (e) {
    console.error('extractInvoiceItemsSimple error', e);
    throw new functions.https.HttpsError('internal', e.message || String(e));
  }
});

// This function performs the inventory update logic in batch:
// For each item: if product with same name exists, increment stock; else create.
exports.applyInvoiceStockSimple = functions.region('us-central1').https.onCall(async (data, context) => {
  const { items } = data || {};
  if (!Array.isArray(items)) {
    throw new functions.https.HttpsError('invalid-argument', 'items array required');
  }
  const db = admin.firestore();
  const batch = db.batch();
  const results = [];
  for (const item of items) {
    if (!item || !item.name) continue;
    const name = String(item.name).trim();
    const qty = Number(item.qty) || 1;
    // Query by exact name match
    const snap = await db.collection('products').where('name', '==', name).limit(1).get();
    if (!snap.empty) {
      const doc = snap.docs[0];
      const ref = doc.ref;
      const current = doc.get('stock') || 0;
      batch.update(ref, { stock: current + qty });
      results.push({ name, action: 'increment', newStock: current + qty });
    } else {
      const ref = db.collection('products').doc();
      batch.set(ref, { name, stock: qty });
      results.push({ name, action: 'create', newStock: qty });
    }
  }
  await batch.commit();
  return { updated: results.length, results };
});
