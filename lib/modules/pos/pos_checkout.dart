import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'pos.dart';
import 'printing/print_settings.dart';

class CheckoutPanel extends StatefulWidget {
  final Stream<List<Customer>> customersStream;
  final List<Customer> initialCustomers;
  final Customer? selectedCustomer;
  final Customer walkIn;
  final ValueChanged<Customer?> onCustomerSelected;
  // Scroll controller shared with parent to ensure Scrollbar attaches correctly
  final ScrollController? scrollController;
  final double subtotal;
  final double discountValue;
  final double redeemValue;
  final double grandTotal;
  final double payableTotal;
  final double Function() getRedeemedPoints;
  final double Function() getAvailablePoints;
  final TextEditingController redeemPointsController;
  final VoidCallback onRedeemMax;
  final VoidCallback onRedeemChanged;
  final Map<String, CartItem> cart;
  final Map<String, double> lineTaxes;
  final VoidCallback onCheckout;
  // For mixed credit checkout (cart present + credit payment entered)
  final void Function(double amount)? onCheckoutCreditMix;
  final VoidCallback? onQuickPrint;
  final PaymentMode selectedPaymentMode;
  final ValueChanged<PaymentMode> onPaymentModeChanged;
  final Future<void> Function(double amount)? onPayCredit; // repay credit without creating a new sale
  const CheckoutPanel({
    super.key,
    required this.customersStream,
    required this.initialCustomers,
    required this.selectedCustomer,
    required this.walkIn,
    required this.onCustomerSelected,
    this.scrollController,
    required this.subtotal,
    required this.discountValue,
    required this.redeemValue,
    required this.grandTotal,
    required this.payableTotal,
    required this.getRedeemedPoints,
    required this.getAvailablePoints,
    required this.redeemPointsController,
    required this.onRedeemMax,
    required this.onRedeemChanged,
    required this.cart,
    required this.lineTaxes,
  required this.onCheckout,
  this.onCheckoutCreditMix,
    this.onQuickPrint,
    required this.selectedPaymentMode,
    required this.onPaymentModeChanged,
    this.onPayCredit,
  });
  @override
  State<CheckoutPanel> createState() => _CheckoutPanelState();
}

