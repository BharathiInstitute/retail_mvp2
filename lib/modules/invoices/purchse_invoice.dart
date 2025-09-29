import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

Future<void> showEditPurchaseInvoiceDialog(BuildContext context, String docId, Map<String, dynamic> data) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => PurchaseInvoiceDialog(existingId: docId, existingData: data),
  );
}

class PurchaseInvoiceDialog extends StatefulWidget {
  final String? existingId;
  final Map<String, dynamic>? existingData;
  const PurchaseInvoiceDialog({super.key, this.existingId, this.existingData});

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

  // Cached inventory products (simple live snapshot once per rebuild via StreamBuilder below)
  List<_ProductLite> _products = const [];

  @override
  void initState() {
    super.initState();
    // Prefill if editing
    final data = widget.existingData;
    if (data != null) {
      final typeLabel = (data['type'] ?? '') as String;
      type = PurchaseType.values.firstWhere(
        (t) => _purchaseTypeLabel(t) == typeLabel,
        orElse: () => PurchaseType.noBill,
      );
      supplierCtrl.text = (data['supplier'] ?? '') as String;
      invoiceNoCtrl.text = (data['invoiceNo'] ?? '') as String;
      paymentMode = (data['paymentMode'] ?? 'Cash') as String;
      final dateStr = (data['invoiceDate'] ?? '') as String;
      if (dateStr.isNotEmpty) {
        try { invoiceDate = DateTime.parse(dateStr); } catch (_) {}
      }
      final utility = (data['utility'] as Map?) ?? const {};
      utilityAmountCtrl.text = '${utility['amount'] ?? 0}';
      notesCtrl.text = (utility['notes'] ?? '') as String;
      linkedInvoiceCtrl.text = (utility['linkedInvoice'] ?? '') as String;
      final itemsData = (data['items'] as List?)?.whereType<Map>().toList() ?? const <Map>[];
      items.clear();
      for (final it in itemsData) {
        items.add(_ItemRow(
          name: TextEditingController(text: (it['name'] ?? '').toString()),
          qty: TextEditingController(text: '${it['qty'] ?? 0}'),
          price: TextEditingController(text: '${it['unitPrice'] ?? 0}'),
          gstRate: (it['gstRate'] is int) ? it['gstRate'] as int : int.tryParse('${it['gstRate']}') ?? 0,
        )..sku = (it['sku'] ?? '') == '' ? null : (it['sku'] as String));
      }
      if (items.isEmpty) {
        items.add(_ItemRow(name: TextEditingController(), qty: TextEditingController(text: '1'), price: TextEditingController(text: '0'), gstRate: 0));
      }
      final payment = (data['payment'] as Map?) ?? const {};
      paidCtrl.text = '${payment['paid'] ?? 0}';
      final summary = (data['summary'] as Map?) ?? const {};
      cessCtrl.text = '${summary['cess'] ?? 0}';
      freightCtrl.text = '${summary['freight'] ?? 0}';
      customsCtrl.text = '${summary['customs'] ?? 0}';
    }
    // Load inventory products stream
    FirebaseFirestore.instance.collection('inventory').snapshots().listen((snap) {
      final prods = snap.docs.map((d) {
        final m = d.data();
        double toD(v) => v is int ? v.toDouble() : (v is double ? v : double.tryParse(v?.toString() ?? '') ?? 0);
        return _ProductLite(
          sku: d.id,
          name: (m['name'] ?? '') as String,
          unitPrice: toD(m['unitPrice']),
          taxPct: m['taxPct'] is num ? (m['taxPct'] as num).toDouble() : double.tryParse('${m['taxPct']}'),
        );
      }).where((p) => p.name.isNotEmpty).toList();
      prods.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (mounted) setState(() => _products = prods);
    });
  }

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

