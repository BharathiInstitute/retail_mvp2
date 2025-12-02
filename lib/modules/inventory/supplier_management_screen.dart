import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'Products/inventory.dart' show selectedStoreProvider; // current store id
import 'package:retail_mvp2/core/firestore_store_collections.dart';
import '../../core/theme/theme_extension_helpers.dart';
import '../../core/paging/infinite_scroll_controller.dart';
import '../../core/firebase/firestore_pagination_helper.dart';
import '../../core/loading/page_loading_state_widget.dart';

// --- Inlined Supplier model & repository (moved from supplier_repository.dart) ---
class SupplierDoc {
  final String id; final String name; final String address; final String phone; final String email;
  SupplierDoc({required this.id,required this.name,required this.address,required this.phone,required this.email});
  factory SupplierDoc.fromSnap(DocumentSnapshot<Map<String,dynamic>> d){
    final m=d.data()??const{}; return SupplierDoc(
      id:d.id,
      name:(m['name']??'') as String,
      address:(m['address']??'') as String,
      phone:(m['phone']??'') as String,
      email:(m['email']??'') as String,
    );
  }
  Map<String,dynamic> toMap()=>{'name':name,'address':address,'phone':phone,'email':email};
}

class SupplierRepository {
  SupplierRepository({FirebaseFirestore? firestore, required String? storeId})
      : _db = firestore ?? FirebaseFirestore.instance,
        _storeId = storeId;
  final FirebaseFirestore _db;
  final String? _storeId;
  CollectionReference<Map<String, dynamic>> get _col {
    final sid = _storeId;
    if (sid == null) {
      throw StateError('No store selected');
    }
    return StoreRefs.of(sid, fs: _db).suppliers();
  }
  Stream<List<SupplierDoc>> streamSuppliers() => _col.orderBy('name').snapshots().map((snap) => snap.docs.map((d) => SupplierDoc.fromSnap(d)).toList());
  Future<void> addSupplier({required String name, required String address, required String phone, required String email}) async {
    await _col.add({'name': name, 'address': address, 'phone': phone, 'email': email, 'createdAt': FieldValue.serverTimestamp()});
  }
  Future<void> updateSupplier({required String id, required String name, required String address, required String phone, required String email}) async {
    await _col.doc(id).update({'name': name, 'address': address, 'phone': phone, 'email': email, 'updatedAt': FieldValue.serverTimestamp()});
  }
  Future<void> deleteSupplier({required String id}) async {
    await _col.doc(id).delete();
  }
}

/// Repository provider for suppliers (scoped for reuse if needed elsewhere)
final supplierRepoProvider = Provider<SupplierRepository>((ref) {
  final storeId = ref.watch(selectedStoreProvider);
  return SupplierRepository(storeId: storeId);
});

/// Stream provider kept for any legacy/aux consumers (not used by screen now)
final supplierStreamProvider = StreamProvider.autoDispose<List<SupplierDoc>>((ref) {
  final repo = ref.watch(supplierRepoProvider);
  return repo.streamSuppliers();
});

/// Paged controller for suppliers used by the screen
final suppliersPagedControllerProvider = ChangeNotifierProvider.autoDispose<PagedListController<SupplierDoc>>((ref) {
  final storeId = ref.watch(selectedStoreProvider);

  final controller = PagedListController<SupplierDoc>(
    pageSize: 50,
    loadPage: (cursor) async {
      final after = cursor as DocumentSnapshot<Map<String, dynamic>>?;
      if (storeId == null) {
        return (<SupplierDoc>[], null);
      }
      final query = StoreRefs.of(storeId).suppliers().orderBy('name');
      final (items, next) = await fetchFirestorePage<SupplierDoc>(
        base: query,
        after: after,
        pageSize: 50,
        map: (d) => SupplierDoc.fromSnap(d),
      );
      return (items, next);
    },
  );

  Future.microtask(controller.resetAndLoad);
  ref.onDispose(controller.dispose);
  return controller;
});

