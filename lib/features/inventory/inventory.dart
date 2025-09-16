import 'package:flutter/material.dart';

// Consolidated Inventory module in a single file.
// Contains InventoryScreen, models, and helpers.

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});
  @override
  State<InventoryScreen> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryScreen> {
  late List<Supplier> suppliers;
  late List<Product> products;
  final List<StockMovement> ledger = [];
  final List<TransferLog> transfers = [];

  Product? selectedProduct;
  String searchQuery = '';
  final Map<String, AuditItem> audit = {};

  @override
  void initState() {
    super.initState();
    suppliers = [
      Supplier(name: 'FreshFoods Co', contact: '+91 90000 11111'),
      Supplier(name: 'Daily Essentials', contact: '+91 90000 22222'),
      Supplier(name: 'PersonalCare Pvt Ltd', contact: '+91 90000 33333'),
    ];

    products = [
      Product(
        sku: 'SKU1001',
        name: 'Milk 1L',
        price: 55.0,
        taxPercent: 5,
        variants: const ['Toned', 'Full Cream'],
        supplier: suppliers[0],
        batches: [
          Batch(batchNo: 'B1', expiry: DateTime.now().add(const Duration(days: 10)), qty: 30, location: 'Store'),
          Batch(batchNo: 'B2', expiry: DateTime.now().add(const Duration(days: 40)), qty: 20, location: 'Warehouse'),
        ],
      ),
      Product(
        sku: 'SKU2001',
        name: 'Shampoo 200ml',
        price: 120.0,
        taxPercent: 18,
        variants: const ['Herbal', 'Anti-dandruff'],
        supplier: suppliers[2],
        batches: [
          Batch(batchNo: 'S1', expiry: DateTime.now().add(const Duration(days: 365)), qty: 15, location: 'Store'),
          Batch(batchNo: 'S2', expiry: DateTime.now().add(const Duration(days: 300)), qty: 25, location: 'Warehouse'),
        ],
      ),
      Product(
        sku: 'SKU3001',
        name: 'Biscuits 100g',
        price: 20.0,
        taxPercent: 12,
        variants: const ['Chocolate', 'Butter'],
        supplier: suppliers[1],
        batches: [
          Batch(batchNo: 'C1', expiry: DateTime.now().add(const Duration(days: 20)), qty: 80, location: 'Store'),
          Batch(batchNo: 'C2', expiry: DateTime.now().subtract(const Duration(days: 5)), qty: 10, location: 'Store'),
        ],
      ),
    ];

    for (final p in products) {
      audit[p.sku] = AuditItem(product: p, expectedQty: p.totalStock, countedQty: p.totalStock, status: AuditStatus.pending);
    }
  }

  // Utilities
  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  List<Product> get filteredProducts {
    final q = searchQuery.trim().toLowerCase();
    if (q.isEmpty) return products;
    return products.where((p) => p.sku.toLowerCase().contains(q) || p.name.toLowerCase().contains(q)).toList();
  }

  // CRUD
  void createOrEditProduct({Product? existing}) async {
    final result = await showDialog<Product>(
      context: context,
      builder: (_) => _ProductDialog(suppliers: suppliers, existing: existing),
    );
    if (result != null) {
      setState(() {
        if (existing == null) {
          products.add(result);
          audit[result.sku] = AuditItem(product: result, expectedQty: result.totalStock, countedQty: result.totalStock, status: AuditStatus.pending);
        } else {
          final idx = products.indexWhere((p) => p.sku == existing.sku);
          if (idx >= 0) products[idx] = result;
          audit[result.sku] = AuditItem(product: result, expectedQty: result.totalStock, countedQty: result.totalStock, status: audit[existing.sku]?.status ?? AuditStatus.pending);
          if (existing.sku != result.sku) audit.remove(existing.sku);
        }
      });
      _snack(existing == null ? 'Product created' : 'Product updated');
    }
  }

  void deleteProduct(Product p) {
    setState(() {
      products.removeWhere((e) => e.sku == p.sku);
      audit.remove(p.sku);
    });
    _snack('Product deleted');
  }

  // Adjustments
  void adjustStock({required Product product, required String location, required bool isIn, required int qty, required String note}) {
    if (qty <= 0) return _snack('Quantity must be > 0');
    setState(() {
      if (isIn) {
        product.batches.add(Batch(batchNo: 'ADJ-${DateTime.now().millisecondsSinceEpoch % 10000}', expiry: DateTime.now().add(const Duration(days: 365)), qty: qty, location: location));
        ledger.add(StockMovement.now(type: 'adjust-in', sku: product.sku, name: product.name, qty: qty, location: location, note: note));
      } else {
        int remaining = qty;
        for (final b in product.batches.where((b) => b.location == location).toList()) {
          if (remaining <= 0) break;
          final take = remaining.clamp(0, b.qty);
          b.qty -= take;
          remaining -= take;
        }
        product.batches.removeWhere((b) => b.qty <= 0);
        ledger.add(StockMovement.now(type: 'adjust-out', sku: product.sku, name: product.name, qty: -qty, location: location, note: note));
      }
      audit[product.sku] = audit[product.sku]!.copyWith(expectedQty: product.totalStock, countedQty: product.totalStock);
    });
  }

  // Transfers
  void transferStock({required Product product, required String from, required String to, required int qty, required String note}) {
    if (qty <= 0) return _snack('Quantity must be > 0');
    if (from == to) return _snack('From/To cannot be same');
    setState(() {
      int remaining = qty;
      for (final b in product.batches.where((b) => b.location == from).toList()) {
        if (remaining <= 0) break;
        final take = remaining.clamp(0, b.qty);
        b.qty -= take;
        remaining -= take;
      }
      product.batches.removeWhere((b) => b.qty <= 0);
      product.batches.add(Batch(batchNo: 'TRF-${DateTime.now().millisecondsSinceEpoch % 10000}', expiry: DateTime.now().add(const Duration(days: 365)), qty: qty, location: to));

      transfers.add(TransferLog.now(sku: product.sku, name: product.name, from: from, to: to, qty: qty, note: note));
      ledger.add(StockMovement.now(type: 'transfer-out', sku: product.sku, name: product.name, qty: -qty, location: from, note: note));
      ledger.add(StockMovement.now(type: 'transfer-in', sku: product.sku, name: product.name, qty: qty, location: to, note: note));
      audit[product.sku] = audit[product.sku]!.copyWith(expectedQty: product.totalStock, countedQty: product.totalStock);
    });
  }

  // POS sale simulation
  void simulatePosSale({required Product product, int qty = 1}) {
    if (qty <= 0) return;
    if (product.stockAt('Store') < qty) return _snack('Insufficient Store stock');
    setState(() {
      int remaining = qty;
      for (final b in product.batches.where((b) => b.location == 'Store').toList()) {
        if (remaining <= 0) break;
        final take = remaining.clamp(0, b.qty);
        b.qty -= take;
        remaining -= take;
      }
      product.batches.removeWhere((b) => b.qty <= 0);
      ledger.add(StockMovement.now(type: 'sale', sku: product.sku, name: product.name, qty: -qty, location: 'Store', note: 'POS sale (demo)'));
      audit[product.sku] = audit[product.sku]!.copyWith(expectedQty: product.totalStock, countedQty: product.totalStock);
    });
  }

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
  Widget _productsTab() {
    final isWide = MediaQuery.of(context).size.width > 1100;
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: isWide ? _productsWide() : _productsNarrow(),
    );
  }

  Widget _productsToolbar() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ElevatedButton.icon(onPressed: () => createOrEditProduct(), icon: const Icon(Icons.add), label: const Text('Add Product')),
        OutlinedButton.icon(onPressed: () => _snack('Import started (demo)'), icon: const Icon(Icons.file_upload), label: const Text('Import CSV')),
        OutlinedButton.icon(onPressed: () => _snack('Exported (demo)'), icon: const Icon(Icons.file_download), label: const Text('Export CSV')),
        const SizedBox(width: 12),
        SizedBox(
          width: 300,
          child: TextField(
            decoration: const InputDecoration(labelText: 'Search products', prefixIcon: Icon(Icons.search)),
            onChanged: (v) => setState(() => searchQuery = v),
          ),
        ),
      ],
    );
  }

  Widget _productsWide() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _productsToolbar(),
              const SizedBox(height: 8),
              Expanded(child: _productListView()),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: _productDetailsPanel()),
      ],
    );
  }

  Widget _productsNarrow() {
    return ListView(
      children: [
        _productsToolbar(),
        const SizedBox(height: 8),
        _productListView(height: 320),
        const SizedBox(height: 8),
        _productDetailsPanel(),
      ],
    );
  }

  Widget _productListView({double? height}) {
    final list = filteredProducts;
    final content = Card(
      child: ListView.separated(
        itemCount: list.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final p = list[i];
          return ListTile(
            onTap: () => setState(() => selectedProduct = p),
            title: Text('${p.name} • ${p.sku}'),
            subtitle: Text('Stock: Store ${p.stockAt('Store')} • Warehouse ${p.stockAt('Warehouse')} • Total ${p.totalStock}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(icon: const Icon(Icons.edit), onPressed: () => createOrEditProduct(existing: p)),
                IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => deleteProduct(p)),
              ],
            ),
          );
        },
      ),
    );
    return height != null ? SizedBox(height: height, child: content) : Expanded(child: content);
  }

  Widget _productDetailsPanel() {
    final p = selectedProduct ?? (filteredProducts.isNotEmpty ? filteredProducts.first : null);
    if (p == null) return const Card(child: SizedBox(height: 240, child: Center(child: Text('Select a product'))));
    final today = DateTime.now();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            children: [
              Expanded(child: Text('${p.name} • ${p.sku}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
              IconButton(icon: const Icon(Icons.edit), onPressed: () => createOrEditProduct(existing: p)),
            ],
          ),
          Text('Supplier: ${p.supplier.name} (${p.supplier.contact})'),
          Text('Price: ₹${p.price.toStringAsFixed(2)} • GST ${p.taxPercent}%'),
          Wrap(spacing: 6, children: p.variants.map((v) => Chip(label: Text(v))).toList()),
          const Divider(),
          const Text('Batches & Expiry'),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(columns: const [
              DataColumn(label: Text('Batch')),
              DataColumn(label: Text('Location')),
              DataColumn(label: Text('Qty')),
              DataColumn(label: Text('Expiry')),
              DataColumn(label: Text('Alert')),
            ], rows: [
              for (final b in p.batches)
                DataRow(cells: [
                  DataCell(Text(b.batchNo)),
                  DataCell(Text(b.location)),
                  DataCell(Text(b.qty.toString())),
                  DataCell(Text(_fmtDate(b.expiry))),
                  DataCell(_expiryChip(b.expiry, today)),
                ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _expiryChip(DateTime expiry, DateTime today) {
    final diff = expiry.difference(today).inDays;
    if (diff < 0) return const Chip(label: Text('Expired'), backgroundColor: Colors.redAccent);
    if (diff <= 30) return const Chip(label: Text('Expiring soon'), backgroundColor: Colors.orangeAccent);
    return const Chip(label: Text('OK'), backgroundColor: Colors.greenAccent);
  }

  // MOVEMENTS TAB
  Widget _movementsTab() {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Stock Adjustments', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _AdjustmentForm(
          products: products,
          onApply: (p, location, isIn, qty, note) => adjustStock(product: p, location: location, isIn: isIn, qty: qty, note: note),
        ),
        const SizedBox(height: 12),
        Row(children: [
          const Text('Simulate POS Sale (Store):'),
          const SizedBox(width: 8),
          _PosSaleSimulator(products: products, onSale: (p, qty) => simulatePosSale(product: p, qty: qty)),
          const Spacer(),
          _liveIndicator(),
        ]),
        const Divider(),
        Expanded(child: _ledgerTable()),
      ]),
    );
  }

  Widget _liveIndicator() {
    return Row(children: const [
      Icon(Icons.circle, size: 10, color: Colors.green),
      SizedBox(width: 6),
      Text('POS Sync: Live'),
    ]);
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
              DataCell(Text(_fmtDateTime(m.date)) ),
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

  // TRANSFERS TAB
  Widget _transfersTab() {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Transfer Stock'),
        const SizedBox(height: 8),
        _TransferForm(products: products, onTransfer: (p, from, to, qty, note) => transferStock(product: p, from: from, to: to, qty: qty, note: note)),
        const Divider(),
        Expanded(child: _transfersTable()),
      ]),
    );
  }

  Widget _transfersTable() {
    return Card(
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
    );
  }

  // SUPPLIERS TAB
  Widget _suppliersTab() {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: const [
          Icon(Icons.factory, size: 18),
          SizedBox(width: 6),
          Text('Suppliers'),
        ]),
        const SizedBox(height: 8),
        Card(
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: suppliers.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final s = suppliers[i];
              return ListTile(
                title: Text(s.name),
                subtitle: Text(s.contact),
                trailing: const Icon(Icons.chevron_right),
              );
            },
          ),
        ),
      ]),
    );
  }

  // ALERTS TAB
  Widget _alertsTab() {
    final today = DateTime.now();
    final alerts = <LowStockAlert>[];
    for (final p in products) {
      if (p.stockAt('Store') < 5) {
        alerts.add(LowStockAlert(sku: p.sku, name: p.name, location: 'Store', qty: p.stockAt('Store')));
      }
      for (final b in p.batches) {
        final days = b.expiry.difference(today).inDays;
        if (days < 0) {
          alerts.add(LowStockAlert(sku: p.sku, name: '${p.name} (Expired ${b.batchNo})', location: b.location, qty: b.qty));
        } else if (days <= 15) {
          alerts.add(LowStockAlert(sku: p.sku, name: '${p.name} (Expiring ${b.batchNo})', location: b.location, qty: b.qty));
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Card(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(columns: const [
            DataColumn(label: Text('SKU')),
            DataColumn(label: Text('Item')),
            DataColumn(label: Text('Location')),
            DataColumn(label: Text('Qty')),
          ], rows: [
            for (final a in alerts)
              DataRow(cells: [
                DataCell(Text(a.sku)),
                DataCell(Text(a.name)),
                DataCell(Text(a.location)),
                DataCell(Text(a.qty.toString())),
              ]),
          ]),
        ),
      ),
    );
  }

  // AUDIT TAB
  Widget _auditTab() {
    final items = audit.values.toList();
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: const [
          Icon(Icons.fact_check, size: 18),
          SizedBox(width: 6),
          Text('Cycle Count'),
        ]),
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
              ], rows: [
                for (final it in items)
                  DataRow(cells: [
                    DataCell(Text(it.product.sku)),
                    DataCell(Text(it.product.name)),
                    DataCell(Text(it.expectedQty.toString())),
                    DataCell(_countEditor(it)),
                    DataCell(Text(it.status.name.toUpperCase())),
                  ]),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _countEditor(AuditItem it) {
    return Row(children: [
      IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => setState(() => it.countedQty = (it.countedQty - 1).clamp(0, 1000000))),
      Text(it.countedQty.toString()),
      IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => setState(() => it.countedQty++)),
    ]);
  }
}

