import 'package:flutter/material.dart';
import 'pos.dart';
import '../../core/theme/theme_extension_helpers.dart';

/// Minimal checkout UI for the tab screen: hides totals/calculations.
/// When the user taps Checkout, a sheet pops up to select Cash or UPI.
class SimpleCheckoutTab extends StatelessWidget {
  final ValueChanged<PaymentMode>? onModeSelected;
  final String title;
  const SimpleCheckoutTab({super.key, this.onModeSelected, this.title = 'Checkout'});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Customer', style: Theme.of(context).textTheme.titleSmall),
            context.gapVSm,
            // Placeholder for customer selection; intentionally minimal
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Walk-in Customer',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              child: const SizedBox.shrink(),
            ),
            context.gapVMd,
            ElevatedButton.icon(
              icon: const Icon(Icons.check_circle),
              label: Text(title),
              onPressed: () => _openPaymentSheet(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openPaymentSheet(BuildContext context) async {
    final scheme = Theme.of(context).colorScheme;
    await showModalBottomSheet<PaymentMode>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Select Payment Method', style: Theme.of(ctx).textTheme.titleMedium),
              context.gapVMd,
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx, PaymentMode.cash);
                  onModeSelected?.call(PaymentMode.cash);
                },
                style: FilledButton.styleFrom(backgroundColor: scheme.primary),
                icon: const Icon(Icons.payments),
                label: const Text('Cash'),
              ),
              context.gapVMd,
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx, PaymentMode.upi);
                  onModeSelected?.call(PaymentMode.upi);
                },
                icon: const Icon(Icons.qr_code),
                label: const Text('UPI'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
