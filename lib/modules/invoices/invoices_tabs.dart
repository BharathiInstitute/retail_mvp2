import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'invoices.dart';
import 'purchse_invoice.dart';
import 'package:retail_mvp2/dev/gstr3b_demo_seed.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Persist the last selected tab index across navigation using Riverpod.
final invoicesTabIndexProvider = StateProvider<int>((ref) => 0);

class InvoicesTabsScreen extends ConsumerStatefulWidget {
  const InvoicesTabsScreen({super.key});
  @override
  ConsumerState<InvoicesTabsScreen> createState() => _InvoicesTabsScreenState();
}

class _InvoicesTabsScreenState extends ConsumerState<InvoicesTabsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    final initial = ref.read(invoicesTabIndexProvider);
    _tabController = TabController(length: 2, vsync: this, initialIndex: initial);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return; // wait until settled
      final current = ref.read(invoicesTabIndexProvider);
      if (current != _tabController.index) {
        ref.read(invoicesTabIndexProvider.notifier).state = _tabController.index;
      }
    });
  }

  @override
  void didUpdateWidget(covariant InvoicesTabsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If provider changed externally (unlikely), sync controller.
    final target = ref.read(invoicesTabIndexProvider);
    if (target != _tabController.index) {
      _tabController.index = target;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TabBar(
          controller: _tabController,
          isScrollable: false,
          tabs: const [
            Tab(text: 'Sales'),
            Tab(text: 'Purchases'),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [
              _SalesTab(),
              _PurchasesTab(),
            ],
          ),
        ),
      ],
    );
  }
}

class _SalesTab extends StatelessWidget {
  const _SalesTab();
  Future<void> _seed(BuildContext context) async {
    try {
      await seedGstr3bDemoData();
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Demo sales invoices seeded.')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Seed failed: $e')));
    }
  }
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(onPressed: () => _seed(context), icon: const Icon(Icons.cloud_download_outlined), label: const Text('Seed Demo Invoices')),
          FilledButton.tonalIcon(onPressed: () async {
            if (!context.mounted) return;
            showDialog(context: context, builder: (_) => const AlertDialog(
              title: Text('GSTR-3B Summary'),
              content: Text('GST computation service removed. Reintroduce gstr3b_service.dart to enable.'),
            ));
          }, icon: const Icon(Icons.summarize_outlined), label: const Text('Compute GSTR-3B (Disabled)')),
        ]),
        const SizedBox(height: 12),
        const Expanded(child: InvoicesListScreen()),
      ]),
    );
  }
}

class _PurchasesTab extends StatelessWidget {
  const _PurchasesTab();
  Future<void> _seedPurchases(BuildContext context) async {
    try {
      await seedGstr3bDemoData();
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Demo purchase invoices seeded (shared seed).')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Seed failed: $e')));
    }
  }

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
            OutlinedButton.icon(onPressed: () => _seedPurchases(context), icon: const Icon(Icons.cloud_download_outlined), label: const Text('Seed Demo Purchases')),
          ]),
          const SizedBox(height: 12),
          Expanded(child: _PurchasesList()),
        ],
      ),
    );
  }
}

class _PurchasesList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance
      .collection('purchase_invoices')
      .orderBy('timestampMs', descending: true)
      .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
  final docs = snapshot.data!.docs; // show all
        if (docs.isEmpty) {
          return Card(
            child: Center(
              child: Text(
                'No purchases yet. Create the first one.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          );
        }
        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final data = docs[i].data();
            final supplier = (data['supplier'] ?? '') as String;
            final type = (data['type'] ?? '') as String;
            final grand = (data['summary']?['grandTotal'] ?? 0).toDouble();
            final createdAt = (data['createdAt'] ?? '').toString();
            final invoiceNo = (data['invoiceNo'] ?? '') as String;
            final dateStr = createdAt.split('T').first;
            final titleParts = <String>[];
            if (invoiceNo.isNotEmpty) titleParts.add('#$invoiceNo');
            titleParts.add(supplier.isEmpty ? 'Unknown Supplier' : supplier);
            return ListTile(
              leading: const Icon(Icons.receipt_long),
              title: Text(titleParts.join(' • ')),
              subtitle: Text('$type • ₹${grand.toStringAsFixed(2)} • $dateStr'),
              onTap: () => _showPurchaseDetails(context, docs[i].id, data),
            );
          },
        );
      },
    );
  }
}

