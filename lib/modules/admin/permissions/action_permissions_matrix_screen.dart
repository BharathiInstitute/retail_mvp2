import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../rbac/admin_rbac_providers.dart';
import '../rbac/action_permissions_providers.dart';

/// UI similar to the screenshot: categories (groups) with rows and role columns.
/// Allows toggling role access per action row.
/// Data lives in collection `permissions_actions` (see provider file).

class ActionPermissionsMatrixScreen extends ConsumerWidget {
  const ActionPermissionsMatrixScreen({super.key});
  static const rolesOrder = ['clerk','cashier','accountant','manager','owner']; // ascending by power
  static const roleLabels = {
    'clerk':'Clerk', 'cashier':'Cashier', 'accountant':'Accountant', 'manager':'Manager', 'owner':'Owner'
  };

  bool _canEdit(Capabilities c) => c.manageUsers || c.editSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(capabilitiesProvider);
    final groups = ref.watch(actionPermissionGroupsProvider);
    final isLoading = ref.watch(actionPermissionsProvider).isLoading;
    return Column(children:[
      Row(children:[
        if(_canEdit(caps)) FilledButton.icon(onPressed: ()=> _showAddRowDialog(context), icon: const Icon(Icons.add), label: const Text('Add Action')), const SizedBox(width:12),
        if(_canEdit(caps)) FilledButton.icon(onPressed: ()=> _showAddCategoryDialog(context), icon: const Icon(Icons.view_day_outlined), label: const Text('Add Category')),
        const Spacer(),
        if(isLoading) const Padding(padding: EdgeInsets.only(right:8), child: SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2)))
      ]),
      const SizedBox(height:12),
      Expanded(child: groups.isEmpty && !isLoading
        ? _Empty()
        : ListView.builder(
          itemCount: groups.length,
          itemBuilder: (ctx, i){
            final g = groups[i];
            return _CategoryBlock(group: g, canEdit: _canEdit(caps));
          })
      )
    ]);
  }

  Future<void> _showAddCategoryDialog(BuildContext context) async {
    final nameCtrl = TextEditingController();
    final orderCtrl = TextEditingController(text:'100');
    await showDialog(context: context, builder: (ctx){
      return AlertDialog(
        title: const Text('Add Category'),
        content: SizedBox(width:380, child: Column(mainAxisSize: MainAxisSize.min, children:[
          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText:'Name')), 
          TextField(controller: orderCtrl, decoration: const InputDecoration(labelText:'Order (int)')),
          const SizedBox(height:8), const Text('Categories are implicit; adding one now is optional. First row you add can also create it.')
        ])),
        actions: [
          TextButton(onPressed: ()=> Navigator.pop(ctx), child: const Text('Close')),
        ],
      );
    });
  }

  Future<void> _showAddRowDialog(BuildContext context) async {
    final formKey = GlobalKey<FormState>();
    final actionKeyCtrl = TextEditingController();
    final labelCtrl = TextEditingController();
    final categoryCtrl = TextEditingController();
    final categoryOrderCtrl = TextEditingController(text:'100');
    final orderCtrl = TextEditingController(text:'100');
    final roleChecks = { for(final r in rolesOrder) r:false };
    await showDialog(context: context, builder: (ctx){
      return AlertDialog(
        title: const Text('New Action'),
        content: Form(
          key: formKey,
          child: SizedBox(
            width:480,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children:[
          TextFormField(controller: actionKeyCtrl, decoration: const InputDecoration(labelText:'Action Key', hintText:'e.g. jobs.create'), validator: (v){
            if(v==null||v.trim().isEmpty) return 'Required';
            if(!RegExp(r'^[a-z0-9_.-]+$').hasMatch(v)) return 'Lowercase letters, numbers, . _ - only';
            return null;
          }),
          TextFormField(controller: labelCtrl, decoration: const InputDecoration(labelText:'Label'), validator: (v)=> (v==null||v.trim().isEmpty)?'Required':null),
          TextFormField(controller: categoryCtrl, decoration: const InputDecoration(labelText:'Category (existing or new)')),
          Row(children:[
            Expanded(child: TextFormField(controller: categoryOrderCtrl, decoration: const InputDecoration(labelText:'Category Order'))),
            const SizedBox(width:8),
            Expanded(child: TextFormField(controller: orderCtrl, decoration: const InputDecoration(labelText:'Row Order'))),
          ]),
          const SizedBox(height:12),
          Align(alignment: Alignment.centerLeft, child: Text('Roles', style: Theme.of(context).textTheme.labelLarge)),
          const SizedBox(height:8),
          Wrap(spacing:8, runSpacing:8, children:[
            for(final r in rolesOrder) StatefulBuilder(builder: (c, setState){
              final sel = roleChecks[r]!; return FilterChip(label: Text(ActionPermissionsMatrixScreen.roleLabels[r]??r), selected: sel, onSelected: (_){ setState(()=> roleChecks[r]=!sel); });
            }),
          ])
        ])))),
        actions: [
          TextButton(onPressed: ()=> Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () async {
            if(!formKey.currentState!.validate()) return;
            try {
              final id = actionKeyCtrl.text.trim();
              final doc = FirebaseFirestore.instance.collection('permissions_actions').doc(id);
              final exists = await doc.get();
              if(exists.exists){
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Action key already exists')));
                return;
              }
              await doc.set({
                'actionKey': id,
                'label': labelCtrl.text.trim(),
                'category': categoryCtrl.text.trim().isEmpty? 'General': categoryCtrl.text.trim(),
                'categoryOrder': int.tryParse(categoryOrderCtrl.text.trim()) ?? 1000,
                'order': int.tryParse(orderCtrl.text.trim()) ?? 1000,
                'roles': roleChecks.map((k,v)=> MapEntry(k,v)),
                'createdAt': FieldValue.serverTimestamp(),
                'updatedAt': FieldValue.serverTimestamp(),
              });
              if(context.mounted) Navigator.pop(ctx);
            }catch(e){
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Create failed: $e')));
            }
          }, child: const Text('Create')),
        ],
      );
    });
  }
}