  // Auto-save removed: invoices now persist only on explicit Save button press.

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
    // Utility amount handling: if there are no item line values, use utility amount as base (grand total),
    // regardless of type. For import we still add freight/customs, for others we ignore those (already zero).
    final hasItemValue = subtotal > 0;
    final utilityAmount = double.tryParse(utilityAmountCtrl.text) ?? 0;
    double base = subtotal + freight + customs;
    if (!hasItemValue && utilityAmount > 0) {
      base = utilityAmount + (type == PurchaseType.import ? (freight + customs) : 0);
    }
    final taxable = base.clamp(0, double.infinity);
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
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(10.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _inlineTitle('Header'),
                        _buildHeader(),
                        const SizedBox(height: 14),
                        if (type == PurchaseType.gst || type == PurchaseType.import) ...[
                          _inlineTitle('Supplier & Invoice Details'),
                          _buildSupplierInvoice(),
                          const SizedBox(height: 14),
                        ],
                        _inlineTitle('Utility'),
                        _buildAdvanced(),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            _inlineTitle('Items'),
                            const Spacer(),
                            IconButton(
                              tooltip: 'Add Item',
                              onPressed: () => setState(() => items.add(_ItemRow(name: TextEditingController(), qty: TextEditingController(text: '1'), price: TextEditingController(text: '0'), gstRate: 0))),
                              icon: const Icon(Icons.add),
                            ),
                          ],
                        ),
                        _buildItems(),
                        const SizedBox(height: 14),
                        _inlineTitle('Invoice Summary / Payment'),
                        const SizedBox(height: 6),
                        _buildSummaryAndPayment(totals, balance),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            // Validation rules:
            // 1. Supplier required always.
            // 2. For standard purchase types (gst, credit/debit, noBill) need at least one item with amount.
            // 3. For Utilities (import type) allow saving with only utility amount (no item lines with value).
            if (supplierCtrl.text.trim().isEmpty) {
              _toast(context, 'Enter supplier');
              return;
            }
            final hasItemValue = items.any((r) => (double.tryParse(r.qty.text) ?? 0) * (double.tryParse(r.price.text) ?? 0) > 0);
            // Enforce explicit Save: require either an item amount or (for Utility/No Bill) a utility amount
            if (!hasItemValue) {
              final utilAmt = double.tryParse(utilityAmountCtrl.text) ?? 0;
              final utilityMode = (type == PurchaseType.import || type == PurchaseType.noBill) && utilAmt > 0;
              if (!utilityMode) {
                _toast(context, 'Enter at least one item amount or utility amount');
                return;
              }
            }
            final payload = _buildPurchasePayload();
            // Auto-generate invoice no if empty
            if ((payload['invoiceNo'] as String).isEmpty) {
              // We'll await generation before persisting
              // (Do not block UI too long; small transaction)
              // ignore: use_build_context_synchronously
              _toast(context, 'Generating invoice number...');
            }
            if ((payload['summary']?['grandTotal'] ?? 0) <= 0) {
              _toast(context, 'Grand total is 0. Add item or utility amount.');
              return;
            }
            Future<String?> maybeGen() async {
              if ((payload['invoiceNo'] as String).isNotEmpty) return payload['invoiceNo'];
              try { return await _generateInvoiceNo(); } catch (_) { return null; }
            }
            maybeGen().then((gen) {
              if (gen != null) payload['invoiceNo'] = gen;
              return _saveToFirestore(payload);
            }).then((_) {
              // After successfully saving a NEW invoice, adjust inventory (skip if editing or already adjusted)
              if (mounted && widget.existingId == null) {
                _applyInventoryAdjustments(payload).catchError((e){
                  // Non-blocking: show warning but keep invoice saved
                  _toast(context, 'Inventory update failed: $e');
                });
              }
              if (mounted) {
                Navigator.pop(context);
                _toast(context, 'Purchase saved');
              }
            }).catchError((e) { _toast(context, 'Save failed: $e'); return null; });
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _saveToFirestore(Map<String, dynamic> data) async {
    final col = FirebaseFirestore.instance.collection('purchase_invoices');
    if (widget.existingId != null) {
      final doc = col.doc(widget.existingId);
      data['id'] = widget.existingId;
      data['updatedAt'] = DateTime.now().toIso8601String();
      // Do not overwrite original timestampMs if present
      await doc.update(data);
    } else {
      final doc = col.doc();
      data['id'] = doc.id;
      data['timestampMs'] = DateTime.now().millisecondsSinceEpoch;
      await doc.set(data);
    }
  }

  /// Increase inventory stock for each item line that has an associated SKU.
  /// Assumptions:
  ///  * All received stock goes to Warehouse.
  ///  * Quantities are additive (no negative lines).
  ///  * Only executed for newly created invoices (not edits) to avoid complex delta logic.
  Future<void> _applyInventoryAdjustments(Map<String, dynamic> payload) async {
    final items = (payload['items'] as List?)?.whereType<Map>().toList() ?? const <Map>[];
    if (items.isEmpty) return;
    // Aggregate quantities per sku (convert qty to int)
    final Map<String, int> skuQty = {};
    for (final it in items) {
      final sku = (it['sku'] ?? '') as String;
      if (sku.isEmpty) continue;
      final qtyNum = it['qty'];
      final qty = (qtyNum is num) ? qtyNum.toDouble() : double.tryParse('$qtyNum') ?? 0;
      if (qty <= 0) continue;
      skuQty.update(sku, (v) => v + qty.round(), ifAbsent: () => qty.round());
    }
    if (skuQty.isEmpty) return;
    final db = FirebaseFirestore.instance;
    const warehouseLoc = 'Warehouse';
    const storeLoc = 'Store'; // preserved if present
    // Run sequential transactions (could be parallel but Firestore limits 500 ops anyway)
    for (final entry in skuQty.entries) {
      final sku = entry.key;
      final addQty = entry.value;
      final docRef = db.collection('inventory').doc(sku);
      await db.runTransaction((txn) async {
        final snap = await txn.get(docRef);
        if (!snap.exists) return; // silently skip unknown sku
        final data = snap.data() as Map<String, dynamic>;
        final batchesRaw = (data['batches'] as List?)?.whereType<Map>().toList() ?? <Map>[];
        int storeQty = 0; int whQty = 0; final others = <Map<String, dynamic>>[];
        for (final b in batchesRaw) {
          final loc = (b['location'] ?? '') as String;
            final q = (b['qty'] is int) ? b['qty'] as int : (b['qty'] is num ? (b['qty'] as num).toInt() : int.tryParse('${b['qty']}') ?? 0);
          if (loc == storeLoc) {
            storeQty += q;
          } else if (loc == warehouseLoc) {
            whQty += q;
          } else {
            others.add(Map<String,dynamic>.from(b));
          }
        }
        whQty += addQty; // Add received stock to warehouse
        final newBatches = <Map<String,dynamic>>[...others];
        if (storeQty > 0) newBatches.add({'batchNo': 'MOVE-Store', 'qty': storeQty, 'location': storeLoc});
        if (whQty > 0) newBatches.add({'batchNo': 'MOVE-Warehouse', 'qty': whQty, 'location': warehouseLoc});
        txn.update(docRef, {
          'batches': newBatches,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': 'purchase-invoice',
        });
      });
    }
  }

  Future<String> _generateInvoiceNo() async {
    // Use a single counters document with per-type fields.
    final countersRef = FirebaseFirestore.instance.collection('meta').doc('purchase_counters');
    return FirebaseFirestore.instance.runTransaction((txn) async {
      final snap = await txn.get(countersRef);
      final typeKey = _purchaseTypeLabel(type).replaceAll(' ', '_').toLowerCase();
      int current = 0;
      if (snap.exists) {
        current = (snap.data()?[typeKey] ?? 0) as int;
      }
      final next = current + 1;
      txn.set(countersRef, {typeKey: next}, SetOptions(merge: true));
      final prefix = switch (type) {
        PurchaseType.noBill => 'NB',
        PurchaseType.gst => 'GST',
        PurchaseType.import => 'UTL',
        PurchaseType.creditNote => 'CRN',
        PurchaseType.debitNote => 'DBN',
      };
      return '$prefix-${next.toString().padLeft(5, '0')}';
    });
  }

  // _section helper removed after flattening into single card

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _inlineTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
      );

  Widget _buildHeader() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 200,
          child: DropdownButtonFormField<PurchaseType>(
            value: type,
            items: PurchaseType.values
                .map((t) => DropdownMenuItem(value: t, child: Text(_purchaseTypeLabel(t))))
                .toList(),
            onChanged: (v) => setState(() => type = v ?? type),
            decoration: const InputDecoration(labelText: 'Purchase Type'),
          ),
        ),
        SizedBox(
          width: 240,
          child: _SupplierDropdown(controller: supplierCtrl, autofocus: true),
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
            value: paymentMode,
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
          child: _ProductAutocomplete(
            controller: r.name,
            initialSku: r.sku,
            onProductSelected: (prod) {
              setState(() {
                r.sku = prod?.sku;
                if ((r.price.text.trim().isEmpty || r.price.text == '0') && prod != null) {
                  r.price.text = prod.unitPrice.toStringAsFixed(2);
                }
                if ((type == PurchaseType.gst || type == PurchaseType.import) && prod?.taxPct != null) {
                  r.gstRate = (prod!.taxPct ?? 0).toInt();
                }
              });
            },
            products: _products,
          ),
        ),
        const SizedBox(width: 8),
  SizedBox(width: 90, child: TextFormField(controller: r.qty, decoration: const InputDecoration(labelText: 'Qty'), keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}))),
        const SizedBox(width: 8),
  SizedBox(width: 120, child: TextFormField(controller: r.price, decoration: const InputDecoration(labelText: 'Unit Price ₹'), keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}))),
        const SizedBox(width: 8),
        if (type == PurchaseType.gst || type == PurchaseType.import)
          SizedBox(
            width: 120,
            child: DropdownButtonFormField<int>(
              value: r.gstRate,
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
    // Always-visible Utility content (removed ExpansionTile per request)
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        SizedBox(width: 320, child: TextFormField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notes'))),
        SizedBox(width: 200, child: TextFormField(controller: utilityAmountCtrl, decoration: const InputDecoration(labelText: 'Amount ₹'), keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}))),
        if (type == PurchaseType.creditNote || type == PurchaseType.debitNote)
          SizedBox(width: 260, child: TextFormField(controller: linkedInvoiceCtrl, decoration: const InputDecoration(labelText: 'Linked Invoice No'))),
      ],
    );
  }

  // Combined horizontal layout for Summary + Payment to better use dialog width
  Widget _buildSummaryAndPayment(_Totals totals, double balance) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth > 700;
        final summaryContent = _buildSummary(totals); // already a Wrap of kv chips / fields
        final paymentContent = _buildPayment(balance); // Wrap with text field + balance chip

        if (!horizontal) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              summaryContent,
              const SizedBox(height: 12),
              paymentContent,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: summaryContent),
            const SizedBox(width: 32),
            Expanded(child: paymentContent),
          ],
        );
      },
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
      'explicitSave': true,
      'type': _purchaseTypeLabel(type),
      'supplier': supplierCtrl.text.trim(),
      'invoiceNo': invoiceNoCtrl.text.trim(),
      'invoiceDate': invoiceDate.toIso8601String(),
      'paymentMode': paymentMode,
      'items': [
        for (final r in items)
          {
            if (r.sku != null) 'sku': r.sku,
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
  String? sku; // selected inventory sku (if chosen via autocomplete)
  _ItemRow({required this.name, required this.qty, required this.price, required this.gstRate});
  void dispose() { name.dispose(); qty.dispose(); price.dispose(); }
}

String _fmtDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Firestore suppliers dropdown (global 'suppliers' collection)
class _SupplierDropdown extends StatefulWidget {
  final TextEditingController controller;
  final bool autofocus;
  const _SupplierDropdown({required this.controller, this.autofocus = false});
  @override
  State<_SupplierDropdown> createState() => _SupplierDropdownState();
}

class _SupplierDropdownState extends State<_SupplierDropdown> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('suppliers').orderBy('name').snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return TextFormField(
            controller: widget.controller,
            autofocus: widget.autofocus,
            decoration: const InputDecoration(labelText: 'Supplier (error)'),
          );
        }
        if (!snap.hasData) {
          return const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)));
        }
        final docs = snap.data!.docs;
        final items = docs.map((d) => (d.data()['name'] ?? '') as String).where((s) => s.isNotEmpty).toList();
        // Ensure current value present
        final current = widget.controller.text;
        if (current.isNotEmpty && !items.contains(current)) items.add(current);
        return DropdownButtonFormField<String>(
          isExpanded: true,
            value: current.isEmpty ? null : current,
            items: items
                .map((s) => DropdownMenuItem<String>(value: s, child: Text(s)))
                .toList(),
            onChanged: (v) {
              widget.controller.text = v ?? '';
            },
            decoration: const InputDecoration(labelText: 'Supplier Name'),
            hint: const Text('Select supplier'),
          );
      },
    );
  }
}

