import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:retail_mvp2/core/theme/theme_extension_helpers.dart';
import 'package:retail_mvp2/core/paging/infinite_scroll_controller.dart';
import 'package:retail_mvp2/core/firebase/firestore_pagination_helper.dart';
import 'package:retail_mvp2/core/loading/page_loading_state_widget.dart';
import 'package:retail_mvp2/core/firestore_store_collections.dart';
import 'package:retail_mvp2/modules/stores/providers.dart';

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

class PurchaseInvoiceDialog extends ConsumerStatefulWidget {
  final String? existingId;
  final Map<String, dynamic>? existingData;
  const PurchaseInvoiceDialog({super.key, this.existingId, this.existingData});

  @override
  ConsumerState<PurchaseInvoiceDialog> createState() => _PurchaseInvoiceDialogState();
}

class _PurchaseInvoiceDialogState extends ConsumerState<PurchaseInvoiceDialog> {
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
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _invSub;

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
    // Load inventory products stream and keep a handle so we can cancel on dispose
    final sid = ref.read(selectedStoreIdProvider);
    if (sid == null) {
      if (mounted) setState(() => _products = const <_ProductLite>[]);
    } else {
      _invSub = StoreRefs.of(sid).products().snapshots().listen((snap) {
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
      }, onError: (_) {
        // Ignore transient errors (e.g., during logout teardown on web)
      });
    }
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
    _invSub?.cancel();
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
    final size = MediaQuery.of(context).size;
    final double contentWidth = size.width > 860 ? 820 : (size.width - 24).clamp(320, 820);
    final double contentHeight = size.height > 700 ? 620 : (size.height - 24).clamp(420, 620);
    final cs = Theme.of(context).colorScheme;
    final sizes = context.sizes;
    final isNarrow = size.width < 600;
    
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: context.radiusMd),
      backgroundColor: cs.surface,
      child: Container(
        width: contentWidth,
        height: contentHeight + 120,
        decoration: BoxDecoration(
          borderRadius: context.radiusMd,
          color: cs.surface,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Modern header
            Container(
              padding: EdgeInsets.fromLTRB(isNarrow ? sizes.gapMd : sizes.gapMd, sizes.gapMd, sizes.gapMd, sizes.gapMd),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(0.3),
                borderRadius: BorderRadius.vertical(top: Radius.circular(sizes.radiusMd)),
                border: Border(bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.3))),
              ),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(sizes.gapSm),
                    decoration: BoxDecoration(
                      color: cs.primary.withOpacity(0.1),
                      borderRadius: context.radiusSm,
                    ),
                    child: Icon(Icons.shopping_cart_rounded, size: sizes.iconMd, color: cs.primary),
                  ),
                  SizedBox(width: sizes.gapMd),
                  Expanded(
                    child: Text(
                      widget.existingId == null ? 'New Purchase Invoice' : 'Edit Purchase Invoice',
                      style: TextStyle(fontSize: sizes.fontMd, fontWeight: FontWeight.w700, color: cs.onSurface),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            // Content
            Expanded(
              child: Scrollbar(
                controller: _scrollCtrl,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _scrollCtrl,
                  padding: EdgeInsets.all(sizes.gapMd),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildModernSection('Header', Icons.description_rounded, _buildModernHeader(cs, isNarrow)),
                      context.gapVLg,
                      if (type == PurchaseType.gst || type == PurchaseType.import) ...[
                        _buildModernSection('Supplier & Invoice Details', Icons.business_rounded, _buildModernSupplierInvoice(cs)),
                        context.gapVLg,
                      ],
                      _buildModernSection('Utility', Icons.settings_rounded, _buildModernAdvanced(cs)),
                      context.gapVLg,
                      _buildModernItemsSection(cs, isNarrow),
                      context.gapVLg,
                      _buildModernSection('Summary & Payment', Icons.calculate_rounded, _buildModernSummaryAndPayment(totals, balance, cs)),
                    ],
                  ),
                ),
              ),
            ),
            // Footer actions
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(0.3),
                border: Border(top: BorderSide(color: cs.outlineVariant.withOpacity(0.3))),
              ),
              child: Row(
                children: [
                  if (widget.existingId != null) ...[
                    TextButton.icon(
                      onPressed: _handleDelete,
                      icon: Icon(Icons.delete_outline_rounded, size: 18, color: cs.error),
                      label: Text('Delete', style: TextStyle(color: cs.error)),
                    ),
                    const Spacer(),
                  ] else
                    const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel', style: TextStyle(color: cs.onSurfaceVariant)),
                  ),
                  context.gapHSm,
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [cs.primary, cs.primary.withOpacity(0.8)]),
                      borderRadius: context.radiusSm,
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _handleSave,
                        borderRadius: context.radiusSm,
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: context.sizes.gapLg, vertical: context.sizes.gapSm),
                          child: Text('Save', style: TextStyle(fontSize: context.sizes.fontSm, fontWeight: FontWeight.w600, color: cs.onPrimary)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernSection(String title, IconData icon, Widget content) {
    final cs = Theme.of(context).colorScheme;
    final sizes = context.sizes;
    return Container(
      padding: EdgeInsets.all(sizes.gapMd),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.2),
        borderRadius: context.radiusSm,
        border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(sizes.gapXs),
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(sizes.radiusSm),
                ),
                child: Icon(icon, size: sizes.iconSm, color: cs.primary),
              ),
              SizedBox(width: sizes.gapSm),
              Text(title, style: TextStyle(fontSize: sizes.fontSm, fontWeight: FontWeight.w700, color: cs.onSurface)),
            ],
          ),
          SizedBox(height: sizes.gapMd),
          content,
        ],
      ),
    );
  }

  Widget _buildModernHeader(ColorScheme cs, bool isNarrow) {
    final sid = ref.watch(selectedStoreIdProvider);
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _buildCompactDropdown<PurchaseType>(
          value: type,
          items: PurchaseType.values.map((t) => DropdownMenuItem(value: t, child: Text(_purchaseTypeLabel(t)))).toList(),
          onChanged: (v) => setState(() => type = v ?? type),
          label: 'Purchase Type',
          width: isNarrow ? double.infinity : 160,
          cs: cs,
        ),
        SizedBox(
          width: isNarrow ? double.infinity : 200,
          child: sid == null
              ? _buildCompactTextField(supplierCtrl, 'Supplier', cs)
              : _ModernSupplierDropdown(controller: supplierCtrl, storeId: sid, cs: cs),
        ),
        _buildCompactDateField('Invoice Date', invoiceDate, (d) => setState(() => invoiceDate = d), cs, isNarrow ? double.infinity : 140),
        _buildCompactDropdown<String>(
          value: paymentMode,
          items: const [
            DropdownMenuItem(value: 'Cash', child: Text('Cash')),
            DropdownMenuItem(value: 'Bank', child: Text('Bank')),
          ],
          onChanged: (v) => setState(() => paymentMode = v ?? paymentMode),
          label: 'Payment Mode',
          width: isNarrow ? double.infinity : 120,
          cs: cs,
        ),
      ],
    );
  }

  Widget _buildModernSupplierInvoice(ColorScheme cs) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _buildCompactTextField(invoiceNoCtrl, 'Invoice No', cs, width: 140),
        if (type == PurchaseType.gst || type == PurchaseType.import)
          _buildCompactTextField(gstinCtrl, 'Supplier GSTIN', cs, width: 160),
        _buildCompactTextField(addressCtrl, 'Supplier Address', cs, width: 260),
      ],
    );
  }

  Widget _buildModernAdvanced(ColorScheme cs) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _buildCompactTextField(notesCtrl, 'Notes', cs, width: 260),
        _buildCompactTextField(utilityAmountCtrl, 'Amount ₹', cs, width: 140, isNumber: true, onChanged: (_) => setState(() {})),
        if (type == PurchaseType.creditNote || type == PurchaseType.debitNote)
          _buildCompactTextField(linkedInvoiceCtrl, 'Linked Invoice No', cs, width: 180),
      ],
    );
  }

  Widget _buildModernItemsSection(ColorScheme cs, bool isNarrow) {
    final sizes = context.sizes;
    return Container(
      padding: EdgeInsets.all(sizes.gapMd),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.2),
        borderRadius: context.radiusMd,
        border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(sizes.gapXs),
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.1),
                  borderRadius: context.radiusSm,
                ),
                child: Icon(Icons.shopping_bag_rounded, size: sizes.iconXs, color: cs.primary),
              ),
              SizedBox(width: sizes.gapSm),
              Text('Items', style: TextStyle(fontSize: sizes.fontSm, fontWeight: FontWeight.w700, color: cs.onSurface)),
              const Spacer(),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => setState(() => items.add(_ItemRow(name: TextEditingController(), qty: TextEditingController(text: '1'), price: TextEditingController(text: '0'), gstRate: 0))),
                  borderRadius: context.radiusSm,
                  child: Container(
                    padding: EdgeInsets.all(sizes.gapXs),
                    decoration: BoxDecoration(
                      color: cs.primary.withOpacity(0.1),
                      borderRadius: context.radiusSm,
                    ),
                    child: Icon(Icons.add_rounded, size: sizes.iconSm, color: cs.primary),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: sizes.gapMd),
          for (int i = 0; i < items.length; i++) _buildModernItemRow(i, cs, isNarrow),
        ],
      ),
    );
  }

  Widget _buildModernItemRow(int index, ColorScheme cs, bool isNarrow) {
    final sizes = context.sizes;
    final r = items[index];
    
    if (isNarrow) {
      return Container(
        margin: EdgeInsets.only(bottom: sizes.gapSm),
        padding: EdgeInsets.all(sizes.gapSm),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: context.radiusSm,
          border: Border.all(color: cs.outlineVariant.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _ModernProductAutocomplete(
                    controller: r.name,
                    initialSku: r.sku,
                    onProductSelected: (prod) => _onProductSelected(r, prod),
                    products: _products,
                    cs: cs,
                  ),
                ),
                IconButton(
                  onPressed: items.length <= 1 ? null : () => setState(() { items.removeAt(index).dispose(); }),
                  icon: Icon(Icons.close_rounded, size: 18, color: cs.error.withOpacity(0.7)),
                ),
              ],
            ),
            SizedBox(height: sizes.gapSm),
            Row(
              children: [
                Expanded(child: _buildCompactTextField(r.qty, 'Qty', cs, isNumber: true, onChanged: (_) => setState(() {}))),
                SizedBox(width: sizes.gapSm),
                Expanded(child: _buildCompactTextField(r.price, 'Unit Price ₹', cs, isNumber: true, onChanged: (_) => setState(() {}))),
              ],
            ),
            if (type == PurchaseType.gst || type == PurchaseType.import) ...[
              SizedBox(height: sizes.gapSm),
              Row(
                children: [
                  Expanded(
                    child: _buildCompactDropdown<int>(
                      value: r.gstRate,
                      items: const [0, 5, 12, 18, 28].map((v) => DropdownMenuItem(value: v, child: Text('GST $v%'))).toList(),
                      onChanged: (v) => setState(() => r.gstRate = v ?? r.gstRate),
                      label: 'Tax Rate',
                      cs: cs,
                    ),
                  ),
                  SizedBox(width: sizes.gapSm),
                  Expanded(child: _buildAmountDisplay((double.tryParse(r.qty.text) ?? 0) * (double.tryParse(r.price.text) ?? 0), cs)),
                ],
              ),
            ] else
              Padding(
                padding: EdgeInsets.only(top: sizes.gapSm),
                child: _buildAmountDisplay((double.tryParse(r.qty.text) ?? 0) * (double.tryParse(r.price.text) ?? 0), cs),
              ),
          ],
        ),
      );
    }

    return Container(
      margin: EdgeInsets.only(bottom: sizes.gapSm),
      padding: EdgeInsets.symmetric(horizontal: sizes.gapSm, vertical: sizes.gapSm),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: context.radiusSm,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: _ModernProductAutocomplete(
              controller: r.name,
              initialSku: r.sku,
              onProductSelected: (prod) => _onProductSelected(r, prod),
              products: _products,
              cs: cs,
            ),
          ),
          SizedBox(width: sizes.gapSm),
          SizedBox(width: 70, child: _buildCompactTextField(r.qty, 'Qty', cs, isNumber: true, onChanged: (_) => setState(() {}))),
          SizedBox(width: sizes.gapSm),
          SizedBox(width: 100, child: _buildCompactTextField(r.price, 'Unit Price ₹', cs, isNumber: true, onChanged: (_) => setState(() {}))),
          if (type == PurchaseType.gst || type == PurchaseType.import) ...[
            SizedBox(width: sizes.gapSm),
            SizedBox(
              width: 100,
              child: _buildCompactDropdown<int>(
                value: r.gstRate,
                items: const [0, 5, 12, 18, 28].map((v) => DropdownMenuItem(value: v, child: Text('GST $v%'))).toList(),
                onChanged: (v) => setState(() => r.gstRate = v ?? r.gstRate),
                label: 'Tax',
                cs: cs,
              ),
            ),
          ],
          SizedBox(width: sizes.gapSm),
          SizedBox(width: 90, child: _buildAmountDisplay((double.tryParse(r.qty.text) ?? 0) * (double.tryParse(r.price.text) ?? 0), cs)),
          IconButton(
            onPressed: items.length <= 1 ? null : () => setState(() { items.removeAt(index).dispose(); }),
            icon: Icon(Icons.close_rounded, size: 18, color: cs.error.withOpacity(0.7)),
          ),
        ],
      ),
    );
  }

  void _onProductSelected(_ItemRow r, _ProductLite? prod) {
    setState(() {
      r.sku = prod?.sku;
      if ((r.price.text.trim().isEmpty || r.price.text == '0') && prod != null) {
        r.price.text = prod.unitPrice.toStringAsFixed(2);
      }
      if ((type == PurchaseType.gst || type == PurchaseType.import) && prod?.taxPct != null) {
        r.gstRate = (prod!.taxPct ?? 0).toInt();
      }
    });
  }

  Widget _buildAmountDisplay(double amount, ColorScheme cs) {
    final sizes = context.sizes;
    return Container(
      height: sizes.inputHeightSm,
      padding: EdgeInsets.symmetric(horizontal: sizes.gapSm),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: context.radiusSm,
      ),
      alignment: Alignment.centerLeft,
      child: Text('₹${amount.toStringAsFixed(2)}', style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w600, color: cs.primary)),
    );
  }

  Widget _buildModernSummaryAndPayment(_Totals totals, double balance, ColorScheme cs) {
    return Wrap(
      spacing: 16,
      runSpacing: 12,
      children: [
        if (type == PurchaseType.gst) ...[
          _buildSummaryChip('CGST', totals.cgst, cs),
          _buildSummaryChip('SGST', totals.sgst, cs),
          _buildSummaryChip('IGST', totals.igst, cs),
          _buildCompactTextField(cessCtrl, 'CESS ₹', cs, width: 100, isNumber: true, onChanged: (_) => setState(() {})),
        ],
        if (type == PurchaseType.import) ...[
          _buildCompactTextField(freightCtrl, 'Freight ₹', cs, width: 100, isNumber: true, onChanged: (_) => setState(() {})),
          _buildCompactTextField(customsCtrl, 'Customs ₹', cs, width: 110, isNumber: true, onChanged: (_) => setState(() {})),
          _buildSummaryChip('IGST', totals.igst, cs),
        ],
        _buildSummaryChip('Grand Total', totals.grand, cs, highlight: true),
        _buildCompactTextField(paidCtrl, 'Paid ₹', cs, width: 110, isNumber: true, onChanged: (_) => setState(() {})),
        _buildSummaryChip('Balance', balance, cs, isBalance: true),
      ],
    );
  }

  Widget _buildSummaryChip(String label, double value, ColorScheme cs, {bool highlight = false, bool isBalance = false}) {
    final sizes = context.sizes;
    final color = isBalance ? (value > 0 ? context.appColors.warning : context.appColors.success) : (highlight ? cs.primary : cs.onSurface);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: sizes.gapSm, vertical: sizes.gapSm),
      decoration: BoxDecoration(
        color: highlight ? cs.primary.withOpacity(0.1) : cs.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: context.radiusSm,
        border: highlight ? Border.all(color: cs.primary.withOpacity(0.3)) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurfaceVariant)),
          SizedBox(width: sizes.gapXs),
          Text('₹${value.toStringAsFixed(2)}', style: TextStyle(fontSize: sizes.fontXs, fontWeight: highlight ? FontWeight.w700 : FontWeight.w600, color: color)),
        ],
      ),
    );
  }

  Widget _buildCompactTextField(TextEditingController ctrl, String label, ColorScheme cs, {double? width, bool isNumber = false, ValueChanged<String>? onChanged}) {
    final sizes = context.sizes;
    final field = Container(
      height: sizes.inputHeightSm,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: context.radiusSm,
        border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
      ),
      child: TextFormField(
        controller: ctrl,
        style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurface),
        keyboardType: isNumber ? const TextInputType.numberWithOptions(decimal: true) : null,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(fontSize: sizes.fontXs, color: cs.onSurfaceVariant),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: sizes.gapSm, vertical: sizes.gapSm),
          isDense: true,
        ),
        onChanged: onChanged,
      ),
    );
    return width != null ? SizedBox(width: width, child: field) : field;
  }

  Widget _buildCompactDropdown<T>({required T value, required List<DropdownMenuItem<T>> items, required ValueChanged<T?> onChanged, required String label, double? width, required ColorScheme cs}) {
    final sizes = context.sizes;
    final dropdown = Container(
      height: sizes.inputHeightSm,
      padding: EdgeInsets.symmetric(horizontal: sizes.gapSm),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: context.radiusSm,
        border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          style: TextStyle(fontSize: context.sizes.fontXs, color: cs.onSurface),
          icon: Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: cs.onSurfaceVariant),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
    return width != null ? SizedBox(width: width, child: dropdown) : dropdown;
  }

  Widget _buildCompactDateField(String label, DateTime value, ValueChanged<DateTime> onChanged, ColorScheme cs, double width) {
    final sizes = context.sizes;
    return SizedBox(
      width: width,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              firstDate: DateTime(2020),
              lastDate: DateTime(2100),
              initialDate: value,
            );
            if (picked != null) onChanged(picked);
          },
          borderRadius: context.radiusSm,
          child: Container(
            height: sizes.inputHeightSm,
            padding: EdgeInsets.symmetric(horizontal: sizes.gapSm),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: context.radiusSm,
              border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Expanded(child: Text(_fmtDate(value), style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurface))),
                Icon(Icons.calendar_today_rounded, size: sizes.iconXs, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleDelete() async {
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final cs = Theme.of(context).colorScheme;
    final sizes = context.sizes;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: context.radiusMd),
        title: Text('Delete invoice?', style: TextStyle(fontSize: sizes.fontMd, fontWeight: FontWeight.w700, color: cs.onSurface)),
        content: Text(
          'This will permanently delete this purchase invoice. This action cannot be undone.',
          style: TextStyle(fontSize: sizes.fontSm, color: cs.onSurfaceVariant),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: TextStyle(color: cs.onSurfaceVariant))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _deleteInvoice();
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Invoice deleted')));
      if (nav.mounted) nav.pop();
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  void _handleSave() {
    if (supplierCtrl.text.trim().isEmpty) {
      _toast(context, 'Enter supplier');
      return;
    }
    final hasItemValue = items.any((r) => (double.tryParse(r.qty.text) ?? 0) * (double.tryParse(r.price.text) ?? 0) > 0);
    if (!hasItemValue) {
      final utilAmt = double.tryParse(utilityAmountCtrl.text) ?? 0;
      final utilityMode = (type == PurchaseType.import || type == PurchaseType.noBill) && utilAmt > 0;
      if (!utilityMode) {
        _toast(context, 'Enter at least one item amount or utility amount');
        return;
      }
    }
    final payload = _buildPurchasePayload();
    if ((payload['invoiceNo'] as String).isEmpty) {
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
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    maybeGen().then((gen) {
      if (gen != null) payload['invoiceNo'] = gen;
      return _saveToFirestore(payload);
    }).then((_) {
      if (mounted && widget.existingId == null) {
        _applyInventoryAdjustments(payload).catchError((e){
          if (!mounted) return;
          messenger.showSnackBar(SnackBar(content: Text('Inventory update failed: $e')));
        });
      }
      if (mounted) {
        nav.pop();
        messenger.showSnackBar(const SnackBar(content: Text('Purchase saved')));
      }
    }).catchError((e) { if (mounted) messenger.showSnackBar(SnackBar(content: Text('Save failed: $e'))); return null; });
  }

  Future<void> _deleteInvoice() async {
    final id = widget.existingId;
    if (id == null || id.isEmpty) return;
    final sid = ref.read(selectedStoreIdProvider);
    if (sid == null) throw Exception('No store selected');
    final col = StoreRefs.of(sid).purchaseInvoices();
    await col.doc(id).delete();
    // Note: We are not auto-reversing inventory stock here to avoid unintended side effects.
    // If required later, implement a safe reversal flow with audit and proper confirmation.
  }

  Future<void> _saveToFirestore(Map<String, dynamic> data) async {
    final sid = ref.read(selectedStoreIdProvider);
    if (sid == null) throw Exception('No store selected');
    final col = StoreRefs.of(sid).purchaseInvoices();
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
  final sid = ref.read(selectedStoreIdProvider);
  if (sid == null) return; // cannot adjust without store context
    const warehouseLoc = 'Warehouse';
    const storeLoc = 'Store'; // preserved if present
    // Run sequential transactions (could be parallel but Firestore limits 500 ops anyway)
    for (final entry in skuQty.entries) {
      final sku = entry.key;
      final addQty = entry.value;
      final docRef = StoreRefs.of(sid, fs: db).products().doc(sku);
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
    final sid = ref.read(selectedStoreIdProvider);
    if (sid == null) throw Exception('No store selected');
    final countersRef = FirebaseFirestore.instance.collection('stores').doc(sid).collection('meta').doc('purchase_counters');
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

// Lightweight product model for autocomplete list
class _ProductLite {
  final String sku;
  final String name;
  final double unitPrice;
  final double? taxPct;
  const _ProductLite({required this.sku, required this.name, required this.unitPrice, this.taxPct});
}

typedef _ProductSelCallback = void Function(_ProductLite? product);

/// Modern Firestore suppliers dropdown
class _ModernSupplierDropdown extends StatefulWidget {
  final TextEditingController controller;
  final String storeId;
  final ColorScheme cs;
  const _ModernSupplierDropdown({required this.controller, required this.storeId, required this.cs});
  @override
  State<_ModernSupplierDropdown> createState() => _ModernSupplierDropdownState();
}

class _ModernSupplierDropdownState extends State<_ModernSupplierDropdown> {
  @override
  Widget build(BuildContext context) {
    final sizes = context.sizes;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: StoreRefs.of(widget.storeId).suppliers().orderBy('name').snapshots(),
      builder: (context, snap) {
        final cs = widget.cs;
        if (snap.hasError) {
          return Container(
            height: sizes.inputHeightSm,
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: context.radiusSm,
              border: Border.all(color: cs.error.withOpacity(0.5)),
            ),
            padding: EdgeInsets.symmetric(horizontal: sizes.gapSm),
            alignment: Alignment.centerLeft,
            child: Text('Error loading suppliers', style: TextStyle(fontSize: sizes.fontXs, color: cs.error)),
          );
        }
        if (!snap.hasData) {
          return Container(
            height: sizes.inputHeightSm,
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: context.radiusSm,
              border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
            ),
            alignment: Alignment.center,
            child: SizedBox(width: sizes.iconSm, height: sizes.iconSm, child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary)),
          );
        }
        final docs = snap.data!.docs;
        final items = docs.map((d) => (d.data()['name'] ?? '') as String).where((s) => s.isNotEmpty).toList();
        final current = widget.controller.text;
        if (current.isNotEmpty && !items.contains(current)) items.add(current);
        return Container(
          height: sizes.inputHeightSm,
          padding: EdgeInsets.symmetric(horizontal: sizes.gapSm),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: context.radiusSm,
            border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: current.isEmpty ? null : (items.contains(current) ? current : null),
              hint: Text('Select supplier', style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurfaceVariant)),
              isExpanded: true,
              style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurface),
              icon: Icon(Icons.keyboard_arrow_down_rounded, size: sizes.iconSm, color: cs.onSurfaceVariant),
              items: items.map((s) => DropdownMenuItem<String>(value: s, child: Text(s))).toList(),
              onChanged: (v) => setState(() => widget.controller.text = v ?? ''),
            ),
          ),
        );
      },
    );
  }
}

