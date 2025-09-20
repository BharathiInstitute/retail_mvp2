import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'invoice_models.dart';
import 'invoice_pdf.dart';
import 'file_saver_io.dart' if (dart.library.html) 'file_saver_web.dart';
import 'invoice_email_service.dart';
import 'dart:typed_data';

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
  static final Customer walkIn = Customer(id: '', name: 'Walk-in Customer');
  List<Customer> customers = [walkIn];

  final TextEditingController barcodeCtrl = TextEditingController();
  final TextEditingController searchCtrl = TextEditingController();
  final TextEditingController customerSearchCtrl = TextEditingController();

  final Map<String, CartItem> cart = {};
  final List<HeldOrder> heldOrders = [];

  // Favorites: store product SKUs marked as favorite
  final Set<String> favoriteSkus = <String>{};

  DiscountType discountType = DiscountType.none;
  final TextEditingController discountCtrl = TextEditingController(text: '0');

  Customer? selectedCustomer;

  // Selected payment mode (simple)
  PaymentMode selectedPaymentMode = PaymentMode.cash;

  // Last generated invoice snapshot (for PDF/email after checkout)
  InvoiceData? lastInvoice;

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

  @override
  void dispose() {
    barcodeCtrl.dispose();
    searchCtrl.dispose();
    customerSearchCtrl.dispose();
    discountCtrl.dispose();
    super.dispose();
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

  // Effective percent discount comes from the selected customer's discountPercent plus any manual percent entered.
  // For now we ADD them but clamp at 100%. (Alternative would be to take max; adjust if business logic changes.)
  double get _customerPercent => (selectedCustomer?.discountPercent ?? 0).clamp(0, 100);
  double get effectiveDiscountPercent => _customerPercent.clamp(0, 100);

  double get discountValue {
    switch (discountType) {
      case DiscountType.none:
        // Still allow automatic customer discount even if discountType was none previously.
        if (_customerPercent == 0) return 0;
        return (subtotal * (_customerPercent / 100)).clamp(0, subtotal);
      case DiscountType.percent:
        return (subtotal * (_customerPercent / 100)).clamp(0, subtotal);
      case DiscountType.flat:
        final val = (double.tryParse(discountCtrl.text) ?? 0).clamp(0, subtotal);
        // Apply customer percent on the remaining after flat? Simpler: treat flat as override when chosen.
        return val.toDouble();
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

  // Compute net amount eligible for rewards (exclude tax) and accrue before clearing state
  final double netEarnable = (subtotal - discountValue).clamp(0.0, double.infinity);
  _accrueRewards(netEarnable);

  // Build invoice snapshot BEFORE clearing state
    // Build invoice snapshot BEFORE clearing state
    final discounts = lineDiscounts;
    final taxes = lineTaxes;
    final taxesByRate = <int, double>{};
    for (final it in cart.values) {
      final tax = taxes[it.product.sku] ?? 0.0;
      taxesByRate.update(it.product.taxPercent, (v) => v + tax, ifAbsent: () => tax);
    }
    final lines = cart.values.map((it) {
      final price = it.product.price;
      final lineSubtotal = price * it.qty;
      final disc = discounts[it.product.sku] ?? 0.0;
      final tax = taxes[it.product.sku] ?? 0.0;
      final lineTotal = lineSubtotal - disc + tax;
      return InvoiceLine(
        sku: it.product.sku,
        name: it.product.name,
        qty: it.qty,
        unitPrice: price,
        taxPercent: it.product.taxPercent,
        lineSubtotal: lineSubtotal,
        discount: disc,
        tax: tax,
        lineTotal: lineTotal,
      );
    }).toList();
    final now = DateTime.now();
    final invoice = InvoiceData(
      invoiceNumber: invoiceNumber,
      timestamp: now,
      customerName: selectedCustomer?.name ?? 'Walk-in Customer',
      customerEmail: selectedCustomer?.email,
      customerPhone: selectedCustomer?.phone,
      customerId: selectedCustomer?.id,
      lines: lines,
      subtotal: subtotal,
      discountTotal: discountValue,
      taxTotal: totalTax,
      grandTotal: grandTotal,
      taxesByRate: taxesByRate,
      customerDiscountPercent: _customerPercent,
      paymentMode: selectedPaymentMode.label,
    );
    lastInvoice = invoice;

  final summary = _buildInvoiceSummaryFromInvoice(invoice);

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
            onPressed: () => _downloadInvoice(dialogCtx),
            icon: const Icon(Icons.download),
            label: const Text('Download'),
          ),
          TextButton.icon(
            onPressed: () {
              // Will trigger PDF generation & email/share (implemented later)
              _emailInvoice(dialogCtx);
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

<<<<<<< HEAD
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
            Future<void> _accrueRewards(double netAmount) async {
              try {
                if (netAmount <= 0) return;
                final custName = selectedCustomer?.name.trim();
                if (custName == null || custName.isEmpty || custName.toLowerCase() == 'walk-in customer') {
                  return; // skip walk-in / empty
                }
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
              } catch (_) {
                // swallow silently
              }
            }

            // Removed legacy _buildInvoiceSummary (replaced by invoice snapshot version)
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Preparing PDF...')));
      final (bytes, filename) = await _generatePdfBytes();
      final saver = PdfSaver();
      await saver.savePdf(filename, bytes);
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('PDF saved/downloaded')));
    } catch (e) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Failed to download PDF: $e')));
    }
  }

  Future<(List<int>, String)> _generatePdfBytes() async {
    final bytes = await buildInvoicePdf(lastInvoice!);
    final filename = '${lastInvoice!.invoiceNumber}.pdf';
    return (bytes, filename);
  }

  Widget _buildInvoiceSummaryFromInvoice(InvoiceData invoice) {
    final dateStr = '${invoice.timestamp.year.toString().padLeft(4, '0')}-${invoice.timestamp.month.toString().padLeft(2, '0')}-${invoice.timestamp.day.toString().padLeft(2, '0')}';
    final timeStr = '${invoice.timestamp.hour.toString().padLeft(2, '0')}:${invoice.timestamp.minute.toString().padLeft(2, '0')}:${invoice.timestamp.second.toString().padLeft(2, '0')}';
>>>>>>> c405321 (feat(pos): invoice PDF generation + email service scaffolding (storage upload + callable) and customer phone/email on invoice)
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Invoice #: ${invoice.invoiceNumber}'),
        Text('Date: $dateStr  Time: $timeStr'),
        Text('Customer: ${invoice.customerName}'),
        if ((invoice.customerEmail ?? '').isNotEmpty)
          Text('Email: ${invoice.customerEmail}'),
        if ((invoice.customerPhone ?? '').isNotEmpty)
          Text('Phone: ${invoice.customerPhone}'),
        const SizedBox(height: 8),
        const Divider(),
        ...invoice.lines.map((it) => ListTile(
              dense: true,
              title: Text('${it.name} x ${it.qty}'),
              subtitle: Text('Price: ₹${it.unitPrice.toStringAsFixed(2)}  |  Disc: ₹${it.discount.toStringAsFixed(2)}  |  Tax ${it.taxPercent}%: ₹${it.tax.toStringAsFixed(2)}'),
              trailing: Text('₹${it.lineTotal.toStringAsFixed(2)}'),
            )),
        const Divider(),
        _kv('Subtotal', invoice.subtotal),
        _kv('Discount', -invoice.discountTotal),
        _kv('Tax Total', invoice.taxTotal),
        const Divider(),
        _kv('Grand Total', invoice.grandTotal, bold: true),
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
          _SearchableCustomerDropdown(
            customersStream: _customerStream,
            initialCustomers: customers,
            selected: selectedCustomer,
            onSelected: (c) => setState(() => selectedCustomer = c),
            walkIn: walkIn,
          ),
          const SizedBox(height: 6),
          Builder(builder: (_) {
            final c = selectedCustomer;
            if (c == null || c.id.isEmpty) {
              return const SizedBox();
            }
            String planLabel = (c.status ?? 'standard');
            planLabel = planLabel[0].toUpperCase() + planLabel.substring(1);
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (c.email != null && c.email!.isNotEmpty)
                    Text(c.email!, style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 12, runSpacing: 4, children: [
                    _miniInfoChip(Icons.workspace_premium, 'Plan: $planLabel'),
                    _miniInfoChip(Icons.percent, 'Discount: ${c.discountPercent.toStringAsFixed(0)}%'),
                    _miniInfoChip(Icons.card_giftcard, 'Rewards: ${c.rewardsPoints}'),
                    _miniInfoChip(Icons.account_balance_wallet, 'Spend: ₹${c.totalSpend.toStringAsFixed(0)}'),
                  ]),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
          // Discount (Percent only)
           // Discount (Customer-based only)
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

  Widget _miniInfoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 4),
            Text(text, style: const TextStyle(fontSize: 11)),
        ],
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

class _SearchableCustomerDropdown extends StatefulWidget {
  final Stream<List<Customer>> customersStream;
  final List<Customer> initialCustomers;
  final Customer? selected;
  final ValueChanged<Customer?> onSelected;
  final Customer walkIn;
  const _SearchableCustomerDropdown({
    required this.customersStream,
    required this.initialCustomers,
    required this.selected,
    required this.onSelected,
    required this.walkIn,
  });

  @override
  State<_SearchableCustomerDropdown> createState() => _SearchableCustomerDropdownState();
}

class _SearchableCustomerDropdownState extends State<_SearchableCustomerDropdown> {
  final LayerLink _link = LayerLink();
  late TextEditingController _controller;
  late FocusNode _focusNode;
  OverlayEntry? _entry;
  List<Customer> _all = [];
  List<Customer> _filtered = [];
  Customer? _selected;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
    _selected = widget.selected ?? widget.walkIn;
    _all = widget.initialCustomers;
    _filtered = _all;
    // Listen to stream
    widget.customersStream.listen((data) {
      setState(() {
        _all = data;
        _applyFilter();
      });
    });
  }

  void _applyFilter() {
    final q = _controller.text.trim().toLowerCase();
    if (q.isEmpty) {
      _filtered = _all;
    } else {
      _filtered = _all.where((c) => c.name.toLowerCase().contains(q) || (c.email ?? '').toLowerCase().contains(q)).toList();
      if (!_filtered.any((c) => c.id.isEmpty)) {
        // keep walk-in on top
        final w = _all.firstWhere((c) => c.id.isEmpty, orElse: () => widget.walkIn);
        _filtered.insert(0, w);
      }
    }
    // Request overlay rebuild
    _entry?.markNeedsBuild();
  }

  @override
  void dispose() {
    _entry?.remove();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _openOverlay() {
    _closeOverlay();
    _entry = OverlayEntry(builder: (context) {
      return Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _closeOverlay,
          child: Stack(children: [
            CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              offset: const Offset(0, 48),
              child: Material(
                elevation: 4,
                clipBehavior: Clip.antiAlias,
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320, minWidth: 260),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        child: TextField(
                          controller: _controller,
                          autofocus: true,
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'Search customers',
                            prefixIcon: const Icon(Icons.search, size: 18),
                            suffixIcon: _controller.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () {
                                      _controller.clear();
                                      setState(() {
                                        _applyFilter();
                                      });
                                    },
                                  )
                                : null,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          onChanged: (_) => setState(() => _applyFilter()),
                          onSubmitted: (_) {
                            if (_filtered.length == 1) _select(_filtered.first);
                          },
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: _filtered.isEmpty
                            ? const Center(child: Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Text('No customers')))
                            : ListView.separated(
                                padding: EdgeInsets.zero,
                                itemCount: _filtered.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (_, i) {
                                  final c = _filtered[i];
                                  final isSelected = _selected?.id == c.id;
                                  final isWalkIn = c.id.isEmpty;
                                  final planLabel = (c.status ?? 'standard');
                                  return InkWell(
                                    onTap: () => _select(c),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(Icons.person_outline, size: 16, color: isSelected ? Theme.of(context).colorScheme.primary : null),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  c.name,
                                                  style: TextStyle(fontWeight: FontWeight.w600, color: isSelected ? Theme.of(context).colorScheme.primary : null),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (!isWalkIn && c.discountPercent > 0)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                                                    borderRadius: BorderRadius.circular(12),
                                                  ),
                                                  child: Text('${c.discountPercent.toStringAsFixed(0)}% off', style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.primary)),
                                                ),
                                            ],
                                          ),
                                          if (!isWalkIn) ...[
                                            const SizedBox(height: 2),
                                            Row(
                                              children: [
                                                if (c.email != null && c.email!.isNotEmpty)
                                                  Expanded(
                                                    child: Text(
                                                      c.email!,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(fontSize: 11),
                                                    ),
                                                  ),
                                                const SizedBox(width: 6),
                                                Text(planLabel, style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                            Row(
                                              children: [
                                                Icon(Icons.card_giftcard, size: 12, color: Theme.of(context).iconTheme.color),
                                                const SizedBox(width: 2),
                                                Text('${c.rewardsPoints}', style: const TextStyle(fontSize: 11)),
                                                const SizedBox(width: 10),
                                                Icon(Icons.account_balance_wallet, size: 12, color: Theme.of(context).iconTheme.color),
                                                const SizedBox(width: 2),
                                                Text('₹${c.totalSpend.toStringAsFixed(0)}', style: const TextStyle(fontSize: 11)),
                                              ],
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ]),
        ),
      );
    });
    Overlay.of(context).insert(_entry!);
  }

  void _closeOverlay() {
    _entry?.remove();
    _entry = null;
  }

  void _select(Customer c) {
    setState(() => _selected = c);
    widget.onSelected(c);
    _closeOverlay();
  }

  @override
  Widget build(BuildContext context) {
    final display = _selected ?? widget.walkIn;
    final isWalkIn = display.id.isEmpty;
    final discount = (!isWalkIn && display.discountPercent > 0) ? ' (${display.discountPercent.toStringAsFixed(0)}% off)' : '';
    final plan = (!isWalkIn && (display.status ?? '').isNotEmpty)
        ? ' • ${(display.status![0].toUpperCase() + display.status!.substring(1))}'
        : '';
    return CompositedTransformTarget(
      link: _link,
      child: GestureDetector(
        onTap: _openOverlay,
        child: InputDecorator(
          decoration: const InputDecoration(labelText: 'Customer'),
          isEmpty: false,
          child: Row(
            children: [
              const Icon(Icons.person_outline, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  display.name + discount + plan,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
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
  final String? email;
  final String? phone;
  final String? status; // loyalty tier e.g. bronze/silver/gold
  final double totalSpend;
  final int rewardsPoints;
  final double discountPercent; // derived suggested discount

  Customer({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    this.status,
    this.totalSpend = 0.0,
    this.rewardsPoints = 0,
    this.discountPercent = 0.0,
  });

  factory Customer.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    String name = (data['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) name = 'Unnamed';
    final tier = (data['status'] as String?)?.toLowerCase();
    final spendRaw = data['totalSpend'];
    final spend = spendRaw is num ? spendRaw.toDouble() : double.tryParse('$spendRaw') ?? 0.0;
    // Simple derived rules for discount & rewards (can adjust later)
    double discount;
    switch (tier) {
      case 'gold':
        discount = 10;
        break;
      case 'silver':
        discount = 5;
        break;
      case 'bronze':
        discount = 2;
        break;
      default:
        discount = 0;
    }
    final rewards = (spend / 100).floor(); // 1 point per ₹100 spent
    return Customer(
      id: doc.id,
      name: name,
      email: (data['email'] as String?)?.trim(),
      phone: (data['phone'] as String?)?.trim(),
      status: tier,
      totalSpend: spend,
      rewardsPoints: rewards,
      discountPercent: discount,
    );
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

