import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth_repository_and_provider.dart';
import 'Products/inventory_repository.dart';
// Removed CSV export/import for Audit screen
import 'Products/inventory.dart' show productsStreamProvider, inventoryRepoProvider, selectedStoreProvider; // access shared providers
import 'Products/inventory_repository.dart' show ProductDoc; // product model
import '../../core/theme/theme_extension_helpers.dart';

// Public copy of active filter enum (was private in inventory.dart)
enum ActiveFilter { all, active, inactive }

class _AuditMeta {
  final DateTime updatedAt;
  final String updatedBy;
  _AuditMeta(this.updatedAt, this.updatedBy);
}

class AuditScreen extends ConsumerStatefulWidget {
  const AuditScreen({super.key});
  @override
  ConsumerState<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends ConsumerState<AuditScreen> {
  final Map<String,int> _storeOverrides = {};
  final Map<String,int> _whOverrides = {};
  final Map<String,String> _noteOverrides = {};
  final Map<String,_AuditMeta> _overrideMeta = {}; // tracks last update timestamp + user
  String _search = '';
  // Removed Active and GST dropdown filters per request

  String _fmtDateTime(DateTime d){
    return '${d.year.toString().padLeft(4,'0')}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')} ${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
  }
  String _fmtDate(DateTime d){
    return '${d.year.toString().padLeft(4,'0')}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
  }

  @override
  void dispose() { super.dispose(); }

