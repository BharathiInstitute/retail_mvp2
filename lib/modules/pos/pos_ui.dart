// POS UI separated from models (moved out of pos.dart)
// This file contains all UI widgets and stateful logic for the POS screen.
// Models & enums live in pos.dart to allow reuse without pulling in UI code.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'invoice_models.dart';
import 'invoice_pdf.dart' as pdf_gen; // For PDF generation (email attachment only; download removed)
import 'invoice_email_service.dart';
import 'pos.dart'; // models & enums
import 'pos_search_scan_fav.dart';
import '../inventory/inventory_repository.dart';
import 'pos_checkout.dart';

class PosPage extends StatefulWidget {
  const PosPage({super.key});

  @override
  State<PosPage> createState() => _PosPageState();
}

class _PosPageState extends State<PosPage> {
  // Firestore-backed products cache (for quick lookup by barcode/SKU)
  List<Product> _cacheProducts = [];

  // POS customers: Walk-in plus CRM customers from Firestore
  static final Customer walkIn = Customer(id: '', name: 'Walk-in Customer');
  List<Customer> customers = [walkIn];

  final TextEditingController barcodeCtrl = TextEditingController();
  final TextEditingController searchCtrl = TextEditingController();
  final TextEditingController customerSearchCtrl = TextEditingController();

  final Map<String, CartItem> cart = {};
  final List<HeldOrder> heldOrders = [];

  // Favorites: store product SKUs marked as favorite
  final Set<String> favoriteSkus = <String>{};
  late CartHoldController _holdController;

  DiscountType discountType = DiscountType.none;
  final TextEditingController discountCtrl = TextEditingController(text: '0');

  Customer? selectedCustomer;

  // Selected payment mode (simple)
  PaymentMode selectedPaymentMode = PaymentMode.cash;

  // Last generated invoice snapshot (for PDF/email after checkout)
  InvoiceData? lastInvoice;

  // --- Loyalty redemption state ---
  final TextEditingController _redeemPointsCtrl = TextEditingController(text: '0');
  double _availablePoints = 0; // loaded from customer doc when selected
  static const double _pointValue = 1; // 1 point = ₹1 (adjust if needed or load from settings)
  // Scroll controller for summary/payment panel (enables scrollbar & prevents overflow)
  final ScrollController _summaryScrollCtrl = ScrollController();
  // Active subscription to currently selected customer's document for live loyalty point updates
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _customerDocSub;

  // --- Physical scanner integration ---
  bool _scannerActive = false; // true while user is holding the Scan button (long press) or toggled
  final StringBuffer _scanBuffer = StringBuffer();
  DateTime? _lastKeyTime;
  DateTime? _lastSuccessfulScan; // last completed scan timestamp
  // Scan timeout gap threshold between key events for a single physical scan.
  // Made final to satisfy prefer_final_fields lint (tune by changing constant value).
  final Duration _scanTimeout = const Duration(milliseconds: 60); // gap threshold between fast key events
  Timer? _finalizeTimer;
  static const int _minScanLength = 3; // minimal length to consider a valid scan
  late final FocusNode _scannerFocusNode;

  String get invoiceNumber => 'INV-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
  late final String _backendBase; // resolved at runtime to support web/LAN
  bool _isPrinting = false; // UI guard for one-click print

  @override
  void initState() {
    super.initState();
    _backendBase = _resolveBackendBase();
    selectedCustomer = customers.first;
    // Fix discount mode to Percent (discount type selector removed)
    discountType = DiscountType.percent;
    // Preload CRM customers once to seed the dropdown/search
    _loadCustomersOnce();
    _scannerFocusNode = FocusNode(debugLabel: 'scannerFocus', skipTraversal: true);
    _holdController = CartHoldController(
      cart: cart,
      heldOrders: heldOrders,
      discountType: discountType,
      discountCtrl: discountCtrl,
      notify: () => setState(() {}),
      showMessage: _snack,
    );
  }

  String _resolveBackendBase() {
    const envUrl = String.fromEnvironment('PRINTER_BACKEND_URL', defaultValue: '');
    if (envUrl.isNotEmpty) return envUrl;
    if (kIsWeb) {
      final scheme = Uri.base.scheme == 'https' ? 'https' : 'http';
      final host = Uri.base.host.isEmpty ? 'localhost' : Uri.base.host;
      const port = 5005;
      return '$scheme://$host:$port';
    }
    return 'http://localhost:5005';
  }

  Future<void> _loadCustomersOnce() async {
    try {
      final first = await _customerStream.first;
      if (mounted) {
        setState(() {
          customers = first;
          if (!customers.contains(selectedCustomer)) {
            selectedCustomer = customers.first;
          }
        });
      }
    } catch (_) {
      // ignore failures; UI will still use stream builder later
    }
  }

  @override
  void dispose() {
    _finalizeTimer?.cancel();
    _customerDocSub?.cancel();
    _scannerFocusNode.dispose();
    barcodeCtrl.dispose();
    searchCtrl.dispose();
    customerSearchCtrl.dispose();
    discountCtrl.dispose();
    _redeemPointsCtrl.dispose();
    _summaryScrollCtrl.dispose();
    super.dispose();
  }

