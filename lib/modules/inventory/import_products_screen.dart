import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart' as csvpkg;
import 'package:excel/excel.dart' as xls;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth.dart';
import 'inventory_repository.dart';

/// Unified Products Import screen (CSV/XLSX): pick → preview → import → summary
class ImportProductsScreen extends ConsumerStatefulWidget {
  const ImportProductsScreen({super.key});

  @override
  ConsumerState<ImportProductsScreen> createState() => _ImportProductsScreenState();
}

enum _ImportStep { pick, preview, importing, summary }

enum _RowStatus { unknown, valid, invalid }

class _ParsedRow {
  final int index; // 0-based data index
  final Map<String, String> raw; // normalized header -> value
  final List<String> errors;
  final _RowStatus status;

  const _ParsedRow({required this.index, required this.raw, this.errors = const [], this.status = _RowStatus.unknown});

  _ParsedRow copyWith({List<String>? errors, _RowStatus? status}) =>
      _ParsedRow(index: index, raw: raw, errors: errors ?? this.errors, status: status ?? this.status);
}

class _Summary {
  final int added;
  final int updated;
  final int errored;
  final List<String> errorMessages;
  const _Summary({required this.added, required this.updated, required this.errored, required this.errorMessages});
}

class _ImportProductsScreenState extends ConsumerState<ImportProductsScreen> {
  _ImportStep step = _ImportStep.pick;
  List<_ParsedRow> rows = [];
  List<String> headers = [];
  int validCount = 0;
  int invalidCount = 0;
  String? pickedFileName;
  String _filter = 'all'; // all | valid | errors

  // Progress
  int processed = 0;
  int added = 0;
  int updated = 0;
  int errors = 0;
  final List<String> log = [];

  _Summary? summary;

