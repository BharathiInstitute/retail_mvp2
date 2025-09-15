import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/mock_services.dart';

class PosScreen extends ConsumerWidget {
  const PosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(productsProvider);
    final cart = ref.watch(cartProvider);
    final cartTotal = ref.read(cartProvider.notifier).total;

    return Row(children: [
      Expanded(
        flex: 3,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: products.when(
            data: (items) => GridView.extent(
              maxCrossAxisExtent: 220,
              childAspectRatio: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                for (final p in items)
                  ElevatedButton(
                    onPressed: () => ref.read(cartProvider.notifier).add(p),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [Text(p.name), Text('₹${p.price.toStringAsFixed(0)}')],
                    ),
                  ),
              ],
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
          ),
        ),
      ),
      VerticalDivider(width: 1, color: Theme.of(context).dividerColor),
      Expanded(
        flex: 2,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Cart (${cart.length})', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  for (final item in cart)
                    ListTile(
                      title: Text(item.product.name),
                      subtitle: Text('Qty: ${item.qty}'),
                      trailing: Text('₹${(item.product.price * item.qty).toStringAsFixed(0)}'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Discount'),
              FilledButton.tonal(onPressed: () {}, child: const Text('Apply')),
            ]),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Total'),
              Text('₹${cartTotal.toStringAsFixed(0)}', style: Theme.of(context).textTheme.titleLarge),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.preview), label: const Text('Invoice Preview'))),
              const SizedBox(width: 8),
              Expanded(child: FilledButton.icon(onPressed: () {}, icon: const Icon(Icons.payment), label: const Text('Pay'))),
            ]),
          ]),
        ),
      ),
    ]);
  }
}
