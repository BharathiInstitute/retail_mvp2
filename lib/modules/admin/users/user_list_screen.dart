import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../rbac/admin_rbac_providers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/user_admin_service.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

final userCollectionQueryProvider = StreamProvider.autoDispose((ref){
  return FirebaseFirestore.instance.collection('users').orderBy('displayName').snapshots();
});

class UserListScreen extends ConsumerWidget {
  const UserListScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(capabilitiesProvider);
    final usersSnap = ref.watch(userCollectionQueryProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children:[
          const Text('Users', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(width: 12),
          if (caps.manageUsers) FilledButton.icon(onPressed: ()=> _openCreate(context), icon: const Icon(Icons.person_add), label: const Text('Invite / Add')),
        ]),
        const SizedBox(height: 12),
        Expanded(child: usersSnap.when(
          data: (snap){
            final docs = snap.docs;
            if (docs.isEmpty) {
              // Show manual bootstrap option if capability missing
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('No users yet', style: TextStyle(fontSize:16)),
                    const SizedBox(height:12),
                    if (!caps.manageUsers) FilledButton.icon(
                      icon: const Icon(Icons.rocket_launch_outlined),
                      label: const Text('Bootstrap Owner'),
                      onPressed: () async {
                        final fb = FirebaseAuth.instance.currentUser;
                        if (fb == null) return;
                        try {
                          await FirebaseFirestore.instance.collection('users').doc(fb.uid).set({
                            'email': fb.email,
                            'displayName': fb.displayName ?? (fb.email?.split('@').first ?? 'Owner'),
                            'role': 'owner',
                            'stores': <String>[],
                            'createdAt': FieldValue.serverTimestamp(),
                            'updatedAt': FieldValue.serverTimestamp(),
                          }, SetOptions(merge: true));
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Bootstrap failed: $e')));
                          }
                        }
                      },
                    ) else const Text('Use the Invite / Add button to create users.'),
                  ],
                ),
              );
            }
            return SingleChildScrollView(
              child: DataTable(columns: const [
                DataColumn(label: Text('Name')),
                DataColumn(label: Text('Email')),
                DataColumn(label: Text('Role')),
                DataColumn(label: Text('Stores')),
                DataColumn(label: Text('Actions')),
              ], rows: [
                for (final d in docs) _row(context, ref, d.id, d.data())
              ]),
            );
          },
          loading: ()=> const Center(child: CircularProgressIndicator()),
          error: (e,_)=> Center(child: Text('Error: $e')),
        )),
      ],
    );
  }

  DataRow _row(BuildContext context, WidgetRef ref, String uid, Map<String,dynamic> data){
    final caps = ref.read(capabilitiesProvider);
    final stores = (data['stores'] as List?)?.join(', ') ?? '';
    final role = data['role'] ?? '-';
    return DataRow(cells: [
      DataCell(Text(data['displayName'] ?? '—')),
      DataCell(Text(data['email'] ?? '—')),
      DataCell(_RoleCell(uid: uid, role: role, enabled: caps.manageUsers)),
      DataCell(Text(stores)),
      DataCell(Row(children:[
        if (caps.manageUsers) IconButton(onPressed: ()=> _editStores(context, uid, data), icon: const Icon(Icons.store_outlined, size:18)),
        if (caps.manageUsers) IconButton(onPressed: ()=> _confirmDelete(context, uid), icon: const Icon(Icons.delete_outline, size:18)),
      ])),
    ]);
  }

  void _openCreate(BuildContext context){
    showDialog(context: context, builder: (_)=> const _CreateUserDialog());
  }
  void _editStores(BuildContext context, String uid, Map<String,dynamic> data){
    showDialog(context: context, builder: (_)=> _EditStoresDialog(uid: uid, stores: List<String>.from((data['stores'] as List?)?.whereType<String>() ?? const <String>[])));
  }
  void _confirmDelete(BuildContext context, String uid){
    showDialog(context: context, builder: (_)=> AlertDialog(
      title: const Text('Delete User'),
      content: const Text('This only deletes the Firestore user document. Auth deletion requires admin function.'),
      actions: [
        TextButton(onPressed: ()=> Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () async { await UserAdminService.instance.deleteUserDoc(uid); if(context.mounted) Navigator.pop(context); }, child: const Text('Delete')),
      ],
    ));
  }
}

