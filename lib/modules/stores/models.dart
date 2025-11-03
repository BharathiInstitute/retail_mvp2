import 'package:cloud_firestore/cloud_firestore.dart';

class StoreDoc {
  final String id;
  final String name;
  final String? slug;
  final String status; // active | archived
  final String? createdBy;
  final Timestamp? createdAt;

  const StoreDoc({
    required this.id,
    required this.name,
    this.slug,
    this.status = 'active',
    this.createdBy,
    this.createdAt,
  });

  factory StoreDoc.fromFirestore(DocumentSnapshot<Map<String, dynamic>> snap) {
    final m = snap.data() ?? const {};
    return StoreDoc(
      id: snap.id,
      name: (m['name'] ?? '') as String,
      slug: (m['slug'] as String?)?.trim().isEmpty == true ? null : (m['slug'] as String?),
      status: (m['status'] as String?) ?? 'active',
      createdBy: m['createdBy'] as String?,
      createdAt: m['createdAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        if (slug != null) 'slug': slug,
        'status': status,
        if (createdBy != null) 'createdBy': createdBy,
        if (createdAt != null) 'createdAt': createdAt,
      };
}

class StoreMembership {
  final String id; // storeId_userId (deterministic)
  final String storeId;
  final String userId;
  final String role; // owner | manager | cashier | viewer
  final String status; // invited | active | revoked
  final Timestamp? invitedAt;
  final Timestamp? acceptedAt;

  const StoreMembership({
    required this.id,
    required this.storeId,
    required this.userId,
    required this.role,
    required this.status,
    this.invitedAt,
    this.acceptedAt,
  });

  factory StoreMembership.fromFirestore(DocumentSnapshot<Map<String, dynamic>> snap) {
    final m = snap.data() ?? const {};
    return StoreMembership(
      id: snap.id,
      storeId: (m['storeId'] ?? '') as String,
      userId: (m['userId'] ?? '') as String,
      role: (m['role'] ?? 'viewer') as String,
      status: (m['status'] ?? 'active') as String,
      invitedAt: m['invitedAt'] as Timestamp?,
      acceptedAt: m['acceptedAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toMap() => {
        'storeId': storeId,
        'userId': userId,
        'role': role,
        'status': status,
        if (invitedAt != null) 'invitedAt': invitedAt,
        if (acceptedAt != null) 'acceptedAt': acceptedAt,
      };
}