// Dialogs and Forms
class _ProductDialog extends StatefulWidget {
  final List<Supplier> suppliers; final Product? existing;
  const _ProductDialog({required this.suppliers, this.existing});
  @override
  State<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<_ProductDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController skuCtrl, nameCtrl, priceCtrl, variantsCtrl;
  int taxPercent = 0;
  late Supplier supplier;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    skuCtrl = TextEditingController(text: e?.sku ?? '');
    nameCtrl = TextEditingController(text: e?.name ?? '');
    priceCtrl = TextEditingController(text: e?.price.toString() ?? '');
    variantsCtrl = TextEditingController(text: e?.variants.join(', ') ?? '');
    taxPercent = e?.taxPercent ?? 0;
    supplier = e?.supplier ?? widget.suppliers.first;
  }

  @override
  void dispose() {
    skuCtrl.dispose(); nameCtrl.dispose(); priceCtrl.dispose(); variantsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add Product' : 'Edit Product'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextFormField(controller: skuCtrl, decoration: const InputDecoration(labelText: 'SKU'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter SKU' : null),
              TextFormField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter name' : null),
              TextFormField(controller: priceCtrl, decoration: const InputDecoration(labelText: 'Price'), keyboardType: TextInputType.number, validator: (v) => (v == null || double.tryParse(v) == null) ? 'Enter valid price' : null),
              DropdownButtonFormField<int>(value: taxPercent, items: const [DropdownMenuItem(value: 0, child: Text('GST 0%')), DropdownMenuItem(value: 5, child: Text('GST 5%')), DropdownMenuItem(value: 12, child: Text('GST 12%')), DropdownMenuItem(value: 18, child: Text('GST 18%'))], onChanged: (v) => setState(() => taxPercent = v ?? 0), decoration: const InputDecoration(labelText: 'GST %')),
              DropdownButtonFormField<Supplier>(value: supplier, items: [for (final s in widget.suppliers) DropdownMenuItem(value: s, child: Text(s.name))], onChanged: (v) => setState(() => supplier = v ?? widget.suppliers.first), decoration: const InputDecoration(labelText: 'Supplier')),
              TextFormField(controller: variantsCtrl, decoration: const InputDecoration(labelText: 'Variants (comma-separated)')),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final p = Product(
                sku: skuCtrl.text.trim(),
                name: nameCtrl.text.trim(),
                price: double.parse(priceCtrl.text.trim()),
                taxPercent: taxPercent,
                variants: variantsCtrl.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
                supplier: supplier,
                batches: [],
              );
              Navigator.pop(context, p);
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// Models & helpers
class Supplier { final String name; final String contact; Supplier({required this.name, required this.contact}); }

