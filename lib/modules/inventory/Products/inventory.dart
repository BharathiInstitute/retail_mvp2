// ignore_for_file: use_build_context_synchronously
// Rebuilt Inventory module root screen (clean version)
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/firestore_store_collections.dart';
import '../../../core/theme/theme_extension_helpers.dart';
import '../../stores/providers.dart';

import '../../../core/paging/infinite_scroll_controller.dart';
import '../../../core/firebase/firestore_pagination_helper.dart';
import '../../../core/loading/page_loading_state_widget.dart';

import '../../../core/auth/auth_repository_and_provider.dart';
import '../../../core/user_permissions_provider.dart';
import 'inventory_repository.dart';
import 'csv_utils.dart';
import '../download_helper_stub.dart' if (dart.library.html) '../download_helper_web.dart';
import 'barcode_label_generator.dart';
import '../product_csv_import_screen.dart' show ImportProductsScreen;
import 'products_spreadsheet_screen.dart';
import 'ai_invoice_analyzer_screen.dart';
import '../category_management_screen.dart';
import 'product_image_uploader.dart';

// -------------------- Inventory Root Screen (Tabs) --------------------
class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Simplified: show Products by default; no TabBar.
    final owner = ref.watch(ownerProvider).asData?.value ?? false;
    final perms = ref.watch(permissionsProvider).asData?.value ?? UserPermissions.empty;
    if (!(owner || perms.can(ScreenKeys.invProducts, 'view'))) {
      return const Scaffold(body: Center(child: Text('No inventory access')));
    }
    return const Scaffold(
      body: _CloudProductsView(),
    );
  }
}

// Standalone Products screen for routing from side menu
class ProductsStandaloneScreen extends ConsumerWidget {
  const ProductsStandaloneScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Scaffold(
      body: _CloudProductsView(),
    );
  }
}

// -------------------- Products Providers & Views --------------------
final inventoryRepoProvider = Provider<InventoryRepository>((ref) => InventoryRepository());
final selectedStoreProvider = Provider<String?>((ref) => ref.watch(selectedStoreIdProvider));
final productsStreamProvider = StreamProvider.autoDispose<List<ProductDoc>>((ref) {
  final repo = ref.watch(inventoryRepoProvider);
  final storeId = ref.watch(selectedStoreIdProvider);
  if (storeId == null) return const Stream<List<ProductDoc>>.empty();
  return repo.streamProducts(storeId: storeId);
});

