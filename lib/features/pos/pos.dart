import 'package:flutter/material.dart';

// Standalone POS Screen UI with demo data and full feature coverage (no external deps)

class PosPage extends StatefulWidget {
  const PosPage({super.key});

  @override
  State<PosPage> createState() => _PosPageState();
}

class _PosPageState extends State<PosPage> {
  // Demo Data
  final List<Product> products = [
    Product(sku: 'SKU1001', name: 'Milk 1L', price: 55.0, stock: 50, taxPercent: 5),
    Product(sku: 'SKU1002', name: 'Bread Loaf', price: 40.0, stock: 80, taxPercent: 5),
    Product(sku: 'SKU1003', name: 'Rice 5kg', price: 345.0, stock: 30, taxPercent: 5),
    Product(sku: 'SKU2001', name: 'Shampoo 200ml', price: 120.0, stock: 25, taxPercent: 18),
    Product(sku: 'SKU2002', name: 'Soap Bar', price: 30.0, stock: 100, taxPercent: 18),
    Product(sku: 'SKU3001', name: 'Biscuits', price: 20.0, stock: 200, taxPercent: 12),
    Product(sku: 'SKU4001', name: 'Cooking Oil 1L', price: 160.0, stock: 40, taxPercent: 5),
    Product(sku: 'SKU5001', name: 'Toothpaste', price: 90.0, stock: 60, taxPercent: 12),
  ];

  final List<Customer> customers = [
    Customer(name: 'Walk-in Customer'),
    Customer(name: 'Rahul Sharma'),
    Customer(name: 'Priya Singh'),
  ];

  final TextEditingController barcodeCtrl = TextEditingController();
  final TextEditingController searchCtrl = TextEditingController();

  final Map<String, CartItem> cart = {};
  final List<HeldOrder> heldOrders = [];

  DiscountType discountType = DiscountType.none;
  final TextEditingController discountCtrl = TextEditingController(text: '0');

  Customer? selectedCustomer;

  final List<PaymentSplit> splits = [PaymentSplit(mode: PaymentMode.cash, amount: 0)];

  String get invoiceNumber => 'INV-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';

  @override
  void initState() {
    super.initState();
    selectedCustomer = customers.first;
  }

  // Business logic helpers (demo only)
  void addToCart(Product p, {int qty = 1}) {
    final existing = cart[p.sku];
    final newQty = (existing?.qty ?? 0) + qty;
    if (newQty > p.stock) {
      _snack('Insufficient stock for ${p.name}');
      return;
    }
    setState(() {
      cart[p.sku] = CartItem(product: p, qty: newQty);
    });
  }

  void removeFromCart(String sku) {
    setState(() => cart.remove(sku));
  }

  void changeQty(String sku, int delta) {
    final item = cart[sku];
    if (item == null) return;
    final newQty = item.qty + delta;
    if (newQty <= 0) {
      removeFromCart(sku);
    } else if (newQty > item.product.stock) {
      _snack('Insufficient stock for ${item.product.name}');
    } else {
      setState(() => cart[sku] = item.copyWith(qty: newQty));
    }
  }

  double get subtotal => cart.values.fold(0.0, (s, it) => s + it.product.price * it.qty);

  double get discountValue {
    final val = double.tryParse(discountCtrl.text) ?? 0.0;
    switch (discountType) {
      case DiscountType.none:
        return 0;
      case DiscountType.percent:
        return (subtotal * (val / 100)).clamp(0, subtotal);
      case DiscountType.flat:
        return val.clamp(0, subtotal);
    }
  }

  // Distribute discount proportionally by line amount
  Map<String, double> get lineDiscounts {
    if (subtotal == 0) return {};
    final map = <String, double>{};
    for (final it in cart.values) {
      final line = it.product.price * it.qty;
      map[it.product.sku] = (line / subtotal) * discountValue;
    }
    return map;
  }

  // Tax per line after discount share
  Map<String, double> get lineTaxes {
    final discounts = lineDiscounts;
    final map = <String, double>{};
    for (final it in cart.values) {
      final line = it.product.price * it.qty;
      final net = (line - (discounts[it.product.sku] ?? 0)).clamp(0, double.infinity);
      final tax = net * (it.product.taxPercent / 100);
      map[it.product.sku] = tax;
    }
    return map;
  }

  double get totalTax => lineTaxes.values.fold(0.0, (s, t) => s + t);
  double get grandTotal => (subtotal - discountValue + totalTax);

  double get paidAmount => splits.fold(0.0, (s, p) => s + (p.amount));
  double get balanceDue => (grandTotal - paidAmount);

