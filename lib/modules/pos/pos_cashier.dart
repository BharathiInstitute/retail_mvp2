import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth.dart';

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
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Form(
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
      ),
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
  // (surfaceColor no longer needed after removing enhancements panel)
    final user = ref.watch(authStateProvider);
    final isWide = MediaQuery.of(context).size.width >= 1100;
    final summaryCard = _buildShiftSummaryCard(userEmail: user?.email);
    final invoicesCard = _buildRecentInvoicesCard(userEmail: user?.email);

    return Scaffold(
      appBar: AppBar(title: const Text('Cashier')),
      body: Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: isWide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Decreased width of shift summary by reducing flex
                    Expanded(flex: 4, child: summaryCard),
                    const SizedBox(width: 16),
                    Expanded(flex: 7, child: invoicesCard),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    summaryCard,
                    const SizedBox(height: 16),
                    invoicesCard,
                  ],
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
    final query = FirebaseFirestore.instance
        .collection('invoices')
        .where('timestampMs', isGreaterThanOrEqualTo: start.millisecondsSinceEpoch)
        .where('timestampMs', isLessThan: end.millisecondsSinceEpoch);
    _todayCashSub?.cancel();
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
    return Card(
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Shift Summary', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                _openingBalanceCluster(),
                _cashSalesCluster(),
                _closingBalanceCluster(),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                if (!_shiftOpen)
                  FilledButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    onPressed: _openShift,
                    label: const Text('Open Shift'),
                  )
                else OutlinedButton.icon(
                  icon: const Icon(Icons.stop_circle_outlined),
                  onPressed: _closeShift,
                  label: const Text('Close Shift'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Note: Sales figures are placeholders; integrate with invoices collection to compute real-time cash sales.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentInvoicesCard({required String? userEmail}) {
    return Card(
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Recent Invoices', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            // Constrain height and allow vertical scrolling to avoid overflow.
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 520),
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
      ),
    );
  }

  // _metric helper removed after consolidating into cluster widgets.

  Widget _openingBalanceCluster() {
    final theme = Theme.of(context);
    TextStyle? labelStyle = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    TextStyle? valueStyle = theme.textTheme.bodyMedium;
    TextStyle? valueBold = valueStyle?.copyWith(fontWeight: FontWeight.bold);
    return SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Opening balance', style: labelStyle?.copyWith(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Cash', style: labelStyle?.copyWith(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(_currency(_recentInvoicesCashTotal), style: valueStyle),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total', style: labelStyle?.copyWith(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(_currency(_recentInvoicesTotal), style: valueBold),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cashSalesCluster() {
    final theme = Theme.of(context);
    TextStyle? labelStyle = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    TextStyle? valueStyle = theme.textTheme.bodyMedium;
    TextStyle? valueBold = valueStyle?.copyWith(fontWeight: FontWeight.bold);
    return SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Cash Sales', style: labelStyle?.copyWith(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Cash', style: labelStyle?.copyWith(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(_currency(_cashSales), style: valueStyle),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total', style: labelStyle?.copyWith(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(_currency(_openingFloat + _cashSales), style: valueBold),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _closingBalanceCluster() {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final valueStyle = theme.textTheme.bodyMedium;
    final valueBold = valueStyle?.copyWith(fontWeight: FontWeight.bold);
    return SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Closing Balance', style: labelStyle?.copyWith(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Cash', style: labelStyle?.copyWith(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(_currency(_recentInvoicesCashTotal), style: valueStyle),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total', style: labelStyle?.copyWith(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(_currency(_recentInvoicesTotal), style: valueBold),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // _timeFmt removed (no longer showing opened/closed times)
  String _currency(double v) => '₹${v.toStringAsFixed(2)}';
}

class _RecentInvoicesTable extends StatelessWidget {
  final String? currentUserEmail;
  final ValueChanged<double>? onOverallTotal; // legacy single total callback
  final void Function(double cashTotal, double overallTotal)? onTotals; // new combined callback
  const _RecentInvoicesTable({required this.currentUserEmail, this.onOverallTotal, this.onTotals});

  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance
        .collection('invoices')
        .orderBy('timestampMs', descending: true)
        .limit(10);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Text('Error: ${snap.error}', style: TextStyle(color: Theme.of(context).colorScheme.error));
        }
        if (!snap.hasData) {
          return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24.0),
            child: Center(child: Text('No invoices yet')),
          );
        }
        // Aggregate totals per mode
        double totalCash = 0, totalUpiCard = 0, overallTotal = 0;
        final rows = <DataRow>[];
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
          rows.add(DataRow(cells: [
            DataCell(Text('$number')),
            DataCell(Text(dt == null ? '-' : _fmt(dt))),
            DataCell(Text(currentUserEmail ?? '-')), // placeholder; invoice doesn't store cashier yet
            DataCell(Text(cash == 0 ? '' : _amt(cash))),
            DataCell(Text(upiCard == 0 ? '' : _amt(upiCard))),
            DataCell(Text(_amt(total))),
          ]));
        }
        // Totals row
        rows.add(DataRow(cells: [
          const DataCell(Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold))),
          const DataCell(Text('')),
          const DataCell(Text('')),
          DataCell(Text(_amt(totalCash), style: const TextStyle(fontWeight: FontWeight.bold))),
          DataCell(Text(_amt(totalUpiCard), style: const TextStyle(fontWeight: FontWeight.bold))),
          DataCell(Text(_amt(overallTotal), style: const TextStyle(fontWeight: FontWeight.bold))),
        ]));

        // Notify parent of overall total (sum of last 10 invoices) for closing balance display.
        if (onOverallTotal != null || onTotals != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (onOverallTotal != null) onOverallTotal!(overallTotal);
            if (onTotals != null) onTotals!(totalCash, overallTotal);
          });
        }

        final headerStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: .2,
            );
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 35,
            headingRowHeight: 40,
            columns: [
              DataColumn(label: Text('Invoice #', style: headerStyle)),
              DataColumn(label: Text('Date & Time', style: headerStyle)),
              DataColumn(label: Text('Cashier', style: headerStyle)),
              DataColumn(label: Text('Cash', style: headerStyle)),
              DataColumn(label: Text('UPI/Card', style: headerStyle)),
              DataColumn(label: Text('Total', style: headerStyle)),
            ],
            rows: rows,
          ),
        );
      },
    );
  }

  static String _fmt(DateTime dt) {
    final d = dt;
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
  static String _amt(double v) => '₹${v.toStringAsFixed(2)}';
}


