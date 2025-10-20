// material import already present above
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:retail_mvp2/core/logging.dart';
// Removed unused firebase_auth import.
import 'package:flutter/material.dart';

class AdminUsersPage extends StatelessWidget {
  const AdminUsersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin · Users')),
      body: const Padding(
        padding: EdgeInsets.all(16),
        child: UsersTab(),
      ),
    );
  }
}

class UsersTab extends ConsumerWidget {
  const UsersTab({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
  final usersQuery = FirebaseFirestore.instance.collection('users').orderBy('createdAt', descending: true);
  AppLog.info('admin.users.build', 'Building UsersTab');
  // Query current owner (0 or 1 doc expected)
  final ownerQuery = FirebaseFirestore.instance
    .collection('users')
    .where('role', isEqualTo: 'owner')
    .limit(1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Owner status banner
        StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
          stream: ownerQuery.snapshots().handleError((e,st){ AppLog.error('admin.owner.stream', e, st); }),
          builder: (context, ownerSnap){
            if(ownerSnap.hasError){
              AppLog.error('admin.owner.stream.error', ownerSnap.error!, StackTrace.current);
              return _OwnerBanner(error: ownerSnap.error.toString());
            }
            if(!ownerSnap.hasData){
              return const _OwnerBanner(loading: true);
            }
            final hasOwner = ownerSnap.data!.docs.isNotEmpty;
            final ownerData = hasOwner ? ownerSnap.data!.docs.first.data() : null;
            final ownerId = hasOwner ? ownerSnap.data!.docs.first.id : null;
            AppLog.info('admin.owner.stream.data', 'Owner snapshot', data: {'hasOwner': hasOwner, 'ownerId': ownerId});
            return _OwnerBanner(hasOwner: hasOwner, ownerName: ownerData?['displayName'] ?? ownerData?['email'], ownerId: ownerId);
          },
        ),
        const SizedBox(height: 8),
        Row(children: [
          FilledButton.icon(onPressed: () => _openAddUser(context), icon: const Icon(Icons.person_add_outlined), label: const Text('Add User')),
          const SizedBox(width: 12),
          OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.refresh), label: const Text('Live')),
        ]),
        const SizedBox(height: 16),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
            stream: usersQuery.snapshots().handleError((e,st){ AppLog.error('admin.users.stream', e, st); }),
            builder: (context, snap){
              if (snap.hasError){ AppLog.error('admin.users.stream.error', snap.error!, StackTrace.current); return Center(child: Text('Error: ${snap.error}')); }
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final docs = snap.data!.docs;
              if (docs.isEmpty){ AppLog.info('admin.users.stream.empty', 'Users collection empty'); return const Center(child: Text('No users')); }
              AppLog.info('admin.users.stream.data', 'Users snapshot', data: {'count': docs.length});
              return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (c,i){
                  try {
                    final d = docs[i];
                    final data = d.data();
                    final display = (data['displayName'] ?? data['email'] ?? 'user').toString();
                    final email = (data['email'] ?? '').toString();
                    final role = (data['role'] ?? '').toString();
                    final disabled = data['disabled'] == true;
                    if(disabled){ AppLog.info('admin.users.item.disabled', 'Disabled user', data: {'uid': d.id}); }
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(child: Text(display.isNotEmpty? display.substring(0,1).toUpperCase(): '?')),
                        title: Text(display),
                        subtitle: Text('$email • $role${disabled? ' • disabled':''}'),
                        trailing: _UserActions(userId: d.id, currentValues: data),
                      ),
                    );
                  } catch(e){ AppLog.error('admin.users.item.error', e, StackTrace.current, data: {'index': i});
                    return ListTile(title: const Text('Error rendering user'), subtitle: Text('$e'));
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _OwnerBanner extends StatelessWidget {
  final bool loading; final bool hasOwner; final String? ownerName; final String? ownerId; final String? error;
  const _OwnerBanner({this.loading=false, this.hasOwner=false, this.ownerName, this.ownerId, this.error});
  @override
  Widget build(BuildContext context){
    Widget child;
    if(error!=null){
      child = Text('Owner error: $error', style: const TextStyle(color: Colors.red));
    } else if(loading){
      child = const Text('Checking owner...');
    } else if(!hasOwner){
      child = Row(children:[
        const Icon(Icons.warning_amber,color: Colors.orange),
        const SizedBox(width:8),
        const Expanded(child: Text('No owner configured. You can promote an existing user to Owner.', style: TextStyle(fontWeight: FontWeight.w500))),
        FilledButton(onPressed: () async {
          final messenger = ScaffoldMessenger.of(context);
          final selected = await showDialog<String>(context: context, builder: (_)=> const _SelectUserForOwnerDialog());
          if(selected!=null){
            try {
              final cf = FirebaseFunctions.instanceFor(region: 'us-central1');
              await cf.httpsCallable('setInitialOwner').call({'uid': selected});
              // Force token refresh before proceeding with UI changes
              try { await FirebaseAuth.instance.currentUser?.getIdToken(true); } catch(_){ }
              if(!context.mounted) return;
              messenger.showSnackBar(const SnackBar(content: Text('Owner set')));
            } on FirebaseFunctionsException catch(e){
              if(!context.mounted) return;
              messenger.showSnackBar(SnackBar(content: Text(e.message ?? e.code)));
            } catch(e){
              if(!context.mounted) return;
              messenger.showSnackBar(SnackBar(content: Text('$e')));
            }
          }
        }, child: const Text('Set Owner'))
      ]);
    } else {
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      final isOwner = currentUid != null && currentUid == ownerId;
      child = Row(children:[
        const Icon(Icons.verified_user, color: Colors.green),
        const SizedBox(width:8),
        Expanded(child: Text('Owner: ${ownerName ?? ownerId}', style: const TextStyle(fontWeight: FontWeight.w600))),
        if(isOwner) FilledButton.tonal(onPressed: () async {
          final messenger = ScaffoldMessenger.of(context);
          final target = await showDialog<String>(context: context, builder: (_)=> const _SelectUserForOwnerDialog());
          if(target!=null){
            try {
              try { await FirebaseAuth.instance.currentUser?.getIdToken(true); } catch(_){ }
              final cf = FirebaseFunctions.instanceFor(region: 'us-central1');
              await cf.httpsCallable('transferOwnership').call({'newOwnerUid': target});
              try { await FirebaseAuth.instance.currentUser?.getIdToken(true); } catch(_){ }
              if(!context.mounted) return;
              messenger.showSnackBar(const SnackBar(content: Text('Ownership transferred')));
            } on FirebaseFunctionsException catch(e){
              if(!context.mounted) return;
              final msg = 'Transfer failed: ${e.code} ${e.message ?? ''}'.trim();
              messenger.showSnackBar(SnackBar(content: Text(msg)));
            } catch(e){
              if(!context.mounted) return;
              messenger.showSnackBar(SnackBar(content: Text('$e')));
            }
          }
        }, child: const Text('Transfer'))
      ]);
    }
  return Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)), child: child);
  }
}

