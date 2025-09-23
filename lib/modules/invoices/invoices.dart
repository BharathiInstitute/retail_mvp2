import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Invoices module (renamed from Billing)
// Lists invoices stored in Firestore.

class InvoicesListScreen extends StatefulWidget {
  final String? invoiceId;
  const InvoicesListScreen({super.key, this.invoiceId});
  @override
  State<InvoicesListScreen> createState() => _InvoicesPageState();
}

class _InvoicesPageState extends State<InvoicesListScreen> {
  final List<Invoice> _invoicesCache = [];
  final List<CreditDebitNote> notes = [];
  Invoice? selected;
  String query = '';
  String? statusFilter;
  DateTimeRange? dateRange;
  bool taxInclusive = true;

  @override
  void initState() { super.initState(); }

  Stream<List<Invoice>> get _invoiceStream => FirebaseFirestore.instance
      .collection('invoices')
      .orderBy('timestampMs', descending: true)
      .snapshots()
      .map((snap) {
        final list = <Invoice>[];
        for (final d in snap.docs) {
          final data = d.data();
            try { list.add(Invoice.fromFirestore(data)); } catch (_) {}
        }
        return list;
      });

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  List<Invoice> filteredInvoices(List<Invoice> source) {
    return source.where((inv) {
      final q = query.trim().toLowerCase();
      final matchesQuery = q.isEmpty || inv.invoiceNo.toLowerCase().contains(q) || inv.customer.name.toLowerCase().contains(q);
      final matchesStatus = statusFilter == null || inv.status == statusFilter;
      final matchesDate = dateRange == null || (inv.date.isAfter(dateRange!.start.subtract(const Duration(days: 1))) && inv.date.isBefore(dateRange!.end.add(const Duration(days: 1))));
      return matchesQuery && matchesStatus && matchesDate;
    }).toList();
  }

  void addNote(Invoice inv) async {
    final note = await showDialog<CreditDebitNote>(
      context: context,
      builder: (_) => _NoteEditor(invoice: inv),
    );
    if (note != null) {
      setState(() => notes.add(note));
      _snack('${note.type.toUpperCase()} note created');
    }
  }

