import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:retail_mvp2/core/theme/theme_utils.dart';

import '../../../core/auth/auth.dart';
import 'inventory.dart' show inventoryRepoProvider, productsStreamProvider, selectedStoreProvider; // reuse providers
import 'inventory_repository.dart' show ProductDoc, InventoryRepository;

class InvoiceAnalysisPage extends ConsumerStatefulWidget {
  const InvoiceAnalysisPage({super.key});

  @override
  ConsumerState<InvoiceAnalysisPage> createState() => _InvoiceAnalysisPageState();
}

class _InvoiceAnalysisPageState extends ConsumerState<InvoiceAnalysisPage> {
  Uint8List? _fileBytes;
  String? _fileName;
  String? _mimeType;
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _result;

  // Movement config
  String _movement = 'Purchase (+)'; // or 'Sale (-)'
  String _location = 'Store'; // 'Store' | 'Warehouse'

  Future<void> _pickFile() async {
    setState(() {
      _error = null;
      _result = null;
    });
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    setState(() {
      _fileBytes = f.bytes;
      _fileName = f.name;
      final ext = (f.extension ?? '').toLowerCase();
      _mimeType = ext == 'pdf' ? 'application/pdf' : 'image/${ext == 'jpg' ? 'jpeg' : ext}';
    });
  }

