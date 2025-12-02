import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retail_mvp2/core/firestore_store_collections.dart';
import 'package:retail_mvp2/modules/stores/providers.dart';
import '../../core/auth/auth_repository_and_provider.dart';
import '../../core/theme/theme_extension_helpers.dart';

/// Cashier screen with a primary card panel for shift summary and cash drawer actions.
class PosCashierScreen extends ConsumerStatefulWidget {
  const PosCashierScreen({super.key});

  @override
  ConsumerState<PosCashierScreen> createState() => _PosCashierScreenState();
}

class _PosCashierScreenState extends ConsumerState<PosCashierScreen> {
  bool _shiftOpen = false;
  double _openingFloat = 0;
  double _cashSales = 0; // Sum of today's invoices paid in cash (live)
  // Cash In removed from summary
  double _recentInvoicesTotal = 0; // Sum of totals from recent invoices (last 10)
  double _recentInvoicesCashTotal = 0; // Sum of cash-only totals from recent invoices
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _todayCashSub;
 
  Future<void> _promptAmount({required String title, required void Function(double) onSubmit}) async {
    final ctrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final val = await showDialog<double>(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        final texts = Theme.of(ctx).textTheme;
        return AlertDialog(
        title: Text(
          title,
          style: texts.titleMedium?.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w700),
        ),
        content: DefaultTextStyle(
          style: texts.bodyMedium?.copyWith(color: scheme.onSurface) ?? const TextStyle(),
          child: Form(
          key: formKey,
          child: TextFormField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Required';
              final d = double.tryParse(v.trim());
              if (d == null || d < 0) return 'Invalid';
              return null;
            },
          ),
  ),
  ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              final d = double.parse(ctrl.text.trim());
              Navigator.pop(ctx, d);
            },
            child: const Text('Save'),
          ),
        ],
      );
      },
    );
    if (val != null) {
      onSubmit(val);
    }
  }

  void _openShift() async {
    if (_shiftOpen) return;
    await _promptAmount(title: 'Opening balance', onSubmit: (amt) {
      setState(() {
  _openingFloat = amt;
        _cashSales = 0; // will refresh from listener shortly
  // opened/closed timestamps removed from simplified summary
        _shiftOpen = true;
      });
    });
  }

  void _closeShift() {
    if (!_shiftOpen) return;
    setState(() {
  // closed timestamp removed
      _shiftOpen = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Shift closed')));
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider);
    final cs = Theme.of(context).colorScheme;
    final summaryCard = _buildShiftSummaryCard(userEmail: user?.email);
    final invoicesCard = _buildRecentInvoicesCard(userEmail: user?.email);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [cs.surface, cs.primaryContainer.withOpacity(0.05)],
          ),
        ),
        child: Scrollbar(
          thumbVisibility: true,
          child: SingleChildScrollView(
            padding: context.padLg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(context.sizes.gapSm),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [cs.primary, cs.primary.withOpacity(0.7)]),
                        borderRadius: context.radiusSm,
                      ),
                      child: Icon(Icons.point_of_sale_rounded, size: context.sizes.iconMd, color: cs.onPrimary),
                    ),
                    SizedBox(width: context.sizes.gapSm),
                    Text('Cashier', style: context.heading2),
                  ],
                ),
                context.gapVMd,
                // Shift Summary (compact, above table)
                summaryCard,
                context.gapVMd,
                // Recent Invoices
                invoicesCard,
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _subscribeTodayCashSales();
  }

  void _subscribeTodayCashSales() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    final sel = ref.read(selectedStoreIdProvider);
    _todayCashSub?.cancel();
    if (sel == null) {
      setState(() => _cashSales = 0);
      return;
    }
    final query = StoreRefs.of(sel)
        .invoices()
        .where('timestampMs', isGreaterThanOrEqualTo: start.millisecondsSinceEpoch)
        .where('timestampMs', isLessThan: end.millisecondsSinceEpoch);
    _todayCashSub = query.snapshots().listen((snap) {
      double total = 0;
      for (final d in snap.docs) {
        final data = d.data();
        final mode = (data['paymentMode'] ?? '').toString().toLowerCase();
        if (mode.contains('cash')) {
          final val = (data['grandTotal'] is num) ? (data['grandTotal'] as num).toDouble() : 0.0;
          total += val;
        }
      }
      if (mounted) {
        setState(() => _cashSales = total);
      }
    });
  }

  @override
  void dispose() {
    _todayCashSub?.cancel();
    super.dispose();
  }

  Widget _buildShiftSummaryCard({required String? userEmail}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: context.radiusMd,
        border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(color: cs.shadow.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          // Balance Cards
          Expanded(
            child: Row(
              children: [
                _compactBalanceChip('Opening', _recentInvoicesCashTotal, _recentInvoicesTotal, Icons.account_balance_wallet_rounded, context.appColors.info),
                context.gapHSm,
                _compactBalanceChip('Sales', _cashSales, _openingFloat + _cashSales, Icons.trending_up_rounded, context.appColors.success),
                context.gapHSm,
                _compactBalanceChip('Closing', _recentInvoicesCashTotal, _recentInvoicesTotal, Icons.savings_rounded, context.appColors.warning),
              ],
            ),
          ),
          context.gapHMd,
          // Action Button
          if (!_shiftOpen)
            FilledButton.icon(
              icon: const Icon(Icons.play_arrow_rounded, size: 16),
              onPressed: _openShift,
              label: Text('Open Shift', style: context.bodySm),
              style: FilledButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: context.sizes.gapMd, vertical: context.sizes.gapSm),
                shape: RoundedRectangleBorder(borderRadius: context.radiusSm),
              ),
            )
          else
            OutlinedButton.icon(
              icon: Icon(Icons.stop_circle_rounded, size: 16, color: cs.error),
              onPressed: _closeShift,
              label: Text('Close', style: context.bodySm.copyWith(color: cs.error)),
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: context.sizes.gapMd, vertical: context.sizes.gapSm),
                shape: RoundedRectangleBorder(borderRadius: context.radiusSm),
                side: BorderSide(color: cs.error.withOpacity(0.5)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _compactBalanceChip(String title, double cash, double total, IconData icon, Color color) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: context.radiusSm,
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, size: 12, color: color),
                context.gapHXs,
                Text(title, style: TextStyle(fontSize: context.sizes.fontXs, fontWeight: FontWeight.w600, color: color)),
              ],
            ),
            context.gapVXs,
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Cash', style: TextStyle(fontSize: context.sizes.fontXs - 1, color: cs.onSurfaceVariant)),
                      Text(_currency(cash), style: TextStyle(fontSize: context.sizes.fontXs, fontWeight: FontWeight.w600, color: cs.onSurface)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Total', style: TextStyle(fontSize: context.sizes.fontXs - 1, color: cs.onSurfaceVariant)),
                      Text(_currency(total), style: TextStyle(fontSize: context.sizes.fontXs, fontWeight: FontWeight.w700, color: color)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentInvoicesCard({required String? userEmail}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: context.radiusMd,
        border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(color: cs.shadow.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: cs.secondaryContainer.withOpacity(0.5),
                    borderRadius: context.radiusSm,
                  ),
                  child: Icon(Icons.receipt_rounded, size: 18, color: cs.secondary),
                ),
                SizedBox(width: context.sizes.gapSm),
                Text('Recent Invoices', style: context.heading3),
              ],
            ),
          ),
          // Table with constrained height
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: Scrollbar(
              thumbVisibility: true,
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SizedBox(
                  width: double.infinity,
                  child: _RecentInvoicesTable(
                    currentUserEmail: userEmail,
                    onOverallTotal: (v) {
                      if (mounted && _recentInvoicesTotal != v) {
                        setState(() => _recentInvoicesTotal = v);
                      }
                    },
                    onTotals: (cash, overall) {
                      if (!mounted) return;
                      bool changed = false;
                      if (_recentInvoicesCashTotal != cash) { _recentInvoicesCashTotal = cash; changed = true; }
                      if (_recentInvoicesTotal != overall) { _recentInvoicesTotal = overall; changed = true; }
                      if (changed) setState(() {});
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // _metric helper removed after consolidating into cluster widgets.

  // _timeFmt removed (no longer showing opened/closed times)
  String _currency(double v) => '₹${v.toStringAsFixed(2)}';
}

class _RecentInvoicesTable extends StatelessWidget {
  final String? currentUserEmail;
  final ValueChanged<double>? onOverallTotal;
  final void Function(double cashTotal, double overallTotal)? onTotals;
  const _RecentInvoicesTable({required this.currentUserEmail, this.onOverallTotal, this.onTotals});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sizes = context.sizes;
    final sel = ProviderScope.containerOf(context).read(selectedStoreIdProvider);
    if (sel == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24.0),
        child: Center(child: Text('Select a store to view recent invoices', style: context.subtleSm)),
      );
    }
    final query = StoreRefs.of(sel).invoices().orderBy('timestampMs', descending: true).limit(10);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Text('Error: ${snap.error}', style: context.errorSm);
        }
        if (!snap.hasData) {
          return const SizedBox(height: 100, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24.0),
            child: Center(child: Text('No invoices yet', style: context.subtleSm)),
          );
        }
        
        double totalCash = 0, totalUpiCard = 0, overallTotal = 0;
        final items = <Map<String, dynamic>>[];
        
        for (final d in docs) {
          final data = d.data();
          final number = data['invoiceNumber'] ?? d.id;
          final tsMs = (data['timestampMs'] is int) ? data['timestampMs'] as int : null;
          DateTime? dt; if (tsMs != null) { dt = DateTime.fromMillisecondsSinceEpoch(tsMs); }
          final mode = (data['paymentMode'] ?? '').toString().toLowerCase();
          final total = (data['grandTotal'] is num) ? (data['grandTotal'] as num).toDouble() : 0.0;
          overallTotal += total;
          double cash = 0, upiCard = 0;
          if (mode.contains('cash')) { cash = total; totalCash += total; }
          else if (mode.contains('upi') || mode.contains('card') || mode.contains('credit')) { upiCard = total; totalUpiCard += total; }
          items.add({
            'number': number,
            'dt': dt,
            'cashier': currentUserEmail,
            'cash': cash,
            'upi': upiCard,
            'total': total,
          });
        }

        if (onOverallTotal != null || onTotals != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (onOverallTotal != null) onOverallTotal!(overallTotal);
            if (onTotals != null) onTotals!(totalCash, overallTotal);
          });
        }

        return Column(
          children: [
            // Header Row
            Container(
              padding: EdgeInsets.symmetric(horizontal: sizes.gapMd, vertical: sizes.gapSm),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(0.5),
              ),
              child: Row(
                children: [
                  SizedBox(width: 80, child: Text('Invoice #', style: TextStyle(fontSize: sizes.fontSm, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant))),
                  SizedBox(width: 90, child: Text('Date & Time', style: TextStyle(fontSize: sizes.fontSm, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant))),
                  Expanded(child: Text('Cashier', style: TextStyle(fontSize: sizes.fontSm, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant))),
                  SizedBox(width: 70, child: Text('Cash', style: TextStyle(fontSize: sizes.fontSm, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant), textAlign: TextAlign.right)),
                  SizedBox(width: 70, child: Text('UPI/Card', style: TextStyle(fontSize: sizes.fontSm, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant), textAlign: TextAlign.right)),
                  SizedBox(width: 70, child: Text('Total', style: TextStyle(fontSize: sizes.fontSm, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant), textAlign: TextAlign.right)),
                ],
              ),
            ),
            // Data Rows
            ...items.map((it) => Container(
              padding: EdgeInsets.symmetric(horizontal: sizes.gapMd, vertical: sizes.gapSm),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.3))),
              ),
              child: Row(
                children: [
                  SizedBox(width: 80, child: Text('${it['number']}', style: TextStyle(fontSize: sizes.fontSm, fontWeight: FontWeight.w500, color: cs.primary))),
                  SizedBox(width: 90, child: Text(it['dt'] == null ? '-' : _fmt(it['dt'] as DateTime), style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurfaceVariant))),
                  Expanded(child: Text('${it['cashier'] ?? '-'}', style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurface), overflow: TextOverflow.ellipsis)),
                  SizedBox(width: 70, child: Text((it['cash'] as double) == 0 ? '' : _amt(it['cash'] as double), style: TextStyle(fontSize: sizes.fontSm, color: cs.onSurface), textAlign: TextAlign.right)),
                  SizedBox(width: 70, child: Text((it['upi'] as double) == 0 ? '' : _amt(it['upi'] as double), style: TextStyle(fontSize: sizes.fontSm, color: cs.onSurface), textAlign: TextAlign.right)),
                  SizedBox(width: 70, child: Text(_amt(it['total'] as double), style: TextStyle(fontSize: sizes.fontSm, fontWeight: FontWeight.w600, color: cs.onSurface), textAlign: TextAlign.right)),
                ],
              ),
            )),
            // Total Row
            Container(
              padding: EdgeInsets.symmetric(horizontal: sizes.gapMd, vertical: sizes.gapSm + 2),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [cs.primaryContainer.withOpacity(0.3), cs.primaryContainer.withOpacity(0.1)],
                ),
                borderRadius: BorderRadius.only(bottomLeft: Radius.circular(sizes.radiusMd), bottomRight: Radius.circular(sizes.radiusMd)),
              ),
              child: Row(
                children: [
                  SizedBox(width: 80, child: Text('TOTAL', style: TextStyle(fontSize: sizes.fontSm, fontWeight: FontWeight.w700, color: cs.onSurface))),
                  const SizedBox(width: 90),
                  const Expanded(child: SizedBox()),
                  SizedBox(width: 70, child: Text(_amt(totalCash), style: TextStyle(fontSize: sizes.fontSm, fontWeight: FontWeight.w700, color: cs.primary), textAlign: TextAlign.right)),
                  SizedBox(width: 70, child: Text(_amt(totalUpiCard), style: TextStyle(fontSize: sizes.fontSm, fontWeight: FontWeight.w700, color: cs.primary), textAlign: TextAlign.right)),
                  SizedBox(width: 70, child: Text(_amt(overallTotal), style: TextStyle(fontSize: sizes.fontSm, fontWeight: FontWeight.w700, color: cs.primary), textAlign: TextAlign.right)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  static String _fmt(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
  static String _amt(double v) => '₹${v.toStringAsFixed(2)}';
}


