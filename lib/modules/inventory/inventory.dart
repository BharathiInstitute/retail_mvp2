import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth.dart';
import 'inventory_repository.dart';
import 'csv_utils.dart';
import 'download_helper_stub.dart'
  if (dart.library.html) 'download_helper_web.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});
  @override
  State<InventoryScreen> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryScreen> {
  late List<Supplier> suppliers;
  final List<StockMovement> ledger = [];
  final List<TransferLog> transfers = [];
  final Map<String, AuditItem> audit = {};

  @override
  void initState() {
    super.initState();
    suppliers = [
      Supplier(name: 'FreshFoods Co', contact: '+91 90000 11111'),
      Supplier(name: 'Daily Essentials', contact: '+91 90000 22222'),
      Supplier(name: 'PersonalCare Pvt Ltd', contact: '+91 90000 33333'),
    ];
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const TabBar(isScrollable: true, tabs: [
            Tab(text: 'Products'),
            Tab(text: 'Stock Movements'),
            Tab(text: 'Transfers'),
            Tab(text: 'Suppliers'),
            Tab(text: 'Alerts'),
            Tab(text: 'Audit / Cycle Count'),
          ]),
        ),
        body: TabBarView(children: [
          _productsTab(),
          _movementsTab(),
          _transfersTab(),
          _suppliersTab(),
          _alertsTab(),
          _auditTab(),
        ]),
      ),
    );
  }

  // PRODUCTS TAB
  Widget _productsTab() => const _CloudProductsView();

  // MOVEMENTS TAB (placeholder + local ledger table)
  Widget _movementsTab() {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Stock Movements', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            title: const Text('Adjustments via Firestore coming soon'),
            subtitle: const Text('This tab will post stock in/out and transfers against Firestore data.'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: const [
              Icon(Icons.circle, size: 10, color: Colors.green),
              SizedBox(width: 6),
              Text('POS Sync: Live'),
            ]),
          ),
        ),
        const Divider(),
        Expanded(child: _ledgerTable()),
      ]),
    );
  }

  Widget _ledgerTable() {
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(columns: const [
          DataColumn(label: Text('Date')),
          DataColumn(label: Text('SKU')),
          DataColumn(label: Text('Product')),
          DataColumn(label: Text('Type')),
          DataColumn(label: Text('Location')),
          DataColumn(label: Text('Qty')),
          DataColumn(label: Text('Note')),
        ], rows: [
          for (final m in ledger)
            DataRow(cells: [
              DataCell(Text(_fmtDateTime(m.date))),
              DataCell(Text(m.sku)),
              DataCell(Text(m.name)),
              DataCell(Text(m.type)),
              DataCell(Text(m.location)),
              DataCell(Text(m.qty.toString())),
              DataCell(Text(m.note)),
            ]),
        ]),
      ),
    );
  }

  // TRANSFERS TAB (placeholder + local log table)
  Widget _transfersTab() {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Transfers'),
        const SizedBox(height: 8),
        Card(child: ListTile(title: const Text('Transfers via Firestore coming soon'))),
        const Divider(),
        Expanded(
          child: Card(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(columns: const [
                DataColumn(label: Text('Date')),
                DataColumn(label: Text('SKU')),
                DataColumn(label: Text('Product')),
                DataColumn(label: Text('From')),
                DataColumn(label: Text('To')),
                DataColumn(label: Text('Qty')),
                DataColumn(label: Text('Note')),
              ], rows: [
                for (final t in transfers)
                  DataRow(cells: [
                    DataCell(Text(_fmtDateTime(t.date))),
                    DataCell(Text(t.sku)),
                    DataCell(Text(t.name)),
                    DataCell(Text(t.from)),
                    DataCell(Text(t.to)),
                    DataCell(Text(t.qty.toString())),
                    DataCell(Text(t.note)),
                  ]),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  // SUPPLIERS TAB
  Widget _suppliersTab() {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Card(
        child: ListView.separated(
          itemCount: suppliers.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final s = suppliers[i];
            return ListTile(
              title: Text(s.name),
              subtitle: Text(s.contact),
              trailing: IconButton(icon: const Icon(Icons.call), onPressed: () => _snack('Calling ${s.name}')),
            );
          },
        ),
      ),
    );
  }

  // ALERTS TAB
  Widget _alertsTab() {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: ListView(children: const [
        Text('Alerts'),
        SizedBox(height: 8),
        Card(child: ListTile(title: Text('Low stock & expiry alerts will appear here based on Firestore data.'))),
      ]),
    );
  }

  // AUDIT TAB
  Widget _auditTab() {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Cycle Count / Audit'),
        const SizedBox(height: 8),
        Expanded(
          child: Card(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(columns: const [
                DataColumn(label: Text('SKU')),
                DataColumn(label: Text('Product')),
                DataColumn(label: Text('Expected')),
                DataColumn(label: Text('Counted')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Actions')),
              ], rows: [
                for (final a in audit.values)
                  DataRow(cells: [
                    DataCell(Text(a.product.sku)),
                    DataCell(Text(a.product.name)),
                    DataCell(Text(a.expectedQty.toString())),
                    DataCell(Text(a.countedQty.toString())),
                    DataCell(Text(a.status.name.toUpperCase())),
                    DataCell(Row(children: [
                      IconButton(onPressed: () => setState(() => a.countedQty++), icon: const Icon(Icons.add)),
                      IconButton(onPressed: () => setState(() => a.countedQty = (a.countedQty - 1).clamp(0, 9999)), icon: const Icon(Icons.remove)),
                      IconButton(onPressed: () => setState(() => a.status = AuditStatus.review), icon: const Icon(Icons.flag)),
                      IconButton(onPressed: () => setState(() => a.status = AuditStatus.ok), icon: const Icon(Icons.check)),
                    ])),
                  ]),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          ElevatedButton(onPressed: () => _snack('Audit submitted for review'), child: const Text('Submit Audit')),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () => setState(() {
              for (final a in audit.values) {
                a.countedQty = a.expectedQty;
                a.status = AuditStatus.ok;
              }
            }),
            child: const Text('Mark All OK'),
          ),
        ]),
      ]),
    );
  }
}