  Future<void> _analyze() async {
    if (_fileBytes == null || _mimeType == null) return;
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
  // Ensure region matches the function's region
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable('analyzeInvoice');
      final response = await callable.call({
        'fileName': _fileName,
        'mimeType': _mimeType,
        'bytesB64': base64Encode(_fileBytes!),
      });
      if (!mounted) return;
      final data = response.data as Map;
      setState(() {
        _result = Map<String, dynamic>.from(data);
      });
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() {
        final parts = <String>[];
        if (e.message != null && e.message!.trim().isNotEmpty) parts.add(e.message!);
        if (e.details != null) parts.add('Details: ${e.details}');
        if (parts.isEmpty) parts.add(e.toString());
        _error = parts.join('\n');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openManualAddDialog() {
    showDialog(context: context, builder: (ctx) {
      final rows = <_ManualRow>[_ManualRow()];
      return StatefulBuilder(builder: (context, setS) {
        void addRow() => setS(() => rows.add(_ManualRow()));
        void save() {
          final items = <Map<String,dynamic>>[];
          for (final r in rows) {
            final name = r.name.text.trim();
            final qty = int.tryParse(r.qty.text.trim()) ?? 0;
            if (name.isEmpty || qty <= 0) continue;
            final price = double.tryParse(r.price.text.trim());
            final gst = double.tryParse(r.gst.text.trim());
            items.add({
              'itemName': name,
              'quantity': qty,
              if (price != null) 'price': price,
              if (gst != null) 'gst': gst,
            });
          }
          if (items.isEmpty) { Navigator.pop(context); return; }
          setState(() { _result = {'items': items, 'meta': {'manual': true}}; });
          Navigator.pop(context);
        }
        return AlertDialog(
          title: Text(
            'Add Items Manually',
            style: context.texts.titleMedium?.copyWith(color: context.colors.onSurface, fontWeight: FontWeight.w700),
          ),
          content: DefaultTextStyle(
            style: (context.texts.bodyMedium ?? const TextStyle()).copyWith(color: context.colors.onSurface),
            child: SizedBox(
            width: 640,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                height: 340,
                child: ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (c, i) {
                    final r = rows[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(children: [
                        Expanded(flex:3, child: TextField(controller: r.name, decoration: const InputDecoration(labelText: 'Item Name', isDense: true))),
                        const SizedBox(width: 8),
                        Expanded(flex:1, child: TextField(controller: r.qty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Qty', isDense: true))),
                        const SizedBox(width: 8),
                        Expanded(flex:2, child: TextField(controller: r.price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Price', isDense: true))),
                        const SizedBox(width: 8),
                        Expanded(flex:2, child: TextField(controller: r.gst, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'GST %', isDense: true))),
                        const SizedBox(width: 4),
                        IconButton(onPressed: () { setS(() { rows.removeAt(i); }); }, icon: const Icon(Icons.delete, size: 18))
                      ]),
                    );
                  },
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(onPressed: addRow, icon: const Icon(Icons.add), label: const Text('Add Row')),
              ),
            ]),
          ),
        ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(onPressed: save, child: const Text('Use Items')),
          ],
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsStreamProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Invoice Analysis (Stateless)')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
            'Upload an invoice (PDF/JPG/PNG). The app sends the file to a Cloud Function, '
            'which runs OCR + Gemini to return structured items without storing data.',
          ),
          const SizedBox(height: 12),
          Row(children: [
            ElevatedButton.icon(
              onPressed: _loading ? null : _pickFile,
              icon: const Icon(Icons.upload_file),
              label: const Text('Choose File'),
            ),
            const SizedBox(width: 12),
            if (_fileName != null) Expanded(child: Text(_fileName!, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: (_fileBytes != null && !_loading) ? _analyze : null,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Analyze'),
            ),
            const SizedBox(width: 12),
            // Auto-apply UI removed
          ]),
          const SizedBox(height: 16),
          const SizedBox(height: 16),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              'Error: $_error',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            Text('Tips:', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w700)),
            const Text('• Ensure Cloud Vision API and Vertex AI are enabled for your GCP project.'),
            const Text('• Deploy functions and set the correct region (us-central1 by default).'),
            const Text('• Verify Functions service account has permission to call Vision and Vertex AI.'),
          ],
          const SizedBox(height: 16),
          Expanded(
            child: _result == null
                ? const Center(child: Text('No result yet'))
                : productsAsync.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Products error: $e')),
                    data: (products) {
                      var items = _parseItems(_result!);
                      if (items.isEmpty) {
                        final meta = (_result!['meta'] as Map?) ?? const {};
                        final ocr = (meta['ocrText'] ?? meta['raw'] ?? '').toString();
                        final heur = _heuristicParseOcr(ocr);
                        if (heur.isNotEmpty) {
                          items = heur;
                        } else {
                          return _NoItemsView(ocrText: ocr, onAddManually: _openManualAddDialog);
                        }
                      }
                      final repo = ref.read(inventoryRepoProvider);
                      final user = ref.read(authStateProvider);
                      final storeId = ref.read(selectedStoreProvider);
                      return _PreviewAndApply(
                        items: items,
                        products: products,
                        movement: _movement,
                        location: _location,
                        onMovementChanged: (v) => setState(() => _movement = v),
                        onLocationChanged: (v) => setState(() => _location = v),
                        repo: repo,
                        userEmail: user?.email,
                        storeId: storeId,
                        // autoApply removed
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}


class _ManualRow {
  final name = TextEditingController();
  final qty = TextEditingController(text: '1');
  final price = TextEditingController();
  final gst = TextEditingController();
}

class _NoItemsView extends StatelessWidget {
  final String ocrText;
  final VoidCallback? onAddManually;
  const _NoItemsView({required this.ocrText, this.onAddManually});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('No line items detected', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('Try these:'),
          const Text('• Ensure the invoice has clear item lines with quantity and price.'),
          const Text('• Try a clearer image or a PDF export from the source.'),
          const SizedBox(height: 8),
          if (onAddManually != null)
            FilledButton.icon(
              onPressed: onAddManually,
              icon: const Icon(Icons.add),
              label: const Text('Add Items Manually'),
            ),
          const SizedBox(height: 12),
          const Text('OCR Text (first 2000 chars):'),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: SelectableText(ocrText.isEmpty ? '(empty)' : ocrText.substring(0, math.min(ocrText.length, 2000))),
            ),
          )
        ]),
      ),
    );
  }
}

class ParsedItem {
  final String itemName;
  final int quantity;
  final double? price;
  final double? gst;
  ParsedItem({required this.itemName, required this.quantity, this.price, this.gst});
}

List<ParsedItem> _parseItems(Map<String, dynamic> result) {
  final list = (result['items'] as List?) ?? const [];
  final out = <ParsedItem>[];
  for (final e in list) {
    if (e is! Map) continue;
    final name = (e['itemName'] ?? e['name'] ?? '').toString();
    final qty = e['quantity'] is num ? (e['quantity'] as num).toInt() : int.tryParse('${e['quantity']}') ?? 0;
    final price = e['price'] is num ? (e['price'] as num).toDouble() : double.tryParse('${e['price']}');
    final gst = e['gst'] is num ? (e['gst'] as num).toDouble() : double.tryParse('${e['gst']}');
    if (name.trim().isEmpty || qty == 0) continue;
    out.add(ParsedItem(itemName: name.trim(), quantity: qty, price: price, gst: gst));
  }
  return out;
}

// Heuristic OCR line parser (fallback when function returns no structured items)
List<ParsedItem> _heuristicParseOcr(String ocr) {
  if (ocr.trim().isEmpty) return const <ParsedItem>[];
  final lines = ocr.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  final items = <ParsedItem>[];
  final skipPrefixes = [
    'invoice #','invoice no','invoice:','date','customer','subtotal','discount','tax total','grand total','total','grandtotal'
  ];
  final priceLinePrefix = RegExp(r'^(price|mrp|rate)[:\s]', caseSensitive: false);
  final lineItemQtyPattern = RegExp(r'^(.*?)(?:\s{2,}|\s+)?x\s*(\d+)\b', caseSensitive: false); // "Name ... x 2"
  final trailingQtyPattern = RegExp(r'^(.*?[a-zA-Z)] )[\s*:-]+(\d+)\s*$'); // requires some letters before qty
  final pricePattern = RegExp(r'price[:\s]*([0-9]+(?:\.[0-9]{1,2})?)', caseSensitive: false);
  final taxPctPattern = RegExp(r'(?:tax|gst)[:\s]*([0-9]{1,2})%');

  ParsedItem? last; // we will mutate last by recreating (immutable struct) when adding price/gst

  void attachMeta(String text) {
    if (last == null) return;
    final pm = pricePattern.firstMatch(text);
    final tm = taxPctPattern.firstMatch(text);
    if (pm == null && tm == null) return;
    final newPrice = pm != null ? double.tryParse(pm.group(1)!) : last!.price;
    final newGst = tm != null ? double.tryParse(tm.group(1)!) : last!.gst;
    // replace last in list
    final idx = items.length - 1;
    items[idx] = ParsedItem(itemName: last!.itemName, quantity: last!.quantity, price: newPrice, gst: newGst);
    last = items[idx];
  }

  for (var i=0;i<lines.length;i++) {
    final raw = lines[i];
    final lower = raw.toLowerCase();
    if (skipPrefixes.any((p) => lower.startsWith(p))) continue;
    if (priceLinePrefix.hasMatch(raw)) { attachMeta(raw); continue; }
    // ignore pure price / discount lines accidentally formatted without prefix
    if (RegExp(r'^(price|disc|discount)\b', caseSensitive: false).hasMatch(lower)) { attachMeta(raw); continue; }
    String name=''; int qty=0; double? price; double? gst;
    var m = lineItemQtyPattern.firstMatch(raw);
    if (m != null) {
      name = m.group(1)!.trim();
      qty = int.tryParse(m.group(2)!) ?? 0;
    } else {
      final t = trailingQtyPattern.firstMatch(raw);
      if (t != null) {
        name = t.group(1)!.trim();
        qty = int.tryParse(t.group(2)!) ?? 0;
      }
    }
    if (name.isEmpty || qty<=0) {
      // maybe a metadata line for previous item
      attachMeta(raw);
      continue;
    }
    // look ahead for immediate price/gst lines (up to next 2 non-empty lines)
    for (var j=i+1; j<lines.length && j<=i+3; j++) {
      final look = lines[j];
      if (lineItemQtyPattern.hasMatch(look) || trailingQtyPattern.hasMatch(look)) break; // next item starts
      final pm = pricePattern.firstMatch(look); if (pm!=null) price = double.tryParse(pm.group(1)!);
      final tm = taxPctPattern.firstMatch(look); if (tm!=null) gst = double.tryParse(tm.group(1)!);
      if (price!=null || gst!=null) continue; // keep scanning small window
    }
    final parsed = ParsedItem(itemName: name, quantity: qty, price: price, gst: gst);
    items.add(parsed);
    last = parsed;
  }
  return items;
}

class _PreviewAndApply extends StatefulWidget {
  final List<ParsedItem> items;
  final List<ProductDoc> products;
  final String movement; // 'Purchase (+)' | 'Sale (-)'
  final String location; // 'Store' | 'Warehouse'
  final ValueChanged<String> onMovementChanged;
  final ValueChanged<String> onLocationChanged;
  final InventoryRepository repo;
  final String? userEmail;
  final String? storeId;
  const _PreviewAndApply({
    required this.items,
    required this.products,
    required this.movement,
    required this.location,
    required this.onMovementChanged,
    required this.onLocationChanged,
    required this.repo,
    required this.userEmail,
    required this.storeId,
  });
  @override
  State<_PreviewAndApply> createState() => _PreviewAndApplyState();
}

class _RowState {
  bool apply = true;
  ProductDoc? match;
  int? overrideQty; // allow user to adjust quantity before applying
  double? confidence; // 0..1 score
  List<ProductDoc>? alternatives; // near matches
  bool locked = false; // prevent auto-match from overwriting manual choice
}

class _Scored {
  final ProductDoc prod;
  final double score;
  _Scored(this.prod, this.score);
}

class _MatchResult {
  final ProductDoc? best;
  final double bestScore;
  final List<ProductDoc> alternatives;
  _MatchResult(this.best, this.bestScore, this.alternatives);
}

class _AutoMatchStats {
  final int total;
  final int matched;
  final int high;
  final int medium;
  final int low;
  final int unmatched;
  final int millis;
  const _AutoMatchStats({
    required this.total,
    required this.matched,
    required this.high,
    required this.medium,
    required this.low,
    required this.unmatched,
    required this.millis,
  });
}

class _PreviewAndApplyState extends State<_PreviewAndApply> {
  late final Map<int, _RowState> _rows;
  // Guard against re-entrant Apply Adjustments
  bool _applyInProgress = false;
  // Navigator used to close progress dialog if widget unmounts mid-operation
  NavigatorState? _progressNavigator;

  void _showProgress() {
    // Use root navigator so it survives route pops of nested dialogs
    _progressNavigator = Navigator.of(context, rootNavigator: true);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    // Safety timeout: auto dismiss after 25s to avoid permanent lock if something hangs
    Future.delayed(const Duration(seconds: 25), () {
      if (_progressNavigator != null) {
        try { _progressNavigator!.maybePop(); } catch (_) {}
        _progressNavigator = null;
      }
    });
  }

  void _hideProgress() {
    if (_progressNavigator != null) {
      try { _progressNavigator!.maybePop(); } catch (_) {}
      _progressNavigator = null;
    }
  }

  @override
  void dispose() {
    // Ensure any lingering progress dialog is removed
    _hideProgress();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _rows = { for (var i=0;i<widget.items.length;i++) i: _RowState() };
    // initial best-effort match by sku/barcode/name
    for (var i=0;i<widget.items.length;i++) {
      _rows[i]!.match = _autoMatch(widget.items[i]);
    }
  }

  ProductDoc? _autoMatch(ParsedItem it) {
    final p = widget.products;
    // exact SKU
    final bySku = p.where((e) => e.sku.toLowerCase() == it.itemName.toLowerCase()).toList();
    if (bySku.isNotEmpty) return bySku.first;
    // exact barcode
    final byBarcode = p.where((e) => e.barcode.isNotEmpty && e.barcode == it.itemName).toList();
    if (byBarcode.isNotEmpty) return byBarcode.first;
    // exact name
    final byName = p.where((e) => e.name.toLowerCase() == it.itemName.toLowerCase()).toList();
    if (byName.isNotEmpty) return byName.first;
    // contains name
    final variantMatch = p.where((e) => e.variants.map((v)=>v.toLowerCase()).contains(it.itemName.toLowerCase())).toList();
    if (variantMatch.isNotEmpty) return variantMatch.first;
    final contains = p.where((e) => e.name.toLowerCase().contains(it.itemName.toLowerCase())).toList();
    if (contains.isNotEmpty) return contains.first;
    // token overlap similarity
    final itemTokens = it.itemName.toLowerCase().split(RegExp(r'[^a-z0-9]+')).where((t)=>t.length>2).toSet();
    if (itemTokens.isEmpty) return null;
    ProductDoc? best; double bestScore = 0;
    for (final prod in p) {
      final prodTokens = ('${prod.name} ${prod.variants.join(' ')}').toLowerCase().split(RegExp(r'[^a-z0-9]+')).where((t)=>t.length>2).toSet();
      if (prodTokens.isEmpty) continue;
      final overlap = prodTokens.intersection(itemTokens).length.toDouble();
      final score = overlap / itemTokens.length;
      if (score >= 0.6 && score > bestScore) { bestScore = score; best = prod; }
    }
    return best;
  }

  void _runAutoMatch() {
    _runAutoMatchAsync();
  }

  bool _autoMatching = false;
  _AutoMatchStats? _lastAutoMatchStats;
  List<String> _matchLog = [];

  Future<void> _runAutoMatchAsync() async {
    if (_autoMatching) return;
    setState(() { _autoMatching = true; _matchLog = []; });
    final sw = Stopwatch()..start();
    final products = widget.products;
    int high=0, med=0, low=0, unmatched=0, matched=0;
    for (var i=0;i<widget.items.length;i++) {
      final st = _rows[i]!;
      if (st.locked) {
        final scoreLocked = st.confidence ?? 0;
        if (st.match == null || scoreLocked < 0.55) {
          unmatched++; _matchLog.add('${widget.items[i].itemName} -> (locked unmatched)');
        } else {
          matched++;
          if (scoreLocked >= 0.85) {
            high++;
          } else if (scoreLocked >= 0.7) {
            med++;
          } else {
            low++;
          }
          _matchLog.add('${widget.items[i].itemName} -> ${st.match!.sku} (${(scoreLocked*100).toStringAsFixed(0)}%) (locked)');
        }
        continue;
      }
      final item = widget.items[i];
      final result = _scoreBest(products, item);
      st.match = result.best;
      st.confidence = result.bestScore == 0 ? null : result.bestScore;
      st.alternatives = result.alternatives;
      final score = result.bestScore;
      if (result.best == null || score < 0.55) {
        unmatched++; _matchLog.add('${item.itemName} -> (unmatched)');
      } else {
        matched++;
        if (score >= 0.85) {
          high++;
        } else if (score >= 0.7) {
          med++;
        } else {
          low++;
        }
        _matchLog.add('${item.itemName} -> ${result.best!.sku} (${(score*100).toStringAsFixed(0)}%)');
      }
    }
    sw.stop();
    setState(() {
      _autoMatching = false;
      _lastAutoMatchStats = _AutoMatchStats(
        total: widget.items.length,
        matched: matched,
        high: high,
        medium: med,
        low: low,
        unmatched: unmatched,
        millis: sw.elapsedMilliseconds,
      );
    });
    if (mounted) {
      final s = _lastAutoMatchStats!;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Auto Match: ${s.matched}/${s.total} matched (H:${s.high} M:${s.medium} L:${s.low} U:${s.unmatched}) in ${s.millis}ms')));
    }
  }

  Future<void> _refineUnmatched() async {
    if (_autoMatching) return;
    setState(() { _autoMatching = true; });
    final products = widget.products;
    for (var i=0;i<widget.items.length;i++) {
      final st = _rows[i]!;
      if (st.locked) {
        continue;
      }
      final needs = st.match == null || (st.confidence ?? 0) < 0.55;
      if (!needs) {
        continue;
      }
      final result = _scoreBest(products, widget.items[i]);
      setState(() {
        st.match = result.best;
        st.confidence = result.bestScore == 0 ? null : result.bestScore;
        st.alternatives = result.alternatives;
      });
      await Future.delayed(const Duration(milliseconds: 10));
    }
    setState(() { _autoMatching = false; });
  }

  Future<void> _createProductFromItem(int index) async {
    final storeId = widget.storeId;
    if (storeId == null || storeId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a store to create products')));
      return;
    }
    final item = widget.items[index];
    final nameCtrl = TextEditingController(text: item.itemName);
    final priceCtrl = TextEditingController(text: (item.price ?? '').toString());
    final gstCtrl = TextEditingController(text: (item.gst ?? '').toString());
    int qty = item.quantity; String loc = widget.location; final inbound = widget.movement.startsWith('Purchase');
    final confirmed = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: Text('Create Product', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w700)),
      content: DefaultTextStyle(style: (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(color: Theme.of(context).colorScheme.onSurface), child: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children:[
        TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
        TextField(controller: priceCtrl, decoration: const InputDecoration(labelText: 'Unit Price'), keyboardType: TextInputType.number),
        TextField(controller: gstCtrl, decoration: const InputDecoration(labelText: 'Tax %'), keyboardType: TextInputType.number),
        const SizedBox(height:12),
        Row(children:[
          const Text('Initial Qty:'), const SizedBox(width:8),
          SizedBox(width:80, child: TextField(controller: TextEditingController(text: '$qty'), onChanged: (v){ final q=int.tryParse(v); if(q!=null) qty=q; }, keyboardType: TextInputType.number)),
          const SizedBox(width:16),
          DropdownButton<String>(value: loc, onChanged: (v){ if(v!=null){ loc=v; } }, items: const [DropdownMenuItem(value:'Store',child:Text('Store')), DropdownMenuItem(value:'Warehouse',child:Text('Warehouse'))]),
        ])
      ]))),
      actions: [
        TextButton(onPressed: ()=> Navigator.pop(context,false), child: const Text('Cancel')),
        FilledButton(onPressed: ()=> Navigator.pop(context,true), child: const Text('Create')),
      ],
    ));
    if (confirmed != true) return;
    final name = nameCtrl.text.trim(); if (name.isEmpty) return;
    final price = double.tryParse(priceCtrl.text.trim()) ?? 0;
    final gst = double.tryParse(gstCtrl.text.trim());
    var sku = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'),'_').replaceAll(RegExp(r'_+'),'_');
    if (sku.length>24) sku = sku.substring(0,24);
    try {
      await widget.repo.addProduct(
        storeId: storeId,
        sku: sku,
        name: name,
        unitPrice: price,
        taxPct: gst,
        storeQty: inbound && loc=='Store' ? qty : 0,
        warehouseQty: inbound && loc=='Warehouse' ? qty : 0,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Created product $sku')));
      await _refineUnmatched();
      setState(() { final st2 = _rows[index]!; st2.locked = true; });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Create failed: $e')));
    }
  }

