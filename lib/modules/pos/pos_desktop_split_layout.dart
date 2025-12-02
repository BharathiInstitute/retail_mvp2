import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retail_mvp2/core/firestore_store_collections.dart';
import 'package:retail_mvp2/core/theme/theme_extension_helpers.dart';
import 'package:retail_mvp2/modules/stores/providers.dart';
import 'pos.dart';
import 'pos_product_selector_panel.dart';
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
  Stream<List<Product>> _productStream(String storeId) => _inventoryRepo.streamProducts(storeId: storeId).map((docs) {
        return docs
            .map((d) => Product(
                  sku: d.sku,
                  name: d.name,
                  price: d.unitPrice,
                  stock: d.totalStock,
                  taxPercent: (d.taxPct ?? 0).toInt(),
                  barcode: d.barcode.isEmpty ? null : d.barcode,
                  imageUrls: d.imageUrls,
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
    return Consumer(builder: (context, ref, _) {
      final sel = ref.watch(selectedStoreIdProvider);
      if (sel == null) {
        return const Center(child: Text('Select a store to start POS'));
      }
      final cs = Theme.of(context).colorScheme;
      final screenWidth = MediaQuery.of(context).size.width;
      final isMobile = screenWidth < 700;
      
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [cs.surface, cs.primaryContainer.withOpacity(0.03)],
          ),
        ),
        child: isMobile 
          ? _buildMobileLayout(sel, cs)
          : _buildDesktopLayout(sel, cs, screenWidth),
      );
    });
  }

  Widget _buildMobileLayout(String storeId, ColorScheme cs) {
    return Stack(children: [
      Column(
        children: [
          // Products area
          Expanded(
            child: StreamBuilder<List<Product>>(
              stream: _productStream(storeId),
              builder: (context, snap) {
                if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
                if (!snap.hasData) return Center(child: CircularProgressIndicator(color: cs.primary));
                final products = snap.data!;
                _cacheProducts = products;
                return Column(
                  children: [
                    _buildModernSearchCard(cs, storeId),
                    Expanded(
                      child: _useGrid
                          ? PosProductGrid(
                              products: _filteredProducts(products),
                              favoriteSkus: _favoriteSkus,
                              onAdd: addToCart,
                              onToggleFavorite: (p) => setState(() {
                                _favoriteSkus.contains(p.sku) ? _favoriteSkus.remove(p.sku) : _favoriteSkus.add(p.sku);
                              }),
                            )
                          : PosProductList(
                              products: _filteredProducts(products),
                              favoriteSkus: _favoriteSkus,
                              onAdd: addToCart,
                              onToggleFavorite: (p) => setState(() {
                                _favoriteSkus.contains(p.sku) ? _favoriteSkus.remove(p.sku) : _favoriteSkus.add(p.sku);
                              }),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
          // Bottom cart bar
          _buildModernCartBar(cs, storeId),
        ],
      ),
    ]);
  }

  Widget _buildDesktopLayout(String storeId, ColorScheme cs, double screenWidth) {
    final leftWidth = (screenWidth * 0.52).clamp(360.0, 560.0);
    
    return Stack(children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: Products
          SizedBox(
            width: leftWidth,
            child: StreamBuilder<List<Product>>(
              stream: _productStream(storeId),
              builder: (context, snap) {
                if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
                if (!snap.hasData) return Center(child: CircularProgressIndicator(color: cs.primary));
                final products = snap.data!;
                _cacheProducts = products;
                return Column(
                  children: [
                    _buildModernSearchCard(cs, storeId),
                    Expanded(
                      child: _useGrid
                          ? PosProductGrid(
                              products: _filteredProducts(products),
                              favoriteSkus: _favoriteSkus,
                              onAdd: addToCart,
                              onToggleFavorite: (p) => setState(() {
                                _favoriteSkus.contains(p.sku) ? _favoriteSkus.remove(p.sku) : _favoriteSkus.add(p.sku);
                              }),
                            )
                          : PosProductList(
                              products: _filteredProducts(products),
                              favoriteSkus: _favoriteSkus,
                              onAdd: addToCart,
                              onToggleFavorite: (p) => setState(() {
                                _favoriteSkus.contains(p.sku) ? _favoriteSkus.remove(p.sku) : _favoriteSkus.add(p.sku);
                              }),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
          context.gapHMd,
          // Right: Cart
          Expanded(
            child: Align(
              alignment: Alignment.topRight,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: _buildModernCartCard(cs, storeId),
              ),
            ),
          ),
        ],
      ),
    ]);
  }

  Widget _buildModernSearchCard(ColorScheme cs, String storeId) {
    final sizes = context.sizes;
    return Container(
      margin: EdgeInsets.all(sizes.gapMd),
      padding: EdgeInsets.all(sizes.gapMd),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: context.radiusMd,
        border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
        boxShadow: [BoxShadow(color: cs.shadow.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Customer row
          Row(
            children: [
              Expanded(
                child: Container(
                  height: sizes.inputHeightMd,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withOpacity(0.4),
                    borderRadius: context.radiusSm,
                    border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      SizedBox(width: sizes.gapMd),
                      Icon(Icons.person_rounded, size: sizes.iconSm, color: cs.primary),
                      SizedBox(width: sizes.gapSm),
                      Expanded(
                        child: TextField(
                          controller: _customerSearchCtrl,
                          style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurface),
                          decoration: InputDecoration(
                            hintText: selectedCustomer?.name ?? 'Walk-in Customer',
                            hintStyle: TextStyle(fontSize: sizes.fontXs, color: cs.onSurfaceVariant.withOpacity(0.8)),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            isDense: true,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: sizes.gapSm),
              _buildIconBtn(Icons.person_outline_rounded, 'Details', _showCustomerDetailsSheet, cs),
              SizedBox(width: sizes.gapXs),
              _buildIconBtn(Icons.person_add_alt_1_rounded, 'Add', _showAddCustomerDialog, cs),
              SizedBox(width: sizes.gapXs),
              _buildScannerToggle(cs),
            ],
          ),
          // Customer suggestions
          if (_buildCustomerSuggestions().isNotEmpty && _customerSearchCtrl.text.trim().length >= 2)
            _buildCustomerSuggestionsDropdown(cs),
          SizedBox(height: sizes.gapMd),
          // Search row
          Row(
            children: [
              _buildViewToggle(Icons.view_list_rounded, !_useGrid, () => setState(() => _useGrid = false), cs),
              SizedBox(width: sizes.gapXs),
              _buildViewToggle(Icons.grid_view_rounded, _useGrid, () => setState(() => _useGrid = true), cs),
              SizedBox(width: sizes.gapXs),
              _buildViewToggle(Icons.star_rounded, _showFavoritesOnly, () => setState(() => _showFavoritesOnly = !_showFavoritesOnly), cs, badge: _favoriteSkus.isNotEmpty),
              SizedBox(width: sizes.gapMd),
              Expanded(
                child: Container(
                  height: sizes.inputHeightMd,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withOpacity(0.4),
                    borderRadius: context.radiusSm,
                    border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
                  ),
                  child: TextField(
                    controller: searchCtrl,
                    style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurface),
                    decoration: InputDecoration(
                      prefixIcon: Icon(Icons.qr_code_scanner_rounded, size: sizes.iconSm, color: cs.onSurfaceVariant),
                      hintText: 'Barcode / SKU or Search',
                      hintStyle: TextStyle(fontSize: sizes.fontXs, color: cs.onSurfaceVariant.withOpacity(0.7)),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: sizes.gapMd),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _onUnifiedSubmit(),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIconBtn(IconData icon, String tooltip, VoidCallback onTap, ColorScheme cs) {
    final sizes = context.sizes;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: context.radiusSm,
          child: Container(
            padding: EdgeInsets.all(sizes.gapSm),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withOpacity(0.4),
              borderRadius: context.radiusSm,
            ),
            child: Icon(icon, size: sizes.iconSm, color: cs.onSurfaceVariant),
          ),
        ),
      ),
    );
  }

  Widget _buildScannerToggle(ColorScheme cs) {
    final sizes = context.sizes;
    return Container(
      padding: EdgeInsets.all(sizes.gapSm),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.4),
        borderRadius: context.radiusSm,
      ),
      child: Icon(Icons.settings_input_antenna_rounded, size: sizes.iconSm, color: cs.onSurfaceVariant),
    );
  }

  Widget _buildViewToggle(IconData icon, bool active, VoidCallback onTap, ColorScheme cs, {bool badge = false}) {
    final sizes = context.sizes;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: context.radiusSm,
        child: Container(
          padding: EdgeInsets.all(sizes.gapSm),
          decoration: BoxDecoration(
            color: active ? cs.primary.withOpacity(0.12) : cs.surfaceContainerHighest.withOpacity(0.4),
            borderRadius: context.radiusSm,
            border: Border.all(color: active ? cs.primary.withOpacity(0.3) : Colors.transparent),
          ),
          child: Stack(
            children: [
              Icon(icon, size: sizes.iconSm, color: active ? cs.primary : cs.onSurfaceVariant),
              if (badge)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    width: sizes.gapSm,
                    height: sizes.gapSm,
                    decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCustomerSuggestionsDropdown(ColorScheme cs) {
    final suggestions = _buildCustomerSuggestions();
    return Container(
      margin: const EdgeInsets.only(top: 8),
      constraints: const BoxConstraints(maxHeight: 160),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: context.radiusMd,
        border: Border.all(color: cs.outlineVariant.withOpacity(0.4)),
        boxShadow: [BoxShadow(color: cs.shadow.withOpacity(0.08), blurRadius: 8)],
      ),
      child: ClipRRect(
        borderRadius: context.radiusMd,
        child: ListView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: suggestions.length,
          itemBuilder: (_, i) {
            final c = suggestions[i];
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  setState(() {
                    selectedCustomer = c.id.isEmpty ? walkIn : c;
                    _availablePoints = (selectedCustomer?.rewardsPoints ?? 0).toDouble();
                    _customerSearchCtrl.text = selectedCustomer?.name ?? '';
                  });
                  FocusScope.of(context).unfocus();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer.withOpacity(0.5),
                          borderRadius: context.radiusSm,
                        ),
                        child: Icon(Icons.person_rounded, size: 14, color: cs.primary),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(c.name, style: TextStyle(fontSize: context.sizes.fontSm, color: cs.onSurface), overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildModernCartBar(ColorScheme cs, String storeId) {
    final itemCount = cart.values.fold(0, (s, it) => s + it.qty);
    final sizes = context.sizes;
    
    return Container(
      padding: EdgeInsets.symmetric(horizontal: sizes.gapMd, vertical: sizes.gapMd),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant.withOpacity(0.3))),
        boxShadow: [BoxShadow(color: cs.shadow.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, -2))],
      ),
      child: Row(
        children: [
          // Cart button
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: cart.isEmpty ? null : () => _openMobileCartSheet(cs, storeId),
              borderRadius: context.radiusSm,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: sizes.gapMd, vertical: sizes.gapMd),
                decoration: BoxDecoration(
                  gradient: cart.isEmpty 
                      ? null 
                      : LinearGradient(colors: [cs.primary, cs.primary.withOpacity(0.85)]),
                  color: cart.isEmpty ? cs.surfaceContainerHighest : null,
                  borderRadius: context.radiusSm,
                  boxShadow: cart.isEmpty ? null : [BoxShadow(color: cs.primary.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shopping_cart_rounded, size: sizes.iconSm, color: cart.isEmpty ? cs.onSurfaceVariant : cs.onPrimary),
                    SizedBox(width: sizes.gapSm),
                    Text('Cart', style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w600, color: cart.isEmpty ? cs.onSurfaceVariant : cs.onPrimary)),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(width: sizes.gapMd),
          // Items & discount
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$itemCount items', style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w600, color: cs.onSurface)),
                Text('Disc. ₹${discountValue.toStringAsFixed(2)}', style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          // Total
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('₹${payableTotal.toStringAsFixed(2)}', style: TextStyle(fontSize: sizes.fontMd, fontWeight: FontWeight.w700, color: cs.primary)),
              Text('GST ₹${totalTax.toStringAsFixed(2)}', style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurfaceVariant)),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openMobileCartSheet(ColorScheme cs, String storeId) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _buildMobileCartSheetContent(ctx, cs, storeId),
    );
  }

  Widget _buildMobileCartSheetContent(BuildContext ctx, ColorScheme cs, String storeId) {
    final sizes = ctx.sizes;
    return StatefulBuilder(
      builder: (ctx, setLocal) {
        final maxH = MediaQuery.of(ctx).size.height * 0.85;
        return Container(
          constraints: BoxConstraints(maxHeight: maxH),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(sizes.radiusLg)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: EdgeInsets.only(top: sizes.gapMd),
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: ctx.radiusSm),
              ),
              // Header
              Padding(
                padding: EdgeInsets.fromLTRB(sizes.gapLg, sizes.gapLg, sizes.gapSm, sizes.gapSm),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(sizes.gapSm),
                      decoration: BoxDecoration(
                        color: cs.primary.withOpacity(0.1),
                        borderRadius: ctx.radiusSm,
                      ),
                      child: Icon(Icons.shopping_cart_rounded, size: sizes.iconSm, color: cs.primary),
                    ),
                    SizedBox(width: sizes.gapMd),
                    Text('Cart', style: TextStyle(fontSize: sizes.fontMd, fontWeight: FontWeight.w700, color: cs.onSurface)),
                    const Spacer(),
                    _buildSheetIconBtn(Icons.pause_circle_rounded, 'Hold', _holdCart, cs, setLocal),
                    _buildSheetIconBtn(Icons.play_circle_rounded, 'Resume', () async { await _pickHeldOrder(ctx); setLocal(() {}); }, cs, setLocal, enabled: heldOrders.isNotEmpty),
                    _buildSheetIconBtn(Icons.delete_sweep_rounded, 'Clear', () { _clearCart(); setLocal(() {}); }, cs, setLocal, enabled: cart.isNotEmpty),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: cs.outlineVariant.withOpacity(0.3)),
              // Cart items
              Expanded(
                child: cart.isEmpty
                    ? _buildEmptyCartState(cs)
                    : ListView.builder(
                        padding: EdgeInsets.symmetric(vertical: sizes.gapSm),
                        itemCount: cart.length,
                        itemBuilder: (_, i) {
                          final item = cart.values.elementAt(i);
                          return _buildCartItemTile(item, cs, setLocal);
                        },
                      ),
              ),
              // Footer
              Container(
                padding: EdgeInsets.all(sizes.gapLg),
                decoration: BoxDecoration(
                  color: cs.surface,
                  border: Border(top: BorderSide(color: cs.outlineVariant.withOpacity(0.3))),
                ),
                child: Column(
                  children: [
                    _buildSummaryRow('Subtotal', subtotal, cs),
                    _buildSummaryRow('Discount', -discountValue, cs),
                    _buildSummaryRow('GST', totalTax, cs),
                    SizedBox(height: sizes.gapSm),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total', style: TextStyle(fontSize: sizes.fontMd, fontWeight: FontWeight.w700, color: cs.onSurface)),
                        Text('₹${payableTotal.toStringAsFixed(2)}', style: TextStyle(fontSize: sizes.fontLg, fontWeight: FontWeight.w700, color: cs.primary)),
                      ],
                    ),
                    SizedBox(height: sizes.gapMd),
                    SizedBox(
                      width: double.infinity,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: cart.isEmpty ? null : () { Navigator.pop(ctx); _openPaymentSheetDesktop(context); },
                          borderRadius: ctx.radiusMd,
                          child: Container(
                            padding: EdgeInsets.symmetric(vertical: sizes.gapMd),
                            decoration: BoxDecoration(
                              gradient: cart.isEmpty ? null : LinearGradient(colors: [cs.primary, cs.primary.withOpacity(0.85)]),
                              color: cart.isEmpty ? cs.surfaceContainerHighest : null,
                              borderRadius: ctx.radiusMd,
                            ),
                            child: Center(
                              child: Text(
                                'Pay ₹${payableTotal.toStringAsFixed(2)}',
                                style: TextStyle(fontSize: sizes.fontMd, fontWeight: FontWeight.w600, color: cart.isEmpty ? cs.onSurfaceVariant : cs.onPrimary),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSheetIconBtn(IconData icon, String tooltip, VoidCallback onTap, ColorScheme cs, StateSetter setLocal, {bool enabled = true}) {
    final sizes = context.sizes;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: enabled ? () { onTap(); setLocal(() {}); } : null,
        icon: Icon(icon, size: sizes.iconMd, color: enabled ? cs.onSurfaceVariant : cs.outlineVariant),
      ),
    );
  }

  Widget _buildEmptyCartState(ColorScheme cs) {
    final sizes = context.sizes;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(sizes.gapLg),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withOpacity(0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.shopping_cart_outlined, size: sizes.iconXl, color: cs.outlineVariant),
          ),
          SizedBox(height: sizes.gapMd),
          Text('Cart is empty', style: TextStyle(fontSize: sizes.fontMd, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
          SizedBox(height: sizes.gapXs),
          Text('Add products to get started', style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurfaceVariant.withOpacity(0.7))),
        ],
      ),
    );
  }

  Widget _buildCartItemTile(CartItem item, ColorScheme cs, StateSetter setLocal) {
    final sizes = context.sizes;
    final line = item.product.price * item.qty;
    return Container(
      margin: EdgeInsets.symmetric(horizontal: sizes.gapMd, vertical: sizes.gapXs),
      padding: EdgeInsets.all(sizes.gapMd),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: context.radiusSm,
        border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          // Product image/icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: context.radiusSm,
            ),
            child: item.product.imageUrls.isNotEmpty
                ? ClipRRect(
                    borderRadius: context.radiusSm,
                    child: Image.network(item.product.imageUrls.first, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(Icons.inventory_2_rounded, size: sizes.iconMd, color: cs.outline)),
                  )
                : Icon(Icons.inventory_2_rounded, size: sizes.iconMd, color: cs.outline),
          ),
          SizedBox(width: sizes.gapMd),
          // Name & price
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.product.name, style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w600, color: cs.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis),
                SizedBox(height: sizes.gapXs),
                Text('₹${item.product.price.toStringAsFixed(2)}', style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          // Qty controls
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildQtyBtn(Icons.remove_rounded, () { changeQty(item.product.sku, -1); setLocal(() {}); }, cs),
              Container(
                width: sizes.buttonHeightSm,
                alignment: Alignment.center,
                child: Text(item.qty.toString(), style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w600, color: cs.onSurface)),
              ),
              _buildQtyBtn(Icons.add_rounded, () { changeQty(item.product.sku, 1); setLocal(() {}); }, cs),
            ],
          ),
          SizedBox(width: sizes.gapSm),
          // Line total
          Text('₹${line.toStringAsFixed(0)}', style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w700, color: cs.primary)),
          SizedBox(width: sizes.gapXs),
          // Remove
          InkWell(
            onTap: () { removeFromCart(item.product.sku); setLocal(() {}); },
            borderRadius: context.radiusSm,
            child: Padding(
              padding: EdgeInsets.all(sizes.gapXs),
              child: Icon(Icons.close_rounded, size: sizes.iconSm, color: cs.error.withOpacity(0.7)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQtyBtn(IconData icon, VoidCallback onTap, ColorScheme cs) {
    final sizes = context.sizes;
    return InkWell(
      onTap: onTap,
      borderRadius: context.radiusSm,
      child: Container(
        padding: EdgeInsets.all(sizes.gapSm),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withOpacity(0.5),
          borderRadius: context.radiusSm,
        ),
        child: Icon(icon, size: sizes.iconXs, color: cs.onSurfaceVariant),
      ),
    );
  }

  Widget _buildSummaryRow(String label, double value, ColorScheme cs) {
    final sizes = context.sizes;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: sizes.gapXs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurfaceVariant)),
          Text('₹${value.toStringAsFixed(2)}', style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurface)),
        ],
      ),
    );
  }

  Widget _buildModernCartCard(ColorScheme cs, String storeId) {
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 10, 10, 10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: context.radiusLg,
        border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
        boxShadow: [BoxShadow(color: cs.shadow.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
            child: Row(
              children: [
                Container(
                  padding: context.padSm,
                  decoration: BoxDecoration(
                    color: cs.primary.withOpacity(0.1),
                    borderRadius: context.radiusSm,
                  ),
                  child: Icon(Icons.shopping_cart_rounded, size: 16, color: cs.primary),
                ),
                const SizedBox(width: 10),
                Text('Cart', style: TextStyle(fontSize: context.sizes.fontMd, fontWeight: FontWeight.w700, color: cs.onSurface)),
                const Spacer(),
                _buildCartHeaderBtn(Icons.pause_circle_rounded, 'Hold', _holdCart, cs),
                _buildCartHeaderBtn(Icons.play_circle_rounded, 'Resume', () async { await _pickHeldOrder(context); }, cs, enabled: heldOrders.isNotEmpty),
                _buildCartHeaderBtn(Icons.delete_sweep_rounded, 'Clear', _clearCart, cs, enabled: cart.isNotEmpty),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant.withOpacity(0.3)),
          // Items
          Expanded(
            child: cart.isEmpty
                ? _buildEmptyCartState(cs)
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: cart.length,
                    itemBuilder: (_, i) {
                      final item = cart.values.elementAt(i);
                      return _buildDesktopCartItem(item, cs);
                    },
                  ),
          ),
          // Footer
          Container(
            padding: context.padMd,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withOpacity(0.3),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${cart.values.fold(0, (s, it) => s + it.qty)} items', style: TextStyle(fontSize: context.sizes.fontSm, fontWeight: FontWeight.w600, color: cs.onSurface)),
                          Text('Disc. ₹${discountValue.toStringAsFixed(2)}', style: TextStyle(fontSize: context.sizes.fontXs, color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('₹${payableTotal.toStringAsFixed(2)}', style: TextStyle(fontSize: context.sizes.fontLg, fontWeight: FontWeight.w700, color: cs.primary)),
                        Text('GST ₹${totalTax.toStringAsFixed(2)}', style: TextStyle(fontSize: context.sizes.fontXs, color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: cart.isEmpty ? null : () => _openPaymentSheetDesktop(context),
                      borderRadius: context.radiusMd,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          gradient: cart.isEmpty ? null : LinearGradient(colors: [cs.primary, cs.primary.withOpacity(0.85)]),
                          color: cart.isEmpty ? cs.surfaceContainerHighest : null,
                          borderRadius: context.radiusMd,
                          boxShadow: cart.isEmpty ? null : [BoxShadow(color: cs.primary.withOpacity(0.25), blurRadius: 8, offset: const Offset(0, 2))],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.shopping_cart_checkout_rounded, size: 16, color: cart.isEmpty ? cs.onSurfaceVariant : cs.onPrimary),
                            context.gapHSm,
                            Text('Checkout', style: TextStyle(fontSize: context.sizes.fontSm, fontWeight: FontWeight.w600, color: cart.isEmpty ? cs.onSurfaceVariant : cs.onPrimary)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartHeaderBtn(IconData icon, String tooltip, VoidCallback onTap, ColorScheme cs, {bool enabled = true}) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: context.radiusSm,
        child: Padding(
          padding: context.padSm,
          child: Icon(icon, size: 18, color: enabled ? cs.onSurfaceVariant : cs.outlineVariant),
        ),
      ),
    );
  }

  Widget _buildDesktopCartItem(CartItem item, ColorScheme cs) {
    final line = item.product.price * item.qty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(item.product.name, style: TextStyle(fontSize: context.sizes.fontSm, color: cs.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: () => changeQty(item.product.sku, -1),
                borderRadius: context.radiusXs,
                child: Container(
                  padding: context.padXs,
                  child: Icon(Icons.remove_rounded, size: 14, color: cs.onSurfaceVariant),
                ),
              ),
              Container(
                width: 24,
                alignment: Alignment.center,
                child: Text(item.qty.toString(), style: TextStyle(fontSize: context.sizes.fontSm, fontWeight: FontWeight.w600, color: cs.onSurface)),
              ),
              InkWell(
                onTap: () => changeQty(item.product.sku, 1),
                borderRadius: context.radiusXs,
                child: Container(
                  padding: context.padXs,
                  child: Icon(Icons.add_rounded, size: 14, color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 60,
            child: Text('₹${line.toStringAsFixed(0)}', style: TextStyle(fontSize: context.sizes.fontSm, fontWeight: FontWeight.w600, color: cs.onSurface), textAlign: TextAlign.right),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: () => removeFromCart(item.product.sku),
            borderRadius: context.radiusXs,
            child: Padding(
              padding: context.padXs,
              child: Icon(Icons.close_rounded, size: 14, color: cs.error.withOpacity(0.7)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openPaymentSheetDesktop(BuildContext context) async {
    var selected = PaymentMode.cash;
    final cs = Theme.of(context).colorScheme;
    await showModalBottomSheet<PaymentMode>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final maxH = MediaQuery.of(ctx).size.height * 0.9;
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxH),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom + MediaQuery.of(ctx).padding.bottom),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text('Payment', style: TextStyle(fontSize: context.sizes.fontXl, fontWeight: FontWeight.w700, color: cs.onSurface)),
                        const Spacer(),
                        IconButton(onPressed: () => Navigator.pop(ctx), icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant)),
                      ],
                    ),
                    context.gapVLg,
                    if (selectedCustomer != null) ...[
                      _buildPaymentCustomerInfo(ctx, cs),
                      context.gapVLg,
                    ],
                    _buildBillSummary(ctx, cs),
                    context.gapVLg,
                    Text('Payment Method', style: TextStyle(fontSize: context.sizes.fontMd, fontWeight: FontWeight.w600, color: cs.onSurface)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _buildPaymentMethodBtn('Cash', Icons.payments_rounded, PaymentMode.cash, selected, (m) => setLocal(() => selected = m), cs),
                        const SizedBox(width: 10),
                        _buildPaymentMethodBtn('UPI', Icons.qr_code_rounded, PaymentMode.upi, selected, (m) => setLocal(() => selected = m), cs),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () { Navigator.pop(ctx); onSelectPayment(selected); },
                        borderRadius: context.radiusMd,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [cs.primary, cs.primary.withOpacity(0.85)]),
                            borderRadius: context.radiusMd,
                            boxShadow: [BoxShadow(color: cs.primary.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))],
                          ),
                          child: Center(
                            child: Text('Pay ₹${payableTotal.toStringAsFixed(2)}', style: TextStyle(fontSize: context.sizes.fontLg, fontWeight: FontWeight.w700, color: cs.onPrimary)),
                          ),
                        ),
                      ),
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

  Widget _buildPaymentCustomerInfo(BuildContext ctx, ColorScheme cs) {
    return Container(
      padding: context.padMd,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: context.radiusMd,
      ),
      child: Row(
        children: [
          Container(
            padding: context.padSm,
            decoration: BoxDecoration(color: cs.primaryContainer.withOpacity(0.5), borderRadius: context.radiusSm),
            child: Icon(Icons.person_rounded, size: 16, color: cs.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(selectedCustomer!.name, style: TextStyle(fontSize: context.sizes.fontSm, fontWeight: FontWeight.w600, color: cs.onSurface)),
                if ((selectedCustomer!.phone ?? '').isNotEmpty)
                  Text(selectedCustomer!.phone!, style: TextStyle(fontSize: context.sizes.fontXs, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBillSummary(BuildContext ctx, ColorScheme cs) {
    return Container(
      padding: context.padMd,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: context.radiusMd,
      ),
      child: Column(
        children: [
          _buildSummaryRow('Subtotal', subtotal, cs),
          _buildSummaryRow('Discount', -discountValue, cs),
          _buildSummaryRow('Tax (GST)', totalTax, cs),
          Divider(height: 16, color: cs.outlineVariant.withOpacity(0.3)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total', style: TextStyle(fontSize: context.sizes.fontMd, fontWeight: FontWeight.w700, color: cs.onSurface)),
              Text('₹${payableTotal.toStringAsFixed(2)}', style: TextStyle(fontSize: context.sizes.fontLg, fontWeight: FontWeight.w700, color: cs.primary)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodBtn(String label, IconData icon, PaymentMode mode, PaymentMode selected, ValueChanged<PaymentMode> onSelect, ColorScheme cs) {
    final isSelected = mode == selected;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onSelect(mode),
          borderRadius: context.radiusMd,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: isSelected ? cs.primary.withOpacity(0.1) : cs.surfaceContainerHighest.withOpacity(0.4),
              borderRadius: context.radiusMd,
              border: Border.all(color: isSelected ? cs.primary.withOpacity(0.4) : cs.outlineVariant.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: isSelected ? cs.primary : cs.onSurfaceVariant),
                context.gapHSm,
                Text(label, style: TextStyle(fontSize: context.sizes.fontSm, fontWeight: FontWeight.w600, color: isSelected ? cs.primary : cs.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void onSelectPayment(PaymentMode mode) {
    setState(() { selectedPaymentMode = mode; });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Payment completed with ${mode.label}')),
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
                          Text('Customers', style: tt.titleMedium?.copyWith(color: Theme.of(ctx).colorScheme.onSurface)),
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
                            stream: () {
                              final s = ProviderScope.containerOf(ctx).read(selectedStoreIdProvider);
                              if (s == null) {
                                return Stream<List<Customer>>.value(customers);
                              }
                              return _customerStream(s);
                            }(),
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
                                  child: Text('Start typing to search customers', style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
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
                                          ? Icon(Icons.check, color: Theme.of(ctx).colorScheme.primary)
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
                          Text('Selected', style: tt.titleSmall?.copyWith(color: Theme.of(ctx).colorScheme.onSurface)),
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
                          const SizedBox(height: 16),
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
        Text(value, style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface)),
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
                context.gapVSm,
                TextFormField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(labelText: 'Phone', prefixIcon: Icon(Icons.phone_iphone)),
                  keyboardType: TextInputType.phone,
                ),
                context.gapVSm,
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
  // Optional: print invoice callback
  final VoidCallback? onPrint;

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
    this.onPrint,
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
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: cs.onSurface),
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
                                  Text(item.qty.toString(), style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                                  const SizedBox(width: 2),
                                  IconButton(
                                    icon: const Icon(Icons.add),
                                    onPressed: () => onChangeQty(item.product.sku, 1),
                                    padding: EdgeInsets.zero,
                                    visualDensity: VisualDensity.compact,
                                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                  ),
                                  context.gapHXs,
                                  Flexible(child: Text('₹${line.toStringAsFixed(2)}', overflow: TextOverflow.ellipsis, softWrap: false, style: TextStyle(color: Theme.of(context).colorScheme.onSurface))),
                                  context.gapHXs,
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
              context.gapVSm,
              Divider(height: 1, color: cs.outlineVariant),
              const SizedBox(height: 6),
              // Bottom summary bar (neutral background)
              Container(
                decoration: BoxDecoration(
                  borderRadius: context.radiusSm,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    // Left: Cart button
                    FilledButton.icon(
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
                      onPressed: cart.isEmpty ? null : () => _openPaymentSheet(context),
                      icon: const Icon(Icons.shopping_cart, size: 18),
                      label: const Text('Cart'),
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
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface),
                            ),
                          ],
                        ),
                        Text(
                          'GST ₹${tax.toStringAsFixed(2)}',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
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
          decoration: BoxDecoration(borderRadius: context.radiusSm),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            children: [
              // Cart button
              FilledButton.icon(
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6)),
                onPressed: cart.isEmpty ? null : () => _openPaymentSheet(context),
                icon: const Icon(Icons.shopping_cart, size: 18),
                label: const Text('Cart'),
              ),
              context.gapHSm,
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
                      Text('₹${total.toStringAsFixed(2)}', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface)),
                    ],
                  ),
                  Text('GST ₹${tax.toStringAsFixed(2)}', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
                          Text('Cart', style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: Theme.of(ctx).colorScheme.onSurface)),
                          const Spacer(),
                          if (onPrint != null)
                            IconButton(
                              tooltip: 'Print Invoice',
                              onPressed: cart.isEmpty ? null : onPrint,
                              icon: const Icon(Icons.print),
                            ),
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
                                        Text(item.qty.toString(), style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface)),
                                        IconButton(
                                          icon: const Icon(Icons.add),
                                          onPressed: () { onChangeQty(item.product.sku, 1); setLocal((){}); },
                                        ),
                                        context.gapHXs,
                                        Flexible(child: Text('₹${line.toStringAsFixed(2)}', overflow: TextOverflow.ellipsis, softWrap: false, style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface))),
                                        context.gapHXs,
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
                              Text('₹${total.toStringAsFixed(2)}', style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: Theme.of(ctx).colorScheme.onSurface)),
                              Text('GST ₹${tax.toStringAsFixed(2)}', style: Theme.of(ctx).textTheme.labelSmall?.copyWith(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
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
                      Text('Customer', style: Theme.of(ctx).textTheme.titleMedium?.copyWith(color: Theme.of(ctx).colorScheme.onSurface)),
                      const SizedBox(height: 6),
                      Text(selectedCustomer!.name, style: Theme.of(ctx).textTheme.bodyMedium),
                      if ((selectedCustomer!.phone ?? '').isNotEmpty)
                        Text('Phone: ${selectedCustomer!.phone!}', style: Theme.of(ctx).textTheme.labelSmall),
                      if ((selectedCustomer!.email ?? '').isNotEmpty)
                        Text('Email: ${selectedCustomer!.email!}', style: Theme.of(ctx).textTheme.labelSmall),
                      const Divider(),
                    ],
                    Text('Bill', style: Theme.of(ctx).textTheme.titleMedium),
                    context.gapVSm,
                    ..._buildBillLines(ctx),
                    const Divider(),
                    _kvRow(ctx, 'Subtotal', subtotal),
                    _kvRow(ctx, 'Discount', -discount),
                    _kvRow(ctx, 'Tax', tax),
                    const SizedBox(height: 6),
                    _kvRow(ctx, 'Total', total, bold: true),
                    context.gapVLg,
                    Text('Payment Method', style: Theme.of(ctx).textTheme.titleSmall),
                    context.gapVSm,
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        pmButton(PaymentMode.cash, 'Cash', Icons.payments),
                        pmButton(PaymentMode.upi, 'UPI', Icons.qr_code),
                      ],
                    ),
                    context.gapVMd,
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
                  Expanded(child: Text(it.product.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Theme.of(context).colorScheme.onSurface))),
                  Text('₹${lineTotal.toStringAsFixed(2)}', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '${it.qty} NOS @ ₹${it.product.price.toStringAsFixed(2)}   •   Discount ₹${discShare.toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text('GST ${it.product.taxPercent.toStringAsFixed(0)}%', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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

