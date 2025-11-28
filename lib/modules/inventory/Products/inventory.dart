// ignore_for_file: use_build_context_synchronously
// Rebuilt Inventory module root screen (clean version)
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import '../web_image_picker_stub.dart' if (dart.library.html) '../web_image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/store_scoped_refs.dart';
import '../../stores/providers.dart';

import '../../../core/paging/paged_list_controller.dart';
import '../../../core/firebase/firestore_paging.dart';
import '../../../core/loading/page_loader_overlay.dart';

import '../../../core/auth/auth.dart';
import '../../../core/permissions.dart';
import 'inventory_repository.dart';
import 'csv_utils.dart';
import '../download_helper_stub.dart' if (dart.library.html) '../download_helper_web.dart';
import 'barcodes_pdf.dart';
import '../import_products_screen.dart' show ImportProductsScreen;
import 'inventory_sheet_page.dart';
import 'invoice_analysis_page.dart';
import '../category_screen.dart';
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
      padding: const EdgeInsets.all(12.0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LayoutBuilder(builder: (context, constraints) {
          final narrow = constraints.maxWidth < 560;
          final searchWidth = narrow ? 220.0 : 280.0;
          final btnMinH = 36.0;
          final btnPad = const EdgeInsets.symmetric(horizontal: 12, vertical: 8);
          final compactFilled = FilledButton.styleFrom(
            minimumSize: Size(0, btnMinH),
            padding: btnPad,
            visualDensity: VisualDensity.compact,
          );
          final compactOutlined = OutlinedButton.styleFrom(
            minimumSize: Size(0, btnMinH),
            padding: btnPad,
            visualDensity: VisualDensity.compact,
          );
          final searchBox = SizedBox(
            width: searchWidth,
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search SKU/Name/Barcode',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                floatingLabelBehavior: FloatingLabelBehavior.never,
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          );
          final activeDrop = DropdownButton<_ActiveFilter>(
            value: _activeFilter,
            onChanged: (v) => setState(() => _activeFilter = v ?? _ActiveFilter.all),
            items: const [
              DropdownMenuItem(value: _ActiveFilter.all, child: Text('All')),
              DropdownMenuItem(value: _ActiveFilter.active, child: Text('Active')),
              DropdownMenuItem(value: _ActiveFilter.inactive, child: Text('Inactive')),
            ],
          );
          final gstDrop = DropdownButton<int>(
            value: _gstFilter,
            onChanged: (v) => setState(() => _gstFilter = v ?? -1),
            items: const [
              DropdownMenuItem(value: -1, child: Text('GST: All')),
              DropdownMenuItem(value: 0, child: Text('GST 0%')),
              DropdownMenuItem(value: 5, child: Text('GST 5%')),
              DropdownMenuItem(value: 12, child: Text('GST 12%')),
              DropdownMenuItem(value: 18, child: Text('GST 18%')),
            ],
          );
          return Wrap(
            spacing: narrow ? 6 : 8,
            runSpacing: narrow ? 6 : 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              searchBox,
              activeDrop,
              gstDrop,
              FilledButton.icon(
                style: compactFilled,
                onPressed: isSignedIn && selStore != null ? () => _openAddDialog(context) : _requireSignInNotice,
                icon: const Icon(Icons.add),
                label: const Text('Add Product'),
              ),
              OutlinedButton.icon(
                style: compactOutlined,
                onPressed: () => _exportCsv(),
                icon: const Icon(Icons.file_download_outlined),
                label: const Text('Export CSV'),
              ),
              OutlinedButton.icon(
                style: compactOutlined,
                onPressed: isSignedIn && selStore != null
                    ? () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const ImportProductsScreen()),
                        )
                    : _requireSignInNotice,
                icon: const Icon(Icons.file_upload_outlined),
                label: const Text('Import CSV'),
              ),
              Builder(builder: (_) {
                final hasData = state.items.isNotEmpty;
                return OutlinedButton.icon(
                  style: compactOutlined,
                  onPressed: hasData ? () => _exportBarcodesPdf(context) : null,
                  icon: const Icon(Icons.qr_code_2),
                  label: const Text('Barcodes PDF'),
                );
              }),
              OutlinedButton.icon(
                style: compactOutlined,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const InventorySheetPage()),
                ),
                icon: const Icon(Icons.grid_on_outlined),
                label: const Text('Update Sheet'),
              ),
              OutlinedButton.icon(
                style: compactOutlined,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CategoryScreen()),
                ),
                icon: const Icon(Icons.category_outlined),
                label: const Text('Categories'),
              ),
              OutlinedButton.icon(
                style: compactOutlined,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const InvoiceAnalysisPage()),
                ),
                icon: const Icon(Icons.analytics_outlined),
                label: const Text('Invoice Analysis'),
              ),
            ],
          );
        }),
        const SizedBox(height: 12),
        Expanded(
          child: PageLoaderOverlay(
            loading: state.loading && state.items.isEmpty,
            error: state.error,
            onRetry: () => ref.read(productsPagedControllerProvider).resetAndLoad(),
            child: Card(
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
                return Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final table = DataTable(
                        columnSpacing: 28,
                        horizontalMargin: 12,
                        columns: const [
                          DataColumn(label: Text('SKU')),
                          DataColumn(label: Text('Name')),
                          DataColumn(label: Text('Barcode')),
                          DataColumn(label: Text('Unit Price')),
                          DataColumn(label: Text('GST %')),
                          DataColumn(label: Text('Store')),
                          DataColumn(label: Text('Warehouse')),
                          DataColumn(label: Text('Total')),
                          DataColumn(label: Text('Active')),
                        ],
                        rows: [
                          for (final p in filtered)
                            DataRow(
                              onSelectChanged: (selected) {
                                if (selected == true && isSignedIn) {
                                  _openEditDialog(context, p);
                                }
                              },
                              onLongPress: isSignedIn ? () => _confirmDelete(context, p) : null,
                              cells: [
                                DataCell(Text(p.sku)),
                                DataCell(Text(p.name)),
                                DataCell(Text(p.barcode)),
                                DataCell(Text('₹${p.unitPrice.toStringAsFixed(2)}')),
                                DataCell(Text((p.taxPct ?? 0).toString())),
                                DataCell(Text(p.stockAt('Store').toString())),
                                DataCell(Text(p.stockAt('Warehouse').toString())),
                                DataCell(Text(p.totalStock.toString())),
                                DataCell(
                                  Builder(
                                    builder: (context) {
                                      final scheme = Theme.of(context).colorScheme;
                                      final color = p.isActive ? scheme.primary : scheme.error;
                                      return Icon(p.isActive ? Icons.check_circle : Icons.cancel, color: color);
                                    },
                                  ),
                                ),
                              ],
                            ),
                        ],
                      );
                      return Column(
                        children: [
                          Expanded(
                            child: Scrollbar(
                              thumbVisibility: true,
                              notificationPredicate: (notif) => notif.metrics.axis == Axis.horizontal,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onHorizontalDragUpdate: (details) {
                                  if (!_hScrollCtrl.hasClients) return;
                                  final maxExtent = _hScrollCtrl.position.maxScrollExtent;
                                  double next = _hScrollCtrl.offset - details.delta.dx;
                                  if (next < 0) next = 0;
                                  if (next > maxExtent) next = maxExtent;
                                  _hScrollCtrl.jumpTo(next);
                                },
                                child: SingleChildScrollView(
                                  controller: _hScrollCtrl,
                                  physics: const ClampingScrollPhysics(),
                                  scrollDirection: Axis.horizontal,
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                                    child: SingleChildScrollView(
                                      controller: _vScrollCtrl,
                                      child: DataTableTheme(
                                        data: DataTableThemeData(
                                          dataTextStyle: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                                          headingTextStyle: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w700),
                                        ),
                                        child: table,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
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
                    },
                  ),
                );
              }),
            ),
          ),
        ),
      ]),
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
      variants: result.variants,
      mrpPrice: result.mrpPrice,
      costPrice: result.costPrice,
      height: result.height,
      width: result.width,
      weight: result.weight,
      volumeMl: result.volumeMl,
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

  Future<void> _exportBarcodesPdf(BuildContext context) async {
    if (_currentProducts.isEmpty) return;
    final products = _currentProducts
        .map((p) => BarcodeProduct(sku: p.sku, realBarcode: p.barcode))
        .toList();
    late final Uint8List bytes;
    try {
      bytes = await buildBarcodesPdf(products);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to build PDF: $e')));
      return;
    }
    final ok = await downloadBytes(bytes, 'product_barcodes.pdf', 'application/pdf');
    if (!mounted) return;
    if (!ok) {
      // Fallback: show simple dialog with note
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(
            'Barcodes PDF generated',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
          ),
          content: DefaultTextStyle(
            style: (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
                .copyWith(color: Theme.of(context).colorScheme.onSurface),
            child: const Text('Automatic download failed. Try again or check browser settings.'),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Barcodes PDF downloaded')));
    }
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
    // Placeholder for future barcode scanning implementation
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Scan Barcode: coming soon')),
    );
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
    if (!kIsWeb) {
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Camera'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.folder_open),
                title: const Text('Browse Files'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );
      if (source == null) return;
      final XFile? img = await _picker.pickImage(source: source);
      if (!mounted) return;
      if (img != null) {
        final bytes = await img.readAsBytes();
        setState(() => _pickedImages[index] = _PickedImage(name: img.name, bytes: bytes));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Image selected: ${img.name}')),
        );
      }
    } else {
      final choice = await showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Camera'),
                onTap: () => Navigator.pop(ctx, 'camera'),
              ),
              ListTile(
                leading: const Icon(Icons.folder_open),
                title: const Text('Browse Files'),
                onTap: () => Navigator.pop(ctx, 'files'),
              ),
            ],
          ),
        ),
      );
      if (choice == null) return;
      WebPickedImage? webImg = choice == 'camera' ? await pickImageFromCameraWeb() : await pickImageFromFilesWeb();
      if (!mounted) return;
      if (webImg != null) {
        setState(() => _pickedImages[index] = _PickedImage(name: webImg.name, bytes: webImg.bytes));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Image selected: ${webImg.name}')),
        );
      }
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
          const SizedBox(height: 8),
          // Preview strip directly below title
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(3, (i) {
                final data = _pickedImages[i];
                final uploadingThis = _uploading && data != null && _progress[i] < 1.0;
                final failed = _uploadError != null;
                return Padding(
                  padding: EdgeInsets.only(right: i < 2 ? 8.0 : 0.0),
                  child: InkWell(
                    onTap: () => (_uploading) ? null : (data == null ? _pickImageShowOptions(i) : _showImagePreview(i)),
                    child: Stack(
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                            borderRadius: BorderRadius.circular(8),
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          ),
                          child: data == null
                              ? Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(Icons.add_a_photo, size: 20),
                                    SizedBox(height: 4),
                                    Text('Image', style: TextStyle(fontSize: 11)),
                                  ],
                                )
                              : ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.memory(data.bytes, fit: BoxFit.cover, width: 80, height: 80),
                                ),
                        ),
                        if (data != null && !_uploading)
                          Positioned(
                            top: 0,
                            right: 0,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black45,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minHeight: 24, minWidth: 24),
                                icon: const Icon(Icons.close, size: 16, color: Colors.white),
                                onPressed: () => _removeImage(i),
                                tooltip: 'Remove',
                              ),
                            ),
                          ),
                        if (uploadingThis)
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black38,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: SizedBox(
                                  width: 42,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const CircularProgressIndicator(strokeWidth: 3),
                                      const SizedBox(height: 6),
                                      Text('${(_progress[i]*100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 11, color: Colors.white)),
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
                            child: Icon(Icons.check_circle, color: Colors.green.shade400, size: 20),
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
              child: Text('Upload failed: $_uploadError', style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
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
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                      controller: _sku,
                      decoration: InputDecoration(
                        labelText: 'SKU',
                        suffixIcon: IconButton(
                          tooltip: 'Generate SKU',
                          icon: const Icon(Icons.auto_awesome),
                          onPressed: _generateSku,
                        ),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                      controller: _barcode,
                      decoration: InputDecoration(
                        labelText: 'Barcode',
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
                    ),
                  ),
                ]),
                TextFormField(style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface), controller: _name, decoration: const InputDecoration(labelText: 'Name'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
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
                            labelText: 'Category',
                            suffixIcon: IconButton(
                              tooltip: 'Add Category',
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: _quickAddCategory,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
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
                Row(children: [
                  Expanded(child: TextFormField(style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface), controller: _buyingPrice, decoration: const InputDecoration(labelText: 'Buying Price'), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
                  const SizedBox(width: 12),
                  Expanded(child: TextFormField(style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface), controller: _sellingPrice, decoration: const InputDecoration(labelText: 'Selling Price'), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
                ]),
                Row(children: [
                  Expanded(child: TextFormField(style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface), controller: _discountPct, decoration: const InputDecoration(labelText: 'Discount %'), keyboardType: const TextInputType.numberWithOptions(decimal: true)) ),
                  const SizedBox(width: 12),
                  Expanded(child: TextFormField(style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface), controller: _quantityPerUnit, decoration: const InputDecoration(labelText: 'Unit / Count'))),
                ]),
                Row(children: [
                  Expanded(child: TextFormField(style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface), controller: _height, decoration: const InputDecoration(labelText: 'Height (cm)'), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
                  const SizedBox(width: 12),
                  Expanded(child: TextFormField(style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface), controller: _width, decoration: const InputDecoration(labelText: 'Width (cm)'), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
                  const SizedBox(width: 12),
                  Expanded(child: TextFormField(style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface), controller: _weight, decoration: const InputDecoration(labelText: 'Weight (g)'), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
                  const SizedBox(width: 12),
                  Expanded(child: TextFormField(style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface), controller: _volumeMl, decoration: const InputDecoration(labelText: 'Volume (ml)'), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
                ]),
                TextFormField(style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface), controller: _minStock, decoration: const InputDecoration(labelText: 'Min Stock'), keyboardType: TextInputType.number),
                TextFormField(style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface), controller: _description, decoration: const InputDecoration(labelText: 'Description')),
                // Removed single-file indicator; use image boxes above
                const SizedBox(height: 8),
                CheckboxListTile(value: _isActive, onChanged: (v) => setState(() => _isActive = v ?? true), title: const Text('Active')),
                Row(children: [
                  Expanded(child: TextFormField(style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface), controller: _storeQty, decoration: const InputDecoration(labelText: 'Initial Store Qty'), keyboardType: TextInputType.number)),
                  const SizedBox(width: 12),
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
            if (_sku.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('SKU required before saving')));
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
  final List<String>? variants;
  final double? mrpPrice;
  final double? costPrice;
  final double? height;
  final double? width;
  final double? weight;
  final double? volumeMl;
  final bool? isActive;
  _EditProductResult({
    this.name,
    this.unitPrice,
    this.taxPct,
    this.barcode,
    this.description,
    this.variants,
    this.mrpPrice,
    this.costPrice,
    this.height,
    this.width,
    this.weight,
    this.volumeMl,
    this.isActive,
  });
}

class _EditProductDialog extends StatefulWidget {
  final ProductDoc product;
  const _EditProductDialog({required this.product});
  @override
  State<_EditProductDialog> createState() => _EditProductDialogState();
}

class _EditProductDialogState extends State<_EditProductDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _unitPrice;
  late final TextEditingController _taxPct;
  late final TextEditingController _barcode;
  late final TextEditingController _description;
  late final TextEditingController _variants;
  late final TextEditingController _mrpPrice;
  late final TextEditingController _costPrice;
  late final TextEditingController _height;
  late final TextEditingController _width;
  late final TextEditingController _weight;
  late final TextEditingController _volumeMl;
  late bool _isActive;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _name = TextEditingController(text: p.name);
    _unitPrice = TextEditingController(text: p.unitPrice.toString());
    _taxPct = TextEditingController(text: p.taxPct?.toString() ?? '');
    _barcode = TextEditingController(text: p.barcode);
    _description = TextEditingController(text: p.description ?? '');
    _variants = TextEditingController(text: p.variants.join(';'));
    _mrpPrice = TextEditingController(text: p.mrpPrice?.toString() ?? '');
    _costPrice = TextEditingController(text: p.costPrice?.toString() ?? '');
    _height = TextEditingController(text: p.height?.toString() ?? '');
    _width = TextEditingController(text: p.width?.toString() ?? '');
    _weight = TextEditingController(text: p.weight?.toString() ?? '');
    _volumeMl = TextEditingController(text: p.volumeMl?.toString() ?? '');
    _isActive = p.isActive;
  }

  @override
  void dispose() {
    _name.dispose();
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Edit ${widget.product.sku}',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
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
                TextFormField(style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface), controller: _name, decoration: const InputDecoration(labelText: 'Name')),
                TextFormField(style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface), controller: _barcode, decoration: const InputDecoration(labelText: 'Barcode')),
                Row(children: [
                  Expanded(child: TextFormField(style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface), controller: _unitPrice, decoration: const InputDecoration(labelText: 'Unit Price'), keyboardType: TextInputType.numberWithOptions(decimal: true))),
                  const SizedBox(width: 12),
                  Expanded(child: TextFormField(style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface), controller: _taxPct, decoration: const InputDecoration(labelText: 'GST %'), keyboardType: TextInputType.numberWithOptions(decimal: true))),
                ]),
                Row(children: [
                  Expanded(child: TextFormField(style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface), controller: _mrpPrice, decoration: const InputDecoration(labelText: 'MRP'), keyboardType: TextInputType.numberWithOptions(decimal: true))),
                  const SizedBox(width: 12),
                  Expanded(child: TextFormField(style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface), controller: _costPrice, decoration: const InputDecoration(labelText: 'Cost Price'), keyboardType: TextInputType.numberWithOptions(decimal: true))),
                ]),
                Row(children: [
                  Expanded(child: TextFormField(style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface), controller: _height, decoration: const InputDecoration(labelText: 'Height (cm)'), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
                  const SizedBox(width: 12),
                  Expanded(child: TextFormField(style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface), controller: _width, decoration: const InputDecoration(labelText: 'Width (cm)'), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
                  const SizedBox(width: 12),
                  Expanded(child: TextFormField(style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface), controller: _weight, decoration: const InputDecoration(labelText: 'Weight (g)'), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
                  const SizedBox(width: 12),
                  Expanded(child: TextFormField(style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface), controller: _volumeMl, decoration: const InputDecoration(labelText: 'Volume (ml)'), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
                ]),
                TextFormField(style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface), controller: _variants, decoration: const InputDecoration(labelText: 'Variants (separate with ;)')),
                TextFormField(style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface), controller: _description, decoration: const InputDecoration(labelText: 'Description')),
                const SizedBox(height: 8),
                CheckboxListTile(value: _isActive, onChanged: (v) => setState(() => _isActive = v ?? true), title: const Text('Active')),
              ],
            ),
          ),
        ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final result = _EditProductResult(
              name: _name.text.trim().isEmpty ? null : _name.text.trim(),
              unitPrice: _unitPrice.text.trim().isEmpty ? null : double.tryParse(_unitPrice.text.trim()),
              taxPct: _taxPct.text.trim().isEmpty ? null : num.tryParse(_taxPct.text.trim()),
              barcode: _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
              description: _description.text.trim().isEmpty ? null : _description.text.trim(),
              variants: _variants.text.trim().isEmpty ? null : _variants.text.split(';').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
              mrpPrice: _mrpPrice.text.trim().isEmpty ? null : double.tryParse(_mrpPrice.text.trim()),
              costPrice: _costPrice.text.trim().isEmpty ? null : double.tryParse(_costPrice.text.trim()),
              height: _height.text.trim().isEmpty ? null : double.tryParse(_height.text.trim()),
              width: _width.text.trim().isEmpty ? null : double.tryParse(_width.text.trim()),
              weight: _weight.text.trim().isEmpty ? null : double.tryParse(_weight.text.trim()),
              volumeMl: _volumeMl.text.trim().isEmpty ? null : double.tryParse(_volumeMl.text.trim()),
              isActive: _isActive,
            );
            Navigator.pop(context, result);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

enum _ActiveFilter { all, active, inactive }