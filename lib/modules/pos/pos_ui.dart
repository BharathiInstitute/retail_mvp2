// POS UI separated from models (moved out of pos.dart)
// This file contains all UI widgets and stateful logic for the POS screen.
// Models & enums live in pos.dart to allow reuse without pulling in UI code.

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'pos_invoices/invoice_models.dart';
import 'pos_invoices/invoice_pdf.dart' as pdf_gen; // For PDF generation (email attachment only; download removed)
import 'pos_invoices/invoice_email_service.dart';
import 'pos.dart'; // models & enums
import 'pos_search_scan_fav_fixed.dart';
import 'device_class_icon.dart';
import 'pos_checkout.dart';
import 'credit_service.dart';
import 'backend_launcher_stub.dart' if (dart.library.io) 'backend_launcher_desktop.dart';
import 'printing/windows_print_stub.dart' if (dart.library.io) 'windows_print.dart';
import 'printing/web_print_fallback_stub.dart' if (dart.library.js) 'printing/web_print_fallback.dart';
import '../../core/app_keys.dart';
import '../../core/paging/paged_list_controller.dart';
import '../../core/loading/page_loader_overlay.dart';
import '../../core/firebase/firestore_paging.dart';
import 'package:retail_mvp2/core/store_scoped_refs.dart';
import 'package:retail_mvp2/modules/stores/providers.dart';

// Debug/feature flags (set with --dart-define=KEY=value)
const bool kDisableInvoiceWrites = bool.fromEnvironment('DISABLE_INVOICE_WRITES', defaultValue: false);
const bool kDisableLoyaltyTx = bool.fromEnvironment('DISABLE_LOYALTY_TX', defaultValue: false);
const bool kPosVerbose = bool.fromEnvironment('POS_DEBUG_VERBOSE', defaultValue: false);
const bool kSafeWindowsSkipFirestore = bool.fromEnvironment('SAFE_WINDOWS_SKIP_FIRESTORE', defaultValue: true); // default true until crash source isolated
// Enable or disable direct hidden PowerShell printing on Windows (fallback / alternative to backend service)
const bool kEnableDirectPsPrint = bool.fromEnvironment('ENABLE_DIRECT_PS_PRINT', defaultValue: true);
// Web: if true, open the browser's print dialog; if false, send to backend silently
const bool kWebOpenBrowserPrint = bool.fromEnvironment('WEB_OPEN_BROWSER_PRINT', defaultValue: false);
// Web strict-silent: when true, never open browser print dialog (no fallback); fail with a message instead
const bool kWebStrictSilent = bool.fromEnvironment('WEB_STRICT_SILENT', defaultValue: false);

class PosPage extends ConsumerStatefulWidget {
  const PosPage({super.key});

  @override
  ConsumerState<PosPage> createState() => _PosPageState();
}

class _PosPageState extends ConsumerState<PosPage> {
  // Firestore-backed products cache (for quick lookup by barcode/SKU)
  final List<Product> _cacheProducts = [];

  // POS customers: Walk-in plus CRM customers from Firestore
  static final Customer walkIn = Customer(id: '', name: 'Walk-in Customer');
  List<Customer> customers = [walkIn];

  final TextEditingController barcodeCtrl = TextEditingController();
  final TextEditingController searchCtrl = TextEditingController();
  final TextEditingController customerSearchCtrl = TextEditingController();
  final ScrollController _productsScrollCtrl = ScrollController();
  Timer? _searchDebounce;

  late final PagedListController<Product> _productsPager;

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
  // Scrollbar for summary panel now managed inside CheckoutPanel; local controller removed.
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
  // On Windows desktop attempt to auto-start backend if not reachable.
  ensurePrinterBackendRunning();
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
    // Initialize paged products controller with Firestore-backed paging and optional name prefix search
    _productsPager = PagedListController<Product>(
      pageSize: 50,
      loadPage: (cursor) async {
        final qText = searchCtrl.text.trim();
        final storeId = ref.read(selectedStoreIdProvider);
        if (storeId == null) {
          return (<Product>[], null);
        }
        Query<Map<String, dynamic>> base = StoreRefs.of(storeId)
            .products()
            .orderBy('name');
        if (qText.length >= 2) {
          base = base.startAt([qText]).endAt(['$qText\uf8ff']);
        }
        final (items, next) = await fetchFirestorePage<Product>(
          base: base,
          after: cursor as DocumentSnapshot<Map<String, dynamic>>?,
          pageSize: _productsPager.pageSize,
          map: (doc) => Product.fromDoc(doc),
        );
        // Build cache for scanner incremental lookup
        _cacheProducts.addAll(items);
        return (items, next);
      },
    );
    _productsPager.resetAndLoad();

