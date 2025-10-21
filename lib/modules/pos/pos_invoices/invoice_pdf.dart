import 'dart:typed_data';
import 'package:pdf/widgets.dart' as pw;
import 'invoice_models.dart';
import 'pdf_theme.dart';

Future<Uint8List> buildInvoicePdf(InvoiceData data) async {
  final doc = pw.Document();
  final dateStr = '${data.timestamp.year.toString().padLeft(4, '0')}-${data.timestamp.month.toString().padLeft(2, '0')}-${data.timestamp.day.toString().padLeft(2, '0')}';
  final timeStr = '${data.timestamp.hour.toString().padLeft(2, '0')}:${data.timestamp.minute.toString().padLeft(2, '0')}:${data.timestamp.second.toString().padLeft(2, '0')}';

  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        margin: const pw.EdgeInsets.all(24),
        textDirection: pw.TextDirection.ltr,
        orientation: pw.PageOrientation.portrait,
      ),
      header: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('TAX INVOICE', style: PdfTheme.h1Bold),
          pw.SizedBox(height: 4),
          pw.Text('Invoice #: ${data.invoiceNumber}'),
          pw.Text('Date: $dateStr  Time: $timeStr'),
          pw.Text('Customer: ${data.customerName}'),
          if (data.customerEmail != null && data.customerEmail!.isNotEmpty)
            pw.Text('Email: ${data.customerEmail}'),
          if (data.customerPhone != null && data.customerPhone!.isNotEmpty)
            pw.Text('Phone: ${data.customerPhone}'),
          pw.SizedBox(height: 8),
        ],
      ),
      build: (context) => [
        pw.Table(
          border: pw.TableBorder(
            bottom: pw.BorderSide(color: PdfTheme.border),
            horizontalInside: pw.BorderSide(color: PdfTheme.border, width: 0.4),
          ),
          columnWidths: {
            0: const pw.FlexColumnWidth(5),
            1: const pw.FlexColumnWidth(1.2),
            2: const pw.FlexColumnWidth(2),
            3: const pw.FlexColumnWidth(2),
            4: const pw.FlexColumnWidth(2),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfTheme.headerBg),
              children: [
                _h('Item'),
                _h('Qty'),
                _h('Rate'),
                _h('Disc'),
                _h('Total'),
              ],
            ),
            ...data.lines.map((l) => pw.TableRow(children: [
                  _c(l.name, align: pw.TextAlign.left),
                  _c('${l.qty}'),
                  _c('₹${l.unitPrice.toStringAsFixed(2)}'),
                  _c('₹${l.discount.toStringAsFixed(2)}'),
                  _c('₹${l.lineTotal.toStringAsFixed(2)}'),
                ])),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Row(children: [pw.Expanded(child: pw.Container()), _totalsBlock(data)]),
        pw.SizedBox(height: 16),
    pw.Text('GST Breakdown', style: PdfTheme.headerCell),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder.all(color: PdfTheme.border, width: 0.4),
          columnWidths: {0: const pw.FlexColumnWidth(2), 1: const pw.FlexColumnWidth(3)},
          children: [
            pw.TableRow(children: [
              _h('GST %'),
              _h('Amount'),
            ]),
            ...data.taxesByRate.entries.map((e) => pw.TableRow(children: [
                  _c('${e.key}%'),
                  _c('₹${e.value.toStringAsFixed(2)}'),
                ])),
          ],
        ),
        pw.SizedBox(height: 24),
    pw.Text('Thank you for your purchase!', style: PdfTheme.accentSmall),
      ],
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.centerRight,
    child: pw.Text('Generated on $dateStr $timeStr', style: PdfTheme.note),
      ),
    ),
  );

  return doc.save();
}

pw.Widget _h(String text) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: pw.Text(text, style: PdfTheme.headerCell),
    );

pw.Widget _c(String text, {pw.TextAlign align = pw.TextAlign.center}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: pw.Text(text, textAlign: align, style: PdfTheme.cell),
    );

pw.Widget _totalsBlock(InvoiceData d) {
  return pw.Container(
    width: 180,
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _kv('Subtotal', d.subtotal),
        _kv('Discount', -d.discountTotal),
        _kv('GST Total', d.taxTotal),
        if (d.redeemedValue > 0) _kv('Redeemed', -d.redeemedValue),
        pw.Divider(),
        _kv('Grand Total', d.grandTotal, bold: true),
        pw.SizedBox(height: 4),
    pw.Text('Paid via: ${d.paymentMode}', style: PdfTheme.cell),
        if (d.customerDiscountPercent > 0)
          pw.Text('Customer Discount: ${d.customerDiscountPercent.toStringAsFixed(0)}%', style: PdfTheme.cell),
        if (d.redeemedPoints > 0)
          pw.Text('Points Used: ${d.redeemedPoints.toStringAsFixed(0)}', style: PdfTheme.cell),
      ],
    ),
  );
}

pw.Widget _kv(String label, double value, {bool bold = false}) => pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: bold ? PdfTheme.headerCell : PdfTheme.cell),
        pw.Text('₹${value.toStringAsFixed(2)}', style: bold ? PdfTheme.headerCell : PdfTheme.cell),
      ],
    );