// MODELS (local demo for movements/transfers/audit)
class Supplier {
  final String name;
  final String contact;
  Supplier({required this.name, required this.contact});
}

class Product {
  final String sku;
  final String name;
  final double price;
  final int taxPercent;
  final List<String> variants;
  final Supplier supplier;
  final List<Batch> batches;
  Product({required this.sku, required this.name, required this.price, required this.taxPercent, required this.variants, required this.supplier, required this.batches});
  int get totalStock => batches.fold(0, (s, b) => s + b.qty);
  int stockAt(String location) => batches.where((b) => b.location == location).fold(0, (s, b) => s + b.qty);
}

class Batch {
  final String batchNo;
  DateTime expiry;
  int qty;
  String location;
  Batch({required this.batchNo, required this.expiry, required this.qty, required this.location});
}

class StockMovement {
  final DateTime date;
  final String type;
  final String sku;
  final String name;
  final String location;
  final int qty;
  final String note;
  StockMovement({required this.date, required this.type, required this.sku, required this.name, required this.location, required this.qty, required this.note});
}

class TransferLog {
  final DateTime date;
  final String sku;
  final String name;
  final String from;
  final String to;
  final int qty;
  final String note;
  TransferLog({required this.date, required this.sku, required this.name, required this.from, required this.to, required this.qty, required this.note});
}

enum AuditStatus { pending, review, ok }

class AuditItem {
  final Product product;
  int expectedQty;
  int countedQty;
  AuditStatus status;
  AuditItem({required this.product, required this.expectedQty, required this.countedQty, required this.status});
  AuditItem copyWith({Product? product, int? expectedQty, int? countedQty, AuditStatus? status}) =>
      AuditItem(product: product ?? this.product, expectedQty: expectedQty ?? this.expectedQty, countedQty: countedQty ?? this.countedQty, status: status ?? this.status);
}

String _fmtDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String _fmtDateTime(DateTime d) => '${_fmtDate(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

