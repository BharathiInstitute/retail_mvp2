import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'inventory.dart' show productsStreamProvider, inventoryRepoProvider; // reuse providers
import '../../core/auth/auth.dart';
import 'inventory_repository.dart';

/// Transfers screen with Firestore-backed history (inventory_transfers collection)
class TransfersScreen extends ConsumerStatefulWidget {
  const TransfersScreen({super.key});
  @override
  ConsumerState<TransfersScreen> createState() => _TransfersScreenState();
}

class _TransfersScreenState extends ConsumerState<TransfersScreen> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final transfers = ref.watch(_transfersProvider);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(children: [
            FilledButton.icon(
              onPressed: _openAddTransfer,
              icon: const Icon(Icons.repeat),
              label: const Text('Record Transfer'),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 260,
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Filter Transfers',
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _filter = v),
              ),
            ),
            const Spacer(),
          ]),
          const SizedBox(height: 12),
          Expanded(
            child: transfers.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (all) {
                final q = _filter.trim().toLowerCase();
                final filtered = q.isEmpty
                    ? all
                    : all.where((t) =>
                        t.sku.toLowerCase().contains(q) ||
                        t.name.toLowerCase().contains(q) ||
                        (t.note?.toLowerCase().contains(q) ?? false) ||
                        (t.updatedBy?.toLowerCase().contains(q) ?? false)).toList();
                if (filtered.isEmpty) {
                  return const Center(child: Text('No transfers recorded.'));
                }
                return Card(
                  margin: EdgeInsets.zero,
                  child: LayoutBuilder(builder: (context, constraints) {
                    final minWidth = constraints.maxWidth; // ensure fills width
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minWidth: minWidth),
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Date')),
                            DataColumn(label: Text('SKU')),
                            DataColumn(label: Text('Name')),
                            DataColumn(label: Text('From')),
                            DataColumn(label: Text('To')),
                            DataColumn(label: Text('Qty')),
                            DataColumn(label: Text('Store After')),
                            DataColumn(label: Text('WH After')),
                            DataColumn(label: Text('Total')),
                            DataColumn(label: Text('Updated Time')),
                            DataColumn(label: Text('Updated By')),
                            DataColumn(label: Text('Note')),
                          ],
                          rows: [
                            for (final t in filtered)
                              DataRow(cells: [
                                DataCell(Text(_fmtDateTime(t.date))),
                                DataCell(Text(t.sku)),
                                DataCell(Text(t.name)),
                                DataCell(Text(t.from)),
                                DataCell(Text(t.to)),
                                DataCell(Text(t.qty.toString())),
                                DataCell(Text(t.storeAfter?.toString() ?? '-')),
                                DataCell(Text(t.warehouseAfter?.toString() ?? '-')),
                                DataCell(Text(t.totalAfter?.toString() ?? '-')),
                                DataCell(Text(t.updatedAt == null ? '-' : _fmtDateTime(t.updatedAt!))),
                                DataCell(Text(t.updatedBy ?? '-')),
                                DataCell(SizedBox(width: 200, child: Text(t.note ?? ''))),
                              ]),
                          ],
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openAddTransfer() async {
    await showDialog<TransferRecord>(
      context: context,
      builder: (_) => const _TransferDialog(),
    );
  }
}

class TransferRecord {
  final DateTime date;
  final String sku;
  final String name;
  final String from;
  final String to;
  final int qty;
  final String? note;
  final int? storeAfter;
  final int? warehouseAfter;
  final int? totalAfter;
  final DateTime? updatedAt;
  final String? updatedBy;
  TransferRecord({
    required this.date,
    required this.sku,
    required this.name,
    required this.from,
    required this.to,
    required this.qty,
    this.note,
    this.storeAfter,
    this.warehouseAfter,
    this.totalAfter,
    this.updatedAt,
    this.updatedBy,
  });
}

final _transfersProvider = StreamProvider.autoDispose<List<TransferRecord>>((ref) {
  final firestore = FirebaseFirestore.instance;
  return firestore
      .collection('inventory_transfers')
      .orderBy('createdAt', descending: true)
      .limit(500)
      .snapshots()
      .map((snap) => snap.docs.map((d) => _transferFromDoc(d)).toList());
});

TransferRecord _transferFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
  final m = d.data();
  DateTime? ts(dynamic v) => v is Timestamp ? v.toDate() : null;
  return TransferRecord(
    date: ts(m['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    sku: (m['sku'] ?? '') as String,
    name: (m['name'] ?? '') as String,
    from: (m['from'] ?? '') as String,
    to: (m['to'] ?? '') as String,
    qty: (m['qty'] is int) ? m['qty'] as int : (m['qty'] is num ? (m['qty'] as num).toInt() : 0),
    note: m['note'] as String?,
    storeAfter: (m['storeAfter'] as num?)?.toInt(),
    warehouseAfter: (m['warehouseAfter'] as num?)?.toInt(),
    totalAfter: (m['totalAfter'] as num?)?.toInt(),
    updatedAt: ts(m['updatedAt']),
    updatedBy: m['updatedBy'] as String?,
  );
}

class _TransferDialog extends ConsumerStatefulWidget {
  const _TransferDialog();
  @override
  ConsumerState<_TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends ConsumerState<_TransferDialog> {
  final _formKey = GlobalKey<FormState>();
  final _searchCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '0');
  final _noteCtrl = TextEditingController();
  ProductDoc? _selected;
  String _search = '';
  String _from = 'Store';
  String _to = 'Warehouse';
  bool _submitting = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _qtyCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsStreamProvider);
    return AlertDialog(
      title: const Text('Record Transfer'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 520,
          child: productsAsync.when(
            loading: () => const SizedBox(height: 160, child: Center(child: CircularProgressIndicator())),
            error: (e, _) => SizedBox(width: 400, child: Text('Error loading products: $e')),
            data: (products) {
              final matches = _search.isEmpty
                  ? const <ProductDoc>[]
                  : products.where((p) {
                      final q = _search.toLowerCase();
                      return p.sku.toLowerCase().contains(q) ||
                          p.barcode.toLowerCase().contains(q) ||
                          p.name.toLowerCase().contains(q);
                    }).take(8).toList();
              final storeQty = _selected?.stockAt('Store') ?? 0;
              final whQty = _selected?.stockAt('Warehouse') ?? 0;
              final qty = int.tryParse(_qtyCtrl.text.trim()) ?? 0;
              final newStore = _selected == null ? null : (_from == 'Store' ? storeQty - qty : storeQty + qty);
              final newWh = _selected == null ? null : (_from == 'Warehouse' ? whQty - qty : whQty + qty);
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: _searchCtrl,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'Search / Scan SKU, Barcode or Name',
                        suffixIcon: _searchCtrl.text.isEmpty
                            ? const Icon(Icons.qr_code_scanner)
                            : IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () => setState(() {
                                  _searchCtrl.clear();
                                  _search = '';
                                  _selected = null;
                                }),
                              ),
                      ),
                      onChanged: (v) => setState(() {
                        _search = v.trim();
                        _selected = null;
                      }),
                      onFieldSubmitted: (_) {
                        if (matches.length == 1) setState(() => _selected = matches.first);
                      },
                      validator: (_) => _selected == null ? 'Select a product' : null,
                    ),
                    if (matches.isNotEmpty && _selected == null)
                      Container(
                        margin: const EdgeInsets.only(top: 6, bottom: 8),
                        constraints: const BoxConstraints(maxHeight: 220),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(4),
                          color: Colors.white,
                        ),
                        child: ListView.builder(
                          itemCount: matches.length,
                          itemBuilder: (_, i) {
                            final p = matches[i];
                            return ListTile(
                              dense: true,
                              title: Text('${p.sku} • ${p.name}', maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: p.barcode.isNotEmpty ? Text(p.barcode) : null,
                              onTap: () => setState(() => _selected = p),
                            );
                          },
                        ),
                      ),
                    if (_selected != null) ...[
                      const SizedBox(height: 6),
                      _productSummary(storeQty, whQty),
                      const SizedBox(height: 12),
                    ],
                    Row(children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _from,
                          items: const ['Store', 'Warehouse']
                              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                              .toList(),
                          onChanged: (v) => setState(() => _from = v ?? 'Store'),
                          decoration: const InputDecoration(labelText: 'From'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _to,
                          items: const ['Store', 'Warehouse']
                              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                              .toList(),
                          onChanged: (v) => setState(() => _to = v ?? 'Warehouse'),
                          decoration: const InputDecoration(labelText: 'To'),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _qtyCtrl,
                      decoration: const InputDecoration(labelText: 'Quantity'),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        final n = int.tryParse(v.trim());
                        if (n == null || n <= 0) return 'Positive number';
                        if (_selected != null && _from == 'Store' && n > storeQty) return 'Exceeds Store stock';
                        if (_selected != null && _from == 'Warehouse' && n > whQty) return 'Exceeds Warehouse stock';
                        if (_from == _to) return 'From & To cannot match';
                        return null;
                      },
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _noteCtrl,
                      decoration: const InputDecoration(labelText: 'Note', hintText: 'Optional'),
                      maxLines: 2,
                    ),
                    if (_selected != null && qty > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: _afterPreview(storeQty, whQty, newStore!, newWh!),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _submitting ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _submitting
              ? null
              : () async {
                  if (!(_formKey.currentState?.validate() ?? false)) return;
                  if (_selected == null) return;
                  final repo = ref.read(inventoryRepoProvider);
                  final user = ref.read(authStateProvider);
                  final qty = int.parse(_qtyCtrl.text.trim());
                  setState(() => _submitting = true);
                  try {
                    await repo.applyTransfer(
                      sku: _selected!.sku,
                      from: _from,
                      to: _to,
                      qty: qty,
                      updatedBy: user?.email,
                    );
                    final after = await repo.getProduct(_selected!.sku);
                    final firestore = FirebaseFirestore.instance;
                    final noteVal = _noteCtrl.text.trim();
                    final skuVal = _selected!.sku;
                    final nameVal = _selected!.name;
                    await firestore.collection('inventory_transfers').add({
                      'createdAt': FieldValue.serverTimestamp(),
                      'sku': skuVal,
                      'name': nameVal,
                      'from': _from,
                      'to': _to,
                      'qty': qty,
                      'note': noteVal.isEmpty ? null : noteVal,
                      'storeAfter': after?.stockAt('Store'),
                      'warehouseAfter': after?.stockAt('Warehouse'),
                      'totalAfter': after == null ? null : (after.stockAt('Store') + after.stockAt('Warehouse')),
                      'updatedAt': after?.updatedAt,
                      'updatedBy': after?.updatedBy,
                    });
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
                    }
                    setState(() => _submitting = false);
                    return;
                  }
                  if (!mounted) return;
                  Navigator.pop(context); // stream refresh
                },
          child: _submitting
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Transfer'),
        ),
      ],
    );
  }

  Widget _productSummary(int storeQty, int whQty) {
    return Material(
      elevation: 1,
      borderRadius: BorderRadius.circular(6),
      color: Colors.blueGrey.shade50,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${_selected!.name} (SKU: ${_selected!.sku})', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Wrap(spacing: 8, children: [
              _qtyBadge('Store', storeQty, Icons.store),
              _qtyBadge('Warehouse', whQty, Icons.warehouse),
              _qtyBadge('Total', storeQty + whQty, Icons.summarize),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _afterPreview(int storeBefore, int whBefore, int storeAfter, int whAfter) {
    Color color(int before, int after) => after > before
        ? Colors.green.shade600
        : after < before
            ? Colors.red.shade600
            : Colors.grey.shade600;
    Widget chip(String label, int before, int after) {
      final diff = after - before;
      final diffStr = diff == 0 ? '0' : (diff > 0 ? '+$diff' : diff.toString());
      return Chip(
        label: Text('$label: $before → $after ($diffStr)', style: const TextStyle(color: Colors.white)),
        backgroundColor: color(before, after),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 20),
        Row(children: [
          chip('Store', storeBefore, storeAfter),
          const SizedBox(width: 8),
          chip('Warehouse', whBefore, whAfter),
        ]),
        const SizedBox(height: 4),
        Text('Total After: ${storeAfter + whAfter}', style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _qtyBadge(String label, int value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: Colors.blueGrey.shade600),
        const SizedBox(width: 4),
        Text('$label: $value', style: const TextStyle(fontSize: 12)),
      ]),
    );
  }
}

String _fmtDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
String _fmtDateTime(DateTime d) => '${_fmtDate(d)} ${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