/// Public Suppliers screen widget (moved out of inventory.dart)
class SuppliersScreen extends ConsumerStatefulWidget {
  const SuppliersScreen({super.key});
  @override
  ConsumerState<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends ConsumerState<SuppliersScreen> {
  String _search = '';
  // Horizontal scroll controller to enable drag-to-pan on desktop/tablet/mobile
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
    final after = _vScrollCtrl.position.extentAfter;
    if (after < 600) {
      final c = ref.read(suppliersPagedControllerProvider);
      final s = c.state;
      if (!s.loading && !s.endReached) c.loadMore();
    }
  }

  List<SupplierDoc> _filter(List<SupplierDoc> list) {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return list;
    return list.where((s) =>
      s.name.toLowerCase().contains(q) ||
      s.phone.toLowerCase().contains(q) ||
      s.email.toLowerCase().contains(q)
    ).toList();
  }

  @override
  Widget build(BuildContext context) {
    final paged = ref.watch(suppliersPagedControllerProvider);
    final state = paged.state;
    final cs = Theme.of(context).colorScheme;
    final sizes = context.sizes;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cs.surface, cs.primaryContainer.withOpacity(0.05)],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 10 : 14),
        child: Column(
          children: [
            // Modern Header
            Container(
              padding: EdgeInsets.symmetric(horizontal: isMobile ? sizes.gapMd : sizes.gapMd, vertical: sizes.gapMd),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: context.radiusMd,
                border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
                boxShadow: [BoxShadow(color: cs.shadow.withOpacity(0.05), blurRadius: 10)],
              ),
              child: Row(
                children: [
                  // Search Field
                  Expanded(
                    child: Container(
                      height: sizes.inputHeightSm,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withOpacity(0.5),
                        borderRadius: context.radiusMd,
                        border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
                      ),
                      child: TextField(
                        style: TextStyle(fontSize: sizes.fontSm, color: cs.onSurface),
                        decoration: InputDecoration(
                          prefixIcon: Icon(Icons.search_rounded, size: sizes.iconSm, color: cs.onSurfaceVariant),
                          hintText: 'Search name / phone / email',
                          hintStyle: TextStyle(fontSize: sizes.fontSm, color: cs.onSurfaceVariant.withOpacity(0.7)),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: sizes.gapSm, vertical: sizes.gapSm),
                        ),
                        onChanged: (v) => setState(() => _search = v),
                      ),
                    ),
                  ),
                  SizedBox(width: sizes.gapMd),
                  // Add Button
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [cs.primary, cs.primary.withOpacity(0.85)]),
                      borderRadius: context.radiusMd,
                      boxShadow: [BoxShadow(color: cs.primary.withOpacity(0.25), blurRadius: 6, offset: const Offset(0, 2))],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _openAddDialog,
                        borderRadius: context.radiusMd,
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: isMobile ? sizes.gapMd : sizes.gapMd, vertical: sizes.gapSm),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_rounded, size: sizes.iconSm, color: cs.onPrimary),
                              if (!isMobile) ...[
                                SizedBox(width: sizes.gapSm),
                                Text('Add Supplier', style: TextStyle(fontSize: sizes.fontSm, fontWeight: FontWeight.w600, color: cs.onPrimary)),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: sizes.gapMd),
            // Content
            Expanded(
              child: PageLoaderOverlay(
                loading: state.loading && state.items.isEmpty,
                error: state.error,
                onRetry: () => ref.read(suppliersPagedControllerProvider).resetAndLoad(),
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: context.radiusMd,
                    border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
                    boxShadow: [BoxShadow(color: cs.shadow.withOpacity(0.05), blurRadius: 10)],
                  ),
                  child: ClipRRect(
                    borderRadius: context.radiusMd,
                    child: _buildContent(context, state, cs, isMobile),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, PageState<SupplierDoc> state, ColorScheme cs, bool isMobile) {
    final list = state.items;
    if (list.isEmpty && !state.loading) {
      return _buildEmptyState(cs);
    }
    final filtered = _filter(list);
    if (filtered.isEmpty && !state.loading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded, size: 40, color: cs.onSurfaceVariant.withOpacity(0.4)),
            const SizedBox(height: 10),
            Text('No suppliers match search', style: TextStyle(fontSize: context.sizes.fontMd, color: cs.onSurfaceVariant)),
          ],
        ),
      );
    }

    if (isMobile) {
      return _buildMobileList(filtered, cs, state);
    }
    return _buildDesktopTable(filtered, cs, state);
  }

  Widget _buildEmptyState(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withOpacity(0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.people_outline_rounded, size: 40, color: cs.onSurfaceVariant.withOpacity(0.5)),
          ),
          const SizedBox(height: 14),
          Text('No suppliers yet', style: TextStyle(fontSize: context.sizes.fontMd, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
          const SizedBox(height: 6),
          Text('Add your first supplier to get started', style: TextStyle(fontSize: context.sizes.fontSm, color: cs.onSurfaceVariant.withOpacity(0.7))),
        ],
      ),
    );
  }

  Widget _buildMobileList(List<SupplierDoc> filtered, ColorScheme cs, PageState<SupplierDoc> state) {
    return ListView.builder(
      controller: _vScrollCtrl,
      padding: context.padSm,
      itemCount: filtered.length + (state.endReached ? 0 : 1),
      itemBuilder: (context, index) {
        if (index == filtered.length) {
          return _buildLoadMore(state, cs);
        }
        final s = filtered[index];
        return _buildMobileCard(s, cs);
      },
    );
  }

  Widget _buildMobileCard(SupplierDoc s, ColorScheme cs) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: context.radiusMd,
        border: Border.all(color: cs.outlineVariant.withOpacity(0.2)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openEditDialog(s),
          onLongPress: () => _deleteSupplier(context, s.id),
          borderRadius: context.radiusMd,
          child: Padding(
            padding: context.padMd,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: context.padSm,
                      decoration: BoxDecoration(
                        color: cs.primary.withOpacity(0.1),
                        borderRadius: context.radiusSm,
                      ),
                      child: Icon(Icons.person_rounded, size: 16, color: cs.primary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.name, style: TextStyle(fontSize: context.sizes.fontMd, fontWeight: FontWeight.w600, color: cs.onSurface)),
                          if (s.address.isNotEmpty)
                            Text(s.address, style: TextStyle(fontSize: context.sizes.fontSm, color: cs.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    _buildActionButton(Icons.call_rounded, context.appColors.success, () => _showSnack('Call ${s.phone}')),
                    const SizedBox(width: 6),
                    _buildActionButton(Icons.email_rounded, context.appColors.info, () => _showSnack('Email ${s.email}')),
                  ],
                ),
                context.gapVSm,
                Row(
                  children: [
                    Icon(Icons.phone_rounded, size: 12, color: cs.onSurfaceVariant.withOpacity(0.6)),
                    context.gapHXs,
                    Text(s.phone.isNotEmpty ? s.phone : '-', style: TextStyle(fontSize: context.sizes.fontSm, color: cs.onSurfaceVariant)),
                    context.gapHLg,
                    Icon(Icons.email_rounded, size: 12, color: cs.onSurfaceVariant.withOpacity(0.6)),
                    context.gapHXs,
                    Expanded(child: Text(s.email.isNotEmpty ? s.email : '-', style: TextStyle(fontSize: context.sizes.fontSm, color: cs.onSurfaceVariant), overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopTable(List<SupplierDoc> filtered, ColorScheme cs, PageState<SupplierDoc> state) {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withOpacity(0.5),
            border: Border(bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.3))),
          ),
          child: Row(
            children: [
              const SizedBox(width: 36),
              SizedBox(width: 140, child: _headerText('Name', cs)),
              Expanded(child: _headerText('Address', cs)),
              SizedBox(width: 110, child: _headerText('Phone', cs)),
              Expanded(child: _headerText('Email', cs)),
              SizedBox(width: 70, child: _headerText('Actions', cs, center: true)),
            ],
          ),
        ),
        // Rows
        Expanded(
          child: ListView.builder(
            controller: _vScrollCtrl,
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: filtered.length + (state.endReached ? 0 : 1),
            itemBuilder: (context, index) {
              if (index == filtered.length) {
                return _buildLoadMore(state, cs);
              }
              final s = filtered[index];
              return _buildDesktopRow(s, cs, index);
            },
          ),
        ),
      ],
    );
  }

  Widget _headerText(String text, ColorScheme cs, {bool center = false}) {
    return Text(
      text,
      style: TextStyle(fontSize: context.sizes.fontSm, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
      textAlign: center ? TextAlign.center : TextAlign.left,
    );
  }

  Widget _buildDesktopRow(SupplierDoc s, ColorScheme cs, int index) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: index.isEven ? cs.surface : cs.surfaceContainerHighest.withOpacity(0.25),
        borderRadius: context.radiusSm,
        border: Border.all(color: cs.outlineVariant.withOpacity(0.15)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openEditDialog(s),
          onLongPress: () => _deleteSupplier(context, s.id),
          borderRadius: context.radiusSm,
          hoverColor: cs.primary.withOpacity(0.04),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: cs.primary.withOpacity(0.1),
                    borderRadius: context.radiusSm,
                  ),
                  child: Center(
                    child: Text(
                      s.name.isNotEmpty ? s.name[0].toUpperCase() : '?',
                      style: TextStyle(fontSize: context.sizes.fontSm, fontWeight: FontWeight.w700, color: cs.primary),
                    ),
                  ),
                ),
                context.gapHSm,
                // Name
                SizedBox(
                  width: 132,
                  child: Text(s.name, style: TextStyle(fontSize: context.sizes.fontSm, fontWeight: FontWeight.w500, color: cs.onSurface), overflow: TextOverflow.ellipsis),
                ),
                // Address
                Expanded(
                  child: Text(s.address.isNotEmpty ? s.address : '-', style: TextStyle(fontSize: context.sizes.fontSm, color: cs.onSurfaceVariant), overflow: TextOverflow.ellipsis),
                ),
                // Phone
                SizedBox(
                  width: 110,
                  child: Text(s.phone.isNotEmpty ? s.phone : '-', style: TextStyle(fontSize: context.sizes.fontSm, color: cs.onSurface, fontFamily: 'monospace'), overflow: TextOverflow.ellipsis),
                ),
                // Email
                Expanded(
                  child: Text(s.email.isNotEmpty ? s.email : '-', style: TextStyle(fontSize: context.sizes.fontSm, color: cs.onSurface), overflow: TextOverflow.ellipsis),
                ),
                // Actions
                SizedBox(
                  width: 70,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildActionButton(Icons.call_rounded, context.appColors.success, () => _showSnack('Call ${s.phone}')),
                      context.gapHXs,
                      _buildActionButton(Icons.email_rounded, context.appColors.info, () => _showSnack('Email ${s.email}')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(IconData icon, Color color, VoidCallback onTap) {
    final smallRadius = context.radiusSm;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: smallRadius,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: smallRadius,
          ),
          child: Icon(icon, size: 14, color: color),
        ),
      ),
    );
  }

  Widget _buildLoadMore(PageState<SupplierDoc> state, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: state.loading
            ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary))
            : TextButton.icon(
                onPressed: () => ref.read(suppliersPagedControllerProvider).loadMore(),
                icon: Icon(Icons.expand_more_rounded, size: 18, color: cs.primary),
                label: Text('Load more', style: TextStyle(fontSize: context.sizes.fontSm, color: cs.primary)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  backgroundColor: cs.primary.withOpacity(0.08),
                  shape: RoundedRectangleBorder(borderRadius: context.radiusSm),
                ),
              ),
      ),
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 1)));
  }

  Future<void> _openAddDialog() async {
    final repo = ref.read(supplierRepoProvider);
    final result = await showDialog<_SupplierEditResult>(
      context: context,
      builder: (_) => const _SupplierEditDialog(),
    );
    if (result == null) return;
    await repo.addSupplier(name: result.name,address: result.address,phone: result.phone,email: result.email);
    if (!mounted) return;
    ref.read(suppliersPagedControllerProvider).resetAndLoad();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Supplier added')));
  }

  Future<void> _openEditDialog(SupplierDoc doc) async {
    final repo = ref.read(supplierRepoProvider);
    final result = await showDialog<_SupplierEditResult>(
      context: context,
      builder: (_) => _SupplierEditDialog(existing: doc),
    );
    if (result == null) return;
    await repo.updateSupplier(id: doc.id,name: result.name,address: result.address,phone: result.phone,email: result.email);
    if (!mounted) return;
    ref.read(suppliersPagedControllerProvider).resetAndLoad();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Supplier updated')));
  }

  Future<void> _deleteSupplier(BuildContext context, String id) async {
    // Capture messenger before awaits; usage after await is safe.
    // ignore: use_build_context_synchronously
    final rootMessenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Delete Supplier', style: context.texts.titleMedium?.copyWith(color: context.colors.onSurface, fontWeight: FontWeight.w700)),
        content: DefaultTextStyle(
          style: (context.texts.bodyMedium ?? const TextStyle()).copyWith(color: context.colors.onSurface),
          child: const Text('Are you sure?'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.colors.error, foregroundColor: context.colors.onError),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  if (ok != true) return;
  final repo = ref.read(supplierRepoProvider);
  await repo.deleteSupplier(id: id);
  if (!mounted) return;
  ref.read(suppliersPagedControllerProvider).resetAndLoad();
  rootMessenger.showSnackBar(const SnackBar(content: Text('Supplier deleted')));
  }
}

