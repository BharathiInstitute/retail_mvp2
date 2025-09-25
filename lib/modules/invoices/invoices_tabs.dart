import 'package:flutter/material.dart';
import 'invoices.dart';
import 'purchse_invoice.dart';

class InvoicesTabsScreen extends StatelessWidget {
  const InvoicesTabsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const TabBar(
            isScrollable: false,
            tabs: [
              Tab(text: 'Sales'),
              Tab(text: 'Purchases'),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TabBarView(
              children: const [
                // Sales tab reuses the existing invoices list UI
                InvoicesListScreen(),
                // Purchases tab provides entry to Purchase Invoice dialog
                _PurchasesTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PurchasesTab extends StatelessWidget {
  const _PurchasesTab();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            FilledButton.icon(
              onPressed: () => showPurchaseInvoiceDialog(context),
              icon: const Icon(Icons.add_shopping_cart),
              label: const Text('New Purchase Invoice'),
            ),
          ]),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              child: Center(
                child: Text(
                  'No purchases to show yet. Use "New Purchase Invoice" to create one.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
