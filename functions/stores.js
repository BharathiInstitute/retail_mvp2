const functions = require("firebase-functions");
const admin = require("firebase-admin");

function slugify(input) {
  return String(input || "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/(^-+|-+$)/g, '');
}

async function getCallerRole(uid, storeId) {
  // Try custom claims role (global), then membership role for the store
  const claimsUser = await admin.auth().getUser(uid).catch(() => null);
  const globalRole = claimsUser && claimsUser.customClaims && claimsUser.customClaims.role;
  if (!storeId) return globalRole || null;
  const memId = `${storeId}_${uid}`;
  const memDoc = await admin.firestore().collection('store_users').doc(memId).get();
  return memDoc.exists ? (memDoc.get('role') || globalRole || null) : (globalRole || null);
}

exports.createStore = functions.region('us-central1').https.onCall(async (data, context) => {
  try {
    if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Login required');
    const uid = context.auth.uid;
    const name = (data && data.name) ? String(data.name).trim() : '';
    if (!name || name.length < 3) throw new functions.https.HttpsError('invalid-argument', 'name must be >= 3 chars');
  const providedSlug = (data && data.slug) ? String(data.slug).trim() : '';
  const seedType = (data && data.seed) ? String(data.seed).toLowerCase() : 'empty'; // 'empty' | 'demo'
    const slug = providedSlug ? slugify(providedSlug) : slugify(name);

    const db = admin.firestore();
    // Idempotency by slug if present
    let storeRef;
    if (slug) {
      const snap = await db.collection('stores').where('slug', '==', slug).limit(1).get();
      if (!snap.empty) storeRef = snap.docs[0].ref;
    }
    if (!storeRef) storeRef = db.collection('stores').doc();

    const now = admin.firestore.FieldValue.serverTimestamp();
  await storeRef.set({ name, slug, status: 'active', createdAt: now, createdBy: uid }, { merge: true });

  const storeId = storeRef.id;
    const memId = `${storeId}_${uid}`;
    await db.collection('store_users').doc(memId).set({
      storeId,
      userId: uid,
      role: 'owner',
      status: 'active',
      acceptedAt: now,
    }, { merge: true });

    // Ensure the creator is recognized as an owner globally so they can fully configure the app.
    // This mirrors the existing security rule owner bypass (users/{uid}.role == 'owner' or custom claims).
    try {
      const userRef = db.collection('users').doc(uid);
      const userSnap = await userRef.get();
      if (!userSnap.exists || (userSnap.get('role') || '') !== 'owner') {
        await userRef.set({ role: 'owner', updatedAt: now }, { merge: true });
      }
      // Also set custom claims for immediate effect in the client
      try { await admin.auth().setCustomUserClaims(uid, { role: 'owner' }); } catch (_) {}
    } catch (e) {
      console.warn('createStore: failed to promote creator to owner claims/doc (non-fatal)', e?.message || e);
    }

    // Seed baseline data under subcollections (idempotent)
    try {
      await seedStore(admin.firestore(), storeId, seedType);
    } catch (seedErr) {
      console.warn('createStore: seedStore warning (non-fatal):', seedErr?.message || seedErr);
    }

    // Audit
    await admin.firestore().collection('audit_logs').add({
      ts: now,
      action: 'createStore',
      actorUid: uid,
      storeId,
      name,
      slug,
    });

    return { ok: true, storeId, slug, seed: seedType };
  } catch (err) {
    console.error('createStore error', err);
    if (err instanceof functions.https.HttpsError) throw err;
    throw new functions.https.HttpsError('internal', err?.message || String(err));
  }
});

/**
 * Seed minimal baseline docs for a store under subcollections.
 * Idempotent: uses set(..., {merge:true}) and checks counts before inserting demo.
 */
async function seedStore(db, storeId, seedType) {
  const now = admin.firestore.FieldValue.serverTimestamp();
  const storeRef = db.collection('stores').doc(storeId);

  // Settings
  await storeRef.collection('settings').doc('app').set({
    currency: 'INR',
    taxInclusive: true,
    createdAt: now,
    updatedAt: now,
  }, { merge: true });

  // Counters
  await storeRef.collection('counters').doc('invoices').set({ next: 1, updatedAt: now }, { merge: true });
  await storeRef.collection('counters').doc('products').set({ nextSku: 1000, updatedAt: now }, { merge: true });

  // Loyalty settings placeholder (readable by POS)
  await storeRef.collection('loyalty_settings').doc('config').set({
    enabled: false,
    pointsPerCurrency: 0,
    updatedAt: now,
  }, { merge: true });

  if (seedType !== 'demo') return; // empty seed ends here

  // For demo seed: insert a tiny dataset if not already present
  const prodCol = storeRef.collection('products');
  const prodSnap = await prodCol.limit(1).get();
  if (prodSnap.empty) {
    const demoProducts = [
      { name: 'Demo Product A', price: 199.0, sku: 'DEMO-A', status: 'active' },
      { name: 'Demo Product B', price: 299.0, sku: 'DEMO-B', status: 'active' },
    ];
    const batch = db.batch();
    demoProducts.forEach((p) => {
      const ref = prodCol.doc();
      batch.set(ref, Object.assign({}, p, { createdAt: now, updatedAt: now }));
    });
    await batch.commit();
  }

  const custCol = storeRef.collection('customers');
  const custSnap = await custCol.limit(1).get();
  if (custSnap.empty) {
    await custCol.doc().set({ name: 'Walk-in', phone: '', createdAt: now, updatedAt: now });
  }
}

exports.inviteUserToStore = functions.region('us-central1').https.onCall(async (data, context) => {
  try {
    if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Login required');
    const uid = context.auth.uid;
    const { storeId, email, role } = data || {};
    if (!storeId || !email) throw new functions.https.HttpsError('invalid-argument', 'storeId and email required');
    const tgtRole = role || 'viewer';
    const allowed = new Set(['owner','manager','cashier','viewer']);
    if (!allowed.has(tgtRole)) throw new functions.https.HttpsError('invalid-argument', 'Invalid role');

    const callerRole = await getCallerRole(uid, storeId);
    if (!callerRole || !['owner','manager'].includes(callerRole)) {
      throw new functions.https.HttpsError('permission-denied', 'Only owner/manager can invite');
    }

    const db = admin.firestore();
    const now = admin.firestore.FieldValue.serverTimestamp();

    // Simple rate limit: max 20 invites per hour per caller per store
    const rlId = `invite_${uid}_${storeId}`;
    const rlRef = db.collection('rate_limits').doc(rlId);
    await db.runTransaction(async (tx) => {
      const d = await tx.get(rlRef);
      const nowMs = Date.now();
      const windowMs = 60 * 60 * 1000; // 1 hour
      let count = 0; let windowStart = nowMs;
      if (d.exists) {
        count = d.get('count') || 0;
        windowStart = d.get('windowStart') || nowMs;
        if ((nowMs - windowStart) > windowMs) {
          count = 0; windowStart = nowMs;
        }
      }
      if (count >= 20) {
        throw new functions.https.HttpsError('resource-exhausted', 'Invite rate limit exceeded');
      }
      tx.set(rlRef, { count: count + 1, windowStart }, { merge: true });
    });

    // Optional: fetch store name for convenience
    let storeName = storeId;
    try { const s = await db.collection('stores').doc(storeId).get(); storeName = s.exists ? (s.get('name') || storeId) : storeId; } catch(_){}

    const invRef = db.collection('invites').doc();
    const expiresAt = new Date(Date.now() + 14 * 24 * 60 * 60 * 1000);
    await invRef.set({
      storeId,
      storeName,
      email: String(email).toLowerCase(),
      role: tgtRole,
      status: 'pending',
      invitedBy: uid,
      invitedAt: now,
      expiresAt,
    });
    // Audit
    await db.collection('audit_logs').add({ ts: now, action: 'inviteUserToStore', actorUid: uid, storeId, inviteId: invRef.id, email: String(email).toLowerCase(), role: tgtRole });
    return { ok: true, inviteId: invRef.id };
  } catch (err) {
    console.error('inviteUserToStore error', err);
    if (err instanceof functions.https.HttpsError) throw err;
    throw new functions.https.HttpsError('internal', err?.message || String(err));
  }
});

exports.acceptInvite = functions.region('us-central1').https.onCall(async (data, context) => {
  try {
    if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Login required');
    const uid = context.auth.uid;
    const { inviteId } = data || {};
    if (!inviteId) throw new functions.https.HttpsError('invalid-argument', 'inviteId required');

    const db = admin.firestore();
    const invRef = db.collection('invites').doc(inviteId);
    const invDoc = await invRef.get();
    if (!invDoc.exists) throw new functions.https.HttpsError('not-found', 'Invite not found');
    const inv = invDoc.data() || {};

    // Validate email matches current user
    const authUser = await admin.auth().getUser(uid);
    const userEmail = (authUser && authUser.email) ? authUser.email.toLowerCase() : '';
    const invEmail = String(inv.email || '').toLowerCase();
    if (!userEmail || userEmail !== invEmail) {
      throw new functions.https.HttpsError('permission-denied', 'Invite email does not match your account email');
    }

    if (inv.status !== 'pending') {
      throw new functions.https.HttpsError('failed-precondition', 'Invite is not pending');
    }
    // Expiry check
    if (inv.expiresAt && inv.expiresAt.toDate && inv.expiresAt.toDate() < new Date()) {
      await invRef.update({ status: 'expired' });
      throw new functions.https.HttpsError('failed-precondition', 'Invite expired');
    }

    const now = admin.firestore.FieldValue.serverTimestamp();
    const storeId = inv.storeId;
    const role = inv.role || 'viewer';
    const memId = `${storeId}_${uid}`;

    await db.runTransaction(async (tx) => {
      tx.set(db.collection('store_users').doc(memId), {
        storeId,
        userId: uid,
        role,
        status: 'active',
        acceptedAt: now,
      }, { merge: true });
      tx.update(invRef, { status: 'accepted', acceptedAt: now });
    });
    // Audit
    await db.collection('audit_logs').add({ ts: now, action: 'acceptInvite', actorUid: uid, storeId, inviteId: invRef.id, role });
    return { ok: true, storeId, role };
  } catch (err) {
    console.error('acceptInvite error', err);
    if (err instanceof functions.https.HttpsError) throw err;
    throw new functions.https.HttpsError('internal', err?.message || String(err));
  }
});

exports.declineInvite = functions.region('us-central1').https.onCall(async (data, context) => {
  try {
    if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Login required');
    const uid = context.auth.uid;
    const { inviteId } = data || {};
    if (!inviteId) throw new functions.https.HttpsError('invalid-argument', 'inviteId required');

    const db = admin.firestore();
    const invRef = db.collection('invites').doc(inviteId);
    const invDoc = await invRef.get();
    if (!invDoc.exists) throw new functions.https.HttpsError('not-found', 'Invite not found');
    const inv = invDoc.data() || {};

    // Validate email matches current user
    const authUser = await admin.auth().getUser(uid);
    const userEmail = (authUser && authUser.email) ? authUser.email.toLowerCase() : '';
    const invEmail = String(inv.email || '').toLowerCase();
    if (!userEmail || userEmail !== invEmail) {
      throw new functions.https.HttpsError('permission-denied', 'Invite email does not match your account email');
    }

    await invRef.update({ status: 'declined', declinedAt: admin.firestore.FieldValue.serverTimestamp() });
    await admin.firestore().collection('audit_logs').add({ ts: admin.firestore.FieldValue.serverTimestamp(), action: 'declineInvite', actorUid: uid, inviteId });
    return { ok: true };
  } catch (err) {
    console.error('declineInvite error', err);
    if (err instanceof functions.https.HttpsError) throw err;
    throw new functions.https.HttpsError('internal', err?.message || String(err));
  }
});