class Batch { String batchNo; DateTime expiry; int qty; String location; Batch({required this.batchNo, required this.expiry, required this.qty, required this.location}); }

class Product {
  String sku; String name; double price; int taxPercent; List<String> variants; Supplier supplier; List<Batch> batches;
  Product({required this.sku, required this.name, required this.price, required this.taxPercent, required this.variants, required this.supplier, required this.batches});
  int get totalStock => batches.fold(0, (a, b) => a + b.qty);
  int stockAt(String loc) => batches.where((b) => b.location == loc).fold(0, (a, b) => a + b.qty);
}

class StockMovement { final DateTime date; final String type; final String sku; final String name; final String location; final int qty; final String note; const StockMovement({required this.date, required this.type, required this.sku, required this.name, required this.location, required this.qty, required this.note}); factory StockMovement.now({required String type, required String sku, required String name, required int qty, required String location, required String note}) => StockMovement(date: DateTime.now(), type: type, sku: sku, name: name, location: location, qty: qty, note: note); }
class TransferLog { final DateTime date; final String sku; final String name; final String from; final String to; final int qty; final String note; const TransferLog({required this.date, required this.sku, required this.name, required this.from, required this.to, required this.qty, required this.note}); factory TransferLog.now({required String sku, required String name, required String from, required String to, required int qty, required String note}) => TransferLog(date: DateTime.now(), sku: sku, name: name, from: from, to: to, qty: qty, note: note); }