class _CheckoutPanelState extends State<CheckoutPanel> {
  late final ScrollController _scrollCtrl;
  final TextEditingController _creditAmountCtrl = TextEditingController();
  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController();
    _creditAmountCtrl.addListener(() => setState(() {}));
  }
  @override
  void dispose() {
    _scrollCtrl.dispose();
    _creditAmountCtrl.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final selectedCustomer = widget.selectedCustomer;
    final taxesByRate = <int, double>{};
    for (final it in widget.cart.values) {
      final tax = widget.lineTaxes[it.product.sku] ?? 0.0;
      taxesByRate.update(it.product.taxPercent, (v) => v + tax, ifAbsent: () => tax);
    }
    final content = SingleChildScrollView(
      controller: _scrollCtrl,
      primary: false,
      padding: const EdgeInsets.all(10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _CustomerDropdown(
          customersStream: widget.customersStream,
          initialCustomers: widget.initialCustomers,
          selected: selectedCustomer,
          onSelected: widget.onCustomerSelected,
          walkIn: widget.walkIn,
        ),
        const SizedBox(height: 6),
        _CustomerInfo(
          selected: selectedCustomer,
          creditActive: widget.selectedPaymentMode == PaymentMode.credit,
        ),
        const SizedBox(height: 8),
        _kv('Subtotal', widget.subtotal),
        _kv('Discount', -widget.discountValue),
        if (widget.redeemValue > 0) _kv('Redeemed (Pts)', -widget.redeemValue),
        const SizedBox(height: 6),
        Builder(builder: (context) => Text('GST Breakdown', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w700))),
        ...taxesByRate.entries.map((e) => _kv('GST ${e.key}%', e.value)),
        const Divider(),
        _kv('Grand Total', widget.grandTotal),
        if (widget.redeemValue > 0) _kv('Redeem Applied', -widget.redeemValue),
        _kv('Payable', widget.payableTotal, bold: true),
        const SizedBox(height: 10),
        _RedeemSection(
          controller: widget.redeemPointsController,
          availablePoints: widget.getAvailablePoints(),
          redeemValue: widget.redeemValue,
          onChange: widget.onRedeemChanged,
          onMax: widget.onRedeemMax,
          redeemedPoints: widget.getRedeemedPoints(),
        ),
        const SizedBox(height: 10),
  _paymentModesSection(buildButton: (mode, label, icon) => _payModeButton(context, mode, label, icon)),
        if (widget.selectedPaymentMode == PaymentMode.credit) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: TextField(
                controller: _creditAmountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Amount Paid Now (₹)',
                  prefixIcon: Icon(Icons.receipt_long),
                  border: OutlineInputBorder(),
                  helperText: 'Leave blank = 0. Less than payable → rest becomes new credit. More than payable → extra repays old credit.',
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          _CreditPreview(
            entered: double.tryParse(_creditAmountCtrl.text.trim()) ?? 0,
            payable: widget.payableTotal,
            existingCredit: widget.selectedCustomer?.creditBalance ?? 0,
          ),
        ],
        const SizedBox(height: 12),
  _actionsSection(
          onQuickPrint: widget.onQuickPrint,
          onCheckout: () {
            if (widget.selectedPaymentMode == PaymentMode.credit) {
              final amt = double.tryParse(_creditAmountCtrl.text.trim()) ?? 0;
              if (kDebugMode) {
                debugPrint('[CheckoutPanel] Credit button pressed cartItems=${widget.cart.length} amt=$amt mixCb=${widget.onCheckoutCreditMix!=null} repayCb=${widget.onPayCredit!=null}');
              }
              if (widget.cart.isNotEmpty) {
                if (widget.onCheckoutCreditMix != null) {
                  widget.onCheckoutCreditMix!(amt);
                } else if (kDebugMode) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Missing credit mix callback')));
                }
              } else {
                if (widget.onPayCredit != null) {
                  widget.onPayCredit!(amt);
                } else if (kDebugMode) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Missing credit repay callback')));
                }
              }
            } else {
              widget.onCheckout();
            }
          },
          openPrintSettings: () => _openPrintSettings(context),
          creditMode: widget.selectedPaymentMode == PaymentMode.credit,
        ),
      ]),
    );
    return Card(
      child: Scrollbar(
        controller: _scrollCtrl,
        thumbVisibility: true,
        child: content,
      ),
    );
  }

  // Localized responsive section: payment modes
  Widget _paymentModesSection({
    required Widget Function(PaymentMode mode, String label, IconData icon) buildButton,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 420;
        if (narrow) {
          return Column(children: [
            SizedBox(width: double.infinity, child: buildButton(PaymentMode.cash, 'Cash', Icons.payments)),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: buildButton(PaymentMode.upi, 'UPI', Icons.qr_code)),
          ]);
        }
        return Row(children: [
          Expanded(child: buildButton(PaymentMode.cash, 'Cash', Icons.payments)),
          const SizedBox(width: 8),
          Expanded(child: buildButton(PaymentMode.upi, 'UPI', Icons.qr_code)),
        ]);
      },
    );
  }

  // Localized responsive section: actions (print/settings/checkout)
  Widget _actionsSection({
    required VoidCallback? onQuickPrint,
    required VoidCallback openPrintSettings,
    required VoidCallback onCheckout,
    required bool creditMode,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 420;
        if (narrow) {
          return Column(children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              ElevatedButton.icon(
                onPressed: () { final qp = onQuickPrint; if (qp != null) qp(); },
                icon: const Icon(Icons.print),
                label: const Text('Print'),
              ),
              IconButton(
                tooltip: 'Print Settings',
                onPressed: openPrintSettings,
                icon: const Icon(Icons.settings),
              ),
            ]),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onCheckout,
                icon: const Icon(Icons.check_circle),
                label: Text(creditMode ? 'Checkout (Credit Mix)' : 'Checkout'),
              ),
            ),
          ]);
        }
        return Row(children: [
          ElevatedButton.icon(
            onPressed: () { final qp = onQuickPrint; if (qp != null) qp(); },
            icon: const Icon(Icons.print),
            label: const Text('Print'),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Print Settings',
            onPressed: openPrintSettings,
            icon: const Icon(Icons.settings),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: onCheckout,
              icon: const Icon(Icons.check_circle),
              label: Text(creditMode ? 'Checkout (Credit Mix)' : 'Checkout'),
            ),
          ),
        ]);
      },
    );
  }
  Widget _payModeButton(BuildContext context, PaymentMode mode, String label, IconData icon) {
    final selected = widget.selectedPaymentMode == mode;
    return OutlinedButton.icon(
      onPressed: () {
        if (mode == PaymentMode.credit) {
          // Leave field blank per new UX (no auto-populate)
          _creditAmountCtrl.text = '';
        }
        widget.onPaymentModeChanged(mode);
      },
      icon: Icon(icon, color: selected ? Theme.of(context).colorScheme.primary : null),
      label: Text(label),
      style: OutlinedButton.styleFrom(
  backgroundColor: selected ? Theme.of(context).colorScheme.primary.withOpacity(0.08) : null,
        side: BorderSide(color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).dividerColor),
      ),
    );
  }
  Widget _kv(String label, double value, {bool bold = false}) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ) ?? TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: bold ? FontWeight.bold : FontWeight.normal);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: style),
        Text('₹${value.toStringAsFixed(2)}', style: style),
      ]),
    );
  }
  Future<void> _openPrintSettings(BuildContext context) async {
    final ps = globalPrintSettings;
    int tempWidth = ps.receiptCharWidth;
    int tempPaperMm = ps.paperWidthMm;
    int tempFontSize = ps.fontSizePt;
    PaperSize tempSize = ps.paperSize;
    PageOrientation tempOrientation = ps.orientation;
    bool tempScale = ps.scaleToFit;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        final scheme = Theme.of(ctx).colorScheme;
        final texts = Theme.of(ctx).textTheme;
        int previewWidth = tempScale && tempSize == PaperSize.receipt ? _deriveCharWidth(tempPaperMm) : tempWidth;
        return AlertDialog(
          title: Text(
            'Print Settings',
            style: texts.titleMedium?.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w700),
          ),
          content: DefaultTextStyle(
            style: texts.bodyMedium?.copyWith(color: scheme.onSurface) ?? const TextStyle(),
            child: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                const Text('Paper:'), const SizedBox(width: 8),
                DropdownButton<PaperSize>(
                  value: tempSize,
                  items: const [
                    DropdownMenuItem(value: PaperSize.receipt, child: Text('Receipt (Thermal)')),
                    DropdownMenuItem(value: PaperSize.a4, child: Text('A4')),
                  ],
                  onChanged: (v) { if (v != null) setLocal(() => tempSize = v); },
                ),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                const Text('Orientation:'), const SizedBox(width: 8),
                DropdownButton<PageOrientation>(
                  value: tempOrientation,
                  items: const [
                    DropdownMenuItem(value: PageOrientation.portrait, child: Text('Portrait')),
                    DropdownMenuItem(value: PageOrientation.landscape, child: Text('Landscape')),
                  ],
                  onChanged: tempSize == PaperSize.receipt ? null : (v) { if (v != null) setLocal(() => tempOrientation = v); },
                ),
              ]),
              if (tempSize == PaperSize.receipt) const SizedBox(height: 8),
              if (tempSize == PaperSize.receipt) Row(children: [
                const Text('Width (mm):'), const SizedBox(width: 8),
                DropdownButton<int>(
                  value: tempPaperMm,
                  items: const [
                    DropdownMenuItem(value: 48, child: Text('48 mm')),
                    DropdownMenuItem(value: 58, child: Text('58 mm')),
                    DropdownMenuItem(value: 80, child: Text('80 mm')),
                  ],
                  onChanged: (v) { if (v != null) setLocal(() => tempPaperMm = v); },
                ),
              ]),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Auto scale to paper width'),
                value: tempScale,
                onChanged: (v) => setLocal(() => tempScale = v),
              ),
              const SizedBox(height: 8),
              Row(children: [
                const Text('Font size:'), const SizedBox(width: 8),
                Expanded(
                  child: Slider(
                    min: 6,
                    max: 24,
                    divisions: 18,
                    value: tempFontSize.toDouble(),
                    label: '${tempFontSize}pt',
                    onChanged: (v) => setLocal(() => tempFontSize = v.round()),
                  ),
                ),
                SizedBox(
                    width: 40,
                    child: Text(
                      '${tempFontSize}pt',
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.labelSmall,
                    ))
              ]),
              const SizedBox(height: 8),
              if (tempSize == PaperSize.receipt && !tempScale) Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Receipt Character Width'),
                Slider(
                  min: 20,
                  max: 80,
                  divisions: 60,
                  value: tempWidth.toDouble(),
                  label: '$tempWidth',
                  onChanged: (v) => setLocal(() => tempWidth = v.round()),
                ),
              ]),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Preview width: $previewWidth chars • Font ${tempFontSize}pt (${tempSize == PaperSize.receipt ? '${tempPaperMm}mm' : 'A4'})',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(fontStyle: FontStyle.italic),
                ),
              )
            ]),
          ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(onPressed: () {
              ps.update(
                paperSize: tempSize,
                orientation: tempOrientation,
                scaleToFit: tempScale,
                receiptCharWidth: tempWidth,
                paperWidthMm: tempPaperMm,
                fontSizePt: tempFontSize,
              );
              Navigator.pop(ctx);
            }, child: const Text('Save')),
          ],
        );
      }),
    );
  }
  int _deriveCharWidth(int mm) {
    if (mm <= 50) return 32;
    if (mm <= 60) return 40;
    if (mm <= 72) return 48;
    if (mm <= 86) return 56;
    return 64;
  }
}

