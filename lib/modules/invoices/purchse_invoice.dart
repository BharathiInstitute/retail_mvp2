import 'package:flutter/material.dart';

/// Purchase types supported in the dialog
enum PurchaseType { noBill, gst, import, creditNote, debitNote }

String _purchaseTypeLabel(PurchaseType t) => switch (t) {
      PurchaseType.noBill => 'No Bill ',
      PurchaseType.gst => 'GST Invoice',
      PurchaseType.creditNote => 'Credit Note',
      PurchaseType.debitNote => 'Debit Note',
      PurchaseType.import => 'Utilities',
    };

Future<void> showPurchaseInvoiceDialog(BuildContext context) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PurchaseInvoiceDialog(),
  );
}

class PurchaseInvoiceDialog extends StatefulWidget {
  const PurchaseInvoiceDialog({super.key});

  @override
  State<PurchaseInvoiceDialog> createState() => _PurchaseInvoiceDialogState();
}

class _PurchaseInvoiceDialogState extends State<PurchaseInvoiceDialog> {
  // Core state
  PurchaseType type = PurchaseType.noBill;
  final TextEditingController supplierCtrl = TextEditingController();
  DateTime invoiceDate = DateTime.now();
  String paymentMode = 'Cash';

  // Conditional supplier/invoice fields
  final TextEditingController invoiceNoCtrl = TextEditingController();
  final TextEditingController gstinCtrl = TextEditingController();
  final TextEditingController addressCtrl = TextEditingController();
  // (Due date removed per streamlined spec)

  // Items (unified for all types, including No-Bill)
  final List<_ItemRow> items = [
    _ItemRow(name: TextEditingController(), qty: TextEditingController(text: '1'), price: TextEditingController(text: '0'), gstRate: 0),
  ];

  // Summary fields
  // Removed: Discount, Other Charges, Round Off per request
  // Import-only charges
  final TextEditingController freightCtrl = TextEditingController(text: '0');
  final TextEditingController customsCtrl = TextEditingController(text: '0');
  // GST-only CESS
  final TextEditingController cessCtrl = TextEditingController(text: '0');

  // Payment
  final TextEditingController paidCtrl = TextEditingController(text: '0');

  // Utility section
  final TextEditingController notesCtrl = TextEditingController();
  final TextEditingController utilityAmountCtrl = TextEditingController(text: '0');
  final TextEditingController linkedInvoiceCtrl = TextEditingController();