  void autoSplitBalance() {
    if (splits.isEmpty) return;
    setState(() {
      final amtBeforeLast = splits.take(splits.length - 1).fold(0.0, (s, p) => s + p.amount);
      final remaining = (grandTotal - amtBeforeLast).clamp(0.0, double.infinity).toDouble();
      splits.last = splits.last.copyWith(amount: remaining);
    });
  }

  void holdCart() {
    if (cart.isEmpty) return _snack('Cart is empty');
    final snapshot = HeldOrder(
      id: 'HLD-${heldOrders.length + 1}',
      timestamp: DateTime.now(),
      items: cart.values.map((e) => e.copy()).toList(),
      discountType: discountType,
      discountValueText: discountCtrl.text,
    );
    setState(() {
      heldOrders.add(snapshot);
      cart.clear();
    });
    _snack('Order ${snapshot.id} held');
  }

  void resumeHeld(HeldOrder order) {
    setState(() {
      cart.clear();
      for (final it in order.items) {
        cart[it.product.sku] = it.copy();
      }
      discountType = order.discountType;
      discountCtrl.text = order.discountValueText;
    });
  }

  void completeSale() {
    if (cart.isEmpty) return _snack('Cart is empty');
    if (balanceDue > 0.009) return _snack('Payment incomplete');

    // Update stock
    for (final item in cart.values) {
      item.product.stock -= item.qty;
    }

    final summary = _buildInvoiceSummary();

    // Clear transactional state (keep payment splits layout)
    setState(() {
      cart.clear();
      discountType = DiscountType.none;
      discountCtrl.text = '0';
      for (int i = 0; i < splits.length; i++) {
        splits[i] = splits[i].copyWith(amount: 0);
      }
    });

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Invoice Preview (GST)'),
        content: SizedBox(width: 480, child: summary),
        actions: [
          TextButton(onPressed: () { Navigator.pop(context); _snack('Printing invoice...'); }, child: const Text('Print')),
          TextButton(onPressed: () { Navigator.pop(context); _snack('Email sent'); }, child: const Text('Email')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _buildInvoiceSummary() {
    // Build from last computed values; for demo we recompute
    final discounts = lineDiscounts;
    final taxes = lineTaxes;
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Invoice #: $invoiceNumber'),
        Text('Customer: ${selectedCustomer?.name ?? 'Walk-in'}'),
        const SizedBox(height: 8),
        const Divider(),
        ...cart.values.map((it) {
          final price = it.product.price;
          final line = price * it.qty;
          final disc = discounts[it.product.sku] ?? 0;
          final tax = taxes[it.product.sku] ?? 0;
          final net = line - disc + tax;
          return ListTile(
            dense: true,
            title: Text('${it.product.name} x ${it.qty}'),
            subtitle: Text('Price: ₹${price.toStringAsFixed(2)}  |  Disc: ₹${disc.toStringAsFixed(2)}  |  Tax ${it.product.taxPercent}%: ₹${tax.toStringAsFixed(2)}'),
            trailing: Text('₹${net.toStringAsFixed(2)}'),
          );
        }),
        const Divider(),
        _kv('Subtotal', subtotal),
        _kv('Discount', -discountValue),
        _kv('Tax Total', totalTax),
        const Divider(),
        _kv('Grand Total', grandTotal, bold: true),
        const SizedBox(height: 8),
        const Text('Payments:'),
        ...splits.where((s) => s.amount > 0).map((s) => Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text(' - ${s.mode.label}'), Text('₹${s.amount.toStringAsFixed(2)}')],
            )),
      ]),
    );
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 1100;
    final filtered = _filteredProducts();
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: isWide ? _wideLayout(filtered) : _narrowLayout(filtered),
    );
  }

  List<Product> _filteredProducts() {
    final q = searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return products;
    return products.where((p) => p.sku.toLowerCase().contains(q) || p.name.toLowerCase().contains(q)).toList();
  }

  Widget _wideLayout(List<Product> filtered) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left: Product Search/List + Popular
        SizedBox(
          width: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _searchAndBarcode(),
              const SizedBox(height: 8),
              Expanded(child: _productList(filtered)),
              const SizedBox(height: 8),
              _popularGrid(),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // Middle: Cart
        Expanded(child: _cartSection()),
        const SizedBox(width: 12),
        // Right: Payment & Summary
        SizedBox(width: 360, child: _paymentAndSummary()),
      ],
    );
  }

  Widget _narrowLayout(List<Product> filtered) {
    return ListView(
      children: [
        _searchAndBarcode(),
        const SizedBox(height: 8),
        SizedBox(height: 240, child: _productList(filtered)),
        const SizedBox(height: 8),
        _popularGrid(),
        const SizedBox(height: 8),
        _cartSection(),
        const SizedBox(height: 8),
        _paymentAndSummary(),
      ],
    );
  }

  Widget _searchAndBarcode() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: barcodeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Barcode / SKU',
                  prefixIcon: Icon(Icons.qr_code_scanner),
                ),
                onSubmitted: (_) => _scan(),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(onPressed: _scan, icon: const Icon(Icons.center_focus_strong), label: const Text('Scan')),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: searchCtrl,
            decoration: const InputDecoration(
              labelText: 'Quick Product Search',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ]),
      ),
    );
  }

  void _scan() {
    final sku = barcodeCtrl.text.trim();
    final p = products.where((e) => e.sku.toLowerCase() == sku.toLowerCase()).firstWhere(
          (e) => true,
          orElse: () => Product(sku: '', name: '', price: 0, stock: 0, taxPercent: 0),
        );
    if (p.sku.isEmpty) {
      _snack('No product for barcode/SKU: $sku');
    } else {
      addToCart(p);
    }
    barcodeCtrl.clear();
  }

  Widget _productList(List<Product> items) {
    return Card(
      child: ListView.separated(
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final p = items[i];
          return ListTile(
            title: Text('${p.name}  •  ₹${p.price.toStringAsFixed(2)}'),
            subtitle: Text('SKU: ${p.sku}  •  Stock: ${p.stock}  •  GST ${p.taxPercent}%'),
            trailing: IconButton(
              icon: const Icon(Icons.add_circle),
              onPressed: p.stock > 0 ? () => addToCart(p) : null,
            ),
          );
        },
      ),
    );
  }

  Widget _popularGrid() {
    final popular = products.take(6).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Popular Items', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: popular.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 3),
            itemBuilder: (_, i) {
              final p = popular[i];
              return ElevatedButton(
                onPressed: p.stock > 0 ? () => addToCart(p) : null,
                child: Text(p.name, overflow: TextOverflow.ellipsis),
              );
            },
          ),
        ]),
      ),
    );
  }

  Widget _cartSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            children: [
              const Text('Cart', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              ElevatedButton.icon(onPressed: holdCart, icon: const Icon(Icons.pause_circle), label: const Text('Hold')),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: heldOrders.isEmpty
                    ? null
                    : () async {
                        final sel = await showDialog<HeldOrder>(
                          context: context,
                          builder: (_) => _HeldOrdersDialog(orders: heldOrders),
                        );
                        if (sel != null) resumeHeld(sel);
                      },
                icon: const Icon(Icons.play_circle),
                label: const Text('Resume'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: cart.isEmpty
                ? const Center(child: Text('Cart is empty'))
                : ListView.separated(
                    itemCount: cart.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final item = cart.values.elementAt(i);
                      final line = item.product.price * item.qty;
                      return ListTile(
                        title: Text(item.product.name),
                        subtitle: Text('₹${item.product.price.toStringAsFixed(2)}  •  GST ${item.product.taxPercent}%'),
                        leading: IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => changeQty(item.product.sku, -1)),
                        trailing: SizedBox(
                          width: 190,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton(icon: const Icon(Icons.remove), onPressed: () => changeQty(item.product.sku, -1)),
                              Text(item.qty.toString()),
                              IconButton(icon: const Icon(Icons.add), onPressed: () => changeQty(item.product.sku, 1)),
                              const SizedBox(width: 6),
                              Text('₹${line.toStringAsFixed(2)}'),
                              IconButton(icon: const Icon(Icons.close), onPressed: () => removeFromCart(item.product.sku)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }

  Widget _paymentAndSummary() {
    final taxesByRate = <int, double>{};
    final taxes = lineTaxes;
    for (final it in cart.values) {
      final tax = taxes[it.product.sku] ?? 0.0;
      taxesByRate.update(it.product.taxPercent, (v) => v + tax, ifAbsent: () => tax);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Customer selection
          DropdownButtonFormField<Customer>(
            value: selectedCustomer,
            items: [for (final c in customers) DropdownMenuItem(value: c, child: Text(c.name))],
            onChanged: (c) => setState(() => selectedCustomer = c),
            decoration: const InputDecoration(labelText: 'Customer'),
          ),
          const SizedBox(height: 8),
          // Discount controls
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<DiscountType>(
                value: discountType,
                items: DiscountType.values
                    .map((e) => DropdownMenuItem(value: e, child: Text(e.label)))
                    .toList(),
                onChanged: (v) => setState(() => discountType = v ?? DiscountType.none),
                decoration: const InputDecoration(labelText: 'Discount Type'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: discountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: discountType == DiscountType.percent ? 'Percent %' : 'Flat ₹'),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          // Payment splits
          const Text('Payments (Split Supported)', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          ...splits.asMap().entries.map((e) => _splitRow(e.key, e.value)),
          Row(children: [
            OutlinedButton.icon(
              onPressed: () => setState(() => splits.add(PaymentSplit(mode: PaymentMode.cash, amount: 0))),
              icon: const Icon(Icons.add),
              label: const Text('Add Split'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: autoSplitBalance, child: const Text('Auto Split Balance')),
          ]),
          const Divider(),
          // Summary
          _kv('Subtotal', subtotal),
          _kv('Discount', -discountValue),
          const SizedBox(height: 6),
          const Text('GST Breakdown'),
          ...taxesByRate.entries.map((e) => _kv('GST ${e.key}%', e.value)),
          const Divider(),
          _kv('Grand Total', grandTotal, bold: true),
          _kv('Paid', paidAmount),
          _kv('Balance', balanceDue),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: completeSale,
                icon: const Icon(Icons.check_circle),
                label: const Text('Checkout'),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: () => _snack('Printing invoice...'), icon: const Icon(Icons.print), label: const Text('Print Invoice'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(onPressed: () => _snack('Email sent'), icon: const Icon(Icons.email), label: const Text('Email Invoice'))),
          ]),
        ]),
      ),
    );
  }

  Widget _splitRow(int index, PaymentSplit split) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Row(children: [
        Expanded(
          flex: 2,
          child: DropdownButtonFormField<PaymentMode>(
            value: split.mode,
            items: PaymentMode.values
                .map((m) => DropdownMenuItem(value: m, child: Text(m.label)))
                .toList(),
            onChanged: (v) => setState(() => splits[index] = split.copyWith(mode: v ?? split.mode)),
            decoration: const InputDecoration(labelText: 'Mode'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: TextFormField(
            initialValue: split.amount == 0 ? '' : split.amount.toStringAsFixed(2),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Amount ₹'),
            onChanged: (v) => setState(() => splits[index] = split.copyWith(amount: double.tryParse(v) ?? 0)),
          ),
        ),
        IconButton(
          onPressed: splits.length > 1 ? () => setState(() => splits.removeAt(index)) : null,
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Remove split',
        ),
      ]),
    );
  }

  Widget _kv(String label, double value, {bool bold = false}) {
    final style = TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text('₹${value.toStringAsFixed(2)}', style: style)],
      ),
    );
  }
}

