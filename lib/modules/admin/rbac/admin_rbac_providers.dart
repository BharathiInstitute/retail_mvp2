import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Basic RBAC + user doc stream
class AppUser {
  final String uid;
  final String? email;
  final String? displayName;
  final String? role; // global / highest role
  final List<String> storeIds;
  AppUser({required this.uid, this.email, this.displayName, this.role, required this.storeIds});
}

final firebaseUserProvider = StreamProvider<User?>((ref) => FirebaseAuth.instance.authStateChanges());

final appUserDocProvider = StreamProvider<DocumentSnapshot<Map<String,dynamic>>?>((ref){
  final u = ref.watch(firebaseUserProvider).value;
  if(u==null) return const Stream.empty();
  return FirebaseFirestore.instance.collection('users').doc(u.uid).snapshots();
});

final appUserProvider = Provider<AppUser?>((ref){
  final fb = ref.watch(firebaseUserProvider).value;
  final doc = ref.watch(appUserDocProvider).value;
  if(fb==null) return null;
  final data = doc?.data() ?? {};
  final stores = (data['stores'] as List?)?.whereType<String>().toList() ?? const <String>[];
  return AppUser(
    uid: fb.uid,
    email: fb.email,
    displayName: data['displayName'] ?? fb.displayName,
    role: data['role'] as String?,
    storeIds: stores,
  );
});

class Capabilities {
  final bool manageUsers; final bool editSettings; final bool viewAuditLogs; final bool manageInventory; final bool viewAccounting;
  const Capabilities({this.manageUsers=false,this.editSettings=false,this.viewAuditLogs=false,this.manageInventory=false,this.viewAccounting=false});
  static const none = Capabilities();
}

Capabilities _roleCaps(String? role){
  switch(role){
    case 'owner': return const Capabilities(manageUsers:true, editSettings:true, viewAuditLogs:true, manageInventory:true, viewAccounting:true);
    case 'manager': return const Capabilities(manageUsers:true, editSettings:true, viewAuditLogs:true, manageInventory:true);
    case 'accountant': return const Capabilities(viewAccounting:true, viewAuditLogs:true);
    case 'cashier': return const Capabilities(manageInventory:true);
    case 'clerk': return const Capabilities(manageInventory:true);
    default: return Capabilities.none;
  }
}

final capabilitiesProvider = Provider<Capabilities>((ref){
  final u = ref.watch(appUserProvider);
  return _roleCaps(u?.role);
});

/// Bootstrap: if there are no user documents at all, automatically create
/// the currently signed-in Firebase user as an `owner` so the system becomes
/// manageable (otherwise you can't see the Invite/Add button).
/// Runs only when admin area is visited and is safe/idempotent: after the
/// first user doc exists it becomes a fast no-op.
final bootstrapOwnerProvider = FutureProvider<void>((ref) async {
  final fb = FirebaseAuth.instance.currentUser;
  if (fb == null) return; // not signed in
  final usersColl = FirebaseFirestore.instance.collection('users');
  try {
    final existing = await usersColl.limit(1).get();
    if (existing.size == 0) {
      await usersColl.doc(fb.uid).set({
        'email': fb.email,
        'displayName': fb.displayName ?? (fb.email?.split('@').first ?? 'Owner'),
        'role': 'owner',
        'stores': <String>[],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  } catch (_) {
    // Swallow errors quietly; not critical for normal operation.
  }
});
