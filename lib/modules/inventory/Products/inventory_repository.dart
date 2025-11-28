import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/store_scoped_refs.dart';

/// Clean rebuilt InventoryRepository (single definition) providing CRUD,
/// audit overwrite and incremental stock movement support.
class InventoryRepository {
  InventoryRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  static const _storeLocation = 'Store';
  static const _warehouseLocation = 'Warehouse';

  // -------------------- Streams --------------------
  Stream<List<ProductDoc>> streamProducts({required String storeId}) {
    Query<Map<String, dynamic>> q = StoreRefs.of(storeId, fs: _db).products();
    return q.snapshots().map((s) {
      final list = s.docs.map(ProductDoc.fromDoc).toList();
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return list;
    });
  }

  // -------------------- CRUD --------------------
  Future<void> addProduct({
    required String storeId,
    required String sku,
    required String name,
    required double unitPrice,
    num? taxPct,
    String? barcode,
    String? description,
    List<String>? variants,
    List<String>? imageUrls,
    double? mrpPrice,
    double? costPrice,
    num? discountPct,
    String? category,
    String? subCategory,
    String? quantityPerUnit,
    double? height,
    double? width,
    double? weight,
    double? volumeMl,
    int? minStock,
    bool isActive = true,
    int storeQty = 0,
    int warehouseQty = 0,
    List<BatchDoc>? customBatches,
  }) async {
    final doc = StoreRefs.of(storeId, fs: _db).products().doc(sku);
    await _db.runTransaction((tx) async {
      if ((await tx.get(doc)).exists) {
        throw StateError('A product with SKU "$sku" already exists.');
      }
      final batches = <Map<String, dynamic>>[
        if (customBatches == null || customBatches.isEmpty) ...[
          if (storeQty > 0)
            {'batchNo': 'INIT-Store', 'qty': storeQty, 'location': _storeLocation},
          if (warehouseQty > 0)
            {'batchNo': 'INIT-Warehouse', 'qty': warehouseQty, 'location': _warehouseLocation},
        ] else ...customBatches.map((b) => b.toMap()),
      ];
      tx.set(doc, {
        'storeId': storeId,
        'sku': sku,
        'barcode': barcode ?? '',
        'name': name,
        'description': description,
        'unitPrice': unitPrice,
        'mrpPrice': mrpPrice,
        'costPrice': costPrice,
        'taxPct': taxPct,
        'discountPct': discountPct,
        'variants': (variants ?? const <String>[]).where((v) => v.trim().isNotEmpty).toList(),
        'imageUrls': (imageUrls ?? const <String>[]).where((u) => u.trim().isNotEmpty).toList(),
        'height': height,
        'width': width,
        'weight': weight,
        'volumeMl': volumeMl,
        'minStock': minStock,
        'category': category,
        'subCategory': subCategory,
        'quantityPerUnit': quantityPerUnit,
        'categoryId': null,
        'supplierId': null,
        'isActive': isActive,
        'batches': batches,
      });
    });
  }

  Future<void> updateProduct({
    required String storeId,
    required String sku,
    String? name,
    double? unitPrice,
    num? taxPct,
    String? barcode,
    String? description,
    List<String>? variants,
    List<String>? imageUrls,
    double? mrpPrice,
    double? costPrice,
    num? discountPct,
    String? category,
    String? subCategory,
    String? quantityPerUnit,
    double? height,
    double? width,
    double? weight,
    double? volumeMl,
    int? minStock,
    bool? isActive,
  }) async {
    final doc = StoreRefs.of(storeId, fs: _db).products().doc(sku);
    final data = <String, dynamic>{};
    void put(String k, dynamic v) {
      if (v != null) data[k] = v;
    }

    put('name', name);
    put('unitPrice', unitPrice);
    put('taxPct', taxPct);
    put('barcode', barcode);
    put('description', description);
    put('mrpPrice', mrpPrice);
    put('costPrice', costPrice);
    put('discountPct', discountPct);
    put('height', height);
    put('width', width);
    put('weight', weight);
    put('volumeMl', volumeMl);
    put('minStock', minStock);
    put('category', category);
    put('subCategory', subCategory);
    put('quantityPerUnit', quantityPerUnit);
    put('isActive', isActive);
    if (variants != null) {
      data['variants'] = variants.where((v) => v.trim().isNotEmpty).toList();
    }
    if (imageUrls != null) {
      data['imageUrls'] = imageUrls.where((u) => u.trim().isNotEmpty).toList();
    }
    if (data.isNotEmpty) await doc.update(data);
  }

