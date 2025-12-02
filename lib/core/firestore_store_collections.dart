import 'package:cloud_firestore/cloud_firestore.dart';
import 'database_migration_mode.dart';

/// Centralized helpers for store-scoped collection references.
/// During migration with DataLayout.dual, prefer subcollections and allow callers
/// to optionally request top-level fallback reads.
class StoreRefs {
  final FirebaseFirestore _fs;
  final String storeId;
  const StoreRefs._(this._fs, this.storeId);

  factory StoreRefs.of(String storeId, {FirebaseFirestore? fs}) {
    return StoreRefs._(fs ?? FirebaseFirestore.instance, storeId);
  }

  CollectionReference<Map<String, dynamic>> products() {
    switch (kDataLayout) {
      case DataLayout.subcollections:
      case DataLayout.dual:
        return _fs.collection('stores').doc(storeId).collection('products');
      case DataLayout.topLevel:
        return _fs.collection('inventory');
    }
  }

  CollectionReference<Map<String, dynamic>> customers() {
    switch (kDataLayout) {
      case DataLayout.subcollections:
      case DataLayout.dual:
        return _fs.collection('stores').doc(storeId).collection('customers');
      case DataLayout.topLevel:
        return _fs.collection('customers');
    }
  }

  CollectionReference<Map<String, dynamic>> invoices() {
    switch (kDataLayout) {
      case DataLayout.subcollections:
      case DataLayout.dual:
        return _fs.collection('stores').doc(storeId).collection('invoices');
      case DataLayout.topLevel:
        return _fs.collection('invoices');
    }
  }

  CollectionReference<Map<String, dynamic>> purchaseInvoices() {
    switch (kDataLayout) {
      case DataLayout.subcollections:
      case DataLayout.dual:
        return _fs.collection('stores').doc(storeId).collection('purchase_invoices');
      case DataLayout.topLevel:
        return _fs.collection('purchase_invoices');
    }
  }

  CollectionReference<Map<String, dynamic>> stockMovements() {
    switch (kDataLayout) {
      case DataLayout.subcollections:
      case DataLayout.dual:
        return _fs.collection('stores').doc(storeId).collection('stock_movements');
      case DataLayout.topLevel:
        // Legacy top-level collection name was `inventory_movements`
        return _fs.collection('inventory_movements');
    }
  }

  CollectionReference<Map<String, dynamic>> suppliers() {
    switch (kDataLayout) {
      case DataLayout.subcollections:
      case DataLayout.dual:
        return _fs.collection('stores').doc(storeId).collection('suppliers');
      case DataLayout.topLevel:
        return _fs.collection('suppliers');
    }
  }

  CollectionReference<Map<String, dynamic>> alerts() {
    switch (kDataLayout) {
      case DataLayout.subcollections:
      case DataLayout.dual:
        return _fs.collection('stores').doc(storeId).collection('alerts');
      case DataLayout.topLevel:
        return _fs.collection('alerts');
    }
  }

  CollectionReference<Map<String, dynamic>> loyalty() {
    switch (kDataLayout) {
      case DataLayout.subcollections:
      case DataLayout.dual:
        return _fs.collection('stores').doc(storeId).collection('loyalty');
      case DataLayout.topLevel:
        return _fs.collection('loyalty');
    }
  }

  CollectionReference<Map<String, dynamic>> loyaltySettings() {
    switch (kDataLayout) {
      case DataLayout.subcollections:
      case DataLayout.dual:
        return _fs.collection('stores').doc(storeId).collection('loyalty_settings');
      case DataLayout.topLevel:
        return _fs.collection('loyalty_settings');
    }
  }
}