// Lightweight product model for autocomplete list
class _ProductLite {
  final String sku;
  final String name;
  final double unitPrice;
  final double? taxPct;
  const _ProductLite({required this.sku, required this.name, required this.unitPrice, this.taxPct});
}

typedef _ProductSelCallback = void Function(_ProductLite? product);

class _ProductAutocomplete extends StatefulWidget {
  final TextEditingController controller;
  final List<_ProductLite> products;
  final _ProductSelCallback onProductSelected;
  final String? initialSku;
  const _ProductAutocomplete({
    required this.controller,
    required this.products,
    required this.onProductSelected,
    this.initialSku,
  });
  @override
  State<_ProductAutocomplete> createState() => _ProductAutocompleteState();
}

class _ProductAutocompleteState extends State<_ProductAutocomplete> {
  _ProductLite? _selected;
  List<_ProductLite> _filtered = const [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.products;
    if (widget.initialSku != null) {
      _selected = widget.products.firstWhere(
        (p) => p.sku == widget.initialSku,
        orElse: () => _ProductLite(sku: widget.initialSku!, name: widget.controller.text, unitPrice: 0),
      );
    }
  }

  @override
  void didUpdateWidget(covariant _ProductAutocomplete oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Refresh filtered list when master list changes
    final query = widget.controller.text.trim();
    _applyFilter(query);
    if (_selected != null) {
      final match = widget.products.where((p) => p.sku == _selected!.sku).toList();
      if (match.isNotEmpty) _selected = match.first;
    }
  }