  Future<void> deleteProduct({required String storeId, required String sku}) async {
    await StoreRefs.of(storeId, fs: _db).products().doc(sku).delete();
  }

  // -------------------- Audit Overwrite --------------------
  Future<void> auditUpdateStock({
    required String storeId,
    required String sku,
    required int storeQty,
    required int warehouseQty,
    String? updatedBy,
    String? note,
  }) async {
    final doc = StoreRefs.of(storeId, fs: _db).products().doc(sku);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(doc);
      if (!snap.exists) throw StateError('Product $sku does not exist');
      final data = snap.data() as Map<String, dynamic>;
      final existing = (data['batches'] as List?)?.whereType<Map>().toList() ?? <Map>[];
      final kept = existing
          .where((b) {
            final loc = (b['location'] ?? '') as String;
            return loc != _storeLocation && loc != _warehouseLocation;
          })
          .toList();
      if (storeQty > 0) {
        kept.add({'batchNo': 'AUDIT-Store', 'qty': storeQty, 'location': _storeLocation});
      }
      if (warehouseQty > 0) {
        kept.add({'batchNo': 'AUDIT-Warehouse', 'qty': warehouseQty, 'location': _warehouseLocation});
      }
      tx.update(doc, {
        'batches': kept,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': updatedBy,
        'auditNote': note,
      });
    });
  }

  // -------------------- Import / Upsert --------------------
  Future<UpsertOutcome> upsertProductFromImport({
    required String storeId,
    required String sku,
    required String name,
    required double unitPrice,
    num? taxPct,
    String? barcode,
    String? description,
    List<String>? variants,
    double? mrpPrice,
    double? costPrice,
    required bool isActive,
    required int storeQty,
    required int warehouseQty,
    String? supplierId,
    List<BatchDoc>? customBatches,
  }) async {
    if (barcode != null && barcode.trim().isNotEmpty) {
      final dup = await StoreRefs.of(storeId, fs: _db)
          .products()
          .where('barcode', isEqualTo: barcode)
          .limit(1)
          .get();
      if (dup.docs.isNotEmpty && dup.docs.first.id != sku) {
        throw StateError('Duplicate barcode: $barcode already used by SKU ${dup.docs.first.id}');
      }
    }
    final doc = StoreRefs.of(storeId, fs: _db).products().doc(sku);
    return _db.runTransaction<UpsertOutcome>((tx) async {
      final snap = await tx.get(doc);
      final batchesNew = <Map<String, dynamic>>[
        if (customBatches == null || customBatches.isEmpty) ...[
          if (storeQty > 0)
            {'batchNo': 'IMPORT-Store', 'qty': storeQty, 'location': _storeLocation},
          if (warehouseQty > 0)
            {'batchNo': 'IMPORT-Warehouse', 'qty': warehouseQty, 'location': _warehouseLocation},
        ] else ...customBatches.map((b) => b.toMap()),
      ];
      if (snap.exists) {
        final data = <String, dynamic>{
          'name': name,
          'unitPrice': unitPrice,
          'taxPct': taxPct,
          'barcode': barcode ?? '',
          'description': description,
          'variants': (variants ?? const <String>[]).where((v) => v.trim().isNotEmpty).toList(),
          'mrpPrice': mrpPrice,
          'costPrice': costPrice,
          'isActive': isActive,
          'supplierId': supplierId,
        };
        if (isActive) data['batches'] = batchesNew;
        tx.update(doc, data);
        return UpsertOutcome.updated;
      } else {
        tx.set(doc, {
          'storeId': storeId,
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
          'supplierId': supplierId,
          'isActive': isActive,
          'batches': isActive ? batchesNew : [],
        });
        return UpsertOutcome.added;
      }
    });
  }

  // -------------------- Lookup --------------------
  Future<ProductDoc?> getProduct(String storeId, String sku) async {
    final d = await StoreRefs.of(storeId, fs: _db).products().doc(sku).get();
    if (!d.exists) return null;
    return ProductDoc.fromDoc(d);
  }

  // -------------------- Incremental Movement --------------------
  Future<void> applyStockMovement({
    required String storeId,
    required String sku,
    required String location,
    required int deltaQty,
    required String type, // kept for potential future audit trail
    String? note, // (not persisted yet, placeholder for future history collection)
    String? updatedBy,
  }) async {
    assert(location == _storeLocation || location == _warehouseLocation);
    final doc = StoreRefs.of(storeId, fs: _db).products().doc(sku);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(doc);
      if (!snap.exists) throw StateError('Product $sku does not exist');
      final data = snap.data() as Map<String, dynamic>;
      final list = (data['batches'] as List?)?.whereType<Map>().toList() ?? <Map>[];
      int store = 0;
      int wh = 0;
      final others = <Map<String, dynamic>>[];
      for (final b in list) {
        final loc = (b['location'] ?? '') as String;
        final q = (b['qty'] is int)
            ? b['qty'] as int
            : (b['qty'] is num ? (b['qty'] as num).toInt() : 0);
        if (loc == _storeLocation) {
          store += q;
        } else if (loc == _warehouseLocation) {
          wh += q;
        } else {
          // Ensure typing; Firestore returns Map<String,dynamic>, but cast defensively
          others.add(Map<String, dynamic>.from(b));
        }
      }
      if (location == _storeLocation) {
        store += deltaQty;
        if (store < 0) throw StateError('Store stock would become negative');
      } else {
        wh += deltaQty;
        if (wh < 0) throw StateError('Warehouse stock would become negative');
      }
      final newBatches = <Map<String, dynamic>>[...others];
      if (store > 0) {
        newBatches.add({'batchNo': 'MOVE-Store', 'qty': store, 'location': _storeLocation});
      }
      if (wh > 0) {
        newBatches.add({'batchNo': 'MOVE-Warehouse', 'qty': wh, 'location': _warehouseLocation});
      }
      tx.update(doc, {
        'batches': newBatches,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': updatedBy,
      });
    });
  }

  // -------------------- Stock Transfer (Store <-> Warehouse) --------------------
  Future<void> applyTransfer({
    required String storeId,
    required String sku,
    required String from,
    required String to,
    required int qty,
    String? updatedBy,
  }) async {
    assert(qty > 0, 'Transfer qty must be positive');
    const store = _storeLocation;
    const wh = _warehouseLocation;
    if (!{store, wh}.contains(from) || !{store, wh}.contains(to) || from == to) {
      throw ArgumentError('Invalid from/to locations');
    }
  final doc = StoreRefs.of(storeId, fs: _db).products().doc(sku);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(doc);
      if (!snap.exists) throw StateError('Product $sku does not exist');
      final data = snap.data() as Map<String, dynamic>;
      final list = (data['batches'] as List?)?.whereType<Map>().toList() ?? <Map>[];
      int storeQty = 0;
      int whQty = 0;
      final others = <Map<String, dynamic>>[];
      for (final b in list) {
        final loc = (b['location'] ?? '') as String;
        final q = (b['qty'] is int)
            ? b['qty'] as int
            : (b['qty'] is num ? (b['qty'] as num).toInt() : 0);
        if (loc == store) {
          storeQty += q;
        } else if (loc == wh) {
          whQty += q;
        } else {
          others.add(Map<String, dynamic>.from(b));
        }
      }
      if (from == store) {
        if (storeQty < qty) throw StateError('Not enough stock in Store to transfer');
        storeQty -= qty;
        whQty += qty;
      } else { // from warehouse
        if (whQty < qty) throw StateError('Not enough stock in Warehouse to transfer');
        whQty -= qty;
        storeQty += qty;
      }
      final newBatches = <Map<String, dynamic>>[...others];
      if (storeQty > 0) newBatches.add({'batchNo': 'MOVE-Store', 'qty': storeQty, 'location': store});
      if (whQty > 0) newBatches.add({'batchNo': 'MOVE-Warehouse', 'qty': whQty, 'location': wh});
      tx.update(doc, {
        'batches': newBatches,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': updatedBy,
      });
    });
  }
}