  List<CreditDebitNote> get notesForSelected => selected == null ? [] : notes.where((n) => n.invoiceNo == selected!.invoiceNo).toList();

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
        if (selected != null) {
          final match = data.where((e) => e.invoiceNo == selected!.invoiceNo).toList();
            if (match.isNotEmpty) {
              selected = match.first;
            } else if (data.isNotEmpty) {
              selected = data.first;
            } else {
              selected = null;
            }
        } else if (data.isNotEmpty) {
          selected = data.first;
        }
        _invoicesCache..clear()..addAll(data);
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
      Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 400, child: _invoiceList(list: list)),
        const SizedBox(width: 12),
        Expanded(child: _invoiceDetails()),
      ])),
    ],
  );

  Widget _narrowLayout(List<Invoice> list) => ListView(children: [
    _searchFilterBar(),
    const SizedBox(height: 8),
    _invoiceList(height: 280, list: list),
    const SizedBox(height: 8),
    _invoiceDetails(),
  ]);

  Widget _searchFilterBar() => Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
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
        final picked = await showDateRangePicker(context: context, firstDate: DateTime(now.year - 1), lastDate: DateTime(now.year + 1));
        if (picked != null) setState(() => dateRange = picked);
      },
      icon: const Icon(Icons.date_range),
      label: Text(dateRange == null ? 'Date Range' : '${_fmtDate(dateRange!.start)} → ${_fmtDate(dateRange!.end)}'),
    ),
    OutlinedButton.icon(
      onPressed: () => setState(() { query = ''; statusFilter = null; dateRange = null; }),
      icon: const Icon(Icons.clear),
      label: const Text('Clear'),
    ),
  ]);

  Widget _invoiceList({double? height, required List<Invoice> list}) {
    final listView = ListView.separated(
      itemCount: list.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final inv = list[i];
        return ListTile(
          selected: inv == selected,
          onTap: () => setState(() => selected = inv),
          title: Text('Invoice #${inv.invoiceNo} • ${inv.customer.name}'),
          subtitle: Text('${_fmtDate(inv.date)} • ₹${inv.total(taxInclusive: taxInclusive).toStringAsFixed(2)}'),
          trailing: _statusChip(inv.status),
        );
      },
    );
    final content = Card(child: Scrollbar(thumbVisibility: true, child: listView));
    return height != null ? SizedBox(height: height, child: content) : content;
  }

  Widget _invoiceDetails() {
    if (selected == null) return const Card(child: SizedBox(height: 240, child: Center(child: Text('Select an invoice'))));
    final inv = selected!;
    final gst = inv.gstBreakup(taxInclusive: taxInclusive);
    return Card(
      child: Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12.0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('Invoice #${inv.invoiceNo}  •  ${_fmtDateTime(inv.date)}', style: const TextStyle(fontWeight: FontWeight.bold))),
              DropdownButton<String>(
                value: inv.status,
                items: const [
                  DropdownMenuItem(value: 'Paid', child: Text('Paid')),
                  DropdownMenuItem(value: 'Pending', child: Text('Pending')),
                  DropdownMenuItem(value: 'Credit', child: Text('Credit')),
                ],
                onChanged: (v) => setState(() {
                  final updated = inv.copyWith(status: v ?? inv.status);
                  selected = updated;
                  _replaceInvoice(updated);
                }),
              ),
            ]),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(columns: const [
                DataColumn(label: Text('SKU')),
                DataColumn(label: Text('Item')),
                DataColumn(label: Text('Qty')),
                DataColumn(label: Text('Price')),
                DataColumn(label: Text('GST %')),
                DataColumn(label: Text('Line Total')),
              ], rows: [
                for (final it in inv.items) DataRow(cells: [
                  DataCell(Text(it.product.sku)),
                  DataCell(Text(it.product.name)),
                  DataCell(Text(it.qty.toString())),
                  DataCell(Text('₹${it.product.price.toStringAsFixed(2)}')),
                  DataCell(Text('${it.product.taxPercent}%')),
                  DataCell(Text('₹${it.lineTotal(taxInclusive: taxInclusive).toStringAsFixed(2)}')),
                ]),
              ]),
            ),
            const Divider(),
            Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.spaceBetween, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('GST Breakup'),
                _kv('CGST', gst.cgst),
                _kv('SGST', gst.sgst),
                _kv('IGST', gst.igst),
                const SizedBox(height: 6),
                _kv('Subtotal', inv.subtotal(taxInclusive: taxInclusive)),
                _kv('Tax Total', gst.totalTax),
                const Divider(),
                _kv('Grand Total', inv.total(taxInclusive: taxInclusive), bold: true),
              ]),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Actions'),
                Wrap(spacing: 8, children: [
                  OutlinedButton.icon(onPressed: () => _snack('Printing...'), icon: const Icon(Icons.print), label: const Text('Print')),
                  OutlinedButton.icon(onPressed: () => _snack('Email sent'), icon: const Icon(Icons.email), label: const Text('Email')),
                  OutlinedButton.icon(onPressed: () => addNote(inv), icon: const Icon(Icons.edit_note), label: const Text('Credit/Debit Note')),
                ]),
              ]),
            ]),
            const Divider(),
            const Text('Notes (Credit/Debit)'),
            _notesList(notesForSelected),
          ]),
        ),
      ),
    );
  }

  Widget _notesList(List<CreditDebitNote> list) {
    if (list.isEmpty) return const Padding(padding: EdgeInsets.all(8), child: Text('No notes'));
    return Card(
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: list.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) { final n = list[i]; return ListTile(title: Text('${n.type.toUpperCase()} • ₹${n.amount.toStringAsFixed(2)}'), subtitle: Text('Reason: ${n.reason} • Date: ${_fmtDateTime(n.date)}')); },
      ),
    );
  }

  void _replaceInvoice(Invoice updated) {
    FirebaseFirestore.instance.collection('invoices').doc(updated.invoiceNo).update({'status': updated.status}).catchError((_) {});
  }

  Widget _kv(String label, double value, {bool bold = false}) {
    final style = TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal);
    return Padding(padding: const EdgeInsets.symmetric(vertical: 2.0), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: style), Text('₹${value.toStringAsFixed(2)}', style: style)]));
  }
  Widget _statusChip(String status) {
    Color c = Colors.grey; if (status == 'Paid') c = Colors.green; if (status == 'Pending') c = Colors.orange; if (status == 'Credit') c = Colors.purple; return Chip(label: Text(status), backgroundColor: c.withValues(alpha: 0.15));
  }
}

