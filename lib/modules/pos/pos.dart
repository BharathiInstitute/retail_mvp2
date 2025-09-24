import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Standalone POS Screen UI with demo data and full feature coverage (no external deps)

class PosPage extends StatefulWidget {
  const PosPage({super.key});

  @override
  State<PosPage> createState() => _PosPageState();
}

class _PosPageState extends State<PosPage> {
  // Firestore-backed products cache (for quick lookup by barcode/SKU)
  List<Product> _cacheProducts = [];

  // POS customers: Walk-in plus CRM customers from Firestore
  static const Customer walkIn = Customer(id: '', name: 'Walk-in Customer');
  List<Customer> customers = const [walkIn];

  final TextEditingController barcodeCtrl = TextEditingController();
  final TextEditingController searchCtrl = TextEditingController();

  final Map<String, CartItem> cart = {};
  final List<HeldOrder> heldOrders = [];

  // Favorites: store product SKUs marked as favorite
  final Set<String> favoriteSkus = <String>{};

  DiscountType discountType = DiscountType.none;
  final TextEditingController discountCtrl = TextEditingController(text: '0');

  Customer? selectedCustomer;

  // Selected payment mode (simple)
  PaymentMode selectedPaymentMode = PaymentMode.cash;

  String get invoiceNumber => 'INV-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';

  @override
  void initState() {
    super.initState();
    selectedCustomer = customers.first;
    // Fix discount mode to Percent (discount type selector removed)
    discountType = DiscountType.percent;
    // Preload CRM customers once to seed the dropdown/search
    _loadCustomersOnce();
  }

  // Stream CRM customers from Firestore `customers` collection
  Stream<List<Customer>> get _customerStream => FirebaseFirestore.instance
      .collection('customers')
      .snapshots()
      .map((snap) {
        final list = snap.docs.map((d) => Customer.fromDoc(d)).toList();
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        return [walkIn, ...list];
      });

  Future<void> _loadCustomersOnce() async {
    try {
      final s = await FirebaseFirestore.instance.collection('customers').get();
      final list = s.docs.map((d) => Customer.fromDoc(d)).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      setState(() {
        customers = [walkIn, ...list];
        // keep existing selection if still present; else default to Walk-in
        if (selectedCustomer == null || !customers.any((c) => c.id == selectedCustomer!.id)) {
          selectedCustomer = walkIn;
        }
      });
    } catch (_) {
      // ignore errors for now
    }
  }

  // Stream products from Firestore `inventory` collection
  Stream<List<Product>> get _productStream => FirebaseFirestore.instance
      .collection('inventory')
      .snapshots()
      .map((snap) => snap.docs.map((d) => Product.fromDoc(d)).toList());

