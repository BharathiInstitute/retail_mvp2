import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';

class PrintDemoPage extends StatefulWidget {
  const PrintDemoPage({super.key});
  @override
  State<PrintDemoPage> createState() => _PrintDemoPageState();
}

class _PrintDemoPageState extends State<PrintDemoPage> {
  final TextEditingController _receiptText = TextEditingController(text: 'Demo Store\nItem A  2 x 10.00 = 20.00\nItem B  1 x 15.00 = 15.00\n---------------------------\nTOTAL: 35.00\nTHANK YOU!');
  late final String backendBase;
  bool printing = false;

  @override
  void initState() {
    super.initState();
    backendBase = _resolveBackendBase();
  }

  String _resolveBackendBase() {
    const envUrl = String.fromEnvironment('PRINTER_BACKEND_URL', defaultValue: '');
    if (envUrl.isNotEmpty) return envUrl;
    if (kIsWeb) {
      final scheme = Uri.base.scheme == 'https' ? 'https' : 'http';
      final host = Uri.base.host.isEmpty ? 'localhost' : Uri.base.host;
      const port = 5005;
      return '$scheme://$host:$port';
    }
    return 'http://localhost:5005';
  }

  Future<void> _printText() async {
    setState(()=> printing = true);
    try {
      // Send only the text. The backend should use its default/connected printer.
      final resp = await http.post(
        Uri.parse('$backendBase/print-text'),
        headers: {'Content-Type':'application/json'},
        body: jsonEncode({'text': _receiptText.text}),
      );
      if (resp.statusCode == 200) {
        _snack('Printed');
      } else {
        _snack('Print failed: ${resp.statusCode}');
      }
    } catch (e) { _snack('Print error: $e'); } finally { setState(()=> printing = false); }
  }

  Future<void> _printPdf() async {
    setState(()=> printing = true);
    try {
      final pdfBytes = await _buildDemoPdf();
      final req = http.MultipartRequest('POST', Uri.parse('$backendBase/print-pdf'))
        ..files.add(http.MultipartFile.fromBytes('file', pdfBytes, filename: 'receipt.pdf'));
      final streamed = await req.send();
      final resp = await http.Response.fromStream(streamed);
      if (resp.statusCode == 200) {
        _snack('PDF Printed');
      } else { _snack('PDF print failed: ${resp.statusCode}'); }
    } catch (e) { _snack('PDF print error: $e'); } finally { setState(()=> printing = false); }
  }

  Future<Uint8List> _buildDemoPdf() async {
    final doc = pw.Document();
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.roll80,
      build: (ctx) {
        return pw.Column(children: [
          pw.Text('DEMO STORE', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text(DateTime.now().toString().substring(0,19)),
          pw.Divider(),
          pw.Text('Item A    2 x 10.00 = 20.00'),
            pw.Text('Item B    1 x 15.00 = 15.00'),
          pw.Divider(),
          pw.Text('TOTAL 35.00', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.BarcodeWidget(data: 'https://example.com', barcode: pw.Barcode.qrCode()),
          pw.SizedBox(height: 8),
          pw.Text('Thank you!'),
        ]);
      }
    ));
    return doc.save();
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Printing Demo')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 8),
            TextField(controller: _receiptText, maxLines: 8, decoration: const InputDecoration(labelText: 'Receipt Text (for Print Text)', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            Row(children:[
              ElevatedButton.icon(onPressed: printing ? null : _printText, icon: const Icon(Icons.print), label: const Text('Print Text Receipt')),
              const SizedBox(width: 12),
              ElevatedButton.icon(onPressed: printing ? null : _printPdf, icon: const Icon(Icons.picture_as_pdf), label: const Text('Print PDF Receipt')),
            ]),
          ]),
        ),
      ),
    );
  }
}
