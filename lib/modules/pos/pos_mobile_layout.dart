import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retail_mvp2/core/store_scoped_refs.dart';
import 'package:retail_mvp2/modules/stores/providers.dart';
import 'pos.dart';
import 'pos_search_scan_fav_fixed.dart';
import 'pos_two_section_tab.dart';
import 'device_class_icon.dart';
import '../inventory/Products/inventory_repository.dart';

/// Mobile-friendly POS: vertical stack with
/// - Customer + Barcode/Search on top
/// - Products list (fills available space)
/// - Pay/Cart card below the list
class PosMobilePage extends StatefulWidget {
  const PosMobilePage({super.key});
  @override
  State<PosMobilePage> createState() => _PosMobilePageState();
}

class _PosMobilePageState extends State<PosMobilePage> {
  // Data
  final InventoryRepository _inventoryRepo = InventoryRepository();
  final TextEditingController barcodeCtrl = TextEditingController();
  final TextEditingController searchCtrl = TextEditingController();
  final TextEditingController _customerSearchCtrl = TextEditingController();
  List<Product> _cacheProducts = const [];

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
  double _availablePoints = 0;

  // Favorites and filters
  final Set<String> _favoriteSkus = <String>{};
  bool _showFavoritesOnly = false;
  bool _useGrid = false;

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

  // Streams
  Stream<List<Product>> _productStream(String storeId) => _inventoryRepo.streamProducts(storeId: storeId).map((docs) {
        return docs
            .map((d) => Product(
                  sku: d.sku,
                  name: d.name,
                  price: d.unitPrice,
                  stock: d.totalStock,
                  taxPercent: (d.taxPct ?? 0).toInt(),
                  barcode: d.barcode.isEmpty ? null : d.barcode,
                  ref: StoreRefs.of(storeId).products().doc(d.sku),
                ))
            .toList();
      });

  Stream<List<Customer>> _customerStream(String storeId) => StoreRefs.of(storeId)
      .customers()
      .snapshots()
      .map((s) {
        final list = s.docs.map((d) => Customer.fromDoc(d)).toList();
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        return list;
      });

  Future<void> _loadCustomersOnce() async {
    try {
      final sel = ProviderScope.containerOf(context).read(selectedStoreIdProvider);
      if (sel == null) return;
      final first = await _customerStream(sel).first;
      if (!mounted) return;
      setState(() {
        customers = [walkIn, ...first.where((c) => c.id != walkIn.id)];
        selectedCustomer = customers.first;
        _availablePoints = (selectedCustomer?.rewardsPoints ?? 0).toDouble();
      });
    } catch (_) {}
  }

  // Cart helpers
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

