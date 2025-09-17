import 'package:cloud_firestore/cloud_firestore.dart';

/// InventoryRepository manages Firestore-backed product catalog.
/// Collection name used: "inventory" (one document per product).
class InventoryRepository {
  InventoryRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Stream products for a tenant ordered by name.
  Stream<List<ProductDoc>> streamProducts({required String tenantId}) {
    return _db
        .collection('inventory')
        .where('tenantId', isEqualTo: tenantId)
        .snapshots()
        .map((snap) {
          final list = snap.docs.map((d) => ProductDoc.fromDoc(d)).toList();
          list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          return list;
        });
  }

  // Seeding and bulk delete helpers removed

  /// Create a new product document under the `inventory` collection.
  /// Uses the SKU as the document ID to keep it unique and readable.
  Future<void> addProduct({
    required String tenantId,
    required String sku,
    required String name,
    required double unitPrice,
    num? taxPct,
    String? barcode,
    String? description,
    List<String>? variants,
    double? mrpPrice,
    double? costPrice,
    bool isActive = true,
    int storeQty = 0,
    int warehouseQty = 0,
  }) async {
    final docRef = _db.collection('inventory').doc(sku);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(docRef);
      if (snap.exists) {
        throw StateError('A product with SKU "$sku" already exists.');
      }

      final List<Map<String, dynamic>> batches = [];
      if (storeQty > 0) {
        batches.add({
          'batchNo': 'INIT-Store',
          'qty': storeQty,
          'location': 'Store',
        });
      }
      if (warehouseQty > 0) {
        batches.add({
          'batchNo': 'INIT-Warehouse',
          'qty': warehouseQty,
          'location': 'Warehouse',
        });
      }

      tx.set(docRef, {
        'tenantId': tenantId,
        'sku': sku,
        'barcode': barcode ?? '',
        'name': name,
        'description': description,
        'unitPrice': unitPrice,
        'mrpPrice': mrpPrice,
        'costPrice': costPrice,
        'taxPct': taxPct,
        'variants': (variants ?? const <String>[]).where((v) => v.trim().isNotEmpty).toList(),
        'categoryId': null,
        'supplierId': null,
        'isActive': isActive,
        'batches': batches,
      });
    });
  }

  /// Update an existing product document (by SKU/doc id). Only fields provided
  /// are updated; others are left unchanged. SKU cannot be changed here.
  Future<void> updateProduct({
    required String sku,
    String? name,
    double? unitPrice,
    num? taxPct,
    String? barcode,
    String? description,
    List<String>? variants,
    double? mrpPrice,
    double? costPrice,
    bool? isActive,
  }) async {
    final docRef = _db.collection('inventory').doc(sku);
    final data = <String, dynamic>{};
    void put(String key, dynamic value) { if (value != null) data[key] = value; }
    put('name', name);
    put('unitPrice', unitPrice);
    put('taxPct', taxPct);
    put('barcode', barcode);
    put('description', description);
    if (variants != null) {
      data['variants'] = variants.where((v) => v.trim().isNotEmpty).toList();
    }
    put('mrpPrice', mrpPrice);
    put('costPrice', costPrice);
    put('isActive', isActive);
    if (data.isEmpty) return; // nothing to update
    await docRef.update(data);
  }

  /// Delete a product by SKU (doc id).
  Future<void> deleteProduct({required String sku}) async {
    final docRef = _db.collection('inventory').doc(sku);
    await docRef.delete();
  }
}

class ProductDoc {
  final String id;
  final String tenantId;
  final String sku;
  final String barcode;
  final String name;
  final String? description;
  final double unitPrice;
  final double? mrpPrice;
  final double? costPrice;
  final num? taxPct;
  final List<String> variants;
  final String? categoryId;
  final String? supplierId;
  final bool isActive;
  final List<BatchDoc> batches;

  ProductDoc({
    required this.id,
    required this.tenantId,
    required this.sku,
    required this.barcode,
    required this.name,
    this.description,
    required this.unitPrice,
    this.mrpPrice,
    this.costPrice,
    this.taxPct,
    required this.variants,
    this.categoryId,
    this.supplierId,
    required this.isActive,
    required this.batches,
  });

  int get totalStock => batches.fold(0, (p, b) => p + (b.qty ?? 0));
  int stockAt(String location) =>
      batches.where((b) => (b.location ?? '') == location).fold(0, (p, b) => p + (b.qty ?? 0));

  factory ProductDoc.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const {};
    final batches = (m['batches'] as List?)?.map((e) => BatchDoc.fromMap(e)).whereType<BatchDoc>().toList() ?? const <BatchDoc>[];
    return ProductDoc(
      id: d.id,
      tenantId: (m['tenantId'] ?? '') as String,
      sku: (m['sku'] ?? '') as String,
      barcode: (m['barcode'] ?? '') as String,
      name: (m['name'] ?? '') as String,
      description: m['description'] as String?,
      unitPrice: (m['unitPrice'] is int) ? (m['unitPrice'] as int).toDouble() : (m['unitPrice'] ?? 0.0) as double,
      mrpPrice: m['mrpPrice'] == null
          ? null
          : (m['mrpPrice'] is int)
              ? (m['mrpPrice'] as int).toDouble()
              : m['mrpPrice'] as double,
      costPrice: m['costPrice'] == null
          ? null
          : (m['costPrice'] is int)
              ? (m['costPrice'] as int).toDouble()
              : m['costPrice'] as double,
      taxPct: m['taxPct'] as num?,
      variants: (m['variants'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[],
      categoryId: m['categoryId'] as String?,
      supplierId: m['supplierId'] as String?,
      isActive: (m['isActive'] ?? true) as bool,
      batches: batches,
    );
  }
}

class BatchDoc {
  final String? batchNo;
  final DateTime? expiry;
  final int? qty;
  final String? location;
  BatchDoc({this.batchNo, this.expiry, this.qty, this.location});

  factory BatchDoc.fromMap(dynamic m) {
    if (m is! Map) return BatchDoc();
  final expiry = m['expiry'];
    return BatchDoc(
    batchNo: m['batchNo']?.toString(),
    expiry: expiry is Timestamp ? expiry.toDate() : (expiry is DateTime ? expiry : null),
    qty: (m['qty'] is String)
      ? int.tryParse(m['qty'])
      : (m['qty'] as num?)?.toInt(),
    location: m['location']?.toString(),
    );
  }
}

// Demo-name generator removed
