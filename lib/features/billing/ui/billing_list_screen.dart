import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/mock_services.dart';

class BillingListScreen extends ConsumerWidget {
  final String? invoiceId; // for nested route placeholder
  const BillingListScreen({super.key, this.invoiceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoices = ref.watch(invoicesProvider);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Invoices', style: Theme.of(context).textTheme.headlineSmall),
            FilledButton.icon(onPressed: () {}, icon: const Icon(Icons.print), label: const Text('Print / Export')),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: invoices.when(
            data: (list) => ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, index) {
                final inv = list[index];
                return ListTile(
                  title: Text('Invoice #${inv.id}'),
                  subtitle: Text('Amount: ₹${inv.amount.toStringAsFixed(0)}  •  ${inv.date.toLocal()}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {},
                );
              },
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
          ),
        ),
      ]),
    );
  }
}