/// Modern product autocomplete widget
class _ModernProductAutocomplete extends StatefulWidget {
  final TextEditingController controller;
  final List<_ProductLite> products;
  final _ProductSelCallback onProductSelected;
  final String? initialSku;
  final ColorScheme cs;
  const _ModernProductAutocomplete({
    required this.controller,
    required this.products,
    required this.onProductSelected,
    required this.cs,
    this.initialSku,
  });
  @override
  State<_ModernProductAutocomplete> createState() => _ModernProductAutocompleteState();
}

class _ModernProductAutocompleteState extends State<_ModernProductAutocomplete> {
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
  void didUpdateWidget(covariant _ModernProductAutocomplete oldWidget) {
    super.didUpdateWidget(oldWidget);
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
      final base = widget.products;
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
    final cs = widget.cs;
    return Autocomplete<_ProductLite>(
      initialValue: TextEditingValue(text: widget.controller.text),
      displayStringForOption: (opt) => opt.name,
      optionsBuilder: (textEditingValue) {
        try {
          _applyFilter(textEditingValue.text);
          return _filtered;
        } catch (_) {
          return const <_ProductLite>[];
        }
      },
      onSelected: (opt) {
        widget.controller.text = opt.name;
        _selected = opt;
        widget.onProductSelected(opt);
      },
      fieldViewBuilder: (ctx, textCtrl, focusNode, onSubmit) {
        final sizes = context.sizes;
        textCtrl.text = widget.controller.text;
        textCtrl.selection = TextSelection.collapsed(offset: textCtrl.text.length);
        textCtrl.addListener(() {
          widget.controller.text = textCtrl.text;
          if (textCtrl.text.trim().isEmpty) {
            widget.onProductSelected(null);
          }
        });
        return Container(
          height: sizes.inputHeightSm,
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: context.radiusSm,
            border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
          ),
          child: TextFormField(
            controller: textCtrl,
            focusNode: focusNode,
            style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurface),
            decoration: InputDecoration(
              labelText: 'Item / Product',
              labelStyle: TextStyle(fontSize: sizes.fontXs, color: cs.onSurfaceVariant),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: sizes.gapSm, vertical: sizes.gapSm),
              isDense: true,
              suffixIcon: _selected == null
                  ? Icon(Icons.search_rounded, size: sizes.iconSm, color: cs.onSurfaceVariant)
                  : InkWell(
                      onTap: () => setState(() { _selected = null; widget.onProductSelected(null); }),
                      child: Icon(Icons.check_circle_rounded, size: sizes.iconSm, color: cs.primary),
                    ),
            ),
          ),
        );
      },
      optionsViewBuilder: (ctx, onSelected, options) {
        final sizes = context.sizes;
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: context.radiusSm,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 200, maxWidth: 340),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: context.radiusSm,
                border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
              ),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (c, i) {
                  final opt = options.elementAt(i);
                  return InkWell(
                    onTap: () => onSelected(opt),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: sizes.gapMd, vertical: sizes.gapSm),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.2))),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(opt.name, style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurface)),
                          SizedBox(height: sizes.gapXs / 2),
                          Text(
                            'SKU: ${opt.sku}  •  ₹${opt.unitPrice.toStringAsFixed(2)}${opt.taxPct != null ? '  •  Tax ${opt.taxPct!.toStringAsFixed(0)}%' : ''}',
                            style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
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

// Simple wrapper page used by router for Purchases invoices list
class PurchasesInvoicesScreen extends ConsumerWidget {
  const PurchasesInvoicesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sid = ref.watch(selectedStoreIdProvider);
    final cs = Theme.of(context).colorScheme;
    final sizes = context.sizes;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [cs.primary.withOpacity(0.04), cs.surface],
            stops: const [0.0, 0.3],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(sizes.gapMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Modern button
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [cs.primary, cs.primary.withOpacity(0.8)]),
                  borderRadius: context.radiusMd,
                  boxShadow: [BoxShadow(color: cs.primary.withOpacity(0.25), blurRadius: 8, offset: const Offset(0, 2))],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () async {
                      await showPurchaseInvoiceDialog(context);
                      ref.read(purchaseInvoicesPagedControllerProvider).resetAndLoad();
                    },
                    borderRadius: context.radiusMd,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: sizes.gapMd, vertical: sizes.gapSm),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_shopping_cart_rounded, size: sizes.iconMd, color: cs.onPrimary),
                          SizedBox(width: sizes.gapSm),
                          Text('New Purchase Invoice', style: TextStyle(fontSize: sizes.fontSm, fontWeight: FontWeight.w600, color: cs.onPrimary)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: sizes.gapMd),
              Expanded(
                child: sid == null
                    ? Center(child: Text('Select a store to view purchase invoices', style: TextStyle(color: cs.onSurfaceVariant)))
                    : const _PurchasesList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Purchase invoices list (replaces legacy _PurchasesList from invoices_tabs.dart)
class _PurchasesList extends ConsumerStatefulWidget {
  const _PurchasesList();
  @override
  ConsumerState<_PurchasesList> createState() => _PurchasesListState();
}

class _PurchasesListState extends ConsumerState<_PurchasesList> {
  final ScrollController _vScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _vScrollCtrl.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _vScrollCtrl.removeListener(_maybeLoadMore);
    _vScrollCtrl.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!_vScrollCtrl.hasClients) return;
    if (_vScrollCtrl.position.extentAfter < 600) {
      final c = ref.read(purchaseInvoicesPagedControllerProvider);
      final s = c.state;
      if (!s.loading && !s.endReached) c.loadMore();
    }
  }

  double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }

  String _fmtShortDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final d = DateTime.parse(iso);
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final paged = ref.watch(purchaseInvoicesPagedControllerProvider);
    final state = paged.state;
    final cs = Theme.of(context).colorScheme;
    final sizes = context.sizes;
    
    return PageLoaderOverlay(
      loading: state.loading && state.items.isEmpty,
      error: state.error,
      onRetry: () => ref.read(purchaseInvoicesPagedControllerProvider).resetAndLoad(),
      child: state.items.isEmpty && !state.loading
          ? Center(child: Text('No purchase invoices yet', style: TextStyle(color: cs.onSurfaceVariant)))
          : ListView.builder(
              controller: _vScrollCtrl,
              itemCount: state.items.length + (state.endReached ? 0 : 1),
              itemBuilder: (context, index) {
                if (index >= state.items.length) {
                  return Padding(
                    padding: EdgeInsets.symmetric(vertical: sizes.gapMd),
                    child: state.loading
                        ? Center(child: SizedBox(width: sizes.iconLg, height: sizes.iconLg, child: const CircularProgressIndicator(strokeWidth: 2)))
                        : Center(
                            child: TextButton.icon(
                              onPressed: () => ref.read(purchaseInvoicesPagedControllerProvider).loadMore(),
                              icon: Icon(Icons.expand_more_rounded, color: cs.primary),
                              label: Text('Load more', style: TextStyle(color: cs.primary)),
                            ),
                          ),
                  );
                }
                final item = state.items[index];
                final m = item.data;
                final supplier = (m['supplier'] ?? '') as String;
                final invoiceNo = (m['invoiceNo'] ?? '') as String;
                final type = (m['type'] ?? '') as String;
                final invoiceDate = _fmtShortDate(m['invoiceDate'] as String?);
                final sum = (m['summary'] as Map?) ?? const {};
                final grand = _asDouble(sum['grandTotal']);
                final paid = _asDouble(((m['payment'] as Map?) ?? const {})['paid']);

                return Container(
                  margin: EdgeInsets.only(bottom: sizes.gapSm),
                  decoration: BoxDecoration(
                    color: index.isEven ? cs.surface : cs.surfaceContainerHighest.withOpacity(0.3),
                    borderRadius: context.radiusMd,
                    border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () async {
                        await showEditPurchaseInvoiceDialog(context, item.id, m);
                        if (mounted) {
                          ref.read(purchaseInvoicesPagedControllerProvider).resetAndLoad();
                        }
                      },
                      borderRadius: context.radiusMd,
                      child: Padding(
                        padding: EdgeInsets.all(sizes.gapMd),
                        child: Row(
                          children: [
                            // Icon
                            Container(
                              padding: EdgeInsets.all(sizes.gapSm),
                              decoration: BoxDecoration(
                                color: cs.primary.withOpacity(0.1),
                                borderRadius: context.radiusMd,
                              ),
                              child: Icon(Icons.receipt_long_rounded, size: sizes.iconMd, color: cs.primary),
                            ),
                            SizedBox(width: sizes.gapMd),
                            // Content
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          supplier.isEmpty ? '(No supplier)' : supplier,
                                          style: TextStyle(fontSize: sizes.fontSm, fontWeight: FontWeight.w600, color: cs.onSurface),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (invoiceNo.isNotEmpty)
                                        Text(
                                          '#$invoiceNo',
                                          style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w500, color: cs.primary, fontFamily: 'monospace'),
                                        ),
                                    ],
                                  ),
                                  SizedBox(height: sizes.gapXs),
                                  Wrap(
                                    spacing: sizes.gapSm,
                                    runSpacing: sizes.gapXs,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      if (type.isNotEmpty)
                                        Container(
                                          padding: EdgeInsets.symmetric(horizontal: sizes.gapSm, vertical: sizes.gapXs / 2),
                                          decoration: BoxDecoration(
                                            color: cs.secondaryContainer.withOpacity(0.5),
                                            borderRadius: context.radiusMd,
                                          ),
                                          child: Text(type, style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w600, color: cs.onSecondaryContainer)),
                                        ),
                                      if (invoiceDate.isNotEmpty)
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.calendar_today_rounded, size: sizes.iconXs, color: cs.onSurfaceVariant),
                                            SizedBox(width: sizes.gapXs),
                                            Text(invoiceDate, style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurfaceVariant)),
                                          ],
                                        ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text('Total: ', style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurfaceVariant)),
                                          Text('₹${grand.toStringAsFixed(2)}', style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w600, color: cs.onSurface)),
                                        ],
                                      ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text('Paid: ', style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurfaceVariant)),
                                          Text('₹${paid.toStringAsFixed(2)}', style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w500, color: context.appColors.success)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(width: sizes.gapSm),
                            Icon(Icons.chevron_right_rounded, size: sizes.iconMd, color: cs.onSurfaceVariant),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class PurchaseListItem {
  final String id;
  final Map<String, dynamic> data;
  PurchaseListItem({required this.id, required this.data});
}

final purchaseInvoicesPagedControllerProvider = ChangeNotifierProvider.autoDispose<PagedListController<PurchaseListItem>>((ref) {
  final sid = ref.watch(selectedStoreIdProvider);
  final Query<Map<String, dynamic>>? base = (sid == null)
      ? null
      : StoreRefs.of(sid).purchaseInvoices().orderBy('timestampMs', descending: true);

  final controller = PagedListController<PurchaseListItem>(
    pageSize: 100,
    loadPage: (cursor) async {
      if (base == null) return (<PurchaseListItem>[], null);
      final after = cursor as DocumentSnapshot<Map<String, dynamic>>?;
      final (items, next) = await fetchFirestorePage<PurchaseListItem>(
        base: base,
        after: after,
        pageSize: 100,
        map: (d) => PurchaseListItem(id: d.id, data: d.data()),
      );
      return (items, next);
    },
  );

  Future.microtask(controller.resetAndLoad);
  ref.onDispose(controller.dispose);
  return controller;
});