enum AuditStatus { pending, ok, mismatch }
class AuditItem { final Product product; int expectedQty; int countedQty; AuditStatus status; AuditItem({required this.product, required this.expectedQty, required this.countedQty, required this.status}); AuditItem copyWith({Product? product, int? expectedQty, int? countedQty, AuditStatus? status}) => AuditItem(product: product ?? this.product, expectedQty: expectedQty ?? this.expectedQty, countedQty: countedQty ?? this.countedQty, status: status ?? this.status); }
class LowStockAlert { final String sku; final String name; final String location; final int qty; LowStockAlert({required this.sku, required this.name, required this.location, required this.qty}); }

String _fmtDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String _fmtDateTime(DateTime d) => '${_fmtDate(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

class _PosSaleSimulator extends StatefulWidget {
  final List<Product> products; final void Function(Product p, int qty) onSale;
  const _PosSaleSimulator({required this.products, required this.onSale});
  @override
  State<_PosSaleSimulator> createState() => _PosSaleSimulatorState();
}

class _PosSaleSimulatorState extends State<_PosSaleSimulator> {
  late Product prod; int qty = 1;
  @override
  void initState() { super.initState(); prod = widget.products.first; }
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      DropdownButton<Product>(value: prod, items: [for (final p in widget.products) DropdownMenuItem(value: p, child: Text(p.name))], onChanged: (v) => setState(() => prod = v ?? widget.products.first)),
      const SizedBox(width: 8),
      SizedBox(width: 80, child: TextField(decoration: const InputDecoration(labelText: 'Qty'), keyboardType: TextInputType.number, onChanged: (v) => qty = int.tryParse(v) ?? 1)),
      const SizedBox(width: 8),
      FilledButton(onPressed: () => widget.onSale(prod, qty), child: const Text('Sale')),
    ]);
  }
}

