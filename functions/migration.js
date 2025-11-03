const functions = require('firebase-functions');
const admin = require('firebase-admin');

/**
 * Callable: backfillTopToSub
 * Copies documents from top-level collections to store-scoped subcollections
 * under /stores/{storeId}/... based on each document's storeId field.
 *
 * AuthZ: owner only (via custom claim or users/{uid}.role == 'owner').
 *
 * Request shape:
 * {
 *   collections?: string[]; // defaults to common sets
 *   batchSize?: number;     // default 300
 *   dryRun?: boolean;       // simulate only
 *   storeId?: string;       // limit to one store
 *   whereMissingOnly?: boolean; // skip if destination exists
 * }
 */
exports.backfillTopToSub = functions.region('us-central1').runWith({ timeoutSeconds: 540 }).https.onCall(async (data, context) => {
  try {
    if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Login required');

    // Owner check (claims or users doc)
    const uid = context.auth.uid;
    const token = context.auth.token || {};
    let isOwner = token.role === 'owner';
    if (!isOwner) {
      const udoc = await admin.firestore().collection('users').doc(uid).get();
      isOwner = udoc.exists && udoc.get('role') === 'owner';
    }
    if (!isOwner) throw new functions.https.HttpsError('permission-denied', 'Owner only');

    const cfg = Object.assign({
      collections: ['inventory','customers','invoices','purchase_invoices','stock_movements','suppliers','alerts','loyalty','loyalty_settings'],
      batchSize: 300,
      dryRun: false,
      storeId: undefined,
      whereMissingOnly: true,
    }, data || {});

    const mapTarget = (top) => {
      switch (top) {
        case 'inventory': return 'products';
        case 'customers': return 'customers';
        case 'invoices': return 'invoices';
        case 'purchase_invoices': return 'purchase_invoices';
        case 'stock_movements': return 'stock_movements';
        case 'suppliers': return 'suppliers';
        case 'alerts': return 'alerts';
        case 'loyalty': return 'loyalty';
        case 'loyalty_settings': return 'loyalty_settings';
        default: return null;
      }
    };

    const db = admin.firestore();
    const summary = [];

    for (const col of cfg.collections) {
      const target = mapTarget(col);
      if (!target) continue;

      let q = db.collection(col);
      if (cfg.storeId) q = q.where('storeId', '==', cfg.storeId);

      let processed = 0, copied = 0, skipped = 0, errors = 0;
      let lastDoc = null;

      while (true) {
        let page = q.orderBy(admin.firestore.FieldPath.documentId()).limit(cfg.batchSize);
        if (lastDoc) page = page.startAfter(lastDoc.id);
        const snap = await page.get();
        if (snap.empty) break;

        const batch = db.batch();
        for (const doc of snap.docs) {
          processed++;
          const data = doc.data() || {};
          const storeId = data.storeId || data.store_id || data.tenantId; // fallback legacy keys
          if (!storeId || typeof storeId !== 'string') { skipped++; continue; }

          const destRef = db.collection('stores').doc(storeId).collection(target).doc(doc.id);
          if (cfg.whereMissingOnly) {
            try {
              const exists = await destRef.get();
              if (exists.exists) { skipped++; continue; }
            } catch (_) {}
          }
          try {
            if (!cfg.dryRun) batch.set(destRef, data, { merge: true });
            copied++;
          } catch (e) {
            console.error(`[backfill ${col}] failed for ${doc.id}`, e);
            errors++;
          }
        }
        if (!cfg.dryRun) await batch.commit();
        lastDoc = snap.docs[snap.docs.length - 1];
      }

      summary.push({ collection: col, target, processed, copied, skipped, errors });
    }

    return { ok: true, summary };
  } catch (err) {
    console.error('backfillTopToSub error', err);
    if (err instanceof functions.https.HttpsError) throw err;
    throw new functions.https.HttpsError('internal', err?.message || String(err));
  }
});