  List<ProductDoc> _applyFilters(List<ProductDoc> src){
    Iterable<ProductDoc> it = src;
    final q = _search.trim().toLowerCase();
    if(q.isNotEmpty){
      it = it.where((p)=> p.sku.toLowerCase().contains(q) || p.name.toLowerCase().contains(q) || p.barcode.toLowerCase().contains(q));
    }
    // Active and GST filters removed
    // No forced date filter here; we'll group by date and render day-wise cards below.
    return it.toList();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(productsStreamProvider);
    final cs = Theme.of(context).colorScheme;
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
        child: Column(children: [
          // Header with search and audit button
          Container(
            padding: EdgeInsets.all(isMobile ? 10 : 14),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: context.radiusMd,
              border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
              boxShadow: [BoxShadow(color: cs.shadow.withOpacity(0.05), blurRadius: 10)],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Container(
                      height: 38,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withOpacity(0.3),
                        borderRadius: context.radiusMd,
                        border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
                      ),
                      child: TextField(
                        style: TextStyle(fontSize: context.sizes.fontSm, color: cs.onSurface),
                        decoration: InputDecoration(
                          prefixIcon: Icon(Icons.search_rounded, size: 18, color: cs.onSurfaceVariant),
                          hintText: 'Search SKU/Name/Barcode',
                          hintStyle: TextStyle(fontSize: context.sizes.fontSm, color: cs.onSurfaceVariant.withOpacity(0.7)),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        onChanged: (v) => setState(() => _search = v),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _buildAuditButton(cs),
                ]),
                context.gapVSm,
                Row(children: [
                  Container(
                    padding: context.padXs,
                    decoration: BoxDecoration(
                      color: cs.primary.withOpacity(0.1),
                      borderRadius: context.radiusSm,
                    ),
                    child: Icon(Icons.info_outline_rounded, size: 12, color: cs.primary),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Tap any row to edit stock counts & add a note',
                      style: TextStyle(fontSize: context.sizes.fontXs, color: cs.onSurfaceVariant),
                    ),
                  ),
                ]),
              ],
            ),
          ),
          context.gapVMd,
          // Content
          Expanded(
            child: async.when(
              data: (products) {
                if (products.isEmpty) {
                  return _buildEmptyState(cs, 'No products', 'Add products to start auditing');
                }
                final filtered = _applyFilters(products);
                if (filtered.isEmpty) {
                  return _buildEmptyState(cs, 'No matches', 'Try a different search');
                }

                // Group by day
                final Map<String, List<ProductDoc>> groups = {};
                DateTime? eff(ProductDoc p) => _overrideMeta[p.sku]?.updatedAt ?? p.updatedAt;
                for (final p in filtered) {
                  final dt = eff(p);
                  if (dt == null) continue;
                  final key = _fmtDate(DateTime(dt.year, dt.month, dt.day));
                  groups.putIfAbsent(key, () => <ProductDoc>[]).add(p);
                }
                final keys = groups.keys.toList()..sort((a, b) => b.compareTo(a));

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: keys.length,
                  itemBuilder: (context, i) {
                    final key = keys[i];
                    final items = groups[key]!
                      ..sort((a, b) {
                        final da = eff(a) ?? DateTime.fromMillisecondsSinceEpoch(0);
                        final db = eff(b) ?? DateTime.fromMillisecondsSinceEpoch(0);
                        return db.compareTo(da);
                      });
                    return _buildDateGroup(key, items, cs, isMobile);
                  },
                );
              },
              error: (e, st) => _buildEmptyState(cs, 'Error', e.toString()),
              loading: () => Center(child: CircularProgressIndicator(color: cs.primary)),
            ),
          ),
          // Footer note
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withOpacity(0.3),
              borderRadius: context.radiusSm,
            ),
            child: Row(children: [
              Icon(Icons.info_outline_rounded, size: 12, color: cs.onSurfaceVariant.withOpacity(0.7)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Changes are LOCAL audit overrides. They do NOT modify product master data.',
                  style: TextStyle(fontSize: context.sizes.fontXs, color: cs.onSurfaceVariant.withOpacity(0.7)),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildAuditButton(ColorScheme cs) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openQuickAudit,
        borderRadius: context.radiusMd,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [cs.primary, cs.primary.withOpacity(0.8)]),
            borderRadius: context.radiusMd,
            boxShadow: [BoxShadow(color: cs.primary.withOpacity(0.3), blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.inventory_2_rounded, size: 14, color: cs.onPrimary),
            const SizedBox(width: 6),
            Text('Quick Audit', style: TextStyle(fontSize: context.sizes.fontSm, fontWeight: FontWeight.w600, color: cs.onPrimary)),
          ]),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme cs, String title, String subtitle) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: context.radiusMd,
        border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.inventory_rounded, size: 40, color: cs.primary.withOpacity(0.5)),
            ),
            const SizedBox(height: 14),
            Text(title, style: TextStyle(fontSize: context.sizes.fontMd, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
            context.gapVXs,
            Text(subtitle, style: TextStyle(fontSize: context.sizes.fontSm, color: cs.onSurfaceVariant.withOpacity(0.7))),
          ],
        ),
      ),
    );
  }

  Widget _buildDateGroup(String dateKey, List<ProductDoc> items, ColorScheme cs, bool isMobile) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: context.radiusMd,
        border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
        boxShadow: [BoxShadow(color: cs.shadow.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withOpacity(0.5),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.12),
                  borderRadius: context.radiusSm,
                ),
                child: Icon(Icons.calendar_today_rounded, size: 12, color: cs.primary),
              ),
              const SizedBox(width: 10),
              Text(dateKey, style: TextStyle(fontSize: context.sizes.fontSm, fontWeight: FontWeight.w700, color: cs.onSurface)),
              context.gapHSm,
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.1),
                  borderRadius: context.radiusMd,
                ),
                child: Text('${items.length} items', style: TextStyle(fontSize: context.sizes.fontXs, fontWeight: FontWeight.w600, color: cs.primary)),
              ),
            ]),
          ),
          // Items
          if (isMobile)
            _buildMobileItems(items, cs)
          else
            _buildDesktopTable(items, cs),
        ],
      ),
    );
  }

  Widget _buildMobileItems(List<ProductDoc> items, ColorScheme cs) {
    return Padding(
      padding: context.padSm,
      child: Column(
        children: items.map((p) => _buildMobileCard(p, cs)).toList(),
      ),
    );
  }

  Widget _buildMobileCard(ProductDoc p, ColorScheme cs) {
    final storeQty = _storeOverrides[p.sku] ?? p.stockAt('Store');
    final whQty = _whOverrides[p.sku] ?? p.stockAt('Warehouse');
    final total = storeQty + whQty;
    final note = _noteOverrides[p.sku] ?? p.auditNote;

    return GestureDetector(
      onTap: () => _openEditDialog(p),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: context.padMd,
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: context.radiusMd,
          border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.08),
                  borderRadius: context.radiusXs,
                ),
                child: Text(p.sku, style: TextStyle(fontSize: context.sizes.fontXs, fontWeight: FontWeight.w600, color: cs.primary, fontFamily: 'monospace')),
              ),
              context.gapHSm,
              Expanded(child: Text(p.name, style: TextStyle(fontSize: context.sizes.fontSm, fontWeight: FontWeight.w600, color: cs.onSurface), overflow: TextOverflow.ellipsis)),
              Icon(Icons.edit_rounded, size: 14, color: cs.onSurfaceVariant.withOpacity(0.5)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              _buildQtyBadge('Store', storeQty, context.appColors.info, cs),
              context.gapHSm,
              _buildQtyBadge('Warehouse', whQty, context.colors.tertiary, cs),
              context.gapHSm,
              _buildQtyBadge('Total', total, cs.primary, cs),
            ]),
            if (note != null && note.isNotEmpty) ...[
              context.gapVSm,
              Row(children: [
                Icon(Icons.note_rounded, size: 12, color: cs.onSurfaceVariant.withOpacity(0.6)),
                context.gapHXs,
                Flexible(child: Text(note, style: TextStyle(fontSize: context.sizes.fontXs, color: cs.onSurfaceVariant), maxLines: 2, overflow: TextOverflow.ellipsis)),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQtyBadge(String label, int qty, Color color, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: context.radiusSm,
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Text(qty.toString(), style: TextStyle(fontSize: context.sizes.fontSm, fontWeight: FontWeight.w700, color: color)),
          Text(label, style: TextStyle(fontSize: context.sizes.fontXs, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildDesktopTable(List<ProductDoc> items, ColorScheme cs) {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.3))),
          ),
          child: Row(children: [
            SizedBox(width: 80, child: _headerText('SKU', cs)),
            Expanded(flex: 2, child: _headerText('Name', cs)),
            SizedBox(width: 90, child: _headerText('Barcode', cs)),
            SizedBox(width: 70, child: _headerText('Price', cs, center: true)),
            SizedBox(width: 45, child: _headerText('GST', cs, center: true)),
            SizedBox(width: 50, child: _headerText('Store', cs, center: true)),
            SizedBox(width: 50, child: _headerText('W/H', cs, center: true)),
            SizedBox(width: 50, child: _headerText('Total', cs, center: true)),
            SizedBox(width: 100, child: _headerText('Updated', cs)),
            SizedBox(width: 80, child: _headerText('By', cs)),
            Expanded(child: _headerText('Note', cs)),
          ]),
        ),
        // Rows
        ...items.asMap().entries.map((entry) {
          final index = entry.key;
          final p = entry.value;
          return _buildDesktopRow(p, cs, index);
        }),
      ],
    );
  }

  Widget _headerText(String text, ColorScheme cs, {bool center = false}) {
    return Text(
      text,
      style: TextStyle(fontSize: context.sizes.fontXs, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
      textAlign: center ? TextAlign.center : TextAlign.left,
    );
  }

  Widget _buildDesktopRow(ProductDoc p, ColorScheme cs, int index) {
    final storeQty = _storeOverrides[p.sku] ?? p.stockAt('Store');
    final whQty = _whOverrides[p.sku] ?? p.stockAt('Warehouse');
    final total = storeQty + whQty;
    final note = _noteOverrides[p.sku] ?? p.auditNote ?? '-';
    final updatedAt = _overrideMeta[p.sku]?.updatedAt ?? p.updatedAt;
    final updatedBy = _overrideMeta[p.sku]?.updatedBy ?? p.updatedBy ?? '-';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openEditDialog(p),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: index.isEven ? cs.surface : cs.surfaceContainerHighest.withOpacity(0.25),
            border: Border(bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.1))),
          ),
          child: Row(children: [
            // SKU
            SizedBox(
              width: 80,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.08),
                  borderRadius: context.radiusXs,
                ),
                child: Text(p.sku, style: TextStyle(fontSize: context.sizes.fontXs, fontWeight: FontWeight.w600, color: cs.primary, fontFamily: 'monospace'), overflow: TextOverflow.ellipsis),
              ),
            ),
            // Name
            Expanded(
              flex: 2,
              child: Text(p.name, style: TextStyle(fontSize: context.sizes.fontSm, color: cs.onSurface), overflow: TextOverflow.ellipsis),
            ),
            // Barcode
            SizedBox(
              width: 90,
              child: Text(p.barcode, style: TextStyle(fontSize: context.sizes.fontXs, color: cs.onSurfaceVariant), overflow: TextOverflow.ellipsis),
            ),
            // Price
            SizedBox(
              width: 70,
              child: Text('₹${p.unitPrice.toStringAsFixed(0)}', style: TextStyle(fontSize: context.sizes.fontXs, color: cs.onSurface), textAlign: TextAlign.center),
            ),
            // GST
            SizedBox(
              width: 45,
              child: Text('${(p.taxPct ?? 0).toString()}%', style: TextStyle(fontSize: context.sizes.fontXs, color: cs.onSurfaceVariant), textAlign: TextAlign.center),
            ),
            // Store
            SizedBox(
              width: 50,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(storeQty.toString(), style: TextStyle(fontSize: context.sizes.fontXs, fontWeight: FontWeight.w600, color: context.appColors.info), textAlign: TextAlign.center),
              ),
            ),
            // Warehouse
            SizedBox(
              width: 50,
              child: Text(whQty.toString(), style: TextStyle(fontSize: context.sizes.fontXs, fontWeight: FontWeight.w600, color: context.colors.tertiary), textAlign: TextAlign.center),
            ),
            // Total
            SizedBox(
              width: 50,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.1),
                  borderRadius: context.radiusXs,
                ),
                child: Text(total.toString(), style: TextStyle(fontSize: context.sizes.fontXs, fontWeight: FontWeight.w700, color: cs.primary), textAlign: TextAlign.center),
              ),
            ),
            // Updated At
            SizedBox(
              width: 100,
              child: Text(updatedAt != null ? _fmtDateTime(updatedAt) : '-', style: TextStyle(fontSize: context.sizes.fontXs, color: cs.onSurfaceVariant)),
            ),
            // Updated By
            SizedBox(
              width: 80,
              child: Text(updatedBy, style: TextStyle(fontSize: context.sizes.fontXs, color: cs.onSurfaceVariant), overflow: TextOverflow.ellipsis),
            ),
            // Note
            Expanded(
              child: Text(note, style: TextStyle(fontSize: context.sizes.fontXs, color: cs.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _openQuickAudit() async {
    final p = await showDialog<ProductDoc>(
      context: context,
      builder: (_) => const _ProductPickerDialog(),
    );
    if (p == null) return;
    if (!mounted) return;
    final result = await showDialog<_AuditEditResult>(
      context: context,
      builder: (_) => _AuditEditDialog(
        sku: p.sku,
        store: _storeOverrides[p.sku] ?? p.stockAt('Store'),
        warehouse: _whOverrides[p.sku] ?? p.stockAt('Warehouse'),
        note: _noteOverrides[p.sku] ?? p.auditNote,
      ),
    );
    if (result == null) return;
    if (!mounted) return;
    final user = ref.read(authStateProvider);
    final origStore = p.stockAt('Store');
    final origWh = p.stockAt('Warehouse');
    setState(() {
      if (result.store == origStore) {
        _storeOverrides.remove(p.sku);
      } else {
        _storeOverrides[p.sku] = result.store;
      }
      if (result.warehouse == origWh) {
        _whOverrides.remove(p.sku);
      } else {
        _whOverrides[p.sku] = result.warehouse;
      }
      if (result.note == null || result.note!.trim().isEmpty) {
        _noteOverrides.remove(p.sku);
      } else {
        _noteOverrides[p.sku] = result.note!.trim();
      }
      final changed = (result.store != origStore) || (result.warehouse != origWh) || (result.note != (p.auditNote ?? ''));
      if (changed) {
        final by = (user?.email?.isNotEmpty ?? false) ? user!.email! : (user?.uid ?? 'local');
        _overrideMeta[p.sku] = _AuditMeta(DateTime.now(), by);
      } else {
        _overrideMeta.remove(p.sku);
      }
    });
    try {
  if (user != null) {
    final storeId = ref.read(selectedStoreProvider);
    if (storeId == null) throw StateError('No store selected');
        await ref.read(inventoryRepoProvider).auditUpdateStock(
      storeId: storeId,
              sku: p.sku,
              storeQty: result.store,
              warehouseQty: result.warehouse,
              updatedBy: user.email ?? user.uid,
              note: result.note?.trim().isEmpty ?? true ? null : result.note!.trim(),
            );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update: $e')));
      }
    }
  }

  Future<void> _openEditDialog(ProductDoc p) async {
    final result = await showDialog<_AuditEditResult>(
      context: context,
      builder: (_) => _AuditEditDialog(
        sku: p.sku,
        store: _storeOverrides[p.sku] ?? p.stockAt('Store'),
        warehouse: _whOverrides[p.sku] ?? p.stockAt('Warehouse'),
        note: _noteOverrides[p.sku] ?? p.auditNote,
      ),
    );
    if(result == null) return;
    final user = ref.read(authStateProvider);
    final origStore = p.stockAt('Store');
    final origWh = p.stockAt('Warehouse');
    setState(() {
      if(result.store == origStore){ _storeOverrides.remove(p.sku);} else {_storeOverrides[p.sku]=result.store;}
      if(result.warehouse == origWh){ _whOverrides.remove(p.sku);} else {_whOverrides[p.sku]=result.warehouse;}
      if(result.note == null || result.note!.trim().isEmpty){ _noteOverrides.remove(p.sku);} else { _noteOverrides[p.sku]=result.note!.trim(); }
      final changed = (result.store!=origStore) || (result.warehouse!=origWh) || (result.note != (p.auditNote ?? ''));
      if(changed){
        final by = (user?.email?.isNotEmpty ?? false) ? user!.email! : (user?.uid ?? 'local');
        _overrideMeta[p.sku] = _AuditMeta(DateTime.now(), by);
      } else {
        _overrideMeta.remove(p.sku);
      }
    });
    try{
      if(user != null){
        final storeId = ref.read(selectedStoreProvider);
        if (storeId == null) throw StateError('No store selected');
        await ref.read(inventoryRepoProvider).auditUpdateStock(
          storeId: storeId,
          sku: p.sku,
          storeQty: result.store,
          warehouseQty: result.warehouse,
          updatedBy: user.email ?? user.uid,
          note: result.note?.trim().isEmpty ?? true ? null : result.note!.trim(),
        );
      }
    }catch(e){
      if(mounted){
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update: $e')));
      }
    }
  }

  // Export CSV removed per request.
}

class _AuditEditResult {
  final int store;
  final int warehouse;
  final String? note;
  _AuditEditResult({required this.store, required this.warehouse, this.note});
}

class _AuditEditDialog extends StatefulWidget {
  final String sku; final int store; final int warehouse; final String? note;
  const _AuditEditDialog({required this.sku, required this.store, required this.warehouse, this.note});
  @override State<_AuditEditDialog> createState()=>_AuditEditDialogState();
}

class _AuditEditDialogState extends State<_AuditEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _store;
  late final TextEditingController _wh;
  late final TextEditingController _note;

  @override void initState(){
    super.initState();
    _store = TextEditingController(text: widget.store.toString());
    _wh = TextEditingController(text: widget.warehouse.toString());
    _note = TextEditingController(text: widget.note ?? '');
  }
  @override void dispose(){ _store.dispose(); _wh.dispose(); _note.dispose(); super.dispose(); }

  @override Widget build(BuildContext context){
    return AlertDialog(
      title: Text(
        'Audit ${widget.sku}',
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
                  Row(children:[
                    Expanded(child: TextFormField(
                      controller: _store,
                      style: context.texts.bodyMedium?.copyWith(color: context.colors.onSurface),
                      decoration: InputDecoration(
                        labelText:'Store Qty',
                        labelStyle: context.texts.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                        hintStyle: context.texts.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                      validator:(v){ final n=int.tryParse(v??''); if(n==null||n<0) return 'Enter >=0'; return null; },
                    )),
                    context.gapHMd,
                    Expanded(child: TextFormField(
                      controller: _wh,
                      style: context.texts.bodyMedium?.copyWith(color: context.colors.onSurface),
                      decoration: InputDecoration(
                        labelText:'Warehouse Qty',
                        labelStyle: context.texts.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                        hintStyle: context.texts.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                      validator:(v){ final n=int.tryParse(v??''); if(n==null||n<0) return 'Enter >=0'; return null; },
                    )),
                  ]),
                  context.gapVMd,
                  TextFormField(
                    controller: _note,
                    style: context.texts.bodyMedium?.copyWith(color: context.colors.onSurface),
                    decoration: InputDecoration(
                      labelText:'Note (optional)',
                      labelStyle: context.texts.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                      hintStyle: context.texts.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                      isDense: true,
                    ),
                    maxLines: 3,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: ()=>Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: (){
            if(!(_formKey.currentState?.validate()??false)) return;
            final store = int.parse(_store.text.trim());
            final wh = int.parse(_wh.text.trim());
            Navigator.pop(context, _AuditEditResult(store: store, warehouse: wh, note: _note.text.trim().isEmpty ? null : _note.text.trim()));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// Simple product picker for quick Audit button
class _ProductPickerDialog extends ConsumerStatefulWidget {
  const _ProductPickerDialog();
  @override
  ConsumerState<_ProductPickerDialog> createState() => _ProductPickerDialogState();
}

class _ProductPickerDialogState extends ConsumerState<_ProductPickerDialog> {
  final _qCtrl = TextEditingController();
  @override
  void dispose(){ _qCtrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context){
    final async = ref.watch(productsStreamProvider);
    return AlertDialog(
      title: Text('Pick a product', style: context.texts.titleMedium?.copyWith(color: context.colors.onSurface, fontWeight: FontWeight.w700)),
      content: DefaultTextStyle(
        style: (context.texts.bodyMedium ?? const TextStyle()).copyWith(color: context.colors.onSurface),
        child: SizedBox(
        width: 480,
        child: async.when(
          data: (list){
            final q = _qCtrl.text.trim().toLowerCase();
            final results = q.isEmpty
                ? list.take(30).toList()
                : list.where((p)=> p.sku.toLowerCase().contains(q) || p.name.toLowerCase().contains(q) || p.barcode.toLowerCase().contains(q)).take(30).toList();
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _qCtrl,
                  style: context.texts.bodyMedium?.copyWith(color: context.colors.onSurface),
                  decoration: InputDecoration(
                    prefixIcon: Icon(Icons.search, color: context.colors.onSurfaceVariant),
                    labelText: 'Search SKU/Name/Barcode',
                    labelStyle: context.texts.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                    hintStyle: context.texts.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                    isDense: true,
                  ),
                  onChanged: (_)=> setState((){}),
                ),
                context.gapVSm,
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: results.length,
                    itemBuilder: (_, i){
                      final p = results[i];
                      return ListTile(
                        dense: true,
                        title: Text(
                          '${p.sku} • ${p.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.texts.bodyMedium?.copyWith(color: context.colors.onSurface),
                        ),
                        subtitle: p.barcode.isNotEmpty
                            ? Text(p.barcode, style: context.texts.bodySmall?.copyWith(color: context.colors.onSurfaceVariant))
                            : null,
                        onTap: ()=> Navigator.pop(context, p),
                      );
                    },
                  ),
                ),
              ],
            );
          },
          error: (e,_)=> SizedBox(width: 360, child: Text('Error: $e')),
          loading: ()=> const SizedBox(width: 360, height: 160, child: Center(child: CircularProgressIndicator())),
        ),
      ),
      ),
      actions: [
        TextButton(onPressed: ()=> Navigator.pop(context), child: const Text('Cancel')),
      ],
    );
  }
}