// Firestore-backed products panel providers
final _inventoryRepoProvider = Provider<InventoryRepository>((ref) => InventoryRepository());
final _tenantIdProvider = Provider<String>((ref) {
  final user = ref.watch(authStateProvider);
  return user?.uid ?? 'demo-tenant';
});
final _productsStreamProvider = StreamProvider.autoDispose<List<ProductDoc>>((ref) {
  final repo = ref.watch(_inventoryRepoProvider);
  final tenantId = ref.watch(_tenantIdProvider);
  return repo.streamProducts(tenantId: tenantId);
});

class _CloudProductsView extends ConsumerStatefulWidget {
  const _CloudProductsView();
  @override
  ConsumerState<_CloudProductsView> createState() => _CloudProductsViewState();
}

class _CloudProductsViewState extends ConsumerState<_CloudProductsView> {
  List<ProductDoc> _currentProducts = const [];

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_productsStreamProvider);
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          FilledButton.icon(
            onPressed: () => _openAddDialog(context),
            icon: const Icon(Icons.add),
            label: const Text('Add Product'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => _exportCsv(),
            icon: const Icon(Icons.file_download_outlined),
            label: const Text('Export CSV'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => _importCsv(context),
            icon: const Icon(Icons.file_upload_outlined),
            label: const Text('Import CSV'),
          ),
        ]),
        const SizedBox(height: 12),
        Expanded(
          child: Card(
            child: async.when(
              data: (list) {
                if (list.isEmpty) {
                  return const Center(child: Text('No products found. Sign in and add a product.'));
                }
                _currentProducts = list; // cache for export
                return ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final p = list[i];
                    return ListTile(
                      title: Text('${p.name} • ${p.sku}'),
                      subtitle: Text('Stock: Store ${p.stockAt('Store')} • Warehouse ${p.stockAt('Warehouse')} • Total ${p.totalStock}'),
                      trailing: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        Text('₹${p.unitPrice.toStringAsFixed(2)} • GST ${p.taxPct ?? 0}%'),
                        IconButton(
                          tooltip: 'Edit',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _openEditDialog(context, p),
                        ),
                        IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _confirmDelete(context, p),
                        ),
                      ]),
                    );
                  },
                );
              },
              error: (e, st) => _errorView(context, e),
              loading: () => const Center(child: CircularProgressIndicator()),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _errorView(BuildContext context, Object e) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text('Error: $e'),
        ),
      );

  Future<void> _openAddDialog(BuildContext context) async {
    final result = await showDialog<_AddProductResult>(
      context: context,
      builder: (_) => const _AddProductDialog(),
    );
    if (result == null) return;
    final repo = ref.read(_inventoryRepoProvider);
    final tenantId = ref.read(_tenantIdProvider);
    await repo.addProduct(
      tenantId: tenantId,
      sku: result.sku,
      name: result.name,
      unitPrice: result.unitPrice,
      taxPct: result.taxPct,
      barcode: result.barcode,
      description: result.description,
      variants: result.variants,
      mrpPrice: result.mrpPrice,
      costPrice: result.costPrice,
      isActive: result.isActive,
      storeQty: result.storeQty,
      warehouseQty: result.warehouseQty,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Product added')));
    }
  }

  Future<void> _openEditDialog(BuildContext context, ProductDoc p) async {
    final result = await showDialog<_EditProductResult>(
      context: context,
      builder: (_) => _EditProductDialog(product: p),
    );
    if (result == null) return;
    final repo = ref.read(_inventoryRepoProvider);
    await repo.updateProduct(
      sku: p.sku,
      name: result.name,
      unitPrice: result.unitPrice,
      taxPct: result.taxPct,
      barcode: result.barcode,
      description: result.description,
      variants: result.variants,
      mrpPrice: result.mrpPrice,
      costPrice: result.costPrice,
      isActive: result.isActive,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Product updated')));
    }
  }

  Future<void> _confirmDelete(BuildContext context, ProductDoc p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Product'),
        content: Text('Are you sure you want to delete ${p.name} (${p.sku})?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton.tonal(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    final repo = ref.read(_inventoryRepoProvider);
    await repo.deleteProduct(sku: p.sku);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Product deleted')));
    }
  }

  void _exportCsv() {
    final rows = <List<String>>[];
    rows.add(CsvUtils.headers);
    for (final p in _currentProducts) {
      rows.add([
        p.tenantId,
        p.sku,
        p.name,
        p.barcode,
        p.unitPrice.toString(),
        (p.taxPct ?? '').toString(),
        (p.mrpPrice ?? '').toString(),
        (p.costPrice ?? '').toString(),
        p.variants.join(';'),
        p.description ?? '',
        p.isActive ? 'true' : 'false',
        p.stockAt('Store').toString(),
        p.stockAt('Warehouse').toString(),
      ]);
    }
    final csv = CsvUtils.listToCsv(rows);
    final bytes = Uint8List.fromList(csv.codeUnits);
    // Try automatic download on web; fallback to dialog elsewhere or if failed.
    downloadBytes(bytes, 'products_export.csv', 'text/csv').then((ok) {
      if (ok) return;
      if (!context.mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Export CSV'),
          content: SizedBox(width: 700, child: SelectableText(csv)),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
        ),
      );
    });
  }

  Future<void> _importCsv(BuildContext context) async {
    final textCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Import CSV'),
        content: Form(
          key: formKey,
          child: SizedBox(
            width: 700,
            child: TextFormField(
              controller: textCtrl,
              maxLines: 16,
              decoration: const InputDecoration(hintText: 'Paste CSV here with headers'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'CSV required' : null,
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Import')),
        ],
      ),
    );
    if (result != true) return;
    if (!(formKey.currentState?.validate() ?? false)) return;

    final csv = textCtrl.text;
    late final List<List<String>> table;
    try {
      table = CsvUtils.csvToList(csv);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('CSV parse failed: $e')));
      return;
    }
    if (table.isEmpty) return;

    // Validate headers
    final header = table.first.map((s) => s.trim()).toList();
    final expected = CsvUtils.headers;
    final okHeaders = header.length == expected.length &&
        List.generate(expected.length, (i) => header[i] == expected[i]).every((x) => x);
    if (!okHeaders) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid headers. Please use the template from Export CSV.')));
      return;
    }

    // Prepare batch import (simple loop calling addProduct)
    final repo = ref.read(_inventoryRepoProvider);
    final tenantId = ref.read(_tenantIdProvider);
    int imported = 0;
    final rows = table.skip(1).where((r) => r.isNotEmpty && r.any((c) => c.trim().isNotEmpty));
    for (final r in rows) {
      try {
        final sku = r[1].trim();
        final name = r[2].trim();
        if (sku.isEmpty || name.isEmpty) continue;
        await repo.addProduct(
          tenantId: tenantId,
          sku: sku,
          name: name,
          unitPrice: double.tryParse(r[4].trim()) ?? 0,
          taxPct: r[5].trim().isEmpty ? null : num.tryParse(r[5].trim()),
          barcode: r[3].trim().isEmpty ? null : r[3].trim(),
          description: r[9].trim().isEmpty ? null : r[9].trim(),
          variants: r[8].split(';').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
          mrpPrice: r[6].trim().isEmpty ? null : double.tryParse(r[6].trim()),
          costPrice: r[7].trim().isEmpty ? null : double.tryParse(r[7].trim()),
          isActive: (r[10].trim().toLowerCase() != 'false'),
          storeQty: int.tryParse(r[11].trim()) ?? 0,
          warehouseQty: int.tryParse(r[12].trim()) ?? 0,
        );
        imported++;
      } catch (e) {
        // Continue with next row on error
      }
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Imported $imported products')));
    }
  }
}

