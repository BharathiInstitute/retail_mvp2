import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:retail_mvp2/core/debug_logger_helper.dart';
import 'package:flutter/material.dart';
import 'package:retail_mvp2/core/theme/theme_extension_helpers.dart';
import 'package:retail_mvp2/modules/stores/providers.dart';

class AdminUsersPage extends StatelessWidget {
  const AdminUsersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [const Color(0xFF1a1a2e), const Color(0xFF16213e), const Color(0xFF0f3460)]
                : [const Color(0xFFf8fafc), const Color(0xFFe2e8f0), const Color(0xFFcbd5e1)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: context.padXl,
            child: const UsersTab(),
          ),
        ),
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
      child: _ModernCard(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.store_outlined, size: 64, color: context.colors.primary.withOpacity(0.5)),
              context.gapVLg,
              Text(
                'Select a store to manage users',
                style: (context.texts.titleMedium ?? const TextStyle()).copyWith(color: context.colors.onSurface),
              ),
            ],
          ),
        ),
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
        // Page header
        Row(
          children: [
            Container(
              padding: context.padMd,
              decoration: BoxDecoration(
                color: context.colors.primary.withOpacity(0.1),
                borderRadius: context.radiusMd,
              ),
              child: Icon(Icons.people_alt_outlined, color: context.colors.primary, size: 28),
            ),
            context.gapHLg,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('User Management', style: context.texts.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: context.colors.onSurface)),
                  context.gapVXs,
                  Text('Manage team members and their roles', style: context.texts.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
        context.gapVXl,
        // Owner status banner + user list wrapped in Expanded
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
            stream: ownerQuery.snapshots().handleError((e,st){ AppLog.error('admin.owner.stream', e, st); }),
            builder: (context, ownerSnap){
              // Determine the actual owner UID (only ONE owner should be recognized)
              String? actualOwnerUid;
              if (ownerSnap.hasData && ownerSnap.data!.docs.isNotEmpty) {
                final mdocs = ownerSnap.data!.docs;
                // Prefer current user if they are an owner, otherwise take the first one
                final currentUid = FirebaseAuth.instance.currentUser?.uid;
                QueryDocumentSnapshot<Map<String, dynamic>> chosen = mdocs.first;
                if (currentUid != null) {
                  final idx = mdocs.indexWhere((d) => (d.data()['userId'] as String?) == currentUid);
                  if (idx != -1) chosen = mdocs[idx];
                }
                actualOwnerUid = (chosen.data()['userId'] as String?) ?? chosen.id;
              }
              
              if(ownerSnap.hasError){
                AppLog.error('admin.owner.stream.error', ownerSnap.error!, StackTrace.current);
                return _buildContent(context, selStoreId, membersQuery, null, error: ownerSnap.error.toString());
              }
              if(!ownerSnap.hasData){
                return _buildContent(context, selStoreId, membersQuery, null, loading: true);
              }
              final mdocs = ownerSnap.data!.docs;
              if (mdocs.isEmpty) {
                return _buildContent(context, selStoreId, membersQuery, null, hasOwner: false);
              }
              
              return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                future: FirebaseFirestore.instance.collection('users').doc(actualOwnerUid).get(),
                builder: (context, userSnap) {
                  String? name;
                  String? email;
                  if (userSnap.hasData && userSnap.data!.exists) {
                    final u = userSnap.data!.data() ?? const {};
                    name = (u['displayName'] as String?)?.trim();
                    email = (u['email'] as String?)?.trim();
                  }
                  return _buildContent(
                    context, 
                    selStoreId, 
                    membersQuery, 
                    actualOwnerUid,
                    hasOwner: true,
                    ownerName: (name?.isNotEmpty ?? false) ? name : null,
                    ownerEmail: (email?.isNotEmpty ?? false) ? email : null,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
  
  Widget _buildContent(
    BuildContext context, 
    String storeId, 
    Query<Map<String, dynamic>> membersQuery, 
    String? actualOwnerUid, {
    bool loading = false,
    bool hasOwner = true,
    String? ownerName,
    String? ownerEmail,
    String? error,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _OwnerBanner(
          storeId: storeId,
          loading: loading,
          hasOwner: hasOwner,
          ownerId: actualOwnerUid,
          ownerName: ownerName,
          ownerEmail: ownerEmail,
          error: error,
        ),
        context.gapVLg,
        _buildActionButtons(context),
        const SizedBox(height: 20),
        Expanded(child: _buildUsersList(context, membersQuery, actualOwnerUid)),
      ],
    );
  }
  
  Widget _buildActionButtons(BuildContext context) {
    return Row(children: [
      _ModernButton(
        onPressed: () => _openAddUser(context),
        icon: Icons.person_add_outlined,
        label: 'Add User',
        isPrimary: true,
      ),
      context.gapHMd,
      _ModernButton(
        onPressed: () {},
        icon: Icons.refresh,
        label: 'Refresh',
        isPrimary: false,
      ),
    ]);
  }
  
  Widget _buildUsersList(BuildContext context, Query<Map<String, dynamic>> membersQuery, String? actualOwnerUid) {
    return _ModernCard(
      child: StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
        stream: membersQuery.snapshots().handleError((e,st){ AppLog.error('admin.users.members.stream', e, st); }),
        builder: (context, snap){
          if (snap.hasError){ AppLog.error('admin.users.members.error', snap.error!, StackTrace.current); return Center(child: Text('Error: ${snap.error}')); }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final mdocs = snap.data!.docs;
          if (mdocs.isEmpty){ AppLog.info('admin.users.members.empty', 'No users in this store'); return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person_off_outlined, size: 48, color: context.colors.onSurfaceVariant.withOpacity(0.5)),
                context.gapVMd,
                Text('No users in this store', style: context.texts.bodyLarge?.copyWith(color: context.colors.onSurfaceVariant)),
              ],
            ),
          ); }
          AppLog.info('admin.users.members.data', 'Members snapshot', data: {'count': mdocs.length});
          return ListView.separated(
            padding: context.padLg,
            itemCount: mdocs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (c,i){
              try {
                final m = mdocs[i];
                final mv = m.data();
                final uid = (mv['userId'] ?? m.id).toString();
                // Only show "owner" role if this is THE actual owner
                final storedRole = (mv['role'] ?? '').toString();
                final role = (uid == actualOwnerUid) ? 'owner' : (storedRole == 'owner' ? 'manager' : storedRole);
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
                    return _UserListTile(
                      uid: uid,
                      display: display,
                      email: email,
                      role: role,
                      disabled: disabled,
                      currentValues: {...data, 'role': role},
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MODERN UI HELPER WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _ModernCard extends StatelessWidget {
  final Widget child;
  const _ModernCard({required this.child});
  
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: context.radiusLg,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.7),
            borderRadius: context.radiusLg,
            border: Border.all(
              color: isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.8),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _ModernButton extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  final bool isPrimary;
  const _ModernButton({required this.onPressed, required this.icon, required this.label, this.isPrimary = false});
  
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sizes = context.sizes;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    if (isPrimary) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [cs.primary, cs.primary.withOpacity(0.8)],
          ),
          borderRadius: context.radiusMd,
          boxShadow: [
            BoxShadow(
              color: cs.primary.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: context.radiusMd,
            onTap: onPressed,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: sizes.gapLg, vertical: sizes.gapMd),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: cs.onPrimary, size: sizes.iconMd),
                  SizedBox(width: sizes.gapSm),
                  Text(label, style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ),
      );
    }
    
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.8),
        borderRadius: context.radiusMd,
        border: Border.all(color: cs.outline.withOpacity(0.3)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: context.radiusMd,
          onTap: onPressed,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: sizes.gapLg, vertical: sizes.gapMd),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: cs.onSurface, size: sizes.iconMd),
                SizedBox(width: sizes.gapSm),
                Text(label, style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UserListTile extends StatelessWidget {
  final String uid;
  final String display;
  final String email;
  final String role;
  final bool disabled;
  final Map<String, dynamic> currentValues;
  
  const _UserListTile({
    required this.uid,
    required this.display,
    required this.email,
    required this.role,
    required this.disabled,
    required this.currentValues,
  });
  
  Color _getRoleColor(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    switch (role.toLowerCase()) {
      case 'owner': return Colors.amber;
      case 'manager': return cs.primary;
      case 'cashier': return Colors.teal;
      case 'clerk': return Colors.indigo;
      case 'accountant': return Colors.deepPurple;
      default: return cs.secondary;
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sizes = context.sizes;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final roleColor = _getRoleColor(context);
    final initial = (display.isNotEmpty ? display : uid).substring(0, 1).toUpperCase();
    
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.white.withOpacity(0.5),
        borderRadius: context.radiusMd,
        border: Border.all(color: cs.outline.withOpacity(0.1)),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: sizes.gapMd, vertical: sizes.gapSm),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [roleColor.withOpacity(0.8), roleColor],
            ),
            borderRadius: context.radiusMd,
            boxShadow: [
              BoxShadow(
                color: roleColor.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: Text(
              initial,
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: sizes.fontLg),
            ),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                display.isEmpty ? uid : display,
                style: context.texts.titleSmall?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: sizes.gapSm, vertical: sizes.gapXs),
              decoration: BoxDecoration(
                color: roleColor.withOpacity(0.15),
                borderRadius: context.radiusLg,
              ),
              child: Text(
                role.toUpperCase(),
                style: TextStyle(
                  color: roleColor,
                  fontSize: sizes.fontXs,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: EdgeInsets.only(top: sizes.gapXs),
          child: Row(
            children: [
              Icon(Icons.email_outlined, size: sizes.iconSm, color: cs.onSurfaceVariant.withOpacity(0.7)),
              SizedBox(width: sizes.gapSm),
              Expanded(
                child: Text(
                  email.isEmpty ? uid : email,
                  style: context.texts.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
              if (disabled)
                Container(
                  margin: EdgeInsets.only(left: sizes.gapSm),
                  padding: EdgeInsets.symmetric(horizontal: sizes.gapSm, vertical: sizes.gapXs),
                  decoration: BoxDecoration(
                    color: cs.error.withOpacity(0.15),
                    borderRadius: context.radiusMd,
                  ),
                  child: Text(
                    'DISABLED',
                    style: TextStyle(color: cs.error, fontSize: sizes.fontXs, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
        ),
        trailing: _UserActions(userId: uid, currentValues: currentValues),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OWNER BANNER
// ─────────────────────────────────────────────────────────────────────────────

class _OwnerBanner extends StatelessWidget {
  final String storeId;
  final bool loading; final bool hasOwner; final String? ownerName; final String? ownerEmail; final String? ownerId; final String? error;
  const _OwnerBanner({required this.storeId, this.loading=false, this.hasOwner=false, this.ownerName, this.ownerEmail, this.ownerId, this.error});
  @override
  Widget build(BuildContext context){
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    
    Widget child;
    Color bannerColor;
    IconData bannerIcon;
    
    if(error!=null){
      bannerColor = cs.error;
      bannerIcon = Icons.error_outline;
      child = Text('Owner error: $error', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.error));
    } else if(loading){
      bannerColor = cs.primary;
      bannerIcon = Icons.hourglass_empty;
      child = Row(
        children: [
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary)),
          context.gapHMd,
          const Text('Checking owner...'),
        ],
      );
    } else if(!hasOwner){
      bannerColor = context.appColors.warning;
      bannerIcon = Icons.warning_amber_rounded;
      child = Row(children:[
        Expanded(child: Text('No owner configured. You can promote an existing user to Owner.', style: context.texts.bodyMedium?.copyWith(fontWeight: FontWeight.w500, color: context.colors.onSurface))),
        const SizedBox(width: 12),
        _ModernButton(
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            final selected = await showDialog<String>(context: context, builder: (_)=> _SelectUserForOwnerDialog(storeId: storeId));
            if(selected!=null){
              try {
                final cf = FirebaseFunctions.instanceFor(region: 'us-central1');
                await cf.httpsCallable('setInitialOwner').call({'uid': selected});
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
          },
          icon: Icons.person_add_outlined,
          label: 'Set Owner',
          isPrimary: true,
        ),
      ]);
    } else {
      bannerColor = context.appColors.success;
      bannerIcon = Icons.verified_user;
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      final isOwner = currentUid != null && currentUid == ownerId;
      final selfEmail = isOwner ? (FirebaseAuth.instance.currentUser?.email?.trim() ?? '') : '';
      final selfName = isOwner
          ? ((FirebaseAuth.instance.currentUser?.displayName?.trim().isNotEmpty ?? false)
              ? FirebaseAuth.instance.currentUser!.displayName!.trim()
              : (selfEmail.isNotEmpty ? selfEmail.split('@').first : ''))
          : '';
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
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Store Owner', style: context.texts.labelSmall?.copyWith(color: cs.onSurface.withOpacity(0.7))),
              context.gapVXs,
              Text(label, style: context.texts.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface)),
            ],
          ),
        ),
        if(isOwner) _ModernButton(
          onPressed: () async {
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
          },
          icon: Icons.swap_horiz,
          label: 'Transfer',
          isPrimary: false,
        ),
      ]);
    }
    
    return ClipRRect(
      borderRadius: context.radiusLg,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: context.padMd,
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.7),
            borderRadius: context.radiusLg,
            border: Border.all(
              color: bannerColor.withOpacity(0.3),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: bannerColor.withOpacity(0.15),
                  borderRadius: context.radiusMd,
                ),
                child: Icon(bannerIcon, color: bannerColor, size: context.sizes.iconMd),
              ),
              SizedBox(width: context.sizes.gapMd),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectUserForOwnerDialog extends StatelessWidget {
  final String? storeId;
  const _SelectUserForOwnerDialog({this.storeId});
  @override
  Widget build(BuildContext context){
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    AppLog.info('admin.owner.select.dialog', 'Open select user dialog');
    
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ClipRRect(
        borderRadius: context.radiusXl,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            width: 420,
            constraints: const BoxConstraints(maxHeight: 500),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey.shade900.withOpacity(0.9) : Colors.white.withOpacity(0.95),
              borderRadius: context.radiusXl,
              border: Border.all(
                color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey.withOpacity(0.2),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: context.padLg,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: cs.outline.withOpacity(0.1)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: context.padSm,
                        decoration: BoxDecoration(
                          color: cs.primary.withOpacity(0.1),
                          borderRadius: context.radiusMd,
                        ),
                        child: Icon(Icons.person_search, color: cs.primary, size: context.sizes.iconMd),
                      ),
                      SizedBox(width: context.sizes.gapMd),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Select User', style: context.texts.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: cs.onSurface)),
                            SizedBox(height: context.sizes.gapXs),
                            Text('Choose a user to transfer ownership', style: context.texts.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.close, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                // Content
                Flexible(
                  child: Builder(builder: (context){
                    if (storeId != null && storeId!.isNotEmpty) {
                      final membersQ = FirebaseFirestore.instance
                          .collection('store_users')
                          .where('storeId', isEqualTo: storeId)
                          .where('status', isEqualTo: 'active');
                      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: membersQ.snapshots().handleError((e, st) { AppLog.error('admin.owner.select.members.stream', e, st); }),
                        builder: (context, mSnap) {
                          if (mSnap.hasError) { return Center(child: Text('Error: ${mSnap.error}')); }
                          if (!mSnap.hasData) { return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())); }
                          final mems = mSnap.data!.docs;
                          if (mems.isEmpty) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.person_off_outlined, size: 48, color: cs.onSurfaceVariant.withOpacity(0.5)),
                                    context.gapVMd,
                                    Text('No users in this store', style: context.texts.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
                                  ],
                                ),
                              ),
                            );
                          }
                          return ListView.separated(
                            shrinkWrap: true,
                            padding: context.padLg,
                            itemCount: mems.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
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
                                  return _SelectableUserTile(
                                    display: display,
                                    email: email,
                                    role: role,
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
                          if (snap.hasError) { return Center(child: Text('Error: ${snap.error}')); }
                          if (!snap.hasData) { return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())); }
                          final docs = snap.data!.docs;
                          if (docs.isEmpty) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.person_off_outlined, size: 48, color: cs.onSurfaceVariant.withOpacity(0.5)),
                                    context.gapVMd,
                                    Text('No users', style: context.texts.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
                                  ],
                                ),
                              ),
                            );
                          }
                          return ListView.separated(
                            shrinkWrap: true,
                            padding: context.padLg,
                            itemCount: docs.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (c, i) {
                              final d = docs[i];
                              final data = d.data();
                              final role = (data['role'] ?? '').toString();
                              return _SelectableUserTile(
                                display: (data['displayName'] ?? data['email'] ?? d.id).toString(),
                                email: (data['email'] ?? '').toString(),
                                role: role,
                                onTap: () => Navigator.pop(context, d.id),
                              );
                            },
                          );
                        },
                      );
                    }
                  }),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectableUserTile extends StatelessWidget {
  final String display;
  final String email;
  final String role;
  final VoidCallback onTap;
  
  const _SelectableUserTile({
    required this.display,
    required this.email,
    required this.role,
    required this.onTap,
  });
  
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final initial = display.isNotEmpty ? display[0].toUpperCase() : '?';
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: context.radiusMd,
        onTap: onTap,
        child: Container(
          padding: context.padMd,
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.withOpacity(0.05),
            borderRadius: context.radiusMd,
            border: Border.all(color: cs.outline.withOpacity(0.1)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [cs.primary.withOpacity(0.8), cs.primary],
                  ),
                  borderRadius: context.radiusMd,
                ),
                child: Center(
                  child: Text(initial, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: context.sizes.fontXl)),
                ),
              ),
              context.gapHMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(display, style: context.texts.titleSmall?.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface)),
                    if (email.isNotEmpty)
                      Text(email, style: context.texts.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              if (role.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.primary.withOpacity(0.1),
                    borderRadius: context.radiusLg,
                  ),
                  child: Text(role.toUpperCase(), style: TextStyle(color: cs.primary, fontSize: context.sizes.fontSm, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MODERN FORM WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _ModernTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  
  const _ModernTextField({
    required this.controller,
    required this.label,
    this.hint,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.validator,
  });
  
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      style: TextStyle(color: cs.onSurface),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: cs.onSurfaceVariant),
        hintStyle: TextStyle(color: cs.onSurfaceVariant.withOpacity(0.6)),
        prefixIcon: prefixIcon != null ? Icon(prefixIcon, color: cs.onSurfaceVariant, size: 20) : null,
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.withOpacity(0.05),
        border: OutlineInputBorder(
          borderRadius: context.radiusMd,
          borderSide: BorderSide(color: cs.outline.withOpacity(0.2)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: context.radiusMd,
          borderSide: BorderSide(color: cs.outline.withOpacity(0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: context.radiusMd,
          borderSide: BorderSide(color: cs.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: context.radiusMd,
          borderSide: BorderSide(color: cs.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: context.radiusMd,
          borderSide: BorderSide(color: cs.error, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}

class _ModernDropdown extends StatelessWidget {
  final String value;
  final String label;
  final List<DropdownMenuItem<String>> items;
  final ValueChanged<String?>? onChanged;
  
  const _ModernDropdown({
    required this.value,
    required this.label,
    required this.items,
    this.onChanged,
  });
  
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return DropdownButtonFormField<String>(
      value: value,
      items: items,
      onChanged: onChanged,
      style: TextStyle(color: cs.onSurface),
      dropdownColor: isDark ? Colors.grey.shade800 : Colors.white,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: cs.onSurfaceVariant),
        prefixIcon: Icon(Icons.badge_outlined, color: cs.onSurfaceVariant, size: 20),
        filled: true,
        fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.withOpacity(0.05),
        border: OutlineInputBorder(
          borderRadius: context.radiusMd,
          borderSide: BorderSide(color: cs.outline.withOpacity(0.2)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: context.radiusMd,
          borderSide: BorderSide(color: cs.outline.withOpacity(0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: context.radiusMd,
          borderSide: BorderSide(color: cs.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    
    // Listen for existence of an owner to decide if owner option should be shown
    final ownerStream = FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'owner')
        .limit(1)
        .snapshots();
    return StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
      stream: ownerStream,
      builder: (context, ownerSnap){
        final allowOwner = ownerSnap.hasData && ownerSnap.data!.docs.isEmpty;
        return Dialog(
          backgroundColor: Colors.transparent,
          child: ClipRRect(
            borderRadius: context.radiusXl,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                width: 480,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey.shade900.withOpacity(0.9) : Colors.white.withOpacity(0.95),
                  borderRadius: context.radiusXl,
                  border: Border.all(
                    color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey.withOpacity(0.2),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Container(
                      padding: context.padXl,
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: cs.outline.withOpacity(0.1)),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: cs.primary.withOpacity(0.1),
                              borderRadius: context.radiusMd,
                            ),
                            child: Icon(Icons.person_add, color: cs.primary, size: 24),
                          ),
                          context.gapHLg,
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Add New User', style: context.texts.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: cs.onSurface)),
                                context.gapVXs,
                                Text('Create a new team member account', style: context.texts.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: _saving ? null : () => Navigator.pop(context),
                            icon: Icon(Icons.close, color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    // Form content
                    Flexible(
                      child: SingleChildScrollView(
                        padding: context.padXl,
                        child: Form(
                          key: _form,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _ModernTextField(
                                controller: _emailCtrl,
                                label: 'Email Address',
                                hint: 'user@example.com',
                                prefixIcon: Icons.email_outlined,
                                keyboardType: TextInputType.emailAddress,
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) return 'Email is required';
                                  if (!v.contains('@')) return 'Invalid email format';
                                  return null;
                                },
                              ),
                              context.gapVLg,
                              _ModernTextField(
                                controller: _nameCtrl,
                                label: 'Display Name',
                                hint: 'John Doe (optional)',
                                prefixIcon: Icons.person_outline,
                              ),
                              context.gapVLg,
                              Row(
                                children: [
                                  Expanded(
                                    child: _ModernTextField(
                                      controller: _passwordCtrl,
                                      label: 'Password',
                                      hint: '••••••••',
                                      prefixIcon: Icons.lock_outline,
                                      obscureText: !_showPassword,
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _showPassword ? Icons.visibility_off : Icons.visibility,
                                          color: cs.onSurfaceVariant,
                                          size: 20,
                                        ),
                                        onPressed: () => setState(() => _showPassword = !_showPassword),
                                      ),
                                      validator: (v) {
                                        if (v == null || v.length < 6) return 'Min 6 characters';
                                        return null;
                                      },
                                    ),
                                  ),
                                  context.gapHMd,
                                  Expanded(
                                    child: _ModernTextField(
                                      controller: _password2Ctrl,
                                      label: 'Confirm',
                                      hint: '••••••••',
                                      prefixIcon: Icons.lock_outline,
                                      obscureText: true,
                                      validator: (v) {
                                        if (v != _passwordCtrl.text) return 'Passwords don\'t match';
                                        return null;
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              context.gapVLg,
                              _ModernDropdown(
                                value: _role,
                                label: allowOwner ? 'Role (Owner allowed once)' : 'Role',
                                items: [
                                  if (allowOwner) const DropdownMenuItem(value: 'owner', child: Text('Owner')),
                                  const DropdownMenuItem(value: 'manager', child: Text('Manager')),
                                  const DropdownMenuItem(value: 'cashier', child: Text('Cashier')),
                                  const DropdownMenuItem(value: 'clerk', child: Text('Clerk')),
                                  const DropdownMenuItem(value: 'accountant', child: Text('Accountant')),
                                ],
                                onChanged: _saving ? null : (v) {
                                  if (v != null) setState(() => _role = v);
                                },
                              ),
                              context.gapVLg,
                              _ModernTextField(
                                controller: _storesCtrl,
                                label: 'Store IDs',
                                hint: 'store1, store2 (comma separated)',
                                prefixIcon: Icons.store_outlined,
                              ),
                              if (_error != null)
                                Container(
                                  margin: const EdgeInsets.only(top: 16),
                                  padding: context.padMd,
                                  decoration: BoxDecoration(
                                    color: cs.error.withOpacity(0.1),
                                    borderRadius: context.radiusMd,
                                    border: Border.all(color: cs.error.withOpacity(0.3)),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.error_outline, color: cs.error, size: 20),
                                      context.gapHMd,
                                      Expanded(
                                        child: Text(_error!, style: TextStyle(color: cs.error, fontSize: context.sizes.fontMd)),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Footer
                    Container(
                      padding: context.padXl,
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: cs.outline.withOpacity(0.1)),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: _saving ? null : () => Navigator.pop(context),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            ),
                            child: Text('Cancel', style: TextStyle(color: cs.onSurfaceVariant)),
                          ),
                          context.gapHMd,
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [cs.primary, cs.primary.withOpacity(0.8)],
                              ),
                              borderRadius: context.radiusMd,
                              boxShadow: [
                                BoxShadow(
                                  color: cs.primary.withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: context.radiusMd,
                                onTap: _saving ? null : _submit,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                  child: _saving
                                      ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary))
                                      : Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.add, color: cs.onPrimary, size: 20),
                                            context.gapHSm,
                                            Text('Create User', style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w600)),
                                          ],
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _UserActions extends StatefulWidget {
  final String userId; final Map<String,dynamic> currentValues;
  const _UserActions({required this.userId, required this.currentValues});
  @override State<_UserActions> createState() => _UserActionsState();
}
class _UserActionsState extends State<_UserActions>{
  bool _busy = false;
  @override Widget build(BuildContext context){
    final cs = Theme.of(context).colorScheme;
    final role = (widget.currentValues['role'] ?? '') as String;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: context.radiusSm,
      ),
      child: PopupMenuButton<String>(
        icon: Icon(Icons.more_vert, color: cs.onSurfaceVariant),
        shape: RoundedRectangleBorder(borderRadius: context.radiusMd),
        onSelected: (v) async {
          if(v=='edit'){
            _openEditUser(context, widget.userId, widget.currentValues);
          } else if (v=='delete'){
            final currentUid = FirebaseAuth.instance.currentUser?.uid;
            if (currentUid != null && currentUid == widget.userId) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot delete the currently signed-in user')));
              return;
            }
            final messenger = ScaffoldMessenger.of(context);
            await Future<void>.delayed(const Duration(milliseconds: 10));
            if (!context.mounted) return;
            final ok = await _showDeleteConfirmation(context, widget.currentValues['email'] ?? widget.userId);
            if(ok==true){
              if(!mounted) return;
              setState(()=> _busy=true);
              try {
                final callable = FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable('deleteUserAccount');
                await callable.call({'uid': widget.userId});
              } on FirebaseFunctionsException catch(e){
                if(!mounted) return;
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
            PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit_outlined, size: 18, color: cs.onSurface),
                  context.gapHMd,
                  const Text('Edit'),
                ],
              ),
            ),
          ];
          final isOwnerUser = role == 'owner';
          final currentUid = FirebaseAuth.instance.currentUser?.uid;
          final isSelf = currentUid != null && currentUid == widget.userId;
          final canDelete = !_busy && !isOwnerUser && !isSelf;
          items.add(PopupMenuItem(
            value: 'delete',
            enabled: canDelete,
            child: Row(
              children: [
                Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: canDelete ? cs.error : cs.onSurfaceVariant,
                ),
                context.gapHMd,
                Text(
                  isOwnerUser ? 'Delete (owner)' : (isSelf ? 'Delete (self)' : 'Delete'),
                  style: TextStyle(color: canDelete ? cs.error : cs.onSurfaceVariant),
                ),
              ],
            ),
          ));
          return items;
        },
      ),
    );
  }
  
  Future<bool?> _showDeleteConfirmation(BuildContext context, String userIdentifier) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => Dialog(
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: context.radiusXl,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              width: 400,
              decoration: BoxDecoration(
                color: isDark ? Colors.grey.shade900.withOpacity(0.9) : Colors.white.withOpacity(0.95),
                borderRadius: context.radiusXl,
                border: Border.all(
                  color: cs.error.withOpacity(0.3),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: context.padXl,
                    child: Column(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: cs.error.withOpacity(0.1),
                            borderRadius: context.radiusLg,
                          ),
                          child: Icon(Icons.delete_forever, color: cs.error, size: 32),
                        ),
                        const SizedBox(height: 20),
                        Text('Delete User', style: context.texts.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: cs.onSurface)),
                        context.gapVMd,
                        Text(
                          'Are you sure you want to delete $userIdentifier? This action cannot be undone.',
                          textAlign: TextAlign.center,
                          style: context.texts.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: context.padLg,
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: cs.outline.withOpacity(0.1)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(dialogCtx, false),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: Text('Cancel', style: TextStyle(color: cs.onSurfaceVariant)),
                          ),
                        ),
                        context.gapHMd,
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: cs.error,
                              borderRadius: context.radiusMd,
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: context.radiusMd,
                                onTap: () => Navigator.pop(dialogCtx, true),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.delete_outline, color: cs.onError, size: 18),
                                      context.gapHSm,
                                      Text('Delete', style: TextStyle(color: cs.onError, fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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

  static const List<String> _allowedRoles = ['manager','cashier','clerk','accountant'];
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
      setState(()=> _success = 'Updated successfully!');
    } on FirebaseFunctionsException catch(e){
      setState(()=> _error = e.message ?? e.code);
    } catch(e){ setState(()=> _error = '$e'); }
    setState(()=> _saving=false);
  }
  
  @override Widget build(BuildContext context){
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final email = (widget.current['email'] ?? '').toString();
    final displayName = (widget.current['displayName'] ?? email.split('@').first).toString();
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ClipRRect(
        borderRadius: context.radiusXl,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            width: 480,
            decoration: BoxDecoration(
              color: isDark ? Colors.grey.shade900.withOpacity(0.9) : Colors.white.withOpacity(0.95),
              borderRadius: context.radiusXl,
              border: Border.all(
                color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey.withOpacity(0.2),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header with user info
                Container(
                  padding: context.padXl,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: cs.outline.withOpacity(0.1)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [cs.primary.withOpacity(0.8), cs.primary],
                          ),
                          borderRadius: context.radiusLg,
                          boxShadow: [
                            BoxShadow(
                              color: cs.primary.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(initial, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: context.sizes.fontXxl)),
                        ),
                      ),
                      context.gapHLg,
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Edit User', style: context.texts.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: cs.onSurface)),
                            context.gapVXs,
                            Text(email.isNotEmpty ? email : widget.uid, style: context.texts.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _saving ? null : () => Navigator.pop(context),
                        icon: Icon(Icons.close, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                // Form content
                Padding(
                  padding: context.padXl,
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ModernTextField(
                          controller: _nameCtrl,
                          label: 'Display Name',
                          hint: 'John Doe',
                          prefixIcon: Icons.person_outline,
                        ),
                        context.gapVLg,
                        _ModernDropdown(
                          value: _role,
                          label: 'Role',
                          items: _buildRoleItems(_role),
                          onChanged: _saving ? null : (v) {
                            if (v != null) setState(() => _role = v);
                          },
                        ),
                        context.gapVLg,
                        _ModernTextField(
                          controller: _storesCtrl,
                          label: 'Store IDs',
                          hint: 'store1, store2 (comma separated)',
                          prefixIcon: Icons.store_outlined,
                        ),
                        if (_error != null)
                          Container(
                            margin: const EdgeInsets.only(top: 16),
                            padding: context.padMd,
                            decoration: BoxDecoration(
                              color: cs.error.withOpacity(0.1),
                              borderRadius: context.radiusMd,
                              border: Border.all(color: cs.error.withOpacity(0.3)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.error_outline, color: cs.error, size: 20),
                                context.gapHMd,
                                Expanded(
                                  child: Text(_error!, style: TextStyle(color: cs.error, fontSize: context.sizes.fontMd)),
                                ),
                              ],
                            ),
                          ),
                        if (_success != null)
                          Container(
                            margin: const EdgeInsets.only(top: 16),
                            padding: context.padMd,
                            decoration: BoxDecoration(
                              color: context.appColors.success.withOpacity(0.1),
                              borderRadius: context.radiusMd,
                              border: Border.all(color: context.appColors.success.withOpacity(0.3)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.check_circle_outline, color: context.appColors.success, size: 20),
                                context.gapHMd,
                                Expanded(
                                  child: Text(_success!, style: TextStyle(color: context.appColors.success, fontSize: context.sizes.fontMd)),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                // Footer
                Container(
                  padding: context.padXl,
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: cs.outline.withOpacity(0.1)),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _saving ? null : () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                        child: Text('Close', style: TextStyle(color: cs.onSurfaceVariant)),
                      ),
                      context.gapHMd,
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [cs.primary, cs.primary.withOpacity(0.8)],
                          ),
                          borderRadius: context.radiusMd,
                          boxShadow: [
                            BoxShadow(
                              color: cs.primary.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: context.radiusMd,
                            onTap: _saving ? null : _submit,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              child: _saving
                                  ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary))
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.save_outlined, color: cs.onPrimary, size: 20),
                                        context.gapHSm,
                                        Text('Save Changes', style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                      ),
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
}
// DemoUser list removed – live Firestore data is shown instead.
