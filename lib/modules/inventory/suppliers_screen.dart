import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/theme/theme_utils.dart';

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
  SupplierRepository({FirebaseFirestore? firestore}):_db=firestore??FirebaseFirestore.instance; final FirebaseFirestore _db;
  CollectionReference<Map<String,dynamic>> get _col=>_db.collection('suppliers');
  Stream<List<SupplierDoc>> streamSuppliers()=>_col.orderBy('name').snapshots().map((snap)=>snap.docs.map((d)=>SupplierDoc.fromSnap(d)).toList());
  Future<void> addSupplier({required String name,required String address,required String phone,required String email}) async{
    await _col.add({'name':name,'address':address,'phone':phone,'email':email,'createdAt':FieldValue.serverTimestamp()});
  }
  Future<void> updateSupplier({required String id,required String name,required String address,required String phone,required String email}) async{
    await _col.doc(id).update({'name':name,'address':address,'phone':phone,'email':email,'updatedAt':FieldValue.serverTimestamp()});
  }
  Future<void> deleteSupplier({required String id}) async{ await _col.doc(id).delete(); }
}

/// Repository provider for suppliers (scoped for reuse if needed elsewhere)
final supplierRepoProvider = Provider<SupplierRepository>((ref) => SupplierRepository());

/// Stream provider for suppliers list.
final supplierStreamProvider = StreamProvider.autoDispose<List<SupplierDoc>>((ref) {
  final repo = ref.watch(supplierRepoProvider);
  return repo.streamSuppliers();
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

  @override
  void dispose() {
    _hScrollCtrl.dispose();
    super.dispose();
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
    final async = ref.watch(supplierStreamProvider);
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 480;
              // Compact search field with a max width so it doesn't dominate the row
              final searchField = Flexible(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: narrow ? 260 : 420),
                    child: TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search name / phone / email',
                        isDense: true,
                        floatingLabelBehavior: FloatingLabelBehavior.never,
                      ),
                      onChanged: (v) => setState(() => _search = v),
                    ),
                  ),
                ),
              );
              final addBtn = FilledButton.icon(
                onPressed: _openAddDialog,
                icon: const Icon(Icons.add),
                label: const Text('Add Supplier'),
              );
              if (narrow) {
                // On mobile, place search and button in a single row with tight spacing
                return Row(children: [
                  searchField,
                  const SizedBox(width: 8),
                  Flexible(flex: 0, child: addBtn),
                ]);
              }
              return Row(children: [
                searchField,
                const SizedBox(width: 12),
                addBtn,
              ]);
            },
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              child: async.when(
                data: (list) {
                  // Sign-in requirement removed.
                  if (list.isEmpty) {
                    return const Center(child: Text('No suppliers found.'));
                  }
                  final filtered = _filter(list);
                  if (filtered.isEmpty) {
                    return const Center(child: Text('No suppliers match search.'));
                  }
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final addressWidth = constraints.maxWidth < 480 ? 220.0 : 300.0;
                      // On narrow screens, render a mobile-friendly stacked list instead of a wide DataTable
                      if (constraints.maxWidth < 560) {
                        return Scrollbar(
                          thumbVisibility: true,
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemBuilder: (context, i) {
                              final s = filtered[i];
                              return ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                title: Text(s.name, style: context.texts.titleSmall?.copyWith(color: context.colors.onSurface, fontWeight: FontWeight.w600)),
                                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  if (s.address.isNotEmpty)
                                    Text(s.address, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.texts.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
                                  const SizedBox(height: 2),
                                  Row(children: [
                                    Expanded(child: Text(s.phone, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.texts.bodySmall?.copyWith(color: context.colors.onSurface))),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text(s.email, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.texts.bodySmall?.copyWith(color: context.colors.onSurface)))
                                  ]),
                                ]),
                                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                  IconButton(
                                    tooltip: 'Call',
                                    icon: const Icon(Icons.call),
                                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Call ${s.phone} (demo)')),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Email',
                                    icon: const Icon(Icons.email_outlined),
                                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Email ${s.email} (demo)')),
                                    ),
                                  ),
                                ]),
                                onTap: () => _openEditDialog(s),
                                onLongPress: () => _deleteSupplier(context, s.id),
                              );
                            },
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemCount: filtered.length,
                          ),
                        );
                      }
                      final table = DataTable(
                        columnSpacing: 24,
                        headingRowHeight: 42,
                        dataRowMinHeight: 40,
                        dataRowMaxHeight: 46,
                        columns: const [
                          DataColumn(label: Text('Name')),
                          DataColumn(label: Text('Address')),
                          DataColumn(label: Text('Phone')),
                          DataColumn(label: Text('Email')),
                          DataColumn(label: Text('Actions')),
                        ],
                        rows: [
                          for (final s in filtered)
                            DataRow(
                              onSelectChanged: (selected) {
                                if (selected == true) {
                                  _openEditDialog(s);
                                }
                              },
                              onLongPress: () => _deleteSupplier(context, s.id),
                              cells: [
                                DataCell(Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false)),
                                DataCell(SizedBox(width: addressWidth, child: Text(s.address, maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false))),
                                DataCell(Text(s.phone, maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false)),
                                DataCell(Text(s.email, maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false)),
                                DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                                  IconButton(
                                    tooltip: 'Call',
                                    icon: const Icon(Icons.call),
                                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Call ${s.phone} (demo)')),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Email',
                                    icon: const Icon(Icons.email_outlined),
                                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Email ${s.email} (demo)')),
                                    ),
                                  ),
                                ])),
                              ],
                            ),
                        ],
                      );
                      return Scrollbar(
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
                              child: DataTableTheme(
                                data: DataTableThemeData(
                                  dataTextStyle: context.texts.bodySmall?.copyWith(color: context.colors.onSurface),
                                  headingTextStyle: context.texts.bodySmall?.copyWith(color: context.colors.onSurface, fontWeight: FontWeight.w700),
                                ),
                                child: table,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
                error: (e, st) => Center(child: Text('Error: $e')),
                loading: () => const Center(child: CircularProgressIndicator()),
              ),
            ),
          ),
        ],
      ),
    );
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
