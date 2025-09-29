const functions = require("firebase-functions");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");
// Lazy/optional dependencies (Vision + Vertex AI). They may not be installed in all environments.
let vision;
let VertexAI;
try { vision = require('@google-cloud/vision'); } catch(e){ console.warn('vision module unavailable (optional):', e.message); }
try { ({ VertexAI } = require('@google-cloud/vertexai')); } catch(e){ console.warn('vertexai module unavailable (optional):', e.message); }

admin.initializeApp();
// Load additional simple invoice workflow functions (added separately)
try { require('./invoice_simple'); } catch (e) { console.warn('invoice_simple not loaded', e?.message || e); }

/* Environment config options:
 * Generic SMTP:
 *   firebase functions:config:set \
 *     smtp.host="HOST" smtp.port="587" smtp.user="USER" smtp.pass="PASS" \
 *     from.email="no-reply@yourdomain.com" from.name="Retail ERP"
 * Gmail (will override generic SMTP if present):
 *   firebase functions:config:set \
 *     gmail.email="your@gmail.com" gmail.password="app_password" \
 *     from.email="your@gmail.com" from.name="Retail ERP"
 */
const cfg = functions.config();
const smtp = cfg.smtp || {};
const gmail = cfg.gmail || {};
const fromCfg = cfg.from || {};

let transporter;
if (gmail.email && gmail.password) {
	transporter = nodemailer.createTransport({
		service: "gmail",
		auth: {user: gmail.email, pass: gmail.password},
	});
} else {
	transporter = nodemailer.createTransport({
		host: smtp.host,
		port: Number(smtp.port || 587),
		secure: false,
		auth: {user: smtp.user, pass: smtp.pass},
	});
}

exports.sendInvoiceEmail = functions.https.onCall(async (data) => {
	console.log('[sendInvoiceEmail] incoming keys:', Object.keys(data || {}));
		const {
			invoiceNumber,
			invoiceData,
			to,
			customerEmail,
			subject,
			body,
			invoiceHtml,
			pdfBase64,
			pdfFilename,
		} = data || {};

		const recipient = to || customerEmail; // support both keys

		if (!recipient) {
		throw new functions.https.HttpsError(
			"invalid-argument",
			"Recipient (to) required",
		);
	}

	// Priority order:
	// 1. If pdfBase64 provided -> send with optional built or provided HTML
	// 2. Else if invoiceHtml provided -> send HTML only
	// 3. Else build HTML from invoiceData

	let finalHtml = invoiceHtml;
	let plain = body || "";

	if (pdfBase64 && !invoiceNumber) {
		throw new functions.https.HttpsError(
			"invalid-argument",
			"invoiceNumber required when sending PDF attachment",
		);
	}

	if (!finalHtml) {
		if (invoiceData) {
			const lines = (invoiceData.lines || []);
			const lineRows = lines.map((l) => [
				"<tr>",
				`<td style=\"padding:4px 8px;border:1px solid #ccc;\">${l.name}</td>`,
				`<td style=\"padding:4px 8px;border:1px solid #ccc;\" align=\"right\">${l.qty}</td>`,
				`<td style=\"padding:4px 8px;border:1px solid #ccc;\" align=\"right\">₹${Number(l.unitPrice).toFixed(2)}</td>`,
				`<td style=\"padding:4px 8px;border:1px solid #ccc;\" align=\"right\">₹${Number(l.discount).toFixed(2)}</td>`,
				`<td style=\"padding:4px 8px;border:1px solid #ccc;\" align=\"right\">₹${Number(l.lineTotal).toFixed(2)}</td>`,
				"</tr>",
			].join("")).join("");
			const headerCols = ["Item", "Qty", "Rate", "Disc", "Total"].map((h, i) => {
				const align = i === 0 ? "left" : "right";
				return `<th style=\"padding:4px 8px;border:1px solid #ccc;\" align=\"${align}\">${h}</th>`;
			}).join("");
			finalHtml = [
				`<p>${(body || "").replace(/\n/g, "<br/>")}</p>`,
				`<p><strong>Invoice:</strong> ${invoiceNumber}</p>`,
				`<table cellspacing=\"0\" cellpadding=\"0\" style=\"border-collapse:collapse;font-size:13px;\">` +
					`<thead><tr style=\"background:#f2f2f2;\">${headerCols}</tr></thead>` +
					`<tbody>${lineRows}</tbody>` +
				`</table>`,
				`<p><strong>Subtotal:</strong> ₹${Number(invoiceData.subtotal).toFixed(2)}<br/>` +
					`<strong>Discount:</strong> ₹${Number(invoiceData.discountTotal).toFixed(2)}<br/>` +
					`<strong>Tax:</strong> ₹${Number(invoiceData.taxTotal).toFixed(2)}<br/>` +
					`<strong>Grand Total:</strong> ₹${Number(invoiceData.grandTotal).toFixed(2)}</p>`,
			].join("\n");
			plain = `${body || ""}\nInvoice: ${invoiceNumber}\nTotal: ${invoiceData.grandTotal}`;
		} else if (invoiceNumber) {
			// Minimal fallback when only invoiceNumber + pdf provided
			finalHtml = `<p>${(body || '').replace(/\n/g,'<br/>')}</p><p><strong>Invoice:</strong> ${invoiceNumber}</p>`;
			plain = `${body || ''}\nInvoice: ${invoiceNumber}`;
		} else {
			throw new functions.https.HttpsError(
				"invalid-argument",
				"recipient with invoiceHtml or (invoiceNumber + pdfBase64) or (invoiceNumber + invoiceData) required",
			);
		}
	}

	const mailOptions = {
		from: `"${fromCfg.name || "Retail ERP"}" <${fromCfg.email || gmail.email || recipient}>`,
		to: recipient,
		subject: subject || (invoiceNumber ? `Invoice ${invoiceNumber}` : "Invoice"),
		html: finalHtml,
		text: plain,
		attachments: []
	};

	if (pdfBase64) {
		mailOptions.attachments.push({
			filename: pdfFilename || `${invoiceNumber || 'invoice'}.pdf`,
			content: Buffer.from(pdfBase64, 'base64'),
			contentType: 'application/pdf'
		});
	}

	await transporter.sendMail(mailOptions);
	return { status: 'sent', mode: pdfBase64 ? 'pdf-attach' : (invoiceHtml ? 'html-direct' : 'json-build') };
});

