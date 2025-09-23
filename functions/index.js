const functions = require("firebase-functions");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");

admin.initializeApp();

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