// Demo Models & Data structures

class Product {
  final String sku;
  final String name;
  final double price;
  int stock;
  final int taxPercent; // GST

  Product({required this.sku, required this.name, required this.price, required this.stock, required this.taxPercent});
}

class Customer {
  final String name;
  Customer({required this.name});
}

class CartItem {
  final Product product;
  final int qty;
  CartItem({required this.product, required this.qty});
  CartItem copyWith({Product? product, int? qty}) => CartItem(product: product ?? this.product, qty: qty ?? this.qty);
  CartItem copy() => CartItem(product: product, qty: qty);
}

class HeldOrder {
  final String id;
  final DateTime timestamp;
  final List<CartItem> items;
  final DiscountType discountType;
  final String discountValueText;
  HeldOrder({required this.id, required this.timestamp, required this.items, required this.discountType, required this.discountValueText});
}

enum PaymentMode { cash, upi, card, wallet }

extension PaymentModeX on PaymentMode {
  String get label => switch (this) { PaymentMode.cash => 'Cash', PaymentMode.upi => 'UPI', PaymentMode.card => 'Card', PaymentMode.wallet => 'Wallet' };
}

class PaymentSplit {
  final PaymentMode mode;
  final double amount;
  PaymentSplit({required this.mode, required this.amount});
  PaymentSplit copyWith({PaymentMode? mode, double? amount}) => PaymentSplit(mode: mode ?? this.mode, amount: amount ?? this.amount);
}

enum DiscountType { none, percent, flat }

extension DiscountTypeX on DiscountType {
  String get label => switch (this) { DiscountType.none => 'None', DiscountType.percent => 'Percent %', DiscountType.flat => 'Flat ₹' };
}

class _HeldOrdersDialog extends StatelessWidget {
  final List<HeldOrder> orders;
  const _HeldOrdersDialog({required this.orders});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Held Orders'),
      content: SizedBox(
        width: 420,
        height: 360,
        child: ListView.separated(
          itemCount: orders.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final o = orders[i];
            final count = o.items.fold<int>(0, (s, it) => s + it.qty);
            return ListTile(
              title: Text('${o.id} • ${o.timestamp.hour.toString().padLeft(2, '0')}:${o.timestamp.minute.toString().padLeft(2, '0')}'),
              subtitle: Text('Items: $count • Discount: ${o.discountType.name.toUpperCase()} ${o.discountValueText}'),
              trailing: const Icon(Icons.play_circle_outline),
              onTap: () => Navigator.pop(context, o),
            );
          },
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}
