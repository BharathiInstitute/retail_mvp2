// ignore_for_file: use_build_context_synchronously
// Rebuilt Inventory module root screen (clean version)

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth.dart';
import 'inventory_repository.dart';
import 'csv_utils.dart';
import 'download_helper_stub.dart' if (dart.library.html) 'download_helper_web.dart';
import 'barcodes_pdf.dart';
import 'import_products_screen.dart' show ImportProductsScreen;
import 'suppliers_screen.dart';
import 'alerts_screen.dart';
import 'audit_screen.dart';
import 'stock_movements_screen.dart';
import 'transfers_screen.dart';
import 'inventory_sheet_page.dart';

// -------------------- Inventory Root Screen (Tabs) --------------------
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {

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
          const StockMovementsScreen(),
          const TransfersScreen(),
          _suppliersTab(),
          _alertsTab(),
          const AuditScreen(),
        ]),
      ),
    );
  }

  // ---------- Tab Builders ----------
  Widget _productsTab() => const _CloudProductsView();

  Widget _suppliersTab() => const SuppliersScreen();
  Widget _alertsTab() => const AlertsScreen();
  // Extracted tabs already wired in TabBarView.
}

// -------------------- Products Providers & Views --------------------
final inventoryRepoProvider = Provider<InventoryRepository>((ref) => InventoryRepository());
final tenantIdProvider = Provider<String?>((ref) { final user = ref.watch(authStateProvider); return user?.uid; });
final productsStreamProvider = StreamProvider.autoDispose<List<ProductDoc>>((ref) { final repo = ref.watch(inventoryRepoProvider); return repo.streamProducts(tenantId: null); });

// (Date formatting helpers for transfers were removed with extraction; not needed here.)

class _CloudProductsView extends ConsumerStatefulWidget {
  const _CloudProductsView();
  @override
  ConsumerState<_CloudProductsView> createState() => _CloudProductsViewState();
}

class _CloudProductsViewState extends ConsumerState<_CloudProductsView> {
  List<ProductDoc> _currentProducts = const [];
  String _search = '';
  _ActiveFilter _activeFilter = _ActiveFilter.all;
  int _gstFilter = -1; // -1 => All, otherwise 0/5/12/18

  List<ProductDoc> _applyFilters(List<ProductDoc> src) {
    Iterable<ProductDoc> it = src;
    final q = _search.trim().toLowerCase();
    if (q.isNotEmpty) {
      it = it.where((p) =>
          p.sku.toLowerCase().contains(q) ||
          p.name.toLowerCase().contains(q) ||
          (p.barcode).toLowerCase().contains(q));
    }
    if (_activeFilter != _ActiveFilter.all) {
      final want = _activeFilter == _ActiveFilter.active;
      it = it.where((p) => p.isActive == want);
    }
    if (_gstFilter != -1) {
      it = it.where((p) => (p.taxPct ?? 0) == _gstFilter);
    }
    return it.toList();
  }

