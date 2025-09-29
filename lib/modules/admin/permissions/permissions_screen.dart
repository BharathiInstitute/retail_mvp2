import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../rbac/admin_rbac_providers.dart';

/// Data model: Per-module CRUD role sets.
/// Collection: `permissions`
/// Doc ID: moduleKey (e.g. `inventory`, `dashboard.sales`).
/// Shape (new schema):
/// {
///   moduleKey: 'inventory',
///   label: 'Inventory',
///   readRoles:   ['owner','manager','cashier'],
///   createRoles: ['owner','manager','cashier'],
///   updateRoles: ['owner','manager'],
///   deleteRoles: ['owner','manager'],
///   createdAt, updatedAt
/// }
/// Legacy support: documents may still have 'allowedRoles' (treated as readRoles + all actions fallback).
/// UI: matrix toggle of roles vs actions (R,C,U,D) plus quick copy-from-read convenience.

final _permissionsColl = FirebaseFirestore.instance.collection('permissions');

// Stream provider for all permissions ordered by moduleKey
final permissionsStreamProvider = StreamProvider.autoDispose<List<QueryDocumentSnapshot<Map<String,dynamic>>>>((ref){
  return _permissionsColl.orderBy('moduleKey').snapshots().map((snap)=>snap.docs.cast<QueryDocumentSnapshot<Map<String,dynamic>>>());
});

class PermissionsScreen extends ConsumerWidget {
  const PermissionsScreen({super.key});
  static const knownRoles = ['owner','manager','accountant','cashier','clerk'];

