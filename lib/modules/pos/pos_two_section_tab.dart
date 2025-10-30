import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'pos.dart';
import 'pos_search_scan_fav_fixed.dart';
import 'device_class_icon.dart';
import '../inventory/Products/inventory_repository.dart';

/// A simplified POS screen for the tab view with two sections:
/// - Left: Search + Products list/grid
/// - Right: Cart (top, flexible) + Checkout (bottom, fixed scrollable card)
/// This screen is UI-focused and reuses existing widgets without changing global behavior.
class PosTwoSectionTabPage extends StatefulWidget {
  const PosTwoSectionTabPage({super.key});
  @override
  State<PosTwoSectionTabPage> createState() => _PosTwoSectionTabPageState();
}

class _PosTwoSectionTabPageState extends State<PosTwoSectionTabPage> {
  // --- Data state (subset of PosPage) ---
  final InventoryRepository _inventoryRepo = InventoryRepository();
  final TextEditingController barcodeCtrl = TextEditingController();
  final TextEditingController searchCtrl = TextEditingController();
  final TextEditingController _customerSearchCtrl = TextEditingController();
  List<Product> _cacheProducts = const [];
  final Set<String> _favoriteSkus = <String>{};
  bool _showFavoritesOnly = false;
  bool _useGrid = false;

  // Customers
  static final Customer walkIn = Customer(id: '', name: 'Walk-in Customer');
  List<Customer> customers = [walkIn];
  Customer? selectedCustomer;

  // Cart
  final Map<String, CartItem> cart = {};
  final List<HeldOrder> heldOrders = [];
  PaymentMode selectedPaymentMode = PaymentMode.cash;

  // Loyalty
  final TextEditingController _redeemPointsCtrl = TextEditingController(text: '0');
  double _availablePoints = 0; // fetched when customer changes

  @override
  void initState() {
    super.initState();
    _loadCustomersOnce();
    selectedCustomer = customers.first;
    _customerSearchCtrl.text = selectedCustomer?.name ?? '';
  }

  @override
  void dispose() {
    barcodeCtrl.dispose();
    searchCtrl.dispose();
    _customerSearchCtrl.dispose();
    _redeemPointsCtrl.dispose();
    super.dispose();
  }

  // --- Streams & data helpers ---
  Stream<List<Product>> get _productStream => _inventoryRepo.streamProducts().map((docs) {
        return docs
            .map((d) => Product(
                  sku: d.sku,
                  name: d.name,
                  price: d.unitPrice,
                  stock: d.totalStock,
                  taxPercent: (d.taxPct ?? 0).toInt(),
                  barcode: d.barcode.isEmpty ? null : d.barcode,
                  ref: FirebaseFirestore.instance.collection('inventory').doc(d.sku),
                ))
            .toList();
      });

  Stream<List<Customer>> get _customerStream => FirebaseFirestore.instance
      .collection('customers')
      .snapshots()
      .map((s) {
        final list = s.docs.map((d) => Customer.fromDoc(d)).toList();
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        return list;
      });

  Future<void> _loadCustomersOnce() async {
    try {
      final first = await _customerStream.first;
      if (!mounted) return;
      setState(() {
        customers = [walkIn, ...first.where((c) => c.id != walkIn.id)];
        selectedCustomer = customers.first;
        _availablePoints = (selectedCustomer?.rewardsPoints ?? 0).toDouble();
      });
    } catch (_) {}
  }

  // (inline customer selection handled via lambdas; helper removed)

  // --- Cart helpers ---
  void addToCart(Product p) {
    cart.update(p.sku, (ex) => ex.copyWith(qty: ex.qty + 1), ifAbsent: () => CartItem(product: p, qty: 1));
    setState(() {});
  }

  void changeQty(String sku, int delta) {
    final it = cart[sku];
    if (it == null) return;
    final nq = it.qty + delta;
    if (nq <= 0) {
      cart.remove(sku);
    } else {
      cart[sku] = it.copyWith(qty: nq);
    }
    setState(() {});
  }

  void removeFromCart(String sku) {
    cart.remove(sku);
    setState(() {});
  }

