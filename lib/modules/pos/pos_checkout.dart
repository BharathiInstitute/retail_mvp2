import 'dart:async';
import 'package:flutter/material.dart';
import 'pos.dart';
// Removed printer setup button from this panel; printer setup now appears in checkout popup dialog.

// Clean rebuilt checkout panel with inline printer configuration button.
class CheckoutPanel extends StatelessWidget {
  final Stream<List<Customer>> customersStream;
  final List<Customer> initialCustomers;
  final Customer? selectedCustomer;
  final Customer walkIn;
  final ValueChanged<Customer?> onCustomerSelected;
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
  final VoidCallback? onQuickPrint; // direct print
  final PaymentMode selectedPaymentMode;
  final ValueChanged<PaymentMode> onPaymentModeChanged;

  const CheckoutPanel({
    super.key,
    required this.customersStream,
    required this.initialCustomers,
    required this.selectedCustomer,
    required this.walkIn,
    required this.onCustomerSelected,
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
  this.onQuickPrint,
    required this.selectedPaymentMode,
    required this.onPaymentModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final taxesByRate = <int, double>{};
    for (final it in cart.values) {
      final tax = lineTaxes[it.product.sku] ?? 0.0;
      taxesByRate.update(it.product.taxPercent, (v) => v + tax, ifAbsent: () => tax);
    }
    return Card(
      child: Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(10.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CustomerDropdown(
                customersStream: customersStream,
                initialCustomers: initialCustomers,
                selected: selectedCustomer,
                onSelected: onCustomerSelected,
                walkIn: walkIn,
              ),
              const SizedBox(height: 6),
              _CustomerInfo(selected: selectedCustomer),
              const SizedBox(height: 8),
              _kv('Subtotal', subtotal),
              _kv('Discount', -discountValue),
              if (redeemValue > 0) _kv('Redeemed (Pts)', -redeemValue),
              const SizedBox(height: 6),
              const Text('GST Breakdown'),
              ...taxesByRate.entries.map((e) => _kv('GST ${e.key}%', e.value)),
              const Divider(),
              _kv('Grand Total', grandTotal),
              if (redeemValue > 0) _kv('Redeem Applied', -redeemValue),
              _kv('Payable', payableTotal, bold: true),
              const SizedBox(height: 10),
              _RedeemSection(
                controller: redeemPointsController,
                availablePoints: getAvailablePoints(),
                redeemValue: redeemValue,
                onChange: onRedeemChanged,
                onMax: onRedeemMax,
                redeemedPoints: getRedeemedPoints(),
              ),
              Row(children: [
                Expanded(child: _payModeButton(context, PaymentMode.cash, 'Cash', Icons.payments)),
                const SizedBox(width: 8),
                Expanded(child: _payModeButton(context, PaymentMode.upi, 'UPI', Icons.qr_code)),
                const SizedBox(width: 8),
                Expanded(child: _payModeButton(context, PaymentMode.card, 'Card', Icons.credit_card)),
              ]),
              const SizedBox(height: 10),
              Row(
                children: [
                  InkWell(
                    onTap: onQuickPrint,
                    borderRadius: BorderRadius.circular(24),
                    child: const Padding(
                      padding: EdgeInsets.all(6.0),
                      child: Icon(Icons.print),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: onCheckout,
                      icon: const Icon(Icons.check_circle),
                      label: const Text('Checkout'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _payModeButton(BuildContext context, PaymentMode mode, String label, IconData icon) {
    final selected = selectedPaymentMode == mode;
    return OutlinedButton.icon(
      onPressed: () => onPaymentModeChanged(mode),
      icon: Icon(icon, color: selected ? Theme.of(context).colorScheme.primary : null),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08) : null,
        side: BorderSide(color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).dividerColor),
      ),
    );
  }

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

class _CustomerInfo extends StatelessWidget {
  final Customer? selected;
  const _CustomerInfo({required this.selected});
  String _fmtPts(double v) {
    final s = v.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }
  @override
  Widget build(BuildContext context) {
    final c = selected;
    if (c == null || c.id.isEmpty) return const SizedBox();
    String planLabel = (c.status ?? 'standard');
    planLabel = planLabel[0].toUpperCase() + planLabel.substring(1);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold)),
          if (c.email != null && c.email!.isNotEmpty)
            Text(c.email!, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 4),
          Wrap(spacing: 12, runSpacing: 4, children: [
            _miniInfoChip(context, Icons.workspace_premium, 'Plan: $planLabel'),
            _miniInfoChip(context, Icons.percent, 'Discount: ${c.discountPercent.toStringAsFixed(0)}%'),
            _miniInfoChip(context, Icons.card_giftcard, 'Rewards: ${_fmtPts(c.rewardsPoints)}'),
            _miniInfoChip(context, Icons.account_balance_wallet, 'Spend: ₹${c.totalSpend.toStringAsFixed(0)}'),
          ]),
        ],
      ),
    );
  }

  Widget _miniInfoChip(BuildContext context, IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}

class _RedeemSection extends StatelessWidget {
  final TextEditingController controller;
  final double availablePoints;
  final double redeemedPoints;
  final double redeemValue;
  final VoidCallback onChange;
  final VoidCallback onMax;
  const _RedeemSection({
    required this.controller,
    required this.availablePoints,
    required this.redeemValue,
    required this.onChange,
    required this.onMax,
    required this.redeemedPoints,
  });
  @override
  Widget build(BuildContext context) {
    final entered = redeemedPoints;
    final over = entered > availablePoints;
    final negative = entered < 0;
    String? errorText;
    if (negative) {
      errorText = 'Cannot be negative';
    } else if (over) {
      errorText = 'Not enough points (Avail: ${availablePoints.toStringAsFixed(0)})';
    }
    final helper = (!over && !negative && redeemValue > 0)
        ? 'Value: ₹${redeemValue.toStringAsFixed(2)}'
        : (!over && !negative ? 'Enter points to redeem' : null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
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
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      )
                    : null,
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => onChange(),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: availablePoints <= 0 ? null : onMax,
            child: const Text('Max'),
          ),
        ]),
      ],
    );
  }
}