  // Stream CRM customers from Firestore `customers` collection
  Stream<List<Customer>> get _customerStream => FirebaseFirestore.instance
      .collection('customers')
      .snapshots()
      .map((snap) {
        final list = snap.docs.map((d) => Customer.fromDoc(d)).toList();
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        return [walkIn, ...list];
      });

  // Print Settings UI removed; printing now sends to backend default printer.
  Future<void> _quickPrintFromPanel() async {
    if (_isPrinting) return;
    await _oneClickPrintCurrentCart();
  }

  Future<void> _oneClickPrintCurrentCart() async {
    if (cart.isEmpty) {
      _snack('Cart empty');
      return;
    }
    setState(() => _isPrinting = true);
    try {
      final invoice = _buildTempInvoiceForPrint();
      final pdfBytes = await _buildThermalPdf(invoice, widthMm: 48, marginMm: 4, density: 8);
      final uri = Uri.parse('$_backendBase/print-pdf');
      final req = http.MultipartRequest('POST', uri)
        ..files.add(http.MultipartFile.fromBytes('file', pdfBytes, filename: 'pos_receipt.pdf'));
      final streamed = await req.send();
      final resp = await http.Response.fromStream(streamed);
      if (resp.statusCode == 200) {
        _snack('Printed');
      } else {
        _snack('Print failed: ${resp.statusCode}');
      }
    } catch (e) {
      _snack('Print error: $e');
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  InvoiceData _buildTempInvoiceForPrint() {
    final discounts = lineDiscounts;
    final taxes = lineTaxes;
    final taxesByRate = <int, double>{};
    for (final it in cart.values) {
      final tax = taxes[it.product.sku] ?? 0.0;
      taxesByRate.update(it.product.taxPercent, (v) => v + tax, ifAbsent: () => tax);
    }
    final lines = cart.values.map((it) {
      final lineSubtotal = it.product.price * it.qty;
      final disc = discounts[it.product.sku] ?? 0.0;
      final net = (lineSubtotal - disc).clamp(0, double.infinity);
      final tax = taxes[it.product.sku] ?? 0.0;
      final lineTotal = net + tax;
      return InvoiceLine(
        sku: it.product.sku,
        name: it.product.name,
        qty: it.qty,
        unitPrice: it.product.price,
        taxPercent: it.product.taxPercent,
        lineSubtotal: lineSubtotal,
        discount: disc,
        tax: tax,
        lineTotal: lineTotal,
      );
    }).toList();
    return InvoiceData(
      invoiceNumber: 'TEMP-${DateTime.now().millisecondsSinceEpoch}',
      timestamp: DateTime.now(),
      customerName: selectedCustomer?.name ?? 'Walk-in',
      customerEmail: selectedCustomer?.email,
      customerPhone: selectedCustomer?.phone,
      customerId: selectedCustomer?.id,
      lines: lines,
      subtotal: subtotal,
      discountTotal: discountValue,
      taxTotal: totalTax,
      grandTotal: grandTotal - redeemValue,
      redeemedValue: redeemValue,
      redeemedPoints: redeemedPoints,
      taxesByRate: taxesByRate,
      customerDiscountPercent: selectedCustomer?.discountPercent ?? 0,
      paymentMode: selectedPaymentMode.label,
    );
  }

  Future<Uint8List> _buildThermalPdf(InvoiceData data, {double widthMm = 48, double marginMm = 4, int density = 8}) async {
    final doc = pw.Document();
    final fmtDate = '${data.timestamp.year.toString().padLeft(4,'0')}-${data.timestamp.month.toString().padLeft(2,'0')}-${data.timestamp.day.toString().padLeft(2,'0')}';
    final fmtTime = '${data.timestamp.hour.toString().padLeft(2,'0')}:${data.timestamp.minute.toString().padLeft(2,'0')}:${data.timestamp.second.toString().padLeft(2,'0')}';
    final pageFormat = PdfPageFormat(widthMm * PdfPageFormat.mm, double.maxFinite, marginAll: marginMm * PdfPageFormat.mm);
    doc.addPage(pw.MultiPage(
      pageFormat: pageFormat,
      build: (ctx) {
        final widgets = <pw.Widget>[];
        widgets.add(pw.Center(child: pw.Text('RECEIPT', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold))));
        widgets.add(pw.SizedBox(height: 4));
        widgets.add(pw.Text('No: ${data.invoiceNumber}', style: const pw.TextStyle(fontSize: 8)));
        widgets.add(pw.Text('Date: $fmtDate $fmtTime', style: const pw.TextStyle(fontSize: 8)));
        widgets.add(pw.Text('Cust: ${data.customerName}', style: const pw.TextStyle(fontSize: 8)));
        if ((data.customerPhone ?? '').isNotEmpty) widgets.add(pw.Text('Ph: ${data.customerPhone}', style: const pw.TextStyle(fontSize: 8)));
        widgets.add(pw.Divider());
        for (final l in data.lines) {
          widgets.add(pw.Row(children:[
            pw.Expanded(child: pw.Text(l.name, style: const pw.TextStyle(fontSize: 8))),
            pw.Text('x${l.qty}', style: const pw.TextStyle(fontSize: 8)),
          ]));
          widgets.add(pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children:[
            pw.Text('₹${l.unitPrice.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 8)),
            if (l.discount>0) pw.Text('-${l.discount.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 8)),
            pw.Text('₹${l.lineTotal.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 8)),
          ]));
        }
        widgets.add(pw.Divider());
        pw.Widget kv(String k, String v,{bool b=false}) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children:[pw.Text(k,style: pw.TextStyle(fontSize:8,fontWeight:b?pw.FontWeight.bold:pw.FontWeight.normal)), pw.Text(v,style: pw.TextStyle(fontSize:8,fontWeight:b?pw.FontWeight.bold:pw.FontWeight.normal))]);
        widgets.add(kv('Subtotal','₹${data.subtotal.toStringAsFixed(2)}'));
        widgets.add(kv('Discount','-₹${data.discountTotal.toStringAsFixed(2)}'));
        if (data.redeemedValue>0) widgets.add(kv('Redeemed','-₹${data.redeemedValue.toStringAsFixed(2)}'));
        widgets.add(kv('GST','₹${data.taxTotal.toStringAsFixed(2)}'));
        widgets.add(pw.Divider());
        widgets.add(kv('TOTAL','₹${data.grandTotal.toStringAsFixed(2)}', b:true));
        widgets.add(kv('Paid', data.paymentMode));
        widgets.add(pw.SizedBox(height:4));
        widgets.add(pw.Text('Thank you!', style: const pw.TextStyle(fontSize: 8)));
        return widgets;
      }
    ));
    return doc.save();
  }
  double get _customerPercent => selectedCustomer?.discountPercent ?? 0;
  double get discountValue {
    switch (discountType) {
      case DiscountType.none:
        if (_customerPercent == 0) return 0;
        return (subtotal * (_customerPercent / 100)).clamp(0, subtotal);
      case DiscountType.percent:
        return (subtotal * (_customerPercent / 100)).clamp(0, subtotal);
      case DiscountType.flat:
        final val = (double.tryParse(discountCtrl.text) ?? 0).clamp(0, subtotal);
        return val.toDouble();
    }
  }

  Map<String, double> get lineDiscounts {
    if (subtotal == 0) return {};
    final map = <String, double>{};
    for (final it in cart.values) {
      final line = it.product.price * it.qty;
      map[it.product.sku] = (line / subtotal) * discountValue;
    }
    return map;
  }

  Map<String, double> get lineTaxes {
    final discounts = lineDiscounts;
    final map = <String, double>{};
    for (final it in cart.values) {
      final line = it.product.price * it.qty;
      final net = (line - (discounts[it.product.sku] ?? 0)).clamp(0, double.infinity);
      final tax = net * (it.product.taxPercent / 100);
      map[it.product.sku] = tax;
    }
    return map;
  }

  double get totalTax => lineTaxes.values.fold(0.0, (s, t) => s + t);
  double get grandTotal => (subtotal - discountValue + totalTax);
  double get redeemedPoints => double.tryParse(_redeemPointsCtrl.text) != null ? double.parse(_redeemPointsCtrl.text) : 0;
  double get redeemValue => (redeemedPoints.clamp(0, _availablePoints)) * _pointValue > grandTotal
      ? grandTotal
      : (redeemedPoints.clamp(0, _availablePoints)) * _pointValue;
  double get payableTotal => (grandTotal - redeemValue).clamp(0, double.infinity);


  void holdCart() {
    _holdController.holdCart();
  }

  void resumeHeld(HeldOrder order) {
    _holdController.resumeHeld(order);
  }

  Future<void> completeSale() async {
    if (cart.isEmpty) return _snack('Cart is empty');
    final rp = redeemedPoints;
    if (rp > _availablePoints) {
      _snack('You do not have enough points');
      setState(() {
        _redeemPointsCtrl.text = _availablePoints.toStringAsFixed(0);
      });
      return;
    }

    for (final item in cart.values) {
      item.product.stock -= item.qty;
    }

    final discounts = lineDiscounts;
    final taxes = lineTaxes;
    final taxesByRate = <int, double>{};
    for (final it in cart.values) {
      final tax = taxes[it.product.sku] ?? 0.0;
      taxesByRate.update(it.product.taxPercent, (v) => v + tax, ifAbsent: () => tax);
    }
    final lines = cart.values.map((it) {
      final price = it.product.price;
      final lineSubtotal = price * it.qty;
      final disc = discounts[it.product.sku] ?? 0.0;
      final tax = taxes[it.product.sku] ?? 0.0;
      final lineTotal = lineSubtotal - disc + tax;
      return InvoiceLine(
        sku: it.product.sku,
        name: it.product.name,
        qty: it.qty,
        unitPrice: price,
        taxPercent: it.product.taxPercent,
        lineSubtotal: lineSubtotal,
        discount: disc,
        tax: tax,
        lineTotal: lineTotal,
      );
    }).toList();
    final now = DateTime.now();
    final invoice = InvoiceData(
      invoiceNumber: invoiceNumber,
      timestamp: now,
      customerName: selectedCustomer?.name ?? 'Walk-in Customer',
      customerEmail: selectedCustomer?.email,
      customerPhone: selectedCustomer?.phone,
      customerId: selectedCustomer?.id,
      lines: lines,
      subtotal: subtotal,
      discountTotal: discountValue,
      taxTotal: totalTax,
      grandTotal: payableTotal,
      redeemedValue: redeemValue,
      redeemedPoints: redeemValue > 0 ? redeemValue / _pointValue : 0,
      taxesByRate: taxesByRate,
      customerDiscountPercent: _customerPercent,
      paymentMode: selectedPaymentMode.label,
    );
    lastInvoice = invoice;

    try {
      final data = invoice.toJson();
      await FirebaseFirestore.instance.collection('invoices').doc(invoice.invoiceNumber).set({
        ...data,
        'timestampMs': invoice.timestamp.millisecondsSinceEpoch,
        'status': 'Paid',
        'paymentMode': invoice.paymentMode,
      });
    } catch (e) {
      // ignore persistence failure
    }

    if (selectedCustomer != null && selectedCustomer!.id.isNotEmpty) {
      try {
        await _applyLoyaltyRewardsForCustomer(invoice);
      } catch (e) {
        if (mounted) {
          _snack('Loyalty update failed: $e');
        }
      }
    }

    if (!mounted) return;

    final summary = _buildInvoiceSummaryFromInvoice(invoice);

    setState(() {
      cart.clear();
      discountType = DiscountType.none;
      discountCtrl.text = '0';
    });

    // Direct print removed (migrated to new Node backend architecture).

    showDialog(
        context: context,
        barrierDismissible: true,
        builder: (dialogCtx) => AlertDialog(
              title: const Text('Invoice Preview (GST)'),
              content: SizedBox(width: 480, child: summary),
              actions: [
                // Email first
                TextButton.icon(
                  onPressed: () => _emailInvoice(dialogCtx),
                  icon: const Icon(Icons.email),
                  label: const Text('Email'),
                ),
                // Print beside Email
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
                  onPressed: _isPrinting ? null : () async {
                    setState(() => _isPrinting = true);
                    try {
                      final pdfBytes = await _buildThermalPdf(invoice, widthMm: 48, marginMm: 4, density: 8);
                      final req = http.MultipartRequest('POST', Uri.parse('$_backendBase/print-pdf'))
                        ..files.add(http.MultipartFile.fromBytes('file', pdfBytes, filename: 'invoice_${invoice.invoiceNumber}.pdf'));
                      final streamed = await req.send();
                      final resp = await http.Response.fromStream(streamed);
                      if (resp.statusCode == 200) {
                        _snack('Invoice printed');
                      } else {
                        _snack('Print failed: ${resp.statusCode}');
                      }
                    } catch (e) {
                      _snack('Print error: $e');
                    } finally {
                      if (mounted) setState(() => _isPrinting = false);
                    }
                  },
                  icon: _isPrinting ? const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2,color: Colors.white)) : const Icon(Icons.print),
                  label: const Text('Print'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx, rootNavigator: true).pop(),
                  child: const Text('Close'),
                ),
              ],
            ));
  }

  // ---------------- Temporary placeholder cart/product helpers ----------------
  // Replace placeholder with live Firestore stream from inventory collection.
  final InventoryRepository _inventoryRepo = InventoryRepository();
  Stream<List<Product>> get _productStream => _inventoryRepo.streamProducts().map((docs) {
        final list = docs.map((d) => Product(
              sku: d.sku,
              name: d.name,
              price: d.unitPrice,
              stock: d.totalStock,
              taxPercent: (d.taxPct ?? 0).toInt(),
              barcode: d.barcode.isEmpty ? null : d.barcode,
              ref: FirebaseFirestore.instance.collection('inventory').doc(d.sku),
            )).toList();
        return list;
      });
  void addToCart(Product p) { cart.update(p.sku, (ex) => ex.copyWith(qty: ex.qty + 1), ifAbsent: () => CartItem(product: p, qty: 1)); setState(() {}); }
  void changeQty(String sku, int delta) { final it = cart[sku]; if (it==null) return; final nq = it.qty + delta; if (nq<=0) { cart.remove(sku);} else { cart[sku]=it.copyWith(qty: nq);} setState(() {}); }
  void removeFromCart(String sku){ cart.remove(sku); setState(() {}); }
  double get subtotal => cart.values.fold(0.0, (s,it)=> s + it.product.price * it.qty);

  Future<void> _applyLoyaltyRewardsForCustomer(InvoiceData invoice) async {
    final customerId = selectedCustomer?.id;
    if (customerId == null || customerId.isEmpty) return; // walk-in
    final fs = FirebaseFirestore.instance;
    final settingsRef = fs.collection('settings').doc('loyalty_config');
    final customerRef = fs.collection('customers').doc(customerId);
    double earned = 0;
    double newPointsTotal = 0;
    await fs.runTransaction((tx) async {
      final settingsSnap = await tx.get(settingsRef);
      final settingsData = settingsSnap.data() ?? {};
      double pointsPerCurrency = 0.01; // 1 point per 100 currency
      final ppcRaw = settingsData['pointsPerCurrency'];
      if (ppcRaw is num) {
        pointsPerCurrency = ppcRaw.toDouble();
      } else if (ppcRaw is String) {
        pointsPerCurrency = double.tryParse(ppcRaw) ?? pointsPerCurrency;
      }
      List<Map<String, dynamic>> rawTiers = [];
      final tiersData = settingsData['tiers'];
      if (tiersData is List) {
        for (final t in tiersData) {
          if (t is Map) rawTiers.add(Map<String, dynamic>.from(t));
        }
      }
      rawTiers.sort((a, b) {
        final am = (a['minSpend'] is num) ? (a['minSpend'] as num).toDouble() : double.tryParse('${a['minSpend']}') ?? 0;
        final bm = (b['minSpend'] is num) ? (b['minSpend'] as num).toDouble() : double.tryParse('${b['minSpend']}') ?? 0;
        return am.compareTo(bm);
      });
      final custSnap = await tx.get(customerRef);
      final custData = custSnap.data() ?? {};
      final prevPointsRaw = custData['loyaltyPoints'];
      double prevPoints = 0;
      if (prevPointsRaw is num) prevPoints = prevPointsRaw.toDouble();
      final prevSpendRaw = custData['totalSpend'];
      double prevSpend = 0;
      if (prevSpendRaw is num) prevSpend = prevSpendRaw.toDouble();
      earned = (invoice.grandTotal * pointsPerCurrency);
      final redeemedPts = invoice.redeemedPoints;
      final afterRedeem = (prevPoints - redeemedPts).clamp(0, double.infinity);
      newPointsTotal = afterRedeem + earned;
      final newSpendTotal = prevSpend + invoice.grandTotal;
      String? newStatus;
      double? newDiscount;
      for (final tier in rawTiers) {
        final minSpend = (tier['minSpend'] is num) ? (tier['minSpend'] as num).toDouble() : double.tryParse('${tier['minSpend']}') ?? 0;
        if (newSpendTotal >= minSpend) {
          newStatus = (tier['name'] ?? '').toString().toLowerCase();
          final discRaw = tier['discount'];
          if (discRaw is num) newDiscount = discRaw.toDouble();
        }
      }
      final update = <String, dynamic>{
        'loyaltyPoints': newPointsTotal,
        'loyaltyUpdatedAt': FieldValue.serverTimestamp(),
        'lastInvoiceNumber': invoice.invoiceNumber,
        'lastInvoiceTotal': invoice.grandTotal,
        'loyaltyEarnedLast': earned,
        'loyaltyRedeemedLast': redeemedPts,
        'totalSpend': newSpendTotal,
      };
      if (newStatus != null && newStatus.isNotEmpty) {
        update['status'] = newStatus;
        if (newDiscount != null) {
          update['loyaltyDiscount'] = newDiscount;
        }
      }
      tx.update(customerRef, update);
    });
    if (!mounted) return;
    _snack('Earned ${earned.toStringAsFixed(1)} pts (Total: ${newPointsTotal.toStringAsFixed(1)})');
  }

  Future<void> _onCustomerSelected(Customer? c) async {
    final chosen = c ?? Customer(id: '', name: 'Walk-in Customer');
    setState(() => selectedCustomer = chosen);
    _customerDocSub?.cancel();
    if (chosen.id.isEmpty) {
      setState(() { _availablePoints = 0; _redeemPointsCtrl.text = '0'; });
      return;
    }
    try {
      final docRef = FirebaseFirestore.instance.collection('customers').doc(chosen.id);
      final snap = await docRef.get();
      if (snap.data() != null && mounted) {
        final refreshed = Customer.fromDoc(snap);
        setState(() {
          selectedCustomer = refreshed;
          _availablePoints = refreshed.rewardsPoints;
          final current = redeemedPoints;
          if (current > _availablePoints) {
            _redeemPointsCtrl.text = _availablePoints.toStringAsFixed(0);
          }
        });
      }
      _customerDocSub = docRef.snapshots().listen((liveSnap) {
        final data = liveSnap.data();
        if (data == null || !mounted) return;
        final refreshed = Customer.fromDoc(liveSnap);
        setState(() {
          selectedCustomer = refreshed;
          _availablePoints = refreshed.rewardsPoints;
          final current = redeemedPoints;
          if (current > _availablePoints) {
            _redeemPointsCtrl.text = _availablePoints.toStringAsFixed(0);
          }
        });
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _availablePoints = 0; });
    }
  }

  Future<void> _emailInvoice(BuildContext ctx) async {
    final inv = lastInvoice;
    if (inv == null) {
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('No invoice snapshot available')));
      return;
    }
    final email = inv.customerEmail;
    if (email == null || email.isEmpty) {
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Customer email not available')));
      return;
    }
    try {
      final messenger = ScaffoldMessenger.of(ctx);
      messenger.showSnackBar(const SnackBar(content: Text('Generating PDF...')));
      final pdfBytes = await pdf_gen.buildInvoicePdf(inv);
      messenger.showSnackBar(const SnackBar(content: Text('Sending invoice email (PDF)...')));
      final service = InvoiceEmailService();
      await service.sendInvoicePdf(
        customerEmail: email,
        invoiceNumber: inv.invoiceNumber,
        pdfBytes: pdfBytes,
        invoiceJson: inv.toJson(),
        subject: 'Invoice ${inv.invoiceNumber}',
        body: 'Dear ${inv.customerName},\n\nPlease find your invoice attached as PDF.\n\nRegards.',
        filename: '${inv.invoiceNumber}.pdf',
      );
      messenger.showSnackBar(const SnackBar(content: Text('Invoice PDF email sent')));
    } catch (e) {
      final messenger = ScaffoldMessenger.of(ctx);
      messenger.showSnackBar(SnackBar(content: Text('Failed to send PDF email: $e')));
    }
  }


  Widget _buildInvoiceSummaryFromInvoice(InvoiceData invoice) {
    final dateStr = '${invoice.timestamp.year.toString().padLeft(4, '0')}-${invoice.timestamp.month.toString().padLeft(2, '0')}-${invoice.timestamp.day.toString().padLeft(2, '0')}';
    final timeStr = '${invoice.timestamp.hour.toString().padLeft(2, '0')}:${invoice.timestamp.minute.toString().padLeft(2, '0')}:${invoice.timestamp.second.toString().padLeft(2, '0')}';
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Invoice #: ${invoice.invoiceNumber}'),
        Text('Date: $dateStr  Time: $timeStr'),
        Text('Customer: ${invoice.customerName}'),
        Text('Paid via: ${invoice.paymentMode}'),
        if ((invoice.customerEmail ?? '').isNotEmpty)
          Text('Email: ${invoice.customerEmail}'),
        if ((invoice.customerPhone ?? '').isNotEmpty)
          Text('Phone: ${invoice.customerPhone}'),
        const SizedBox(height: 8),
        const Divider(),
        ...invoice.lines.map((it) => ListTile(
              dense: true,
              title: Text('${it.name} x ${it.qty}'),
              subtitle: Text('Price: ₹${it.unitPrice.toStringAsFixed(2)}  |  Disc: ₹${it.discount.toStringAsFixed(2)}  |  Tax ${it.taxPercent}%: ₹${it.tax.toStringAsFixed(2)}'),
              trailing: Text('₹${it.lineTotal.toStringAsFixed(2)}'),
            )),
        const Divider(),
        _kv('Subtotal', invoice.subtotal),
        _kv('Discount', -invoice.discountTotal),
        _kv('Tax Total', invoice.taxTotal),
        const Divider(),
        _kv('Grand Total', invoice.grandTotal, bold: true),
        const SizedBox(height: 8),
      ]),
    );
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 1100;
    return KeyboardListener(
      focusNode: _scannerFocusNode,
      onKeyEvent: _handleKeyEvent,
      child: StreamBuilder<List<Product>>(
      stream: _productStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error loading products: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final allProducts = snapshot.data!;
        _cacheProducts = allProducts;
        final filtered = _filteredProducts(allProducts);
        return Padding(
          padding: const EdgeInsets.all(12.0),
          child: isWide ? _wideLayout(filtered, allProducts) : _narrowLayout(filtered, allProducts),
        );
      },
    ));
  }

  List<Product> _filteredProducts(List<Product> products) {
    final q = searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return products;
    return products.where((p) =>
      (p.sku.toLowerCase().contains(q)) ||
      (p.name.toLowerCase().contains(q)) ||
      ((p.barcode ?? '').toLowerCase().contains(q))
    ).toList();
  }

  Widget _wideLayout(List<Product> filtered, List<Product> allProducts) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PosSearchAndScanCard(
                barcodeController: barcodeCtrl,
                searchController: searchCtrl,
                scannerActive: _scannerActive,
                scannerConnected: _isScannerConnected,
                onScannerToggle: (v) => v ? _activateScanner() : _deactivateScanner(finalize: true),
                onBarcodeSubmitted: _scan,
                onSearchChanged: () => setState(() {}),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: PosProductList(
                  products: filtered,
                  favoriteSkus: favoriteSkus,
                  onAdd: (p) => addToCart(p),
                  onToggleFavorite: (p) => setState(() {
                    if (favoriteSkus.contains(p.sku)) {
                      favoriteSkus.remove(p.sku);
                    } else {
                      favoriteSkus.add(p.sku);
                    }
                  }),
                ),
              ),
              const SizedBox(height: 8),
              PosPopularItemsGrid(
                allProducts: allProducts,
                favoriteSkus: favoriteSkus,
                onAdd: (p) => addToCart(p),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: CartSection(
            cart: cart,
            heldOrders: heldOrders,
            onHold: holdCart,
            onResumeSelect: (ctx) async {
              final sel = await showDialog<HeldOrder>(
                context: ctx,
                builder: (_) => _HeldOrdersDialog(orders: heldOrders),
              );
              if (sel != null) {
                resumeHeld(sel);
              }
              return sel;
            },
            onClear: () {
              setState(() => cart.clear());
              _snack('Cart cleared');
            },
            onChangeQty: (sku, d) => changeQty(sku, d),
            onRemove: (sku) => removeFromCart(sku),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 360,
          child: CheckoutPanel(
            customersStream: _customerStream,
            initialCustomers: customers,
            selectedCustomer: selectedCustomer,
            walkIn: walkIn,
            onCustomerSelected: (c) => _onCustomerSelected(c),
            scrollController: _summaryScrollCtrl,
            subtotal: subtotal,
            discountValue: discountValue,
            redeemValue: redeemValue,
            grandTotal: grandTotal,
            payableTotal: payableTotal,
            getRedeemedPoints: () => redeemedPoints,
            getAvailablePoints: () => _availablePoints,
            redeemPointsController: _redeemPointsCtrl,
            onRedeemMax: () {
              setState(() {
                _redeemPointsCtrl.text = _availablePoints.toStringAsFixed(0);
              });
            },
            onRedeemChanged: () {
              final raw = _redeemPointsCtrl.text.trim();
              if (raw.isEmpty) return setState(() {});
              final val = double.tryParse(raw);
              if (val == null) {
                _redeemPointsCtrl.text = '0';
                _redeemPointsCtrl.selection = TextSelection.collapsed(offset: _redeemPointsCtrl.text.length);
              }
              setState(() {});
            },
            cart: cart,
            lineTaxes: lineTaxes,
            onCheckout: completeSale,
            selectedPaymentMode: selectedPaymentMode,
            onPaymentModeChanged: (m) => setState(() => selectedPaymentMode = m),
            onQuickPrint: _quickPrintFromPanel,
          ),
          
        ),
      ],
    );
  }

  Widget _narrowLayout(List<Product> filtered, List<Product> allProducts) {
    return ListView(
      children: [
        PosSearchAndScanCard(
          barcodeController: barcodeCtrl,
          searchController: searchCtrl,
          scannerActive: _scannerActive,
          scannerConnected: _isScannerConnected,
          onScannerToggle: (v) => v ? _activateScanner() : _deactivateScanner(finalize: true),
          onBarcodeSubmitted: _scan,
          onSearchChanged: () => setState(() {}),
          
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 240,
          child: PosProductList(
            products: filtered,
            favoriteSkus: favoriteSkus,
            onAdd: (p) => addToCart(p),
            onToggleFavorite: (p) => setState(() {
              if (favoriteSkus.contains(p.sku)) {
                favoriteSkus.remove(p.sku);
              } else {
                favoriteSkus.add(p.sku);
              }
            }),
          ),
        ),
        const SizedBox(height: 8),
        PosPopularItemsGrid(
          allProducts: allProducts,
          favoriteSkus: favoriteSkus,
          onAdd: (p) => addToCart(p),
        ),
        const SizedBox(height: 8),
        CartSection(
          cart: cart,
          heldOrders: heldOrders,
          onHold: holdCart,
          onResumeSelect: (ctx) async {
            final sel = await showDialog<HeldOrder>(
              context: ctx,
              builder: (_) => _HeldOrdersDialog(orders: heldOrders),
            );
            if (sel != null) {
              resumeHeld(sel);
            }
            return sel;
          },
          onClear: () {
            setState(() => cart.clear());
            _snack('Cart cleared');
          },
          onChangeQty: (sku, d) => changeQty(sku, d),
          onRemove: (sku) => removeFromCart(sku),
        ),
        const SizedBox(height: 8),
        CheckoutPanel(
          customersStream: _customerStream,
          initialCustomers: customers,
          selectedCustomer: selectedCustomer,
          walkIn: walkIn,
          onCustomerSelected: (c) => _onCustomerSelected(c),
          scrollController: _summaryScrollCtrl,
          subtotal: subtotal,
          discountValue: discountValue,
          redeemValue: redeemValue,
          grandTotal: grandTotal,
          payableTotal: payableTotal,
          getRedeemedPoints: () => redeemedPoints,
          getAvailablePoints: () => _availablePoints,
          redeemPointsController: _redeemPointsCtrl,
          onRedeemMax: () {
            setState(() {
              _redeemPointsCtrl.text = _availablePoints.toStringAsFixed(0);
            });
          },
          onRedeemChanged: () {
            final raw = _redeemPointsCtrl.text.trim();
            if (raw.isEmpty) return setState(() {});
            final val = double.tryParse(raw);
            if (val == null) {
              _redeemPointsCtrl.text = '0';
              _redeemPointsCtrl.selection = TextSelection.collapsed(offset: _redeemPointsCtrl.text.length);
            }
            setState(() {});
          },
          cart: cart,
          lineTaxes: lineTaxes,
          onCheckout: completeSale,
          selectedPaymentMode: selectedPaymentMode,
          onPaymentModeChanged: (m) => setState(() => selectedPaymentMode = m),
          onQuickPrint: _quickPrintFromPanel,
        ),
      ],
    );
  }

  // _searchAndBarcode moved to PosSearchAndScanCard

  Future<void> _scan() async {
    final code = barcodeCtrl.text.trim();
    if (code.isEmpty) return;
    await _processScan(code);
    barcodeCtrl.clear();
  }

  Future<void> _processScan(String code) async {
    if (code.isEmpty) return;
    Product? found;
    for (final p in _cacheProducts) {
      if (p.sku.toLowerCase() == code.toLowerCase() ||
          (p.barcode != null && p.barcode!.toLowerCase() == code.toLowerCase())) {
        found = p;
        break;
      }
    }
    if (found == null) {
      try {
        final bySku = await FirebaseFirestore.instance
            .collection('inventory')
            .where('sku', isEqualTo: code)
            .limit(1)
            .get();
        if (bySku.docs.isNotEmpty) {
          found = Product.fromDoc(bySku.docs.first);
        } else {
          final byBarcode = await FirebaseFirestore.instance
              .collection('inventory')
              .where('barcode', isEqualTo: code)
              .limit(1)
              .get();
          if (byBarcode.docs.isNotEmpty) {
            found = Product.fromDoc(byBarcode.docs.first);
          }
        }
      } catch (e) {
        _snack('Scan failed: $e');
      }
    }

    if (found == null) {
      if (!mounted) return;
      _snack('No product for code: $code');
    } else {
      if (!mounted) return;
      addToCart(found);
    }
  }

  void _handleKeyEvent(KeyEvent event) {
    if (!_scannerActive) return;
    if (event is! KeyDownEvent) return;
    final character = event.character;
    final now = DateTime.now();
    if (character != null && character.isNotEmpty && character.codeUnitAt(0) >= 32) {
      if (_lastKeyTime != null && now.difference(_lastKeyTime!) > _scanTimeout) {
        _scanBuffer.clear();
      }
      _lastKeyTime = now;
      _scanBuffer.write(character);
      _restartFinalizeTimer();
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      _finalizeBuffer();
    }
  }

  void _restartFinalizeTimer() {
    _finalizeTimer?.cancel();
    _finalizeTimer = Timer(_scanTimeout * 2, _finalizeBuffer);
  }

  void _finalizeBuffer() {
    _finalizeTimer?.cancel();
    final code = _scanBuffer.toString().trim();
    _scanBuffer.clear();
    if (code.length >= _minScanLength) {
      _lastSuccessfulScan = DateTime.now();
      _processScan(code);
    }
  }

  void _activateScanner() {
    if (_scannerActive) return;
    setState(() {
      _scannerActive = true;
      _lastSuccessfulScan = null;
    });
    _scanBuffer.clear();
    _lastKeyTime = null;
    _scannerFocusNode.requestFocus();
  }

  void _deactivateScanner({bool finalize = false}) {
    if (!_scannerActive) return;
    if (finalize) {
      _finalizeBuffer();
    } else {
      _scanBuffer.clear();
    }
    setState(() => _scannerActive = false);
  }

  bool get _isScannerConnected {
    if (!_scannerActive) return false;
    if (_lastSuccessfulScan == null) return false;
    return DateTime.now().difference(_lastSuccessfulScan!) < const Duration(seconds: 10);
  }

  // _productList moved to PosProductList

  // _popularGrid moved to PosPopularItemsGrid

  // _cartSection moved to CartSection widget

  // _paymentAndSummary & related helpers moved to CheckoutPanel

  Widget _kv(String label, double value, {bool bold = false}) {
    final style = TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text('₹${value.toStringAsFixed(2)}', style: style)],
      ),
    );
  }
}

// _SearchableCustomerDropdown removed after introducing CheckoutPanel simple dropdown

// _ScannerToggle moved to pos_search_scan_fav.dart

class _HeldOrdersDialog extends StatelessWidget {
  final List<HeldOrder> orders;
  const _HeldOrdersDialog({required this.orders});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Held Orders'),
      content: SizedBox(
        width: 420,
        height: 360,
        child: ListView.separated(
          itemCount: orders.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final o = orders[i];
            final count = o.items.fold<int>(0, (s, it) => s + it.qty);
            return ListTile(
              title: Text('${o.id} • ${o.timestamp.hour.toString().padLeft(2, '0')}:${o.timestamp.minute.toString().padLeft(2, '0')}'),
              subtitle: Text('Items: $count'),
              trailing: const Icon(Icons.play_circle_outline),
              onTap: () => Navigator.pop(context, o),
            );
          },
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}

// ---------------- Simple Print Settings Dialog (placeholder) ----------------
// Print Settings UI removed; printing now sends to backend default printer.