// ----- Dialogs for Add / Edit -----

class _AddProductResult {
  final String sku;
  final String name;
  final double unitPrice;
  final num? taxPct;
  final String? barcode;
  final String? description;
  final List<String> variants;
  final double? mrpPrice;
  final double? costPrice;
  final bool isActive;
  final int storeQty;
  final int warehouseQty;
  _AddProductResult({
    required this.sku,
    required this.name,
    required this.unitPrice,
    this.taxPct,
    this.barcode,
    this.description,
    required this.variants,
    this.mrpPrice,
    this.costPrice,
    required this.isActive,
    required this.storeQty,
    required this.warehouseQty,
  });
}

class _AddProductDialog extends StatefulWidget {
  const _AddProductDialog();
  @override
  State<_AddProductDialog> createState() => _AddProductDialogState();
}

class _AddProductDialogState extends State<_AddProductDialog> {
  final _formKey = GlobalKey<FormState>();
  final _sku = TextEditingController();
  final _name = TextEditingController();
  final _unitPrice = TextEditingController(text: '0');
  final _taxPct = TextEditingController();
  final _barcode = TextEditingController();
  final _description = TextEditingController();
  final _variants = TextEditingController();
  final _mrpPrice = TextEditingController();
  final _costPrice = TextEditingController();
  final _storeQty = TextEditingController(text: '0');
  final _warehouseQty = TextEditingController(text: '0');
  bool _isActive = true;

