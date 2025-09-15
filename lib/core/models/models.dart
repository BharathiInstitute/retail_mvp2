class Product {
  final String id;
  final String name;
  final double price;
  final int stock;
  const Product({required this.id, required this.name, required this.price, required this.stock});
}

class Customer {
  final String id;
  final String name;
  final int loyaltyPoints;
  const Customer({required this.id, required this.name, this.loyaltyPoints = 0});
}

class Invoice {
  final String id;
  final double amount;
  final DateTime date;
  const Invoice({required this.id, required this.amount, required this.date});
}