class _SupplierEditResult {
  final String name;
  final String address;
  final String phone;
  final String email;
  _SupplierEditResult({required this.name, required this.address, required this.phone, required this.email});
}

class _SupplierEditDialog extends StatefulWidget {
  final SupplierDoc? existing;
  const _SupplierEditDialog({this.existing});
  @override
  State<_SupplierEditDialog> createState() => _SupplierEditDialogState();
}

class _SupplierEditDialogState extends State<_SupplierEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _phone;
  late final TextEditingController _email;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _address = TextEditingController(text: e?.address ?? '');
    _phone = TextEditingController(text: e?.phone ?? '');
    _email = TextEditingController(text: e?.email ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return AlertDialog(
      title: Text(
        editing ? 'Edit Supplier' : 'Add Supplier',
        style: context.texts.titleMedium?.copyWith(color: context.colors.onSurface, fontWeight: FontWeight.w700),
      ),
      content: DefaultTextStyle(
        style: (context.texts.bodyMedium ?? const TextStyle()).copyWith(color: context.colors.onSurface),
        child: Form(
          key: _formKey,
          child: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _name,
                    style: context.texts.bodyMedium?.copyWith(color: context.colors.onSurface),
                    decoration: InputDecoration(
                      labelText: 'Name',
                      labelStyle: context.texts.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                      hintStyle: context.texts.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                      isDense: true,
                    ),
                    validator: (v) => (v==null || v.trim().isEmpty) ? 'Name required' : null,
                  ),
                  TextFormField(
                    controller: _address,
                    style: context.texts.bodyMedium?.copyWith(color: context.colors.onSurface),
                    decoration: InputDecoration(
                      labelText: 'Address',
                      labelStyle: context.texts.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                      hintStyle: context.texts.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                      isDense: true,
                    ),
                    maxLines: 2,
                  ),
                  TextFormField(
                    controller: _phone,
                    style: context.texts.bodyMedium?.copyWith(color: context.colors.onSurface),
                    decoration: InputDecoration(
                      labelText: 'Phone',
                      labelStyle: context.texts.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                      hintStyle: context.texts.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                  TextFormField(
                    controller: _email,
                    style: context.texts.bodyMedium?.copyWith(color: context.colors.onSurface),
                    decoration: InputDecoration(
                      labelText: 'Email',
                      labelStyle: context.texts.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                      hintStyle: context.texts.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
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
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.pop(context, _SupplierEditResult(
              name: _name.text.trim(),
              address: _address.text.trim(),
              phone: _phone.text.trim(),
              email: _email.text.trim(),
            ));
          },
          child: Text(editing ? 'Save' : 'Add'),
        ),
      ],
    );
  }
}
