import 'package:flutter/material.dart';

class LoyaltyScreen extends StatelessWidget {
  const LoyaltyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Loyalty', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Card(child: ListTile(title: Text('Rules'), subtitle: Text('TODO: Define earning and redemption rules'))),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.separated(
            itemCount: 5,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (context, index) => ListTile(
              leading: const Icon(Icons.star_outline),
              title: Text('Txn #$index'),
              subtitle: const Text('+10 pts'),
            ),
          ),
        ),
      ]),
    );
  }
}