  bool _canEdit(Capabilities c) => c.manageUsers || c.editSettings; // editing gate

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(capabilitiesProvider);
    final permsAsync = ref.watch(permissionsStreamProvider);
    return permsAsync.when(
      data: (docs){
        if(docs.isEmpty){
          return _EmptyState(onCreate: _canEdit(caps) ? () => _showCreateDialog(context, caps) : null, canCreate: _canEdit(caps));
        }
        return Column(children:[
          Align(alignment: Alignment.centerLeft, child: Wrap(spacing:8, runSpacing:4, children:[
            if(_canEdit(caps)) FilledButton.icon(onPressed: ()=>_showCreateDialog(context, caps), icon: const Icon(Icons.add), label: const Text('Add Permission')),
          ])),
          const SizedBox(height:8),
          Expanded(child: ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __)=> const Divider(height:1),
            itemBuilder: (ctx,i){
              final d = docs[i];
              final data = d.data();
              final moduleKey = data['moduleKey'] as String? ?? d.id;
              final label = data['label'] as String? ?? moduleKey;
              final roles = (data['readRoles'] as List?)?.whereType<String>().toList()
                ?? (data['allowedRoles'] as List?)?.whereType<String>().toList()
                ?? const <String>[];
              final createRoles = (data['createRoles'] as List?)?.whereType<String>().toList();
              final updateRoles = (data['updateRoles'] as List?)?.whereType<String>().toList();
              final deleteRoles = (data['deleteRoles'] as List?)?.whereType<String>().toList();
              return ListTile(
                title: Text(label, style: Theme.of(context).textTheme.titleMedium),
                subtitle: Padding(padding: const EdgeInsets.only(top:4), child: _RoleSummaryChips(read: roles, create: createRoles, update: updateRoles, delete: deleteRoles)),
                leading: const Icon(Icons.lock_outline),
                trailing: _canEdit(caps) ? PopupMenuButton<String>(
                  onSelected: (value){
                    switch(value){
                      case 'edit': _showEditDialog(context, d.id, moduleKey, label, roles, createRoles, updateRoles, deleteRoles); break;
                      case 'delete': _confirmDelete(context, d.id, label); break;
                    }
                  },
                  itemBuilder: (ctx)=> [
                    const PopupMenuItem(value:'edit', child: ListTile(leading: Icon(Icons.edit), title: Text('Edit'), dense:true, contentPadding: EdgeInsets.zero)),
                    const PopupMenuItem(value:'delete', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Delete'), dense:true, contentPadding: EdgeInsets.zero)),
                  ],
                ) : null,
              );
            },
          )),
        ]);
      },
      loading: ()=> const Center(child: CircularProgressIndicator()),
      error: (e,st)=> Center(child: Text('Failed to load permissions: $e')),
    );
  }

  Future<void> _showCreateDialog(BuildContext context, Capabilities caps) async {
    final formKey = GlobalKey<FormState>();
    final moduleCtrl = TextEditingController();
    final labelCtrl = TextEditingController();
    final readSel = <String>{};
    final createSel = <String>{};
    final updateSel = <String>{};
    final deleteSel = <String>{};
    await showDialog(context: context, builder: (ctx){
      return AlertDialog(
        title: const Text('New Permission'),
        content: SizedBox(width: 420, child: Form(key: formKey, child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(controller: moduleCtrl, decoration: const InputDecoration(labelText: 'Module Key', hintText: 'e.g. inventory or dashboard.sales'), validator: (v){
              if(v==null || v.trim().isEmpty) return 'Required';
              if(!RegExp(r'^[a-z0-9_.-]+$').hasMatch(v)) return 'Lowercase letters, numbers, . _ - only';
              return null;
            }),
            TextFormField(controller: labelCtrl, decoration: const InputDecoration(labelText: 'Label'), validator: (v)=> (v==null||v.trim().isEmpty)?'Required':null),
            const SizedBox(height:16),
            Align(alignment: Alignment.centerLeft, child: Text('Role Matrix', style: Theme.of(context).textTheme.labelLarge)),
            const SizedBox(height:8),
            _RoleActionMatrix(
              readSel: readSel,
              createSel: createSel,
              updateSel: updateSel,
              deleteSel: deleteSel,
              onCopyReadToAll: (){
                createSel
                  ..clear()
                  ..addAll(readSel);
                updateSel
                  ..clear()
                  ..addAll(readSel);
                deleteSel
                  ..clear()
                  ..addAll(readSel);
              },
            ),
          ],
        )))),
        actions: [
          TextButton(onPressed: ()=> Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () async {
            if(!formKey.currentState!.validate()) return;
            final key = moduleCtrl.text.trim();
            final readRoles = readSel.toList()..sort();
            try{
              await FirebaseFirestore.instance.runTransaction((tx) async {
                final docRef = _permissionsColl.doc(key);
                final snap = await tx.get(docRef);
                if(snap.exists){
                  throw 'Module key already exists';
                }
                tx.set(docRef, {
                  'moduleKey': key,
                  'label': labelCtrl.text.trim(),
                  'readRoles': readRoles,
                  'createRoles': (createSel.isEmpty ? readSel : createSel).toList()..sort(),
                  'updateRoles': (updateSel.isEmpty ? readSel : updateSel).toList()..sort(),
                  'deleteRoles': (deleteSel.isEmpty ? readSel : deleteSel).toList()..sort(),
                  'createdAt': FieldValue.serverTimestamp(),
                  'updatedAt': FieldValue.serverTimestamp(),
                });
              });
              if(context.mounted) Navigator.pop(ctx);
            }catch(e){
              if(context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Create failed: $e')));
              }
            }
          }, child: const Text('Create')),
        ],
      );
    });
  }

  Future<void> _showEditDialog(BuildContext context, String docId, String moduleKey, String label, List<String> readRoles, List<String>? createRoles, List<String>? updateRoles, List<String>? deleteRoles) async {
    final formKey = GlobalKey<FormState>();
    final labelCtrl = TextEditingController(text: label);
    final readSel = readRoles.toSet();
    final createSel = (createRoles ?? readRoles).toSet();
    final updateSel = (updateRoles ?? readRoles).toSet();
    final deleteSel = (deleteRoles ?? readRoles).toSet();
    await showDialog(context: context, builder: (ctx){
      return AlertDialog(
        title: Text('Edit: $moduleKey'),
        content: SizedBox(width:420, child: Form(key: formKey, child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(controller: labelCtrl, decoration: const InputDecoration(labelText: 'Label'), validator: (v)=> (v==null||v.trim().isEmpty)?'Required':null),
            const SizedBox(height:16),
            _RoleActionMatrix(
              readSel: readSel,
              createSel: createSel,
              updateSel: updateSel,
              deleteSel: deleteSel,
              onCopyReadToAll: (){
                createSel
                  ..clear()
                  ..addAll(readSel);
                updateSel
                  ..clear()
                  ..addAll(readSel);
                deleteSel
                  ..clear()
                  ..addAll(readSel);
              },
            ),
          ],
        )))),
        actions: [
          TextButton(onPressed: ()=> Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () async {
            if(!formKey.currentState!.validate()) return;
            final readRoles = readSel.toList()..sort();
            try{
              await _permissionsColl.doc(docId).set({
                'label': labelCtrl.text.trim(),
                'readRoles': readRoles,
                'createRoles': createSel.toList()..sort(),
                'updateRoles': updateSel.toList()..sort(),
                'deleteRoles': deleteSel.toList()..sort(),
                'updatedAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge:true));
              if(context.mounted) Navigator.pop(ctx);
            }catch(e){
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e')));
            }
          }, child: const Text('Save')),
        ],
      );
    });
  }

  Future<void> _confirmDelete(BuildContext context, String docId, String label) async {
    final confirmed = await showDialog<bool>(context: context, builder: (ctx){
      return AlertDialog(
        title: const Text('Delete Permission'),
        content: Text('Are you sure you want to delete "$label" ?'),
        actions: [
          TextButton(onPressed: ()=> Navigator.pop(ctx,false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: ()=> Navigator.pop(ctx,true), child: const Text('Delete')),
        ],
      );
    });
    if(confirmed==true){
      try { await _permissionsColl.doc(docId).delete(); }
      catch(e){ if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e'))); }
    }
  }
}

class _RoleActionMatrix extends StatefulWidget {
  final Set<String> readSel, createSel, updateSel, deleteSel; final VoidCallback onCopyReadToAll;
  const _RoleActionMatrix({required this.readSel, required this.createSel, required this.updateSel, required this.deleteSel, required this.onCopyReadToAll});
  @override State<_RoleActionMatrix> createState() => _RoleActionMatrixState();
}
class _RoleActionMatrixState extends State<_RoleActionMatrix>{
  static const roles = PermissionsScreen.knownRoles;
  bool showActions = true;
  Widget _chip(String label, bool selected, VoidCallback toggle){
    return FilterChip(label: Text(label), selected: selected, onSelected: (_){ setState(toggle); });
  }
  @override
  Widget build(BuildContext context){
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
      Row(children:[
        const Text('Read'), const SizedBox(width:8),
        Expanded(child: Wrap(spacing:8, runSpacing:8, children:[
          for(final r in roles) _chip(r, widget.readSel.contains(r), ()=> widget.readSel.contains(r) ? widget.readSel.remove(r) : widget.readSel.add(r))
        ])),
      ]),
      const SizedBox(height:12),
      Row(children:[
        TextButton.icon(onPressed: widget.onCopyReadToAll, icon: const Icon(Icons.copy_all, size:18), label: const Text('Copy READ to all actions')),
        const Spacer(),
        IconButton(onPressed: ()=> setState(()=> showActions = !showActions), icon: Icon(showActions? Icons.expand_less : Icons.expand_more))
      ]),
      if(showActions) Column(children:[
        const SizedBox(height:4),
        _actionRow('Create', widget.createSel),
        const SizedBox(height:8),
        _actionRow('Update', widget.updateSel),
        const SizedBox(height:8),
        _actionRow('Delete', widget.deleteSel),
      ]),
    ]);
  }
  Widget _actionRow(String label, Set<String> sel){
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children:[
      SizedBox(width:70, child: Text(label)), const SizedBox(width:8),
      Expanded(child: Wrap(spacing:8, runSpacing:8, children:[
        for(final r in roles) FilterChip(label: Text(r), selected: sel.contains(r), onSelected: (_){ setState(()=> sel.contains(r)? sel.remove(r): sel.add(r)); })
      ]))
    ]);
  }
}

