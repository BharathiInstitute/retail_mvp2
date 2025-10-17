import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth.dart';
import 'Products/inventory.dart' show productsStreamProvider, inventoryRepoProvider; // reuse existing providers
import 'Products/inventory_repository.dart'; // for ProductDoc
import 'package:cloud_firestore/cloud_firestore.dart';

// Local + Firestore-integrated stock movements screen
class StockMovementsScreen extends ConsumerStatefulWidget {
  const StockMovementsScreen({super.key});
  @override
  ConsumerState<StockMovementsScreen> createState() => _StockMovementsScreenState();
}

// Using existing repository & products stream via inventory.dart exports.

class _StockMovementsScreenState extends ConsumerState<StockMovementsScreen> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
  final movementsStream = ref.watch(_movementsProvider);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        Row(children: [
          FilledButton.icon(
            onPressed: _openAddMovement,
            icon: const Icon(Icons.add),
            label: const Text('Add Movement'),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 260,
            child: TextField(
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Filter Movements',
                  isDense: true),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
          const Spacer(),
        ]),
        const SizedBox(height: 12),
        Expanded(
          child: Card(
            child: movementsStream.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (all) {
                final q = _filter.trim().toLowerCase();
                final filtered = q.isEmpty
                    ? all
                    : all.where((m) => m.sku.toLowerCase().contains(q) || m.name.toLowerCase().contains(q) || (m.note?.toLowerCase().contains(q) ?? false) || (m.updatedBy?.toLowerCase().contains(q) ?? false)).toList();
                if (filtered.isEmpty) {
                  return const Center(child: Text('No movements recorded.'));
                }
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Date')),
                      DataColumn(label: Text('Type')),
                      DataColumn(label: Text('SKU')),
                      DataColumn(label: Text('Name')),
                      DataColumn(label: Text('Loc')),
                      DataColumn(label: Text('Δ Qty')),
                      DataColumn(label: Text('Store After')),
                      DataColumn(label: Text('WH After')),
                      DataColumn(label: Text('Total')),
                      DataColumn(label: Text('Updated Time')),
                      DataColumn(label: Text('Updated By')),
                      DataColumn(label: Text('Note')),
                    ],
                    rows: [
                      for (final m in filtered)
                        DataRow(
                          onSelectChanged: (selected) {
                            if (selected == true) {
                              _openEditMovement(m);
                            }
                          },
                          onLongPress: () => _confirmDeleteMovement(m),
                          cells: [
                            DataCell(Text(_fmtDateTime(m.date))),
                            DataCell(Text(m.type)),
                            DataCell(Text(m.sku)),
                            DataCell(Text(m.name)),
                            DataCell(Text(m.location)),
                            DataCell(Text(m.deltaQty.toString())),
                            DataCell(Text(m.storeAfter?.toString() ?? '-')),
                            DataCell(Text(m.warehouseAfter?.toString() ?? '-')),
                            DataCell(Text(m.totalAfter?.toString() ?? '-')),
                            DataCell(Text(m.updatedAt == null ? '-' : _fmtDateTime(m.updatedAt!))),
                            DataCell(Text(m.updatedBy ?? '-')),
                            DataCell(SizedBox(width: 180, child: Text(m.note ?? ''))),
                          ],
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ]),
    );
  }

  Future<void> _openAddMovement() async {
    final result = await showDialog<MovementRecord>(
      context: context,
      builder: (_) => const _MovementDialog(),
    );
    if (result == null) return;
    // Already persisted; Firestore stream will refresh. No local list management now.
  }

  Future<void> _openEditMovement(MovementRecord m) async {
    if (m.id == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot edit: missing document id')));
      }
      return;
    }
    // Show same fields as Add dialog; SKU fixed (read-only).
    final formKey = GlobalKey<FormState>();
    String type = m.type;
    String location = m.location;
    final qtyCtrl = TextEditingController(text: m.deltaQty == 0
        ? '0'
        : (m.type == 'Outbound' ? (m.deltaQty.abs()).toString() : (m.type == 'Inbound' ? (m.deltaQty.abs()).toString() : m.deltaQty.toString())));
    final noteCtrl = TextEditingController(text: m.note ?? '');
    int parseDelta(String type, String text) {
      final raw = int.tryParse(text.trim()) ?? 0;
      if (type == 'Inbound') return raw.abs();
      if (type == 'Outbound') return -raw.abs();
      return raw; // Adjust
    }
    final user = ref.read(authStateProvider);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Edit Movement'),
        content: Form(
          key: formKey,
          child: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SKU: ${m.sku} • ${m.name}', style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: type,
                      items: const ['Inbound', 'Outbound', 'Adjust']
                          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                          .toList(),
                      onChanged: (v) => type = v ?? type,
                      decoration: const InputDecoration(labelText: 'Type'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: location,
                      items: const ['Store', 'Warehouse']
                          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                          .toList(),
                      onChanged: (v) => location = v ?? location,
                      decoration: const InputDecoration(labelText: 'Location'),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                TextFormField(
                  controller: qtyCtrl,
                  decoration: InputDecoration(
                    labelText: type == 'Adjust' ? 'Adjust Qty (can be +/-)' : 'Quantity',
                    helperText: type == 'Outbound' ? 'Will subtract this quantity' : (type == 'Inbound' ? 'Will add this quantity' : 'Positive or negative'),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    final n = int.tryParse(v.trim());
                    if (n == null) return 'Invalid';
                    if (type == 'Outbound' && n <= 0) return 'Enter positive number';
                    if (type != 'Outbound' && type != 'Adjust' && n < 0) return 'Cannot be negative';
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(labelText: 'Note', hintText: 'Optional remarks'),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (!(formKey.currentState?.validate() ?? false)) return;
              Navigator.pop(dialogCtx, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    try {
      final int newDelta = parseDelta(type, qtyCtrl.text);
      await FirebaseFirestore.instance.collection('inventory_movements').doc(m.id).update({
        'type': type,
        'location': location,
        'deltaQty': newDelta,
        'note': noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': user?.email,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Movement updated')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e')));
      }
    }
  }

  Future<void> _confirmDeleteMovement(MovementRecord m) async {
    if (m.id == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot delete: missing document id')));
      }
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete Movement'),
        content: Text('Delete this movement for ${m.sku} • ${m.name}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancel')),
          FilledButton.tonal(onPressed: () => Navigator.pop(dialogCtx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await FirebaseFirestore.instance.collection('inventory_movements').doc(m.id).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Movement deleted')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }
}

class MovementRecord {
  final String? id; // Firestore document id
  final DateTime date;
  final String type;
  final String sku;
  final String name;
  final String location;
  final int deltaQty;
  final int? storeAfter;
  final int? warehouseAfter;
  final int? totalAfter;
  final String? note;
  final DateTime? updatedAt;
  final String? updatedBy;
  MovementRecord({
    this.id,
    required this.date,
    required this.type,
    required this.sku,
    required this.name,
    required this.location,
    required this.deltaQty,
    this.storeAfter,
    this.warehouseAfter,
    this.totalAfter,
    this.note,
    this.updatedAt,
    this.updatedBy,
  });
}

// ---------------- Firestore persistence ----------------
final _movementsProvider = StreamProvider.autoDispose<List<MovementRecord>>((ref) {
  final firestore = FirebaseFirestore.instance; // Could inject if needed
  return firestore
      .collection('inventory_movements')
      .orderBy('createdAt', descending: true)
      .limit(500)
      .snapshots()
      .map((snap) => snap.docs.map((d) => _movementFromDoc(d)).toList());
});

MovementRecord _movementFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
  final m = d.data();
  DateTime? tsLocal(dynamic v) => v is Timestamp ? v.toDate() : null;
  return MovementRecord(
    id: d.id,
    date: tsLocal(m['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    type: (m['type'] ?? '') as String,
    sku: (m['sku'] ?? '') as String,
    name: (m['name'] ?? '') as String,
    location: (m['location'] ?? '') as String,
    deltaQty: (m['deltaQty'] is int) ? m['deltaQty'] as int : (m['deltaQty'] is num ? (m['deltaQty'] as num).toInt() : 0),
    storeAfter: (m['storeAfter'] as num?)?.toInt(),
    warehouseAfter: (m['warehouseAfter'] as num?)?.toInt(),
    totalAfter: (m['totalAfter'] as num?)?.toInt(),
    note: m['note'] as String?,
  updatedAt: tsLocal(m['updatedAt']),
    updatedBy: m['updatedBy'] as String?,
  );
}

class _MovementDialog extends ConsumerStatefulWidget {
  const _MovementDialog();
  @override
  ConsumerState<_MovementDialog> createState() => _MovementDialogState();
}

class _MovementDialogState extends ConsumerState<_MovementDialog> {
  final _formKey = GlobalKey<FormState>();
  final _scanCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '0');
  final _noteCtrl = TextEditingController();
  String _type = 'Inbound';
  String _location = 'Store';
  ProductDoc? _selected;
  String _search = '';
  bool _submitting = false;

  @override
  void dispose() {
    _scanCtrl.dispose();
    _qtyCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
  final productsAsync = ref.watch(productsStreamProvider);
    return AlertDialog(
      title: const Text('Record Stock Movement'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 520,
          child: productsAsync.when(
            data: (products) {
              final matches = _search.isEmpty
                  ? const <ProductDoc>[]
                  : products.where((p) {
                      final q = _search.toLowerCase();
            return p.sku.toLowerCase().contains(q) ||
              p.barcode.toLowerCase().contains(q) ||
              p.name.toLowerCase().contains(q);
                    }).take(8).toList();
              final currentStore = _selected?.stockAt('Store') ?? 0;
              final currentWh = _selected?.stockAt('Warehouse') ?? 0;
              // Removed preview chips; delta & predicted values no longer calculated here.
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: _scanCtrl,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'Scan / Search SKU, Barcode or Name',
                        suffixIcon: _scanCtrl.text.isEmpty
                            ? const Icon(Icons.qr_code_scanner)
                            : IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  setState(() {
                                    _scanCtrl.clear();
                                    _search = '';
                                    _selected = null;
                                  });
                                },
                              ),
                      ),
                      onChanged: (v) => setState(() {
                        _search = v.trim();
                        _selected = null; // reset selection if user types more
                      }),
                      onFieldSubmitted: (v) {
                        // If exactly one match, auto-select
                        if (matches.length == 1) {
                          setState(() => _selected = matches.first);
                        }
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
                      _selectedInfo(currentStore, currentWh),
                      const SizedBox(height: 12),
                    ],
                    Row(children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _type,
                          items: const ['Inbound', 'Outbound', 'Adjust']
                              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                              .toList(),
                          onChanged: (v) => setState(() => _type = v ?? 'Inbound'),
                          decoration: const InputDecoration(labelText: 'Type'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _location,
                          items: const ['Store', 'Warehouse']
                              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                              .toList(),
                          onChanged: (v) => setState(() => _location = v ?? 'Store'),
                          decoration: const InputDecoration(labelText: 'Location'),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _qtyCtrl,
                      decoration: InputDecoration(
                        labelText: _type == 'Adjust' ? 'Adjust Qty (can be +/-)' : 'Quantity',
                        helperText: _type == 'Outbound' ? 'Will subtract this quantity' : (_type == 'Inbound' ? 'Will add this quantity' : 'Positive or negative'),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        final n = int.tryParse(v.trim());
                        if (n == null) return 'Invalid';
                        if (_type == 'Outbound' && n <= 0) return 'Enter positive number';
                        if (_type != 'Outbound' && _type != 'Adjust' && n < 0) return 'Cannot be negative';
                        return null;
                      },
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _noteCtrl,
                      decoration: const InputDecoration(labelText: 'Note', hintText: 'Optional remarks'),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              );
            },
            error: (e, _) => SizedBox(width: 400, child: Text('Error loading products: $e')),
            loading: () => const SizedBox(width: 380, height: 160, child: Center(child: CircularProgressIndicator())),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _submitting ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _submitting ? null : () async {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            if (_selected == null) return;
            final repo = ref.read(inventoryRepoProvider);
            final user = ref.read(authStateProvider);
            final nav = Navigator.of(context);
            final messenger = ScaffoldMessenger.of(context);
            final delta = _parseDelta();
            setState(() => _submitting = true);
            // Capture values needed across async gaps
            final sku = _selected!.sku;
            final name = _selected!.name;
            final noteVal = _noteCtrl.text.trim();
            ProductDoc? after;
            try {
              await repo.applyStockMovement(
                sku: sku,
                location: _location,
                deltaQty: delta,
                type: _type,
                note: noteVal.isEmpty ? null : noteVal,
                updatedBy: user?.email,
              );
              after = await repo.getProduct(sku);
              final firestore = FirebaseFirestore.instance;
              await firestore.collection('inventory_movements').add({
                'createdAt': FieldValue.serverTimestamp(),
                'type': _type,
                'sku': sku,
                'name': name,
                'location': _location,
                'deltaQty': delta,
                'storeAfter': after?.stockAt('Store') ?? 0,
                'warehouseAfter': after?.stockAt('Warehouse') ?? 0,
                'totalAfter': (after?.stockAt('Store') ?? 0) + (after?.stockAt('Warehouse') ?? 0),
                'note': noteVal.isEmpty ? null : noteVal,
                'updatedAt': after?.updatedAt,
                'updatedBy': after?.updatedBy,
              });
            } catch (err) {
              if (!mounted) return; // abort if unmounted
              messenger.showSnackBar(SnackBar(content: Text('Failed: $err')));
              setState(() => _submitting = false);
              return;
            }
            if (!mounted) return;
            final record = MovementRecord(
              date: DateTime.now(),
              type: _type,
              sku: sku,
              name: name,
              location: _location,
              deltaQty: delta,
              storeAfter: after?.stockAt('Store') ?? 0,
              warehouseAfter: after?.stockAt('Warehouse') ?? 0,
              totalAfter: (after?.stockAt('Store') ?? 0) + (after?.stockAt('Warehouse') ?? 0),
              note: noteVal.isEmpty ? null : noteVal,
              updatedAt: after?.updatedAt,
              updatedBy: after?.updatedBy,
            );
            if (mounted && nav.mounted) { nav.pop(record); }
          },
          child: _submitting
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Apply'),
        ),
      ],
    );
  }

  int _parseDelta() {
    final raw = int.tryParse(_qtyCtrl.text.trim()) ?? 0;
    if (_type == 'Inbound') return raw.abs();
    if (_type == 'Outbound') return -raw.abs();
    return raw; // Adjust
  }

  Widget _selectedInfo(int storeQty, int whQty) {
    final total = storeQty + whQty;
    return Material(
      elevation: 1,
      borderRadius: BorderRadius.circular(6),
      color: Colors.blueGrey.shade50,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(
                  _selected == null ? '' : '${_selected!.name}  (SKU: ${_selected!.sku})',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
            const SizedBox(height: 4),
            Wrap(spacing: 12, runSpacing: 4, children: [
              _qtyBadge('Store', storeQty, Icons.store),
              _qtyBadge('Warehouse', whQty, Icons.warehouse),
              _qtyBadge('Total', total, Icons.summarize),
              if (_selected?.updatedAt != null)
                Text('Updated: ${_fmtDateTime(_selected!.updatedAt!)}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
              if ((_selected?.updatedBy ?? '').isNotEmpty)
                Text('By: ${_selected!.updatedBy}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ]),
          ],
        ),
      ),
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

  // Preview row & diff chips removed per user request.
}

String _fmtDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
String _fmtDateTime(DateTime d) => '${_fmtDate(d)} ${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