  @override
  Widget build(BuildContext context) {
  final async = ref.watch(productsStreamProvider);
    final user = ref.watch(authStateProvider);
    final bool isSignedIn = user != null;
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Transform.translate(
            offset: const Offset(0, -4),
            child: SizedBox(
              width: 280,
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Search SKU/Name/Barcode',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Transform.translate(
            offset: const Offset(0, -4),
            child: DropdownButton<_ActiveFilter>(
              value: _activeFilter,
              onChanged: (v) => setState(() => _activeFilter = v ?? _ActiveFilter.all),
              items: const [
                DropdownMenuItem(value: _ActiveFilter.all, child: Text('All')),
                DropdownMenuItem(value: _ActiveFilter.active, child: Text('Active')),
                DropdownMenuItem(value: _ActiveFilter.inactive, child: Text('Inactive')),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Transform.translate(
            offset: const Offset(0, -4),
            child: DropdownButton<int>(
              value: _gstFilter,
              onChanged: (v) => setState(() => _gstFilter = v ?? -1),
              items: const [
                DropdownMenuItem(value: -1, child: Text('GST: All')),
                DropdownMenuItem(value: 0, child: Text('GST 0%')),
                DropdownMenuItem(value: 5, child: Text('GST 5%')),
                DropdownMenuItem(value: 12, child: Text('GST 12%')),
                DropdownMenuItem(value: 18, child: Text('GST 18%')),
              ],
            ),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: isSignedIn ? () => _openAddDialog(context) : _requireSignInNotice,
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
            onPressed: isSignedIn
                ? () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ImportProductsScreen()),
                    )
                : _requireSignInNotice,
            icon: const Icon(Icons.file_upload_outlined),
            label: const Text('Import CSV'),
          ),
          const SizedBox(width: 8),
          Builder(builder: (_) {
            final hasData = !async.isLoading && async.hasValue && (async.valueOrNull?.isNotEmpty ?? false);
            return OutlinedButton.icon(
              onPressed: hasData ? () => _exportBarcodesPdf(context) : null,
              icon: const Icon(Icons.qr_code_2),
              label: const Text('Barcodes PDF'),
            );
          }),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const InventorySheetPage()),
            ),
            icon: const Icon(Icons.grid_on_outlined),
            label: const Text('Update Sheet'),
          ),
        ]),
        const SizedBox(height: 12),
        Expanded(
          child: Card(
            child: async.when(
              data: (list) {
                if (list.isEmpty) {
                  return const Center(child: Text('No products found in Inventory.'));
                }
                final filtered = _applyFilters(list);
                _currentProducts = filtered; // cache (export current view)
                if (filtered.isEmpty) {
                  return const Center(child: Text('No products match the filters.'));
                }
                return Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final table = DataTable(
                        columns: const [
                          DataColumn(label: Text('SKU')),
                          DataColumn(label: Text('Name')),
                          DataColumn(label: Text('Barcode')),
                          DataColumn(label: Text('Unit Price')),
                          DataColumn(label: Text('GST %')),
                          DataColumn(label: Text('Store')),
                          DataColumn(label: Text('Warehouse')),
                          DataColumn(label: Text('Total')),
                          DataColumn(label: Text('Active')),
                          DataColumn(label: Text('Actions')),
                        ],
                        rows: [
                          for (final p in filtered)
                            DataRow(cells: [
                              DataCell(Text(p.sku)),
                              DataCell(Text(p.name)),
                              DataCell(Text(p.barcode)),
                              DataCell(Text('₹${p.unitPrice.toStringAsFixed(2)}')),
                              DataCell(Text((p.taxPct ?? 0).toString())),
                              DataCell(Text(p.stockAt('Store').toString())),
                              DataCell(Text(p.stockAt('Warehouse').toString())),
                              DataCell(Text(p.totalStock.toString())),
                              DataCell(Icon(p.isActive ? Icons.check_circle : Icons.cancel, color: p.isActive ? Colors.green : Colors.red)),
                              DataCell(Wrap(spacing: 4, children: [
                                IconButton(
                                  tooltip: 'Edit',
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: isSignedIn ? () => _openEditDialog(context, p) : null,
                                ),
                                IconButton(
                                  tooltip: 'Delete',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: isSignedIn ? () => _confirmDelete(context, p) : null,
                                ),
                              ])),
                            ]),
                        ],
                      );
                      return SingleChildScrollView(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minWidth: constraints.maxWidth),
                            child: table,
                          ),
                        ),
                      );
                    },
                  ),
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
    final user = ref.read(authStateProvider);
    if (user == null) {
      _requireSignInNotice();
      return;
    }
    // Capture messenger early
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<_AddProductResult>(
      context: context,
      useRootNavigator: false, // keep within branch navigator to avoid element reparenting
      builder: (_) => const _AddProductDialog(),
    );
    if (result == null) return;
  final repo = ref.read(inventoryRepoProvider);
  final tenantId = ref.read(tenantIdProvider);
    if (tenantId == null) {
      _requireSignInNotice();
      return;
    }
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
    if (mounted) messenger.showSnackBar(const SnackBar(content: Text('Product added')));
  }

  Future<void> _openEditDialog(BuildContext context, ProductDoc p) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<_EditProductResult>(
      context: context,
      useRootNavigator: false,
      builder: (_) => _EditProductDialog(product: p),
    );
    if (result == null) return;
  final repo = ref.read(inventoryRepoProvider);
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
    if (mounted) messenger.showSnackBar(const SnackBar(content: Text('Product updated')));
  }

  Future<void> _confirmDelete(BuildContext context, ProductDoc p) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
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
  final repo = ref.read(inventoryRepoProvider);
    await repo.deleteProduct(sku: p.sku);
    if (mounted) messenger.showSnackBar(const SnackBar(content: Text('Product deleted')));
  }

  void _exportCsv() {
    final rows = <List<String>>[];
    // Base columns
    final baseHeader = [
      'tenantId','sku','name','barcode','unitPrice','taxPct','mrpPrice','costPrice','variants','description','isActive'
    ];
    // Determine max batches among products
    int maxBatches = 0;
    for (final p in _currentProducts) {
      if (p.batches.length > maxBatches) maxBatches = p.batches.length;
    }
    final batchHeaderSegments = <String>[];
    for (int i=0;i<maxBatches;i++) {
      final n=i+1;
      batchHeaderSegments.addAll(['Batch$n Qty','Batch$n Location','Batch$n Expiry']);
    }
    rows.add([
      ...baseHeader,
      'storeQty','warehouseQty','totalQty',
      ...batchHeaderSegments,
    ]);
    for (final p in _currentProducts) {
      final store = p.stockAt('Store');
      final wh = p.stockAt('Warehouse');
      final row = [
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
        store.toString(),
        wh.toString(),
        p.totalStock.toString(),
      ];
      for (int i=0;i<maxBatches;i++) {
        if (i < p.batches.length) {
          final b = p.batches[i];
          row.add((b.qty ?? 0).toString());
          row.add(b.location ?? '');
          row.add(b.expiry != null ? b.expiry!.toIso8601String().split('T').first : '');
        } else {
          row.addAll(['','','']);
        }
      }
      rows.add(row);
    }
    final csv = CsvUtils.listToCsv(rows);
    final bytes = Uint8List.fromList(csv.codeUnits);
    // Try automatic download on web; fallback to dialog elsewhere or if failed.
    final ctx = context; // capture for dialog
    downloadBytes(bytes, 'products_export.csv', 'text/csv').then((ok) {
      if (ok) return;
      if (!mounted) return; // ensure still mounted before dialog
      showDialog(
        context: ctx,
        builder: (_) => AlertDialog(
          title: const Text('Export CSV'),
          content: SizedBox(width: 700, child: SelectableText(csv)),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
        ),
      );
    });
  }

  Future<void> _exportBarcodesPdf(BuildContext context) async {
    if (_currentProducts.isEmpty) return;
    final products = _currentProducts
        .map((p) => BarcodeProduct(sku: p.sku, realBarcode: p.barcode))
        .toList();
    late final Uint8List bytes;
    try {
      bytes = await buildBarcodesPdf(products);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to build PDF: $e')));
      return;
    }
    final ok = await downloadBytes(bytes, 'product_barcodes.pdf', 'application/pdf');
    if (!mounted) return;
    if (!ok) {
      // Fallback: show simple dialog with note
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Barcodes PDF generated'),
          content: const Text('Automatic download failed. Try again or check browser settings.'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Barcodes PDF downloaded')));
    }
  }

  // Old inline CSV import flow removed; now navigates to ImportProductsScreen

  void _requireSignInNotice() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please sign in to add, edit, delete, or import products.')),
    );
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
                  Expanded(child: TextFormField(controller: _unitPrice, decoration: const InputDecoration(labelText: 'Unit Price'), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
                  const SizedBox(width: 12),
                  Expanded(child: TextFormField(controller: _taxPct, decoration: const InputDecoration(labelText: 'GST %'), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
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

enum _ActiveFilter { all, active, inactive }