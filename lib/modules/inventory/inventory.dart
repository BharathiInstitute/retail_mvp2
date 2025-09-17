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
					_posSaleSimulator(products: products, onSale: (p, qty) => simulatePosSale(product: p, qty: qty)),
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

		// Small helper widget to simulate a POS sale from Inventory tab
		// Lets you pick a product and quantity, then triggers onSale callback
		// which deducts stock from the 'Store' location in this demo.
		Widget _posSaleSimulator({required List<Product> products, required void Function(Product, int) onSale}) {
			Product p = products.first;
			final qtyCtrl = TextEditingController(text: '1');
			return StatefulBuilder(builder: (context, setState) {
				return Row(children: [
					DropdownButton<Product>(value: p, items: [for (final x in products) DropdownMenuItem(value: x, child: Text(x.name))], onChanged: (v) => setState(() => p = v ?? p)),
					const SizedBox(width: 8),
					SizedBox(width: 64, child: TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Qty'))),
					const SizedBox(width: 8),
					OutlinedButton(onPressed: () => onSale(p, int.tryParse(qtyCtrl.text) ?? 1), child: const Text('Sell')),
				]);
			});
		}

		// TRANSFERS TAB
		Widget _transfersTab() {
			return Padding(
				padding: const EdgeInsets.all(12.0),
				child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
					const Text('Transfers'),
					const SizedBox(height: 8),
					_TransferForm(products: products, onTransfer: (p, from, to, qty, note) => transferStock(product: p, from: from, to: to, qty: qty, note: note)),
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
			final today = DateTime.now();
			final lowStock = products.where((p) => p.totalStock <= 10).toList();
			final expiring = [
				for (final p in products)
					for (final b in p.batches)
						if (b.expiry.isBefore(today.add(const Duration(days: 30)))) _ExpiryRow(p: p, b: b),
			];
			return Padding(
				padding: const EdgeInsets.all(12.0),
				child: ListView(children: [
					const Text('Low Stock'),
					const SizedBox(height: 8),
					Card(
						child: SingleChildScrollView(
							scrollDirection: Axis.horizontal,
							child: DataTable(columns: const [
								DataColumn(label: Text('SKU')),
								DataColumn(label: Text('Product')),
								DataColumn(label: Text('Total Stock')),
							], rows: [
								for (final p in lowStock)
									DataRow(cells: [
										DataCell(Text(p.sku)),
										DataCell(Text(p.name)),
										DataCell(Text(p.totalStock.toString())),
									]),
							]),
						),
					),
					const SizedBox(height: 12),
					const Text('Near Expiry (< 30 days)'),
					const SizedBox(height: 8),
					Card(
						child: SingleChildScrollView(
							scrollDirection: Axis.horizontal,
							child: DataTable(columns: const [
								DataColumn(label: Text('SKU')),
								DataColumn(label: Text('Product')),
								DataColumn(label: Text('Batch')),
								DataColumn(label: Text('Expiry')),
							], rows: [
								for (final r in expiring)
									DataRow(cells: [
										DataCell(Text(r.p.sku)),
										DataCell(Text(r.p.name)),
										DataCell(Text(r.b.batchNo)),
										DataCell(Text(_fmtDate(r.b.expiry))),
									]),
							]),
						),
					),
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
						OutlinedButton(onPressed: () => setState(() { for (final a in audit.values) { a.countedQty = a.expectedQty; a.status = AuditStatus.ok; } }), child: const Text('Mark All OK')),
					]),
				]),
			);
		}
	}

	// DIALOGS & WIDGETS

	class _ProductDialog extends StatefulWidget {
		final List<Supplier> suppliers;
		final Product? existing;
		const _ProductDialog({required this.suppliers, this.existing});

		@override
		State<_ProductDialog> createState() => _ProductDialogState();
	}

	class _ProductDialogState extends State<_ProductDialog> {
		late final TextEditingController skuCtrl;
		late final TextEditingController nameCtrl;
		late final TextEditingController priceCtrl;
		late Supplier supplier;
		int taxPercent = 18;
		final variantsCtrl = TextEditingController();

		@override
		void initState() {
			super.initState();
			final e = widget.existing;
			skuCtrl = TextEditingController(text: e?.sku ?? 'SKU${DateTime.now().millisecondsSinceEpoch % 10000}');
			nameCtrl = TextEditingController(text: e?.name ?? '');
			priceCtrl = TextEditingController(text: e?.price.toStringAsFixed(2) ?? '0');
			supplier = e?.supplier ?? widget.suppliers.first;
			taxPercent = e?.taxPercent ?? 18;
			variantsCtrl.text = e?.variants.join(', ') ?? '';
		}

		@override
		Widget build(BuildContext context) {
			return AlertDialog(
				title: Text(widget.existing == null ? 'Add Product' : 'Edit Product'),
				content: SizedBox(
					width: 420,
					child: SingleChildScrollView(
						child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
							TextField(controller: skuCtrl, decoration: const InputDecoration(labelText: 'SKU')),
							TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
							TextField(controller: priceCtrl, decoration: const InputDecoration(labelText: 'Price ₹'), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
							DropdownButtonFormField<Supplier>(
								value: supplier,
								items: [for (final s in widget.suppliers) DropdownMenuItem(value: s, child: Text(s.name))],
								onChanged: (v) => setState(() => supplier = v ?? supplier),
								decoration: const InputDecoration(labelText: 'Supplier'),
							),
							DropdownButtonFormField<int>(
								value: taxPercent,
								items: const [0, 5, 12, 18].map((t) => DropdownMenuItem(value: t, child: Text('GST $t%'))).toList(),
								onChanged: (v) => setState(() => taxPercent = v ?? taxPercent),
								decoration: const InputDecoration(labelText: 'GST'),
							),
							TextField(controller: variantsCtrl, decoration: const InputDecoration(labelText: 'Variants (comma separated)')),
						]),
					),
				),
				actions: [
					TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
					FilledButton(
						onPressed: () {
							final p = Product(
								sku: skuCtrl.text.trim(),
								name: nameCtrl.text.trim(),
								price: double.tryParse(priceCtrl.text) ?? 0,
								taxPercent: taxPercent,
								variants: variantsCtrl.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
								supplier: supplier,
								batches: [Batch(batchNo: 'NEW', expiry: DateTime.now().add(const Duration(days: 180)), qty: 0, location: 'Store')],
							);
							Navigator.pop(context, p);
						},
						child: const Text('Save'),
					),
				],
			);
		}
	}

	class _AdjustmentForm extends StatefulWidget {
		final List<Product> products;
		final void Function(Product, String, bool, int, String) onApply;
		const _AdjustmentForm({required this.products, required this.onApply});
		@override
		State<_AdjustmentForm> createState() => _AdjustmentFormState();
	}

	class _AdjustmentFormState extends State<_AdjustmentForm> {
		late Product product;
		String location = 'Store';
		bool isIn = true;
		final qtyCtrl = TextEditingController(text: '1');
		final noteCtrl = TextEditingController();
		@override
		void initState() {
			super.initState();
			product = widget.products.first;
		}
		@override
		Widget build(BuildContext context) {
			return Card(
				child: Padding(
					padding: const EdgeInsets.all(8.0),
					child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
						DropdownButton<Product>(
							value: product,
							items: [for (final p in widget.products) DropdownMenuItem(value: p, child: Text(p.name))],
							onChanged: (v) => setState(() => product = v ?? product),
						),
						DropdownButton<String>(
							value: location,
							items: const ['Store', 'Warehouse'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
							onChanged: (v) => setState(() => location = v ?? location),
						),
						DropdownButton<bool>(
							value: isIn,
							items: const [true, false].map((e) => DropdownMenuItem(value: e, child: Text(e ? 'Adjust In' : 'Adjust Out'))).toList(),
							onChanged: (v) => setState(() => isIn = v ?? isIn),
						),
						SizedBox(width: 80, child: TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Qty'))),
						SizedBox(width: 200, child: TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: 'Note'))),
						FilledButton(onPressed: () => widget.onApply(product, location, isIn, int.tryParse(qtyCtrl.text) ?? 0, noteCtrl.text.trim()), child: const Text('Apply')),
					]),
				),
			);
		}
	}

	class _TransferForm extends StatefulWidget {
		final List<Product> products;
		final void Function(Product, String, String, int, String) onTransfer;
		const _TransferForm({required this.products, required this.onTransfer});
		@override
		State<_TransferForm> createState() => _TransferFormState();
	}

	class _TransferFormState extends State<_TransferForm> {
		late Product product;
		String from = 'Store';
		String to = 'Warehouse';
		final qtyCtrl = TextEditingController(text: '1');
		final noteCtrl = TextEditingController();
		@override
		void initState() { super.initState(); product = widget.products.first; }
		@override
		Widget build(BuildContext context) {
			return Card(
				child: Padding(
					padding: const EdgeInsets.all(8.0),
					child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
						DropdownButton<Product>(value: product, items: [for (final p in widget.products) DropdownMenuItem(value: p, child: Text(p.name))], onChanged: (v) => setState(() => product = v ?? product)),
						DropdownButton<String>(value: from, items: const ['Store', 'Warehouse'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setState(() => from = v ?? from)),
						DropdownButton<String>(value: to, items: const ['Store', 'Warehouse'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setState(() => to = v ?? to)),
						SizedBox(width: 80, child: TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Qty'))),
						SizedBox(width: 200, child: TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: 'Note'))),
						FilledButton(onPressed: () => widget.onTransfer(product, from, to, int.tryParse(qtyCtrl.text) ?? 0, noteCtrl.text.trim()), child: const Text('Transfer')),
					]),
				),
			);
		}
	}

	class _ExpiryRow {
		final Product p; final Batch b;
		_ExpiryRow({required this.p, required this.b});
	}

	// MODELS

	class Supplier {
		final String name; final String contact;
		Supplier({required this.name, required this.contact});
	}

	class Product {
		final String sku; final String name; final double price; final int taxPercent; final List<String> variants; final Supplier supplier; final List<Batch> batches;
		Product({required this.sku, required this.name, required this.price, required this.taxPercent, required this.variants, required this.supplier, required this.batches});
		int get totalStock => batches.fold(0, (s, b) => s + b.qty);
		int stockAt(String location) => batches.where((b) => b.location == location).fold(0, (s, b) => s + b.qty);
	}

	class Batch {
		final String batchNo; DateTime expiry; int qty; String location;
		Batch({required this.batchNo, required this.expiry, required this.qty, required this.location});
	}

	class StockMovement {
		final DateTime date; final String type; final String sku; final String name; final String location; final int qty; final String note;
		StockMovement({required this.date, required this.type, required this.sku, required this.name, required this.location, required this.qty, required this.note});
		factory StockMovement.now({required String type, required String sku, required String name, required int qty, required String location, required String note}) => StockMovement(date: DateTime.now(), type: type, sku: sku, name: name, location: location, qty: qty, note: note);
	}

	class TransferLog {
		final DateTime date; final String sku; final String name; final String from; final String to; final int qty; final String note;
		TransferLog({required this.date, required this.sku, required this.name, required this.from, required this.to, required this.qty, required this.note});
		factory TransferLog.now({required String sku, required String name, required String from, required String to, required int qty, required String note}) => TransferLog(date: DateTime.now(), sku: sku, name: name, from: from, to: to, qty: qty, note: note);
	}

	enum AuditStatus { pending, review, ok }

	class AuditItem {
		final Product product; int expectedQty; int countedQty; AuditStatus status;
		AuditItem({required this.product, required this.expectedQty, required this.countedQty, required this.status});
		AuditItem copyWith({Product? product, int? expectedQty, int? countedQty, AuditStatus? status}) => AuditItem(product: product ?? this.product, expectedQty: expectedQty ?? this.expectedQty, countedQty: countedQty ?? this.countedQty, status: status ?? this.status);
	}

	// HELPERS

	String _fmtDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
	String _fmtDateTime(DateTime d) => '${_fmtDate(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';