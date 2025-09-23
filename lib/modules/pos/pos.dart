// POS domain models, enums, and simple data holders.
// UI has been moved to pos_ui.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class Product {
  final String sku;
  final String name;
  final double price;
  int stock;
  final int taxPercent; // GST % from taxPct
  final String? barcode;
  final DocumentReference<Map<String, dynamic>>? ref;

  Product({
    required this.sku,
    required this.name,
    required this.price,
    required this.stock,
    required this.taxPercent,
    this.barcode,
    this.ref,
  });

  factory Product.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final priceRaw = data['unitPrice'];
    final price = priceRaw is num ? priceRaw.toDouble() : double.tryParse('$priceRaw') ?? 0.0;
    // Compute stock from batches list if provided
    int stock = 0;
    final batches = data['batches'];
    if (batches is List) {
      for (final b in batches) {
        if (b is Map && b['qty'] != null) {
          final q = b['qty'];
          if (q is num) {
            stock += q.toInt();
          } else if (q is String) {
            stock += int.tryParse(q) ?? 0;
          }
        }
      }
    }
    final taxRaw = data['taxPct'];
    final tax = taxRaw is num ? taxRaw.toInt() : int.tryParse('$taxRaw') ?? 0;
    return Product(
      sku: (data['sku'] ?? doc.id).toString(),
      name: (data['name'] ?? '').toString(),
      price: price,
      stock: stock,
      taxPercent: tax,
      barcode: (data['barcode'] ?? '').toString(),
      ref: doc.reference,
    );
  }
}

class Customer {
  final String id; // empty id for Walk-in
  final String name;
  final String? email;
  final String? phone;
  final String? status; // loyalty tier e.g. bronze/silver/gold
  final double totalSpend;
  final double rewardsPoints; // allow fractional points
  final double discountPercent; // derived suggested discount

  Customer({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    this.status,
    this.totalSpend = 0.0,
  this.rewardsPoints = 0.0,
    this.discountPercent = 0.0,
  });

  factory Customer.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    String name = (data['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) name = 'Unnamed';
    final tier = (data['status'] as String?)?.toLowerCase();
    final spendRaw = data['totalSpend'];
    final spend = spendRaw is num ? spendRaw.toDouble() : double.tryParse('$spendRaw') ?? 0.0;
    // Use stored loyaltyPoints if present, else fallback
  double rewards = 0;
    final lp = data['loyaltyPoints'];
    if (lp is num) {
      rewards = lp.toDouble();
    } else if (lp is String) {
      rewards = double.tryParse(lp) ?? 0;
    } else {
      rewards = (spend / 100).floorToDouble();
    }
    // Discount may be stored explicitly (loyaltyDiscount) or derived from tier
    double discount = 0;
    final loyaltyDisc = data['loyaltyDiscount'];
    if (loyaltyDisc is num) {
      discount = loyaltyDisc.toDouble();
    } else {
      switch (tier) {
        case 'gold':
          discount = 10; break;
        case 'silver':
          discount = 5; break;
        case 'bronze':
          discount = 2; break;
        default:
          discount = 0;
      }
    }
  return Customer(
      id: doc.id,
      name: name,
      email: (data['email'] as String?)?.trim(),
      phone: (data['phone'] as String?)?.trim(),
      status: tier,
      totalSpend: spend,
      rewardsPoints: rewards,
      discountPercent: discount,
    );
  }
}

class CartItem {
  final Product product;
  final int qty;
  CartItem({required this.product, required this.qty});
  CartItem copyWith({Product? product, int? qty}) => CartItem(product: product ?? this.product, qty: qty ?? this.qty);
  CartItem copy() => CartItem(product: product, qty: qty);
}

class HeldOrder {
  final String id;
  final DateTime timestamp;
  final List<CartItem> items;
  final DiscountType discountType;
  final String discountValueText;
  HeldOrder({required this.id, required this.timestamp, required this.items, required this.discountType, required this.discountValueText});
}

enum PaymentMode { cash, upi, card, wallet }

extension PaymentModeX on PaymentMode {
  String get label => switch (this) { PaymentMode.cash => 'Cash', PaymentMode.upi => 'UPI', PaymentMode.card => 'Card', PaymentMode.wallet => 'Wallet' };
}

// Payment split model removed

enum DiscountType { none, percent, flat }

extension DiscountTypeX on DiscountType {
  String get label => switch (this) { DiscountType.none => 'None', DiscountType.percent => 'Percent %', DiscountType.flat => 'Flat ₹' };
}