// Paged controller for Products (initial page blocks UI via PageLoaderOverlay)
final productsPagedControllerProvider = ChangeNotifierProvider.autoDispose<PagedListController<ProductDoc>>((ref) {
  final selId = ref.watch(selectedStoreIdProvider);
  // If no store is selected, do not hit Firestore at all; return an empty, end-reached pager.
  final Query<Map<String, dynamic>>? base =
      (selId == null) ? null : StoreRefs.of(selId).products().orderBy('name');

  final controller = PagedListController<ProductDoc>(
    pageSize: 50,
    loadPage: (cursor) async {
      if (base == null) {
        return (<ProductDoc>[], null);
      }
      final after = cursor as DocumentSnapshot<Map<String, dynamic>>?;
      final (items, next) = await fetchFirestorePage<ProductDoc>(
        base: base,
        after: after,
        pageSize: 50,
        map: (d) => ProductDoc.fromDoc(d),
      );
      return (items, next);
    },
  );

  // Kick first load
  Future.microtask(controller.resetAndLoad);
  ref.onDispose(controller.dispose);
  return controller;
});

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
  bool _isGridView = true; // Toggle between grid and list view
  // Horizontal scroll controller for drag/swipe panning on desktop/tablet/mobile
  final ScrollController _hScrollCtrl = ScrollController();
  // Vertical controller for infinite scroll
  final ScrollController _vScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _vScrollCtrl.addListener(_maybeLoadMoreOnScroll);
  }

  @override
  void dispose() {
    _hScrollCtrl.dispose();
    _vScrollCtrl.removeListener(_maybeLoadMoreOnScroll);
    _vScrollCtrl.dispose();
    super.dispose();
  }

  void _maybeLoadMoreOnScroll() {
    if (!_vScrollCtrl.hasClients) return;
    final extentAfter = _vScrollCtrl.position.extentAfter;
    // If we're within ~2 viewports of the bottom, try to load more
    if (extentAfter < 600) {
      final controller = ref.read(productsPagedControllerProvider);
      final s = controller.state;
      if (!s.loading && !s.endReached) {
        controller.loadMore();
      }
    }
  }

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
    final paged = ref.watch(productsPagedControllerProvider);
    final state = paged.state;
  final user = ref.watch(authStateProvider);
  final selStore = ref.watch(selectedStoreIdProvider);
  final bool isSignedIn = user != null;
    return Padding(
      padding: const EdgeInsets.all(10.0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LayoutBuilder(builder: (context, constraints) {
          final narrow = constraints.maxWidth < 560;
          final searchWidth = narrow ? 180.0 : 220.0;
          final btnMinH = 30.0;
          final btnPad = const EdgeInsets.symmetric(horizontal: 8, vertical: 4);
          final iconSize = 14.0;
          final fontSize = 11.0;
          final compactFilled = FilledButton.styleFrom(
            minimumSize: Size(0, btnMinH),
            padding: btnPad,
            visualDensity: VisualDensity.compact,
            textStyle: TextStyle(fontSize: fontSize),
          );
          final compactOutlined = OutlinedButton.styleFrom(
            minimumSize: Size(0, btnMinH),
            padding: btnPad,
            visualDensity: VisualDensity.compact,
            textStyle: TextStyle(fontSize: fontSize),
          );
          final searchBox = SizedBox(
            width: searchWidth,
            height: 32,
            child: TextField(
              style: TextStyle(fontSize: context.sizes.fontSm),
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.search, size: 16),
                hintText: 'Search SKU/Name/Barcode',
                hintStyle: TextStyle(fontSize: context.sizes.fontSm),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                floatingLabelBehavior: FloatingLabelBehavior.never,
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          );
          final activeDrop = DropdownButton<_ActiveFilter>(
            value: _activeFilter,
            onChanged: (v) => setState(() => _activeFilter = v ?? _ActiveFilter.all),
            isDense: true,
            style: TextStyle(fontSize: fontSize, color: Theme.of(context).colorScheme.onSurface),
            items: const [
              DropdownMenuItem(value: _ActiveFilter.all, child: Text('All')),
              DropdownMenuItem(value: _ActiveFilter.active, child: Text('Active')),
              DropdownMenuItem(value: _ActiveFilter.inactive, child: Text('Inactive')),
            ],
          );
          final gstDrop = DropdownButton<int>(
            value: _gstFilter,
            onChanged: (v) => setState(() => _gstFilter = v ?? -1),
            isDense: true,
            style: TextStyle(fontSize: fontSize, color: Theme.of(context).colorScheme.onSurface),
            items: const [
              DropdownMenuItem(value: -1, child: Text('GST: All')),
              DropdownMenuItem(value: 0, child: Text('0%')),
              DropdownMenuItem(value: 5, child: Text('5%')),
              DropdownMenuItem(value: 12, child: Text('12%')),
              DropdownMenuItem(value: 18, child: Text('18%')),
            ],
          );
          return Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              searchBox,
              activeDrop,
              gstDrop,
              FilledButton.icon(
                style: compactFilled,
                onPressed: isSignedIn && selStore != null ? () => _openAddDialog(context) : _requireSignInNotice,
                icon: Icon(Icons.add, size: iconSize),
                label: const Text('Add'),
              ),
              OutlinedButton.icon(
                style: compactOutlined,
                onPressed: () => _exportCsv(),
                icon: Icon(Icons.file_download_outlined, size: iconSize),
                label: const Text('Export'),
              ),
              OutlinedButton.icon(
                style: compactOutlined,
                onPressed: isSignedIn && selStore != null
                    ? () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const ImportProductsScreen()),
                        )
                    : _requireSignInNotice,
                icon: Icon(Icons.file_upload_outlined, size: iconSize),
                label: const Text('Import'),
              ),
              Builder(builder: (_) {
                final hasData = state.items.isNotEmpty;
                return OutlinedButton.icon(
                  style: compactOutlined,
                  onPressed: hasData ? () => _openPrintBarcodesDialog(context) : null,
                  icon: Icon(Icons.qr_code_2, size: iconSize),
                  label: const Text('Barcodes'),
                );
              }),
              OutlinedButton.icon(
                style: compactOutlined,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const InventorySheetPage()),
                ),
                icon: Icon(Icons.grid_on_outlined, size: iconSize),
                label: const Text('Sheet'),
              ),
              OutlinedButton.icon(
                style: compactOutlined,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CategoryScreen()),
                ),
                icon: Icon(Icons.category_outlined, size: iconSize),
                label: const Text('Categories'),
              ),
              OutlinedButton.icon(
                style: compactOutlined,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const InvoiceAnalysisPage()),
                ),
                icon: Icon(Icons.analytics_outlined, size: iconSize),
                label: const Text('Analysis'),
              ),
              // View toggle
              ToggleButtons(
                isSelected: [_isGridView, !_isGridView],
                onPressed: (i) => setState(() => _isGridView = i == 0),
                borderRadius: context.radiusSm,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                children: [
                  Icon(Icons.grid_view, size: context.sizes.iconSm),
                  Icon(Icons.view_list, size: context.sizes.iconSm),
                ],
              ),
            ],
          );
        }),
        const SizedBox(height: 10),
        Expanded(
          child: PageLoaderOverlay(
            loading: state.loading && state.items.isEmpty,
            error: state.error,
            onRetry: () => ref.read(productsPagedControllerProvider).resetAndLoad(),
            child: Builder(builder: (context) {
              final list = state.items;
              if (list.isEmpty && !state.loading) {
                return const Center(child: Text('No products found in Inventory.'));
              }
              final filtered = _applyFilters(list);
              _currentProducts = filtered; // cache (export current view)
              if (filtered.isEmpty && !state.loading) {
                return const Center(child: Text('No products match the filters.'));
              }
              return LayoutBuilder(builder: (context, constraints) {
                // Responsive grid: more columns on wider screens
                final crossAxisCount = constraints.maxWidth > 1200
                    ? 7
                    : constraints.maxWidth > 900
                        ? 6
                        : constraints.maxWidth > 600
                            ? 5
                            : 4;
                return Column(
                  children: [
                    Expanded(
                      child: _isGridView
                          ? GridView.builder(
                              controller: _vScrollCtrl,
                              padding: const EdgeInsets.all(6),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                mainAxisSpacing: 6,
                                crossAxisSpacing: 6,
                                childAspectRatio: 0.85,
                              ),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final p = filtered[index];
                                return _buildProductTile(context, p, isSignedIn);
                              },
                            )
                          : ListView.builder(
                              controller: _vScrollCtrl,
                              padding: const EdgeInsets.all(6),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final p = filtered[index];
                                return _buildProductListItem(context, p, isSignedIn);
                              },
                            ),
                    ),
                    if (!state.endReached)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: state.loading
                            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                            : OutlinedButton.icon(
                                onPressed: () => ref.read(productsPagedControllerProvider).loadMore(),
                                icon: const Icon(Icons.more_horiz),
                                label: const Text('Load more'),
                              ),
                      ),
                  ],
                );
              });
            }),
          ),
        ),
      ]),
    );
  }

  // List item for list view
  Widget _buildProductListItem(BuildContext context, ProductDoc p, bool isSignedIn) {
    final cs = Theme.of(context).colorScheme;
    final sizes = context.sizes;
    return Container(
      margin: EdgeInsets.only(bottom: sizes.gapSm),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: context.radiusMd,
        border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
        boxShadow: [BoxShadow(color: cs.shadow.withOpacity(0.03), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      child: InkWell(
        borderRadius: context.radiusMd,
        onTap: () => _showProductDetail(context, p, isSignedIn),
        child: Padding(
          padding: context.padSm,
          child: Row(
            children: [
              // Product Image
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: context.radiusSm,
                  color: cs.surfaceContainerHighest,
                ),
                child: p.imageUrls.isNotEmpty
                    ? ClipRRect(
                        borderRadius: context.radiusSm,
                        child: Image.network(p.imageUrls.first, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(Icons.broken_image_outlined, size: sizes.iconSm, color: cs.outline),
                        ),
                      )
                    : Icon(Icons.inventory_2_outlined, size: sizes.iconSm, color: cs.outline),
              ),
              SizedBox(width: sizes.gapMd),
              // Product Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(p.name, style: TextStyle(fontWeight: FontWeight.w600, fontSize: sizes.fontSm, color: cs.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis),
                    SizedBox(height: sizes.gapXs),
                    Row(
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: sizes.gapXs, vertical: 1),
                          decoration: BoxDecoration(color: cs.primaryContainer.withOpacity(0.5), borderRadius: context.radiusSm),
                          child: Text(p.sku, style: TextStyle(fontSize: sizes.fontXs, color: cs.primary, fontWeight: FontWeight.w500)),
                        ),
                        if (p.barcode.isNotEmpty) ...[
                          SizedBox(width: sizes.gapSm),
                          Expanded(child: Text(p.barcode, style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurfaceVariant), overflow: TextOverflow.ellipsis)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Price
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('₹${p.unitPrice.toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: sizes.fontSm, color: cs.primary)),
                  if ((p.taxPct ?? 0) > 0) Text('+${p.taxPct}%', style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurfaceVariant)),
                ],
              ),
              SizedBox(width: sizes.gapSm),
              // Stock
              Container(
                padding: EdgeInsets.symmetric(horizontal: sizes.gapSm, vertical: sizes.gapXs),
                decoration: BoxDecoration(
                  color: p.totalStock > (p.minStock ?? 0) ? context.appColors.success.withOpacity(0.1) : context.appColors.warning.withOpacity(0.1),
                  borderRadius: context.radiusSm,
                ),
                child: Text('${p.totalStock}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: sizes.fontXs,
                  color: p.totalStock > (p.minStock ?? 0) ? context.appColors.success : context.appColors.warning)),
              ),
              SizedBox(width: sizes.gapSm),
              // Status
              Container(
                width: 16, height: 16,
                decoration: BoxDecoration(color: p.isActive ? context.appColors.success : cs.error, shape: BoxShape.circle),
                child: Icon(p.isActive ? Icons.check : Icons.close, size: 10, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Simple image tile for grid - shows only product image with name overlay
  Widget _buildProductTile(BuildContext context, ProductDoc p, bool isSignedIn) {
    final cs = Theme.of(context).colorScheme;
    final sizes = context.sizes;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: context.radiusMd,
        border: Border.all(color: cs.outlineVariant.withOpacity(0.4)),
        boxShadow: [BoxShadow(color: cs.shadow.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: context.radiusMd,
          onTap: () => _showProductDetail(context, p, isSignedIn),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Image section
              Expanded(
                flex: 3,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                      child: p.imageUrls.isNotEmpty
                          ? Image.network(p.imageUrls.first, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: cs.surfaceContainerHighest,
                                child: Icon(Icons.inventory_2_outlined, size: 28, color: cs.outline),
                              ),
                            )
                          : Container(
                              color: cs.surfaceContainerHighest,
                              child: Icon(Icons.inventory_2_outlined, size: 28, color: cs.outline),
                            ),
                    ),
                    // Status indicator
                    Positioned(
                      top: 4, right: 4,
                      child: Container(
                        width: 14, height: 14,
                        decoration: BoxDecoration(color: p.isActive ? context.appColors.success : cs.error, shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5)),
                        child: Icon(p.isActive ? Icons.check : Icons.close, size: 8, color: Colors.white),
                      ),
                    ),
                    // Image count
                    if (p.imageUrls.length > 1)
                      Positioned(
                        top: 4, left: 4,
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: sizes.gapXs, vertical: 1),
                          decoration: BoxDecoration(color: Colors.black54, borderRadius: context.radiusSm),
                          child: Text('${p.imageUrls.length}', style: TextStyle(color: Colors.white, fontSize: sizes.fontXs, fontWeight: FontWeight.w600)),
                        ),
                      ),
                  ],
                ),
              ),
              // Info section
              Expanded(
                flex: 2,
                child: Padding(
                  padding: context.padSm,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name, style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w600, color: cs.onSurface), maxLines: 2, overflow: TextOverflow.ellipsis),
                      const Spacer(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('₹${p.unitPrice.toStringAsFixed(0)}', style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w700, color: cs.primary)),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: sizes.gapXs, vertical: 1),
                            decoration: BoxDecoration(
                              color: p.totalStock > (p.minStock ?? 0) ? context.appColors.success.withOpacity(0.15) : context.appColors.warning.withOpacity(0.15),
                              borderRadius: context.radiusSm,
                            ),
                            child: Text('${p.totalStock}', style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w700,
                              color: p.totalStock > (p.minStock ?? 0) ? context.appColors.success : context.appColors.warning)),
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
      ),
    );
  }

  // E-commerce style product detail view
  void _showProductDetail(BuildContext context, ProductDoc p, bool isSignedIn) {
    showDialog(
      context: context,
      builder: (ctx) => _ProductDetailDialog(
        product: p,
        isSignedIn: isSignedIn,
        onEdit: () {
          Navigator.pop(ctx);
          _openEditDialog(context, p);
        },
        onDelete: () {
          Navigator.pop(ctx);
          _confirmDelete(context, p);
        },
      ),
    );
  }

  Future<void> _openAddDialog(BuildContext context) async {
    final user = ref.read(authStateProvider);
    if (user == null) {
      _requireSignInNotice();
      return;
    }
    final storeId = ref.read(selectedStoreIdProvider);
    if (storeId == null) {
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
    await repo.addProduct(
      storeId: storeId,
      sku: result.sku,
      name: result.name,
      unitPrice: result.unitPrice,
      costPrice: result.costPrice,
      discountPct: result.discountPct,
      category: result.category,
      subCategory: result.subCategory,
      quantityPerUnit: result.quantityPerUnit,
      barcode: result.barcode,
      description: result.description,
      variants: result.variants,
        imageUrls: result.imageUrls,
      mrpPrice: result.mrpPrice,
      height: result.height,
      width: result.width,
      weight: result.weight,
      volumeMl: result.volumeMl,
      minStock: result.minStock,
      isActive: result.isActive,
      storeQty: result.storeQty,
      warehouseQty: result.warehouseQty,
    );
    // Refresh first page to include new item if visible
    ref.read(productsPagedControllerProvider).resetAndLoad();
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
    final storeId = ref.read(selectedStoreIdProvider);
    if (storeId == null) { _requireSignInNotice(); return; }
    await repo.updateProduct(
      storeId: storeId,
      sku: p.sku,
      name: result.name,
      unitPrice: result.unitPrice,
      taxPct: result.taxPct,
      barcode: result.barcode,
      description: result.description,
      imageUrls: result.imageUrls,
      costPrice: result.costPrice,
      discountPct: result.discountPct,
      category: result.category,
      subCategory: result.subCategory,
      quantityPerUnit: result.quantityPerUnit,
      height: result.height,
      width: result.width,
      weight: result.weight,
      volumeMl: result.volumeMl,
      minStock: result.minStock,
      isActive: result.isActive,
    );
    ref.read(productsPagedControllerProvider).resetAndLoad();
    if (mounted) messenger.showSnackBar(const SnackBar(content: Text('Product updated')));
  }

  Future<void> _confirmDelete(BuildContext context, ProductDoc p) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (dialogCtx) => AlertDialog(
        title: Text(
          'Delete Product',
          style: Theme.of(dialogCtx).textTheme.titleMedium?.copyWith(
                color: Theme.of(dialogCtx).colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
        ),
        content: DefaultTextStyle(
          style: (Theme.of(dialogCtx).textTheme.bodyMedium ?? const TextStyle())
              .copyWith(color: Theme.of(dialogCtx).colorScheme.onSurface),
          child: Text('Are you sure you want to delete ${p.name} (${p.sku})?'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogCtx).colorScheme.error,
              foregroundColor: Theme.of(dialogCtx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
  final repo = ref.read(inventoryRepoProvider);
    final storeId = ref.read(selectedStoreIdProvider);
    if (storeId == null) { _requireSignInNotice(); return; }
    await repo.deleteProduct(storeId: storeId, sku: p.sku);
    ref.read(productsPagedControllerProvider).resetAndLoad();
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
          title: Text(
            'Export CSV',
            style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                  color: Theme.of(ctx).colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
          ),
          content: DefaultTextStyle(
            style: (Theme.of(ctx).textTheme.bodyMedium ?? const TextStyle())
                .copyWith(color: Theme.of(ctx).colorScheme.onSurface),
            child: SizedBox(width: 700, child: SelectableText(csv)),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
        ),
      );
    });
  }

  void _openPrintBarcodesDialog(BuildContext context) {
    if (_currentProducts.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => PrintBarcodesDialog(products: _currentProducts),
    );
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
  // Pricing
  final double unitPrice; // selling price
  final double? costPrice; // buying price
  final num? discountPct;
  // Classification
  final String? category;
  final String? subCategory;
  final String? quantityPerUnit;
  final String? barcode;
  final String? description;
  final List<String> variants;
  final double? mrpPrice;
  final double? height;
  final double? width;
  final double? weight;
    final double? volumeMl;
  final int? minStock;
  final bool isActive;
  final int storeQty;
  final int warehouseQty;
  final List<String> imageUrls;
  _AddProductResult({
    required this.sku,
    required this.name,
    required this.unitPrice,
    this.costPrice,
    this.discountPct,
    this.category,
    this.subCategory,
    this.quantityPerUnit,
    this.barcode,
    this.description,
    required this.variants,
    this.mrpPrice,
    this.height,
    this.width,
    this.weight,
      this.volumeMl,
    this.minStock,
    required this.isActive,
    required this.storeQty,
    required this.warehouseQty,
    required this.imageUrls,
  });
}

class _AddProductDialog extends StatefulWidget {
  const _AddProductDialog();
  @override
  State<_AddProductDialog> createState() => _AddProductDialogState();
}

class _PickedImage {
  final String name;
  final Uint8List bytes;
  _PickedImage({required this.name, required this.bytes});
}

class _AddProductDialogState extends State<_AddProductDialog> {
  final _formKey = GlobalKey<FormState>();
  final _sku = TextEditingController();
  final _name = TextEditingController();
  // New fields per request
  final _buyingPrice = TextEditingController();
  final _sellingPrice = TextEditingController();
  final _discountPct = TextEditingController();
  final _category = TextEditingController();
  final _subCategory = TextEditingController();
  final _quantityPerUnit = TextEditingController();
  final _minStock = TextEditingController();
  final _barcode = TextEditingController();
  final _description = TextEditingController();
  // Legacy controllers kept for compatibility but not shown
  final _unitPrice = TextEditingController(text: '0');
  final _taxPct = TextEditingController();
  final _variants = TextEditingController();
  final _mrpPrice = TextEditingController();
  final _costPrice = TextEditingController();
  final _height = TextEditingController();
  final _width = TextEditingController();
  final _weight = TextEditingController();
  final _volumeMl = TextEditingController();
  final _quantity = TextEditingController();
  final _storeQty = TextEditingController(text: '0');
  final _warehouseQty = TextEditingController(text: '0');
  bool _isActive = true;
  final List<_PickedImage?> _pickedImages = List<_PickedImage?>.filled(3, null);
  final ImagePicker _picker = ImagePicker();
  bool _uploading = false;
  // Upload error message (read in UI for inline display)
  // ignore: unused_field
  String? _uploadError;
  List<double> _progress = [0,0,0];

  int _firstEmptySlot() {
    for (int i = 0; i < 3; i++) {
      if (_pickedImages[i] == null) return i;
    }
    return 0;
  }

  void _removeImage(int index) async {
    if (_pickedImages[index] == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text('Remove Image', style: Theme.of(ctx).textTheme.titleMedium?.copyWith(color: Theme.of(ctx).colorScheme.onSurface, fontWeight: FontWeight.w700)),
        content: DefaultTextStyle(
          style: (Theme.of(ctx).textTheme.bodyMedium ?? const TextStyle()).copyWith(color: Theme.of(ctx).colorScheme.onSurface),
          child: const Text('Do you want to remove this image?'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirm == true) {
      setState(() => _pickedImages[index] = null);
    }
  }

  void _showImagePreview(int index) {
    final data = _pickedImages[index];
    if (data == null) return;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: Text(data.name, style: Theme.of(ctx).textTheme.titleMedium?.copyWith(color: Theme.of(ctx).colorScheme.onSurface, fontWeight: FontWeight.w700)),
        content: DefaultTextStyle(
          style: (Theme.of(ctx).textTheme.bodyMedium ?? const TextStyle()).copyWith(color: Theme.of(ctx).colorScheme.onSurface),
          child: SizedBox(
            width: 400,
            child: Image.memory(data.bytes, fit: BoxFit.contain),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _removeImage(index);
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  Future<String?> _promptText(BuildContext context, String title, {String? initial}) async {
    final ctrl = TextEditingController(text: initial ?? '');
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Enter text'),
          onSubmitted: (v) => Navigator.of(dialogCtx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(ctrl.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  CollectionReference<Map<String, dynamic>> _catsCol(String storeId) =>
      FirebaseFirestore.instance.collection('stores').doc(storeId).collection('categories');

  Future<void> _scanBarcode() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Barcode scanning not available on web. Use mobile app.')),
      );
      return;
    }
    
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => const _BarcodeScannerScreen(),
      ),
    );
    
    if (result != null && result.isNotEmpty && mounted) {
      setState(() {
        _barcode.text = result;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Barcode scanned: $result'), backgroundColor: context.appColors.success),
      );
    }
  }

  String _skuPrefixFromCategory(String category) {
    final letters = category.replaceAll(RegExp('[^A-Za-z]'), '').toUpperCase();
    final padded = ('${letters}XXXX');
    return padded.substring(0, 4);
  }

  Future<void> _generateSku() async {
    final cat = _category.text.trim();
    if (cat.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter or select a Category first')),
      );
      return;
    }
    final sid = ProviderScope.containerOf(context).read(selectedStoreIdProvider);
    if (sid == null || sid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a store first')),
      );
      return;
    }
    try {
      final col = _catsCol(sid);
      DocumentReference<Map<String, dynamic>> docRef;
      final existing = await col.where('name', isEqualTo: cat).limit(1).get();
      if (existing.docs.isEmpty) {
        docRef = await col.add({'name': cat, 'subcategories': <String>[], 'counter': 0});
      } else {
        docRef = existing.docs.first.reference;
      }
      final nextNum = await FirebaseFirestore.instance.runTransaction<int>((txn) async {
        final snap = await txn.get(docRef);
        final current = (snap.data()?['counter'] as int?) ?? 0;
        final next = current + 1;
        txn.update(docRef, {'counter': next});
        return next;
      });
      final prefix = _skuPrefixFromCategory(cat);
      final serial = nextNum.toString().padLeft(4, '0');
      setState(() => _sku.text = '$prefix$serial');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to generate SKU: $e')));
    }
  }

  void _generateBarcodeFromSku() {
    final s = _sku.text.trim();
    if (s.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter or generate SKU first')));
      return;
    }
    final ean = _ean13FromSku(s);
    setState(() => _barcode.text = ean);
  }

  String _ean13FromSku(String sku) {
    // Build 12-digit payload: 4 letters -> 8 digits (A=01..Z=26), plus 4-digit serial from trailing digits
    final lettersOnly = sku.replaceAll(RegExp('[^A-Za-z]'), '').toUpperCase();
    final fourLetters = ('${lettersOnly}AAAA').substring(0, 4);
    final letterDigits = fourLetters
        .split('')
        .map((ch) {
          final code = ch.codeUnitAt(0) - 64; // A->1
          final safe = (code >= 1 && code <= 26) ? code : 0;
          return safe.toString().padLeft(2, '0');
        })
        .join();
    final serialMatch = RegExp(r'(\d+)$').firstMatch(sku);
    final serial4 = (serialMatch?.group(1) ?? '0001');
    final serial = serial4.length >= 4 ? serial4.substring(serial4.length - 4) : serial4.padLeft(4, '0');
    final payload = '$letterDigits$serial'; // 12 digits
    final check = _ean13CheckDigit(payload);
    return '$payload$check';
  }

  int _ean13CheckDigit(String twelveDigits) {
    if (twelveDigits.length != 12) {
      // Fallback: pad or trim to 12 digits
      final digitsOnly = twelveDigits.replaceAll(RegExp('[^0-9]'), '');
      final padded = ('${digitsOnly}000000000000').substring(0, 12);
      twelveDigits = padded;
    }
    int sum = 0;
    for (int i = 0; i < 12; i++) {
      final d = int.parse(twelveDigits[i]);
      // positions are 1-indexed; even positions (i%2==1) weighted by 3
      sum += (i % 2 == 1) ? (3 * d) : d;
    }
    final mod = sum % 10;
    return (10 - mod) % 10;
  }

  Future<void> _quickAddCategory() async {
    final text = await _promptText(context, 'Add category', initial: _category.text.trim().isEmpty ? null : _category.text.trim());
    if (text == null || text.trim().isEmpty) return;
    final sid = ProviderScope.containerOf(context).read(selectedStoreIdProvider);
    if (sid == null || sid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a store first')));
      return;
    }
    final name = text.trim();
    try {
      final existing = await _catsCol(sid).where('name', isEqualTo: name).limit(1).get();
      if (existing.docs.isEmpty) {
        await _catsCol(sid).add({'name': name, 'subcategories': <String>[]});
      }
      setState(() => _category.text = name);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to add category: $e')));
    }
  }

  Future<void> _quickAddSubCategory() async {
    if (_category.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter or add a Category first')),
      );
      return;
    }
    final text = await _promptText(context, 'Add sub category', initial: _subCategory.text.trim().isEmpty ? null : _subCategory.text.trim());
    if (text == null || text.trim().isEmpty) return;
    final sid = ProviderScope.containerOf(context).read(selectedStoreIdProvider);
    if (sid == null || sid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a store first')));
      return;
    }
    final name = text.trim();
    try {
      final q = await _catsCol(sid).where('name', isEqualTo: _category.text.trim()).limit(1).get();
      if (q.docs.isEmpty) {
        // If category not found, create it first
        final doc = await _catsCol(sid).add({'name': _category.text.trim(), 'subcategories': <String>[]});
        await _catsCol(sid).doc(doc.id).update({'subcategories': FieldValue.arrayUnion([name])});
      } else {
        await _catsCol(sid).doc(q.docs.first.id).update({'subcategories': FieldValue.arrayUnion([name])});
      }
      setState(() => _subCategory.text = name);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to add subcategory: $e')));
    }
  }

  

  Future<void> _pickImageShowOptions([int? slot]) async {
    final index = slot ?? _firstEmptySlot();
    
    // On mobile, show options for camera or gallery
    if (!kIsWeb) {
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Take Photo'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from Gallery'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('Cancel'),
                onTap: () => Navigator.pop(ctx),
              ),
            ],
          ),
        ),
      );
      
      if (source == null || !mounted) return;
      
      final XFile? img = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      
      if (!mounted) return;
      if (img != null) {
        final bytes = await img.readAsBytes();
        setState(() {
          _pickedImages[index] = _PickedImage(name: img.name, bytes: bytes);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Image added: ${img.name}'),
            backgroundColor: context.appColors.success,
          ),
        );
      }
      return;
    }
    
    // Web: use gallery only
    final XFile? img = await _picker.pickImage(
      source: ImageSource.gallery, 
      maxWidth: 1024, 
      maxHeight: 1024, 
      imageQuality: 85,
    );
    
    if (!mounted) return;
    if (img != null) {
      final bytes = await img.readAsBytes();
      setState(() {
        _pickedImages[index] = _PickedImage(name: img.name, bytes: bytes);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Image added: ${img.name}'),
          backgroundColor: context.appColors.success,
        ),
      );
    }
  }

  @override
  void dispose() {
    _sku.dispose();
    _name.dispose();
    _buyingPrice.dispose();
    _sellingPrice.dispose();
    _discountPct.dispose();
    _category.dispose();
    _subCategory.dispose();
    _quantityPerUnit.dispose();
    _minStock.dispose();
    _unitPrice.dispose();
    _taxPct.dispose();
    _barcode.dispose();
    _description.dispose();
    _variants.dispose();
    _mrpPrice.dispose();
    _costPrice.dispose();
    _height.dispose();
    _width.dispose();
    _weight.dispose();
    _volumeMl.dispose();
    _quantity.dispose();
    _storeQty.dispose();
    _warehouseQty.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Add Product',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              TextButton(onPressed: _pickImageShowOptions, child: const Text('Upload Image')),
            ],
          ),
          context.gapVSm,
          // Preview strip directly below title
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(3, (i) {
                final data = _pickedImages[i];
                final uploadingThis = _uploading && data != null && _progress[i] < 1.0;
                final failed = _uploadError != null;
                final sizes = context.sizes;
                return Padding(
                  padding: EdgeInsets.only(right: i < 2 ? sizes.gapMd : 0.0, top: sizes.gapXs),
                  child: InkWell(
                    onTap: () => (_uploading) ? null : (data == null ? _pickImageShowOptions(i) : _showImagePreview(i)),
                    borderRadius: context.radiusSm,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: data != null 
                                  ? Theme.of(context).colorScheme.primary 
                                  : Theme.of(context).colorScheme.outlineVariant,
                              width: data != null ? 2 : 1,
                            ),
                            borderRadius: context.radiusSm,
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          ),
                          child: data == null
                              ? Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      i == 0 ? Icons.add_a_photo_outlined : Icons.add_photo_alternate_outlined, 
                                      size: sizes.iconMd,
                                      color: i == 0 ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary,
                                    ),
                                    SizedBox(height: sizes.gapXs),
                                    Text(
                                      i == 0 ? 'Add *' : 'Image ${i + 1}', 
                                      style: TextStyle(
                                        fontSize: sizes.fontXs,
                                        color: i == 0 ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                )
                              : ClipRRect(
                                  borderRadius: context.radiusSm,
                                  child: Image.memory(
                                    data.bytes, 
                                    fit: BoxFit.cover, 
                                    width: 80, 
                                    height: 80,
                                    errorBuilder: (ctx, err, stack) => const Center(
                                      child: Icon(Icons.broken_image, size: 24),
                                    ),
                                  ),
                                ),
                        ),
                        if (data != null && !_uploading)
                          Positioned(
                            top: -6,
                            right: -6,
                            child: GestureDetector(
                              onTap: () => _removeImage(i),
                              child: Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.error,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 1.5),
                                ),
                                child: const Icon(Icons.close, size: 12, color: Colors.white),
                              ),
                            ),
                          ),
                        if (uploadingThis)
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black38,
                                borderRadius: context.radiusSm,
                              ),
                              child: Center(
                                child: SizedBox(
                                  width: 42,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const CircularProgressIndicator(strokeWidth: 3),
                                      SizedBox(height: sizes.gapSm),
                                      Text('${(_progress[i]*100).toStringAsFixed(0)}%', style: TextStyle(fontSize: sizes.fontXs, color: Colors.white)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (data != null && _uploading && _progress[i] >= 1.0 && _uploadError == null)
                          Positioned(
                            bottom: 4,
                            right: 4,
                            child: Icon(Icons.check_circle, color: context.appColors.success, size: 20),
                          ),
                        if (data != null && failed)
                          Positioned(
                            bottom: 4,
                            right: 4,
                            child: const Icon(Icons.error, color: Colors.redAccent, size: 20),
                          ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
          if (_uploadError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6.0),
              child: Text('Upload failed: $_uploadError', style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: context.sizes.fontSm)),
            ),
        ],
      ),
      content: DefaultTextStyle(
        style: (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
            .copyWith(color: Theme.of(context).colorScheme.onSurface),
        child: Form(
        key: _formKey,
        child: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Category and Sub Category - moved to top after images
                Builder(builder: (ctx) {
                  final storeId = ProviderScope.containerOf(ctx).read(selectedStoreIdProvider);
                  if (storeId == null || storeId.isEmpty) {
                    // Fallback to simple inputs if no store is selected
                    return Row(children: [
                      Expanded(
                        child: TextFormField(
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                          controller: _category,
                          decoration: InputDecoration(
                            labelText: 'Category *',
                            suffixIcon: IconButton(
                              tooltip: 'Add Category',
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: _quickAddCategory,
                            ),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                        ),
                      ),
                      context.gapHMd,
                      Expanded(
                        child: TextFormField(
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                          controller: _subCategory,
                          decoration: InputDecoration(
                            labelText: 'Sub Category',
                            suffixIcon: IconButton(
                              tooltip: 'Add Sub Category',
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: _quickAddSubCategory,
                            ),
                          ),
                        ),
                      ),
                    ]);
                  }
                  final stream = FirebaseFirestore.instance
                      .collection('stores')
                      .doc(storeId)
                      .collection('categories')
                      .orderBy('name')
                      .snapshots();
                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: stream,
                    builder: (ctx, snap) {
                      final cats = <String>[];
                      final subsByCat = <String, List<String>>{};
                      if (snap.hasData) {
                        for (final d in snap.data!.docs) {
                          final data = d.data();
                          final name = (data['name'] ?? '') as String;
                          cats.add(name);
                          subsByCat[name] = List<String>.from((data['subcategories'] ?? const <dynamic>[]) as List<dynamic>);
                        }
                      }
                      final selCat = _category.text.trim().isEmpty ? null : _category.text.trim();
                      final subs = selCat == null ? const <String>[] : (subsByCat[selCat] ?? const <String>[]);
                      return Row(children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: 'Category *',
                              suffixIcon: IconButton(
                                tooltip: 'Add Category',
                                icon: const Icon(Icons.add_circle_outline),
                                onPressed: _quickAddCategory,
                              ),
                            ),
                            value: (selCat != null && cats.contains(selCat)) ? selCat : null,
                            items: cats.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                            onChanged: (v) => setState(() {
                              _category.text = v ?? '';
                              _subCategory.clear();
                            }),
                            validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                          ),
                        ),
                        context.gapHMd,
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: 'Sub Category',
                              suffixIcon: IconButton(
                                tooltip: 'Add Sub Category',
                                icon: const Icon(Icons.add_circle_outline),
                                onPressed: _quickAddSubCategory,
                              ),
                            ),
                            value: _subCategory.text.trim().isEmpty ? null : _subCategory.text.trim(),
                            items: subs.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                            onChanged: subs.isEmpty
                                ? null
                                : (v) => setState(() {
                                      _subCategory.text = v ?? '';
                                    }),
                          ),
                        ),
                      ]);
                    },
                  );
                }),
                context.gapVSm,
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                      controller: _sku,
                      decoration: InputDecoration(
                        labelText: 'SKU *',
                        suffixIcon: IconButton(
                          tooltip: 'Generate SKU',
                          icon: const Icon(Icons.auto_awesome),
                          onPressed: _generateSku,
                        ),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                  ),
                  context.gapHMd,
                  Expanded(
                    child: TextFormField(
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                      controller: _barcode,
                      decoration: InputDecoration(
                        labelText: 'Barcode *',
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Generate from SKU',
                              icon: const Icon(Icons.auto_awesome),
                              onPressed: _generateBarcodeFromSku,
                            ),
                            IconButton(
                              tooltip: 'Scan Barcode',
                              icon: const Icon(Icons.qr_code_scanner_outlined),
                              onPressed: _scanBarcode,
                            ),
                          ],
                        ),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                  ),
                ]),
                TextFormField(style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface), controller: _name, decoration: const InputDecoration(labelText: 'Name *'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
                Row(children: [
                  Expanded(child: TextFormField(style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface), controller: _buyingPrice, decoration: const InputDecoration(labelText: 'Buying Price'), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
                  context.gapHMd,
                  Expanded(child: TextFormField(
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface), 
                    controller: _sellingPrice, 
                    decoration: const InputDecoration(labelText: 'Selling Price *'), 
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Required';
                      final price = double.tryParse(v.trim());
                      if (price == null || price <= 0) return 'Enter valid price';
                      return null;
                    },
                  )),
                ]),
                Row(children: [
                  Expanded(child: TextFormField(style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface), controller: _discountPct, decoration: const InputDecoration(labelText: 'Discount %'), keyboardType: const TextInputType.numberWithOptions(decimal: true)) ),
                  context.gapHMd,
                  Expanded(child: TextFormField(style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface), controller: _quantityPerUnit, decoration: const InputDecoration(labelText: 'Unit / Count'))),
                ]),
                Row(children: [
                  Expanded(child: TextFormField(style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface), controller: _height, decoration: const InputDecoration(labelText: 'Height (cm)'), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
                  context.gapHMd,
                  Expanded(child: TextFormField(style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface), controller: _width, decoration: const InputDecoration(labelText: 'Width (cm)'), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
                  context.gapHMd,
                  Expanded(child: TextFormField(style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface), controller: _weight, decoration: const InputDecoration(labelText: 'Weight (g)'), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
                  context.gapHMd,
                  Expanded(child: TextFormField(style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface), controller: _volumeMl, decoration: const InputDecoration(labelText: 'Volume (ml)'), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
                ]),
                TextFormField(style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface), controller: _minStock, decoration: const InputDecoration(labelText: 'Min Stock'), keyboardType: TextInputType.number),
                TextFormField(style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface), controller: _description, decoration: const InputDecoration(labelText: 'Description')),
                // Removed single-file indicator; use image boxes above
                context.gapVSm,
                CheckboxListTile(value: _isActive, onChanged: (v) => setState(() => _isActive = v ?? true), title: const Text('Active')),
                Row(children: [
                  Expanded(child: TextFormField(style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface), controller: _storeQty, decoration: const InputDecoration(labelText: 'Initial Store Qty'), keyboardType: TextInputType.number)),
                  context.gapHMd,
                  Expanded(child: TextFormField(style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface), controller: _warehouseQty, decoration: const InputDecoration(labelText: 'Initial Warehouse Qty'), keyboardType: TextInputType.number)),
                ]),
              ],
            ),
          ),
        ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        // Upload button moved to title
        FilledButton(
          onPressed: _uploading ? null : () async {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            
            // Validate required fields
            final List<String> missingFields = [];
            
            if (_category.text.trim().isEmpty) {
              missingFields.add('Category');
            }
            if (_sku.text.trim().isEmpty) {
              missingFields.add('SKU');
            }
            if (_name.text.trim().isEmpty) {
              missingFields.add('Name');
            }
            if (_sellingPrice.text.trim().isEmpty || (double.tryParse(_sellingPrice.text.trim()) ?? 0) <= 0) {
              missingFields.add('Selling Price');
            }
            if (_barcode.text.trim().isEmpty) {
              missingFields.add('Barcode');
            }
            // Check for at least 1 image
            final hasImage = _pickedImages.any((img) => img != null);
            if (!hasImage) {
              missingFields.add('At least 1 Image');
            }
            
            if (missingFields.isNotEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Required: ${missingFields.join(", ")}'),
                  backgroundColor: Theme.of(context).colorScheme.error,
                  duration: const Duration(seconds: 3),
                ),
              );
              return;
            }
            
            setState(() { _uploadError = null; });
            final parsedQty = int.tryParse(_quantity.text.trim());
            int storeQty = int.tryParse(_storeQty.text.trim()) ?? 0;
            int warehouseQty = int.tryParse(_warehouseQty.text.trim()) ?? 0;
            if ((storeQty == 0 && warehouseQty == 0) && (parsedQty != null && parsedQty > 0)) {
              storeQty = parsedQty;
            }
            final buyingPrice = double.tryParse(_buyingPrice.text.trim());
            final sellingPrice = double.tryParse(_sellingPrice.text.trim()) ?? 0;
            final discountPct = _discountPct.text.trim().isEmpty ? null : num.tryParse(_discountPct.text.trim());
            final minStock = _minStock.text.trim().isEmpty ? null : int.tryParse(_minStock.text.trim());
            final parsedHeight = _height.text.trim().isEmpty ? null : double.tryParse(_height.text.trim());
            final parsedWidth = _width.text.trim().isEmpty ? null : double.tryParse(_width.text.trim());
            // Prepare images
            final imageBytes = _pickedImages.whereType<_PickedImage>().map((e) => e.bytes).toList();
            List<String> imageUrls = const [];
            if (imageBytes.isNotEmpty) {
              final storeId = ProviderScope.containerOf(context).read(selectedStoreIdProvider);
              if (storeId == null || storeId.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select store before uploading images')));
                return;
              }
              setState(() { _uploading = true; _progress = [0,0,0]; });
              try {
                imageUrls = await uploadProductImages(
                  storeId: storeId,
                  sku: _sku.text.trim(),
                  images: imageBytes,
                  onProgress: (index, prog) { setState(() { _progress[index] = prog; }); },
                );
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Uploaded ${imageUrls.length} image(s) successfully')));
              } catch (e) {
                setState(() { _uploadError = e.toString(); _uploading = false; });
                final msg = e.toString();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Image upload failed. Tap to view details'), duration: const Duration(seconds: 4), action: SnackBarAction(label: 'Details', onPressed: () {
                  showDialog(context: context, builder: (_) => AlertDialog(title: const Text('Upload Errors'), content: SingleChildScrollView(child: Text(msg)), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))]));
                })));
                return; // abort save product to allow user to retry
              } finally {
                setState(() { _uploading = false; });
              }
            }
            final result = _AddProductResult(
              sku: _sku.text.trim(),
              name: _name.text.trim(),
              unitPrice: sellingPrice,
              costPrice: buyingPrice,
              discountPct: discountPct,
              category: _category.text.trim().isEmpty ? null : _category.text.trim(),
              subCategory: _subCategory.text.trim().isEmpty ? null : _subCategory.text.trim(),
              quantityPerUnit: _quantityPerUnit.text.trim().isEmpty ? null : _quantityPerUnit.text.trim(),
              barcode: _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
              description: _description.text.trim().isEmpty ? null : _description.text.trim(),
              variants: const <String>[],
              mrpPrice: null,
              height: parsedHeight,
              width: parsedWidth,
              weight: _weight.text.trim().isEmpty ? null : double.tryParse(_weight.text.trim()),
              volumeMl: _volumeMl.text.trim().isEmpty ? null : double.tryParse(_volumeMl.text.trim()),
              minStock: minStock,
              isActive: _isActive,
              storeQty: storeQty,
              warehouseQty: warehouseQty,
              imageUrls: imageUrls,
            );
            Navigator.pop(context, result);
          },
          child: _uploading ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
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
  final double? costPrice;
  final double? height;
  final double? width;
  final double? weight;
  final double? volumeMl;
  final bool? isActive;
  final String? category;
  final String? subCategory;
  final String? quantityPerUnit;
  final num? discountPct;
  final int? minStock;
  final List<String>? imageUrls;
  _EditProductResult({
    this.name,
    this.unitPrice,
    this.taxPct,
    this.barcode,
    this.description,
    this.costPrice,
    this.height,
    this.width,
    this.weight,
    this.volumeMl,
    this.isActive,
    this.category,
    this.subCategory,
    this.quantityPerUnit,
    this.discountPct,
    this.minStock,
    this.imageUrls,
  });
}

