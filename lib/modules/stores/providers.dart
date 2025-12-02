import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/auth/auth_repository_and_provider.dart';
import 'models.dart';

// Current selected store id (in-memory). Persisting can be added later.
final selectedStoreIdProvider = StateProvider<String?>((ref) => null);

// Stream memberships of the current user
final myMembershipsProvider = StreamProvider<List<StoreMembership>>((ref) {
  final user = ref.watch(authStateProvider);
  if (user == null) return Stream.value(const <StoreMembership>[]);
  final q = FirebaseFirestore.instance
      .collection('store_users')
      .where('userId', isEqualTo: user.uid)
      .where('status', isEqualTo: 'active');
  return q.snapshots().map((s) => s.docs.map((d) => StoreMembership.fromFirestore(d)).toList());
});

// Fetch stores for a given set of ids (single-shot). For live updates, expand later.
Future<List<StoreDoc>> _fetchStoresByIds(List<String> ids) async {
  if (ids.isEmpty) return const [];
  final fs = FirebaseFirestore.instance;
  // Firestore whereIn supports up to 10 values; chunk if needed.
  final chunks = <List<String>>[];
  for (var i = 0; i < ids.length; i += 10) {
    chunks.add(ids.sublist(i, i + 10 > ids.length ? ids.length : i + 10));
  }
  final results = <StoreDoc>[];
  for (final chunk in chunks) {
    final snap = await fs.collection('stores').where(FieldPath.documentId, whereIn: chunk).get();
    results.addAll(snap.docs.map((d) => StoreDoc.fromFirestore(d)));
  }
  // Maintain original order by ids
  final byId = {for (final s in results) s.id: s};
  return ids.map((id) => byId[id]).whereType<StoreDoc>().toList();
}

// Derived provider: list of stores the user can access paired with role
class StoreAccess {
  final StoreDoc store;
  final String role;
  const StoreAccess(this.store, this.role);
}

final myStoresProvider = FutureProvider<List<StoreAccess>>((ref) async {
  final membershipsAsync = ref.watch(myMembershipsProvider);
  return await membershipsAsync.when(
    data: (memberships) async {
      final ids = memberships.map((m) => m.storeId).toList();
      final stores = await _fetchStoresByIds(ids);
      final roleByStore = {for (final m in memberships) m.storeId: m.role};
      return stores.map((s) => StoreAccess(s, roleByStore[s.id] ?? 'viewer')).toList();
    },
    loading: () async => const <StoreAccess>[],
    error: (e, st) async => const <StoreAccess>[],
  );
});

// Selected store doc (one-shot fetch when id changes)
final selectedStoreDocProvider = FutureProvider<StoreDoc?>((ref) async {
  final id = ref.watch(selectedStoreIdProvider);
  if (id == null) return null;
  final snap = await FirebaseFirestore.instance.collection('stores').doc(id).get();
  if (!snap.exists) return null;
  return StoreDoc.fromFirestore(snap);
});

// Initialize and persist selected store per user using SharedPreferences
final selectedStorePersistInitProvider = Provider<void>((ref) {
  // React to auth changes
  final user = ref.watch(authStateProvider);
  // Load on first use
  Future<void>(() async {
    final prefs = await SharedPreferences.getInstance();
  String projectId;
  try {
    // Avoid accessing Firebase.apps which can cause web interop issues.
    projectId = Firebase.app().options.projectId;
  } catch (_) {
    projectId = 'default';
  }
    final newKey = user == null ? 'selectedStoreId_${projectId}_anonymous' : 'selectedStoreId_${projectId}_${user.uid}';
    // Migration: read legacy key once and move it under project-scoped key
    final legacyKey = user == null ? 'selectedStoreId_anonymous' : 'selectedStoreId_${user.uid}';
    String? saved = prefs.getString(newKey);
    saved ??= prefs.getString(legacyKey);
    if (saved != null && ref.read(selectedStoreIdProvider) == null) {
      ref.read(selectedStoreIdProvider.notifier).state = saved;
      // Clean up legacy key to avoid cross-project leakage
      if (prefs.containsKey(legacyKey)) {
        await prefs.remove(legacyKey);
        await prefs.setString(newKey, saved);
      }
    }
  });

  // Persist on change
  ref.listen<String?>(selectedStoreIdProvider, (prev, next) async {
    final prefs = await SharedPreferences.getInstance();
  String projectId;
  try {
    // Avoid accessing Firebase.apps which can cause web interop issues.
    projectId = Firebase.app().options.projectId;
  } catch (_) {
    projectId = 'default';
  }
    final key = user == null ? 'selectedStoreId_${projectId}_anonymous' : 'selectedStoreId_${projectId}_${user.uid}';
    if (next == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, next);
    }
  });

  // Auto-heal selection when membership is removed or store archived
  ref.listen<AsyncValue<List<StoreMembership>>>(myMembershipsProvider, (prev, next) async {
    final current = ref.read(selectedStoreIdProvider);
    if (current == null) return;
    final memberships = next.value ?? const <StoreMembership>[];
    final stillMember = memberships.any((m) => m.storeId == current && m.status == 'active');
    if (!stillMember) {
      ref.read(selectedStoreIdProvider.notifier).state = null;
      return;
    }
    // Check store status; if archived, clear selection
    try {
      final doc = await FirebaseFirestore.instance.collection('stores').doc(current).get();
      final status = (doc.data()?['status'] as String?) ?? 'active';
      if (status != 'active') {
        ref.read(selectedStoreIdProvider.notifier).state = null;
      }
    } catch (_) {}
  });
});