  @override
  void dispose() {
    _sku.dispose();
    _name.dispose();
    _unitPrice.dispose();
    _taxPct.dispose();
    _barcode.dispose();
    _description.dispose();
    _variants.dispose();
    _mrpPrice.dispose();
    _costPrice.dispose();
    _storeQty.dispose();
    _warehouseQty.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Product'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(controller: _sku, decoration: const InputDecoration(labelText: 'SKU'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
                TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Name'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
                TextFormField(controller: _barcode, decoration: const InputDecoration(labelText: 'Barcode')),
                Row(children: [
                  Expanded(child: TextFormField(controller: _unitPrice, decoration: const InputDecoration(labelText: 'Unit Price'), keyboardType: TextInputType.numberWithOptions(decimal: true))),
                  const SizedBox(width: 12),
                  Expanded(child: TextFormField(controller: _taxPct, decoration: const InputDecoration(labelText: 'GST %'), keyboardType: TextInputType.numberWithOptions(decimal: true))),
                ]),
                Row(children: [
                  Expanded(child: TextFormField(controller: _mrpPrice, decoration: const InputDecoration(labelText: 'MRP'), keyboardType: TextInputType.numberWithOptions(decimal: true))),
                  const SizedBox(width: 12),
                  Expanded(child: TextFormField(controller: _costPrice, decoration: const InputDecoration(labelText: 'Cost Price'), keyboardType: TextInputType.numberWithOptions(decimal: true))),
                ]),
                TextFormField(controller: _variants, decoration: const InputDecoration(labelText: 'Variants (separate with ;)')),
                TextFormField(controller: _description, decoration: const InputDecoration(labelText: 'Description')),
                const SizedBox(height: 8),
                CheckboxListTile(value: _isActive, onChanged: (v) => setState(() => _isActive = v ?? true), title: const Text('Active')),
                Row(children: [
                  Expanded(child: TextFormField(controller: _storeQty, decoration: const InputDecoration(labelText: 'Initial Store Qty'), keyboardType: TextInputType.number)),
                  const SizedBox(width: 12),
                  Expanded(child: TextFormField(controller: _warehouseQty, decoration: const InputDecoration(labelText: 'Initial Warehouse Qty'), keyboardType: TextInputType.number)),
                ]),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            final result = _AddProductResult(
              sku: _sku.text.trim(),
              name: _name.text.trim(),
              unitPrice: double.tryParse(_unitPrice.text.trim()) ?? 0,
              taxPct: _taxPct.text.trim().isEmpty ? null : num.tryParse(_taxPct.text.trim()),
              barcode: _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
              description: _description.text.trim().isEmpty ? null : _description.text.trim(),
              variants: _variants.text.split(';').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
              mrpPrice: _mrpPrice.text.trim().isEmpty ? null : double.tryParse(_mrpPrice.text.trim()),
              costPrice: _costPrice.text.trim().isEmpty ? null : double.tryParse(_costPrice.text.trim()),
              isActive: _isActive,
              storeQty: int.tryParse(_storeQty.text.trim()) ?? 0,
              warehouseQty: int.tryParse(_warehouseQty.text.trim()) ?? 0,
            );
            Navigator.pop(context, result);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _EditProductResult {
  final String? name;
  final double? unitPrice;
  final num? taxPct;
  final String? barcode;
  final String? description;
  final List<String>? variants;
  final double? mrpPrice;
  final double? costPrice;
  final bool? isActive;
  _EditProductResult({
    this.name,
    this.unitPrice,
    this.taxPct,
    this.barcode,
    this.description,
    this.variants,
    this.mrpPrice,
    this.costPrice,
    this.isActive,
  });
}

class _EditProductDialog extends StatefulWidget {
  final ProductDoc product;
  const _EditProductDialog({required this.product});
  @override
  State<_EditProductDialog> createState() => _EditProductDialogState();
}

class _EditProductDialogState extends State<_EditProductDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _unitPrice;
  late final TextEditingController _taxPct;
  late final TextEditingController _barcode;
  late final TextEditingController _description;
  late final TextEditingController _variants;
  late final TextEditingController _mrpPrice;
  late final TextEditingController _costPrice;
  late bool _isActive;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _name = TextEditingController(text: p.name);
    _unitPrice = TextEditingController(text: p.unitPrice.toString());
    _taxPct = TextEditingController(text: p.taxPct?.toString() ?? '');
    _barcode = TextEditingController(text: p.barcode);
    _description = TextEditingController(text: p.description ?? '');
    _variants = TextEditingController(text: p.variants.join(';'));
    _mrpPrice = TextEditingController(text: p.mrpPrice?.toString() ?? '');
    _costPrice = TextEditingController(text: p.costPrice?.toString() ?? '');
    _isActive = p.isActive;
  }