  _MatchResult _scoreBest(List<ProductDoc> products, ParsedItem item) {
    String normalize(String s) {
      // lower, trim, collapse spaces and strip punctuation to improve equality
      final lower = s.toLowerCase().trim();
      final stripped = lower.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
      return stripped.replaceAll(RegExp(r'\s+'), ' ').trim();
    }
    final normItem = normalize(item.itemName);
    final itemTokens = normItem.split(' ').where((t)=>t.isNotEmpty).toSet();
    ProductDoc? best; double bestScore = 0; final scored = <_Scored>[];
    for (final prod in products) {
      final normProd = normalize(prod.name);
      double score = 0;
      if (normProd == normItem) {
        score = 1.0; // exact normalized match
      } else if (normProd.contains(normItem) || normItem.contains(normProd)) {
        // containment heuristic scaled by relative length ratio
        final ratio = (normProd.length < normItem.length ? normProd.length / normItem.length : normItem.length / normProd.length);
        score = 0.92 * ratio.clamp(0.0, 1.0);
      } else {
        final prodTokens = normProd.split(' ').where((t)=>t.isNotEmpty).toSet();
        if (itemTokens.isNotEmpty && prodTokens.isNotEmpty) {
          final overlap = prodTokens.intersection(itemTokens).length.toDouble();
          final union = (prodTokens.length + itemTokens.length) - overlap;
            final jaccard = union == 0 ? 0 : overlap / union;
          score = (jaccard is double) ? jaccard : jaccard.toDouble(); // name-only Jaccard similarity
        }
      }
      if (score > 0) scored.add(_Scored(prod, score));
      if (score > bestScore) { bestScore = score; best = prod; }
    }
    scored.sort((a,b)=> b.score.compareTo(a.score));
    final near = scored.take(6).map((e)=> e.prod).toList();
    // Lower minimal acceptance to 0.3 (we will still classify below 0.55 as unmatched later)
    if (bestScore < 0.3) {
      return _MatchResult(null, 0, near);
    }
    return _MatchResult(best, bestScore, near);
  }