class _CategoryBlock extends ConsumerWidget {
  final ActionPermissionCategoryGroup group; final bool canEdit;
  const _CategoryBlock({required this.group, required this.canEdit});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(margin: const EdgeInsets.only(bottom:16), child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
      Row(children:[ Icon(Icons.folder_outlined, size:18), const SizedBox(width:6), Text(group.category, style: Theme.of(context).textTheme.titleMedium) ]),
      const SizedBox(height:8),
      _HeaderRow(canEdit: canEdit),
      const Divider(height:24),
      for(final row in group.rows) _ActionRow(row: row, canEdit: canEdit),
    ])));
  }
}

class _HeaderRow extends StatelessWidget {
  final bool canEdit; const _HeaderRow({required this.canEdit});
  @override
  Widget build(BuildContext context){
    final cols = ActionPermissionsMatrixScreen.rolesOrder;
    return Row(children:[
      Expanded(flex: 4, child: Text('Actions', style: Theme.of(context).textTheme.labelLarge)),
      for(final r in cols) SizedBox(width:90, child: Text(ActionPermissionsMatrixScreen.roleLabels[r]??r, textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelSmall)),
      if(canEdit) const SizedBox(width:40),
    ]);
  }
}

class _ActionRow extends StatefulWidget {
  final ActionPermissionRow row; final bool canEdit;
  const _ActionRow({required this.row, required this.canEdit});
  @override State<_ActionRow> createState() => _ActionRowState();
}
class _ActionRowState extends State<_ActionRow> {
  bool saving = false;
  Future<void> _toggle(String role) async {
    if(!widget.canEdit || saving) return; setState(()=> saving=true);
    try {
      final current = widget.row.roles[role] == true;
      await FirebaseFirestore.instance.collection('permissions_actions').doc(widget.row.id).set({
        'roles': { role: !current }, 'updatedAt': FieldValue.serverTimestamp()
      }, SetOptions(merge: true));
    } catch(_){ }
    if(mounted) setState(()=> saving=false);
  }
  @override
  Widget build(BuildContext context){
    final cols = ActionPermissionsMatrixScreen.rolesOrder;
    return AnimatedOpacity(duration: const Duration(milliseconds:120), opacity: saving? .5:1, child: Row(crossAxisAlignment: CrossAxisAlignment.start, children:[
      Expanded(flex:4, child: Padding(padding: const EdgeInsets.symmetric(vertical:8), child: Text(widget.row.label))),
      for(final r in cols) SizedBox(width:90, child: Center(child: InkWell(
        onTap: ()=> _toggle(r),
        child: Icon(widget.row.roles[r]==true ? Icons.check_box : Icons.check_box_outline_blank, size:22),
      ))),
      if(widget.canEdit) SizedBox(width:40, child: PopupMenuButton<String>(onSelected: (v){
        switch(v){
          case 'delete': _delete(); break;
        }
      }, itemBuilder: (ctx)=> [ const PopupMenuItem(value:'delete', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Delete'), dense:true, contentPadding: EdgeInsets.zero)) ])),
    ]));
  }
  Future<void> _delete() async {
    try { await FirebaseFirestore.instance.collection('permissions_actions').doc(widget.row.id).delete(); } catch(_){ }
  }
}

class _Empty extends StatelessWidget {
  @override
  Widget build(BuildContext context){
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children:[
      const Icon(Icons.lock_outline, size:48, color: Colors.grey), const SizedBox(height:12),
      const Text('No action permissions defined'),
      const SizedBox(height:8),
      const SizedBox(width:400, child: Text('Use "Add Action" to create the first granular action permission row.', textAlign: TextAlign.center))
    ]));
  }
}