class BillingCustomer { final String name; BillingCustomer({required this.name}); }
class BillingProduct { final String sku; final String name; final double price; final int taxPercent; BillingProduct({required this.sku, required this.name, required this.price, required this.taxPercent}); }
class InvoiceItem { final BillingProduct product; final int qty; InvoiceItem({required this.product, required this.qty}); InvoiceItem copyWith({BillingProduct? product, int? qty}) => InvoiceItem(product: product ?? this.product, qty: qty ?? this.qty); double lineSubtotal({required bool taxInclusive}) { if (taxInclusive) { final base = product.price / (1 + product.taxPercent / 100); return base * qty; } else { return product.price * qty; } } double lineTax({required bool taxInclusive}) { final base = lineSubtotal(taxInclusive: taxInclusive); return base * (product.taxPercent / 100); } double lineTotal({required bool taxInclusive}) { return lineSubtotal(taxInclusive: taxInclusive) + lineTax(taxInclusive: taxInclusive); } }
class GSTBreakup { final double cgst; final double sgst; final double igst; const GSTBreakup({required this.cgst, required this.sgst, required this.igst}); double get totalTax => cgst + sgst + igst; }
class Invoice {
  final String invoiceNo; final BillingCustomer customer; final List<InvoiceItem> items; final DateTime date; final String status; final bool taxInclusive;
  Invoice({required this.invoiceNo, required this.customer, required this.items, required this.date, required this.status, required this.taxInclusive});
  factory Invoice.fromFirestore(Map<String, dynamic> data) { final invoiceNo = (data['invoiceNumber'] ?? data['invoiceNo'] ?? '').toString(); final customerName = (data['customerName'] ?? 'Walk-in Customer').toString(); final customer = BillingCustomer(name: customerName); DateTime date; if (data['timestampMs'] is int) { date = DateTime.fromMillisecondsSinceEpoch(data['timestampMs']); } else if (data['timestamp'] is String) { date = DateTime.tryParse(data['timestamp']) ?? DateTime.now(); } else { date = DateTime.now(); } final status = (data['status'] ?? 'Paid').toString(); final linesRaw = data['lines']; final items = <InvoiceItem>[]; if (linesRaw is List) { for (final l in linesRaw) { if (l is Map) { final sku = (l['sku'] ?? '').toString(); final name = (l['name'] ?? sku).toString(); final unitPrice = (l['unitPrice'] is num) ? (l['unitPrice'] as num).toDouble() : double.tryParse('${l['unitPrice']}') ?? 0; final taxPercent = (l['taxPercent'] is num) ? (l['taxPercent'] as num).toInt() : int.tryParse('${l['taxPercent']}') ?? 0; final qty = (l['qty'] is num) ? (l['qty'] as num).toInt() : int.tryParse('${l['qty']}') ?? 1; final product = BillingProduct(sku: sku, name: name, price: unitPrice, taxPercent: taxPercent); items.add(InvoiceItem(product: product, qty: qty)); } } } return Invoice(invoiceNo: invoiceNo, customer: customer, items: items, date: date, status: status, taxInclusive: true); }
  Invoice copyWith({String? invoiceNo, BillingCustomer? customer, List<InvoiceItem>? items, DateTime? date, String? status, bool? taxInclusive}) { return Invoice(invoiceNo: invoiceNo ?? this.invoiceNo, customer: customer ?? this.customer, items: items ?? this.items, date: date ?? this.date, status: status ?? this.status, taxInclusive: taxInclusive ?? this.taxInclusive); }
  double subtotal({required bool taxInclusive}) => items.fold(0.0, (s, it) => s + it.lineSubtotal(taxInclusive: taxInclusive));
  double total({required bool taxInclusive}) => items.fold(0.0, (s, it) => s + it.lineTotal(taxInclusive: taxInclusive));
  static GSTBreakup gstBreakupFor(List<InvoiceItem> items, {required bool taxInclusive}) { double cgst = 0, sgst = 0, igst = 0; for (final it in items) { final tax = it.lineTax(taxInclusive: taxInclusive); cgst += tax / 2; sgst += tax / 2; } return GSTBreakup(cgst: cgst, sgst: sgst, igst: igst); }
  GSTBreakup gstBreakup({required bool taxInclusive}) => gstBreakupFor(items, taxInclusive: taxInclusive);
}
class CreditDebitNote { final String invoiceNo; final String type; final double amount; final String reason; final DateTime date; CreditDebitNote({required this.invoiceNo, required this.type, required this.amount, required this.reason, required this.date}); }
String _fmtDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String _fmtDateTime(DateTime d) => '${_fmtDate(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
class _NoteEditor extends StatefulWidget { final Invoice invoice; const _NoteEditor({required this.invoice}); @override State<_NoteEditor> createState() => _NoteEditorState(); }
class _NoteEditorState extends State<_NoteEditor> { String type = 'credit'; final amountCtrl = TextEditingController(text: '0'); final reasonCtrl = TextEditingController(); @override Widget build(BuildContext context) { return AlertDialog( title: Text('New ${type.toUpperCase()} Note'), content: SizedBox( width: 420, child: Column( mainAxisSize: MainAxisSize.min, children: [ DropdownButtonFormField<String>( value: type, items: const [DropdownMenuItem(value: 'credit', child: Text('Credit')), DropdownMenuItem(value: 'debit', child: Text('Debit'))], onChanged: (v) => setState(() => type = v ?? 'credit'), decoration: const InputDecoration(labelText: 'Type'), ), TextFormField(controller: amountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount ₹')), TextFormField(controller: reasonCtrl, decoration: const InputDecoration(labelText: 'Reason')), ], ), ), actions: [ TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), ElevatedButton( onPressed: () { final note = CreditDebitNote(invoiceNo: widget.invoice.invoiceNo, type: type, amount: double.tryParse(amountCtrl.text) ?? 0, reason: reasonCtrl.text.trim(), date: DateTime.now(), ); Navigator.pop(context, note); }, child: const Text('Create'), ) ], ); } }