  // Hold/Resume/Clear helpers
  void _holdCart() {
    if (cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cart is empty')));
      return;
    }
    final snapshot = HeldOrder(
      id: 'HLD-${heldOrders.length + 1}',
      timestamp: DateTime.now(),
      items: cart.values.map((e) => e.copy()).toList(),
      discountType: DiscountType.percent,
      discountValueText: (selectedCustomer?.discountPercent ?? 0).toStringAsFixed(0),
    );
    heldOrders.add(snapshot);
    cart.clear();
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Order ${snapshot.id} held')));
  }

  void _resumeHeld(HeldOrder order) {
    cart.clear();
    for (final it in order.items) {
      cart[it.product.sku] = it.copy();
    }
    heldOrders.removeWhere((o) => o.id == order.id);
    setState(() {});
  }

  Future<HeldOrder?> _pickHeldOrder(BuildContext ctx) async {
    if (heldOrders.isEmpty) return null;
    return showDialog<HeldOrder>(
      context: ctx,
      builder: (dCtx) {
        return AlertDialog(
          title: const Text('Held Orders'),
          content: SizedBox(
            width: 360,
            height: 300,
            child: ListView.separated(
              itemCount: heldOrders.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final o = heldOrders[i];
                final t = '${o.timestamp.hour.toString().padLeft(2, '0')}:${o.timestamp.minute.toString().padLeft(2, '0')}';
                final count = o.items.fold<int>(0, (s, it) => s + it.qty);
                return ListTile(
                  title: Text('${o.id} • $t'),
                  subtitle: Text('Items: $count'),
                  onTap: () => Navigator.of(dCtx).pop(o),
                );
              },
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.of(dCtx).pop(), child: const Text('Close'))],
        );
      },
    ).then((sel) {
      if (sel != null) _resumeHeld(sel);
      return sel;
    });
  }

  void _clearCart() {
    if (cart.isEmpty) return;
    cart.clear();
    setState(() {});
  }

  // --- Totals & taxes (simple, similar to PosPage) ---
  double get subtotal => cart.values.fold(0.0, (s, it) => s + it.product.price * it.qty);
  double get _customerPercent => selectedCustomer?.discountPercent ?? 0;
  double get discountValue => (subtotal * (_customerPercent / 100)).clamp(0, subtotal);

  Map<String, double> get lineDiscounts {
    if (subtotal == 0) return {};
    final map = <String, double>{};
    for (final it in cart.values) {
      final line = it.product.price * it.qty;
      map[it.product.sku] = (line / subtotal) * discountValue;
    }
    return map;
  }

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
  double get redeemedPoints => double.tryParse(_redeemPointsCtrl.text) != null ? double.parse(_redeemPointsCtrl.text) : 0;
  double get redeemValue => (redeemedPoints.clamp(0, _availablePoints));
  double get payableTotal => (grandTotal - redeemValue).clamp(0, double.infinity);

  List<Customer> _buildCustomerSuggestions() {
    final q = _customerSearchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return const <Customer>[];
    final list = customers.where((c) => c.name.toLowerCase().contains(q)).toList();
    return list.take(8).toList();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final leftWidth = constraints.maxWidth * 0.52; // left section share
        final rightMin = 320.0;
        return Stack(children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            SizedBox(
              width: leftWidth.clamp(360.0, 560.0),
              child: StreamBuilder<List<Product>>(
                stream: _productStream,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(child: Text('Error: ${snap.error}'));
                  }
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final products = snap.data!;
                  _cacheProducts = products;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PosSearchAndScanCard(
                        barcodeController: barcodeCtrl,
                        searchController: searchCtrl,
                        customerSearchController: _customerSearchCtrl,
                        customerSuggestions: _buildCustomerSuggestions(),
                        selectedCustomerName: selectedCustomer?.name,
                        onCustomerSelected: (c) {
                          setState(() {
                            selectedCustomer = c.id.isEmpty ? walkIn : c;
                            _availablePoints = (selectedCustomer?.rewardsPoints ?? 0).toDouble();
                            _customerSearchCtrl.text = selectedCustomer?.name ?? '';
                          });
                        },
                        onCustomerQueryChanged: () => setState(() {}),
                        barcodeTrailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          Tooltip(
                            message: 'All products',
                            child: IconButton(
                              icon: Icon(Icons.list_alt, color: !_showFavoritesOnly ? Theme.of(context).colorScheme.primary : null),
                              onPressed: () {
                                setState(() {
                                  _showFavoritesOnly = false;
                                  searchCtrl.clear();
                                });
                              },
                            ),
                          ),
                          Tooltip(
                            message: _useGrid ? 'Show list' : 'Show grid',
                            child: IconButton(
                              icon: Icon(_useGrid ? Icons.view_list : Icons.grid_view),
                              onPressed: () {
                                setState(() { _useGrid = !_useGrid; });
                              },
                            ),
                          ),
                          Tooltip(
                            message: 'Favorites',
                            child: IconButton(
                              icon: Icon(_favoriteSkus.isEmpty ? Icons.star_border : Icons.star, color: _showFavoritesOnly ? Theme.of(context).colorScheme.primary : null),
                              onPressed: () {
                                setState(() {
                                  _showFavoritesOnly = true;
                                  // keep search; user can search within favorites
                                });
                              },
                            ),
                          ),
                        ]),
                        scannerActive: false,
                        scannerConnected: false,
                        onScannerToggle: (_) {},
                        onBarcodeSubmitted: _onUnifiedSubmit,
                        onSearchChanged: () => setState(() {}),
                        customerSelector: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Customer details',
                              icon: const Icon(Icons.person_outline),
                              onPressed: _showCustomerDetailsSheet,
                            ),
                            IconButton(
                              tooltip: 'Add customer',
                              icon: const Icon(Icons.person_add_alt_1_outlined),
                              onPressed: _showAddCustomerDialog,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: _useGrid
                            ? PosProductGrid(
                                products: _filteredProducts(products),
                                favoriteSkus: _favoriteSkus,
                                onAdd: addToCart,
                                onToggleFavorite: (p) {
                                  setState(() {
                                    if (_favoriteSkus.contains(p.sku)) {
                                      _favoriteSkus.remove(p.sku);
                                    } else {
                                      _favoriteSkus.add(p.sku);
                                    }
                                  });
                                },
                              )
                            : PosProductList(
                                products: _filteredProducts(products),
                                favoriteSkus: _favoriteSkus,
                                onAdd: addToCart,
                                onToggleFavorite: (p) {
                                  setState(() {
                                    if (_favoriteSkus.contains(p.sku)) {
                                      _favoriteSkus.remove(p.sku);
                                    } else {
                                      _favoriteSkus.add(p.sku);
                                    }
                                  });
                                },
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            // Right column: single combined card (Cart on top, Checkout below)
            Expanded(
              child: Align(
                alignment: Alignment.topRight,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: CombinedCartCheckoutCard(
                    minWidth: rightMin,
                    cart: cart,
                    heldOrders: heldOrders,
                    onHold: _holdCart,
                    onResumeSelect: _pickHeldOrder,
                    onClear: _clearCart,
                    customersStream: _customerStream,
                    initialCustomers: customers,
                    selectedCustomer: selectedCustomer,
                    onCustomerSelected: (c) {
                      setState(() {
                        selectedCustomer = c ?? walkIn;
                        _availablePoints = (selectedCustomer?.rewardsPoints ?? 0).toDouble();
                        _customerSearchCtrl.text = selectedCustomer?.name ?? '';
                      });
                    },
                    onChangeQty: (sku, d) => changeQty(sku, d),
                    onRemove: (sku) => removeFromCart(sku),
                    subtotal: subtotal,
                    discount: discountValue,
                    tax: totalTax,
                    total: payableTotal,
                    onSelectPayment: (mode) {
                      setState(() {
                        selectedPaymentMode = mode;
                      });
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
          const Positioned(top: 4, right: 4, child: DeviceClassIcon()),
        ]);
      },
    );
  }

  List<Product> _filteredProducts(List<Product> products) {
    Iterable<Product> list = products;
    if (_showFavoritesOnly) {
      list = list.where((p) => _favoriteSkus.contains(p.sku));
    }
    final q = searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return list.toList();
    return list.where((p) =>
        p.sku.toLowerCase().contains(q) ||
        p.name.toLowerCase().contains(q) ||
        (p.barcode ?? '').toLowerCase().contains(q)).toList();
  }

  void _onUnifiedSubmit() {
    final code = searchCtrl.text.trim();
    if (code.isEmpty) return;
    Product? match;
    for (final p in _cacheProducts) {
      if (p.sku.toLowerCase() == code.toLowerCase() ||
          (p.barcode != null && p.barcode!.toLowerCase() == code.toLowerCase())) {
        match = p;
        break;
      }
    }
    if (match != null) {
      addToCart(match);
      searchCtrl.clear();
      setState(() {});
    } else {
      // Keep text for filtering; optionally provide feedback
      setState(() {});
    }
  }

  Future<void> _showCustomerDetailsSheet() async {
    final c = selectedCustomer ?? walkIn;
    final searchCtrl = TextEditingController();
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final tt = Theme.of(ctx).textTheme;
        return SafeArea(
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              final maxH = MediaQuery.of(ctx).size.height * 0.9;
              final bottomPad = MediaQuery.of(ctx).viewInsets.bottom + MediaQuery.of(ctx).padding.bottom;
              return ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxH),
                child: StatefulBuilder(
                  builder: (ctx, setLocal) {
                    return SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPad),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Customers', style: tt.titleMedium),
                          const SizedBox(height: 8),
                          TextField(
                            controller: searchCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Search customers',
                              prefixIcon: Icon(Icons.search),
                            ),
                            onChanged: (_) { setLocal((){}); },
                          ),
                          const SizedBox(height: 8),
                          // Live list of customers (tap to select)
                          StreamBuilder<List<Customer>>(
                            stream: _customerStream,
                            initialData: customers,
                            builder: (ctx, snap) {
                              final all = [
                                const Customer(id: '', name: 'Walk-in Customer'),
                                ...((snap.data ?? const <Customer>[])
                                    .where((x) => x.id.isNotEmpty))
                              ];
                              final q = searchCtrl.text.trim().toLowerCase();
                              if (q.isEmpty) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                                  child: Text('Start typing to search customers', style: Theme.of(ctx).textTheme.bodySmall),
                                );
                              }
                              final list = all.where((c) => c.name.toLowerCase().contains(q)).toList();
                              return Column(
                                children: [
                                  for (final cust in list)
                                    ListTile(
                                      dense: true,
                                      leading: const Icon(Icons.person_outline),
                                      title: Text(cust.name, overflow: TextOverflow.ellipsis),
                                      trailing: (selectedCustomer?.id == cust.id)
                                          ? const Icon(Icons.check, color: Colors.green)
                                          : null,
                                      onTap: () {
                                        // Update app state
                                        setState(() {
                                          selectedCustomer = cust;
                                          _availablePoints = (cust.rewardsPoints).toDouble();
                                          _customerSearchCtrl.text = cust.name;
                                        });
                                        // Also refresh local UI
                                        setLocal((){});
                                      },
                                    ),
                                ],
                              );
                            },
                          ),
                          const Divider(),
                          Text('Selected', style: tt.titleSmall),
                          const SizedBox(height: 6),
                          Row(children: [
                            const Icon(Icons.person_outline),
                            const SizedBox(width: 8),
                            Expanded(child: Text((selectedCustomer ?? c).name, style: tt.titleSmall)),
                          ]),
                          const SizedBox(height: 6),
                          _infoRow(icon: Icons.phone_iphone, label: 'Phone', value: (((selectedCustomer ?? c).phone) ?? '').isEmpty ? '—' : ((selectedCustomer ?? c).phone!)),
                          _infoRow(icon: Icons.email_outlined, label: 'Email', value: (((selectedCustomer ?? c).email) ?? '').isEmpty ? '—' : ((selectedCustomer ?? c).email!)),
                          _infoRow(icon: Icons.stars_outlined, label: 'Status', value: ((selectedCustomer ?? c).status ?? 'walk-in').toString()),
                          _infoRow(icon: Icons.savings_outlined, label: 'Points', value: _availablePoints.toStringAsFixed(0)),
                          _infoRow(icon: Icons.account_balance_wallet_outlined, label: 'Credit', value: '₹${((selectedCustomer ?? c).creditBalance).toStringAsFixed(2)}'),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Done'),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
        );
      },
    );
    searchCtrl.dispose();
  }

  Widget _infoRow({required IconData icon, required String label, required String value}) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(children: [
        Icon(icon, size: 18, color: cs.primary),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant))),
        Text(value, style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Future<void> _showAddCustomerDialog() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Customer'),
        content: Form(
          key: formKey,
          child: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Name', prefixIcon: Icon(Icons.person_outline)),
                  validator: (v) => (v==null || v.trim().isEmpty) ? 'Enter name' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(labelText: 'Phone', prefixIcon: Icon(Icons.phone_iphone)),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
                  keyboardType: TextInputType.emailAddress,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (!(formKey.currentState?.validate() ?? false)) return;
              try {
                final doc = await FirebaseFirestore.instance.collection('customers').add({
                  'name': nameCtrl.text.trim(),
                  'phone': phoneCtrl.text.trim(),
                  'email': emailCtrl.text.trim(),
                  'loyaltyPoints': 0,
                  'totalSpend': 0,
                  'status': 'walk-in',
                  'discountPercent': 0,
                  'creditBalance': 0,
                  'createdAt': FieldValue.serverTimestamp(),
                });
                if (!mounted) return;
                setState(() {
                  final newCust = Customer(
                    id: doc.id,
                    name: nameCtrl.text.trim(),
                    phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
                    email: emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
                    status: 'walk-in',
                    discountPercent: 0,
                    totalSpend: 0,
                    creditBalance: 0,
                  );
                  customers = [for (final c in customers) c, newCust];
                  selectedCustomer = newCust;
                  _availablePoints = 0;
                  _customerSearchCtrl.text = newCust.name;
                });
                if (!ctx.mounted) return;
                Navigator.pop(ctx, true);
              } catch (_) {
                if (!ctx.mounted) return;
                Navigator.pop(ctx, false);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    nameCtrl.dispose();
    phoneCtrl.dispose();
    emailCtrl.dispose();
  }
}

// Combined card for Tab: Cart (top) and Checkout (bottom)
class CombinedCartCheckoutCard extends StatelessWidget {
  final double minWidth;
  final Map<String, CartItem> cart;
  final List<HeldOrder> heldOrders;
  final VoidCallback onHold;
  final Future<HeldOrder?> Function(BuildContext) onResumeSelect;
  final VoidCallback onClear;
  final Stream<List<Customer>> customersStream;
  final List<Customer> initialCustomers;
  final Customer? selectedCustomer;
  final ValueChanged<Customer?> onCustomerSelected;
  final void Function(String sku, int delta) onChangeQty;
  final void Function(String sku) onRemove;
  final double subtotal;
  final double discount;
  final double tax;
  final double total;
  final ValueChanged<PaymentMode> onSelectPayment;
  // When true, render a compact bottom bar with a Cart icon that opens details in a sheet.
  final bool compact;
  // Optional: show a customer icon near total that triggers a customer sheet/selector.
  final VoidCallback? onShowCustomers;

  const CombinedCartCheckoutCard({
    super.key,
    required this.minWidth,
    required this.cart,
    required this.heldOrders,
    required this.onHold,
    required this.onResumeSelect,
    required this.onClear,
    required this.customersStream,
    required this.initialCustomers,
    required this.selectedCustomer,
    required this.onCustomerSelected,
    required this.onChangeQty,
    required this.onRemove,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    required this.onSelectPayment,
    this.compact = false,
    this.onShowCustomers,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: minWidth),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: compact
              ? _buildCompact(context, cs)
              : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Cart header with quick actions
              Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Text(
                  'Cart',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Tooltip(
                  message: 'Hold',
                  child: IconButton(onPressed: onHold, icon: const Icon(Icons.pause_circle)),
                ),
                Tooltip(
                  message: 'Resume',
                  child: IconButton(
                    onPressed: cart.isEmpty && heldOrders.isEmpty
                        ? null
                        : () async { await onResumeSelect(context); },
                    icon: const Icon(Icons.play_circle),
                  ),
                ),
                Tooltip(
                  message: 'Clear',
                  child: IconButton(onPressed: cart.isEmpty ? null : onClear, icon: const Icon(Icons.delete_sweep)),
                ),
              ]),
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
                            title: Text(item.product.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                            // Hide duplicate unit price and GST% under the product title in tab cart items
                            subtitle: null,
                            // Remove the leading minus-in-circle icon per request
                            leading: null,
                            trailing: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 180),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.remove),
                                    onPressed: () => onChangeQty(item.product.sku, -1),
                                    padding: EdgeInsets.zero,
                                    visualDensity: VisualDensity.compact,
                                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                  ),
                                  const SizedBox(width: 2),
                                  Text(item.qty.toString()),
                                  const SizedBox(width: 2),
                                  IconButton(
                                    icon: const Icon(Icons.add),
                                    onPressed: () => onChangeQty(item.product.sku, 1),
                                    padding: EdgeInsets.zero,
                                    visualDensity: VisualDensity.compact,
                                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(child: Text('₹${line.toStringAsFixed(2)}', overflow: TextOverflow.ellipsis, softWrap: false)),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    icon: const Icon(Icons.close),
                                    onPressed: () => onRemove(item.product.sku),
                                    padding: EdgeInsets.zero,
                                    visualDensity: VisualDensity.compact,
                                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 8),
              Divider(height: 1, color: cs.outlineVariant),
              const SizedBox(height: 6),
              // Bottom summary bar (neutral background)
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    // Left: Pay button
                    FilledButton(
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
                      onPressed: cart.isEmpty ? null : () => _openPaymentSheet(context),
                      child: const Text('Pay'),
                    ),
                    const SizedBox(width: 10),
                    // Middle: items and discount summary
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${_itemsCount()} items',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          Text(
                            'Disc. ₹${discount.toStringAsFixed(2)}',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                    // Right: total and tax (with optional customer icon)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (onShowCustomers != null) ...[
                              IconButton(
                                tooltip: 'Customer',
                                icon: const Icon(Icons.person_outline),
                                onPressed: onShowCustomers,
                                visualDensity: VisualDensity.compact,
                              ),
                              const SizedBox(width: 6),
                            ],
                            Text(
                              '₹${total.toStringAsFixed(2)}',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                        Text(
                          'VAT ₹${tax.toStringAsFixed(2)}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompact(BuildContext context, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Only the summary bar with Pay and Cart icon
        Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            children: [
              // Pay button
              FilledButton(
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6)),
                onPressed: cart.isEmpty ? null : () => _openPaymentSheet(context),
                child: const Text('Pay'),
              ),
              const SizedBox(width: 8),
              // Cart icon to open details
              IconButton(
                tooltip: 'Cart',
                icon: const Icon(Icons.shopping_cart_outlined),
                onPressed: () => _openCartDetailsSheet(context),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${_itemsCount()} items', style: Theme.of(context).textTheme.bodyMedium),
                    Text('Disc. ₹${discount.toStringAsFixed(2)}', style: Theme.of(context).textTheme.labelSmall),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (onShowCustomers != null) ...[
                        IconButton(
                          tooltip: 'Customer',
                          icon: const Icon(Icons.person_outline),
                          onPressed: onShowCustomers,
                          visualDensity: VisualDensity.compact,
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text('₹${total.toStringAsFixed(2)}', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    ],
                  ),
                  Text('VAT ₹${tax.toStringAsFixed(2)}', style: Theme.of(context).textTheme.labelSmall),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openCartDetailsSheet(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final maxH = MediaQuery.of(ctx).size.height * 0.85;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: StatefulBuilder(
              builder: (ctx, setLocal) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
                      child: Row(
                        children: [
                          Text('Cart', style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                          const Spacer(),
                          IconButton(
                            tooltip: 'Hold',
                            onPressed: onHold,
                            icon: const Icon(Icons.pause_circle),
                          ),
                          IconButton(
                            tooltip: 'Resume',
                            onPressed: cart.isEmpty && heldOrders.isEmpty
                                ? null
                                : () async { await onResumeSelect(ctx); setLocal((){}); },
                            icon: const Icon(Icons.play_circle),
                          ),
                          IconButton(
                            tooltip: 'Clear',
                            onPressed: cart.isEmpty ? null : () { onClear(); setLocal((){}); },
                            icon: const Icon(Icons.delete_sweep),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: () => Navigator.of(ctx).maybePop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: cart.isEmpty
                          ? const Center(child: Text('Cart is empty'))
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: cart.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (_, i) {
                                final item = cart.values.elementAt(i);
                                final line = item.product.price * item.qty;
                                return ListTile(
                                  title: Text(item.product.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  trailing: ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 200),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.remove),
                                          onPressed: () { onChangeQty(item.product.sku, -1); setLocal((){}); },
                                        ),
                                        Text(item.qty.toString()),
                                        IconButton(
                                          icon: const Icon(Icons.add),
                                          onPressed: () { onChangeQty(item.product.sku, 1); setLocal((){}); },
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(child: Text('₹${line.toStringAsFixed(2)}', overflow: TextOverflow.ellipsis, softWrap: false)),
                                        const SizedBox(width: 4),
                                        IconButton(
                                          icon: const Icon(Icons.close),
                                          onPressed: () { onRemove(item.product.sku); setLocal((){}); },
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('${_itemsCount()} items', style: Theme.of(ctx).textTheme.bodyMedium),
                                Text('Disc. ₹${discount.toStringAsFixed(2)}', style: Theme.of(ctx).textTheme.labelSmall),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('₹${total.toStringAsFixed(2)}', style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                              Text('VAT ₹${tax.toStringAsFixed(2)}', style: Theme.of(ctx).textTheme.labelSmall),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _openPaymentSheet(BuildContext context) async {
    var selected = PaymentMode.cash;
    await showModalBottomSheet<PaymentMode>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final maxH = MediaQuery.of(ctx).size.height * 0.9;
          Widget pmButton(PaymentMode m, String label, IconData icon) {
            final isSel = selected == m;
            final child = Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon), const SizedBox(width: 6), Text(label)]);
            return isSel
                ? FilledButton(onPressed: () => setLocal(() => selected = m), child: child)
                : OutlinedButton(onPressed: () => setLocal(() => selected = m), child: child);
          }
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxH),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom + MediaQuery.of(ctx).padding.bottom),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Close button on top-right
                    Row(
                      children: [
                        const Spacer(),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.of(ctx).maybePop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const Divider(),
                    if (selectedCustomer != null) ...[
                      Text('Customer', style: Theme.of(ctx).textTheme.titleMedium),
                      const SizedBox(height: 6),
                      Text(selectedCustomer!.name, style: Theme.of(ctx).textTheme.bodyMedium),
                      if ((selectedCustomer!.phone ?? '').isNotEmpty)
                        Text('Phone: ${selectedCustomer!.phone!}', style: Theme.of(ctx).textTheme.labelSmall),
                      if ((selectedCustomer!.email ?? '').isNotEmpty)
                        Text('Email: ${selectedCustomer!.email!}', style: Theme.of(ctx).textTheme.labelSmall),
                      const Divider(),
                    ],
                    Text('Bill', style: Theme.of(ctx).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    ..._buildBillLines(ctx),
                    const Divider(),
                    _kvRow(ctx, 'Subtotal', subtotal),
                    _kvRow(ctx, 'Discount', -discount),
                    _kvRow(ctx, 'Tax', tax),
                    const SizedBox(height: 6),
                    _kvRow(ctx, 'Total', total, bold: true),
                    const SizedBox(height: 16),
                    Text('Payment Method', style: Theme.of(ctx).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        pmButton(PaymentMode.cash, 'Cash', Icons.payments),
                        pmButton(PaymentMode.upi, 'UPI', Icons.qr_code),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () { Navigator.pop(ctx); onSelectPayment(selected); },
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: Text('Pay  ₹${total.toStringAsFixed(2)}'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildBillLines(BuildContext context) {
    final items = cart.values.toList();
    if (items.isEmpty) {
      return [const Text('No items')];
    }
    final widgets = <Widget>[];
    // compute line shares for discount
    final sub = subtotal <= 0 ? 1 : subtotal;
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      final lineSub = it.product.price * it.qty;
      final discShare = (discount > 0) ? (lineSub / sub) * discount : 0;
      final net = (lineSub - discShare).clamp(0, double.infinity);
      final taxAmt = net * (it.product.taxPercent / 100);
      final lineTotal = net + taxAmt;
      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text(it.product.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Text('₹${lineTotal.toStringAsFixed(2)}', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '${it.qty} NOS @ ₹${it.product.price.toStringAsFixed(2)}   •   Discount ₹${discShare.toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.labelSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text('VAT ${it.product.taxPercent.toStringAsFixed(0)}%', style: Theme.of(context).textTheme.labelSmall),
                ],
              ),
            ],
          ),
        ),
      );
      if (i != items.length - 1) widgets.add(const Divider(height: 1));
    }
    return widgets;
  }

  Widget _kvRow(BuildContext context, String label, double value, {bool bold = false}) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text('₹${value.toStringAsFixed(2)}', style: style)],
      ),
    );
  }

  int _itemsCount() {
    int count = 0;
    for (final it in cart.values) {
      count += it.qty;
    }
    return count;
  }
}

// Compact customers dropdown to be placed inline beside the barcode/SKU field
// (Inline customer dropdown removed; replaced with icon actions near Barcode field.)

