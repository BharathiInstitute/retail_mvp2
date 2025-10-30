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
  // Keep a stable content width on wide screens so expanding/collapsing the side menu
  // doesn't change the layout. If the viewport is smaller than this, we gracefully
  // shrink and eventually switch to the stacked mobile layout.
  static const double _contentMaxWidth = 1280;
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
  // (surfaceColor no longer needed after removing enhancements panel)
    final user = ref.watch(authStateProvider);
    final isWide = MediaQuery.of(context).size.width >= 1100;
    final summaryCard = _buildShiftSummaryCard(userEmail: user?.email);
    final invoicesCard = _buildRecentInvoicesCard(userEmail: user?.email);

    return Scaffold(
      // Remove the local app bar on narrow/mobile to avoid duplicate titles and extra gap
      appBar: isWide ? AppBar(title: const Text('Cashier')) : null,
      body: Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          // Tighter padding on mobile; no top padding to hug the global app bar
          padding: isWide ? const EdgeInsets.all(16) : const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: isWide
              ? Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        const double summaryW = 420;
                        const double gap = 16;
                        // Cap the Recent Invoices card width so the card is visually narrower
                        // and doesn't stretch too wide on large screens. Horizontal scrolling
                        // inside the table will handle overflow when the card is narrower than
                        // the table's min width.
                        final double rightW = (constraints.maxWidth - summaryW - gap).clamp(560, 820);
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(width: summaryW, child: summaryCard),
                            const SizedBox(width: gap),
                            SizedBox(width: rightW, child: invoicesCard),
                          ],
                        );
                      },
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    summaryCard,
                    const SizedBox(height: 4),
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
    final isWide = MediaQuery.of(context).size.width >= 1100;
    return Card(
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      margin: isWide ? null : EdgeInsets.zero,
      child: Padding(
        padding: isWide ? const EdgeInsets.all(16) : EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Shift Summary',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
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
            const SizedBox(height: 8),
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
    final isWide = MediaQuery.of(context).size.width >= 1100;
    return Card(
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      margin: isWide ? null : EdgeInsets.zero,
      child: Padding(
        padding: isWide ? const EdgeInsets.all(16) : EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recent Invoices',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
            ),
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
  TextStyle? valueStyle = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface);
  TextStyle? valueBold = valueStyle?.copyWith(fontWeight: FontWeight.bold);
    return SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Opening balance', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Cash', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: theme.colorScheme.onSurfaceVariant)),
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
                    Text('Total', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: theme.colorScheme.onSurfaceVariant)),
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
  TextStyle? valueStyle = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface);
  TextStyle? valueBold = valueStyle?.copyWith(fontWeight: FontWeight.bold);
    return SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Cash Sales', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Cash', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: theme.colorScheme.onSurfaceVariant)),
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
                    Text('Total', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: theme.colorScheme.onSurfaceVariant)),
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
  final valueStyle = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface);
  final valueBold = valueStyle?.copyWith(fontWeight: FontWeight.bold);
    return SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Closing Balance', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Cash', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: theme.colorScheme.onSurfaceVariant)),
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
                    Text('Total', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: theme.colorScheme.onSurfaceVariant)),
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
          return Text(
            'Error: ${snap.error}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.error),
          );
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
        final items = <Map<String, dynamic>>[]; // for mobile rendering
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
          rows.add(DataRow(cells: [
            DataCell(Text('$number')),
            DataCell(Text(dt == null ? '-' : _fmt(dt))),
            DataCell(SizedBox(
              width: 88,
              child: Text(
                currentUserEmail ?? '-',
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
            )), // placeholder; invoice doesn't store cashier yet
            DataCell(SizedBox(
              width: 84,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(cash == 0 ? '' : _amt(cash)),
              ),
            )),
            DataCell(SizedBox(
              width: 80,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(upiCard == 0 ? '' : _amt(upiCard)),
              ),
            )),
            DataCell(SizedBox(
              width: 84,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(_amt(total)),
              ),
            )),
          ]));
        }
        // Totals row
        final bold = Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold);
        rows.add(DataRow(cells: [
          DataCell(Text('TOTAL', style: bold)),
          const DataCell(Text('')),
          const DataCell(Text('')),
          DataCell(SizedBox(width: 84, child: Align(alignment: Alignment.centerLeft, child: Text(_amt(totalCash), style: bold)))),
          DataCell(SizedBox(width: 80, child: Align(alignment: Alignment.centerLeft, child: Text(_amt(totalUpiCard), style: bold)))),
          DataCell(SizedBox(width: 84, child: Align(alignment: Alignment.centerLeft, child: Text(_amt(overallTotal), style: bold)))),
        ]));

        // Notify parent of overall total (sum of last 10 invoices) for closing balance display.
        if (onOverallTotal != null || onTotals != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (onOverallTotal != null) onOverallTotal!(overallTotal);
            if (onTotals != null) onTotals!(totalCash, overallTotal);
          });
        }

        final headerStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: .2,
              color: Theme.of(context).colorScheme.onSurface,
            );
        final dataStyle = Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface);

        // Mobile-friendly rendering: compact list instead of wide table
        final isNarrow = MediaQuery.of(context).size.width < 600;
        if (isNarrow) {
          final textTheme = Theme.of(context).textTheme;
          final subtle = Theme.of(context).colorScheme.onSurfaceVariant;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...items.map((it) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left block: invoice, date, cashier
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${it['number']}', style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(it['dt'] == null ? '-' : _fmt(it['dt'] as DateTime), style: textTheme.bodySmall?.copyWith(color: subtle)),
                                const SizedBox(height: 4),
                                Text('${it['cashier'] ?? '-'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.bodySmall),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Right block: amounts stacked
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('Cash  ${_amt((it['cash'] as double))}', style: textTheme.bodySmall),
                              Text('UPI   ${_amt((it["upi"] as double))}', style: textTheme.bodySmall),
                              Text('Total ${_amt((it['total'] as double))}', style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                  ],
                );
              }),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: Text('TOTAL', style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold))),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Cash  ${_amt(totalCash)}', style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
                      Text('UPI   ${_amt(totalUpiCard)}', style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
                      Text('Total ${_amt(overallTotal)}', style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ],
          );
        }
        return DataTableTheme(
          data: DataTableThemeData(
            headingTextStyle: headerStyle,
            dataTextStyle: dataStyle,
          ),
          child: Scrollbar(
            thumbVisibility: true,
            notificationPredicate: (notif) => notif.metrics.axis == Axis.horizontal,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Padding(
                // Add right padding so the vertical scrollbar overlay doesn't cause a tiny overflow
                padding: const EdgeInsets.only(right: 4),
                child: ConstrainedBox(
                  // Force a minimum table width so columns don't get squeezed and overflow.
                  // Horizontal scroll will engage when view is narrower than this.
                    constraints: const BoxConstraints(minWidth: 640),
                  child: DataTable(
                    columnSpacing: 0,
                    horizontalMargin: 0,
                    headingRowHeight: 34,
                    dataRowMinHeight: 36,
                    dataRowMaxHeight: 48,
                    columns: [
                      DataColumn(label: Text('Invoice #', style: headerStyle)),
                      DataColumn(label: Text('Date & Time', style: headerStyle)),
                      DataColumn(
                        label: SizedBox(
                          width: 88,
                          child: Text('Cashier', style: headerStyle, overflow: TextOverflow.ellipsis, softWrap: false),
                        ),
                      ),
                      DataColumn(
                        label: SizedBox(
                          width: 84,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text('Cash'),
                          ),
                        ),
                      ),
                      DataColumn(
                        label: SizedBox(
                          width: 80,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text('UPI/Card', overflow: TextOverflow.ellipsis, softWrap: false),
                          ),
                        ),
                      ),
                      DataColumn(
                        label: SizedBox(
                          width: 84,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text('Total'),
                          ),
                        ),
                      ),
                    ],
                    rows: rows,
                  ),
                ),
              ),
            ),
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


