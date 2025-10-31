import 'package:cloud_firestore/cloud_firestore.dart';

/// Fetch a single page from a Firestore [base] query.
/// Returns items mapped by [map] and the next cursor (last doc) or null if end.
Future<(List<T>, DocumentSnapshot<Map<String, dynamic>>?)> fetchFirestorePage<T>({
  required Query<Map<String, dynamic>> base,
  DocumentSnapshot<Map<String, dynamic>>? after,
  required T Function(QueryDocumentSnapshot<Map<String, dynamic>>) map,
  required int pageSize,
}) async {
  final q = (after == null)
      ? base.limit(pageSize)
      : base.startAfterDocument(after).limit(pageSize);
  final snap = await q.get();
  final docs = snap.docs;
  final items = docs.map(map).toList();
  final next = docs.isEmpty ? null : docs.last;
  return (items, next);
}