class _EditProductDialog extends ConsumerStatefulWidget {
  final ProductDoc product;
  const _EditProductDialog({required this.product});
  @override
  ConsumerState<_EditProductDialog> createState() => _EditProductDialogState();
}

class _EditProductDialogState extends ConsumerState<_EditProductDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _sellingPrice;
  late final TextEditingController _costPrice;
  late final TextEditingController _taxPct;
  late final TextEditingController _barcode;
  late final TextEditingController _description;
  late final TextEditingController _category;
  late final TextEditingController _subCategory;
  late final TextEditingController _quantityPerUnit;
  late final TextEditingController _discountPct;
  late final TextEditingController _height;
  late final TextEditingController _width;
  late final TextEditingController _weight;
  late final TextEditingController _volumeMl;
  late final TextEditingController _minStock;
  late bool _isActive;
  
  // Image handling
  final List<_PickedImage?> _pickedImages = List<_PickedImage?>.filled(3, null);
  List<String> _existingImageUrls = [];
  final ImagePicker _picker = ImagePicker();
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _name = TextEditingController(text: p.name);
    _sellingPrice = TextEditingController(text: p.unitPrice.toString());
    _costPrice = TextEditingController(text: p.costPrice?.toString() ?? '');
    _taxPct = TextEditingController(text: p.taxPct?.toString() ?? '');
    _barcode = TextEditingController(text: p.barcode);
    _description = TextEditingController(text: p.description ?? '');
    _category = TextEditingController(text: p.category ?? '');
    _subCategory = TextEditingController(text: p.subCategory ?? '');
    _quantityPerUnit = TextEditingController(text: p.quantityPerUnit ?? '');
    _discountPct = TextEditingController(text: p.discountPct?.toString() ?? '');
    _height = TextEditingController(text: p.height?.toString() ?? '');
    _width = TextEditingController(text: p.width?.toString() ?? '');
    _weight = TextEditingController(text: p.weight?.toString() ?? '');
    _volumeMl = TextEditingController(text: p.volumeMl?.toString() ?? '');
    _minStock = TextEditingController(text: p.minStock?.toString() ?? '');
    _isActive = p.isActive;
    _existingImageUrls = List<String>.from(p.imageUrls);
  }

  @override
  void dispose() {
    _name.dispose();
    _sellingPrice.dispose();
    _costPrice.dispose();
    _taxPct.dispose();
    _barcode.dispose();
    _description.dispose();
    _category.dispose();
    _subCategory.dispose();
    _quantityPerUnit.dispose();
    _discountPct.dispose();
    _height.dispose();
    _width.dispose();
    _weight.dispose();
    _volumeMl.dispose();
    _minStock.dispose();
    super.dispose();
  }

  int _firstEmptySlot() {
    for (int i = 0; i < 3; i++) {
      if (_pickedImages[i] == null && i >= _existingImageUrls.length) return i;
    }
    return 0;
  }

  Future<void> _pickImage([int? slot]) async {
    final index = slot ?? _firstEmptySlot();
    final XFile? img = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (!mounted) return;
    if (img != null) {
      final bytes = await img.readAsBytes();
      setState(() {
        _pickedImages[index] = _PickedImage(name: img.name, bytes: bytes);
        // Remove from existing if replacing
        if (index < _existingImageUrls.length) {
          _existingImageUrls.removeAt(index);
        }
      });
    }
  }

  void _removeImage(int index) {
    setState(() {
      if (index < _existingImageUrls.length) {
        _existingImageUrls.removeAt(index);
      } else {
        final pickedIndex = index - _existingImageUrls.length;
        if (pickedIndex >= 0 && pickedIndex < _pickedImages.length) {
          _pickedImages[pickedIndex] = null;
        }
      }
    });
  }

  CollectionReference<Map<String, dynamic>> _catsCol(String storeId) =>
      FirebaseFirestore.instance.collection('stores').doc(storeId).collection('categories');

  Future<String?> _promptText(BuildContext context, String title, {String? initial}) async {
    final ctrl = TextEditingController(text: initial ?? '');
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Enter text'),
          onSubmitted: (v) => Navigator.of(dialogCtx).pop(v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogCtx).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(dialogCtx).pop(ctrl.text), child: const Text('Save')),
        ],
      ),
    );
  }

  Future<void> _quickAddCategory() async {
    final text = await _promptText(context, 'Add category', initial: _category.text.trim().isEmpty ? null : _category.text.trim());
    if (text == null || text.trim().isEmpty) return;
    final sid = ref.read(selectedStoreIdProvider);
    if (sid == null || sid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a store first')));
      return;
    }
    final name = text.trim();
    try {
      final existing = await _catsCol(sid).where('name', isEqualTo: name).limit(1).get();
      if (existing.docs.isEmpty) {
        await _catsCol(sid).add({'name': name, 'subcategories': <String>[]});
      }
      setState(() => _category.text = name);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to add category: $e')));
    }
  }

  Future<void> _quickAddSubCategory() async {
    if (_category.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter or add a Category first')));
      return;
    }
    final text = await _promptText(context, 'Add sub category', initial: _subCategory.text.trim().isEmpty ? null : _subCategory.text.trim());
    if (text == null || text.trim().isEmpty) return;
    final sid = ref.read(selectedStoreIdProvider);
    if (sid == null || sid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a store first')));
      return;
    }
    final name = text.trim();
    try {
      final q = await _catsCol(sid).where('name', isEqualTo: _category.text.trim()).limit(1).get();
      if (q.docs.isEmpty) {
        final doc = await _catsCol(sid).add({'name': _category.text.trim(), 'subcategories': <String>[]});
        await _catsCol(sid).doc(doc.id).update({'subcategories': FieldValue.arrayUnion([name])});
      } else {
        await _catsCol(sid).doc(q.docs.first.id).update({'subcategories': FieldValue.arrayUnion([name])});
      }
      setState(() => _subCategory.text = name);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to add subcategory: $e')));
    }
  }

  Future<void> _saveProduct() async {
    if (_uploading) return;
    setState(() => _uploading = true);

    try {
      final storeId = ref.read(selectedStoreIdProvider);
      if (storeId == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No store selected')));
        setState(() => _uploading = false);
        return;
      }

      // Upload new images
      List<String> newUrls = List<String>.from(_existingImageUrls);
      final imagesToUpload = _pickedImages.where((img) => img != null).map((img) => img!.bytes).toList();
      if (imagesToUpload.isNotEmpty) {
        final uploadedUrls = await uploadProductImages(
          storeId: storeId,
          sku: widget.product.sku,
          images: imagesToUpload,
        );
        newUrls.addAll(uploadedUrls);
      }

      final result = _EditProductResult(
        name: _name.text.trim().isEmpty ? null : _name.text.trim(),
        unitPrice: _sellingPrice.text.trim().isEmpty ? null : double.tryParse(_sellingPrice.text.trim()),
        costPrice: _costPrice.text.trim().isEmpty ? null : double.tryParse(_costPrice.text.trim()),
        taxPct: _taxPct.text.trim().isEmpty ? null : num.tryParse(_taxPct.text.trim()),
        barcode: _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
        description: _description.text.trim().isEmpty ? null : _description.text.trim(),
        category: _category.text.trim().isEmpty ? null : _category.text.trim(),
        subCategory: _subCategory.text.trim().isEmpty ? null : _subCategory.text.trim(),
        quantityPerUnit: _quantityPerUnit.text.trim().isEmpty ? null : _quantityPerUnit.text.trim(),
        discountPct: _discountPct.text.trim().isEmpty ? null : num.tryParse(_discountPct.text.trim()),
        height: _height.text.trim().isEmpty ? null : double.tryParse(_height.text.trim()),
        width: _width.text.trim().isEmpty ? null : double.tryParse(_width.text.trim()),
        weight: _weight.text.trim().isEmpty ? null : double.tryParse(_weight.text.trim()),
        volumeMl: _volumeMl.text.trim().isEmpty ? null : double.tryParse(_volumeMl.text.trim()),
        minStock: _minStock.text.trim().isEmpty ? null : int.tryParse(_minStock.text.trim()),
        isActive: _isActive,
        imageUrls: newUrls.isEmpty ? null : newUrls,
      );
      Navigator.pop(context, result);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sizes = context.sizes;
    final textStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurface);
    
    // Combine existing and picked images for display
    final allImages = <dynamic>[];
    for (final url in _existingImageUrls) {
      allImages.add(url);
    }
    for (final img in _pickedImages) {
      if (img != null) allImages.add(img);
    }

    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Edit ${widget.product.sku}', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w700)),
          TextButton(
            onPressed: _uploading ? null : () => _pickImage(),
            child: Text('Upload Image', style: TextStyle(color: scheme.primary)),
          ),
        ],
      ),
      content: DefaultTextStyle(
        style: textStyle ?? const TextStyle(),
        child: Form(
          key: _formKey,
          child: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Image thumbnails
                  if (allImages.isNotEmpty || _existingImageUrls.isEmpty)
                    SizedBox(
                      height: 80,
                      child: Row(
                        children: [
                          // Add button
                          InkWell(
                            onTap: _uploading ? null : () => _pickImage(),
                            child: Container(
                              width: 70,
                              height: 70,
                              margin: EdgeInsets.only(right: sizes.gapSm),
                              decoration: BoxDecoration(
                                borderRadius: context.radiusMd,
                                border: Border.all(color: scheme.outline),
                              ),
                              child: Icon(Icons.add_a_photo, color: scheme.outline),
                            ),
                          ),
                          // Existing & picked images
                          ...List.generate(allImages.length.clamp(0, 3), (i) {
                            final item = allImages[i];
                            return Stack(
                              children: [
                                Container(
                                  width: 70,
                                  height: 70,
                                  margin: EdgeInsets.only(right: sizes.gapSm),
                                  decoration: BoxDecoration(
                                    borderRadius: context.radiusMd,
                                    border: Border.all(color: scheme.primary),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: context.radiusSm,
                                    child: item is String
                                        ? Image.network(item, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(Icons.broken_image))
                                        : Image.memory((item as _PickedImage).bytes, fit: BoxFit.cover),
                                  ),
                                ),
                                Positioned(
                                  top: 0,
                                  right: sizes.gapSm,
                                  child: GestureDetector(
                                    onTap: () => _removeImage(i),
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: BoxDecoration(color: context.colors.error, shape: BoxShape.circle),
                                      child: Icon(Icons.close, size: 14, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }),
                        ],
                      ),
                    ),
                  context.gapVMd,
                  // Category dropdown with add button
                  Builder(builder: (ctx) {
                    final storeId = ref.watch(selectedStoreIdProvider);
                    if (storeId == null || storeId.isEmpty) {
                      return Row(children: [
                        Expanded(
                          child: TextFormField(
                            style: textStyle,
                            controller: _category,
                            decoration: InputDecoration(
                              labelText: 'Category',
                              suffixIcon: IconButton(
                                tooltip: 'Add Category',
                                icon: const Icon(Icons.add_circle_outline),
                                onPressed: _quickAddCategory,
                              ),
                            ),
                          ),
                        ),
                        context.gapHMd,
                        Expanded(
                          child: TextFormField(
                            style: textStyle,
                            controller: _subCategory,
                            decoration: InputDecoration(
                              labelText: 'Sub Category',
                              suffixIcon: IconButton(
                                tooltip: 'Add Sub Category',
                                icon: const Icon(Icons.add_circle_outline),
                                onPressed: _quickAddSubCategory,
                              ),
                            ),
                          ),
                        ),
                      ]);
                    }
                    final stream = FirebaseFirestore.instance
                        .collection('stores')
                        .doc(storeId)
                        .collection('categories')
                        .orderBy('name')
                        .snapshots();
                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: stream,
                      builder: (ctx, snap) {
                        final cats = <String>[];
                        final subsByCat = <String, List<String>>{};
                        if (snap.hasData) {
                          for (final d in snap.data!.docs) {
                            final data = d.data();
                            final name = (data['name'] ?? '') as String;
                            cats.add(name);
                            subsByCat[name] = List<String>.from((data['subcategories'] ?? const <dynamic>[]) as List<dynamic>);
                          }
                        }
                        final selCat = _category.text.trim().isEmpty ? null : _category.text.trim();
                        final subs = selCat == null ? const <String>[] : (subsByCat[selCat] ?? const <String>[]);
                        return Row(children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: 'Category',
                                suffixIcon: IconButton(
                                  tooltip: 'Add Category',
                                  icon: const Icon(Icons.add_circle_outline),
                                  onPressed: _quickAddCategory,
                                ),
                              ),
                              value: (selCat != null && cats.contains(selCat)) ? selCat : null,
                              items: cats.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                              onChanged: (v) => setState(() {
                                _category.text = v ?? '';
                                _subCategory.clear();
                              }),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: 'Sub Category',
                                suffixIcon: IconButton(
                                  tooltip: 'Add Sub Category',
                                  icon: const Icon(Icons.add_circle_outline),
                                  onPressed: _quickAddSubCategory,
                                ),
                              ),
                              value: (_subCategory.text.trim().isNotEmpty && subs.contains(_subCategory.text.trim())) ? _subCategory.text.trim() : null,
                              items: subs.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                              onChanged: subs.isEmpty ? null : (v) => setState(() => _subCategory.text = v ?? ''),
                            ),
                          ),
                        ]);
                      },
                    );
                  }),
                  context.gapVSm,
                  TextFormField(style: textStyle, controller: _name, decoration: const InputDecoration(labelText: 'Name')),
                  context.gapVSm,
                  TextFormField(style: textStyle, controller: _barcode, decoration: const InputDecoration(labelText: 'Barcode')),
                  context.gapVSm,
                  Row(children: [
                    Expanded(child: TextFormField(style: textStyle, controller: _costPrice, decoration: const InputDecoration(labelText: 'Buying Price'), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
                    context.gapHMd,
                    Expanded(child: TextFormField(style: textStyle, controller: _sellingPrice, decoration: const InputDecoration(labelText: 'Selling Price'), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
                  ]),
                  context.gapVSm,
                  Row(children: [
                    Expanded(child: TextFormField(style: textStyle, controller: _discountPct, decoration: const InputDecoration(labelText: 'Discount %'), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
                    context.gapHMd,
                    Expanded(child: TextFormField(style: textStyle, controller: _taxPct, decoration: const InputDecoration(labelText: 'GST %'), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
                  ]),
                  context.gapVSm,
                  Row(children: [
                    Expanded(child: TextFormField(style: textStyle, controller: _quantityPerUnit, decoration: const InputDecoration(labelText: 'Unit / Count'))),
                    context.gapHMd,
                    Expanded(child: TextFormField(style: textStyle, controller: _minStock, decoration: const InputDecoration(labelText: 'Min Stock'), keyboardType: TextInputType.number)),
                  ]),
                  context.gapVSm,
                  Row(children: [
                    Expanded(child: TextFormField(style: textStyle, controller: _height, decoration: const InputDecoration(labelText: 'Height (cm)'), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
                    context.gapHSm,
                    Expanded(child: TextFormField(style: textStyle, controller: _width, decoration: const InputDecoration(labelText: 'Width (cm)'), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
                    context.gapHSm,
                    Expanded(child: TextFormField(style: textStyle, controller: _weight, decoration: const InputDecoration(labelText: 'Weight (g)'), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
                    context.gapHSm,
                    Expanded(child: TextFormField(style: textStyle, controller: _volumeMl, decoration: const InputDecoration(labelText: 'Volume (ml)'), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
                  ]),
                  context.gapVSm,
                  TextFormField(style: textStyle, controller: _description, decoration: const InputDecoration(labelText: 'Description'), maxLines: 2),
                  context.gapVSm,
                  CheckboxListTile(
                    value: _isActive,
                    onChanged: (v) => setState(() => _isActive = v ?? true),
                    title: const Text('Active'),
                    controlAffinity: ListTileControlAffinity.trailing,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _uploading ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _uploading ? null : _saveProduct,
          child: _uploading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Save'),
        ),
      ],
    );
  }
}

enum _ActiveFilter { all, active, inactive }

// E-commerce style product detail dialog with image gallery
class _ProductDetailDialog extends StatefulWidget {
  final ProductDoc product;
  final bool isSignedIn;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ProductDetailDialog({
    required this.product,
    required this.isSignedIn,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_ProductDetailDialog> createState() => _ProductDetailDialogState();
}

class _ProductDetailDialogState extends State<_ProductDetailDialog> {
  int _selectedImageIndex = 0;

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final scheme = Theme.of(context).colorScheme;
    final sizes = context.sizes;
    final isWide = MediaQuery.of(context).size.width > 700;

    return Dialog(
      backgroundColor: scheme.surface,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isWide ? 80 : sizes.gapMd,
        vertical: sizes.gapLg,
      ),
      shape: RoundedRectangleBorder(borderRadius: context.radiusXl),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isWide ? 900 : 500,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with close button
            Container(
              padding: EdgeInsets.symmetric(horizontal: sizes.gapLg, vertical: sizes.gapMd),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.vertical(top: Radius.circular(sizes.radiusXl)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      p.name,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: isWide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left: Images
                          Expanded(flex: 1, child: _buildImageGallery(p, scheme)),
                          SizedBox(width: sizes.gapLg),
                          // Right: Details
                          Expanded(flex: 1, child: _buildProductDetails(p, scheme)),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildImageGallery(p, scheme),
                          SizedBox(height: sizes.gapLg),
                          _buildProductDetails(p, scheme),
                        ],
                      ),
              ),
            ),
            // Action buttons
            if (widget.isSignedIn)
              Container(
                padding: context.padMd,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(sizes.radiusXl)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: widget.onDelete,
                      icon: Icon(Icons.delete_outline, color: scheme.error),
                      label: Text('Delete', style: TextStyle(color: scheme.error)),
                    ),
                    SizedBox(width: sizes.gapMd),
                    FilledButton.icon(
                      onPressed: widget.onEdit,
                      icon: const Icon(Icons.edit),
                      label: const Text('Edit'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageGallery(ProductDoc p, ColorScheme scheme) {
    final sizes = context.sizes;
    if (p.imageUrls.isEmpty) {
      return Container(
        height: 300,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: context.radiusLg,
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.image_not_supported_outlined, size: sizes.iconXl, color: scheme.outline),
              SizedBox(height: sizes.gapMd),
              Text('No images', style: TextStyle(color: scheme.outline)),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // Main large image
        Container(
          height: 300,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: context.radiusLg,
            border: Border.all(color: scheme.outlineVariant.withOpacity(0.3)),
          ),
          child: ClipRRect(
            borderRadius: context.radiusLg,
            child: Image.network(
              p.imageUrls[_selectedImageIndex],
              fit: BoxFit.contain,
              width: double.infinity,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Center(
                  child: CircularProgressIndicator(
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                        : null,
                  ),
                );
              },
              errorBuilder: (_, __, ___) => Center(
                child: Icon(Icons.broken_image_outlined, size: 64, color: scheme.outline),
              ),
            ),
          ),
        ),
        // Thumbnail strip (if multiple images)
        if (p.imageUrls.length > 1) ...[
          SizedBox(height: sizes.gapMd),
          SizedBox(
            height: 70,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: p.imageUrls.length,
              itemBuilder: (context, index) {
                final isSelected = index == _selectedImageIndex;
                return GestureDetector(
                  onTap: () => setState(() => _selectedImageIndex = index),
                  child: Container(
                    width: 70,
                    height: 70,
                    margin: EdgeInsets.only(right: sizes.gapSm),
                    decoration: BoxDecoration(
                      borderRadius: context.radiusMd,
                      border: Border.all(
                        color: isSelected ? scheme.primary : scheme.outlineVariant.withOpacity(0.3),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: context.radiusSm,
                      child: Image.network(
                        p.imageUrls[index],
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Center(
                            child: SizedBox(
                              width: sizes.iconSm,
                              height: sizes.iconSm,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        },
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.broken_image_outlined,
                          size: sizes.iconSm,
                          color: scheme.outline,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildProductDetails(ProductDoc p, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Price section
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '₹${p.unitPrice.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: context.sizes.fontXxl + 4,
                fontWeight: FontWeight.w700,
                color: scheme.primary,
              ),
            ),
            if ((p.taxPct ?? 0) > 0) ...[
              const SizedBox(width: 8),
              Text(
                '+${p.taxPct}% GST',
                style: TextStyle(fontSize: context.sizes.fontMd, color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
        if (p.mrpPrice != null && p.mrpPrice! > p.unitPrice) ...[
          context.gapVXs,
          Row(
            children: [
              Text(
                'MRP: ₹${p.mrpPrice!.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: context.sizes.fontMd,
                  color: scheme.onSurfaceVariant,
                  decoration: TextDecoration.lineThrough,
                ),
              ),
              context.gapHSm,
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: context.appColors.success,
                  borderRadius: context.radiusXs,
                ),
                child: Text(
                  '${((1 - p.unitPrice / p.mrpPrice!) * 100).toStringAsFixed(0)}% OFF',
                  style: TextStyle(color: Colors.white, fontSize: context.sizes.fontSm, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
        context.gapVLg,
        // Status badge
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: p.isActive ? context.appColors.success.withOpacity(0.1) : scheme.error.withOpacity(0.1),
                borderRadius: context.radiusLg,
                border: Border.all(color: p.isActive ? context.appColors.success : scheme.error),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    p.isActive ? Icons.check_circle : Icons.cancel,
                    size: 16,
                    color: p.isActive ? context.appColors.success : scheme.error,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    p.isActive ? 'Active' : 'Inactive',
                    style: TextStyle(
                      color: p.isActive ? context.appColors.success : scheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        // Info cards
        _buildInfoRow('SKU', p.sku, scheme),
        if (p.barcode.isNotEmpty) _buildInfoRow('Barcode', p.barcode, scheme),
        if (p.category != null && p.category!.isNotEmpty) _buildInfoRow('Category', p.category!, scheme),
        if (p.subCategory != null && p.subCategory!.isNotEmpty) _buildInfoRow('Sub-category', p.subCategory!, scheme),
        context.gapVLg,
        // Stock info
        Container(
          padding: context.padLg,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: context.radiusMd,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Stock', style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurface)),
              context.gapVMd,
              Row(
                children: [
                  _buildStockChip('Total', p.totalStock, scheme),
                  context.gapHMd,
                  _buildStockChip('Store', p.stockAt('Store'), scheme),
                  context.gapHMd,
                  _buildStockChip('Warehouse', p.stockAt('Warehouse'), scheme),
                ],
              ),
              if (p.minStock != null) ...[
                context.gapVSm,
                Text(
                  'Min stock alert: ${p.minStock}',
                  style: TextStyle(fontSize: context.sizes.fontSm, color: scheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
        // Description
        if (p.description != null && p.description!.isNotEmpty) ...[
          context.gapVLg,
          Text('Description', style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurface)),
          context.gapVSm,
          Text(p.description!, style: TextStyle(color: scheme.onSurfaceVariant)),
        ],
        // Variants
        if (p.variants.isNotEmpty) ...[
          context.gapVLg,
          Text('Variants', style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurface)),
          context.gapVSm,
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: p.variants
                .map((v) => Chip(
                      label: Text(v, style: TextStyle(fontSize: context.sizes.fontSm)),
                      backgroundColor: scheme.primaryContainer.withOpacity(0.5),
                    ))
                .toList(),
          ),
        ],
        // Dimensions
        if (p.height != null || p.width != null || p.weight != null || p.volumeMl != null) ...[
          context.gapVLg,
          Text('Dimensions', style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurface)),
          context.gapVSm,
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              if (p.height != null) Text('H: ${p.height}cm', style: TextStyle(color: scheme.onSurfaceVariant)),
              if (p.width != null) Text('W: ${p.width}cm', style: TextStyle(color: scheme.onSurfaceVariant)),
              if (p.weight != null) Text('Weight: ${p.weight}g', style: TextStyle(color: scheme.onSurfaceVariant)),
              if (p.volumeMl != null) Text('Volume: ${p.volumeMl}ml', style: TextStyle(color: scheme.onSurfaceVariant)),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: context.sizes.fontMd)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontWeight: FontWeight.w500, color: scheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStockChip(String label, int qty, ColorScheme scheme) {
    final isLow = qty <= 10;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isLow ? context.appColors.warning.withOpacity(0.1) : context.appColors.success.withOpacity(0.1),
        borderRadius: context.radiusSm,
      ),
      child: Column(
        children: [
          Text(
            qty.toString(),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: context.sizes.fontXl,
              color: isLow ? context.appColors.warning : context.appColors.success,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: context.sizes.fontXs, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// -------------------- Barcode Scanner Screen --------------------
class _BarcodeScannerScreen extends StatefulWidget {
  const _BarcodeScannerScreen();

  @override
  State<_BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<_BarcodeScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );
  bool _hasScanned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;
    
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
      _hasScanned = true;
      final code = barcodes.first.rawValue!;
      Navigator.pop(context, code);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Barcode'),
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        actions: [
          IconButton(
            icon: ValueListenableBuilder(
              valueListenable: _controller,
              builder: (context, state, child) {
                return Icon(
                  state.torchState == TorchState.on 
                      ? Icons.flash_on 
                      : Icons.flash_off,
                );
              },
            ),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_ios),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          // Scan overlay
          Center(
            child: Container(
              width: 280,
              height: 150,
              decoration: BoxDecoration(
                border: Border.all(color: cs.primary, width: 3),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          // Instructions
          Positioned(
            bottom: 80,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Point camera at barcode',
                  style: TextStyle(color: Colors.white, fontSize: context.sizes.fontLg),
                ),
              ),
            ),
          ),
          // Manual entry button
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Center(
              child: TextButton.icon(
                onPressed: () async {
                  final result = await showDialog<String>(
                    context: context,
                    builder: (ctx) {
                      final controller = TextEditingController();
                      return AlertDialog(
                        title: const Text('Enter Barcode Manually'),
                        content: TextField(
                          controller: controller,
                          decoration: const InputDecoration(
                            labelText: 'Barcode',
                            hintText: 'Enter barcode number',
                          ),
                          keyboardType: TextInputType.number,
                          autofocus: true,
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                            child: const Text('OK'),
                          ),
                        ],
                      );
                    },
                  );
                  if (result != null && result.isNotEmpty && mounted) {
                    Navigator.pop(context, result);
                  }
                },
                icon: const Icon(Icons.keyboard, color: Colors.white),
                label: const Text('Enter Manually', style: TextStyle(color: Colors.white)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}