import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'parsed_items_screen.dart';

class UploadInvoiceScreen extends StatefulWidget {
  const UploadInvoiceScreen({super.key});
  @override
  State<UploadInvoiceScreen> createState() => _UploadInvoiceScreenState();
}

class _UploadInvoiceScreenState extends State<UploadInvoiceScreen> {
  Uint8List? _bytes;
  String? _mime;
  String? _name;
  bool _loading = false;
  String? _error;

  Future<void> _pick() async {
    setState(() { _error = null; });
    final res = await FilePicker.platform.pickFiles(withData: true, allowedExtensions: ['pdf','jpg','jpeg','png'], type: FileType.custom);
    if (res == null || res.files.isEmpty) return;
    final f = res.files.single;
    final ext = (f.extension ?? '').toLowerCase();
    setState(() {
      _bytes = f.bytes;
      _name = f.name;
      _mime = ext == 'pdf' ? 'application/pdf' : 'image/${ext == 'jpg' ? 'jpeg': ext}';
    });
  }

  Future<void> _analyze() async {
    if (_bytes == null || _mime == null) return;
    setState(() { _loading = true; _error = null; });
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable('extractInvoiceItemsSimple');
      final resp = await callable.call({ 'mimeType': _mime, 'bytesB64': base64Encode(_bytes!) });
      final items = (resp.data as List).map((e) => Map<String,dynamic>.from(e)).toList();
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => ParsedItemsScreen(items: items)));
    } on FirebaseFunctionsException catch (e) {
      setState(() { _error = e.message; });
    } catch (e) {
      setState(() { _error = e.toString(); });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upload Invoice')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _bytes != null && !_loading ? _analyze : null,
        icon: const Icon(Icons.play_arrow), label: const Text('Analyze'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_bytes == null) ...[
              const Text('Pick an invoice (PDF/JPG/PNG)', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 16),
              FilledButton.icon(onPressed: _pick, icon: const Icon(Icons.upload), label: const Text('Select File')),
            ] else ...[
              Text(_name ?? 'file', style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 8),
              Text(_mime ?? ''),
              const SizedBox(height: 16),
              FilledButton.icon(onPressed: _pick, icon: const Icon(Icons.change_circle), label: const Text('Change File')),
            ],
            const SizedBox(height: 24),
            if (_loading) const CircularProgressIndicator(),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
          ]),
        ),
      ),
    );
  }
}