// Stateless invoice analysis: OCR (Vision) + Gemini JSON extraction
exports.analyzeInvoice = functions.region('us-central1').https.onCall(async (data, context) => {
		try {
			const { fileName, mimeType, bytesB64 } = data || {};
			if (!bytesB64 || !mimeType) {
				throw new functions.https.HttpsError('invalid-argument', 'bytesB64 and mimeType required');
			}

			const imgBuffer = Buffer.from(bytesB64, 'base64');
				let ocrText = '';
				let ocrNote;
					const cfgUseVision = (cfg && cfg.analyze && typeof cfg.analyze.use_vision !== 'undefined') ? String(cfg.analyze.use_vision) : '';
					const useVision = (
						(process.env.USE_VISION || '').toString().toLowerCase() === '1' ||
						(process.env.USE_VISION || '').toString().toLowerCase() === 'true' ||
						cfgUseVision.toLowerCase() === '1' || cfgUseVision.toLowerCase() === 'true'
					);
				if (useVision) {
					// Try OCR with Vision but don't fail overall if Vision is disabled
					try {
						if(!vision) throw new Error('vision module not installed');
						const client = new vision.ImageAnnotatorClient();
						const [result] = await client.documentTextDetection({ image: { content: imgBuffer } });
						ocrText = (result.fullTextAnnotation && result.fullTextAnnotation.text) || '';
						if (!ocrText.trim()) {
							ocrNote = 'Vision OCR returned no text';
						}
					} catch (visionErr) {
						console.warn('Vision OCR unavailable, will use Gemini-only parse', visionErr?.message || visionErr);
						ocrNote = 'Vision OCR unavailable; parsing directly with Gemini';
					}
				} else {
					ocrNote = 'Vision OCR disabled; parsing directly with Gemini';
				}

			// Gemini via Vertex AI (with graceful fallback)
				try {
				if(!VertexAI) throw new Error('vertexai module not installed');
				const project = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT;
				const location = process.env.VERTEX_LOCATION || 'us-central1';
				const vertex = new VertexAI({ project, location });
				const model = vertex.getGenerativeModel({ model: 'gemini-1.5-flash' });
					const prompt = [
						'You are a precise invoice parser. Extract line items as an array of objects with keys:',
						'itemName (string)',
						'quantity (number)',
						'price (number, unit price)',
						'gst (number, percent if available else 0)',
						'Return ONLY strict JSON of shape {"items": [{"itemName":"...","quantity":1,"price":0,"gst":0}], "meta": {"vendor": "?", "invoiceNumber": "?", "date": "?"}} without prose.',
						'',
						(ocrText ? 'Use this OCR text as reference.' : 'No OCR text available; read from image input.'),
						ocrText ? 'OCR TEXT START\n' + ocrText.slice(0, 150000) + '\nOCR TEXT END' : '',
					].join('\n');

					const parts = [{ text: prompt }];
					// Include the image for Gemini so it can do its own reading when OCR is missing
					parts.push({ inlineData: { mimeType, data: imgBuffer.toString('base64') } });

					const gen = await model.generateContent({
						contents: [{ role: 'user', parts }],
						generationConfig: { responseMimeType: 'application/json' },
					});
				const response = gen.response ? (await gen.response) : gen;
				const candidate = response?.candidates?.[0];
				const jsonText = candidate?.content?.parts?.map((p) => p.text).join('') || '{}';
				let parsed;
				try {
					parsed = JSON.parse(jsonText);
				} catch (_) {
					parsed = { items: [], meta: { raw: jsonText } };
				}
				// Normalize shape
				if (!parsed || typeof parsed !== 'object') parsed = { items: [], meta: {} };
				if (!Array.isArray(parsed.items)) parsed.items = [];
				if (!parsed.meta || typeof parsed.meta !== 'object') parsed.meta = {};
				const m = parsed.meta;
				if (typeof m.vendor === 'undefined') m.vendor = '';
				if (typeof m.invoiceNumber === 'undefined') m.invoiceNumber = '';
				if (typeof m.date === 'undefined') m.date = '';
				if (ocrText && typeof m.ocrText === 'undefined') m.ocrText = ocrText;
				parsed.meta = m;
				return parsed;
			} catch (gemErr) {
				console.error('Gemini parse failed, returning OCR-only result', gemErr);
				return { items: [], meta: { vendor: '', invoiceNumber: '', date: '', ocrText, note: 'Gemini unavailable; showing OCR text only' } };
			}
	} catch (err) {
			console.error('analyzeInvoice error', err);
			if (err instanceof functions.https.HttpsError) throw err;
			// Provide clearer hints for common setup issues
			const msg = (err && err.message) ? err.message : String(err);
			// Identify API not enabled or permission errors
			const hint = /permission|PERMISSION|not enabled|Enable the API/i.test(msg)
				? 'Verify Cloud Vision API and Vertex AI are enabled, and the Cloud Functions service account has access.'
				: undefined;
			throw new functions.https.HttpsError('internal', hint ? `${msg} — ${hint}` : msg);
	}
});