  // Hold/Resume/Clear
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
      builder: (dCtx) => AlertDialog(
        title: const Text('Held Orders'),
        content: SizedBox(
          width: 320,
          height: 300,
          child: ListView.separated(
            itemCount: heldOrders.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final o = heldOrders[i];
              final time = '${o.timestamp.hour.toString().padLeft(2, '0')}:${o.timestamp.minute.toString().padLeft(2, '0')}';
              final count = o.items.fold<int>(0, (s, it) => s + it.qty);
              return ListTile(
                title: Text('${o.id} • $time'),
                subtitle: Text('Items: $count'),
                onTap: () => Navigator.of(dCtx).pop(o),
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(dCtx).pop(), child: const Text('Close'))],
      ),
    ).then((sel) {
      if (sel != null) _resumeHeld(sel);
      return sel;
    });
  }

  void _clearCart() { if (cart.isEmpty) return; cart.clear(); setState(() {}); }

  // Totals
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

  // Filters Search & Favorites
  List<Customer> _buildCustomerSuggestions() {
    final q = _customerSearchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return const <Customer>[];
    final list = customers.where((c) => c.name.toLowerCase().contains(q)).toList();
    return list.take(8).toList();
  }

  List<Product> _filteredProducts(List<Product> products) {
    Iterable<Product> list = products;
    if (_showFavoritesOnly) list = list.where((p) => _favoriteSkus.contains(p.sku));
    final q = searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return list.toList();
    return list.where((p) =>
      p.sku.toLowerCase().contains(q) ||
      p.name.toLowerCase().contains(q) ||
      (p.barcode ?? '').toLowerCase().contains(q)
    ).toList();
  }

  void _onUnifiedSubmit() {
    final code = searchCtrl.text.trim();
    if (code.isEmpty) return;
    Product? match;
    for (final p in _cacheProducts) {
      if (p.sku.toLowerCase() == code.toLowerCase() || (p.barcode != null && p.barcode!.toLowerCase() == code.toLowerCase())) { match = p; break; }
    }
    if (match != null) { addToCart(match); searchCtrl.clear(); setState(() {}); } else { setState(() {}); }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (context, ref, _) {
      final sel = ref.watch(selectedStoreIdProvider);
      if (sel == null) {
        return const Center(child: Text('Select a store to start POS'));
      }
      return StreamBuilder<List<Product>>(
      stream: _productStream(sel),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final products = snap.data!; _cacheProducts = products;
        return Stack(children: [
          SafeArea(
            top: false,
            bottom: true,
            child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Column(
            children: [
              // Top search row (customer + barcode + icons)
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
                customerSelector: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Add customer',
                      icon: const Icon(Icons.person_add_alt_1_outlined),
                      onPressed: _showAddCustomerDialog,
                    ),
                  ],
                ),
                barcodeTrailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    tooltip: 'All products',
                    icon: Icon(Icons.list_alt, color: !_showFavoritesOnly ? Theme.of(context).colorScheme.primary : null),
                    onPressed: () { setState(() { _showFavoritesOnly = false; searchCtrl.clear(); }); },
                  ),
                  IconButton(
                    tooltip: _useGrid ? 'Show list' : 'Show grid',
                    icon: Icon(_useGrid ? Icons.view_list : Icons.grid_view),
                    onPressed: () { setState(() { _useGrid = !_useGrid; }); },
                  ),
                  IconButton(
                    tooltip: 'Favorites',
                    icon: Icon(_favoriteSkus.isEmpty ? Icons.star_border : Icons.star, color: _showFavoritesOnly ? Theme.of(context).colorScheme.primary : null),
                    onPressed: () { setState(() { _showFavoritesOnly = true; }); },
                  ),
                ]),
                scannerActive: false,
                scannerConnected: false,
                onScannerToggle: (_) {},
                onBarcodeSubmitted: _onUnifiedSubmit,
                onSearchChanged: () => setState(() {}),
              ),
              const SizedBox(height: 8),
              // Products list shares space with bottom card and expands when room is available
              Flexible(
                flex: 1,
                child: Card(
                  child: _useGrid
                      ? PosProductGrid(
                          products: _filteredProducts(products),
                          favoriteSkus: _favoriteSkus,
                          onAdd: addToCart,
                          onToggleFavorite: (p) {
                            setState(() {
                              if (_favoriteSkus.contains(p.sku)) { _favoriteSkus.remove(p.sku); } else { _favoriteSkus.add(p.sku); }
                            });
                          },
                        )
                      : PosProductList(
                          products: _filteredProducts(products),
                          favoriteSkus: _favoriteSkus,
                          onAdd: addToCart,
                          onToggleFavorite: (p) {
                            setState(() {
                              if (_favoriteSkus.contains(p.sku)) { _favoriteSkus.remove(p.sku); } else { _favoriteSkus.add(p.sku); }
                            });
                          },
                        ),
                ),
              ),
              const SizedBox(height: 6),
              // Pay/Cart bar: small fixed cap, does not expand
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 96),
                child: CombinedCartCheckoutCard(
                  minWidth: 320,
                  cart: cart,
                  heldOrders: heldOrders,
                  onHold: _holdCart,
                  onResumeSelect: _pickHeldOrder,
                  onClear: _clearCart,
                  customersStream: _customerStream(sel),
                  initialCustomers: customers,
                  selectedCustomer: selectedCustomer,
                  onCustomerSelected: (c) { setState(() { selectedCustomer = c ?? walkIn; _availablePoints = (selectedCustomer?.rewardsPoints ?? 0).toDouble(); _customerSearchCtrl.text = selectedCustomer?.name ?? ''; }); },
                  onChangeQty: (sku, d) => changeQty(sku, d),
                  onRemove: (sku) => removeFromCart(sku),
                  subtotal: subtotal,
                  discount: discountValue,
                  tax: totalTax,
                  total: payableTotal,
                  onSelectPayment: (mode) { setState(() { selectedPaymentMode = mode; }); },
                  onShowCustomers: _showCustomerPopup,
                  compact: true,
                ),
              ),
            ],
          ),
          ),
            ),
          const Positioned(top: 4, right: 4, child: DeviceClassIcon()),
        ]);
      },
    );
    });
  }

  // ignore: unused_element
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
          child: LayoutBuilder(builder: (ctx, constraints) {
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
                        StreamBuilder<List<Customer>>(
                          stream: () {
                            final s = ProviderScope.containerOf(ctx).read(selectedStoreIdProvider);
                            if (s == null) {
                              // Fallback to a single-shot stream of current in-memory customers
                              return Stream<List<Customer>>.value(customers);
                            }
                            return _customerStream(s);
                          }(),
                          initialData: customers,
                          builder: (ctx, snap) {
                            final all = [walkIn, ...((snap.data ?? const <Customer>[]) .where((x) => x.id.isNotEmpty))];
                            final q = searchCtrl.text.trim().toLowerCase();
                            if (q.isEmpty) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12.0),
                                child: Text('Start typing to search customers', style: Theme.of(ctx).textTheme.bodySmall),
                              );
                            }
                            final list = all.where((c) => c.name.toLowerCase().contains(q)).toList();
                            return Column(children: [
                              for (final cust in list)
                                ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.person_outline),
                                  title: Text(cust.name, overflow: TextOverflow.ellipsis),
                                  trailing: (selectedCustomer?.id == cust.id) ? const Icon(Icons.check, color: Colors.green) : null,
                                  onTap: () {
                                    setState(() {
                                      selectedCustomer = cust;
                                      _availablePoints = (cust.rewardsPoints).toDouble();
                                      _customerSearchCtrl.text = cust.name;
                                    });
                                    setLocal((){});
                                  },
                                ),
                            ]);
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
                          child: FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
                        )
                      ],
                    ),
                  );
                },
              ),
            );
          }),
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
                final sel = ProviderScope.containerOf(ctx).read(selectedStoreIdProvider);
                if (sel == null) throw StateError('No store selected');
                final doc = await StoreRefs.of(sel).customers().add({
                  'name': nameCtrl.text.trim(),
                  'phone': phoneCtrl.text.trim(),
                  'email': emailCtrl.text.trim(),
                  'loyaltyPoints': 0,
                  'rewardsPoints': 0,
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
                if (!ctx.mounted) return; Navigator.pop(ctx, true);
              } catch (_) { if (!ctx.mounted) return; Navigator.pop(ctx, false); }
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

  // Popup dialog for selecting/viewing customers (instead of bottom sheet)
  Future<void> _showCustomerPopup() async {
    final c = selectedCustomer ?? walkIn;
    final searchCtrl = TextEditingController();
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final tt = Theme.of(ctx).textTheme;
        return AlertDialog(
          title: const Text('Customers'),
          content: SizedBox(
            width: 360,
            child: StatefulBuilder(
              builder: (ctx, setLocal) {
                return SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: searchCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Search customers',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (_) { setLocal((){}); },
                      ),
                      const SizedBox(height: 8),
                      StreamBuilder<List<Customer>>(
                        stream: () {
                          final s = ProviderScope.containerOf(ctx).read(selectedStoreIdProvider);
                          if (s == null) {
                            return Stream<List<Customer>>.value(customers);
                          }
                          return _customerStream(s);
                        }(),
                        initialData: customers,
                        builder: (ctx, snap) {
                          final all = [walkIn, ...((snap.data ?? const <Customer>[]) .where((x) => x.id.isNotEmpty))];
                          final q = searchCtrl.text.trim().toLowerCase();
                          if (q.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12.0),
                              child: Text('Start typing to search customers', style: Theme.of(ctx).textTheme.bodySmall),
                            );
                          }
                          final list = all.where((c) => c.name.toLowerCase().contains(q)).toList();
                          return Column(children: [
                            for (final cust in list)
                              ListTile(
                                dense: true,
                                leading: const Icon(Icons.person_outline),
                                title: Text(cust.name, overflow: TextOverflow.ellipsis),
                                trailing: (selectedCustomer?.id == cust.id) ? const Icon(Icons.check, color: Colors.green) : null,
                                onTap: () {
                                  setState(() {
                                    selectedCustomer = cust;
                                    _availablePoints = (cust.rewardsPoints).toDouble();
                                    _customerSearchCtrl.text = cust.name;
                                  });
                                  setLocal((){});
                                },
                              ),
                          ]);
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
                    ],
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
          ],
        );
      },
    );
    searchCtrl.dispose();
  }
}