  void _applyFilter(String input) {
    final q = input.toLowerCase();
    setState(() {
      final base = widget.products; // may be empty but never null
      if (base.isEmpty) { _filtered = const []; return; }
      if (q.isEmpty) { _filtered = base.take(25).toList(); return; }
      _filtered = base
          .where((p) => p.name.toLowerCase().contains(q) || p.sku.toLowerCase().contains(q))
          .take(25)
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<_ProductLite>(
      initialValue: TextEditingValue(text: widget.controller.text),
      displayStringForOption: (opt) => opt.name,
      optionsBuilder: (textEditingValue) {
        try {
          _applyFilter(textEditingValue.text);
          return _filtered;
        } catch (_) {
          return const <_ProductLite>[]; // fail safe
        }
      },
      onSelected: (opt) {
        widget.controller.text = opt.name;
        _selected = opt;
        widget.onProductSelected(opt);
      },
      fieldViewBuilder: (ctx, textCtrl, focusNode, onSubmit) {
        // Keep external controller in sync
        textCtrl.text = widget.controller.text;
        textCtrl.selection = TextSelection.collapsed(offset: textCtrl.text.length);
        textCtrl.addListener(() {
          widget.controller.text = textCtrl.text;
          if (textCtrl.text.trim().isEmpty) {
            widget.onProductSelected(null);
          }
        });
        return TextFormField(
          controller: textCtrl,
          focusNode: focusNode,
            decoration: InputDecoration(
              labelText: 'Item / Product',
              suffixIcon: _selected == null
                  ? const Icon(Icons.search)
                  : Tooltip(
                      message: 'Selected: ${_selected!.sku}',
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _selected = null;
                            widget.onProductSelected(null);
                          });
                        },
                        child: const Icon(Icons.check_circle, color: Colors.green),
                      ),
                    ),
            ),
        );
      },
      optionsViewBuilder: (ctx, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 250, maxWidth: 360),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: options.length,
                itemBuilder: (c, i) {
                  final opt = options.elementAt(i);
                  return ListTile(
                    dense: true,
                    title: Text(opt.name),
                    subtitle: Text('SKU: ${opt.sku}  •  ₹${opt.unitPrice.toStringAsFixed(2)}${opt.taxPct != null ? '  •  Tax ${opt.taxPct!.toStringAsFixed(0)}%' : ''}'),
                    onTap: () => onSelected(opt),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
