import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'pos.dart';
import '../../core/theme/theme_extension_helpers.dart';

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
      padding: context.padSm,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _CustomerDropdown(
          customersStream: widget.customersStream,
          initialCustomers: widget.initialCustomers,
          selected: selectedCustomer,
          onSelected: widget.onCustomerSelected,
          walkIn: widget.walkIn,
        ),
        SizedBox(height: context.sizes.gapXs),
        _CustomerInfo(
          selected: selectedCustomer,
          creditActive: widget.selectedPaymentMode == PaymentMode.credit,
        ),
        SizedBox(height: context.sizes.gapSm),
        _BillingSummary(
          subtotal: widget.subtotal,
          discountValue: widget.discountValue,
          redeemValue: widget.redeemValue,
          grandTotal: widget.grandTotal,
          payableTotal: widget.payableTotal,
          taxesByRate: taxesByRate,
        ),
        SizedBox(height: context.sizes.gapSm),
        _RedeemSection(
          controller: widget.redeemPointsController,
          availablePoints: widget.getAvailablePoints(),
          redeemValue: widget.redeemValue,
          onChange: widget.onRedeemChanged,
          onMax: widget.onRedeemMax,
          redeemedPoints: widget.getRedeemedPoints(),
        ),
        SizedBox(height: context.sizes.gapMd),
  _paymentAndCheckoutRow(
          context: context,
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
          creditMode: widget.selectedPaymentMode == PaymentMode.credit,
        ),
        if (widget.selectedPaymentMode == PaymentMode.credit) ...[  
          context.gapVSm,
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
          context.gapVXs,
          _CreditPreview(
            entered: double.tryParse(_creditAmountCtrl.text.trim()) ?? 0,
            payable: widget.payableTotal,
            existingCredit: widget.selectedCustomer?.creditBalance ?? 0,
          ),
        ],
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

  // Compact payment toggle with checkout
  Widget _paymentAndCheckoutRow({
    required BuildContext context,
    required VoidCallback onCheckout,
    required bool creditMode,
  }) {
    final cs = Theme.of(context).colorScheme;
    final isCash = widget.selectedPaymentMode == PaymentMode.cash;
    final isUpi = widget.selectedPaymentMode == PaymentMode.upi;
    
    return Column(
      children: [
        // Compact segmented toggle
        Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withOpacity(0.4),
            borderRadius: context.radiusSm,
          ),
          padding: EdgeInsets.all(context.sizes.gapXs),
          child: Row(
            children: [
              // Cash toggle
              Expanded(
                child: GestureDetector(
                  onTap: () => widget.onPaymentModeChanged(PaymentMode.cash),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: EdgeInsets.symmetric(vertical: context.sizes.gapSm),
                    decoration: BoxDecoration(
                      color: isCash ? cs.primary : Colors.transparent,
                      borderRadius: context.radiusSm,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.payments_rounded, size: context.sizes.iconXs, color: isCash ? cs.onPrimary : cs.onSurfaceVariant),
                        SizedBox(width: context.sizes.gapXs),
                        Text('Cash', style: TextStyle(fontSize: context.sizes.fontXs, color: isCash ? cs.onPrimary : cs.onSurfaceVariant, fontWeight: isCash ? FontWeight.w600 : FontWeight.w500)),
                      ],
                    ),
                  ),
                ),
              ),
              // UPI toggle
              Expanded(
                child: GestureDetector(
                  onTap: () => widget.onPaymentModeChanged(PaymentMode.upi),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: EdgeInsets.symmetric(vertical: context.sizes.gapSm),
                    decoration: BoxDecoration(
                      color: isUpi ? cs.primary : Colors.transparent,
                      borderRadius: context.radiusSm,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.qr_code_rounded, size: context.sizes.iconXs, color: isUpi ? cs.onPrimary : cs.onSurfaceVariant),
                        SizedBox(width: context.sizes.gapXs),
                        Text('UPI', style: TextStyle(fontSize: context.sizes.fontXs, color: isUpi ? cs.onPrimary : cs.onSurfaceVariant, fontWeight: isUpi ? FontWeight.w600 : FontWeight.w500)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: context.sizes.gapSm),
        // Checkout button
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onCheckout,
            icon: Icon(creditMode ? Icons.credit_card : Icons.check_circle_rounded, size: context.sizes.iconSm),
            label: Text(creditMode ? 'Pay Credit' : 'Checkout', style: TextStyle(fontWeight: FontWeight.w600, fontSize: context.sizes.fontSm)),
            style: FilledButton.styleFrom(
              padding: EdgeInsets.symmetric(vertical: context.sizes.gapMd),
              shape: RoundedRectangleBorder(borderRadius: context.radiusSm),
            ),
          ),
        ),
      ],
    );
  }
}

