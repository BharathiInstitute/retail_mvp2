import 'package:flutter/material.dart';
import 'invoices.dart';
import 'purchse_invoice.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
              title: Text('${titleParts.join(' • ')}'),
              subtitle: Text('${type} • ₹${grand.toStringAsFixed(2)} • $dateStr'),
              onTap: () => _showPurchaseDetails(context, docs[i].id, data),
            );
          },
        );
      },
    );
  }
}

void _showPurchaseDetails(BuildContext context, String docId, Map<String, dynamic> data) {
  showDialog(
    context: context,
    builder: (_) {
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          FilledButton.icon(
            onPressed: () {
              final rootNavigator = Navigator.of(context, rootNavigator: true);
              final rootCtx = rootNavigator.context;
              Navigator.pop(context);
              // Defer opening the edit dialog to next frame to ensure previous dialog fully removed
              WidgetsBinding.instance.addPostFrameCallback((_) {
                showEditPurchaseInvoiceDialog(rootCtx, docId, data);
              });
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