class _SelectUserForOwnerDialog extends StatelessWidget {
  const _SelectUserForOwnerDialog();
  @override
  Widget build(BuildContext context){
    final usersCol = FirebaseFirestore.instance.collection('users');
    AppLog.info('admin.owner.select.dialog', 'Open select user dialog');
    return AlertDialog(
      title: const Text('Select User'),
      content: SizedBox(width: 380, height: 360, child: StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
        stream: usersCol.orderBy('createdAt', descending: true).snapshots().handleError((e,st){ AppLog.error('admin.owner.select.stream', e, st); }),
        builder: (context, snap){
          if(snap.hasError){ AppLog.error('admin.owner.select.error', snap.error!, StackTrace.current); return Text('Error: ${snap.error}'); }
            if(!snap.hasData) return const Center(child: CircularProgressIndicator());
            final docs = snap.data!.docs;
            if(docs.isEmpty){ AppLog.info('admin.owner.select.empty', 'No users to display'); return const Text('No users'); }
            AppLog.info('admin.owner.select.data', 'Users loaded', data: {'count': docs.length});
            return ListView.builder(itemCount: docs.length, itemBuilder: (c,i){
              final d = docs[i]; final data = d.data();
              final role = data['role'];
              return ListTile(
                title: Text(data['displayName'] ?? data['email'] ?? d.id),
                subtitle: Text(data['email'] ?? ''),
                trailing: Text(role ?? ''),
                onTap: (){ Navigator.pop(context, d.id); },
              );
            });
        },
      )),
      actions: [TextButton(onPressed: ()=> Navigator.pop(context), child: const Text('Cancel'))],
    );
  }
}