class _AdjustmentForm extends StatefulWidget {
  final List<Product> products; final void Function(Product p, String location, bool isIn, int qty, String note) onApply;
  const _AdjustmentForm({required this.products, required this.onApply});
  @override
  State<_AdjustmentForm> createState() => _AdjustmentFormState();
}

class _AdjustmentFormState extends State<_AdjustmentForm> {
  late Product prod; String location = 'Store'; bool isIn = true; int qty = 1; final noteCtrl = TextEditingController();
  @override
  void initState() { super.initState(); prod = widget.products.first; }
  @override
  void dispose() { noteCtrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      DropdownButton<Product>(value: prod, items: [for (final p in widget.products) DropdownMenuItem(value: p, child: Text(p.name))], onChanged: (v) => setState(() => prod = v ?? widget.products.first)),
      DropdownButton<String>(value: location, items: const [DropdownMenuItem(value: 'Store', child: Text('Store')), DropdownMenuItem(value: 'Warehouse', child: Text('Warehouse'))], onChanged: (v) => setState(() => location = v ?? 'Store')),
      DropdownButton<bool>(value: isIn, items: const [DropdownMenuItem(value: true, child: Text('Adjust In')), DropdownMenuItem(value: false, child: Text('Adjust Out'))], onChanged: (v) => setState(() => isIn = v ?? true)),
      SizedBox(width: 100, child: TextField(decoration: const InputDecoration(labelText: 'Qty'), keyboardType: TextInputType.number, onChanged: (v) => qty = int.tryParse(v) ?? 1)),
      SizedBox(width: 240, child: TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: 'Note'))),
      FilledButton.icon(onPressed: () => widget.onApply(prod, location, isIn, qty, noteCtrl.text.trim()), icon: const Icon(Icons.check), label: const Text('Apply')),
    ]);
  }
}

