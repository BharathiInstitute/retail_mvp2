import 'dart:typed_data';
import 'package:pdf/widgets.dart' as pw;
import 'package:retail_mvp2/modules/pos/pos_invoices/pdf_theme.dart' as app_pdf;
import 'package:barcode/barcode.dart';

/// Builds a PDF containing barcodes for the provided products.
/// Each product: shows SKU, existing stored barcode (raw), and a generated Code128 barcode
/// using either the stored barcode value (if non-empty) else the SKU.
Future<Uint8List> buildBarcodesPdf(List<BarcodeProduct> products) async {
  final doc = pw.Document();
  final code128 = Barcode.code128();
  const perPage = 10; // adjustable rows per page

  for (var i = 0; i < products.length; i += perPage) {
    final slice = products.sublist(i, (i + perPage).clamp(0, products.length));
    doc.addPage(
      pw.Page(
        margin: const pw.EdgeInsets.all(24),
        build: (ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Product Barcodes', style: app_pdf.PdfTheme.h1Bold),
              pw.SizedBox(height: 12),
              ...slice.map((p) {
                final data = p.realBarcode.isNotEmpty ? p.realBarcode : p.sku;
                final svg = code128.toSvg(data, width: 260, height: 60, drawText: false);
                return pw.Container(
                  margin: const pw.EdgeInsets.only(bottom: 16),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('SKU: ${p.sku}', style: app_pdf.PdfTheme.headerCell),
                            pw.Text('Stored Barcode: ${p.realBarcode.isEmpty ? '(none)' : p.realBarcode}', style: app_pdf.PdfTheme.cell),
                            pw.Text('Encoded: $data', style: app_pdf.PdfTheme.cell),
                            pw.SizedBox(height: 4),
                            pw.SvgImage(svg: svg),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
              if (i + perPage < products.length)
                pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('Continued ->', style: app_pdf.PdfTheme.accentSmall))
            ],
          );
        },
      ),
    );
  }

  return Uint8List.fromList(await doc.save());
}

class BarcodeProduct {
  final String sku;
  final String realBarcode; // current barcode field in Firestore
  BarcodeProduct({required this.sku, required this.realBarcode});
}