void _openAddUser(BuildContext context){
  showDialog(context: context, builder: (_)=> const _AddUserDialog());
}

class _AddUserDialog extends StatefulWidget {
  const _AddUserDialog();
  @override
  State<_AddUserDialog> createState() => _AddUserDialogState();
}

class _AddUserDialogState extends State<_AddUserDialog> {
  final _form = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _password2Ctrl = TextEditingController();
  final _storesCtrl = TextEditingController();
  String _role = 'cashier';
  bool _saving = false;
  String? _error;
  bool _showPassword = false;

  @override
  void dispose(){
    _emailCtrl.dispose();
    _nameCtrl.dispose();
    _passwordCtrl.dispose();
    _password2Ctrl.dispose();
    _storesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if(!_form.currentState!.validate()) return;
  setState((){ _saving=true; _error=null; });
    final email = _emailCtrl.text.trim().toLowerCase();
    final displayName = _nameCtrl.text.trim().isEmpty ? email.split('@').first : _nameCtrl.text.trim();
    final password = _passwordCtrl.text;
    final stores = _storesCtrl.text.split(',').map((e)=>e.trim()).where((e)=>e.isNotEmpty).toList();
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable('createUserAccount');
      AppLog.info('admin.addUser.submit', 'Submitting new user');
      await callable.call({
        'email': email,
        'password': password,
        'displayName': displayName,
        'role': _role == 'owner' ? 'manager' : _role,
        'stores': stores,
      });
      AppLog.info('admin.addUser.success', 'Cloud Function createUserAccount success');
      if(!mounted) return; Navigator.pop(context);
    } on FirebaseFunctionsException catch(e){
      setState(()=> _error = e.message ?? e.code);
      AppLog.error('admin.addUser.functionError', e, StackTrace.current);
    } catch(e){
      final es = e.toString();
      // If function unavailable, fallback to Firestore profile only
      final unavailable = es.contains('unimplemented') || es.contains('404') || es.contains('NOT_FOUND') || es.contains('unavailable');
      if(unavailable){
        try {
          final id = FirebaseFirestore.instance.collection('_').doc().id;
          await FirebaseFirestore.instance.collection('users').doc(id).set({
            'email': email,
            'displayName': displayName,
            'role': _role,
            'stores': stores,
            'authMissing': true,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          AppLog.info('admin.addUser.fallback', 'Created fallback Firestore user', data: {'uid': id});
          if(mounted) Navigator.pop(context);
        } catch(e2){
          setState(()=> _error = 'Fallback failed: $e2');
          AppLog.error('admin.addUser.fallbackError', e2, StackTrace.current);
        }
      } else {
        setState(()=> _error = es);
        AppLog.error('admin.addUser.otherError', e, StackTrace.current);
      }
    } finally {
      if(mounted) setState(()=> _saving=false);
      AppLog.info('admin.addUser.submit.done', 'Submit finished');
    }
  }

  @override
  Widget build(BuildContext context){
    // Listen for existence of an owner to decide if owner option should be shown
    final ownerStream = FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'owner')
        .limit(1)
        .snapshots();
    return StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
      stream: ownerStream,
      builder: (context, ownerSnap){
        final allowOwner = ownerSnap.hasData && ownerSnap.data!.docs.isEmpty; // only if no owner
        return AlertDialog(
      title: const Text('Add User'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: _emailCtrl,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
                validator: (v){ if(v==null||v.trim().isEmpty) return 'Required'; if(!v.contains('@')) return 'Invalid'; return null; },
              ),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Display Name (optional)'),
              ),
              Row(children:[
                Expanded(child: TextFormField(
                  controller: _passwordCtrl,
                  obscureText: !_showPassword,
                  decoration: InputDecoration(labelText: 'Password', suffixIcon: IconButton(icon: Icon(_showPassword? Icons.visibility_off: Icons.visibility), onPressed: ()=> setState(()=> _showPassword=!_showPassword))),
                  validator: (v){ if(v==null||v.length<6) return 'Min 6 chars'; return null; },
                )),
                const SizedBox(width:12),
                Expanded(child: TextFormField(
                  controller: _password2Ctrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Confirm'),
                  validator: (v){ if(v!=_passwordCtrl.text) return 'Mismatch'; return null; },
                )),
              ]),
              const SizedBox(height:8),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: InputDecoration(labelText: allowOwner? 'Role (Owner allowed once)' : 'Role'),
                items: [
                  if(allowOwner) const DropdownMenuItem(value:'owner', child: Text('Owner')),
                  const DropdownMenuItem(value:'manager', child: Text('Manager')),
                  const DropdownMenuItem(value:'cashier', child: Text('Cashier')),
                  const DropdownMenuItem(value:'clerk', child: Text('Clerk')),
                  const DropdownMenuItem(value:'accountant', child: Text('Accountant')),
                ],
                onChanged: _saving? null: (v){ if(v!=null) setState(()=> _role=v); },
              ),
              TextFormField(
                controller: _storesCtrl,
                decoration: const InputDecoration(labelText: 'Store IDs (comma separated)'),
              ),
              if(_error!=null) Padding(padding: const EdgeInsets.only(top:8), child: Align(alignment: Alignment.centerLeft, child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize:12)))),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving? null: ()=> Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _saving? null: _submit, child: _saving? const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)) : const Text('Create')),
      ],
    );
      }
    );
  }
}