  @override
  void dispose() {
    _name.dispose();
    _unitPrice.dispose();
    _taxPct.dispose();
    _barcode.dispose();
    _description.dispose();
    _variants.dispose();
    _mrpPrice.dispose();
    _costPrice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit ${widget.product.sku}'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
                TextFormField(controller: _barcode, decoration: const InputDecoration(labelText: 'Barcode')),
                Row(children: [
                  Expanded(child: TextFormField(controller: _unitPrice, decoration: const InputDecoration(labelText: 'Unit Price'), keyboardType: TextInputType.numberWithOptions(decimal: true))),
                  const SizedBox(width: 12),
                  Expanded(child: TextFormField(controller: _taxPct, decoration: const InputDecoration(labelText: 'GST %'), keyboardType: TextInputType.numberWithOptions(decimal: true))),
                ]),
                Row(children: [
                  Expanded(child: TextFormField(controller: _mrpPrice, decoration: const InputDecoration(labelText: 'MRP'), keyboardType: TextInputType.numberWithOptions(decimal: true))),
                  const SizedBox(width: 12),
                  Expanded(child: TextFormField(controller: _costPrice, decoration: const InputDecoration(labelText: 'Cost Price'), keyboardType: TextInputType.numberWithOptions(decimal: true))),
                ]),
                TextFormField(controller: _variants, decoration: const InputDecoration(labelText: 'Variants (separate with ;)')),
                TextFormField(controller: _description, decoration: const InputDecoration(labelText: 'Description')),
                const SizedBox(height: 8),
                CheckboxListTile(value: _isActive, onChanged: (v) => setState(() => _isActive = v ?? true), title: const Text('Active')),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final result = _EditProductResult(
              name: _name.text.trim().isEmpty ? null : _name.text.trim(),
              unitPrice: _unitPrice.text.trim().isEmpty ? null : double.tryParse(_unitPrice.text.trim()),
              taxPct: _taxPct.text.trim().isEmpty ? null : num.tryParse(_taxPct.text.trim()),
              barcode: _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
              description: _description.text.trim().isEmpty ? null : _description.text.trim(),
              variants: _variants.text.trim().isEmpty ? null : _variants.text.split(';').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
              mrpPrice: _mrpPrice.text.trim().isEmpty ? null : double.tryParse(_mrpPrice.text.trim()),
              costPrice: _costPrice.text.trim().isEmpty ? null : double.tryParse(_costPrice.text.trim()),
              isActive: _isActive,
            );
            Navigator.pop(context, result);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}