class _CreditPreview extends StatelessWidget {
  final double entered;
  final double payable;
  final double existingCredit;
  const _CreditPreview({required this.entered, required this.payable, required this.existingCredit});

  @override
  Widget build(BuildContext context) {
    if (entered < 0) return const SizedBox.shrink();
    double addPortion = 0;
    double repayPortion = 0;
    if (entered >= payable) {
      final excess = entered - payable;
      repayPortion = excess.clamp(0, existingCredit);
    } else {
      addPortion = (payable - entered).clamp(0, double.infinity);
    }
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall;
    String msg;
    if (addPortion > 0) {
      msg = 'Will ADD credit: ₹${addPortion.toStringAsFixed(2)} (Customer owes more)';
    } else if (repayPortion > 0) {
      msg = 'Will REPAY old credit: ₹${repayPortion.toStringAsFixed(2)}';
    } else {
      msg = 'Fully paid — no credit change';
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(msg, style: style?.copyWith(color: theme.colorScheme.secondary)),
    );
  }
}

class _CustomerInfo extends StatelessWidget {
  final Customer? selected; final bool creditActive;
  const _CustomerInfo({required this.selected, this.creditActive = false});
  String _fmtPts(double v) { final s = v.toStringAsFixed(1); return s.endsWith('.0') ? s.substring(0, s.length - 2) : s; }
  @override
  Widget build(BuildContext context) {
    final c = selected; if (c == null || c.id.isEmpty) return const SizedBox();
    String planLabel = (c.status ?? 'standard'); planLabel = planLabel[0].toUpperCase() + planLabel.substring(1);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
  color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.4),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Builder(
          builder: (context) => Text(
            c.name,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
          ),
        ),
        if (c.email != null && c.email!.isNotEmpty)
          Text(
            c.email!,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        const SizedBox(height: 4),
        Wrap(spacing: 12, runSpacing: 4, children: [
          _miniInfoChip(context, Icons.workspace_premium, 'Plan: $planLabel'),
          _miniInfoChip(context, Icons.percent, 'Discount: ${c.discountPercent.toStringAsFixed(0)}%'),
          _miniInfoChip(context, Icons.card_giftcard, 'Rewards: ${_fmtPts(c.rewardsPoints)}'),
          _miniInfoChip(context, Icons.account_balance_wallet, 'Spend: ₹${c.totalSpend.toStringAsFixed(0)}'),
          if (c.creditBalance > 0 || creditActive)
            _miniInfoChip(context, Icons.receipt_long, 'Credit: ₹${c.creditBalance.toStringAsFixed(0)}'),
        ])
      ]),
    );
  }
  Widget _miniInfoChip(BuildContext context, IconData icon, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
  color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
      borderRadius: BorderRadius.circular(24),
  border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.3)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 4),
      Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurface),
      ),
    ]),
  );
}