class _RoleSummaryChips extends StatelessWidget {
  final List<String> read; final List<String>? create; final List<String>? update; final List<String>? delete;
  const _RoleSummaryChips({required this.read, this.create, this.update, this.delete});
  @override
  Widget build(BuildContext context){
    TextStyle meta = Theme.of(context).textTheme.bodySmall!.copyWith(color: Theme.of(context).colorScheme.primary);
    if(read.isEmpty) return const Text('No roles', style: TextStyle(fontStyle: FontStyle.italic));
    Widget line(String prefix, List<String>? list){
      if(list==null) return const SizedBox();
      return Padding(padding: const EdgeInsets.only(top:2), child: Wrap(spacing:4, runSpacing:4, crossAxisAlignment: WrapCrossAlignment.center, children:[
        Text(prefix, style: meta),
        ...list.map((r)=> Chip(label: Text(r), visualDensity: VisualDensity.compact))
      ]));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
      line('Read:', read),
      if(create!=null && !_same(read, create!)) line('Create:', create),
      if(update!=null && !_same(read, update!)) line('Update:', update),
      if(delete!=null && !_same(read, delete!)) line('Delete:', delete),
    ]);
  }
  bool _same(List<String> a, List<String> b){
    if(a.length!=b.length) return false; for(int i=0;i<a.length;i++){ if(a[i]!=b[i]) return false; } return true;
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback? onCreate; final bool canCreate;
  const _EmptyState({this.onCreate, required this.canCreate});
  @override
  Widget build(BuildContext context){
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children:[
      const Icon(Icons.lock_outline, size:48, color: Colors.grey), const SizedBox(height:12),
      const Text('No permissions defined yet', style: TextStyle(fontSize:16)), const SizedBox(height:8),
      const SizedBox(width:420, child: Text('Define which roles can access each module or feature. These entries are optional – missing modules fallback to role-based defaults.', textAlign: TextAlign.center)),
      const SizedBox(height:16),
      if(canCreate) FilledButton.icon(onPressed: onCreate, icon: const Icon(Icons.add), label: const Text('Add First Permission')),
    ]));
  }
}