class _TransferForm extends StatefulWidget {
  final List<Product> products; final void Function(Product p, String from, String to, int qty, String note) onTransfer;
  const _TransferForm({required this.products, required this.onTransfer});
  @override
  State<_TransferForm> createState() => _TransferFormState();
}

class _TransferFormState extends State<_TransferForm> {
  late Product prod; String from = 'Store'; String to = 'Warehouse'; int qty = 1; final noteCtrl = TextEditingController();
  @override
  void initState() { super.initState(); prod = widget.products.first; }
  @override
  void dispose() { noteCtrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      DropdownButton<Product>(value: prod, items: [for (final p in widget.products) DropdownMenuItem(value: p, child: Text(p.name))], onChanged: (v) => setState(() => prod = v ?? widget.products.first)),
      DropdownButton<String>(value: from, items: const [DropdownMenuItem(value: 'Store', child: Text('Store')), DropdownMenuItem(value: 'Warehouse', child: Text('Warehouse'))], onChanged: (v) => setState(() => from = v ?? 'Store')),
      DropdownButton<String>(value: to, items: const [DropdownMenuItem(value: 'Store', child: Text('Store')), DropdownMenuItem(value: 'Warehouse', child: Text('Warehouse'))], onChanged: (v) => setState(() => to = v ?? 'Warehouse')),
      SizedBox(width: 100, child: TextField(decoration: const InputDecoration(labelText: 'Qty'), keyboardType: TextInputType.number, onChanged: (v) => qty = int.tryParse(v) ?? 1)),
      SizedBox(width: 240, child: TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: 'Note'))),
      FilledButton.icon(onPressed: () => widget.onTransfer(prod, from, to, qty, noteCtrl.text.trim()), icon: const Icon(Icons.compare_arrows), label: const Text('Transfer')),
    ]);
  }
}
