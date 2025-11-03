// material import already present above
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:retail_mvp2/core/logging.dart';
// Removed unused firebase_auth import.
import 'package:flutter/material.dart';
import 'package:retail_mvp2/core/theme/theme_utils.dart';
import 'package:retail_mvp2/modules/stores/providers.dart';

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
  final selStoreId = ref.watch(selectedStoreIdProvider);
  AppLog.info('admin.users.build', 'Building UsersTab');
  if (selStoreId == null || selStoreId.isEmpty) {
    return Center(
      child: Text(
        'Select a store to manage users',
        style: (context.texts.titleMedium ?? const TextStyle()).copyWith(color: context.colors.onSurface),
      ),
    );
  }
  // Store-scoped owner membership
  final ownerQuery = FirebaseFirestore.instance
    .collection('store_users')
    .where('storeId', isEqualTo: selStoreId)
    .where('status', isEqualTo: 'active')
    .where('role', isEqualTo: 'owner');
  // Store-scoped members
  final membersQuery = FirebaseFirestore.instance
      .collection('store_users')
      .where('storeId', isEqualTo: selStoreId)
      .where('status', isEqualTo: 'active');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Owner status banner (per selected store)
        StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
          stream: ownerQuery.snapshots().handleError((e,st){ AppLog.error('admin.owner.stream', e, st); }),
          builder: (context, ownerSnap){
            if(ownerSnap.hasError){
              AppLog.error('admin.owner.stream.error', ownerSnap.error!, StackTrace.current);
              return _OwnerBanner(storeId: selStoreId, error: ownerSnap.error.toString());
            }
            if(!ownerSnap.hasData){
              return _OwnerBanner(storeId: selStoreId, loading: true);
            }
            final mdocs = ownerSnap.data!.docs;
            if (mdocs.isEmpty) {
              return _OwnerBanner(storeId: selStoreId, hasOwner: false);
            }
            // Prefer current user if they are an owner of this store
            final currentUid = FirebaseAuth.instance.currentUser?.uid;
            QueryDocumentSnapshot<Map<String, dynamic>> chosen = mdocs.first;
            if (currentUid != null) {
              final idx = mdocs.indexWhere((d) => (d.data()['userId'] as String?) == currentUid);
              if (idx != -1) chosen = mdocs[idx];
            }
            final ownerUid = (chosen.data()['userId'] as String?) ?? chosen.id;
            return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              future: FirebaseFirestore.instance.collection('users').doc(ownerUid).get(),
              builder: (context, userSnap) {
                String? name;
                String? email;
                if (userSnap.hasData && userSnap.data!.exists) {
                  final u = userSnap.data!.data() ?? const {};
                  name = (u['displayName'] as String?)?.trim();
                  email = (u['email'] as String?)?.trim();
                }
                return _OwnerBanner(
                  storeId: selStoreId,
                  hasOwner: true,
                  ownerId: ownerUid,
                  ownerName: (name?.isNotEmpty ?? false) ? name : null,
                  ownerEmail: (email?.isNotEmpty ?? false) ? email : null,
                );
              },
            );
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
            stream: membersQuery.snapshots().handleError((e,st){ AppLog.error('admin.users.members.stream', e, st); }),
            builder: (context, snap){
              if (snap.hasError){ AppLog.error('admin.users.members.error', snap.error!, StackTrace.current); return Center(child: Text('Error: ${snap.error}')); }
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final mdocs = snap.data!.docs;
              if (mdocs.isEmpty){ AppLog.info('admin.users.members.empty', 'No users in this store'); return const Center(child: Text('No users in this store')); }
              AppLog.info('admin.users.members.data', 'Members snapshot', data: {'count': mdocs.length});
              return ListView.builder(
                itemCount: mdocs.length,
                itemBuilder: (c,i){
                  try {
                    final m = mdocs[i];
                    final mv = m.data();
                    final uid = (mv['userId'] ?? m.id).toString();
                    final role = (mv['role'] ?? '').toString();
                    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
                      builder: (context, userSnap) {
                        final data = userSnap.data?.data() ?? const <String, dynamic>{};
                        String displayRaw = (data['displayName'] ?? '').toString().trim();
                        String email = (data['email'] ?? '').toString();
                        // Fallback to Firebase Auth profile when this row is the signed-in user
                        final me = FirebaseAuth.instance.currentUser;
                        if ((displayRaw.isEmpty && email.isEmpty) && me != null && me.uid == uid) {
                          email = (me.email ?? '').trim();
                          displayRaw = (me.displayName ?? '').trim();
                        }
                        final display = displayRaw.isNotEmpty ? displayRaw : (email.isNotEmpty ? email.split('@').first : '');
                        final disabled = data['disabled'] == true;
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(child: Text((display.isNotEmpty ? display : uid).substring(0,1).toUpperCase())),
                            title: Text(display.isEmpty ? uid : display, style: (context.texts.titleSmall ?? const TextStyle()).copyWith(color: context.colors.onSurface)),
                            subtitle: Text('${email.isEmpty ? uid : email} • $role${disabled? ' • disabled':''}', style: (context.texts.bodySmall ?? const TextStyle()).copyWith(color: context.colors.onSurfaceVariant)),
                            trailing: _UserActions(userId: uid, currentValues: {...data, 'role': role}),
                          ),
                        );
                      },
                    );
                  } catch(e){ AppLog.error('admin.users.members.item.error', e, StackTrace.current, data: {'index': i});
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
  final String storeId;
  final bool loading; final bool hasOwner; final String? ownerName; final String? ownerEmail; final String? ownerId; final String? error;
  const _OwnerBanner({required this.storeId, this.loading=false, this.hasOwner=false, this.ownerName, this.ownerEmail, this.ownerId, this.error});
  @override
  Widget build(BuildContext context){
    Widget child;
    if(error!=null){
      child = Text('Owner error: $error', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: context.colors.error));
    } else if(loading){
      child = const Text('Checking owner...');
    } else if(!hasOwner){
      child = Row(children:[
        Icon(Icons.warning_amber, color: context.appColors.warning),
        const SizedBox(width:8),
  Expanded(child: Text('No owner configured. You can promote an existing user to Owner.', style: context.texts.bodyMedium?.copyWith(fontWeight: FontWeight.w500, color: context.colors.onSurface))),
        FilledButton(onPressed: () async {
          final messenger = ScaffoldMessenger.of(context);
          final selected = await showDialog<String>(context: context, builder: (_)=> _SelectUserForOwnerDialog(storeId: storeId));
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
      final selfEmail = isOwner ? (FirebaseAuth.instance.currentUser?.email?.trim() ?? '') : '';
      final selfName = isOwner
          ? ((FirebaseAuth.instance.currentUser?.displayName?.trim().isNotEmpty ?? false)
              ? FirebaseAuth.instance.currentUser!.displayName!.trim()
              : (selfEmail.isNotEmpty ? selfEmail.split('@').first : ''))
          : '';
      // Compose a friendly label: prefer Name (email) using owner doc; if missing and current user is owner, fall back to auth name/email; else uid
      final String label = (){
        final emailPref = (ownerEmail?.trim().isNotEmpty ?? false)
            ? ownerEmail!.trim()
            : (selfEmail.isNotEmpty ? selfEmail : null);
        final namePref = (ownerName?.trim().isNotEmpty ?? false) ? ownerName!.trim() : (selfName.isNotEmpty ? selfName : null);
        if (namePref != null && emailPref != null) return '$namePref  ($emailPref)';
        if (namePref != null) return namePref;
        if (emailPref != null) return emailPref;
        return ownerId ?? '';
      }();
      child = Row(children:[
        Icon(Icons.verified_user, color: context.appColors.success),
        const SizedBox(width:8),
        Expanded(child: Text('Owner: $label', style: context.texts.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: context.colors.onSurface))),
        if(isOwner) FilledButton.tonal(onPressed: () async {
          final messenger = ScaffoldMessenger.of(context);
          final target = await showDialog<String>(context: context, builder: (_)=> _SelectUserForOwnerDialog(storeId: storeId));
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
    return Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: context.colors.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)), child: child);
  }
}

class _SelectUserForOwnerDialog extends StatelessWidget {
  final String? storeId;
  const _SelectUserForOwnerDialog({this.storeId});
  @override
  Widget build(BuildContext context){
    AppLog.info('admin.owner.select.dialog', 'Open select user dialog');
    return AlertDialog(
      title: Text('Select User', style: context.texts.titleMedium?.copyWith(color: context.colors.onSurface, fontWeight: FontWeight.w700)),
      content: DefaultTextStyle(
        style: (context.texts.bodyMedium ?? const TextStyle()).copyWith(color: context.colors.onSurface),
        child: SizedBox(width: 380, height: 360, child: Builder(builder: (context){
          // If storeId is provided, show only members of that store; otherwise show all users
          if (storeId != null && storeId!.isNotEmpty) {
            final membersQ = FirebaseFirestore.instance
                .collection('store_users')
                .where('storeId', isEqualTo: storeId)
                .where('status', isEqualTo: 'active');
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: membersQ.snapshots().handleError((e, st) { AppLog.error('admin.owner.select.members.stream', e, st); }),
              builder: (context, mSnap) {
                if (mSnap.hasError) { AppLog.error('admin.owner.select.members.error', mSnap.error!, StackTrace.current); return Text('Error: ${mSnap.error}'); }
                if (!mSnap.hasData) return const Center(child: CircularProgressIndicator());
                final mems = mSnap.data!.docs;
                if (mems.isEmpty) return const Text('No users in this store');
                return ListView.builder(
                  itemCount: mems.length,
                  itemBuilder: (c, i) {
                    final mv = mems[i].data();
                    final uid = (mv['userId'] ?? mems[i].id).toString();
                    final role = (mv['role'] ?? '').toString();
                    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
                      builder: (context, uSnap) {
                        final u = uSnap.data?.data() ?? const <String, dynamic>{};
                        final display = (u['displayName'] ?? u['email'] ?? uid).toString();
                        final email = (u['email'] ?? '').toString();
                        return ListTile(
                          title: Text(display),
                          subtitle: Text(email),
                          trailing: Text(role),
                          onTap: () => Navigator.pop(context, uid),
                        );
                      },
                    );
                  },
                );
              },
            );
          } else {
            final usersCol = FirebaseFirestore.instance.collection('users');
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: usersCol.orderBy('createdAt', descending: true).snapshots().handleError((e, st) { AppLog.error('admin.owner.select.stream', e, st); }),
              builder: (context, snap) {
                if (snap.hasError) { AppLog.error('admin.owner.select.error', snap.error!, StackTrace.current); return Text('Error: ${snap.error}'); }
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final docs = snap.data!.docs;
                if (docs.isEmpty) { AppLog.info('admin.owner.select.empty', 'No users to display'); return const Text('No users'); }
                AppLog.info('admin.owner.select.data', 'Users loaded', data: {'count': docs.length});
                return ListView.builder(itemCount: docs.length, itemBuilder: (c, i) {
                  final d = docs[i];
                  final data = d.data();
                  final role = data['role'];
                  return ListTile(
                    title: Text(data['displayName'] ?? data['email'] ?? d.id),
                    subtitle: Text(data['email'] ?? ''),
                    trailing: Text(role ?? ''),
                    onTap: () { Navigator.pop(context, d.id); },
                  );
                });
              },
            );
          }
        })),
      ),
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
      title: Text('Add User', style: context.texts.titleMedium?.copyWith(color: context.colors.onSurface, fontWeight: FontWeight.w700)),
      content: DefaultTextStyle(
        style: (context.texts.bodyMedium ?? const TextStyle()).copyWith(color: context.colors.onSurface),
        child: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: _emailCtrl,
                style: (context.texts.bodyMedium ?? const TextStyle()).copyWith(color: context.colors.onSurface),
                decoration: InputDecoration(
                  labelText: 'Email',
                  labelStyle: (context.texts.bodySmall ?? const TextStyle()).copyWith(color: context.colors.onSurfaceVariant),
                  hintStyle: (context.texts.bodySmall ?? const TextStyle()).copyWith(color: context.colors.onSurfaceVariant),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (v){ if(v==null||v.trim().isEmpty) return 'Required'; if(!v.contains('@')) return 'Invalid'; return null; },
              ),
              TextFormField(
                controller: _nameCtrl,
                style: (context.texts.bodyMedium ?? const TextStyle()).copyWith(color: context.colors.onSurface),
                decoration: InputDecoration(
                  labelText: 'Display Name (optional)',
                  labelStyle: (context.texts.bodySmall ?? const TextStyle()).copyWith(color: context.colors.onSurfaceVariant),
                  hintStyle: (context.texts.bodySmall ?? const TextStyle()).copyWith(color: context.colors.onSurfaceVariant),
                ),
              ),
              Row(children:[
                Expanded(child: TextFormField(
                  controller: _passwordCtrl,
                  obscureText: !_showPassword,
                  style: (context.texts.bodyMedium ?? const TextStyle()).copyWith(color: context.colors.onSurface),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    labelStyle: (context.texts.bodySmall ?? const TextStyle()).copyWith(color: context.colors.onSurfaceVariant),
                    hintStyle: (context.texts.bodySmall ?? const TextStyle()).copyWith(color: context.colors.onSurfaceVariant),
                    suffixIcon: IconButton(icon: Icon(_showPassword? Icons.visibility_off: Icons.visibility, color: context.colors.onSurfaceVariant), onPressed: ()=> setState(()=> _showPassword=!_showPassword)),
                  ),
                  validator: (v){ if(v==null||v.length<6) return 'Min 6 chars'; return null; },
                )),
                const SizedBox(width:12),
                Expanded(child: TextFormField(
                  controller: _password2Ctrl,
                  obscureText: true,
                  style: (context.texts.bodyMedium ?? const TextStyle()).copyWith(color: context.colors.onSurface),
                  decoration: InputDecoration(
                    labelText: 'Confirm',
                    labelStyle: (context.texts.bodySmall ?? const TextStyle()).copyWith(color: context.colors.onSurfaceVariant),
                    hintStyle: (context.texts.bodySmall ?? const TextStyle()).copyWith(color: context.colors.onSurfaceVariant),
                  ),
                  validator: (v){ if(v!=_passwordCtrl.text) return 'Mismatch'; return null; },
                )),
              ]),
              const SizedBox(height:8),
              DropdownButtonFormField<String>(
                // initialValue removed (unsupported)
                style: (context.texts.bodyMedium ?? const TextStyle()).copyWith(color: context.colors.onSurface),
                dropdownColor: context.colors.surface,
                iconEnabledColor: context.colors.onSurfaceVariant,
                decoration: InputDecoration(
                  labelText: allowOwner? 'Role (Owner allowed once)' : 'Role',
                  labelStyle: (context.texts.bodySmall ?? const TextStyle()).copyWith(color: context.colors.onSurfaceVariant),
                ),
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
                style: (context.texts.bodyMedium ?? const TextStyle()).copyWith(color: context.colors.onSurface),
                decoration: InputDecoration(
                  labelText: 'Store IDs (comma separated)',
                  labelStyle: (context.texts.bodySmall ?? const TextStyle()).copyWith(color: context.colors.onSurfaceVariant),
                  hintStyle: (context.texts.bodySmall ?? const TextStyle()).copyWith(color: context.colors.onSurfaceVariant),
                ),
              ),
              if(_error!=null)
                Padding(
                  padding: const EdgeInsets.only(top:8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _error!,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                ),
            ]),
          ),
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
                  title: Text('Delete User', style: context.texts.titleMedium?.copyWith(color: context.colors.onSurface, fontWeight: FontWeight.w700)),
                  content: DefaultTextStyle(
                    style: (context.texts.bodyMedium ?? const TextStyle()).copyWith(color: context.colors.onSurface),
                    child: Text('Delete ${widget.currentValues['email'] ?? widget.userId}? This cannot be undone.'),
                  ),
                  actions: [
                    TextButton(onPressed: ()=> Navigator.pop(dialogCtx,false), child: const Text('Cancel')),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: context.colors.error, foregroundColor: context.colors.onError),
                      onPressed: ()=> Navigator.pop(dialogCtx,true),
                      child: const Text('Delete'),
                    ),
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

  // If the current role is something like 'previous_owner', keep it as a selectable item
  // so DropdownButtonFormField does not assert. We still allow changing it to a supported role.
  static const List<String> _allowedRoles = ['manager','cashier','clerk','accountant'];
  // Removed unused function _normalizeRoleValue
  List<DropdownMenuItem<String>> _buildRoleItems(String current){
    final items = <DropdownMenuItem<String>>[];
    if(!_allowedRoles.contains(current)){
      final label = current.replaceAll('_', ' ').split(' ').map((w)=> w.isEmpty? w : (w[0].toUpperCase()+w.substring(1))).join(' ');
      items.add(DropdownMenuItem(value: current, child: Text(label)));
    }
    items.addAll(const [
      DropdownMenuItem(value:'manager', child: Text('Manager')),
      DropdownMenuItem(value:'cashier', child: Text('Cashier')),
      DropdownMenuItem(value:'clerk', child: Text('Clerk')),
      DropdownMenuItem(value:'accountant', child: Text('Accountant')),
    ]);
    return items;
  }
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
      title: Text('Edit User', style: context.texts.titleMedium?.copyWith(color: context.colors.onSurface, fontWeight: FontWeight.w700)),
      content: DefaultTextStyle(
        style: (context.texts.bodyMedium ?? const TextStyle()).copyWith(color: context.colors.onSurface),
        child: SizedBox(width: 420, child: Form(
        key: _form,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(
            controller: _nameCtrl,
            style: (context.texts.bodyMedium ?? const TextStyle()).copyWith(color: context.colors.onSurface),
            decoration: InputDecoration(
              labelText: 'Display Name',
              labelStyle: (context.texts.bodySmall ?? const TextStyle()).copyWith(color: context.colors.onSurfaceVariant),
              hintStyle: (context.texts.bodySmall ?? const TextStyle()).copyWith(color: context.colors.onSurfaceVariant),
            ),
          ),
          const SizedBox(height:8),
          DropdownButtonFormField<String>(
            // initialValue removed (unsupported)
            style: (context.texts.bodyMedium ?? const TextStyle()).copyWith(color: context.colors.onSurface),
            dropdownColor: context.colors.surface,
            iconEnabledColor: context.colors.onSurfaceVariant,
            decoration: InputDecoration(
              labelText: 'Role',
              labelStyle: (context.texts.bodySmall ?? const TextStyle()).copyWith(color: context.colors.onSurfaceVariant),
            ),
            items: _buildRoleItems(_role),
            onChanged: _saving ? null : (v){ if(v!=null) setState(()=> _role=v); },
          ),
          TextFormField(
            controller: _storesCtrl,
            style: (context.texts.bodyMedium ?? const TextStyle()).copyWith(color: context.colors.onSurface),
            decoration: InputDecoration(
              labelText: 'Store IDs (comma separated)',
              labelStyle: (context.texts.bodySmall ?? const TextStyle()).copyWith(color: context.colors.onSurfaceVariant),
              hintStyle: (context.texts.bodySmall ?? const TextStyle()).copyWith(color: context.colors.onSurfaceVariant),
            ),
          ),
          if(_error!=null)
            Padding(
              padding: const EdgeInsets.only(top:8),
              child: Text(
                _error!,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if(_success!=null)
            Padding(
              padding: const EdgeInsets.only(top:8),
              child: Text(
                _success!,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.primary),
              ),
            ),
        ]),
      )),
      ),
      actions: [
        TextButton(onPressed: _saving? null: ()=> Navigator.pop(context), child: const Text('Close')),
        FilledButton(onPressed: _saving? null: _submit, child: _saving? const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)) : const Text('Save')),
      ],
    );
  }
}
// DemoUser list removed – live Firestore data is shown instead.