  static const expectedHeaders = <String>[
    'SKU',
    'Name',
    'Barcode',
    'Unit Price',
    'MRP',
    'Cost Price',
    'GST %',
    'Variants',
    'Description',
    'Active',
    'Stock Store',
    'Stock Warehouse',
    'Supplier',
    // Dynamic batch columns (optional): Batch1 Qty, Batch1 Location, Batch1 Expiry, Batch2 Qty, ...
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import Products')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    switch (step) {
      case _ImportStep.pick:
        return _buildPick();
      case _ImportStep.preview:
        return _buildPreview();
      case _ImportStep.importing:
        return _buildImporting();
      case _ImportStep.summary:
        return _buildSummary();
    }
  }

  Widget _buildPick() {
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Step 1: Pick File (.csv / .xlsx)', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text(pickedFileName == null ? 'No file selected yet' : 'Selected: $pickedFileName'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.folder_open),
                label: const Text('Pick File (.csv / .xlsx)'),
              ),
              const SizedBox(height: 8),
              const Text('Accepted: CSV with headers or XLSX (first sheet).', style: TextStyle(color: Colors.black54))
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreview() {
    final total = rows.length;
    validCount = rows.where((r) => r.status == _RowStatus.valid).length;
    invalidCount = rows.where((r) => r.status == _RowStatus.invalid).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          Chip(label: Text('Total: $total')),
          Chip(label: Text('Valid: $validCount')),
          Chip(label: Text('Invalid: $invalidCount')),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'all', label: Text('All')),
              ButtonSegment(value: 'valid', label: Text('Valid')),
              ButtonSegment(value: 'errors', label: Text('Errors')),
            ],
            selected: {_filter},
            onSelectionChanged: (s) => setState(() => _filter = s.first),
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: () => setState(() => _validateAll()),
            icon: const Icon(Icons.refresh),
            label: const Text('Re-Validate'),
          ),
        ]),
        const SizedBox(height: 8),
        Expanded(
          child: Card(
            child: _PreviewTable(
              headers: headers,
              rows: switch (_filter) {
                'valid' => rows.where((r) => r.status == _RowStatus.valid).toList(),
                'errors' => rows.where((r) => r.status == _RowStatus.invalid).toList(),
                _ => rows,
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          OutlinedButton.icon(onPressed: () => setState(() => step = _ImportStep.pick), icon: const Icon(Icons.arrow_back), label: const Text('Back')),
          const Spacer(),
          FilledButton.icon(onPressed: validCount > 0 ? _startImport : null, icon: const Icon(Icons.play_arrow), label: const Text('Confirm Import')),
        ])
      ],
    );
  }

  Widget _buildImporting() {
    final total = rows.where((r) => r.status == _RowStatus.valid).length;
    final double? value = total == 0 ? null : (processed / total).clamp(0, 1).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Import in progress'),
              const SizedBox(height: 6),
              LinearProgressIndicator(value: value),
              const SizedBox(height: 6),
              Text('Processed: $processed/$total'),
              Text('Added: $added • Updated: $updated • Errors: $errors'),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Log'),
                  const SizedBox(height: 6),
                  Expanded(
                    child: Scrollbar(
                      thumbVisibility: true,
                      child: ListView.builder(
                        itemCount: log.length,
                        itemBuilder: (_, i) => Text(log[i]),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
            label: const Text('Close'),
          ),
        ])
      ],
    );
  }

  Widget _buildSummary() {
    final s = summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Import summary'),
                const SizedBox(height: 6),
                if (s != null) ...[
                  Text('Added: ${s.added}'),
                  Text('Updated: ${s.updated}'),
                  Text('Errors: ${s.errored}'),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (s != null && s.errorMessages.isNotEmpty)
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Errors'),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Scrollbar(
                        thumbVisibility: true,
                        child: ListView.builder(
                          itemCount: s.errorMessages.length,
                          itemBuilder: (_, i) => Text(s.errorMessages[i]),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Row(children: [
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
            label: const Text('Close'),
          ),
        ])
      ],
    );
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const ['csv', 'xls', 'xlsx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return; // cancelled
    final file = result.files.first;
    pickedFileName = file.name;

    try {
      if ((file.extension ?? '').toLowerCase() == 'csv') {
        final content = file.bytes != null
            ? _decodeText(file.bytes!)
            : (file.path != null ? await _readFileAsString(file.path!) : '');
        if (content.isEmpty) throw Exception('Empty CSV file.');
        _parseCsv(content);
      } else {
        final bytes = file.bytes ?? await _readFileAsBytes(file.path!);
        _parseXlsx(bytes);
      }
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to read file: $e')));
    }
  }

  void _parseCsv(String content) {
    // Support CRLF/CR by normalizing to \n
    final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final delimiter = _detectDelimiter(normalized);
    List<List<dynamic>> rowsList = csvpkg.CsvToListConverter(fieldDelimiter: delimiter, eol: '\n').convert(normalized);
    if (rowsList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('CSV has no rows')));
      return;
    }
    // Fallback parse attempt if only header present
    if (rowsList.length <= 1) {
      final alt = delimiter == ',' ? ';' : ',';
      try {
        final tryList = csvpkg.CsvToListConverter(fieldDelimiter: alt, eol: '\n').convert(normalized);
        if (tryList.length > rowsList.length) {
          rowsList = tryList;
        }
      } catch (_) {}
      // Final naive fallback: split lines and delimiter without quote handling
      if (rowsList.length <= 1) {
        final lines = normalized.split('\n').where((l) => l.trim().isNotEmpty).toList();
        if (lines.length > 1) {
          final delim = delimiter;
          final manual = <List<dynamic>>[];
          manual.add(lines.first.split(delim));
          for (var i = 1; i < lines.length; i++) {
            manual.add(lines[i].split(delim));
          }
          if (manual.length > rowsList.length) {
            rowsList = manual;
          }
        }
      }
    }
  final hdr = rowsList.first.map((e) => e.toString().trim()).toList();
  // Preserve original headers (including dynamic BatchN columns) for preview
  headers = hdr;
    final indexMap = _mapHeaders(hdr);
    if (indexMap == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Invalid headers. Expected: ${expectedHeaders.join(', ')}')));
      return;
    }
    rows = [];
    for (var i = 1; i < rowsList.length; i++) {
      final r = rowsList[i];
      if (r.isEmpty || !r.any((c) => c.toString().trim().isNotEmpty)) continue;
      final raw = <String, String>{};
      // Populate expected headers (mapped loosely)
      for (final h in expectedHeaders) {
        final idx = indexMap[h]!;
        raw[h] = idx < r.length ? r[idx].toString().trim() : '';
      }
      // Capture dynamic BatchN columns directly by header name
      final batchPattern = RegExp(r'^Batch\d+ (Qty|Location|Expiry)$', caseSensitive: false);
      for (int c = 0; c < hdr.length; c++) {
        final hName = hdr[c];
        if (expectedHeaders.contains(hName)) continue;
        if (batchPattern.hasMatch(hName)) {
          raw[hName] = c < r.length ? r[c].toString().trim() : '';
        }
      }
      rows.add(_ParsedRow(index: i - 1, raw: raw));
    }
    if (rows.isEmpty) {
      final hdrLen = hdr.length;
      final dataLen = rowsList.length > 1 ? rowsList[1].length : 0;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No data rows found in CSV. Parsed header cols: $hdrLen, first data cols: $dataLen. Ensure each row is on its own line and columns use comma/semicolon.')));
      return;
    }
    _validateAll();
    step = _ImportStep.preview;
  }

  void _parseXlsx(Uint8List bytes) {
    final ex = xls.Excel.decodeBytes(bytes);
    if (ex.tables.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('XLSX has no sheets')));
      return;
    }
    final table = ex.tables.values.first;
    if (table.maxRows == 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('XLSX is empty')));
      return;
    }
    final hdrRow = table.rows
        .firstWhere((row) => row.any((c) => (c?.value?.toString().trim().isNotEmpty ?? false)), orElse: () => []);
    final hdr = hdrRow.map((c) => (c?.value ?? '').toString().trim()).toList();
  // Preserve original headers including dynamic batch columns
  headers = hdr;
    final indexMap = _mapHeaders(hdr);
    if (indexMap == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Invalid headers. Expected: ${expectedHeaders.join(', ')}')));
      return;
    }
  rows = [];
    for (var r = 1; r < table.maxRows; r++) {
      final row = table.row(r);
      if (row.isEmpty || !row.any((c) => (c?.value?.toString().trim().isNotEmpty ?? false))) continue;
      final raw = <String, String>{};
      for (final h in expectedHeaders) {
        final idx = indexMap[h]!;
        String v = '';
        if (idx < row.length) {
          final cell = row[idx];
          v = (cell?.value ?? '').toString().trim();
        }
        raw[h] = v;
      }
      final batchPattern = RegExp(r'^Batch\d+ (Qty|Location|Expiry)$', caseSensitive: false);
      for (int c = 0; c < hdr.length; c++) {
        final hName = hdr[c];
        if (expectedHeaders.contains(hName)) continue;
        if (batchPattern.hasMatch(hName)) {
          String v = '';
          if (c < row.length) {
            final cell = row[c];
            v = (cell?.value ?? '').toString().trim();
          }
            raw[hName] = v;
        }
      }
      rows.add(_ParsedRow(index: r - 1, raw: raw));
    }
    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No data rows found in the first sheet.')));
      return;
    }
    _validateAll();
    step = _ImportStep.preview;
  }

  String _detectDelimiter(String text) {
    // Look at first non-empty line
    final line = text.split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    if (line.isEmpty) return ',';
    // Count common delimiters
    final comma = RegExp(',').allMatches(line).length;
    final semi = RegExp(';').allMatches(line).length;
    final tab = RegExp('\t').allMatches(line).length;
    if (semi > comma && semi >= tab) return ';';
    if (tab > comma && tab >= semi) return '\t';
    return ',';
  }

  String _decodeText(Uint8List bytes) {
    try {
      // Try UTF-8 (common)
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      // Try UTF-16 LE/BE via BOM or heuristic
      if (bytes.length >= 2) {
        final b0 = bytes[0], b1 = bytes[1];
        if (b0 == 0xFF && b1 == 0xFE) {
          // UTF-16 LE with BOM
          final bd = ByteData.sublistView(bytes, 2);
          final codeUnits = [for (var i = 0; i + 1 < bd.lengthInBytes; i += 2) bd.getUint16(i, Endian.little)];
          return String.fromCharCodes(codeUnits);
        }
        if (b0 == 0xFE && b1 == 0xFF) {
          // UTF-16 BE with BOM
          final bd = ByteData.sublistView(bytes, 2);
          final codeUnits = [for (var i = 0; i + 1 < bd.lengthInBytes; i += 2) bd.getUint16(i, Endian.big)];
          return String.fromCharCodes(codeUnits);
        }
        // Heuristic: many zero bytes at odd indexes => UTF-16 LE without BOM
        final zerosAtOdd = [for (var i = 1; i < bytes.length; i += 2) bytes[i] == 0].where((x) => x).length;
        if (zerosAtOdd > (bytes.length / 4)) {
          final bd = ByteData.sublistView(bytes);
          final codeUnits = [for (var i = 0; i + 1 < bd.lengthInBytes; i += 2) bd.getUint16(i, Endian.little)];
          return String.fromCharCodes(codeUnits);
        }
      }
      // Fallback latin1
      return latin1.decode(bytes, allowInvalid: true);
    }
  }

  Map<String, int>? _mapHeaders(List<String> hdr) {
    String normalizeLoose(String h) {
      var s = h.trim();
      // Strip UTF-8 BOM if present
      if (s.isNotEmpty && s.codeUnitAt(0) == 0xFEFF) {
        s = s.substring(1);
      }
      // Collapse whitespace
      s = s.replaceAll(RegExp(r'\s+'), ' ');
      return s;
    }

    String keyify(String h) {
      // Lowercase, remove spaces and common punctuation to match loose variants
      return normalizeLoose(h)
          .toLowerCase()
          .replaceAll(RegExp(r'\s'), '')
          .replaceAll('%', '')
          .replaceAll('_', '')
          .replaceAll('-', '');
    }

    final normalized = hdr.map((h) => normalizeLoose(h)).toList();
    final keys = normalized.map(keyify).toList();

    // Build target keys for expected headers
    final targetKeys = <String, String>{};
    for (final h in expectedHeaders) {
      targetKeys[h] = keyify(h);
    }

    final map = <String, int>{};
    // First try exact normalized match (case/space-insensitive)
    for (final h in expectedHeaders) {
      final k = targetKeys[h]!;
      final idx = keys.indexOf(k);
      if (idx == -1) {
        map.clear();
        break;
      }
      map[h] = idx;
    }

    if (map.isNotEmpty && map.length == expectedHeaders.length) return map;

    // If not matched, try synonym map for a few common variants
    final synonyms = <String, List<String>>{
      'Unit Price': ['price', 'unitprice', 'priceunit'],
      'MRP': ['mrpprice', 'mrp_amount', 'mrpprice'],
      'Cost Price': ['cost', 'costprice', 'purchaseprice'],
      // Added more variants including taxPct from export and generic tax names
      'GST %': ['gst', 'gstpercent', 'gstpct', 'gstpercentage', 'tax', 'taxpercent', 'taxpct'],
      'Stock Store': ['storeqty', 'storequantity', 'stockstore', 'storestock'],
      'Stock Warehouse': ['warehouseqty', 'warehousequantity', 'stockwarehouse', 'warehousestock'],
      'Supplier': ['supplierid', 'vendor', 'vendorid'],
      // Allow exported boolean column name isActive to map to Active
      'Active': ['isactive', 'enabled', 'status'],
    };

    map.clear();
    for (final h in expectedHeaders) {
      final k = targetKeys[h]!;
      var idx = keys.indexOf(k);
      if (idx == -1) {
        final syns = synonyms[h] ?? const <String>[];
        for (final s in syns) {
          final sk = keyify(s);
          idx = keys.indexOf(sk);
          if (idx != -1) break;
        }
      }
      if (idx == -1) {
        map.clear();
        break;
      }
      map[h] = idx;
    }
    if (map.isNotEmpty && map.length == expectedHeaders.length) return map;

    // Final fallback: if column count matches exactly, assume order-based mapping
    if (hdr.length >= expectedHeaders.length) {
      final byIndex = <String, int>{};
      for (var i = 0; i < expectedHeaders.length; i++) {
        byIndex[expectedHeaders[i]] = i;
      }
      return byIndex;
    }

    return null;
  }

  void _validateAll() {
    final fileSku = <String>{};
    final fileBarcode = <String>{};

    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final errors = <String>[];
      final sku = r.raw['SKU']!.trim().toUpperCase();
      final name = r.raw['Name']!.trim();
      final barcode = r.raw['Barcode']!.trim();
      final unitPrice = double.tryParse(r.raw['Unit Price']!.trim());
      final mrpPrice = r.raw['MRP']!.trim().isEmpty ? null : double.tryParse(r.raw['MRP']!.trim());
      final costPrice = r.raw['Cost Price']!.trim().isEmpty ? null : double.tryParse(r.raw['Cost Price']!.trim());
      final gstStr = r.raw['GST %']!.trim();
      final activeStr = r.raw['Active']!.trim();
  final storeQty = int.tryParse(r.raw['Stock Store']!.trim());
  final warehouseQty = int.tryParse(r.raw['Stock Warehouse']!.trim());

      if (name.isEmpty) {
        errors.add('Product name is required.');
      }
      if (sku.isEmpty) {
        errors.add('SKU is required.');
      }
      if (unitPrice == null) {
        errors.add('Unit Price must be a valid number.');
      }
      if (unitPrice != null) {
        final mrp = mrpPrice ?? unitPrice;
        final cost = costPrice ?? 0;
        if (mrp < unitPrice) {
          errors.add('MRP must be greater than or equal to Unit Price.');
        }
        if (unitPrice < cost) {
          errors.add('Unit Price must be greater than or equal to Cost Price.');
        }
      }
      final gst = gstStr.isEmpty ? null : int.tryParse(gstStr);
      const allowedGst = {0, 5, 12, 18};
      if (gst != null && !allowedGst.contains(gst)) {
        errors.add('GST % must be 0, 5, 12, or 18.');
      }
      if ((storeQty ?? -1) < 0 || (warehouseQty ?? -1) < 0) {
        errors.add('Stock values must be integers greater than or equal to 0.');
      }
      final isActive = activeStr.isEmpty ? true : (activeStr.toLowerCase() == 'true' || activeStr.toLowerCase() == 'yes');
      if (!isActive) {
        if ((storeQty ?? 0) > 0 || (warehouseQty ?? 0) > 0) {
          errors.add('Stock values ignored for inactive products.');
        }
      }

      // in-file duplicates
      if (!fileSku.add(sku)) {
        errors.add('Duplicate SKU "$sku" in file.');
      }
      if (barcode.isNotEmpty) {
        final isBarcodeNumeric = RegExp(r'^\d+$').hasMatch(barcode);
        if (!isBarcodeNumeric) {
          errors.add('Barcode must be numeric.');
        }
        if (!fileBarcode.add(barcode)) {
          errors.add('Duplicate barcode "$barcode" in file.');
        }
      }

      rows[i] = r.copyWith(
        errors: errors,
        status: errors.isEmpty ? _RowStatus.valid : _RowStatus.invalid,
      );
    }
  }

  Future<void> _startImport() async {
    setState(() {
      step = _ImportStep.importing;
      processed = 0;
      added = 0;
      updated = 0;
      errors = 0;
      log.clear();
    });

    final repo = InventoryRepository();
    final user = ref.read(authStateProvider);
    final tenantId = user?.uid;
    if (tenantId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please sign in to import.')));
      return;
    }

    final validRows = rows.where((r) => r.status == _RowStatus.valid).toList();

    final errorMessages = <String>[];
    for (var i = 0; i < validRows.length; i++) {
      final r = validRows[i];
      try {
        final sku = r.raw['SKU']!.trim().toUpperCase();
        final name = r.raw['Name']!.trim();
        final barcode = r.raw['Barcode']!.trim();
        final unitPrice = double.parse(r.raw['Unit Price']!.trim());
        final mrpPrice = r.raw['MRP']!.trim().isEmpty ? null : double.parse(r.raw['MRP']!.trim());
        final costPrice = r.raw['Cost Price']!.trim().isEmpty ? null : double.parse(r.raw['Cost Price']!.trim());
        final gst = r.raw['GST %']!.trim().isEmpty ? null : int.parse(r.raw['GST %']!.trim());
        final variants = r.raw['Variants']!
            .split(';')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        final description = r.raw['Description']!.trim();
        final isActive = r.raw['Active']!.trim().isEmpty
            ? true
            : (r.raw['Active']!.trim().toLowerCase() == 'true' || r.raw['Active']!.trim().toLowerCase() == 'yes');
        final storeQty = int.tryParse(r.raw['Stock Store']!.trim()) ?? 0;
        final warehouseQty = int.tryParse(r.raw['Stock Warehouse']!.trim()) ?? 0;
        final supplierId = r.raw['Supplier']!.trim().isEmpty ? null : r.raw['Supplier']!.trim();

        // Parse dynamic batch columns: BatchN Qty, BatchN Location, BatchN Expiry (ISO yyyy-MM-dd)
        final customBatches = <BatchDoc>[];
        // Collect keys to avoid repeated regex work
        final batchGroups = <String, Map<String, String>>{}; // n -> {Qty, Location, Expiry}
        for (final e in r.raw.entries) {
          final k = e.key.trim();
          final qtyM = RegExp(r'^Batch(\d+) Qty$', caseSensitive: false).firstMatch(k);
          final locM = RegExp(r'^Batch(\d+) Location$', caseSensitive: false).firstMatch(k);
          final expM = RegExp(r'^Batch(\d+) Expiry$', caseSensitive: false).firstMatch(k);
          void put(Match? m, String field) {
            if (m == null) return;
            final idx = m.group(1)!;
            batchGroups.putIfAbsent(idx, () => <String, String>{});
            batchGroups[idx]![field] = e.value.trim();
          }
          put(qtyM, 'Qty');
            put(locM, 'Location');
            put(expM, 'Expiry');
        }
        for (final entry in batchGroups.entries) {
          final map = entry.value;
          final qty = int.tryParse(map['Qty'] ?? '');
          if (qty == null || qty <= 0) continue; // skip invalid/empty
          final location = (map['Location']?.isNotEmpty ?? false) ? map['Location']!.trim() : 'Store';
          DateTime? expiry;
          final expStr = map['Expiry'];
          if (expStr != null && expStr.isNotEmpty) {
            try {
              expiry = DateTime.parse(expStr);
            } catch (_) {}
          }
          customBatches.add(BatchDoc(
            batchNo: 'BATCH-${entry.key}-$sku',
            qty: qty,
            location: location,
            expiry: expiry,
          ));
        }

        // Firestore barcode uniqueness check (best-effort)
        if (barcode.isNotEmpty) {
          final dup = await FirebaseFirestore.instance
              .collection('inventory')
              .where('barcode', isEqualTo: barcode)
              .limit(1)
              .get();
          if (dup.docs.isNotEmpty && dup.docs.first.id != sku) {
            errors++;
            processed++;
            final msg = 'Row ${r.index + 2} (SKU: $sku) failed: Duplicate barcode: $barcode already used by SKU ${dup.docs.first.id}';
            errorMessages.add(msg);
            log.add(msg);
            setState(() {});
            await Future<void>.delayed(const Duration(milliseconds: 8));
            continue;
          }
        }

        final outcome = await repo.upsertProductFromImport(
          tenantId: tenantId,
          sku: sku,
          name: name,
          unitPrice: unitPrice,
          taxPct: gst,
          barcode: barcode.isEmpty ? null : barcode,
          description: description.isEmpty ? null : description,
          variants: variants,
          mrpPrice: mrpPrice,
          costPrice: costPrice,
          isActive: isActive,
          storeQty: storeQty,
          warehouseQty: warehouseQty,
          supplierId: supplierId,
          customBatches: customBatches.isEmpty ? null : customBatches,
        );

        if (outcome == UpsertOutcome.added) {
          added++;
          log.add('Row ${r.index + 2} added $sku');
        } else {
          updated++;
          log.add('Row ${r.index + 2} updated $sku');
        }
        processed++;
        if (processed % 10 == 0 || processed == validRows.length) {
          setState(() {});
          await Future<void>.delayed(const Duration(milliseconds: 8));
        } else {
          await Future<void>.delayed(const Duration(milliseconds: 0));
        }
      } catch (e) {
        errors++;
        processed++;
        final msg = 'Row ${r.index + 2} (SKU: ${r.raw['SKU']}) failed: $e';
        errorMessages.add(msg);
        log.add(msg);
        setState(() {});
        await Future<void>.delayed(const Duration(milliseconds: 8));
      }
    }

    summary = _Summary(added: added, updated: updated, errored: errors, errorMessages: errorMessages);
    setState(() => step = _ImportStep.summary);
  }

  Future<String> _readFileAsString(String path) async {
    // Not used; file_picker provides bytes. Left unimplemented intentionally.
    throw UnimplementedError('Use withData: true in picker.');
  }

  Future<Uint8List> _readFileAsBytes(String path) async {
    throw UnimplementedError('Use withData: true in picker.');
  }
}

class _PreviewTable extends StatelessWidget {
  final List<String> headers;
  final List<_ParsedRow> rows;
  const _PreviewTable({required this.headers, required this.rows});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: [
              const DataColumn(label: Text('Status')),
              for (final h in headers) DataColumn(label: Text(h)),
            ],
            rows: [
              for (final r in rows)
                DataRow(
                  color: r.status == _RowStatus.invalid
                      ? WidgetStatePropertyAll(theme.colorScheme.error.withValues(alpha: 0.06))
                      : null,
                  cells: [
                    DataCell(r.status == _RowStatus.valid
                        ? const Tooltip(message: 'Valid', child: Text('✅'))
                        : r.status == _RowStatus.invalid
                            ? Tooltip(message: r.errors.join('\n'), child: const Text('❌'))
                            : const Text('•')),
                    for (final h in headers) DataCell(Text(r.raw[h] ?? '')),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
 