// _PayCreditButton removed (repayment flow simplified)

class _RedeemSection extends StatelessWidget {
  final TextEditingController controller; final double availablePoints; final double redeemedPoints; final double redeemValue; final VoidCallback onChange; final VoidCallback onMax;
  const _RedeemSection({required this.controller, required this.availablePoints, required this.redeemValue, required this.onChange, required this.onMax, required this.redeemedPoints});
  @override
  Widget build(BuildContext context) {
    final entered = redeemedPoints; final over = entered > availablePoints; final negative = entered < 0;
    String? errorText; if (negative) { errorText = 'Cannot be negative'; } else if (over) { errorText = 'Not enough points (Avail: ${availablePoints.toStringAsFixed(0)})'; }
    final helper = (!over && !negative && redeemValue > 0) ? 'Value: ₹${redeemValue.toStringAsFixed(2)}' : (!over && !negative ? 'Enter points to redeem' : null);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 8),
      Row(children: [
        Flexible(child: Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: 'Redeem Points',
                prefixIcon: const Icon(Icons.card_giftcard),
                helperText: helper,
                errorText: errorText,
                suffixIcon: (availablePoints > 0)
                    ? Tooltip(
                        message: 'Available: ${availablePoints.toStringAsFixed(0)}',
                        child: Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: Center(
                                widthFactor: 1,
                                child: Text(
                                  availablePoints.toStringAsFixed(0),
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ))))
                    : null,
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => onChange(),
            ),
          ),
        )),
        const SizedBox(width: 8),
        ElevatedButton(onPressed: availablePoints <= 0 ? null : onMax, child: const Text('Max')),
      ])
    ]);
  }
}

