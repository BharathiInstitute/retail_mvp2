import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/mock_services.dart';

class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(productsProvider);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: products.when(
        data: (items) => DataTable(columns: const [
          DataColumn(label: Text('Product')),
          DataColumn(label: Text('Price')),
          DataColumn(label: Text('Stock')),
        ], rows: [
          for (final p in items)
            DataRow(cells: [
              DataCell(Text(p.name)),
              DataCell(Text('₹${p.price.toStringAsFixed(0)}')),
              DataCell(Text('${p.stock}')),
            ]),
        ]),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}