// -------------------- Models --------------------
enum UpsertOutcome { added, updated }

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
  final num? discountPct;
  final String? category;
  final String? subCategory;
  final String? quantityPerUnit;
  final int? minStock;
  final List<String> variants;
  final double? height;
  final double? width;
  final double? weight;
  final double? volumeMl;
  final List<String> imageUrls;
  final String? categoryId;
  final String? supplierId;
  final bool isActive;
  final List<BatchDoc> batches;
  final DateTime? updatedAt;
  final String? updatedBy;
  final String? auditNote;

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
    this.discountPct,
    this.category,
    this.subCategory,
    this.quantityPerUnit,
    this.minStock,
    required this.variants,
    this.height,
    this.width,
    this.weight,
    this.volumeMl,
    required this.imageUrls,
    this.categoryId,
    this.supplierId,
    required this.isActive,
    required this.batches,
    this.updatedAt,
    this.updatedBy,
    this.auditNote,
  });

  int get totalStock => batches.fold(0, (p, b) => p + (b.qty ?? 0));
  int stockAt(String location) => batches
      .where((b) => (b.location ?? '') == location)
      .fold(0, (p, b) => p + (b.qty ?? 0));

  static ProductDoc fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const {};
    final rawBatches = (m['batches'] as List?)
            ?.map((e) => BatchDoc.fromMap(e))
            .whereType<BatchDoc>()
            .toList() ??
        const <BatchDoc>[];
    double toDoubleLocal(dynamic v) {
      if (v == null) return 0.0;
      if (v is double) return v;
      if (v is int) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }
    return ProductDoc(
      id: d.id,
      tenantId: (m['tenantId'] ?? '') as String,
      sku: (m['sku'] ?? '') as String,
      barcode: (m['barcode'] ?? '') as String,
      name: (m['name'] ?? '') as String,
      description: m['description'] as String?,
      unitPrice: toDoubleLocal(m['unitPrice']),
      mrpPrice: m['mrpPrice'] == null ? null : toDoubleLocal(m['mrpPrice']),
      costPrice: m['costPrice'] == null ? null : toDoubleLocal(m['costPrice']),
      taxPct: m['taxPct'] as num?,
      discountPct: m['discountPct'] as num?,
      category: m['category'] as String?,
      subCategory: m['subCategory'] as String?,
      quantityPerUnit: m['quantityPerUnit'] as String?,
      minStock: (m['minStock'] is int)
          ? m['minStock'] as int
          : (m['minStock'] is num ? (m['minStock'] as num).toInt() : null),
      variants: (m['variants'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[],
      height: m['height'] == null ? null : toDoubleLocal(m['height']),
      width: m['width'] == null ? null : toDoubleLocal(m['width']),
      weight: m['weight'] == null ? null : toDoubleLocal(m['weight']),
      volumeMl: m['volumeMl'] == null ? null : toDoubleLocal(m['volumeMl']),
      imageUrls: (m['imageUrls'] as List?)?.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList() ?? const <String>[],
      categoryId: m['categoryId'] as String?,
      supplierId: m['supplierId'] as String?,
      isActive: (m['isActive'] ?? true) as bool,
      batches: rawBatches,
      updatedAt: m['updatedAt'] is Timestamp ? (m['updatedAt'] as Timestamp).toDate() : null,
      updatedBy: m['updatedBy'] as String?,
      auditNote: m['auditNote'] as String?,
    );
  }
}

class BatchDoc {
  final String? batchNo;
  final DateTime? expiry;
  final int? qty;
  final String? location;
  BatchDoc({this.batchNo, this.expiry, this.qty, this.location});

  Map<String, dynamic> toMap() => {
        'batchNo': batchNo,
        'qty': qty,
        'location': location,
        if (expiry != null) 'expiry': Timestamp.fromDate(expiry!),
      };

  static BatchDoc fromMap(dynamic m) {
    if (m is! Map) return BatchDoc();
    final expiry = m['expiry'];
    return BatchDoc(
      batchNo: m['batchNo']?.toString(),
      expiry: expiry is Timestamp
          ? expiry.toDate()
          : (expiry is DateTime ? expiry : null),
      qty: (m['qty'] is String)
          ? int.tryParse(m['qty'])
          : (m['qty'] as num?)?.toInt(),
      location: m['location']?.toString(),
    );
  }
}