    _productsScrollCtrl.addListener(_maybeLoadMoreProducts);
  }

  @override
  void dispose() {
    _productsScrollCtrl.dispose();
    _searchDebounce?.cancel();
    _productsPager.dispose();
    _customerDocSub?.cancel();
    _scannerFocusNode.dispose();
    super.dispose();
  }

  String _resolveBackendBase() {
    const envUrl = String.fromEnvironment('PRINTER_BACKEND_URL', defaultValue: '');
    if (envUrl.isNotEmpty) return envUrl;
    if (kIsWeb) {
      // If the app is served over HTTPS and no explicit backend URL is provided,
      // do NOT default to https://host:5005 (likely not available). Leave empty to force fallback.
      if (Uri.base.scheme == 'https') {
        return '';
      }
      final host = Uri.base.host.isEmpty ? 'localhost' : Uri.base.host;
      const port = 5005;
      return 'http://$host:$port';
    }
    return 'http://localhost:5005';
  }

  bool get _canUseBackend => _backendBase.isNotEmpty;

  // Live stream of CRM customers from Firestore (store-scoped)
  Stream<List<Customer>> _customerStream(String? storeId) {
    if (storeId == null) return Stream.value(const <Customer>[]);
    return StoreRefs.of(storeId)
        .customers()
        .snapshots()
        .map((s) {
          final list = s.docs.map((d) => Customer.fromDoc(d)).toList();
          list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          return list;
        });
  }

  Future<void> _loadCustomersOnce() async {
    try {
      final storeId = ref.read(selectedStoreIdProvider);
      final first = await _customerStream(storeId).first;
      if (!mounted) return;
      setState(() {
        customers = [walkIn, ...first.where((c) => c.id != walkIn.id)];
        if (!customers.any((c) => c.id == (selectedCustomer?.id ?? ''))) {
          selectedCustomer = customers.first;
        }
      });
    } catch (e) {
      if (kPosVerbose) debugPrint('[POS] customers preload failed: $e');
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

  // One-click print from the right panel without creating an invoice record.
  Future<void> _quickPrintFromPanel() async {
    if (cart.isEmpty) return _snack('Cart empty');
    if (_isPrinting) return;
    setState(() => _isPrinting = true);
    try {
      final invoice = _buildTempInvoiceForPrint();
      bool directOk = false;
      if (kEnableDirectPsPrint) {
        try {
          directOk = await directWindowsPrintInvoice(invoice);
        } catch (_) {
          directOk = false;
        }
      }
      if (directOk) {
        _snack('Invoice sent to printer (direct)');
        return;
      }

      if (kIsWeb) {
        // Web: try backend if available, then always fall back to browser print.
        bool backendOk = false;
        if (_canUseBackend) {
          try {
            try {
              await http.get(Uri.parse('$_backendBase/health')).timeout(const Duration(seconds: 2));
            } catch (_) {}
            final resp = await http.post(Uri.parse('$_backendBase/print-invoice'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({'invoice': invoice.toJson()}));
            if (resp.statusCode == 200) {
              backendOk = true;
              try {
                final data = jsonDecode(resp.body) as Map<String, dynamic>;
                final msg = (data['message'] as String?) ?? 'Invoice print sent';
                final usedPrinter = data['usedPrinter'];
                _snack(usedPrinter != null ? '$msg (${usedPrinter.toString()})' : msg);
              } catch (_) {
                _snack('Invoice print sent');
              }
              return;
            } else if (kPosVerbose) {
              debugPrint('[POS] backend print failed: ${resp.statusCode} ${resp.body}');
            }
          } catch (e) {
            if (kPosVerbose) debugPrint('[POS][web] quick print backend error: $e');
          }
        }
        // Not printed via backend => try browser dialog unless strict silent is enabled
        if (!backendOk) {
          if (kWebStrictSilent) {
            _snack('Silent print unavailable (backend offline)');
          } else {
            // Pre-open window synchronously (for popup blockers), then populate and print
            final handle = webPrintPreopen();
            final handled = await webPrintPopulateAndPrint(handle, invoice);
            if (handled) {
              _snack('Browser print opened');
              return;
            }
            _snack('Print error (popup blocked?)');
          }
        }
      } else {
        // Non-web: use backend service
        try {
          try { await http.get(Uri.parse('$_backendBase/health')).timeout(const Duration(seconds: 2)); } catch (_) {}
          final resp = await http.post(Uri.parse('$_backendBase/print-invoice'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'invoice': invoice.toJson()}));
          if (resp.statusCode == 200) {
            _snack('Invoice print sent');
          } else {
            _snack('Print failed (${resp.statusCode})');
          }
        } catch (e) {
          if (kPosVerbose) debugPrint('[POS] quick print error: $e');
          _snack('Print error');
        }
      }
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
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

  Future<void> completeSale({double creditPaidInput = 0}) async {
    if (cart.isEmpty) return _snack('Cart is empty');
    if (kPosVerbose) debugPrint('[POS] completeSale begin cartItems=${cart.length}');
    final rp = redeemedPoints;
    if (rp > _availablePoints) {
      _snack('You do not have enough points');
      setState(() {
        _redeemPointsCtrl.text = _availablePoints.toStringAsFixed(0);
      });
      return;
    }

    // Update local stock snapshot (UI only)
    for (final item in cart.values) {
      final newStock = item.product.stock - item.qty;
      if (newStock >= 0) {
        item.product.stock = newStock;
      }
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

    final isWindows = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    final skipWritesForPlatform = isWindows && kSafeWindowsSkipFirestore;
    if (skipWritesForPlatform && kPosVerbose) debugPrint('[POS] Skipping Firestore invoice write on Windows (safe mode)');

    // Determine credit mixing BEFORE invoice persistence (central helper ensures consistent math)
    double creditAddPortion = 0;
    double creditRepayPortion = 0;
    double paidNow = 0;
    double expectedNewCredit = selectedCustomer?.creditBalance ?? 0;
    if (selectedPaymentMode == PaymentMode.credit) {
      paidNow = creditPaidInput.clamp(0, double.infinity);
      final existingCredit = selectedCustomer?.creditBalance ?? 0;
      final mix = CustomerCreditService.computeCreditMix(
        saleDue: payableTotal,
        existingCredit: existingCredit,
        paidNow: paidNow,
      );
      creditAddPortion = mix['add'] ?? 0;
      creditRepayPortion = mix['repay'] ?? 0;
      expectedNewCredit = mix['newCredit'] ?? existingCredit;
      if (kPosVerbose) {
        debugPrint('[POS][creditMix] compute due=$payableTotal existing=$existingCredit paid=$paidNow add=$creditAddPortion repay=$creditRepayPortion -> expectedNew=$expectedNewCredit');
      }
    }

    if (!kDisableInvoiceWrites && !skipWritesForPlatform) {
      try {
        final data = invoice.toJson();
        if (kPosVerbose) debugPrint('[POS] writing invoice ${invoice.invoiceNumber}');
        final storeId = ref.read(selectedStoreIdProvider);
        if (storeId == null) {
          throw Exception('No store selected');
        }
        await StoreRefs.of(storeId).invoices().doc(invoice.invoiceNumber).set({
          ...data,
          'timestampMs': invoice.timestamp.millisecondsSinceEpoch,
          'status': (selectedPaymentMode == PaymentMode.credit && creditAddPortion > 0) ? 'on_credit' : 'Paid',
          if (selectedPaymentMode == PaymentMode.credit)
            'credit': {
              'paidNow': paidNow,
              'added': creditAddPortion,
              'repaid': creditRepayPortion,
            },
        });
        if (kPosVerbose) debugPrint('[POS] invoice write done');
      } catch (e, st) {
        if (kPosVerbose) debugPrint('[POS] invoice write error: $e\n$st');
        // Non-fatal for POS flow
      }
    } else if (kPosVerbose) {
      debugPrint('[POS] invoice writes disabled');
      if (selectedPaymentMode == PaymentMode.credit) {
        _snack('Invoice write skipped (debug mode) – credit still adjusting');
      }
    }

    if (selectedPaymentMode == PaymentMode.credit) {
      if (selectedCustomer == null || selectedCustomer!.id.isEmpty) {
        _snack('Select a customer for credit checkout');
      } else {
        try {
          await CustomerCreditService.ensureCreditField(selectedCustomer!.id, storeId: ref.read(selectedStoreIdProvider));
          if (kPosVerbose) {
            debugPrint('[POS][creditMix] attempting adjust add=$creditAddPortion repay=$creditRepayPortion');
          }
          final creditResult = await CustomerCreditService.adjustForCheckout(
            customerId: selectedCustomer!.id,
            creditAdd: creditAddPortion,
            creditRepay: creditRepayPortion,
            invoiceNumber: invoice.invoiceNumber,
            storeId: ref.read(selectedStoreIdProvider),
          );
          setState(() {
            selectedCustomer = Customer(
              id: selectedCustomer!.id,
              name: selectedCustomer!.name,
              email: selectedCustomer!.email,
              phone: selectedCustomer!.phone,
              status: selectedCustomer!.status,
              totalSpend: selectedCustomer!.totalSpend,
              discountPercent: selectedCustomer!.discountPercent,
              creditBalance: creditResult.newBalance,
            );
          });
          if (kPosVerbose) {
            debugPrint('[POS][creditMix] txn result prev=${creditResult.previousBalance} new=${creditResult.newBalance} amountChanged=${creditResult.amountChanged} ledger=${creditResult.ledgerRecorded} type=${creditResult.type} expectedNew=$expectedNewCredit');
            if ((creditResult.newBalance - expectedNewCredit).abs() > 0.01) {
              debugPrint('[POS][creditMix][warn] mismatch expected=$expectedNewCredit actual=${creditResult.newBalance}');
            }
          }
          if (creditAddPortion == 0 && creditRepayPortion == 0) {
            _snack('Credit unchanged (fully paid) → Balance ₹${creditResult.newBalance.toStringAsFixed(2)}');
          } else {
            _snack('Credit updated (Add ₹${creditAddPortion.toStringAsFixed(2)}, Repay ₹${creditRepayPortion.toStringAsFixed(2)}) → Balance ₹${creditResult.newBalance.toStringAsFixed(2)}');
          }
        } on FirebaseException catch (e) {
          _snack('Credit failed (${e.code})');
          if (kPosVerbose) debugPrint('[POS][creditMix][error] FirebaseException ${e.code} ${e.message}');
        } catch (e) {
          _snack('Credit adjust failed: $e');
          if (kPosVerbose) debugPrint('[POS][creditMix][error] $e');
        }
      }
    }

  if (!kDisableLoyaltyTx && !skipWritesForPlatform && selectedCustomer != null && selectedCustomer!.id.isNotEmpty) {
    try {
      if (kPosVerbose) debugPrint('[POS] loyalty tx start for cust=${selectedCustomer!.id}');
      await _applyLoyaltyRewardsForCustomer(invoice);
      if (kPosVerbose) debugPrint('[POS] loyalty tx ok');
    } catch (e, st) {
      // This catch should normally never trigger because the method internally handles errors.
      if (kPosVerbose) debugPrint('[POS][loyalty][outer-catch] $e\n$st');
      if (mounted) {
        _snack('Loyalty failed: $e');
      }
    }
  } else if (kPosVerbose) {
    debugPrint('[POS] loyalty transaction skipped');
  }

    if (!mounted) return;

  final summary = _buildInvoiceSummaryFromInvoice(context, invoice);

    setState(() {
      cart.clear();
      discountType = DiscountType.none;
      discountCtrl.text = '0';
    });

    // Direct print removed (migrated to new Node backend architecture).

  if (kPosVerbose) debugPrint('[POS] showing invoice dialog');
  _showInvoiceDialog(summary, invoice);
  }

  void _showInvoiceDialog(Widget summary, InvoiceData invoice) {
    final dlgRoot = rootNavigatorKey.currentContext;
    if (dlgRoot == null) return;
    showDialog(
      context: dlgRoot,
      barrierDismissible: true,
      builder: (dialogCtx) {
        final cs = Theme.of(dialogCtx).colorScheme;
        final texts = Theme.of(dialogCtx).textTheme;
        return AlertDialog(
        title: Text(
          'Invoice Preview (GST)',
          style: Theme.of(dialogCtx).textTheme.titleLarge?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w700),
        ),
        content: DefaultTextStyle(
          style: texts.bodyMedium?.copyWith(color: cs.onSurface) ?? const TextStyle(),
          child: SizedBox(width: 480, child: summary),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => _emailInvoice(),
            icon: const Icon(Icons.email),
            label: const Text('Email'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
            onPressed: _isPrinting ? null : () async {
              setState(() => _isPrinting = true);
              try {
                bool directOk = false;
                if (kEnableDirectPsPrint) {
                  try { directOk = await directWindowsPrintInvoice(invoice); } catch (_) { directOk = false; }
                }
                if (directOk) {
                  _snack('Invoice printed (direct)');
                  if (kPosVerbose) debugPrint('[POS] direct print success');
                } else {
                  if (kIsWeb) {
                    bool backendOk = false;
                    if (_canUseBackend) {
                      if (kPosVerbose) debugPrint('[POS] print-invoice POST');
                      try {
                        final resp = await http.post(Uri.parse('$_backendBase/print-invoice'),
                            headers: {'Content-Type': 'application/json'},
                            body: jsonEncode({'invoice': invoice.toJson()}));
                        if (resp.statusCode == 200) {
                          backendOk = true;
                          _snack('Invoice printed');
                          if (kPosVerbose) debugPrint('[POS] backend print success');
                          return;
                        } else if (kPosVerbose) {
                          debugPrint('[POS] backend print failed: ${resp.statusCode} ${resp.body}');
                        }
                      } catch (e) {
                        if (kPosVerbose) debugPrint('[POS][web] backend print error: $e');
                      }
                    }
                    if (!backendOk) {
                      if (kWebStrictSilent) {
                        _snack('Silent print unavailable (backend offline)');
                      } else {
                        final handle = webPrintPreopen();
                        final handled = await webPrintPopulateAndPrint(handle, invoice);
                        if (handled) {
                          _snack('Browser print opened');
                          return;
                        }
                        _snack('Print error (popup blocked?)');
                      }
                    }
                  } else {
                    if (kPosVerbose) debugPrint('[POS] print-invoice POST');
                    final resp = await http.post(Uri.parse('$_backendBase/print-invoice'),
                        headers: {'Content-Type': 'application/json'},
                        body: jsonEncode({'invoice': invoice.toJson()}));
                    if (resp.statusCode == 200) {
                      _snack('Invoice printed');
                      if (kPosVerbose) debugPrint('[POS] backend print success');
                    } else {
                      _snack('Print failed: ${resp.statusCode} ${resp.body}');
                      if (kPosVerbose) debugPrint('[POS] backend print failed: ${resp.statusCode} ${resp.body}');
                    }
                  }
                }
              } catch (e) {
                _snack('Print error');
                if (kPosVerbose) debugPrint('[POS] print error: $e');
              } finally {
                if (mounted) setState(() => _isPrinting = false);
              }
            },
            icon: _isPrinting
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  )
                : const Icon(Icons.print),
            label: const Text('Print'),
          ),
          TextButton(
            onPressed: () {
              if (Navigator.of(dialogCtx).canPop()) {
                Navigator.of(dialogCtx).pop();
              }
            },
            child: const Text('Close'),
          ),
        ],
      );
      },
    );
  }

  // ---------------- Cart/product helpers ----------------
  void addToCart(Product p) { cart.update(p.sku, (ex) => ex.copyWith(qty: ex.qty + 1), ifAbsent: () => CartItem(product: p, qty: 1)); setState(() {}); }
  void changeQty(String sku, int delta) { final it = cart[sku]; if (it==null) return; final nq = it.qty + delta; if (nq<=0) { cart.remove(sku);} else { cart[sku]=it.copyWith(qty: nq);} setState(() {}); }
  void removeFromCart(String sku){ cart.remove(sku); setState(() {}); }
  double get subtotal => cart.values.fold(0.0, (s,it)=> s + it.product.price * it.qty);

  Future<void> _applyLoyaltyRewardsForCustomer(InvoiceData invoice) async {
    try {
      final customerId = selectedCustomer?.id;
      if (customerId == null || customerId.isEmpty) {
        if (kPosVerbose) debugPrint('[LOYALTY] abort: no customer');
        return; // walk-in
      }
      final fs = FirebaseFirestore.instance;
      final storeId = ref.read(selectedStoreIdProvider);
      if (storeId == null) {
        if (kPosVerbose) debugPrint('[LOYALTY] abort: no store selected');
        return;
      }
      final settingsRef = StoreRefs.of(storeId, fs: fs).loyaltySettings().doc('config');
      final customerRef = StoreRefs.of(storeId, fs: fs).customers().doc(customerId);
      double earned = 0;
      double newPointsTotal = 0;
      if (kPosVerbose) debugPrint('[LOYALTY] start invoice=${invoice.invoiceNumber} grand=${invoice.grandTotal} cust=$customerId');
      if (kPosVerbose) {
        try {
          final u = FirebaseAuth.instance.currentUser;
          debugPrint('[LOYALTY][auth] user=${u==null ? 'null' : '${u.uid} email=${u.email}'}');
        } catch (e) {
          debugPrint('[LOYALTY][auth] error $e');
        }
      }
      bool txSucceeded = false;
      dynamic lastError;
      try {
        await fs.runTransaction((tx) async {
          final settingsSnap = await tx.get(settingsRef);
          final settingsData = settingsSnap.data() ?? {};
          double pointsPerCurrency = 0.01;
          final ppcRaw = settingsData['pointsPerCurrency'];
          if (ppcRaw is num) {
            pointsPerCurrency = ppcRaw.toDouble();
          } else if (ppcRaw is String) {
            pointsPerCurrency = double.tryParse(ppcRaw) ?? pointsPerCurrency;
          }
          final rawTiers = <Map<String, dynamic>>[];
          final tiersData = settingsData['tiers'];
          if (tiersData is List) {
            for (final t in tiersData) { if (t is Map) rawTiers.add(Map<String,dynamic>.from(t)); }
          }
            rawTiers.sort((a,b){
              double am = (a['minSpend'] is num)? (a['minSpend'] as num).toDouble() : double.tryParse('${a['minSpend']}') ?? 0;
              double bm = (b['minSpend'] is num)? (b['minSpend'] as num).toDouble() : double.tryParse('${b['minSpend']}') ?? 0;
              return am.compareTo(bm);
            });
          final custSnap = await tx.get(customerRef);
          final cdata = custSnap.data() ?? {};
          double prevPoints = (cdata['loyaltyPoints'] is num) ? (cdata['loyaltyPoints'] as num).toDouble() : 0;
          double prevSpend = (cdata['totalSpend'] is num) ? (cdata['totalSpend'] as num).toDouble() : 0;
          final earnBase = invoice.grandTotal;
          earned = double.parse((earnBase * pointsPerCurrency).toStringAsFixed(2));
          if (earned < 0) earned = 0;
          final redeemedPts = invoice.redeemedPoints;
          final afterRedeem = (prevPoints - redeemedPts).clamp(0, double.infinity);
          newPointsTotal = afterRedeem + earned;
          final newSpendTotal = prevSpend + invoice.grandTotal;
          String? newStatus; double? newDiscount;
          for (final tier in rawTiers) {
            final minSpend = (tier['minSpend'] is num)? (tier['minSpend'] as num).toDouble() : double.tryParse('${tier['minSpend']}') ?? 0;
            if (newSpendTotal >= minSpend) {
              newStatus = (tier['name'] ?? '').toString().toLowerCase();
              final discRaw = tier['discount'];
              if (discRaw is num) newDiscount = discRaw.toDouble();
            }
          }
          if (kPosVerbose) {
            debugPrint('[LOYALTY][tx] prevPoints=$prevPoints earned=$earned redeemed=$redeemedPts newPoints=$newPointsTotal');
          }
          final update = <String,dynamic>{
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
        txSucceeded = true;
      } catch (e, st) {
        lastError = e;
        if (kPosVerbose) {
          debugPrint('[LOYALTY][tx-fail] $e\n$st');
        }
      }
      if (!txSucceeded) {
        // Attempt fallback non-transactional optimistic update if the error wasn't permission-denied
        if (lastError is FirebaseException && lastError.code == 'permission-denied') {
          if (mounted) {
            _snack('Loyalty skipped (no permission)');
          }
          return;
        }
        try {
          if (kPosVerbose) {
            debugPrint('[LOYALTY][fallback] attempting direct update');
          }
          final custSnap = await customerRef.get();
          final cdata = custSnap.data() ?? {};
          double prevPoints = (cdata['loyaltyPoints'] is num) ? (cdata['loyaltyPoints'] as num).toDouble() : 0;
          double prevSpend = (cdata['totalSpend'] is num) ? (cdata['totalSpend'] as num).toDouble() : 0;
          double pointsPerCurrency = 0.01;
          final settingsSnap = await settingsRef.get();
          final settingsData = settingsSnap.data() ?? {};
          final ppcRaw = settingsData['pointsPerCurrency'];
          if (ppcRaw is num) {
            pointsPerCurrency = ppcRaw.toDouble();
          } else if (ppcRaw is String) {
            pointsPerCurrency = double.tryParse(ppcRaw) ?? pointsPerCurrency;
          }
          earned = double.parse((invoice.grandTotal * pointsPerCurrency).toStringAsFixed(2));
          if (earned < 0) earned = 0;
          final redeemedPts = invoice.redeemedPoints;
          final afterRedeem = (prevPoints - redeemedPts).clamp(0, double.infinity);
          newPointsTotal = afterRedeem + earned;
          final newSpendTotal = prevSpend + invoice.grandTotal;
          await customerRef.update({
            'loyaltyPoints': newPointsTotal,
            'loyaltyUpdatedAt': FieldValue.serverTimestamp(),
            'lastInvoiceNumber': invoice.invoiceNumber,
            'lastInvoiceTotal': invoice.grandTotal,
            'loyaltyEarnedLast': earned,
            'loyaltyRedeemedLast': invoice.redeemedPoints,
            'totalSpend': newSpendTotal,
          });
          if (kPosVerbose) debugPrint('[LOYALTY][fallback] success new=$newPointsTotal earned=$earned');
        } catch (fe, st2) {
          if (kPosVerbose) debugPrint('[LOYALTY][fallback-fail] $fe\n$st2');
          rethrow; // let outer catch handle final failure
        }
      }
      if (!mounted) return;
      if (kPosVerbose) debugPrint('[LOYALTY] success new=${newPointsTotal.toStringAsFixed(2)} earned=$earned');
      _snack('Earned ${earned.toStringAsFixed(1)} pts (Total: ${newPointsTotal.toStringAsFixed(1)})');
    } on FirebaseException catch (e) {
      if (kPosVerbose) debugPrint('[LOYALTY][fail-inner] code=${e.code} msg=${e.message}');
      if (mounted) {
        if (e.code == 'permission-denied') {
          _snack('Loyalty skipped (no permission)');
        } else {
          _snack('Loyalty error (${e.code})');
        }
      }
    } catch (e, st) {
      if (kPosVerbose) debugPrint('[LOYALTY][uncaught] $e\n$st');
      if (mounted) _snack('Loyalty update failed');
      // swallow to avoid crashing outer sale flow
    }
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
      // Ensure creditBalance field exists (idempotent)
  await CustomerCreditService.ensureCreditField(chosen.id, storeId: ref.read(selectedStoreIdProvider));
    final storeId = ref.read(selectedStoreIdProvider);
    if (storeId == null) {
      // Store must be selected before fetching a store-scoped customer
      if (mounted) {
        _snack('Select a store first');
      }
      return;
    }
    final docRef = StoreRefs.of(storeId).customers().doc(chosen.id);
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

  Future<void> _emailInvoice() async {
    final inv = lastInvoice;
    if (inv == null) {
      scaffoldMessengerKey.currentState?.showSnackBar(const SnackBar(content: Text('No invoice snapshot available')));
      return;
    }
    final email = inv.customerEmail;
    if (email == null || email.isEmpty) {
      scaffoldMessengerKey.currentState?.showSnackBar(const SnackBar(content: Text('Customer email not available')));
      return;
    }
    final messenger = scaffoldMessengerKey.currentState;
    try {
      messenger?.showSnackBar(const SnackBar(content: Text('Generating PDF...')));
      final pdfBytes = await pdf_gen.buildInvoicePdf(inv);
      messenger?.showSnackBar(const SnackBar(content: Text('Sending invoice email (PDF)...')));
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
      messenger?.showSnackBar(const SnackBar(content: Text('Invoice PDF email sent')));
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('Failed to send PDF email: $e')));
    }
  }


  Widget _buildInvoiceSummaryFromInvoice(BuildContext context, InvoiceData invoice) {
    final cs = Theme.of(context).colorScheme;
    final dateStr = '${invoice.timestamp.year.toString().padLeft(4, '0')}-${invoice.timestamp.month.toString().padLeft(2, '0')}-${invoice.timestamp.day.toString().padLeft(2, '0')}';
    final timeStr = '${invoice.timestamp.hour.toString().padLeft(2, '0')}:${invoice.timestamp.minute.toString().padLeft(2, '0')}:${invoice.timestamp.second.toString().padLeft(2, '0')}';
    return SingleChildScrollView(
      child: DefaultTextStyle.merge(
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurface) ?? TextStyle(color: cs.onSurface),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Invoice #: ${invoice.invoiceNumber}', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurface)),
          Text('Date: $dateStr  Time: $timeStr', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurface)),
          Text('Customer: ${invoice.customerName}', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurface)),
          Text('Paid via: ${invoice.paymentMode}', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurface)),
          if ((invoice.customerEmail ?? '').isNotEmpty)
            Text('Email: ${invoice.customerEmail}', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurface)),
          if ((invoice.customerPhone ?? '').isNotEmpty)
            Text('Phone: ${invoice.customerPhone}', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurface)),
          const SizedBox(height: 8),
          const Divider(),
          ...invoice.lines.map((it) => ListTile(
                dense: true,
                title: Text('${it.name} x ${it.qty}', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w600)),
                subtitle: Text('Price: ₹${it.unitPrice.toStringAsFixed(2)}  |  Disc: ₹${it.discount.toStringAsFixed(2)}  |  Tax ${it.taxPercent}%: ₹${it.tax.toStringAsFixed(2)}', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                trailing: Text('₹${it.lineTotal.toStringAsFixed(2)}', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w700)),
              )),
          const Divider(),
          _kv(context, 'Subtotal', invoice.subtotal),
          _kv(context, 'Discount', -invoice.discountTotal),
          _kv(context, 'Tax Total', invoice.taxTotal),
          const Divider(),
          _kv(context, 'Grand Total', invoice.grandTotal, bold: true),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  void _snack(String msg) {
    // Use global messenger to avoid using a widget BuildContext across async gaps
    final messenger = scaffoldMessengerKey.currentState;
    messenger?.showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 1280;
    final isTablet = screenWidth >= 900 && screenWidth < 1280;
    final pagePadding = isDesktop
        ? const EdgeInsets.all(12.0)
        : (isTablet ? const EdgeInsets.all(8.0) : const EdgeInsets.all(12.0));

    final productsState = _productsPager.state;
    final products = productsState.items;

    final body = isDesktop
        ? _wideLayout(products)
        : isTablet
            ? _tabletLayout(products)
            : _narrowLayout(products);

    return KeyboardListener(
      focusNode: _scannerFocusNode,
      onKeyEvent: _handleKeyEvent,
      child: Stack(children: [
        Padding(
          padding: pagePadding,
          child: PageLoaderOverlay(
            loading: products.isEmpty && productsState.loading,
            error: products.isEmpty ? productsState.error : null,
            onRetry: () => _productsPager.resetAndLoad(),
            child: body,
          ),
        ),
        const Positioned(top: 4, right: 4, child: DeviceClassIcon()),
      ]),
    );
  }

  void _maybeLoadMoreProducts() {
    if (!_productsScrollCtrl.hasClients) return;
    final extentAfter = _productsScrollCtrl.position.extentAfter;
    if (extentAfter < 600) {
      _productsPager.loadMore();
    }
  }

  void _onSearchChangedDebounced() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _cacheProducts.clear();
      _productsPager.resetAndLoad();
      if (mounted) setState(() {});
    });
  }

  

  Widget _wideLayout(List<Product> products) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 360,
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
                onSearchChanged: _onSearchChangedDebounced,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Scrollbar(
                  controller: _productsScrollCtrl,
                  child: PosProductList(
                    scrollController: _productsScrollCtrl,
                    products: products,
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
              ),
              const SizedBox(height: 8),
              PosPopularItemsGrid(
                allProducts: products,
                favoriteSkus: favoriteSkus,
                onAdd: (p) => addToCart(p),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
            ],
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 300,
          child: CheckoutPanel(
            customersStream: _customerStream(ref.watch(selectedStoreIdProvider)),
            initialCustomers: customers,
            selectedCustomer: selectedCustomer,
            walkIn: walkIn,
            onCustomerSelected: (c) => _onCustomerSelected(c),
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
            onCheckout: () => completeSale(),
            onCheckoutCreditMix: (amt) => completeSale(creditPaidInput: amt),
            selectedPaymentMode: selectedPaymentMode,
            onPaymentModeChanged: (m) => setState(() => selectedPaymentMode = m),
            onQuickPrint: _quickPrintFromPanel,
            onPayCredit: (amt) => _payCustomerCredit(amt),
          ),
          
        ),
      ],
    );
  }

  // Tablet layout: similar to wide but with reduced widths and spacing
  Widget _tabletLayout(List<Product> products) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 340,
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
                onSearchChanged: _onSearchChangedDebounced,
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Scrollbar(
                  controller: _productsScrollCtrl,
                  child: PosProductList(
                    scrollController: _productsScrollCtrl,
                    products: products,
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
              ),
              const SizedBox(height: 6),
              PosPopularItemsGrid(
                allProducts: products,
                favoriteSkus: favoriteSkus,
                onAdd: (p) => addToCart(p),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _CustomersDropdownCard(
                customersStream: _customerStream(ref.watch(selectedStoreIdProvider)),
                initialCustomers: customers,
                selectedCustomer: selectedCustomer,
                walkIn: walkIn,
                availablePoints: _availablePoints,
                onSelected: (c) => _onCustomerSelected(c),
              ),
              const SizedBox(height: 8),
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
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 300,
          child: CheckoutPanel(
            customersStream: _customerStream(ref.watch(selectedStoreIdProvider)),
            initialCustomers: customers,
            selectedCustomer: selectedCustomer,
            walkIn: walkIn,
            onCustomerSelected: (c) => _onCustomerSelected(c),
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
            onCheckout: () => completeSale(),
            onCheckoutCreditMix: (amt) => completeSale(creditPaidInput: amt),
            selectedPaymentMode: selectedPaymentMode,
            onPaymentModeChanged: (m) => setState(() => selectedPaymentMode = m),
            onQuickPrint: _quickPrintFromPanel,
            onPayCredit: (amt) => _payCustomerCredit(amt),
          ),
        ),
      ],
    );
  }

  Widget _narrowLayout(List<Product> products) {
    return ListView(
      children: [
        PosSearchAndScanCard(
          barcodeController: barcodeCtrl,
          searchController: searchCtrl,
          scannerActive: _scannerActive,
          scannerConnected: _isScannerConnected,
          onScannerToggle: (v) => v ? _activateScanner() : _deactivateScanner(finalize: true),
          onBarcodeSubmitted: _scan,
          onSearchChanged: _onSearchChangedDebounced,
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 200,
          child: Scrollbar(
            controller: _productsScrollCtrl,
            child: PosProductList(
              scrollController: _productsScrollCtrl,
              products: products,
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
        ),
        const SizedBox(height: 8),
        PosPopularItemsGrid(
          allProducts: products,
          favoriteSkus: favoriteSkus,
          onAdd: (p) => addToCart(p),
        ),
        const SizedBox(height: 8),
        _CustomersDropdownCard(
          customersStream: _customerStream(ref.watch(selectedStoreIdProvider)),
          initialCustomers: customers,
          selectedCustomer: selectedCustomer,
          walkIn: walkIn,
          availablePoints: _availablePoints,
          onSelected: (c) => _onCustomerSelected(c),
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
          customersStream: _customerStream(ref.watch(selectedStoreIdProvider)),
          initialCustomers: customers,
          selectedCustomer: selectedCustomer,
          walkIn: walkIn,
          onCustomerSelected: (c) => _onCustomerSelected(c),
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
          onCheckout: () => completeSale(),
          onCheckoutCreditMix: (amt) => completeSale(creditPaidInput: amt),
          selectedPaymentMode: selectedPaymentMode,
          onPaymentModeChanged: (m) => setState(() => selectedPaymentMode = m),
          onQuickPrint: _quickPrintFromPanel,
          onPayCredit: (amt) => _payCustomerCredit(amt),
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
        final storeId = ref.read(selectedStoreIdProvider);
        if (storeId == null) {
          throw Exception('No store selected');
        }
        final bySku = await StoreRefs.of(storeId)
            .products()
            .where('sku', isEqualTo: code)
            .limit(1)
            .get();
        if (bySku.docs.isNotEmpty) {
          found = Product.fromDoc(bySku.docs.first);
        } else {
          final byBarcode = await StoreRefs.of(storeId)
              .products()
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

  Widget _kv(BuildContext context, String label, double value, {bool bold = false}) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ) ?? TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: bold ? FontWeight.bold : FontWeight.normal);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text('₹${value.toStringAsFixed(2)}', style: style)],
      ),
    );
  }

  Future<void> _payCustomerCredit(double enteredAmount) async {
    final cust = selectedCustomer;
    if (cust == null || cust.id.isEmpty) {
      _snack('Select a customer');
      return;
    }
    if (cart.isNotEmpty) {
      _snack('Clear cart before credit repayment');
      return;
    }
  final amount = enteredAmount.clamp(0, cust.creditBalance).toDouble();
    if (amount <= 0) {
      _snack('Enter amount');
      return;
    }
    try {
      await CustomerCreditService.repayCredit(customerId: cust.id, amount: amount, storeId: ref.read(selectedStoreIdProvider));
      _snack('Credit payment ₹${amount.toStringAsFixed(2)} recorded');
      // Refresh customer doc to update live balance (stream listener will also update if active)
      setState(() { selectedPaymentMode = PaymentMode.cash; });
    } catch (e) {
      _snack('Credit payment failed');
    }
  }
}

