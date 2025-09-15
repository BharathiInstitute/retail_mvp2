import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';

class MockDataService {
  final _products = <Product>[
    const Product(id: 'p1', name: 'T-Shirt', price: 499.0, stock: 42),
    const Product(id: 'p2', name: 'Jeans', price: 1199.0, stock: 18),
    const Product(id: 'p3', name: 'Sneakers', price: 2999.0, stock: 9),
  ];

  final _customers = <Customer>[
    const Customer(id: 'c1', name: 'Alice', loyaltyPoints: 120),
    const Customer(id: 'c2', name: 'Bob', loyaltyPoints: 60),
  ];

  final _invoices = <Invoice>[
    Invoice(id: 'inv1', amount: 1599.0, date: DateTime.now().subtract(const Duration(days: 1))),
    Invoice(id: 'inv2', amount: 2999.0, date: DateTime.now().subtract(const Duration(days: 3))),
  ];

  Stream<List<Product>> productsStream() async* {
    yield _products;
  }

  Stream<List<Customer>> customersStream() async* {
    yield _customers;
  }

  Stream<List<Invoice>> invoicesStream() async* {
    yield _invoices;
  }
}

final mockDataServiceProvider = Provider<MockDataService>((ref) => MockDataService());

class CartItem {
  final Product product;
  final int qty;
  const CartItem(this.product, this.qty);
}

class CartNotifier extends StateNotifier<List<CartItem>> {
  CartNotifier() : super(const []);

  void add(Product p) {
    final idx = state.indexWhere((e) => e.product.id == p.id);
    if (idx == -1) {
      state = [...state, CartItem(p, 1)];
    } else {
      final updated = [...state];
      updated[idx] = CartItem(p, updated[idx].qty + 1);
      state = updated;
    }
  }

  void remove(Product p) {
    state = state.where((e) => e.product.id != p.id).toList();
  }

  double get total => state.fold(0, (sum, e) => sum + e.product.price * e.qty);
  int get count => state.fold(0, (sum, e) => sum + e.qty);
}

final cartProvider = StateNotifierProvider<CartNotifier, List<CartItem>>((ref) => CartNotifier());

final productsProvider = StreamProvider.autoDispose((ref) {
  return ref.watch(mockDataServiceProvider).productsStream();
});

final customersProvider = StreamProvider.autoDispose((ref) {
  return ref.watch(mockDataServiceProvider).customersStream();
});

final invoicesProvider = StreamProvider.autoDispose((ref) {
  return ref.watch(mockDataServiceProvider).invoicesStream();
});
