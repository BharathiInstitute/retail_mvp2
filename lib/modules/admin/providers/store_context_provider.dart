import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_claims_provider.dart';

/// Holds the currently selected storeId (persisting can be layered later)
final selectedStoreIdProvider = StateNotifierProvider<SelectedStoreController, String?>((ref) {
  return SelectedStoreController(ref);
});

class SelectedStoreController extends StateNotifier<String?> {
  final Ref ref;
  static const _prefsKey = 'lastStoreId';
  SelectedStoreController(this.ref): super(null) { _init(); }
  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    final auth = await ref.watch(authUserProvider.future);
    // pick in order: saved -> auth.lastStoreId -> first storeRoles key
    final firstStore = auth.storeRoles.keys.isNotEmpty ? auth.storeRoles.keys.first : null;
    state = saved ?? auth.lastStoreId ?? firstStore;
  }
  Future<void> setStore(String id) async {
    state = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, id);
    // Optionally update user doc lastStoreId (fire and forget)
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      FirebaseFirestore.instance.collection('users').doc(uid).set({'lastStoreId': id}, SetOptions(merge: true));
    }
  }
}

/// Stream the active store document
final activeStoreDocProvider = StreamProvider.autoDispose<Map<String,dynamic>?>((ref) {
  final id = ref.watch(selectedStoreIdProvider);
  if (id == null) return const Stream.empty();
  return FirebaseFirestore.instance.collection('stores').doc(id)
    .snapshots().map((s) => s.data());
});

/// Stream membership for the current user inside selected store
final activeMembershipProvider = StreamProvider.autoDispose<Map<String,dynamic>?>((ref) {
  final id = ref.watch(selectedStoreIdProvider);
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (id == null || uid == null) return const Stream.empty();
  return FirebaseFirestore.instance.collection('stores').doc(id)
    .collection('users').doc(uid).snapshots().map((s) => s.data());
});
