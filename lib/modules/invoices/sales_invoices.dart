// Renamed from invoices.dart to sales_invoices.dart
// Content mirrors the original to avoid breakages.

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:retail_mvp2/core/theme/theme_utils.dart';

// Simple wrapper page used by router for Sales invoices
class SalesInvoicesScreen extends StatelessWidget {
  const SalesInvoicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: InvoicesListScreen(),
    );
  }
}

class InvoicesListScreen extends StatefulWidget {
  final String? invoiceId;
  const InvoicesListScreen({super.key, this.invoiceId});

  @override
  State<InvoicesListScreen> createState() => _InvoicesPageState();
}

class _InvoicesPageState extends State<InvoicesListScreen> {
  final List<Invoice> _invoicesCache = [];
  String query = '';
  String? statusFilter;
  DateTimeRange? dateRange;
  bool taxInclusive = true;

  Stream<List<Invoice>> get _invoiceStream => FirebaseFirestore.instance
      .collection('invoices')
      .orderBy('timestampMs', descending: true)
      .snapshots()
      .map((snap) {
        final list = <Invoice>[];
        for (final d in snap.docs) {
          final data = d.data();
          try {
            list.add(Invoice.fromFirestore(data, docId: d.id));
          } catch (_) {}
        }
        return list;
      });