class _RoleCell extends StatefulWidget {
  final String uid; final String role; final bool enabled;
  const _RoleCell({required this.uid, required this.role, required this.enabled});
  @override State<_RoleCell> createState()=> _RoleCellState();
}
class _RoleCellState extends State<_RoleCell>{
  late String value;
  static const roles=['owner','manager','cashier','clerk','accountant'];
  @override void initState(){ super.initState(); value=widget.role; }
  @override Widget build(BuildContext context){
    return DropdownButton<String>(value: value.isEmpty? 'cashier': value, onChanged: widget.enabled? (v) async { if(v!=null){ setState(()=> value=v); await UserAdminService.instance.updateUserRole(uid: widget.uid, role: v); } }: null, items: [
      for (final r in roles) DropdownMenuItem(value: r, child: Text(r))
    ]);
  }
}

class _CreateUserDialog extends StatefulWidget { const _CreateUserDialog(); @override State<_CreateUserDialog> createState()=> _CreateUserDialogState(); }
class _CreateUserDialogState extends State<_CreateUserDialog>{
  final _form = GlobalKey<FormState>();
  String email=''; String name=''; String role='cashier'; String storesRaw='';
  String password=''; String password2='';
  bool saving=false; String? error; bool showPassword=false;
  @override Widget build(BuildContext context){
    return AlertDialog(
      title: const Text('Add / Invite User'),
      content: SizedBox(width: 420, child: Form(key:_form, child: Column(mainAxisSize: MainAxisSize.min, children:[
        TextFormField(decoration: const InputDecoration(labelText: 'Email'), keyboardType: TextInputType.emailAddress, validator: (v)=> (v==null||v.isEmpty)?'Required':null, onChanged:(v)=>email=v),
        TextFormField(decoration: const InputDecoration(labelText: 'Display Name'), onChanged:(v)=>name=v),
        Row(children:[
          Expanded(child: TextFormField(
            decoration: InputDecoration(labelText: 'Password', suffixIcon: IconButton(icon: Icon(showPassword? Icons.visibility_off: Icons.visibility), onPressed: ()=> setState(()=> showPassword=!showPassword))),
            obscureText: !showPassword,
            validator: (v)=> (v==null||v.length<6)?'Min 6 chars':null,
            onChanged:(v)=>password=v)),
          const SizedBox(width:12),
          Expanded(child: TextFormField(
            decoration: const InputDecoration(labelText: 'Confirm'),
            obscureText: true,
            validator: (v)=> v!=password? 'Mismatch': null,
            onChanged:(v)=>password2=v)),
        ]),
        DropdownButtonFormField(value: role, decoration: const InputDecoration(labelText: 'Role'), items: const [
          DropdownMenuItem(value:'owner', child: Text('Owner')),
          DropdownMenuItem(value:'manager', child: Text('Manager')),
          DropdownMenuItem(value:'cashier', child: Text('Cashier')),
          DropdownMenuItem(value:'clerk', child: Text('Clerk')),
          DropdownMenuItem(value:'accountant', child: Text('Accountant')),
        ], onChanged:(v){ if(v!=null) setState(()=> role=v); }),
        TextFormField(decoration: const InputDecoration(labelText: 'Store IDs (comma separated)'), onChanged:(v)=>storesRaw=v),
        if(error!=null) Padding(padding: const EdgeInsets.only(top:8), child: Text(error!, style: const TextStyle(color: Colors.red))),
      ]))),
      actions: [
        TextButton(onPressed: saving? null: ()=> Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: saving? null: () async {
          if(!_form.currentState!.validate()) return; setState(()=> saving=true); error=null;
          try {
            final stores = storesRaw.split(',').map((e)=> e.trim()).where((e)=> e.isNotEmpty).toList();
            final displayName = name.isEmpty? email.split('@').first : name;
            final cf = FirebaseFunctions.instanceFor(region: 'us-central1');
            try {
              final callable = cf.httpsCallable('createUserAccount');
              final resp = await callable.call({
                'email': email,
                'password': password,
                'displayName': displayName,
                'role': role,
                'stores': stores,
              });
              // On success we rely on function's Firestore creation (no local duplicate write)
              final uid = (resp.data is Map)? (resp.data['uid'] as String?) : null;
              if(uid == null){
                // Extremely unlikely: fall back to ensuring profile just in case
                await UserAdminService.instance.createUserDoc(
                  uid: FirebaseFirestore.instance.collection('_').doc().id,
                  email: email,
                  displayName: displayName,
                  role: role,
                  storeIds: stores,
                );
              }
              if(!mounted) return; Navigator.pop(context);
            } catch (e) {
              final es = e.toString();
              // Only allow a safe fallback for unimplemented/unavailable scenarios
              final isUnavailable = es.contains('unimplemented') || es.contains('404') || es.contains('NOT_FOUND') || es.contains('unavailable');
              final isPermission = es.contains('permission-denied') || es.contains('PERMISSION_DENIED');
              final isAuth = es.contains('unauthenticated');
              // Extract firebase functions error structure if available
              String? friendly;
              if (e is FirebaseFunctionsException) {
                final code = e.code;
                switch(code){
                  case 'already-exists': friendly = 'Email already in use'; break;
                  case 'invalid-argument': friendly = e.message ?? 'Invalid input'; break;
                  case 'permission-denied': friendly = 'Insufficient privileges'; break;
                  case 'unauthenticated': friendly = 'Please sign in again'; break;
                  case 'failed-precondition': friendly = e.message ?? 'Auth provider not enabled'; break;
                  default:
                    if (code == 'internal') friendly = e.message ?? 'Internal error';
                }
                if (friendly == null || friendly == 'Internal error') {
                  // Append raw code for diagnostics
                  friendly = '${friendly ?? 'Error'} (code: $code)';
                }
              }
              final isInternal = e is FirebaseFunctionsException && e.code == 'internal';
              if (isUnavailable || isInternal) {
                // Function missing: create Firestore profile (no Auth user!)
                await UserAdminService.instance.createUserDoc(
                  uid: FirebaseFirestore.instance.collection('_').doc().id,
                  email: email,
                  displayName: displayName,
                  role: role,
                  storeIds: stores,
                );
                if(!mounted) return; 
                if (isInternal) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Warning: Auth user not created (internal error); only profile doc saved.')));
                }
                Navigator.pop(context);
              } else if (isPermission || isAuth) {
                setState(()=> error = friendly ?? 'Not allowed to create users (permission)');
              } else {
                setState(()=> error = 'Create failed: ${friendly ?? e}');
              }
            }
          } catch(e){ setState(()=> error = '$e'); }
          finally { if(mounted) setState(()=> saving=false); }
        }, child: saving? const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)) : const Text('Create')),
      ],
    );
  }
}