class _CustomerDropdown extends StatefulWidget {
  final Stream<List<Customer>> customersStream; final List<Customer> initialCustomers; final Customer? selected; final ValueChanged<Customer?> onSelected; final Customer walkIn;
  const _CustomerDropdown({required this.customersStream, required this.initialCustomers, required this.selected, required this.onSelected, required this.walkIn});
  @override
  State<_CustomerDropdown> createState() => _CustomerDropdownState();
}

class _CustomerDropdownState extends State<_CustomerDropdown> {
  late List<Customer> _all; bool _expanded = false; final TextEditingController _searchCtrl = TextEditingController(); StreamSubscription<List<Customer>>? _sub;
  @override
  void initState() { super.initState(); _all = [widget.walkIn, ...widget.initialCustomers]; _sub = widget.customersStream.listen((list) { setState(() { final byId = <String, Customer>{ for (final c in list) c.id : c }; _all = [widget.walkIn, ...byId.values.where((c) => c.id != widget.walkIn.id)]; }); }); }
  @override
  void dispose() { _sub?.cancel(); _searchCtrl.dispose(); super.dispose(); }
  List<Customer> get _filtered { final q = _searchCtrl.text.trim().toLowerCase(); if (q.isEmpty) return _all; return _all.where((c) { bool m(String? v) => v != null && v.toLowerCase().contains(q); return m(c.name) || m(c.email) || m(c.phone); }).toList(); }
  @override
  Widget build(BuildContext context) {
    final sel = widget.selected ?? widget.walkIn;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: InputDecorator(
          decoration: const InputDecoration(labelText: 'Customer', border: OutlineInputBorder(), isDense: true),
          child: Row(children: [
            const Icon(Icons.person, size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                sel.name,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            IconButton(
              tooltip: 'Add Customer',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: const Icon(Icons.add_circle_outline, size: 20),
              onPressed: () async {
                final created = await _showAddCustomerDialog(context);
                if (created != null) { widget.onSelected(created); if (!mounted) return; setState(() { _expanded = false; }); }
              },
            ),
            const SizedBox(width: 4),
            Icon(_expanded ? Icons.expand_less : Icons.expand_more),
          ]),
        ),
      ),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: _expanded ? Container(
          key: const ValueKey('dd'),
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(6),
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
          ),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search name / email / phone',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const Divider(height: 1),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: _filtered.isEmpty ? const Padding(padding: EdgeInsets.all(16.0), child: Text('No customers')) : ListView.separated(
                shrinkWrap: true,
                itemCount: _filtered.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final c = _filtered[i]; final isSel = c.id == sel.id;
                  return ListTile(
                    dense: true,
                    leading: isSel ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary) : const Icon(Icons.person_outline),
                    title: Text(
                      c.name,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                    ),
                    subtitle: (c.email != null && c.email!.isNotEmpty)
                        ? Text(
                            c.email!,
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          )
                        : null,
                    onTap: () { widget.onSelected(c.id.isEmpty ? null : c); setState(() { _expanded = false; _searchCtrl.clear(); }); },
                  );
                },
              ),
            ),
          ]),
        ) : const SizedBox.shrink(),
      ),
    ]);
  }
  Future<Customer?> _showAddCustomerDialog(BuildContext context) async {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final addrCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool saving = false;
    final created = await showDialog<Customer?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final scheme = Theme.of(ctx).colorScheme;
          final texts = Theme.of(ctx).textTheme;
          return AlertDialog(
            title: Text(
              'Add Customer',
              style: texts.titleMedium?.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w700),
            ),
            content: DefaultTextStyle(
              style: texts.bodyMedium?.copyWith(color: scheme.onSurface) ?? const TextStyle(),
              child: SizedBox(
              width: 420,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(labelText: 'Name *'),
                        autofocus: true,
                        validator: (v) => (v==null || v.trim().isEmpty) ? 'Name required' : null,
                      ),
                      TextFormField(
                        controller: emailCtrl,
                        decoration: const InputDecoration(labelText: 'Email'),
                        keyboardType: TextInputType.emailAddress,
                      ),
                      TextFormField(
                        controller: phoneCtrl,
                        decoration: const InputDecoration(labelText: 'Phone'),
                        keyboardType: TextInputType.phone,
                      ),
                      TextFormField(
                        controller: addrCtrl,
                        decoration: const InputDecoration(labelText: 'Address'),
                        minLines: 2,
                        maxLines: 3,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(ctx, null),
                child: const Text('Close'),
              ),
              FilledButton.icon(
                onPressed: saving ? null : () async {
                  if (!formKey.currentState!.validate()) return;
                  setLocal(() => saving = true);
                  final nav = Navigator.of(ctx);
                  final messenger = ScaffoldMessenger.of(ctx);
                  try {
                    final name = nameCtrl.text.trim();
                    final data = <String, dynamic>{
                      'name': name.isEmpty ? 'Unnamed' : name,
                      'email': emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
                      'phone': phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
                      'address': addrCtrl.text.trim().isEmpty ? null : addrCtrl.text.trim(),
                      'createdAt': FieldValue.serverTimestamp(),
                      'updatedAt': FieldValue.serverTimestamp(),
                    };
                    final doc = await FirebaseFirestore.instance.collection('customers').add(data);
                    final newCustomer = Customer(
                      id: doc.id,
                      name: name.isEmpty ? 'Unnamed' : name,
                      email: emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
                      phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
                      status: null,
                      totalSpend: 0,
                      rewardsPoints: 0,
                      discountPercent: 0,
                      creditBalance: 0,
                    );
                    nav.pop(newCustomer);
                  } catch (e) {
                    if (kDebugMode) debugPrint('Add customer failed: $e');
                    messenger.showSnackBar(
                      SnackBar(content: Text('Failed: $e')),
                    );
                  } finally {
                    // Only reset state if the dialog is still visible and we haven't popped.
                    if (saving && nav.mounted) {
                      // If we reached here after an error (no pop) keep dialog enabled again.
                      if (mounted && nav.canPop()) {
                        setLocal(() => saving = false);
                      }
                    }
                  }
                },
                icon: saving
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      )
                    : const Icon(Icons.save),
                label: Text(saving ? 'Saving...' : 'Save'),
              ),
            ],
          );
        },
      ),
    );
    // Dispose controllers
    nameCtrl.dispose();
    emailCtrl.dispose();
    phoneCtrl.dispose();
    addrCtrl.dispose();
    if (created != null && mounted) {
      setState(() {
        if (!_all.any((c) => c.id == created.id)) {
          _all.add(created);
        }
      });
    }
    return created;
  }
}