class _UserActions extends StatefulWidget {
  final String userId; final Map<String,dynamic> currentValues;
  const _UserActions({required this.userId, required this.currentValues});
  @override State<_UserActions> createState() => _UserActionsState();
}
class _UserActionsState extends State<_UserActions>{
  bool _busy = false; // removed unused _err
  @override Widget build(BuildContext context){
    final role = (widget.currentValues['role'] ?? '') as String;
    return PopupMenuButton<String>(
          onSelected: (v) async {
            if(v=='edit'){
              // context used synchronously – safe
              _openEditUser(context, widget.userId, widget.currentValues);
            } else if (v=='delete'){
              // Prevent deleting the currently signed-in user
              final currentUid = FirebaseAuth.instance.currentUser?.uid;
              if (currentUid != null && currentUid == widget.userId) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot delete the currently signed-in user')));
                return;
              }
              // Capture messenger before any awaits.
              final messenger = ScaffoldMessenger.of(context);
              // Ensure popup menu route fully closes before opening dialog to avoid overlay glitches.
              await Future<void>.delayed(const Duration(milliseconds: 10));
              if (!context.mounted) return;
              final ok = await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (dialogCtx)=> AlertDialog(
                  title: const Text('Delete User'),
                  content: Text('Delete ${widget.currentValues['email'] ?? widget.userId}? This cannot be undone.'),
                  actions: [
                    TextButton(onPressed: ()=> Navigator.pop(dialogCtx,false), child: const Text('Cancel')),
                    FilledButton(onPressed: ()=> Navigator.pop(dialogCtx,true), child: const Text('Delete')),
                  ],
                ),
              );
              if(ok==true){
                if(!mounted) return;
                setState(()=> _busy=true);
                try {
                  final callable = FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable('deleteUserAccount');
                  await callable.call({'uid': widget.userId});
                } on FirebaseFunctionsException catch(e){
                  if(!mounted) return; // bail out if disposed
                  messenger.showSnackBar(SnackBar(content: Text(e.message ?? e.code)));
                } catch(e){
                  if(!mounted) return;
                  messenger.showSnackBar(SnackBar(content: Text('$e')));
                }
                if(mounted) setState(()=> _busy=false);
              }
            }
          },
          itemBuilder: (c){
            final items = <PopupMenuEntry<String>>[
              const PopupMenuItem(value:'edit', child: Text('Edit')),
            ];
            // If this user is current owner, we disable delete
            final isOwnerUser = role == 'owner';
            final currentUid = FirebaseAuth.instance.currentUser?.uid;
            final isSelf = currentUid != null && currentUid == widget.userId;
            final canDelete = !_busy && !isOwnerUser && !isSelf;
            final label = isOwnerUser
                ? 'Delete (owner)'
                : (isSelf ? 'Delete (self)' : 'Delete');
            items.add(PopupMenuItem(
              value: 'delete',
              enabled: canDelete,
              child: _busy
                  ? const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2))
                  : Text(label),
            ));
            return items;
          },
        );
  }
}