  Widget _confidenceChip(double score) {
    final scheme = Theme.of(context).colorScheme;
    late final Color c;
    if (score >= 0.85) {
      c = scheme.primary;
    } else if (score >= 0.7) {
      c = scheme.tertiary;
    } else if (score >= 0.55) {
      c = scheme.secondary;
    } else {
      c = Theme.of(context).colorScheme.onSurfaceVariant;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal:6, vertical:2),
      decoration: BoxDecoration(
        // Use withOpacity for compatibility with stable Flutter channels
        color: c.withOpacity(0.12),
        border: Border.all(color: c.withOpacity(0.6)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '${(score*100).toStringAsFixed(0)}%',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _autoMatchStatsChip({bool expanded = false}) {
    final s = _lastAutoMatchStats;
    if (s == null) return const SizedBox.shrink();
    final bg = Theme.of(context).colorScheme.surfaceContainerHighest; // themed chip bg
    final textStyle = Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w500);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal:8, vertical:4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.6)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children:[
        const Icon(Icons.analytics, size:14),
        const SizedBox(width:4),
        if (!expanded) Text('${s.matched}/${s.total}', style: textStyle) else ...[
          Text('Matched ${s.matched}/${s.total}', style: textStyle),
          const SizedBox(width:6),
          Text('H:${s.high}', style: textStyle?.copyWith(color: Theme.of(context).colorScheme.primary)),
          const SizedBox(width:4),
          Text('M:${s.medium}', style: textStyle?.copyWith(color: Theme.of(context).colorScheme.tertiary)),
          const SizedBox(width:4),
          Text('L:${s.low}', style: textStyle?.copyWith(color: Theme.of(context).colorScheme.secondary)),
          const SizedBox(width:4),
          Text('U:${s.unmatched}', style: textStyle?.copyWith(color: Theme.of(context).colorScheme.error)),
          const SizedBox(width:6),
          Text('${s.millis}ms', style: textStyle?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ]),
    );
  }

  int _stockAt(ProductDoc p, String loc) {
    return p.stockAt(loc);
  }

  @override
  Widget build(BuildContext context) {
  final repo = widget.repo;
  final userEmail = widget.userEmail; // tenantId no longer needed after JSON removal
    final messenger = ScaffoldMessenger.of(context);

    final sign = widget.movement.startsWith('Purchase') ? 1 : -1;
    // Aggregate by matched product so adjustment panel can show combined deltas
    final aggregate = <String, int>{}; // sku -> total parsed qty (consider sign)
    for (var i=0;i<widget.items.length;i++) {
      final st = _rows[i]!;
      final it = widget.items[i];
      if (!st.apply || st.match == null) continue;
      final sku = st.match!.sku;
      final q = (st.overrideQty ?? it.quantity) * sign;
      aggregate[sku] = (aggregate[sku] ?? 0) + q;
    }

    final rows = <DataRow>[];
    for (var i=0;i<widget.items.length;i++) {
      final it = widget.items[i];
      final st = _rows[i]!;
      final match = st.match;
      final current = match == null ? 0 : _stockAt(match, widget.location);
      final newStock = current + sign * it.quantity;
      rows.add(
        DataRow(cells: [
          DataCell(Checkbox(
            value: st.apply,
            onChanged: (v) => setState(() => st.apply = v ?? true),
          )),
          DataCell(Text(it.itemName)),
          DataCell(Text('${it.quantity}')),
          DataCell(SizedBox(
            width: 280,
            child: SizedBox(height: 44, child: Row(children:[
              Expanded(
                child: Autocomplete<ProductDoc>(
                  displayStringForOption: (p) => p.name,
                  initialValue: TextEditingValue(text: match?.name ?? ''),
                  optionsBuilder: (t) {
                    final q = t.text.trim().toLowerCase();
                    if (q.isEmpty) {
                      final base = st.alternatives ?? const <ProductDoc>[];
                      return base.take(8);
                    }
                    return widget.products.where((p) => p.name.toLowerCase().contains(q)).take(20);
                  },
                  onSelected: (p) => setState(() { st.match = p; st.locked = true; st.confidence = 1.0; }),
                ),
              ),
              if (st.confidence != null && st.confidence! > 0) Padding(
                padding: const EdgeInsets.symmetric(horizontal:4.0),
                child: _confidenceChip(st.confidence!),
              ),
              if (st.match == null) ...[
                Tooltip(
                  message: 'Create product from line',
                  child: InkWell(
                    onTap: () => _createProductFromItem(i),
                    child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.add_circle_outline, size:16)),
                  ),
                ),
                Tooltip(
                  message: 'Suggest top matches',
                  child: InkWell(
                    onTap: () => setState(() { st.alternatives = widget.products.where((p)=> p.name.toLowerCase().contains(it.itemName.toLowerCase().split(' ').first)).take(8).toList(); }),
                    child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.tips_and_updates, size:16)),
                  ),
                ),
              ] else ...[
                InkWell(
                  onTap: () => setState(() { st.match = null; st.confidence = null; st.locked = false; }),
                  child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.clear, size:16)),
                ),
                InkWell(
                  onTap: () => setState(() { st.locked = !st.locked; }),
                  child: Padding(padding: const EdgeInsets.all(4), child: Icon(st.locked ? Icons.lock : Icons.lock_open, size:16)),
                ),
              ]
            ])),
          )),
          DataCell(Text('$current')),
          DataCell(Row(children: [
            Text('${sign>0?'+':''}${sign*(st.overrideQty ?? it.quantity)}'),
            const SizedBox(width:4),
            InkWell(
              onTap: () async {
                final controller = TextEditingController(text: (st.overrideQty ?? it.quantity).toString());
                final v = await showDialog<int>(context: context, builder: (_) => AlertDialog(
                  title: Text('Override Qty', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w700)),
                  content: DefaultTextStyle(style: (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(color: Theme.of(context).colorScheme.onSurface), child: TextField(controller: controller, keyboardType: TextInputType.number, autofocus: true, decoration: const InputDecoration(labelText: 'Quantity'))),
                  actions: [
                    TextButton(onPressed: ()=> Navigator.pop(context), child: const Text('Cancel')),
                    FilledButton(onPressed: () { final parsed = int.tryParse(controller.text); Navigator.pop(context, parsed); }, child: const Text('Save')),
                  ],
                ));
                if (v != null && v > 0) setState(() { st.overrideQty = v; });
              },
              child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.edit, size:14)),
            )
          ])),
          DataCell(Text('$newStock')),
        ]),
      );
    }

  Future<void> applyAll() async {
      if (_applyInProgress) return; // guard
      _applyInProgress = true;
      final toApply = [
        for (var i=0;i<widget.items.length;i++)
          if (_rows[i]!.apply && _rows[i]!.match != null) (i)
      ];
      if (toApply.isEmpty) {
        messenger.showSnackBar(const SnackBar(content: Text('Nothing to apply')));
        _applyInProgress = false;
        return;
      }
      _showProgress();
      try {
        for (final i in toApply) {
          final it = widget.items[i];
          final p = _rows[i]!.match!;
          await repo.applyStockMovement(
            storeId: widget.storeId!,
            sku: p.sku,
            location: widget.location,
            // Respect override quantity if present
            deltaQty: sign * (_rows[i]!.overrideQty ?? it.quantity),
            type: 'invoice',
            updatedBy: userEmail,
          );
        }
        _hideProgress();
        if (mounted) messenger.showSnackBar(const SnackBar(content: Text('Adjustments applied to inventory')));
      } catch (e) {
        _hideProgress();
        if (mounted) messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
      } finally {
        _applyInProgress = false;
      }
    }


    // JSON apply logic removed

    // Auto-apply once on first build when enabled
    // Auto-apply removed

    // Build adjustment panel summary
    final adjustmentCards = <Widget>[];
    aggregate.forEach((sku, delta) {
      final product = widget.products.firstWhere((p) => p.sku == sku);
      final current = product.stockAt(widget.location);
      final newStock = current + delta;
      adjustmentCards.add(Card(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
              Builder(
                builder: (context) => Text(
                  '${product.sku} · ${product.name}',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height:4),
              Text('Current: $current  Delta: ${delta>0?'+':''}$delta  New: $newStock'),
            ])),
            IconButton(
              tooltip: 'Remove all lines for this product',
              onPressed: () {
                setState(() {
                  for (final entry in _rows.entries) {
                    if (entry.value.match?.sku == sku) entry.value.apply = false;
                  }
                });
              },
              icon: const Icon(Icons.close),
            ),
          ]),
        ),
      ));
    });

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        DropdownButton<String>(
          value: widget.movement,
          items: const [
            DropdownMenuItem(value: 'Purchase (+)', child: Text('Purchase (+)')),
            DropdownMenuItem(value: 'Sale (-)', child: Text('Sale (-)')),
          ],
          onChanged: (v) { if (v!=null) widget.onMovementChanged(v); setState((){}); },
        ),
        const SizedBox(width: 12),
        DropdownButton<String>(
          value: widget.location,
          items: const [
            DropdownMenuItem(value: 'Store', child: Text('Store')),
            DropdownMenuItem(value: 'Warehouse', child: Text('Warehouse')),
          ],
          onChanged: (v) { if (v!=null) widget.onLocationChanged(v); setState((){}); },
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: _autoMatching ? null : _runAutoMatch,
          icon: _autoMatching ? const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)) : const Icon(Icons.auto_fix_high),
          label: Text(_autoMatching ? 'Matching...' : 'Auto Match'),
        ),
        const SizedBox(width:8),
        TextButton(onPressed: _autoMatching ? null : _refineUnmatched, child: const Text('Refine Unmatched')),
        if (_lastAutoMatchStats != null) Padding(
          padding: const EdgeInsets.only(left:8.0),
          child: InkWell(
            onTap: () {
              showDialog(context: context, builder: (_) => AlertDialog(
                title: Text('Auto Match Log', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w700)),
                content: SizedBox(
                  width: 520,
                  height: 400,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
                    if (_lastAutoMatchStats != null) Padding(
                      padding: const EdgeInsets.only(bottom:8.0),
                      child: Text(
                        'Matched ${_lastAutoMatchStats!.matched}/${_lastAutoMatchStats!.total} (High ${_lastAutoMatchStats!.high}, Med ${_lastAutoMatchStats!.medium}, Low ${_lastAutoMatchStats!.low}, Unmatched ${_lastAutoMatchStats!.unmatched}) in ${_lastAutoMatchStats!.millis}ms',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w500),
                      ),
                    ),
                    const Divider(height:1),
                    const SizedBox(height:8),
                    Expanded(child: ListView.builder(
                      itemCount: _matchLog.length,
                      itemBuilder: (c,i) {
                        final line = _matchLog[i];
                        final unmatched = line.endsWith('(unmatched)');
                        return Text(
                          line,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: unmatched ? Theme.of(context).colorScheme.error : null,
                          ),
                        );
                      },
                    )),
                  ]),
                ),
                actions: [TextButton(onPressed: ()=> Navigator.pop(context), child: const Text('Close'))],
              ));
            },
            child: _autoMatchStatsChip(),
          ),
        ),
        const SizedBox(width: 12),
        // JSON editor toggle removed
  FilledButton.icon(onPressed: applyAll, icon: const Icon(Icons.check), label: const Text('Apply Adjustments')),
      ]),
      if (_lastAutoMatchStats != null) Padding(
        padding: const EdgeInsets.only(top:4.0, bottom: 4.0),
        child: Align(
          alignment: Alignment.centerRight,
          child: _autoMatchStatsChip(expanded: true),
        ),
      ),
      // JSON editor removed
      if (aggregate.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text('Adjustment Panel', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        SizedBox(
          height: 140,
          child: ListView(scrollDirection: Axis.horizontal, children: adjustmentCards.isEmpty ? [
            Container(
              width: 260,
              alignment: Alignment.center,
              child: const Text('No adjustments selected'),
            )
          ] : adjustmentCards),
        ),
      ],
      const SizedBox(height: 8),
      Expanded(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTableTheme(
            data: DataTableThemeData(
              dataTextStyle: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface),
              headingTextStyle: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w700),
            ),
            child: DataTable(dataRowMinHeight: 44, dataRowMaxHeight: 56, columns: const [
            DataColumn(label: Text('Apply')),
            DataColumn(label: Text('Parsed Item')),
            DataColumn(label: Text('Qty')),
            DataColumn(label: Text('Match (Name Only)')),
            DataColumn(label: Text('Current')),
            DataColumn(label: Text('Delta')),
            DataColumn(label: Text('New')),
          ], rows: rows),
          ),
        ),
      ),
    ]);
  }
}

// Match & Upsert feature removed
