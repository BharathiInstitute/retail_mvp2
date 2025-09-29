import 'package:cloud_firestore/cloud_firestore.dart';

/// Service encapsulating user CRUD + role assignment + store membership.
class UserAdminService {
  UserAdminService._();
  static final instance = UserAdminService._();

  final _fs = FirebaseFirestore.instance;
  // FirebaseAuth instance kept for future expansion (invite flow / disabling accounts) but currently unused.

  CollectionReference<Map<String,dynamic>> get _users => _fs.collection('users');

  Future<void> createUserDoc({
    required String uid,
    required String email,
    required String displayName,
    required String role,
    List<String>? storeIds,
  }) async {
    final data = {
      'email': email,
      'displayName': displayName,
      'role': role,
      'stores': storeIds ?? <String>[],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await _users.doc(uid).set(data, SetOptions(merge: true));
  }

  Future<void> updateUserRole({required String uid, required String role}) async {
    await _users.doc(uid).update({'role': role, 'updatedAt': FieldValue.serverTimestamp()});
  }

  Future<void> addStoreToUser({required String uid, required String storeId}) async {
    await _users.doc(uid).set({'stores': FieldValue.arrayUnion([storeId]), 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  }

  Future<void> removeStoreFromUser({required String uid, required String storeId}) async {
    await _users.doc(uid).set({'stores': FieldValue.arrayRemove([storeId]), 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  }

  Future<void> deleteUserDoc(String uid) async {
    await _users.doc(uid).delete();
  }

  /// Optional: also disable auth user (requires elevated privileges via Cloud Function usually)
  Future<void> disableAuthUser(String uid) async {
    // Placeholder: This requires an admin SDK (Cloud Function). Left as a no-op here.
  }
}