class _CustomerDropdown extends StatefulWidget {
  final Stream<List<Customer>> customersStream;
  final List<Customer> initialCustomers;
  final Customer? selected;
  final ValueChanged<Customer?> onSelected;
  final Customer walkIn;
  const _CustomerDropdown({
    required this.customersStream,
    required this.initialCustomers,
    required this.selected,
    required this.onSelected,
    required this.walkIn,
  });

  @override
  State<_CustomerDropdown> createState() => _CustomerDropdownState();
}

class _CustomerDropdownState extends State<_CustomerDropdown> {
  late List<Customer> _all;
  bool _expanded = false;
  final TextEditingController _searchCtrl = TextEditingController();
  StreamSubscription<List<Customer>>? _sub;

  @override
  void initState() {
    super.initState();
    _all = [widget.walkIn, ...widget.initialCustomers];
    _sub = widget.customersStream.listen((list) {
      setState(() {
        // Ensure walk-in at top (id empty or special) and remove duplicates by id
        final byId = <String, Customer>{ for (final c in list) c.id : c };
        _all = [widget.walkIn, ...byId.values.where((c) => c.id != widget.walkIn.id)];
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Customer> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _all;
    return _all.where((c) {
      bool m(String? v) => v != null && v.toLowerCase().contains(q);
      return m(c.name) || m(c.email) || m(c.phone);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final sel = widget.selected ?? widget.walkIn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Customer',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            child: Row(
              children: [
                const Icon(Icons.person, size: 18),
                const SizedBox(width: 6),
                Expanded(child: Text(sel.name, overflow: TextOverflow.ellipsis)),
                Icon(_expanded ? Icons.expand_less : Icons.expand_more),
              ],
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _expanded
              ? Container(
                  key: const ValueKey('dd'),
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(6),
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                        child: TextField(
                          controller: _searchCtrl,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            hintText: 'Search name / email / phone',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const Divider(height: 1),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 260),
                        child: _filtered.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Text('No customers'),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                itemCount: _filtered.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (_, i) {
                                  final c = _filtered[i];
                                  final isSel = c.id == sel.id;
                                  return ListTile(
                                    dense: true,
                                    leading: isSel
                                        ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary)
                                        : const Icon(Icons.person_outline),
                                    title: Text(c.name),
                                    subtitle: (c.email != null && c.email!.isNotEmpty)
                                        ? Text(c.email!, style: const TextStyle(fontSize: 11))
                                        : null,
                                    onTap: () {
                                      widget.onSelected(c.id.isEmpty ? null : c);
                                      setState(() {
                                        _expanded = false;
                                        _searchCtrl.clear();
                                      });
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