// -------------------------------------------------------------
// createUserAccount (callable)
// -------------------------------------------------------------
// Creates a Firebase Auth user + (optionally) the Firestore /users doc
// and assigns a role via custom claims. The client currently creates
// the Firestore doc itself; this function is the authoritative place
// for secure Auth user + claims creation. It is idempotent per email.
// -------------------------------------------------------------
exports.createUserAccount = functions.region('us-central1').https.onCall(async (data, context) => {
	try {
		console.log('[createUserAccount] raw data keys:', Object.keys(data || {}));
		if (!context.auth) {
			throw new functions.https.HttpsError('unauthenticated', 'Login required');
		}

		const callerClaims = context.auth.token || {};
		const allowedRoles = new Set(['owner', 'manager']); // Roles allowed to create users
		let callerRole = callerClaims.role;

		// Fallback: if custom claim not present, look up Firestore /users doc
		if (!callerRole) {
			try {
				const callerDoc = await admin.firestore().collection('users').doc(context.auth.uid).get();
				callerRole = callerDoc.exists ? callerDoc.get('role') : undefined;
			} catch (_) {
				// ignore; will be caught by role check below
			}
		}
		if (!callerRole || !allowedRoles.has(String(callerRole))) {
			throw new functions.https.HttpsError('permission-denied', 'Insufficient privileges to create users');
		}

		const { email, password, displayName, role, stores } = data || {};
		if (!email || !password) {
			throw new functions.https.HttpsError('invalid-argument', 'email & password required');
		}
		const targetRole = role || 'clerk';
		const roleWhitelist = new Set(['owner','manager','accountant','cashier','clerk']);
		if (!roleWhitelist.has(targetRole)) {
			throw new functions.https.HttpsError('invalid-argument', 'Invalid role');
		}

		// Idempotency: if user already exists by email, reuse
		let userRecord;
		try {
			userRecord = await admin.auth().getUserByEmail(email);
			console.log('[createUserAccount] existing user found for email');
		} catch (err) {
			// If not found, create; else rethrow
			if (err.code !== 'auth/user-not-found') {
				console.error('[createUserAccount] getUserByEmail failed', err);
				throw err;
			}
		}

		let created = false;
		if (!userRecord) {
			try {
				userRecord = await admin.auth().createUser({ email, password, displayName });
				created = true;
				console.log('[createUserAccount] user created', userRecord.uid);
			} catch (createErr) {
				console.error('[createUserAccount] createUser error', createErr);
				throw createErr;
			}
		} else if (displayName && userRecord.displayName !== displayName) {
			// Sync display name if provided & changed
			await admin.auth().updateUser(userRecord.uid, { displayName });
		}

		// Always (re)set custom claims to ensure correctness
		try {
			await admin.auth().setCustomUserClaims(userRecord.uid, { role: targetRole });
		} catch (claimsErr) {
			console.error('[createUserAccount] setCustomUserClaims failed', claimsErr);
			throw claimsErr;
		}

		// Optionally ensure Firestore profile exists (idempotent)
		const usersCol = admin.firestore().collection('users');
		const userDocRef = usersCol.doc(userRecord.uid);
		const userDoc = await userDocRef.get();
		const now = admin.firestore.FieldValue.serverTimestamp();
		if (!userDoc.exists) {
			await userDocRef.set({
				email,
				displayName: displayName || email.split('@')[0],
				role: targetRole,
				stores: Array.isArray(stores) ? stores.filter(s => typeof s === 'string' && s.trim()) : [],
				createdAt: now,
				updatedAt: now,
			});
		} else {
			// Keep role in sync if changed via this path
			const updates = { updatedAt: now };
			if (userDoc.get('role') !== targetRole) updates.role = targetRole;
			if (displayName && userDoc.get('displayName') !== displayName) updates.displayName = displayName;
			if (Object.keys(updates).length > 1) await userDocRef.update(updates);
		}

		return { uid: userRecord.uid, created, role: targetRole, claimsSet: true };
	} catch (err) {
		console.error('createUserAccount error', err);
		if (err instanceof functions.https.HttpsError) throw err;
		const msg = err && err.message ? err.message : String(err);
		// Map common auth errors to HttpsError
		if (/email-already-in-use|email-already-exists/i.test(msg)) {
			throw new functions.https.HttpsError('already-exists', 'Email already in use');
		}
		if (/invalid-password|password.*6 characters/i.test(msg)) {
			throw new functions.https.HttpsError('invalid-argument', 'Password must be at least 6 characters');
		}
		if (/invalid-email/i.test(msg)) {
			throw new functions.https.HttpsError('invalid-argument', 'Invalid email');
		}
		if (/operation-not-allowed|OPERATION_NOT_ALLOWED/i.test(msg)) {
			throw new functions.https.HttpsError('failed-precondition', 'Auth provider not enabled (Email/Password)');
		}
		if (/uid-already-exists/i.test(msg)) {
			throw new functions.https.HttpsError('already-exists', 'UID already exists');
		}
		if (/setCustomUserClaims/i.test(msg)) {
			throw new functions.https.HttpsError('internal', 'Failed to set custom claims');
		}
		throw new functions.https.HttpsError('internal', msg);
	}
});