// Modern billing summary card
class _BillingSummary extends StatelessWidget {
  final double subtotal;
  final double discountValue;
  final double redeemValue;
  final double grandTotal;
  final double payableTotal;
  final Map<int, double> taxesByRate;
  
  const _BillingSummary({
    required this.subtotal,
    required this.discountValue,
    required this.redeemValue,
    required this.grandTotal,
    required this.payableTotal,
    required this.taxesByRate,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final sizes = context.sizes;
    return Container(
      padding: EdgeInsets.all(sizes.gapMd),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: context.radiusSm,
      ),
      child: Column(
        children: [
          _row(context, 'Subtotal', subtotal, cs.onSurface),
          if (discountValue > 0) _row(context, 'Discount', -discountValue, context.appColors.success),
          if (redeemValue > 0) _row(context, 'Redeemed', -redeemValue, context.appColors.warning),
          SizedBox(height: sizes.gapXs),
          // GST rows
          if (taxesByRate.isNotEmpty) ...[
            Row(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: sizes.gapSm, vertical: sizes.gapXs),
                  decoration: BoxDecoration(
                    color: cs.secondaryContainer,
                    borderRadius: context.radiusSm,
                  ),
                  child: Text('GST', style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w600, color: cs.onSecondaryContainer)),
                ),
                const Spacer(),
              ],
            ),
            SizedBox(height: sizes.gapXs),
            ...taxesByRate.entries.map((e) => _row(context, '${e.key}%', e.value, cs.onSurfaceVariant, small: true)),
          ],
          Divider(height: sizes.gapMd, color: cs.outlineVariant.withOpacity(0.5)),
          _row(context, 'Grand Total', grandTotal, cs.onSurface),
          SizedBox(height: sizes.gapXs),
          // Payable highlight
          Container(
            padding: EdgeInsets.symmetric(horizontal: sizes.gapSm, vertical: sizes.gapSm),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [cs.primary.withOpacity(0.15), cs.primary.withOpacity(0.05)],
              ),
              borderRadius: context.radiusSm,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Payable', style: TextStyle(fontWeight: FontWeight.w700, fontSize: sizes.fontSm, color: cs.primary)),
                Text('₹${payableTotal.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: sizes.fontMd, color: cs.primary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, double value, Color color, {bool small = false}) {
    final sizes = context.sizes;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: sizes.gapXs / 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: small ? sizes.fontXs : sizes.fontSm, color: color)),
          Text('₹${value.toStringAsFixed(2)}', style: TextStyle(fontSize: small ? sizes.fontXs : sizes.fontSm, fontWeight: FontWeight.w500, color: color)),
        ],
      ),
    );
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
    final cs = context.colors;
    final sizes = context.sizes;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(sizes.gapSm),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primaryContainer.withOpacity(0.3), cs.primaryContainer.withOpacity(0.1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: context.radiusSm,
        border: Border.all(color: cs.primary.withOpacity(0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          children: [
            Container(
              padding: EdgeInsets.all(sizes.gapXs),
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.1),
                borderRadius: context.radiusSm,
              ),
              child: Icon(Icons.person_rounded, size: sizes.iconXs, color: cs.primary),
            ),
            SizedBox(width: sizes.gapSm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.name, style: TextStyle(fontWeight: FontWeight.w600, fontSize: sizes.fontSm, color: cs.onSurface)),
                  if (c.email != null && c.email!.isNotEmpty)
                    Text(c.email!, style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: sizes.gapSm),
        Wrap(spacing: sizes.gapSm, runSpacing: sizes.gapXs, children: [
          _CompactChip(icon: Icons.workspace_premium_rounded, text: planLabel, color: cs.tertiary),
          _CompactChip(icon: Icons.percent_rounded, text: '${c.discountPercent.toStringAsFixed(0)}%', color: cs.secondary),
          _CompactChip(icon: Icons.card_giftcard_rounded, text: _fmtPts(c.rewardsPoints), color: cs.primary),
          _CompactChip(icon: Icons.account_balance_wallet_rounded, text: '₹${c.totalSpend.toStringAsFixed(0)}', color: context.appColors.success),
          if (c.creditBalance > 0 || creditActive)
            _CompactChip(icon: Icons.receipt_long_rounded, text: '₹${c.creditBalance.toStringAsFixed(0)}', color: cs.error),
        ])
      ]),
    );
  }
}