void _openEditUser(BuildContext context, String uid, Map<String,dynamic> current){
  showDialog(context: context, builder: (_)=> _EditUserDialog(uid: uid, current: current));
}

class _EditUserDialog extends StatefulWidget {
  final String uid; final Map<String,dynamic> current;
  const _EditUserDialog({required this.uid, required this.current});
  @override State<_EditUserDialog> createState() => _EditUserDialogState();
}
class _EditUserDialogState extends State<_EditUserDialog>{
  final _form = GlobalKey<FormState>();
  late TextEditingController _nameCtrl; late TextEditingController _storesCtrl; String _role = 'cashier'; bool _saving=false; String? _error; String? _success;
  @override void initState(){
    super.initState();
    _nameCtrl = TextEditingController(text: widget.current['displayName'] ?? '');
    // Robustly extract stores list (could be null, List<dynamic>, or other unexpected type)
    final rawStores = widget.current['stores'];
    List storesList;
    if (rawStores is List) {
      storesList = rawStores;
    } else if (rawStores is String) {
      storesList = rawStores.split(',');
    } else {
      storesList = const [];
    }
    _storesCtrl = TextEditingController(text: storesList.whereType<String>().join(', '));
    _role = (widget.current['role'] ?? 'cashier') as String;
  }
  @override void dispose(){ _nameCtrl.dispose(); _storesCtrl.dispose(); super.dispose(); }
  Future<void> _submit() async {
    if(!_form.currentState!.validate()) return;
  setState(()=> _saving=true); _error=null; _success=null;
    final displayName = _nameCtrl.text.trim();
    final stores = _storesCtrl.text.split(',').map((e)=> e.trim()).where((e)=> e.isNotEmpty).toList();
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable('updateUserAccount');
      await callable.call({'uid': widget.uid, 'displayName': displayName, 'role': _role, 'stores': stores});
      setState(()=> _success = 'Updated');
    } on FirebaseFunctionsException catch(e){
      setState(()=> _error = e.message ?? e.code);
    } catch(e){ setState(()=> _error = '$e'); }
    setState(()=> _saving=false);
  }
  @override Widget build(BuildContext context){
    return AlertDialog(
      title: const Text('Edit User'),
      content: SizedBox(width: 420, child: Form(
        key: _form,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Display Name')),
          const SizedBox(height:8),
          DropdownButtonFormField<String>(initialValue: _role, decoration: const InputDecoration(labelText: 'Role'), items: const [
            DropdownMenuItem(value:'manager', child: Text('Manager')),
            DropdownMenuItem(value:'cashier', child: Text('Cashier')),
            DropdownMenuItem(value:'clerk', child: Text('Clerk')),
            DropdownMenuItem(value:'accountant', child: Text('Accountant')),
          ], onChanged: _saving? null: (v){ if(v!=null) setState(()=> _role=v); }),
          TextFormField(controller: _storesCtrl, decoration: const InputDecoration(labelText: 'Store IDs (comma separated)')),
          if(_error!=null) Padding(padding: const EdgeInsets.only(top:8), child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize:12))),
          if(_success!=null) Padding(padding: const EdgeInsets.only(top:8), child: Text(_success!, style: const TextStyle(color: Colors.green, fontSize:12))),
        ]),
      )),
      actions: [
        TextButton(onPressed: _saving? null: ()=> Navigator.pop(context), child: const Text('Close')),
        FilledButton(onPressed: _saving? null: _submit, child: _saving? const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)) : const Text('Save')),
      ],
    );
  }
}
// DemoUser list removed – live Firestore data is shown instead.