// _SearchableCustomerDropdown removed after introducing CheckoutPanel simple dropdown

// _ScannerToggle moved to pos_search_scan_fav.dart

class _HeldOrdersDialog extends StatefulWidget {
  final List<HeldOrder> orders;
  const _HeldOrdersDialog({required this.orders});

  @override
  State<_HeldOrdersDialog> createState() => _HeldOrdersDialogState();
}

class _HeldOrdersDialogState extends State<_HeldOrdersDialog> {
  Future<bool> _askDeleteConfirm(HeldOrder o) async {
    final rootCtx = rootNavigatorKey.currentContext;
    if (rootCtx == null) return false;
    final confirmed = await showDialog<bool>(
      context: rootCtx,
      barrierDismissible: false,
      builder: (dialogCtx) {
        final scheme = Theme.of(dialogCtx).colorScheme;
        final texts = Theme.of(dialogCtx).textTheme;
        return AlertDialog(
          title: Text(
            'Delete held order?',
            style: texts.titleMedium?.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w700),
          ),
          content: DefaultTextStyle(
            style: texts.bodyMedium?.copyWith(color: scheme.onSurface) ?? const TextStyle(),
            child: Text('Delete ${o.id}? This cannot be undone.'),
          ),
          actions: [
            TextButton(onPressed: () => rootNavigatorKey.currentState?.pop(false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError),
              onPressed: () => rootNavigatorKey.currentState?.pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    return confirmed == true;
  }

  Future<void> _confirmAndDelete(HeldOrder o) async {
    // Ensure popup menu is fully closed before opening a dialog to avoid layout glitches
    await Future.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    final confirmed = await _askDeleteConfirm(o);
    if (confirmed == true) {
      if (!mounted) return;
      setState(() {
        widget.orders.removeWhere((e) => e.id == o.id);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text(
        'Held Orders',
        style: texts.titleMedium?.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w700),
      ),
      content: DefaultTextStyle(
        style: texts.bodyMedium?.copyWith(color: scheme.onSurface) ?? const TextStyle(),
        child: SizedBox(
        width: 420,
        height: 360,
        child: widget.orders.isEmpty
            ? const Center(child: Text('No held orders'))
            : ListView.separated(
                itemCount: widget.orders.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final o = widget.orders[i];
                  final count = o.items.fold<int>(0, (s, it) => s + it.qty);
                  final time = '${o.timestamp.hour.toString().padLeft(2, '0')}:${o.timestamp.minute.toString().padLeft(2, '0')}';
                  return ListTile(
                    title: Text('${o.id} • $time'),
                    subtitle: Text('Items: $count'),
                    onTap: () => rootNavigatorKey.currentState?.pop(o),
                    trailing: PopupMenuButton<String>(
                      tooltip: 'More',
                      itemBuilder: (_) => [
                        const PopupMenuItem<String>(value: 'delete', child: Text('Delete')),
                      ],
                      onSelected: (v) {
                        if (v == 'delete') {
                          _confirmAndDelete(o);
                        }
                      },
                      icon: const Icon(Icons.more_vert),
                    ),
                  );
                },
              ),
        ),
      ),
  actions: [TextButton(onPressed: () => rootNavigatorKey.currentState?.pop(), child: const Text('Close'))],
    );
  }
}

// ---------------- Simple Print Settings Dialog (placeholder) ----------------
// Print Settings UI removed; printing now sends to backend default printer.


// Lightweight Customers dropdown/details card placed below cart section
class _CustomersDropdownCard extends StatelessWidget {
  final Stream<List<Customer>> customersStream;
  final List<Customer> initialCustomers;
  final Customer? selectedCustomer;
  final Customer walkIn;
  final double availablePoints;
  final ValueChanged<Customer?> onSelected;

  const _CustomersDropdownCard({
    required this.customersStream,
    required this.initialCustomers,
    required this.selectedCustomer,
    required this.walkIn,
    required this.availablePoints,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.person_search_outlined),
        title: const Text('Customers'),
        childrenPadding: const EdgeInsets.only(bottom: 12, left: 12, right: 12),
        children: [
          StreamBuilder<List<Customer>>(
            stream: customersStream,
            initialData: initialCustomers,
            builder: (ctx, snap) {
              final raw = snap.data ?? initialCustomers;
              final list = <Customer>[walkIn, ...raw.where((c) => c.id != walkIn.id)];
              Customer value = list.first;
              final selId = selectedCustomer?.id ?? value.id;
              for (final c in list) {
                if (c.id == selId) { value = c; break; }
              }
              return DropdownButtonFormField<Customer>(
                initialValue: value,
                items: list
                    .map((c) => DropdownMenuItem<Customer>(value: c, child: Text(c.name, overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: onSelected,
                decoration: const InputDecoration(
                  labelText: 'Select customer',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          _InfoRow(icon: Icons.phone_iphone, label: 'Phone', value: selectedCustomer?.phone?.isNotEmpty == true ? selectedCustomer!.phone! : '—'),
          _InfoRow(icon: Icons.email_outlined, label: 'Email', value: selectedCustomer?.email?.isNotEmpty == true ? selectedCustomer!.email! : '—'),
          _InfoRow(icon: Icons.stars_outlined, label: 'Status', value: (selectedCustomer?.status ?? 'walk-in').toString()),
          _InfoRow(icon: Icons.savings_outlined, label: 'Points', value: availablePoints.toStringAsFixed(0)),
          _InfoRow(icon: Icons.account_balance_wallet_outlined, label: 'Credit', value: '₹${(selectedCustomer?.creditBalance ?? 0).toStringAsFixed(2)}'),
          const SizedBox(height: 4),
          Divider(height: 1, color: cs.outlineVariant),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant))),
          Text(value, style: tt.bodyMedium?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}