void _showPurchaseDetails(BuildContext listContext, String docId, Map<String, dynamic> data) {
  showDialog(
    context: listContext,
    builder: (dialogCtx) {
      final items = (data['items'] as List?)?.whereType<Map>().toList() ?? const <Map>[];
      final summary = (data['summary'] as Map?) ?? const {};
      final payment = (data['payment'] as Map?) ?? const {};
      final utility = (data['utility'] as Map?) ?? const {};
      String money(v) {
        if (v == null) return '0.00';
        if (v is num) return v.toStringAsFixed(2);
        final d = double.tryParse(v.toString()) ?? 0; return d.toStringAsFixed(2);
      }
      return AlertDialog(
        title: Row(
          children: [
            const Text('Purchase Details'),
            const Spacer(),
            if ((data['invoiceNo'] ?? '').toString().isNotEmpty)
              Chip(label: Text('#${data['invoiceNo']}')),
          ],
        ),
        content: SizedBox(
          width: 720,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detailRow('Supplier', data['supplier']),
                _detailRow('Type', data['type']),
                _detailRow('Invoice Date', (data['invoiceDate'] ?? '').toString().split('T').first),
                const SizedBox(height: 12),
                Text('Items', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                if (items.isEmpty)
                  const Text('No item lines'),
                if (items.isNotEmpty)
                  Table(
                    columnWidths: const {
                      0: FlexColumnWidth(4),
                      1: FlexColumnWidth(1),
                      2: FlexColumnWidth(2),
                      3: FlexColumnWidth(2),
                    },
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    children: [
                      const TableRow(children: [
                        Padding(padding: EdgeInsets.all(4), child: Text('Item', style: TextStyle(fontWeight: FontWeight.bold))),
                        Padding(padding: EdgeInsets.all(4), child: Text('Qty', style: TextStyle(fontWeight: FontWeight.bold))),
                        Padding(padding: EdgeInsets.all(4), child: Text('Unit Price', style: TextStyle(fontWeight: FontWeight.bold))),
                        Padding(padding: EdgeInsets.all(4), child: Text('Amount', style: TextStyle(fontWeight: FontWeight.bold))),
                      ]),
                      for (final it in items) TableRow(children: [
                        Padding(padding: const EdgeInsets.all(4), child: Text('${it['name'] ?? ''}')),
                        Padding(padding: const EdgeInsets.all(4), child: Text('${it['qty'] ?? ''}')),
                        Padding(padding: const EdgeInsets.all(4), child: Text('₹${money(it['unitPrice'])}')),
                        Padding(padding: const EdgeInsets.all(4), child: Text('₹${money(((it['qty'] ?? 0) as num) * ((it['unitPrice'] ?? 0) as num))}')),
                      ]),
                    ],
                  ),
                const SizedBox(height: 16),
                Text('Summary', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Wrap(spacing: 12, runSpacing: 6, children: [
                  _chip('Grand Total', '₹${money(summary['grandTotal'])}'),
                  if (summary['cgst'] != null) _chip('CGST', '₹${money(summary['cgst'])}'),
                  if (summary['sgst'] != null) _chip('SGST', '₹${money(summary['sgst'])}'),
                  if (summary['igst'] != null) _chip('IGST', '₹${money(summary['igst'])}'),
                  if (summary['cess'] != null) _chip('CESS', '₹${money(summary['cess'])}'),
                ]),
                const SizedBox(height: 16),
                Text('Payment', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Wrap(spacing: 12, runSpacing: 6, children: [
                  _chip('Paid', '₹${money(payment['paid'])}'),
                  _chip('Balance', '₹${money(payment['balance'])}'),
                ]),
                const SizedBox(height: 16),
                if (utility.isNotEmpty) ...[
                  Text('Utility', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  _detailRow('Amount', '₹${money(utility['amount'])}'),
                  if ((utility['notes'] ?? '').toString().isNotEmpty) _detailRow('Notes', utility['notes']),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Close')),
          FilledButton.icon(
            onPressed: () {
              // Close details then open edit dialog using original list context (prevents blank flash)
              Navigator.of(dialogCtx).pop();
              Future.microtask(() => showEditPurchaseInvoiceDialog(listContext, docId, data));
            },
            icon: const Icon(Icons.edit),
            label: const Text('Edit'),
          ),
        ],
      );
    },
  );
}

Widget _detailRow(String label, dynamic value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2.0),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 140, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
        Expanded(child: Text(value == null || value.toString().isEmpty ? '-' : value.toString())),
      ],
    ),
  );
}

Widget _chip(String label, String value) {
  return Chip(label: Text('$label: $value'));
}

// Old card widget removed in favor of simple ListTile view.