  // Business logic helpers (demo only)
  void addToCart(Product p, {int qty = 1}) {
    final existing = cart[p.sku];
    final newQty = (existing?.qty ?? 0) + qty;
    setState(() {
      cart[p.sku] = CartItem(product: p, qty: newQty);
    });
    _snack('Added to cart: ${p.name} (x$newQty)');
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

  // Payments removed: no paid/balance tracking

  // Payment split auto-balance removed

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
      // Also clear the resumed order from the held list so it doesn't appear again
      heldOrders.removeWhere((o) => o.id == order.id);
    });
  }

  void completeSale() {
    if (cart.isEmpty) return _snack('Cart is empty');

    // Update stock
    for (final item in cart.values) {
      item.product.stock -= item.qty;
    }

    // Note: Not writing stock back to Firestore here because inventory uses batches.
    // Stock adjustments should be handled via batch movements or a Cloud Function.

    // Compute net amount eligible for rewards (exclude tax)
    final double netEarnable = (subtotal - discountValue).clamp(0.0, double.infinity);

    // Accrue rewards to CRM (firestore) before clearing state
    // This function does not use BuildContext after await to avoid analyzer warnings
    _accrueRewards(netEarnable);

    final summary = _buildInvoiceSummary();

    // Clear transactional state
    setState(() {
      cart.clear();
      discountType = DiscountType.none;
      discountCtrl.text = '0';
    });

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Invoice Preview (GST)'),
        content: SizedBox(width: 480, child: summary),
        actions: [
          TextButton.icon(
            onPressed: () {
              // Placeholder: Hook to actual print logic if available
              ScaffoldMessenger.of(dialogCtx).showSnackBar(const SnackBar(content: Text('Printing invoice...')));
            },
            icon: const Icon(Icons.print),
            label: const Text('Print'),
          ),
          TextButton.icon(
            onPressed: () {
              // Placeholder: Hook to actual email logic if available
              ScaffoldMessenger.of(dialogCtx).showSnackBar(const SnackBar(content: Text('Email sent (demo)...')));
            },
            icon: const Icon(Icons.email),
            label: const Text('Email'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx, rootNavigator: true).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _accrueRewards(double netAmount) async {
    try {
      if (netAmount <= 0) return;
  final custName = selectedCustomer?.name.trim();
      if (custName == null || custName.isEmpty || custName.toLowerCase() == 'walk-in customer') {
        return; // skip walk-in / empty
      }

      // Ensure signed in (anonymous is fine)
      final auth = FirebaseAuth.instance;
      if (auth.currentUser == null) {
        await auth.signInAnonymously();
      }

      final col = FirebaseFirestore.instance.collection('customers');
      final snap = await col.where('name', isEqualTo: custName).limit(1).get();
      final now = DateTime.now();
      if (snap.docs.isNotEmpty) {
        final ref = snap.docs.first.reference;
        await ref.set({
          'totalSpend': FieldValue.increment(netAmount),
          'lastVisit': Timestamp.fromDate(now),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        // Create minimal customer if not found
        await col.add({
          'name': custName,
          'phone': '',
          'email': '',
          'status': 'bronze',
          'totalSpend': netAmount,
          'lastVisit': Timestamp.fromDate(now),
          'preferences': '',
          'notes': '',
          'smsOptIn': false,
          'emailOptIn': false,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      // Silent failure; optionally log or surface minimal feedback without using context
      // debugPrint('Reward accrual failed: $e');
    }
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
      ]),
    );
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 1100;
    return StreamBuilder<List<Product>>(
      stream: _productStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error loading products: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final allProducts = snapshot.data!;
        // Update cache for barcode/search usage
        _cacheProducts = allProducts;
        final filtered = _filteredProducts(allProducts);
        return Padding(
          padding: const EdgeInsets.all(12.0),
          child: isWide ? _wideLayout(filtered, allProducts) : _narrowLayout(filtered, allProducts),
        );
      },
    );
  }

  List<Product> _filteredProducts(List<Product> products) {
    final q = searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return products;
    return products.where((p) =>
      (p.sku.toLowerCase().contains(q)) ||
      (p.name.toLowerCase().contains(q)) ||
      ((p.barcode ?? '').toLowerCase().contains(q))
    ).toList();
  }

  Widget _wideLayout(List<Product> filtered, List<Product> allProducts) {
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
              _popularGrid(allProducts),
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

  Widget _narrowLayout(List<Product> filtered, List<Product> allProducts) {
    return ListView(
      children: [
        _searchAndBarcode(),
        const SizedBox(height: 8),
        SizedBox(height: 240, child: _productList(filtered)),
        const SizedBox(height: 8),
        _popularGrid(allProducts),
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
            decoration: InputDecoration(
              labelText: 'Quick Product Search',
              prefixIcon: const Icon(Icons.search),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ]),
      ),
    );
  }

  Future<void> _scan() async {
    final code = barcodeCtrl.text.trim();
    if (code.isEmpty) return;
    // Try local cache first
    Product? found;
    for (final p in _cacheProducts) {
      if (p.sku.toLowerCase() == code.toLowerCase() ||
          (p.barcode != null && p.barcode!.toLowerCase() == code.toLowerCase())) {
        found = p;
        break;
      }
    }
    // If not found, query Firestore by sku then barcode
    if (found == null) {
      try {
        final bySku = await FirebaseFirestore.instance
            .collection('inventory')
            .where('sku', isEqualTo: code)
            .limit(1)
            .get();
        if (bySku.docs.isNotEmpty) {
          found = Product.fromDoc(bySku.docs.first);
        } else {
          final byBarcode = await FirebaseFirestore.instance
              .collection('inventory')
              .where('barcode', isEqualTo: code)
              .limit(1)
              .get();
          if (byBarcode.docs.isNotEmpty) {
            found = Product.fromDoc(byBarcode.docs.first);
          }
        }
      } catch (e) {
        _snack('Scan failed: $e');
      }
    }

    if (found == null) {
      _snack('No product for code: $code');
    } else {
      addToCart(found);
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
          final isFav = favoriteSkus.contains(p.sku);
          return ListTile(
            title: Text('${p.name}  •  ₹${p.price.toStringAsFixed(2)}'),
            subtitle: Text('SKU: ${p.sku}  •  Stock: ${p.stock}  •  GST ${p.taxPercent}%'),
            trailing: IconButton(
              tooltip: isFav ? 'Unfavorite' : 'Mark favorite',
              icon: Icon(isFav ? Icons.star : Icons.star_border, color: isFav ? Colors.amber : null),
              onPressed: () => setState(() {
                if (isFav) {
                  favoriteSkus.remove(p.sku);
                } else {
                  favoriteSkus.add(p.sku);
                }
              }),
            ),
            onTap: () => addToCart(p),
          );
        },
      ),
    );
  }

  Widget _popularGrid(List<Product> allProducts) {
    final popular = allProducts.where((p) => favoriteSkus.contains(p.sku)).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Popular Items', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (popular.isEmpty) ...[
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text('Mark items as favorite to see them here.'),
            ),
          ] else ...[
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: popular.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 3),
              itemBuilder: (_, i) {
                final p = popular[i];
                return ElevatedButton(
                  onPressed: () => addToCart(p),
                  child: Text('${p.name} • ₹${p.price.toStringAsFixed(2)}', overflow: TextOverflow.ellipsis),
                );
              },
            ),
          ],
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
                        if (sel != null) {
                          resumeHeld(sel);
                        }
                      },
                icon: const Icon(Icons.play_circle),
                label: const Text('Resume'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: cart.isEmpty
                    ? null
                    : () {
                        setState(() => cart.clear());
                        _snack('Cart cleared');
                      },
                icon: const Icon(Icons.delete_sweep),
                label: const Text('Clear'),
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
          // Customer selection (searchable)
          StreamBuilder<List<Customer>>(
            stream: _customerStream,
            initialData: customers,
            builder: (context, snap) {
              final list = (snap.data ?? customers);
              return InkWell(
                onTap: () async {
                  final picked = await showDialog<Customer>(
                    context: context,
                    builder: (_) => _CustomerPickerDialog(
                      customers: list,
                      selected: selectedCustomer,
                    ),
                  );
                  if (picked != null) {
                    setState(() => selectedCustomer = picked);
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Customer'),
                  child: Row(
                    children: [
                      const Icon(Icons.person_outline),
                      const SizedBox(width: 8),
                      Expanded(child: Text(selectedCustomer?.name ?? walkIn.name, overflow: TextOverflow.ellipsis)),
                      const Icon(Icons.search),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          // Discount (Percent only)
          TextFormField(
            controller: discountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Discount Percent %'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          // Payments removed
          const Divider(),
          // Summary
          _kv('Subtotal', subtotal),
          _kv('Discount', -discountValue),
          const SizedBox(height: 6),
          const Text('GST Breakdown'),
          ...taxesByRate.entries.map((e) => _kv('GST ${e.key}%', e.value)),
          const Divider(),
          _kv('Grand Total', grandTotal, bold: true),
          const SizedBox(height: 10),
          // Payment mode quick buttons
          Row(children: [
            Expanded(child: _payModeButton(PaymentMode.cash, 'Cash', Icons.payments)),
            const SizedBox(width: 8),
            Expanded(child: _payModeButton(PaymentMode.upi, 'UPI', Icons.qr_code)),
            const SizedBox(width: 8),
            Expanded(child: _payModeButton(PaymentMode.card, 'Card', Icons.credit_card)),
          ]),
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
          // Removed Print/Email invoice buttons as requested
        ]),
      ),
    );
  }

  Widget _payModeButton(PaymentMode mode, String label, IconData icon) {
    final selected = selectedPaymentMode == mode;
    return OutlinedButton.icon(
      onPressed: () => setState(() => selectedPaymentMode = mode),
      icon: Icon(icon, color: selected ? Theme.of(context).colorScheme.primary : null),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08) : null,
        side: BorderSide(color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).dividerColor),
      ),
    );
  }

  // Payment split row removed

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
  final int taxPercent; // GST % from taxPct
  final String? barcode;
  final DocumentReference<Map<String, dynamic>>? ref;

  Product({
    required this.sku,
    required this.name,
    required this.price,
    required this.stock,
    required this.taxPercent,
    this.barcode,
    this.ref,
  });

  factory Product.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final priceRaw = data['unitPrice'];
    final price = priceRaw is num ? priceRaw.toDouble() : double.tryParse('$priceRaw') ?? 0.0;
    // Compute stock from batches list if provided
    int stock = 0;
    final batches = data['batches'];
    if (batches is List) {
      for (final b in batches) {
        if (b is Map && b['qty'] != null) {
          final q = b['qty'];
          if (q is num) {
            stock += q.toInt();
          } else if (q is String) {
            stock += int.tryParse(q) ?? 0;
          }
        }
      }
    }
    final taxRaw = data['taxPct'];
    final tax = taxRaw is num ? taxRaw.toInt() : int.tryParse('$taxRaw') ?? 0;
    return Product(
      sku: (data['sku'] ?? doc.id).toString(),
      name: (data['name'] ?? '').toString(),
      price: price,
      stock: stock,
      taxPercent: tax,
      barcode: (data['barcode'] ?? '').toString(),
      ref: doc.reference,
    );
  }
}

