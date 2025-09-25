import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Invoices module (renamed from Billing)
// Lists invoices stored in Firestore. Preview panel removed per request.

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
            list.add(Invoice.fromFirestore(data));
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
          // Purchase entry moved to Purchases tab (invoices_tabs.dart)
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
        return ListTile(
          onTap: () => _showInvoiceDetails(inv),
          title: Text('Invoice #${inv.invoiceNo} • ${inv.customer.name}'),
          subtitle: Text('${_fmtDate(inv.date)} • ₹${inv.total(taxInclusive: taxInclusive).toStringAsFixed(2)}'),
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
            child: _invoiceDetailsContent(inv, dialogCtx),
          ),
        );
      },
    );
  }

  Widget _invoiceDetailsContent(Invoice inv, BuildContext dialogCtx) {
    final gst = inv.gstBreakup(taxInclusive: taxInclusive);
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
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              FilledButton.icon(
                onPressed: () async {
                  await _showEditSalesInvoice(inv, dialogCtx);
                },
                icon: const Icon(Icons.edit),
                label: const Text('Edit'),
              ),
              const SizedBox(width: 8),
              _statusChip(inv.status),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(dialogCtx, rootNavigator: true).pop(),
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
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
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
                            DataCell(Text('₹${it.lineTotal(taxInclusive: taxInclusive).toStringAsFixed(2)}')),
                          ]),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 24,
                    runSpacing: 16,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('GST Breakup', style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          _kv('CGST', gst.cgst),
                          _kv('SGST', gst.sgst),
                          _kv('IGST', gst.igst),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Totals', style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          // Removed Subtotal per request
                          _kv('Tax Total', gst.totalTax),
                          const Divider(),
                          _kv('Grand Total', inv.total(taxInclusive: taxInclusive), bold: true),
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
                onPressed: () => Navigator.of(dialogCtx, rootNavigator: true).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _kv(String label, double value, {bool bold = false}) {
    final style = TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal);
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
    Color c = Colors.grey;
    if (status == 'Paid') c = Colors.green;
    if (status == 'Pending') c = Colors.orange;
    if (status == 'Credit') c = Colors.purple;
    return Chip(label: Text(status), backgroundColor: c.withValues(alpha: 0.15));
  }

  Future<void> _showEditSalesInvoice(Invoice inv, BuildContext dialogCtx) async {
    // Load the underlying Firestore document by invoiceNumber (assumes doc id == invoiceNumber used in POS save logic)
    final docRef = FirebaseFirestore.instance.collection('invoices').doc(inv.invoiceNo);
    final docSnap = await docRef.get();
    if (!docSnap.exists) {
      ScaffoldMessenger.of(dialogCtx).showSnackBar(const SnackBar(content: Text('Original document not found')));
      return;
    }

    // Controllers & mutable working copy
    final customerController = TextEditingController(text: inv.customer.name);
    String status = inv.status;
    final items = inv.items.map((e) => e).toList(); // shallow copy

    // For each line make qty & price editable via TextEditingController lists
    final qtyControllers = [for (final it in items) TextEditingController(text: it.qty.toString())];
    final priceControllers = [for (final it in items) TextEditingController(text: it.product.price.toStringAsFixed(2))];

    double computeGrandTotal() {
      double total = 0;
      for (int i = 0; i < items.length; i++) {
        final qty = int.tryParse(qtyControllers[i].text.trim()) ?? items[i].qty;
        final price = double.tryParse(priceControllers[i].text.trim()) ?? items[i].product.price;
        final taxPercent = items[i].product.taxPercent;
        final base = price / (1 + taxPercent / 100);
        final lineSubtotal = base * qty;
        final lineTax = lineSubtotal * taxPercent / 100;
        total += lineSubtotal + lineTax;
      }
      return total;
    }

    await showDialog(
      context: dialogCtx,
      useRootNavigator: true,
      builder: (editCtx) {
        return StatefulBuilder(builder: (editCtx, setStateSB) {
          final grandTotal = computeGrandTotal();
          return Dialog(
            insetPadding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900, maxHeight: 720),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('Edit Invoice #${inv.invoiceNo}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.of(editCtx, rootNavigator: true).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: customerController,
                                    decoration: const InputDecoration(labelText: 'Customer Name'),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                DropdownButton<String>(
                                  value: status,
                                  items: const [
                                    DropdownMenuItem(value: 'Paid', child: Text('Paid')),
                                    DropdownMenuItem(value: 'Pending', child: Text('Pending')),
                                    DropdownMenuItem(value: 'Credit', child: Text('Credit')),
                                  ],
                                  onChanged: (v) => setStateSB(() => status = v ?? status),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                columns: const [
                                  DataColumn(label: Text('SKU')),
                                  DataColumn(label: Text('Item')),
                                  DataColumn(label: Text('Qty')),
                                  DataColumn(label: Text('Price')),
                                  DataColumn(label: Text('GST %')),
                                  DataColumn(label: Text('Line Total')),
                                  DataColumn(label: Text('')),
                                ],
                                rows: [
                                  for (int i = 0; i < items.length; i++)
                                    DataRow(cells: [
                                      DataCell(Text(items[i].product.sku)),
                                      DataCell(Text(items[i].product.name)),
                                      DataCell(SizedBox(
                                        width: 60,
                                        child: TextField(
                                          controller: qtyControllers[i],
                                          keyboardType: TextInputType.number,
                                          onChanged: (_) => setStateSB(() {}),
                                          decoration: const InputDecoration(border: InputBorder.none),
                                        ),
                                      )),
                                      DataCell(SizedBox(
                                        width: 80,
                                        child: TextField(
                                          controller: priceControllers[i],
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          onChanged: (_) => setStateSB(() {}),
                                          decoration: const InputDecoration(border: InputBorder.none),
                                        ),
                                      )),
                                      DataCell(Text('${items[i].product.taxPercent}%')),
                                      DataCell(() {
                                        final qty = int.tryParse(qtyControllers[i].text.trim()) ?? items[i].qty;
                                        final price = double.tryParse(priceControllers[i].text.trim()) ?? items[i].product.price;
                                        final taxPercent = items[i].product.taxPercent;
                                        final base = price / (1 + taxPercent / 100);
                                        final lineSubtotal = base * qty;
                                        final lineTax = lineSubtotal * taxPercent / 100;
                                        final total = lineSubtotal + lineTax;
                                        return Text('₹${total.toStringAsFixed(2)}');
                                      }()),
                                      DataCell(IconButton(
                                        tooltip: 'Remove line',
                                        icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                                        onPressed: () {
                                          setStateSB(() {
                                            items.removeAt(i);
                                            qtyControllers.removeAt(i);
                                            priceControllers.removeAt(i);
                                          });
                                        },
                                      )),
                                    ]),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Text('Grand Total: ₹${grandTotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(editCtx, rootNavigator: true).pop(),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            onPressed: items.isEmpty
                                ? null
                                : () async {
                              // Build updated lines array compatible with original structure
                              final updatedLines = <Map<String, dynamic>>[];
                              for (int i = 0; i < items.length; i++) {
                                final qty = int.tryParse(qtyControllers[i].text.trim()) ?? items[i].qty;
                                final price = double.tryParse(priceControllers[i].text.trim()) ?? items[i].product.price;
                                updatedLines.add({
                                  'sku': items[i].product.sku,
                                  'name': items[i].product.name,
                                  'qty': qty,
                                  'unitPrice': price,
                                  'taxPercent': items[i].product.taxPercent,
                                });
                              }
                              if (updatedLines.isEmpty) {
                                ScaffoldMessenger.of(editCtx).showSnackBar(const SnackBar(content: Text('Add at least one line before saving')));
                                return;
                              }
                              await docRef.update({
                                'customerName': customerController.text.trim(),
                                'status': status,
                                'lines': updatedLines,
                                // Keep a simple timestamp update for tracking edits
                                'lastEditedAt': FieldValue.serverTimestamp(),
                              });
                              // Close both dialogs and refresh list (stream auto updates)
                              if (Navigator.of(editCtx).canPop()) {
                                Navigator.of(editCtx, rootNavigator: true).pop(); // close edit
                              }
                              if (Navigator.of(dialogCtx).canPop()) {
                                Navigator.of(dialogCtx, rootNavigator: true).pop(); // close details
                              }
                              // Optionally reopen updated details
                              final refreshedSnap = await docRef.get();
                              if (refreshedSnap.exists) {
                                final updatedData = refreshedSnap.data() as Map<String, dynamic>;
                                final updatedInv = Invoice.fromFirestore(updatedData);
                                if (mounted) {
                                  Future.microtask(() => _showInvoiceDetails(updatedInv));
                                }
                              }
                            },
                            icon: const Icon(Icons.save),
                            label: const Text('Save Changes'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        });
      },
    );
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

  Invoice({required this.invoiceNo, required this.customer, required this.items, required this.date, required this.status, required this.taxInclusive});

  factory Invoice.fromFirestore(Map<String, dynamic> data) {
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
          final name = (l['name'] ?? sku).toString();
          final unitPrice = (l['unitPrice'] is num) ? (l['unitPrice'] as num).toDouble() : double.tryParse('${l['unitPrice']}') ?? 0;
          final taxPercent = (l['taxPercent'] is num) ? (l['taxPercent'] as num).toInt() : int.tryParse('${l['taxPercent']}') ?? 0;
          final qty = (l['qty'] is num) ? (l['qty'] as num).toInt() : int.tryParse('${l['qty']}') ?? 1;
          final product = BillingProduct(sku: sku, name: name, price: unitPrice, taxPercent: taxPercent);
          items.add(InvoiceItem(product: product, qty: qty));
        }
      }
    }
    return Invoice(invoiceNo: invoiceNo, customer: customer, items: items, date: date, status: status, taxInclusive: true);
  }

  Invoice copyWith({String? invoiceNo, BillingCustomer? customer, List<InvoiceItem>? items, DateTime? date, String? status, bool? taxInclusive}) {
    return Invoice(
      invoiceNo: invoiceNo ?? this.invoiceNo,
      customer: customer ?? this.customer,
      items: items ?? this.items,
      date: date ?? this.date,
      status: status ?? this.status,
      taxInclusive: taxInclusive ?? this.taxInclusive,
    );
  }

  double subtotal({required bool taxInclusive}) => items.fold(0.0, (s, it) => s + it.lineSubtotal(taxInclusive: taxInclusive));
  double total({required bool taxInclusive}) => items.fold(0.0, (s, it) => s + it.lineTotal(taxInclusive: taxInclusive));
  static GSTBreakup gstBreakupFor(List<InvoiceItem> items, {required bool taxInclusive}) {
    double cgst = 0, sgst = 0, igst = 0;
    for (final it in items) {
      final tax = it.lineTax(taxInclusive: taxInclusive);
      cgst += tax / 2;
      sgst += tax / 2;
    }
    return GSTBreakup(cgst: cgst, sgst: sgst, igst: igst);
  }
  GSTBreakup gstBreakup({required bool taxInclusive}) => gstBreakupFor(items, taxInclusive: taxInclusive);
}

class CreditDebitNote {
  final String invoiceNo;
  final String type;
  final double amount;
  final String reason;
  final DateTime date;
  CreditDebitNote({required this.invoiceNo, required this.type, required this.amount, required this.reason, required this.date});
}

String _fmtDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