class _EditStoresDialog extends StatefulWidget { final String uid; final List<String> stores; const _EditStoresDialog({required this.uid, required this.stores}); @override State<_EditStoresDialog> createState()=> _EditStoresDialogState(); }
class _EditStoresDialogState extends State<_EditStoresDialog>{
  late List<String> list;
  @override void initState(){ super.initState(); list=[...widget.stores]; }
  @override Widget build(BuildContext context){
    final ctrl = TextEditingController();
    return AlertDialog(
      title: const Text('Edit Stores'),
      content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children:[
        Wrap(spacing:6, runSpacing:6, children:[
          for(final s in list) InputChip(label: Text(s), onDeleted: () async { setState(()=> list.remove(s)); await UserAdminService.instance.removeStoreFromUser(uid: widget.uid, storeId: s); }),
        ]),
        const SizedBox(height:12),
        Row(children:[
          Expanded(child: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Store ID'))),
          const SizedBox(width:8),
          FilledButton(onPressed: () async { final v = ctrl.text.trim(); if(v.isEmpty) return; setState(()=> list.add(v)); ctrl.clear(); await UserAdminService.instance.addStoreToUser(uid: widget.uid, storeId: v); }, child: const Text('Add')),
        ])
      ])),
      actions: [TextButton(onPressed: ()=> Navigator.pop(context), child: const Text('Close'))],
    );
  }
}