class Customer {
  final String id; // empty id for Walk-in
  final String name;
  const Customer({required this.id, required this.name});

  factory Customer.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final name = (data['name'] as String?)?.trim();
    return Customer(id: doc.id, name: (name == null || name.isEmpty) ? 'Unnamed' : name);
  }
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

// Payment split model removed

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
              subtitle: Text('Items: $count'),
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

class _CustomerPickerDialog extends StatefulWidget {
  final List<Customer> customers;
  final Customer? selected;
  const _CustomerPickerDialog({required this.customers, this.selected});

  @override
  State<_CustomerPickerDialog> createState() => _CustomerPickerDialogState();
}

class _CustomerPickerDialogState extends State<_CustomerPickerDialog> {
  final TextEditingController _search = TextEditingController();
  String get q => _search.text.trim().toLowerCase();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.customers.where((c) => q.isEmpty || c.name.toLowerCase().contains(q)).toList();
    return AlertDialog(
      title: const Text('Select Customer'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _search,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Search customers'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final c = filtered[i];
                  final selected = widget.selected?.id == c.id;
                  return ListTile(
                    title: Text(c.name),
                    trailing: selected ? const Icon(Icons.check, color: Colors.green) : null,
                    onTap: () => Navigator.pop(context, c),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, _posWalkInFallback(widget.customers)), child: const Text('Walk-in')),
      ],
    );
  }
}

Customer _posWalkInFallback(List<Customer> list) {
  return list.isNotEmpty ? list.first : Customer(id: '', name: 'Walk-in Customer');
}