// Compact info chip
class _CompactChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _CompactChip({required this.icon, required this.text, required this.color});
  
  @override
  Widget build(BuildContext context) {
    final sizes = context.sizes;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: sizes.gapSm, vertical: sizes.gapXs),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: context.radiusSm,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: sizes.iconXs - 4, color: color),
        SizedBox(width: sizes.gapXs),
        Text(text, style: TextStyle(fontSize: sizes.fontXs, color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// _PayCreditButton removed (repayment flow simplified)

class _RedeemSection extends StatelessWidget {
  final TextEditingController controller; final double availablePoints; final double redeemedPoints; final double redeemValue; final VoidCallback onChange; final VoidCallback onMax;
  const _RedeemSection({required this.controller, required this.availablePoints, required this.redeemValue, required this.onChange, required this.onMax, required this.redeemedPoints});
  @override
  Widget build(BuildContext context) {
    final entered = redeemedPoints; final over = entered > availablePoints; final negative = entered < 0;
    String? errorText; if (negative) { errorText = 'Cannot be negative'; } else if (over) { errorText = 'Max: ${availablePoints.toStringAsFixed(0)}'; }
    final cs = context.colors;
    final sizes = context.sizes;
    return Row(children: [
      Flexible(child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 200),
          child: TextField(
            controller: controller,
            style: TextStyle(fontSize: sizes.fontXs),
            decoration: InputDecoration(
              labelText: 'Redeem Points',
              labelStyle: TextStyle(fontSize: sizes.fontXs),
              prefixIcon: Icon(Icons.card_giftcard_rounded, size: sizes.iconSm, color: cs.primary),
              errorText: errorText,
              errorStyle: TextStyle(fontSize: sizes.fontXs),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: sizes.gapMd, vertical: sizes.gapSm),
              suffixIcon: availablePoints > 0 ? Padding(
                padding: EdgeInsets.only(right: sizes.gapSm),
                child: Center(
                  widthFactor: 1,
                  child: Text(availablePoints.toStringAsFixed(0), style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurfaceVariant)),
                ),
              ) : null,
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => onChange(),
          ),
        ),
      )),
      SizedBox(width: sizes.gapSm),
      SizedBox(
        height: sizes.buttonHeightSm,
        child: FilledButton(
          onPressed: availablePoints <= 0 ? null : onMax,
          style: FilledButton.styleFrom(
            padding: EdgeInsets.symmetric(horizontal: sizes.gapMd),
            textStyle: TextStyle(fontSize: sizes.fontXs),
          ),
          child: const Text('Max'),
        ),
      ),
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
            context.gapHXs,
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
            borderRadius: context.radiusSm,
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
