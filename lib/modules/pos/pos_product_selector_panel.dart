import 'package:flutter/material.dart';
import '../../core/theme/theme_extension_helpers.dart';
import 'pos.dart';

// Clean, compilable replacement for POS search + scan card and related widgets
class PosSearchAndScanCard extends StatelessWidget {
  final TextEditingController barcodeController;
  final TextEditingController searchController;
  final TextEditingController? customerSearchController;
  final List<Customer>? customerSuggestions;
  final ValueChanged<Customer>? onCustomerSelected;
  final VoidCallback? onCustomerQueryChanged;
  final String? selectedCustomerName;
  final bool scannerActive;
  final bool scannerConnected;
  final ValueChanged<bool> onScannerToggle;
  final VoidCallback onBarcodeSubmitted;
  final VoidCallback onSearchChanged;
  final Widget? customerSelector;
  final Widget? barcodeTrailing;

  const PosSearchAndScanCard({
    super.key,
    required this.barcodeController,
    required this.searchController,
    this.customerSearchController,
    this.customerSuggestions,
    this.onCustomerSelected,
    this.onCustomerQueryChanged,
    this.selectedCustomerName,
    required this.scannerActive,
    required this.scannerConnected,
    required this.onScannerToggle,
    required this.onBarcodeSubmitted,
    required this.onSearchChanged,
    this.customerSelector,
    this.barcodeTrailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: context.radiusLg,
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (customerSearchController != null) ...[
                  Row(
                    children: [
                      Expanded(
                        child: _ModernSearchField(
                          controller: customerSearchController!,
                          hint: 'Search customer',
                          icon: Icons.person_search_rounded,
                          onChanged: (_) => onCustomerQueryChanged?.call(),
                        ),
                      ),
                      if (customerSelector != null) ...[
                        context.gapHMd,
                        customerSelector!,
                      ],
                      context.gapHMd,
                      _ModernScannerToggle(
                        active: scannerActive,
                        connected: scannerConnected,
                        onChanged: onScannerToggle,
                      ),
                    ],
                  ),
                  if ((customerSuggestions ?? const <Customer>[]).isNotEmpty &&
                      ((customerSearchController?.text.trim() ?? '').isNotEmpty) &&
                      ((customerSearchController?.text.trim() ?? '').length >= 2) &&
                      ((customerSearchController?.text.trim() ?? '') != (selectedCustomerName ?? '').trim()))
                    Container(
                      margin: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                      constraints: const BoxConstraints(maxHeight: 180),
                      decoration: BoxDecoration(
                        border: Border.all(color: cs.outlineVariant),
                        borderRadius: context.radiusMd,
                        color: cs.surface,
                      ),
                      child: ClipRRect(
                        borderRadius: context.radiusMd,
                        child: ListView.builder(
                          itemCount: customerSuggestions!.length,
                          itemBuilder: (_, i) {
                            final c = customerSuggestions![i];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: cs.primaryContainer,
                                child: Icon(Icons.person_rounded, color: cs.onPrimaryContainer, size: 20),
                              ),
                              dense: true,
                              title: Text(c.name, overflow: TextOverflow.ellipsis),
                              onTap: () {
                                customerSearchController!.text = c.name;
                                onCustomerSelected?.call(c);
                                FocusScope.of(context).unfocus();
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  context.gapVMd,
                ],
                Row(
                  children: [
                    if (barcodeTrailing != null) ...[
                      barcodeTrailing!,
                      context.gapHMd,
                    ],
                    Expanded(
                      child: _ModernSearchField(
                        controller: searchController,
                        hint: 'Barcode / SKU or Search',
                        icon: Icons.qr_code_scanner_rounded,
                        onSubmitted: (_) => onBarcodeSubmitted(),
                        onChanged: (_) => onSearchChanged(),
                      ),
                    ),
                    if (customerSearchController == null && customerSelector != null) ...[
                      context.gapHMd,
                      customerSelector!,
                    ],
                    if (customerSearchController == null) ...[
                      context.gapHMd,
                      _ModernScannerToggle(
                        active: scannerActive,
                        connected: scannerConnected,
                        onChanged: onScannerToggle,
                      ),
                    ],
                  ],
                ),
                // Scanner status shown below the toggle icon
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Modern search field with rounded corners
class _ModernSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  const _ModernSearchField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: cs.onSurfaceVariant),
        filled: true,
        fillColor: cs.surfaceContainerHighest.withOpacity(0.5),
        border: OutlineInputBorder(
          borderRadius: context.radiusMd,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: context.radiusMd,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: context.radiusMd,
          borderSide: BorderSide(color: cs.primary, width: 2),
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      onSubmitted: onSubmitted,
      onChanged: onChanged,
    );
  }
}

// Compact scanner toggle
class _ModernScannerToggle extends StatelessWidget {
  final bool active;
  final bool connected;
  final ValueChanged<bool> onChanged;

  const _ModernScannerToggle({
    required this.active,
    required this.connected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => onChanged(!active),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: context.padSm,
        decoration: BoxDecoration(
          color: active ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: context.radiusSm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.settings_input_antenna_rounded,
              size: 16,
              color: active ? cs.onPrimary : cs.onSurfaceVariant,
            ),
            if (active) ...[
              context.gapHXs,
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: connected ? context.appColors.success : context.appColors.warning,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class PosProductGrid extends StatelessWidget {
  final List<Product> products;
  final Set<String> favoriteSkus;
  final ValueChanged<Product> onAdd;
  final ValueChanged<Product> onToggleFavorite;

  const PosProductGrid({
    super.key,
    required this.products,
    required this.favoriteSkus,
    required this.onAdd,
    required this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 64, color: Theme.of(context).colorScheme.outline),
            context.gapVLg,
            Text('No products found', style: Theme.of(context).textTheme.titleMedium),
            context.gapVSm,
            Text('Add products in Inventory → Products', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
    }
    final width = MediaQuery.of(context).size.width;
    final cols = (width ~/ 180).clamp(2, 5); // Increased from 160 to 180
    return Card(
      child: GridView.builder(
        padding: context.padSm,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 0.75, // Changed for taller cards to fit image
        ),
        itemCount: products.length,
        itemBuilder: (_, i) {
          final p = products[i];
          final isFav = favoriteSkus.contains(p.sku);
          final scheme = Theme.of(context).colorScheme;
          return InkWell(
            onTap: () => onAdd(p),
            borderRadius: context.radiusSm,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: context.radiusSm,
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Product Image
                  Expanded(
                    flex: 3,
                    child: Container(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
                      ),
                      child: p.imageUrls.isNotEmpty
                          ? ClipRRect(
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
                              child: Image.network(
                                p.imageUrls.first,
                                fit: BoxFit.cover,
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return Center(child: CircularProgressIndicator(strokeWidth: 2));
                                },
                                errorBuilder: (_, __, ___) => Icon(Icons.inventory_2_outlined, size: 32, color: scheme.outline),
                              ),
                            )
                          : Center(child: Icon(Icons.inventory_2_outlined, size: 32, color: scheme.outline)),
                    ),
                  ),
                  // Product Info
                  Expanded(
                    flex: 2,
                    child: Padding(
                      padding: context.padSm,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500, color: scheme.onSurface),
                          ),
                          const Spacer(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Text(
                                  '₹${p.price.toStringAsFixed(2)}',
                                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: scheme.primary),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              GestureDetector(
                                onTap: () => onToggleFavorite(p),
                                child: Icon(
                                  isFav ? Icons.star : Icons.star_border,
                                  size: 20,
                                  color: isFav ? scheme.tertiary : scheme.outline,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class PosProductList extends StatefulWidget {
  final List<Product> products;
  final Set<String> favoriteSkus;
  final ValueChanged<Product> onAdd;
  final ValueChanged<Product> onToggleFavorite;
  final ScrollController? scrollController;

  const PosProductList({
    super.key,
    required this.products,
    required this.favoriteSkus,
    required this.onAdd,
    required this.onToggleFavorite,
    this.scrollController,
  });

  @override
  State<PosProductList> createState() => _PosProductListState();
}

class _PosProductListState extends State<PosProductList> {
  bool _isGridView = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (widget.products.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: context.padLg,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.inventory_2_rounded, size: 36, color: cs.outline),
            ),
            context.gapVMd,
            Text('No products found', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface)),
            context.gapVXs,
            Text('Add products in Inventory → Products', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.outline, fontSize: context.sizes.fontSm)),
          ],
        ),
      );
    }
    return Column(
      children: [
        // View toggle header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Text(
                '${widget.products.length} products',
                style: TextStyle(fontSize: context.sizes.fontSm, color: cs.onSurfaceVariant),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _isGridView = !_isGridView),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withOpacity(0.5),
                    borderRadius: context.radiusSm,
                  ),
                  child: Icon(
                    _isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded,
                    size: 16,
                    color: cs.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Product list or grid
        Expanded(
          child: _isGridView ? _buildGrid(cs) : _buildList(cs),
        ),
      ],
    );
  }

  Widget _buildList(ColorScheme cs) {
    return ListView.builder(
      controller: widget.scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: widget.products.length,
      itemBuilder: (_, i) {
        final p = widget.products[i];
        final isFav = widget.favoriteSkus.contains(p.sku);
        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          child: Material(
            color: cs.surface,
            borderRadius: context.radiusSm,
            child: InkWell(
              onTap: () => widget.onAdd(p),
              borderRadius: context.radiusSm,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: context.radiusSm,
                  border: Border.all(color: cs.outlineVariant.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    // Product image
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: context.radiusSm,
                      ),
                      child: p.imageUrls.isNotEmpty
                          ? ClipRRect(
                              borderRadius: context.radiusSm,
                              child: Image.network(
                                p.imageUrls.first,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Icon(Icons.inventory_2_rounded, color: cs.outline, size: 18),
                              ),
                            )
                          : Icon(Icons.inventory_2_rounded, color: cs.outline, size: 18),
                    ),
                    const SizedBox(width: 10),
                    // Product info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            p.name,
                            style: TextStyle(fontWeight: FontWeight.w500, fontSize: context.sizes.fontMd, color: cs.onSurface),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '₹${p.price.toStringAsFixed(0)}',
                            style: TextStyle(
                              color: cs.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: context.sizes.fontSm,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Favorite button
                    GestureDetector(
                      onTap: () => widget.onToggleFavorite(p),
                      child: Icon(
                        isFav ? Icons.star_rounded : Icons.star_border_rounded,
                        size: 18,
                        color: isFav ? cs.tertiary : cs.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGrid(ColorScheme cs) {
    return GridView.builder(
      controller: widget.scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.1,
      ),
      itemCount: widget.products.length,
      itemBuilder: (_, i) {
        final p = widget.products[i];
        final isFav = widget.favoriteSkus.contains(p.sku);
        return Material(
          color: cs.surface,
          borderRadius: context.radiusSm,
          child: InkWell(
            onTap: () => widget.onAdd(p),
            borderRadius: context.radiusSm,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: context.radiusSm,
                border: Border.all(color: cs.outlineVariant.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Product image
                  Expanded(
                    flex: 3,
                    child: Container(
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
                      ),
                      child: Stack(
                        children: [
                          p.imageUrls.isNotEmpty
                              ? ClipRRect(
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
                                  child: Image.network(
                                    p.imageUrls.first,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: double.infinity,
                                    errorBuilder: (_, __, ___) => Center(
                                      child: Icon(Icons.inventory_2_rounded, color: cs.outline, size: 28),
                                    ),
                                  ),
                                )
                              : Center(child: Icon(Icons.inventory_2_rounded, color: cs.outline, size: 28)),
                          // Favorite button
                          Positioned(
                            top: 4,
                            right: 4,
                            child: GestureDetector(
                              onTap: () => widget.onToggleFavorite(p),
                              child: Container(
                                padding: context.padXs,
                                decoration: BoxDecoration(
                                  color: cs.surface.withOpacity(0.9),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isFav ? Icons.star_rounded : Icons.star_border_rounded,
                                  size: 14,
                                  color: isFav ? cs.tertiary : cs.outline,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Product info - compact
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w500, fontSize: context.sizes.fontSm, color: cs.onSurface),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '₹${p.price.toStringAsFixed(0)}',
                          style: TextStyle(
                            color: cs.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: context.sizes.fontSm,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class PosPopularItemsGrid extends StatelessWidget {
  final List<Product> allProducts;
  final Set<String> favoriteSkus;
  final ValueChanged<Product> onAdd;

  const PosPopularItemsGrid({
    super.key,
    required this.allProducts,
    required this.favoriteSkus,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final popular = allProducts.where((p) => favoriteSkus.contains(p.sku)).toList();
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: context.radiusMd,
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(10.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.star_rounded, color: cs.tertiary, size: 16),
                const SizedBox(width: 6),
                Text(
                  'Favorites',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface),
                ),
                if (popular.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: cs.tertiaryContainer,
                      borderRadius: context.radiusSm,
                    ),
                    child: Text(
                      '${popular.length}',
                      style: TextStyle(color: cs.onTertiaryContainer, fontSize: context.sizes.fontXs, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ],
            ),
            context.gapVSm,
            if (popular.isEmpty)
              Text(
                'Tap ★ on products to add favorites',
                style: TextStyle(color: cs.outline, fontSize: context.sizes.fontSm),
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: popular.map((p) => _FavoriteChip(product: p, onTap: () => onAdd(p))).toList(),
              ),
          ],
        ),
      ),
    );
  }
}

// Favorite product chip
class _FavoriteChip extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;

  const _FavoriteChip({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.primaryContainer.withOpacity(0.4),
      borderRadius: context.radiusSm,
      child: InkWell(
        onTap: onTap,
        borderRadius: context.radiusSm,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (product.imageUrls.isNotEmpty)
                Container(
                  width: 20,
                  height: 20,
                  margin: const EdgeInsets.only(right: 6),
                  child: ClipRRect(
                    borderRadius: context.radiusXs,
                    child: Image.network(
                      product.imageUrls.first,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(Icons.inventory_2_rounded, size: 12, color: cs.onPrimaryContainer),
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(Icons.inventory_2_rounded, size: 14, color: cs.onPrimaryContainer),
                ),
              Text(
                product.name,
                style: TextStyle(fontSize: context.sizes.fontSm, fontWeight: FontWeight.w500, color: cs.onPrimaryContainer),
              ),
              context.gapHXs,
              Text(
                '₹${product.price.toStringAsFixed(0)}',
                style: TextStyle(fontSize: context.sizes.fontXs, color: cs.primary, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CartSection extends StatelessWidget {
  final Map<String, CartItem> cart;
  final List<HeldOrder> heldOrders;
  final VoidCallback onHold;
  final Future<HeldOrder?> Function(BuildContext) onResumeSelect;
  final VoidCallback onClear;
  final void Function(String sku, int delta) onChangeQty;
  final void Function(String sku) onRemove;

  const CartSection({
    super.key,
    required this.cart,
    required this.heldOrders,
    required this.onHold,
    required this.onResumeSelect,
    required this.onClear,
    required this.onChangeQty,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: context.radiusMd,
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.3))),
            ),
            child: Row(
              children: [
                Icon(Icons.shopping_cart_rounded, color: cs.primary, size: 18),
                context.gapHSm,
                Text(
                  'Cart',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface),
                ),
                if (cart.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: context.radiusSm,
                    ),
                    child: Text(
                      '${cart.length}',
                      style: TextStyle(color: cs.onPrimary, fontSize: context.sizes.fontXs, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
                const Spacer(),
                // Action buttons (icons only)
                _CartIconButton(icon: Icons.pause_rounded, tooltip: 'Hold', onTap: onHold, color: cs.tertiary),
                _CartIconButton(
                  icon: Icons.play_arrow_rounded,
                  tooltip: 'Resume',
                  onTap: heldOrders.isEmpty ? null : () async => await onResumeSelect(context),
                  color: cs.secondary,
                  badge: heldOrders.isNotEmpty ? heldOrders.length.toString() : null,
                ),
                _CartIconButton(icon: Icons.delete_outline_rounded, tooltip: 'Clear', onTap: cart.isEmpty ? null : onClear, color: cs.error),
              ],
            ),
          ),
          // Cart items
          Expanded(
            child: cart.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.shopping_cart_outlined, size: 32, color: cs.outlineVariant),
                        context.gapVSm,
                        Text('Empty cart', style: TextStyle(color: cs.outline, fontSize: context.sizes.fontSm)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: cart.length,
                    itemBuilder: (_, i) {
                      final item = cart.values.elementAt(i);
                      final line = item.product.price * item.qty;
                      return _ModernCartItem(
                        item: item,
                        lineTotal: line,
                        onDecrease: () => onChangeQty(item.product.sku, -1),
                        onIncrease: () => onChangeQty(item.product.sku, 1),
                        onRemove: () => onRemove(item.product.sku),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// Compact cart icon button
class _CartIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color color;
  final String? badge;

  const _CartIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.color,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDisabled = onTap == null;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: context.radiusSm,
        child: Container(
          padding: const EdgeInsets.all(6),
          margin: const EdgeInsets.only(left: 4),
          child: badge != null
              ? Badge(
                  label: Text(badge!, style: TextStyle(fontSize: context.sizes.fontXs)),
                  child: Icon(icon, size: 16, color: isDisabled ? cs.outline : color),
                )
              : Icon(icon, size: 16, color: isDisabled ? cs.outline : color),
        ),
      ),
    );
  }
}

// Compact cart item row
class _ModernCartItem extends StatelessWidget {
  final CartItem item;
  final double lineTotal;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final VoidCallback onRemove;

  const _ModernCartItem({
    required this.item,
    required this.lineTotal,
    required this.onDecrease,
    required this.onIncrease,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.2),
        borderRadius: context.radiusSm,
      ),
      child: Row(
        children: [
          // Product image
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: cs.primaryContainer.withOpacity(0.4),
              borderRadius: context.radiusSm,
            ),
            child: item.product.imageUrls.isNotEmpty
                ? ClipRRect(
                    borderRadius: context.radiusSm,
                    child: Image.network(
                      item.product.imageUrls.first,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(Icons.inventory_2_rounded, color: cs.onPrimaryContainer, size: 14),
                    ),
                  )
                : Icon(Icons.inventory_2_rounded, color: cs.onPrimaryContainer, size: 14),
          ),
          context.gapHSm,
          // Product info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.product.name,
                  style: TextStyle(fontWeight: FontWeight.w500, fontSize: context.sizes.fontSm, color: cs.onSurface),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '₹${item.product.price.toStringAsFixed(0)} × ${item.qty}',
                  style: TextStyle(fontSize: context.sizes.fontXs, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          // Quantity controls
          Container(
            decoration: BoxDecoration(
              borderRadius: context.radiusSm,
              border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _QtyButton(icon: Icons.remove, onTap: onDecrease),
                Container(
                  constraints: const BoxConstraints(minWidth: 24),
                  alignment: Alignment.center,
                  child: Text('${item.qty}', style: TextStyle(fontWeight: FontWeight.w600, fontSize: context.sizes.fontSm, color: cs.onSurface)),
                ),
                _QtyButton(icon: Icons.add, onTap: onIncrease),
              ],
            ),
          ),
          context.gapHSm,
          // Line total
          Text(
            '₹${lineTotal.toStringAsFixed(0)}',
            style: TextStyle(fontWeight: FontWeight.w600, color: cs.primary, fontSize: context.sizes.fontSm),
          ),
          // Remove button
          GestureDetector(
            onTap: onRemove,
            child: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Icon(Icons.close, size: 16, color: cs.error),
            ),
          ),
        ],
      ),
    );
  }
}

// Quantity button
class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _QtyButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: context.radiusXs,
      child: Padding(
        padding: context.padXs,
        child: Icon(icon, size: 14),
      ),
    );
  }
}

class CartHoldController {
  final Map<String, CartItem> cart;
  final List<HeldOrder> heldOrders;
  DiscountType discountType;
  final TextEditingController discountCtrl;
  final void Function() notify; // typically setState
  final void Function(String message) showMessage;

  CartHoldController({
    required this.cart,
    required this.heldOrders,
    required this.discountType,
    required this.discountCtrl,
    required this.notify,
    required this.showMessage,
  });

  void holdCart() {
    if (cart.isEmpty) return showMessage('Cart is empty');
    final snapshot = HeldOrder(
      id: 'HLD-${heldOrders.length + 1}',
      timestamp: DateTime.now(),
      items: cart.values.map((e) => e.copy()).toList(),
      discountType: discountType,
      discountValueText: discountCtrl.text,
    );
    heldOrders.add(snapshot);
    cart.clear();
    notify();
    showMessage('Order ${snapshot.id} held');
  }

  void resumeHeld(HeldOrder order) {
    cart.clear();
    for (final it in order.items) {
      cart[it.product.sku] = it.copy();
    }
    discountType = order.discountType;
    discountCtrl.text = order.discountValueText;
    heldOrders.removeWhere((o) => o.id == order.id);
    notify();
  }
}