  List<Invoice> filteredInvoices(List<Invoice> source) {
    return source.where((inv) {
      final q = query.trim().toLowerCase();
      final matchesQuery = q.isEmpty || inv.invoiceNo.toLowerCase().contains(q) || inv.customer.name.toLowerCase().contains(q);
      final matchesStatus = statusFilter == null || inv.status == statusFilter;
      final matchesDate = dateRange == null || (inv.date.isAfter(dateRange!.start.subtract(const Duration(days: 1))) && inv.date.isBefore(dateRange!.end.add(const Duration(days: 1))));
      return matchesQuery && matchesStatus && matchesDate;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 1100;
    return StreamBuilder<List<Invoice>>(
      stream: _invoiceStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error loading invoices: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!;
        _invoicesCache
          ..clear()
          ..addAll(data);
        final filtered = filteredInvoices(_invoicesCache);
        return Padding(
          padding: const EdgeInsets.all(12.0),
          child: isWide ? _wideLayout(filtered) : _narrowLayout(filtered),
        );
      },
    );
  }

  Widget _wideLayout(List<Invoice> list) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _searchFilterBar(),
          const SizedBox(height: 8),
          Expanded(child: _invoiceList(list: list)),
        ],
      );

  Widget _narrowLayout(List<Invoice> list) => ListView(
        children: [
          _searchFilterBar(),
          const SizedBox(height: 8),
          _invoiceList(list: list),
        ],
      );

  Widget _searchFilterBar() => Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 260,
            child: TextField(
              decoration: const InputDecoration(labelText: 'Search (invoice no / customer)', prefixIcon: Icon(Icons.search)),
              onChanged: (v) => setState(() => query = v),
            ),
          ),
          DropdownButton<String>(
            value: statusFilter,
            hint: const Text('Status'),
            items: const [
              DropdownMenuItem(value: 'Paid', child: Text('Paid')),
              DropdownMenuItem(value: 'Pending', child: Text('Pending')),
              DropdownMenuItem(value: 'Credit', child: Text('Credit')),
            ],
            onChanged: (v) => setState(() => statusFilter = v),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final now = DateTime.now();
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(now.year - 1),
                lastDate: DateTime(now.year + 1),
              );
              if (picked != null) setState(() => dateRange = picked);
            },
            icon: const Icon(Icons.date_range),
            label: Text(dateRange == null ? 'Date Range' : '${_fmtDate(dateRange!.start)} → ${_fmtDate(dateRange!.end)}'),
          ),
          OutlinedButton.icon(
            onPressed: () => setState(() {
              query = '';
              statusFilter = null;
              dateRange = null;
            }),
            icon: const Icon(Icons.clear),
            label: const Text('Clear'),
          ),
        ],
      );

  Widget _invoiceList({double? height, required List<Invoice> list}) {
    final listView = ListView.separated(
      itemCount: list.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final inv = list[i];
        final pm = (inv is InvoiceWithMode) ? inv.paymentMode : null;
        final subtitle = StringBuffer()
          ..write(_fmtDate(inv.date))
          ..write(' • ₹')
          ..write(inv.total(taxInclusive: taxInclusive).toStringAsFixed(2));
        if (pm != null && pm.isNotEmpty) {
          subtitle..write(' • ')..write(pm);
        }
        return ListTile(
          onTap: () => _showInvoiceDetails(inv),
          title: Text('Invoice #${inv.invoiceNo} • ${inv.customer.name}'),
          subtitle: Text(subtitle.toString()),
          trailing: _statusChip(inv.status),
        );
      },
    );
    final content = Card(child: Scrollbar(thumbVisibility: true, child: listView));
    return height != null ? SizedBox(height: height, child: content) : content;
  }

  Future<void> _showInvoiceDetails(Invoice inv) async {
    await showDialog(
      context: context,
      useRootNavigator: true,
      builder: (dialogCtx) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980, maxHeight: 720),
            child: StreamBuilder<Invoice>(
              stream: _singleInvoiceStream(inv),
              builder: (context, snap) {
                final current = snap.data ?? inv;
                return InvoiceDetailsContent(
                  invoice: current,
                  dialogCtx: dialogCtx,
                  taxInclusive: taxInclusive,
                  onDelete: (inv) => _deleteInvoice(inv, dialogCtx),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Stream<Invoice> _singleInvoiceStream(Invoice inv) {
    final col = FirebaseFirestore.instance.collection('invoices');
    if (inv.docId != null) {
      return col.doc(inv.docId).snapshots().where((d) => d.exists).map((d) {
        final data = d.data() as Map<String, dynamic>;
        return Invoice.fromFirestore(data, docId: d.id);
      });
    } else {
      return col.where('invoiceNumber', isEqualTo: inv.invoiceNo).limit(1).snapshots().map((qs) {
        if (qs.docs.isEmpty) return inv;
        final d = qs.docs.first;
        return Invoice.fromFirestore(d.data(), docId: d.id);
      });
    }
  }

  Widget _statusChip(String status) {
    final colors = context.colors;
    final app = context.appColors;
    Color c = colors.outline;
    if (status == 'Paid') c = app.success;
    if (status == 'Pending') c = app.warning;
    if (status == 'Credit') c = app.info;
    return Chip(
      label: Text(status, style: context.texts.labelMedium),
      backgroundColor: c.withValues(alpha: 0.15),
      side: BorderSide(color: c.withValues(alpha: 0.4)),
    );
  }

  Future<void> _deleteInvoice(Invoice inv, BuildContext dialogCtx) async {
    try {
      final col = FirebaseFirestore.instance.collection('invoices');
      if (inv.docId != null) {
        await col.doc(inv.docId).delete();
      } else {
        // Fallback to invoice number
        try {
          final q = await col.where('invoiceNumber', isEqualTo: inv.invoiceNo).limit(1).get();
          if (q.docs.isNotEmpty) {
            await q.docs.first.reference.delete();
          } else {
            await col.doc(inv.invoiceNo).delete();
          }
        } catch (_) {
          await col.doc(inv.invoiceNo).delete();
        }
      }
      if (context.mounted) {
        final messenger = ScaffoldMessenger.of(dialogCtx);
        messenger.showSnackBar(const SnackBar(content: Text('Invoice deleted')));
        // Close details dialog
        if (Navigator.of(dialogCtx, rootNavigator: true).canPop()) {
          Navigator.of(dialogCtx, rootNavigator: true).pop();
        }
      }
    } catch (e) {
      if (context.mounted) {
        final messenger = ScaffoldMessenger.of(dialogCtx);
        messenger.showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }
}

class InvoiceDetailsContent extends StatefulWidget {
  final Invoice invoice;
  final BuildContext dialogCtx;
  final bool taxInclusive;
  final Future<void> Function(Invoice inv) onDelete;
  const InvoiceDetailsContent({super.key, required this.invoice, required this.dialogCtx, required this.taxInclusive, required this.onDelete});

  @override
  State<InvoiceDetailsContent> createState() => _InvoiceDetailsContentState();
}

class _InvoiceDetailsContentState extends State<InvoiceDetailsContent> {
  bool editing = false;
  final List<_SalesItemRow> rows = [];

  @override
  void initState() {
    super.initState();
    _loadFromInvoice(widget.invoice);
  }

  @override
  void didUpdateWidget(covariant InvoiceDetailsContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!editing && (oldWidget.invoice != widget.invoice)) {
      rows.clear();
      _loadFromInvoice(widget.invoice);
      setState(() {});
    }
  }

  void _loadFromInvoice(Invoice inv) {
    for (final it in inv.items) {
      rows.add(_SalesItemRow(
        sku: it.product.sku,
        name: TextEditingController(text: it.product.name),
        qty: TextEditingController(text: it.qty.toString()),
        price: TextEditingController(text: it.product.price.toStringAsFixed(2)),
        taxPercent: it.product.taxPercent,
      ));
    }
    if (rows.isEmpty) {
      rows.add(_SalesItemRow(
        sku: '',
        name: TextEditingController(),
        qty: TextEditingController(text: '1'),
        price: TextEditingController(text: '0'),
        taxPercent: 0,
      ));
    }
  }

  @override
  void dispose() {
    for (final r in rows) { r.dispose(); }
    super.dispose();
  }

  double _toD(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0.0;
  int _toI(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  @override
  Widget build(BuildContext context) {
    final inv = widget.invoice;
    final gst = inv.gstBreakup(taxInclusive: widget.taxInclusive);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Invoice #${inv.invoiceNo} • ${_fmtDate(inv.date)} • ${inv.customer.name}',
                  style: context.texts.titleSmall?.copyWith(color: context.colors.onSurface, fontWeight: FontWeight.w600),
                ),
              ),
              if (!editing)
                FilledButton.icon(
                  onPressed: () => setState(() => editing = true),
                  icon: const Icon(Icons.edit),
                  label: const Text('Edit'),
                )
              else ...[
                TextButton(
                  onPressed: () => setState(() { editing = false; }),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _save,
                  child: const Text('Save'),
                ),
              ],
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: widget.dialogCtx,
                    builder: (ctx) => AlertDialog(
                      title: Text(
                        'Delete invoice?',
                        style: context.texts.titleMedium?.copyWith(color: context.colors.onSurface, fontWeight: FontWeight.w700),
                      ),
                      content: DefaultTextStyle(
                        style: (context.texts.bodyMedium ?? const TextStyle()).copyWith(color: context.colors.onSurface),
                        child: const Text('This will permanently delete this sales invoice. This action cannot be undone.'),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: context.colors.error, foregroundColor: context.colors.onError),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) await widget.onDelete(inv);
                },
                icon: Icon(Icons.delete_outline, color: context.colors.error),
                label: Text('Delete', style: TextStyle(color: context.colors.error)),
              ),
              const SizedBox(width: 8),
              _statusChip(inv.status),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(widget.dialogCtx, rootNavigator: true).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Divider(height: 1),
        Expanded(
          child: Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!editing)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTableTheme(
                        data: DataTableThemeData(
                          dataTextStyle: context.texts.bodySmall?.copyWith(color: context.colors.onSurface),
                          headingTextStyle: context.texts.bodySmall?.copyWith(color: context.colors.onSurface, fontWeight: FontWeight.w700),
                        ),
                        child: DataTable(
                        columns: const [
                          DataColumn(label: Text('SKU')),
                          DataColumn(label: Text('Item')),
                          DataColumn(label: Text('Qty')),
                          DataColumn(label: Text('Price')),
                          DataColumn(label: Text('GST %')),
                          DataColumn(label: Text('Line Total')),
                        ],
                        rows: [
                          for (final it in inv.items)
                            DataRow(cells: [
                              DataCell(Text(it.product.sku)),
                              DataCell(Text(it.product.name)),
                              DataCell(Text(it.qty.toString())),
                              DataCell(Text('₹${it.product.price.toStringAsFixed(2)}')),
                              DataCell(Text('${it.product.taxPercent}%')),
                              DataCell(Text('₹${it.lineTotal(taxInclusive: widget.taxInclusive).toStringAsFixed(2)}')),
                            ]),
                        ],
                          ),
                      ),
                    )
                  else ...[
                    Row(
                      children: [
                            Text(
                              'Items',
                              style: context.texts.titleSmall?.copyWith(color: context.colors.onSurface, fontWeight: FontWeight.w700),
                            ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Add Item',
                          onPressed: () => setState(() {
                            rows.add(_SalesItemRow(
                              sku: '',
                              name: TextEditingController(),
                              qty: TextEditingController(text: '1'),
                              price: TextEditingController(text: '0'),
                              taxPercent: 0,
                            ));
                          }),
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    for (int i = 0; i < rows.length; i++) _editRow(i),
                  ],
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 24,
                    runSpacing: 16,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('GST Breakup', style: context.texts.titleSmall?.copyWith(color: context.colors.onSurface, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          _kv('CGST', gst.cgst),
                          _kv('SGST', gst.sgst),
                          _kv('IGST', gst.igst),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Totals', style: context.texts.titleSmall?.copyWith(color: context.colors.onSurface, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          _kv('Tax Total', gst.totalTax),
                          const Divider(),
                          _kv('Grand Total', inv.total(taxInclusive: widget.taxInclusive), bold: true),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(widget.dialogCtx, rootNavigator: true).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _editRow(int index) {
    final r = rows[index];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: TextFormField(
              initialValue: r.sku,
              style: context.texts.bodyMedium?.copyWith(color: context.colors.onSurface),
              decoration: const InputDecoration(labelText: 'SKU'),
              onChanged: (v) => r.sku = v.trim(),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              controller: r.name,
              style: context.texts.bodyMedium?.copyWith(color: context.colors.onSurface),
              decoration: const InputDecoration(labelText: 'Item'),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: TextFormField(
              controller: r.qty,
              keyboardType: const TextInputType.numberWithOptions(decimal: false),
              style: context.texts.bodyMedium?.copyWith(color: context.colors.onSurface),
              decoration: const InputDecoration(labelText: 'Qty'),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            child: TextFormField(
              controller: r.price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: context.texts.bodyMedium?.copyWith(color: context.colors.onSurface),
              decoration: const InputDecoration(labelText: 'Unit Price ₹'),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 110,
            child: DropdownButtonFormField<int>(
              initialValue: r.taxPercent,
              style: context.texts.bodyMedium?.copyWith(color: context.colors.onSurface),
              items: const [0, 5, 12, 18, 28]
                  .map((v) => DropdownMenuItem(value: v, child: Text('GST $v%')))
                  .toList(),
              onChanged: (v) => setState(() => r.taxPercent = v ?? r.taxPercent),
              decoration: const InputDecoration(labelText: 'Tax Rate'),
              iconEnabledColor: context.colors.onSurfaceVariant,
              iconDisabledColor: context.colors.onSurface.withValues(alpha: 0.38),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Remove',
            onPressed: rows.length <= 1
                ? null
                : () => setState(() {
                      final rem = rows.removeAt(index);
                      rem.dispose();
                    }),
            icon: const Icon(Icons.close),
            color: context.colors.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  Widget _kv(String label, double value, {bool bold = false}) {
    final style = (context.texts.bodyMedium ?? const TextStyle())
        .copyWith(color: context.colors.onSurface, fontWeight: bold ? FontWeight.w700 : FontWeight.w400);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text('₹${value.toStringAsFixed(2)}', style: style),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    final colors = context.colors;
    final app = context.appColors;
    Color c = colors.outline;
    if (status == 'Paid') c = app.success;
    if (status == 'Pending') c = app.warning;
    if (status == 'Credit') c = app.info;
    return Chip(
      label: Text(status, style: context.texts.labelSmall?.copyWith(color: context.colors.onSurface)),
      backgroundColor: c.withValues(alpha: 0.15),
      side: BorderSide(color: c.withValues(alpha: 0.4)),
    );
  }

  Future<void> _save() async {
    final List<Map<String, dynamic>> lines = [];
    final Map<int, double> taxesByRate = {};
    double subtotal = 0, discountTotal = 0, taxTotal = 0, grandTotal = 0;
    for (final r in rows) {
      final name = r.name.text.trim();
      final qty = _toI(r.qty);
      final unitPrice = _toD(r.price);
      final taxPct = r.taxPercent;
      if (name.isEmpty || qty <= 0) continue;
      final base = unitPrice * qty;
      final discount = 0.0;
      final tax = (base - discount) * (taxPct / 100);
      final total = base - discount + tax;
      subtotal += base;
      discountTotal += discount;
      taxTotal += tax;
      grandTotal += total;
      taxesByRate.update(taxPct, (v) => v + tax, ifAbsent: () => tax);
      lines.add({
        'sku': r.sku,
        'name': name,
        'qty': qty,
        'unitPrice': unitPrice,
        'taxPercent': taxPct,
        'lineSubtotal': base,
        'discount': discount,
        'tax': tax,
        'lineTotal': total,
      });
    }
    final ref = await findInvoiceDocRef(widget.invoice.invoiceNo, docId: widget.invoice.docId);
    await ref.update({
      'lines': lines,
      'subtotal': subtotal,
      'discountTotal': discountTotal,
      'taxTotal': taxTotal,
      'grandTotal': grandTotal,
      'taxesByRate': taxesByRate.map((k, v) => MapEntry(k.toString(), v)),
      'updatedAt': DateTime.now().toIso8601String(),
    });
    if (mounted) setState(() => editing = false);
  }
}

class BillingCustomer {
  final String name;
  BillingCustomer({required this.name});
}

class BillingProduct {
  final String sku;
  final String name;
  final double price;
  final int taxPercent;
  BillingProduct({required this.sku, required this.name, required this.price, required this.taxPercent});
}

class InvoiceItem {
  final BillingProduct product;
  final int qty;
  InvoiceItem({required this.product, required this.qty});
  InvoiceItem copyWith({BillingProduct? product, int? qty}) =>
      InvoiceItem(product: product ?? this.product, qty: qty ?? this.qty);
  double lineSubtotal({required bool taxInclusive}) {
    if (taxInclusive) {
      final base = product.price / (1 + product.taxPercent / 100);
      return base * qty;
    } else {
      return product.price * qty;
    }
  }
  double lineTax({required bool taxInclusive}) {
    final base = lineSubtotal(taxInclusive: taxInclusive);
    return base * (product.taxPercent / 100);
  }
  double lineTotal({required bool taxInclusive}) {
    return lineSubtotal(taxInclusive: taxInclusive) + lineTax(taxInclusive: taxInclusive);
  }
}

class GSTBreakup {
  final double cgst;
  final double sgst;
  final double igst;
  const GSTBreakup({required this.cgst, required this.sgst, required this.igst});
  double get totalTax => cgst + sgst + igst;
}

class Invoice {
  final String invoiceNo;
  final BillingCustomer customer;
  final List<InvoiceItem> items;
  final DateTime date;
  final String status;
  final bool taxInclusive;
  final String? docId; // Firestore document ID

  Invoice({required this.invoiceNo, required this.customer, required this.items, required this.date, required this.status, required this.taxInclusive, this.docId});

  factory Invoice.fromFirestore(Map<String, dynamic> data, {String? docId}) {
    final invoiceNo = (data['invoiceNumber'] ?? data['invoiceNo'] ?? '').toString();
    final customerName = (data['customerName'] ?? 'Walk-in Customer').toString();
    final customer = BillingCustomer(name: customerName);
    DateTime date;
    if (data['timestampMs'] is int) {
      date = DateTime.fromMillisecondsSinceEpoch(data['timestampMs']);
    } else if (data['timestamp'] is String) {
      date = DateTime.tryParse(data['timestamp']) ?? DateTime.now();
    } else {
      date = DateTime.now();
    }
    final status = (data['status'] ?? 'Paid').toString();
    final linesRaw = data['lines'];
    final items = <InvoiceItem>[];
    if (linesRaw is List) {
      for (final l in linesRaw) {
        if (l is Map) {
          final sku = (l['sku'] ?? '').toString();
          final name = (l['name'] ?? '').toString();
          // Prefer POS schema fields; fallback to legacy and safe derivations
          double price = 0.0;
          if (l['price'] is num) {
            price = (l['price'] as num).toDouble();
          } else if (l['unitPrice'] is num) {
            price = (l['unitPrice'] as num).toDouble();
          } else {
            price = double.tryParse(l['price']?.toString() ?? '') ??
                    double.tryParse(l['unitPrice']?.toString() ?? '') ?? 0.0;
          }
          final qty = (l['qty'] is num) ? (l['qty'] as num).toInt() : int.tryParse(l['qty']?.toString() ?? '') ?? 1;
          // If unit price still zero, try deriving from lineSubtotal/qty
          if ((price == 0 || price.isNaN) && qty > 0) {
            final lineSubtotal = (l['lineSubtotal'] is num)
                ? (l['lineSubtotal'] as num).toDouble()
                : double.tryParse(l['lineSubtotal']?.toString() ?? '') ?? 0.0;
            if (lineSubtotal > 0) {
              price = lineSubtotal / qty;
            }
          }
          int tax = 0;
          if (l['taxPct'] is num) {
            tax = (l['taxPct'] as num).toInt();
          } else if (l['taxPercent'] is num) {
            tax = (l['taxPercent'] as num).toInt();
          } else {
            tax = int.tryParse(l['taxPct']?.toString() ?? '') ?? int.tryParse(l['taxPercent']?.toString() ?? '') ?? 0;
          }
          items.add(InvoiceItem(product: BillingProduct(sku: sku, name: name, price: price, taxPercent: tax), qty: qty));
        }
      }
    }
    final taxInclusive = data['taxInclusive'] == true;
    return Invoice(
      invoiceNo: invoiceNo,
      customer: customer,
      items: items,
      date: date,
      status: status,
      taxInclusive: taxInclusive,
      docId: docId,
    );
  }

  double subtotal({required bool taxInclusive}) => items.fold(0.0, (p, it) => p + it.lineSubtotal(taxInclusive: taxInclusive));
  double taxTotal({required bool taxInclusive}) => items.fold(0.0, (p, it) => p + it.lineTax(taxInclusive: taxInclusive));
  double total({required bool taxInclusive}) => items.fold(0.0, (p, it) => p + it.lineTotal(taxInclusive: taxInclusive));

  GSTBreakup gstBreakup({required bool taxInclusive}) {
    double cgst = 0, sgst = 0, igst = 0;
    for (final it in items) {
      final tax = it.lineTax(taxInclusive: taxInclusive);
      // Simple split 50/50 between CGST and SGST, IGST as 0 for local sales.
      cgst += tax / 2;
      sgst += tax / 2;
    }
    return GSTBreakup(cgst: cgst, sgst: sgst, igst: igst);
  }
}

class InvoiceWithMode extends Invoice {
  final String paymentMode;
  InvoiceWithMode({
    required super.invoiceNo,
    required super.customer,
    required super.items,
    required super.date,
    required super.status,
    required super.taxInclusive,
    super.docId,
    required this.paymentMode,
  });
}

// Edit dialog removed per request; inline Delete is available in details view.

class _SalesItemRow {
  String sku;
  final TextEditingController name;
  final TextEditingController qty;
  final TextEditingController price;
  int taxPercent;
  _SalesItemRow({required this.sku, required this.name, required this.qty, required this.price, required this.taxPercent});
  void dispose() { name.dispose(); qty.dispose(); price.dispose(); }
}

  Future<DocumentReference<Map<String, dynamic>>> findInvoiceDocRef(String invoiceNo, {String? docId}) async {
  final col = FirebaseFirestore.instance.collection('invoices');
  if (docId != null) return col.doc(docId);
  try {
    final q = await col.where('invoiceNumber', isEqualTo: invoiceNo).limit(1).get();
    if (q.docs.isNotEmpty) return q.docs.first.reference;
  } catch (_) {}
  return col.doc(invoiceNo);
}

String _fmtDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}' ;