  // Scroll controller to pair with Scrollbar
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void dispose() {
    supplierCtrl.dispose();
    invoiceNoCtrl.dispose();
    gstinCtrl.dispose();
    addressCtrl.dispose();
    for (final r in items) {
      r.name.dispose();
      r.qty.dispose();
      r.price.dispose();
    }
  // Removed controllers: summary fields (discount/other/roundOff)
  freightCtrl.dispose();
  customsCtrl.dispose();
    paidCtrl.dispose();
    notesCtrl.dispose();
  utilityAmountCtrl.dispose();
  linkedInvoiceCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  double _toDouble(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0.0;

  // Basic computations per prompt
  _Totals _computeTotals() {
    double subtotal = 0, cgst = 0, sgst = 0, igst = 0;
    for (final r in items) {
      final q = double.tryParse(r.qty.text) ?? 0;
      final p = double.tryParse(r.price.text) ?? 0;
      final line = q * p;
      subtotal += line;
      final rate = (r.gstRate.toDouble()) / 100.0;
      if (type == PurchaseType.import) {
        igst += line * rate; // simplified
      } else if (type == PurchaseType.gst) {
        final tax = line * rate; cgst += tax / 2; sgst += tax / 2;
      }
    }
    final freight = type == PurchaseType.import ? _toDouble(freightCtrl) : 0.0;
    final customs = type == PurchaseType.import ? _toDouble(customsCtrl) : 0.0;
    final cess = type == PurchaseType.gst ? _toDouble(cessCtrl) : 0.0;
    final taxable = (subtotal + freight + customs).clamp(0, double.infinity);
    final grand = taxable + cgst + sgst + igst + cess;
    return _Totals(cgst: cgst, sgst: sgst, igst: igst, cess: cess, freight: freight, customs: customs, grand: grand);
  }

  @override
  Widget build(BuildContext context) {
    final totals = _computeTotals();
  final balance = ((totals.grand - _toDouble(paidCtrl)).clamp(0, double.infinity)).toDouble();
    return AlertDialog(
      title: const Text('New Purchase Invoice'),
      content: SizedBox(
        width: 820,
        height: 620,
        child: Scrollbar(
          controller: _scrollCtrl,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _scrollCtrl,
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _section('Header', _buildHeader()),
                if (type == PurchaseType.gst || type == PurchaseType.import)
                  _section('Supplier & Invoice Details', _buildSupplierInvoice()),
                _section('Items', _buildItems(), trailing: IconButton(
                  tooltip: 'Add Item',
                  onPressed: () => setState(() => items.add(_ItemRow(name: TextEditingController(), qty: TextEditingController(text: '1'), price: TextEditingController(text: '0'), gstRate: 0))),
                  icon: const Icon(Icons.add),
                )),
                _section('Invoice Summary', _buildSummary(totals)),
                _section('Payment & Accounting', _buildPayment(balance)),
                _section('Utility', _buildAdvanced()),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            // Minimal validation: supplier and amount
            if (supplierCtrl.text.trim().isEmpty) {
              _toast(context, 'Enter supplier');
              return;
            }
            final hasPositive = items.any((r) => (double.tryParse(r.qty.text) ?? 0) * (double.tryParse(r.price.text) ?? 0) > 0);
            if (!hasPositive) {
              _toast(context, 'Enter at least one item with amount');
              return;
            }
            if (type != PurchaseType.noBill && items.isEmpty) {
              _toast(context, 'Add at least one item');
              return;
            }
            Navigator.pop(context);
            _buildPurchasePayload();
            _toast(context, 'Saved (demo only)');
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _section(String title, Widget child, {Widget? trailing}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            children: [
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold))),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 8),
          child,
        ]),
      ),
    );
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _buildHeader() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 200,
          child: DropdownButtonFormField<PurchaseType>(
            initialValue: type,
            items: PurchaseType.values
                .map((t) => DropdownMenuItem(value: t, child: Text(_purchaseTypeLabel(t))))
                .toList(),
            onChanged: (v) => setState(() => type = v ?? type),
            decoration: const InputDecoration(labelText: 'Purchase Type'),
          ),
        ),
        SizedBox(
          width: 240,
          child: TextFormField(
            controller: supplierCtrl,
            decoration: const InputDecoration(labelText: 'Supplier Name'),
          ),
        ),
        SizedBox(
          width: 180,
          child: InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
                initialDate: invoiceDate,
              );
              if (picked != null) setState(() => invoiceDate = picked);
            },
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Invoice Date'),
              child: Text(_fmtDate(invoiceDate)),
            ),
          ),
        ),
        SizedBox(
          width: 160,
          child: DropdownButtonFormField<String>(
            initialValue: paymentMode,
            items: const [
              DropdownMenuItem(value: 'Cash', child: Text('Cash')),
              DropdownMenuItem(value: 'Bank', child: Text('Bank')),
            ],
            onChanged: (v) => setState(() => paymentMode = v ?? paymentMode),
            decoration: const InputDecoration(labelText: 'Payment Mode'),
          ),
        ),
      ],
    );
  }

  Widget _buildSupplierInvoice() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        SizedBox(
          width: 180,
          child: TextFormField(
            controller: invoiceNoCtrl,
            decoration: const InputDecoration(labelText: 'Invoice No'),
          ),
        ),
        if (type == PurchaseType.gst || type == PurchaseType.import)
          SizedBox(
            width: 200,
            child: TextFormField(
              controller: gstinCtrl,
              decoration: const InputDecoration(labelText: 'Supplier GSTIN'),
            ),
          ),
        SizedBox(
          width: 320,
          child: TextFormField(
            controller: addressCtrl,
            decoration: const InputDecoration(labelText: 'Supplier Address'),
          ),
        ),
      ],
    );
  }

  Widget _buildItems() {
    return Column(
      children: [
        for (int i = 0; i < items.length; i++) _itemRow(i),
      ],
    );
  }

  Widget _itemRow(int index) {
    final r = items[index];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(children: [
        Expanded(
          flex: 3,
          child: TextFormField(controller: r.name, decoration: const InputDecoration(labelText: 'Item / Description')),
        ),
        const SizedBox(width: 8),
        SizedBox(width: 90, child: TextFormField(controller: r.qty, decoration: const InputDecoration(labelText: 'Qty'), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
        const SizedBox(width: 8),
        SizedBox(width: 120, child: TextFormField(controller: r.price, decoration: const InputDecoration(labelText: 'Unit Price ₹'), keyboardType: const TextInputType.numberWithOptions(decimal: true))),
        const SizedBox(width: 8),
        if (type == PurchaseType.gst || type == PurchaseType.import)
          SizedBox(
            width: 120,
            child: DropdownButtonFormField<int>(
              initialValue: r.gstRate,
              items: const [0, 5, 12, 18, 28]
                  .map((v) => DropdownMenuItem(value: v, child: Text('GST $v%')))
                  .toList(),
              onChanged: (v) => setState(() => r.gstRate = v ?? r.gstRate),
              decoration: const InputDecoration(labelText: 'Tax Rate'),
            ),
          ),
        const SizedBox(width: 8),
        // Computed line amount
        SizedBox(
          width: 110,
          child: InputDecorator(
            decoration: const InputDecoration(labelText: 'Amount'),
            child: Text(_fmtAmount((double.tryParse(r.qty.text) ?? 0) * (double.tryParse(r.price.text) ?? 0))),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Remove',
          onPressed: items.length <= 1
              ? null
              : () => setState(() {
                    final row = items.removeAt(index);
                    row.dispose();
                  }),
          icon: const Icon(Icons.close),
        ),
      ]),
    );
  }

  Widget _buildSummary(_Totals t) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        if (type == PurchaseType.gst) ...[
          _kv('CGST', t.cgst),
          _kv('SGST', t.sgst),
          _kv('IGST', t.igst),
          SizedBox(width: 140, child: TextFormField(controller: cessCtrl, decoration: const InputDecoration(labelText: 'CESS ₹'), keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}))),
        ],
        if (type == PurchaseType.import) ...[
          SizedBox(width: 140, child: TextFormField(controller: freightCtrl, decoration: const InputDecoration(labelText: 'Freight ₹'), keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}))),
          SizedBox(width: 160, child: TextFormField(controller: customsCtrl, decoration: const InputDecoration(labelText: 'Customs Duty ₹'), keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}))),
          _kv('IGST', t.igst),
        ],
        _kv('Grand Total', t.grand, bold: true),
      ],
    );
  }

  Widget _buildPayment(double balance) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(width: 160, child: TextFormField(controller: paidCtrl, decoration: const InputDecoration(labelText: 'Paid Amount ₹'), keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}))),
        _kv('Balance', balance),
      ],
    );
  }

  Widget _buildAdvanced() {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      initiallyExpanded: false,
      title: const SizedBox.shrink(),
      childrenPadding: EdgeInsets.zero,
      children: [
        Wrap(spacing: 12, runSpacing: 12, children: [
          SizedBox(width: 320, child: TextFormField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notes'))),
          SizedBox(width: 200, child: TextFormField(controller: utilityAmountCtrl, decoration: const InputDecoration(labelText: 'Amount ₹'), keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}))),
          if (type == PurchaseType.creditNote || type == PurchaseType.debitNote)
            SizedBox(width: 260, child: TextFormField(controller: linkedInvoiceCtrl, decoration: const InputDecoration(labelText: 'Linked Invoice No'))),
        ]),
      ],
    );
  }

  Widget _kv(String label, double value, {bool bold = false}) {
    final style = TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: style),
        const SizedBox(width: 8),
        Text('₹${value.toStringAsFixed(2)}', style: style),
      ]),
    );
  }

  String _fmtAmount(double v) => '₹${v.toStringAsFixed(2)}';

  Map<String, dynamic> _buildPurchasePayload() {
    final totals = _computeTotals();
    return {
      'type': _purchaseTypeLabel(type),
      'supplier': supplierCtrl.text.trim(),
      'invoiceNo': invoiceNoCtrl.text.trim(),
      'invoiceDate': invoiceDate.toIso8601String(),
      'paymentMode': paymentMode,
      'items': [
        for (final r in items)
          {
            'name': r.name.text.trim(),
            'qty': double.tryParse(r.qty.text) ?? 0,
            'unitPrice': double.tryParse(r.price.text) ?? 0,
            'gstRate': r.gstRate,
          }
      ],
      'summary': {
        'cgst': totals.cgst,
        'sgst': totals.sgst,
        'igst': totals.igst,
        'cess': totals.cess,
        'grandTotal': totals.grand,
      },
      'payment': {
        'paid': double.tryParse(paidCtrl.text) ?? 0,
        'balance': ((totals.grand - (double.tryParse(paidCtrl.text) ?? 0)).clamp(0, double.infinity)).toDouble(),
      },
      'utility': {
        'amount': double.tryParse(utilityAmountCtrl.text) ?? 0,
        'notes': notesCtrl.text.trim(),
        'linkedInvoice': (type == PurchaseType.creditNote || type == PurchaseType.debitNote) ? linkedInvoiceCtrl.text.trim() : '',
      },
      'createdAt': DateTime.now().toIso8601String(),
    };
  }
}

class _Totals {
  final double cgst, sgst, igst, cess, freight, customs, grand;
  const _Totals({
    required this.cgst,
    required this.sgst,
    required this.igst,
    required this.cess,
    required this.freight,
    required this.customs,
    required this.grand,
  });
}

class _ItemRow {
  final TextEditingController name;
  final TextEditingController qty;
  final TextEditingController price;
  int gstRate; // percent
  _ItemRow({required this.name, required this.qty, required this.price, required this.gstRate});
  void dispose() { name.dispose(); qty.dispose(); price.dispose(); }
}

String _fmtDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
