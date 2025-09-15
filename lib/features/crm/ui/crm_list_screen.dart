import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/mock_services.dart';

class CrmListScreen extends ConsumerWidget {
  const CrmListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customers = ref.watch(customersProvider);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: customers.when(
        data: (list) => ListView.separated(
          itemCount: list.length,
          separatorBuilder: (_, __) => const Divider(),
          itemBuilder: (context, index) {
            final c = list[index];
            return ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(c.name),
              subtitle: Text('Loyalty: ${c.loyaltyPoints} pts'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {},
            );
          },
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}
