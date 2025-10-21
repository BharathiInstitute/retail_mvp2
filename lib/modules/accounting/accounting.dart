import 'package:flutter/material.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/theme/theme_utils.dart';
// Removed import 'gstr3b_service.dart'; file deleted. Replacing GST summary logic with placeholders.

// Consolidated Accounting module in a single file.
// This merges prior UI screens and keeps placeholders for models/services.

// ===== Accounting Module (main screen) =====
class AccountingModuleScreen extends StatefulWidget {
  const AccountingModuleScreen({super.key});
  @override
  State<AccountingModuleScreen> createState() => _AccountingModuleScreenState();
}

class _AccountingModuleScreenState extends State<AccountingModuleScreen> {

// Static GST rows removed; replaced with dynamic computation card.

	double revenue = 480000;
	double expenses = 325000;

	final _TaxSummary taxSummary = const _TaxSummary(gstPayable: 68000, itc: 42000);

late final Stream<List<_LedgerEntry>> _ledgerStream;
Stream<double>? _stockValueStream; // nullable to avoid LateInitializationError on hot reload

	@override
	void initState() {
		super.initState();
		_ledgerStream = _buildLedgerStream().asBroadcastStream();
		_stockValueStream = _buildStockValueStream().asBroadcastStream();
	}

	Stream<List<_LedgerEntry>> _salesStream() {
		final col = FirebaseFirestore.instance.collection('invoices').orderBy('timestampMs', descending: false);
		return col.snapshots().map((snap) => snap.docs.map((d) {
			final data = d.data();
			final tsMs = (data['timestampMs'] is int) ? data['timestampMs'] as int : DateTime.now().millisecondsSinceEpoch;
			final dt = DateTime.fromMillisecondsSinceEpoch(tsMs);
			final total = () {
				final lines = (data['lines'] as List?)?.whereType<Map>().toList() ?? const <Map>[];
				double sum = 0;
				for (final l in lines) {
					final unit = (l['unitPrice'] is num) ? (l['unitPrice'] as num).toDouble() : double.tryParse('${l['unitPrice']}') ?? 0;
					final qty = (l['qty'] is num) ? (l['qty'] as num).toDouble() : double.tryParse('${l['qty']}') ?? 1;
					final taxPct = (l['taxPercent'] is num) ? (l['taxPercent'] as num).toDouble() : double.tryParse('${l['taxPercent']}') ?? 0;
					final base = unit / (1 + taxPct / 100);
					final tax = base * taxPct / 100;
					sum += (base + tax) * qty;
				}
				return sum;
			}();
			return _LedgerEntry(
				date: dt,
				desc: 'Sale #${data['invoiceNumber'] ?? data['invoiceNo'] ?? ''}'.trim(),
				inAmt: total,
				outAmt: 0,
				paymentMethod: (data['paymentMode'] ?? 'Unknown').toString(),
			);
		}).toList());
	}

	Stream<List<_LedgerEntry>> _purchaseStream() {
		final col = FirebaseFirestore.instance.collection('purchase_invoices').orderBy('timestampMs', descending: false);
		return col.snapshots().map((snap) => snap.docs.map((d) {
			final data = d.data();
			final tsMs = (data['timestampMs'] is int) ? data['timestampMs'] as int : DateTime.now().millisecondsSinceEpoch;
			final dt = DateTime.fromMillisecondsSinceEpoch(tsMs);
			final summary = (data['summary'] as Map?) ?? const {};
			final grand = () {
				final g = summary['grandTotal'];
				if (g is num) return g.toDouble();
				return double.tryParse(g?.toString() ?? '0') ?? 0;
			}();
			return _LedgerEntry(
				date: dt,
				desc: 'Purchase ${data['invoiceNo'] ?? ''}'.trim(),
				inAmt: 0,
				outAmt: grand,
				paymentMethod: (data['paymentMode'] ?? (data['payment']?['mode'] ?? 'Unknown')).toString(),
			);
		}).toList());
	}

	Stream<List<_LedgerEntry>> _buildLedgerStream() {
		// Replace rxdart combineLatest with manual merge using StreamZip-like behavior.
		final sales$ = _salesStream();
		final purchases$ = _purchaseStream();
		List<_LedgerEntry>? latestSales;
		List<_LedgerEntry>? latestPurchases;
		StreamController<List<_LedgerEntry>>? controller;
		controller = StreamController<List<_LedgerEntry>>(onListen: () {
			final sub1 = sales$.listen((s) {
				latestSales = s;
				if (latestPurchases != null) {
					final all = [...latestSales!, ...latestPurchases!];
					all.sort((a,b)=>a.date.compareTo(b.date));
					controller!.add(all);
				}
			});
			final sub2 = purchases$.listen((p) {
				latestPurchases = p;
				if (latestSales != null) {
					final all = [...latestSales!, ...latestPurchases!];
					all.sort((a,b)=>a.date.compareTo(b.date));
					controller!.add(all);
				}
			});
			controller!.onCancel = () { sub1.cancel(); sub2.cancel(); };
		});
		return controller.stream.asBroadcastStream();
	}

	Stream<double> _buildStockValueStream() {
		final col = FirebaseFirestore.instance.collection('inventory');
		return col.snapshots().map((snap) {
			double total = 0;
			for (final d in snap.docs) {
				final data = d.data();
				double unitPrice = 0;
				final up = data['unitPrice'];
				if (up is num) {
				  unitPrice = up.toDouble();
				} else if (up != null) {
				  unitPrice = double.tryParse(up.toString()) ?? 0;
				}
				final batches = (data['batches'] as List?)?.whereType<Map>().toList() ?? const <Map>[];
				int qty = 0;
				for (final b in batches) {
					final q = b['qty'];
					if (q is int) {
					  qty += q;
					} else if (q is num) {
					  qty += q.toInt();
					} else if (q != null) {
					  qty += int.tryParse(q.toString()) ?? 0;
					}
				}
				total += unitPrice * qty;
			}
			return total;
		});
	}
	@override
	void dispose() { super.dispose(); }

	@override
	Widget build(BuildContext context) {
		final isWide = MediaQuery.of(context).size.width >= 1000;
		final netProfit = revenue - expenses;

		final salesCard = _TotalSummaryCard(ledgerStream: _ledgerStream, stockValueStream: _stockValueStream);
		final gstrCard = _DynamicGstReportsCard();
		final pnlCard = _PnLCard(revenue: revenue, expenses: expenses, netProfit: netProfit);
		final taxCard = _TaxSummaryCard(summary: taxSummary);
		final exportCard = const _ExportCard();
		final cashBookCard = _CashBookCard(stream: _ledgerStream);

		if (isWide) {
			return Padding(
				padding: const EdgeInsets.all(16),
				child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
					Expanded(
						flex: 2,
						child: ListView(children: [
							salesCard, const SizedBox(height: 12), gstrCard, const SizedBox(height: 12),
							pnlCard, const SizedBox(height: 12), taxCard, const SizedBox(height: 12), exportCard,
						]),
					),
					const SizedBox(width: 16),
					Expanded(
						flex: 3,
						child: ListView(children: [
							cashBookCard,
						]),
					),
				]),
			);
		}

		return ListView(padding: const EdgeInsets.all(16), children: [
			salesCard, const SizedBox(height: 12), gstrCard, const SizedBox(height: 12), pnlCard, const SizedBox(height: 12),
			taxCard, const SizedBox(height: 12), exportCard, const SizedBox(height: 12), cashBookCard,
		]);
	}
}

// ===== Additional simple screen =====
class AccountingReportsScreen extends StatelessWidget {
	const AccountingReportsScreen({super.key});
	@override
	Widget build(BuildContext context) {
		final reports = const ['P&L', 'GSTR', 'Reconciliation'];
		return ListView.separated(
			padding: const EdgeInsets.all(12),
			itemCount: reports.length,
			separatorBuilder: (_, __) => const Divider(),
			itemBuilder: (context, index) => ListTile(
				leading: const Icon(Icons.insert_chart_outlined),
				title: Text(reports[index]),
				trailing: const Icon(Icons.chevron_right),
				onTap: () {},
			),
		);
	}
}

// ===== Reused UI from original file =====
class _TotalSummaryCard extends StatelessWidget {
	final Stream<List<_LedgerEntry>> ledgerStream; final Stream<double>? stockValueStream;
	const _TotalSummaryCard({required this.ledgerStream, required this.stockValueStream});
	@override
	Widget build(BuildContext context) {
		return Card(
			child: Padding(
				padding: const EdgeInsets.all(16),
				child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
										Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
												Text('Total Summary', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface)),
												Chip(
													avatar: Icon(Icons.sync, size: 16, color: Theme.of(context).colorScheme.tertiary),
													label: Text('Live', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurface)),
												),
										]),
					const SizedBox(height: 12),
					StreamBuilder<List<_LedgerEntry>>(
						stream: ledgerStream,
						builder: (context, ledgerSnap) {
							if (ledgerSnap.hasError) return Text('Error: ${ledgerSnap.error}');
							if (!ledgerSnap.hasData) return const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()));
							// If stock stream not yet initialized (hot reload scenario) show zero placeholder
							final effectiveStockStream = stockValueStream ?? Stream<double>.value(0);
							return StreamBuilder<double>(
								stream: effectiveStockStream,
								builder: (context, stockSnap) {
									if (stockSnap.hasError) return Text('Stock error: ${stockSnap.error}');
									if (!stockSnap.hasData) return const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()));

									final entries = ledgerSnap.data!;
									final stockValue = stockSnap.data!;

									// Compute net by payment method (sales in - purchases out)
									final Map<String, double> netByMethod = {};
									for (final e in entries) {
										final m = (e.paymentMethod ?? 'Unknown').isEmpty ? 'Unknown' : e.paymentMethod!;
										final delta = e.inAmt - e.outAmt;
										netByMethod[m] = (netByMethod[m] ?? 0) + delta;
									}
									for (final k in ['Cash','UPI','Card']) { netByMethod.putIfAbsent(k, () => 0); }
									final methodsTotal = netByMethod.values.fold(0.0, (a,b)=>a+b);
									final grandTotal = methodsTotal + stockValue;

									return Wrap(spacing: 12, runSpacing: 12, children: [
										for (final e in netByMethod.entries)
											_MetricTile(
												title: e.key,
												value: '₹${e.value.toStringAsFixed(0)}',
												icon: e.key == 'Cash' ? Icons.currency_rupee : (e.key == 'UPI' ? Icons.qr_code_scanner : Icons.credit_card),
											),
										_MetricTile(title: 'Stock Value', value: '₹${stockValue.toStringAsFixed(0)}', icon: Icons.inventory_2_outlined),
										_MetricTile(title: 'Total (Methods)', value: '₹${methodsTotal.toStringAsFixed(0)}', icon: Icons.summarize_outlined),
										_MetricTile(title: 'Grand Total', value: '₹${grandTotal.toStringAsFixed(0)}', icon: Icons.account_balance_outlined),
									]);
								},
							);
						},
					),
				]),
			),
		);
	}
}

class _DynamicGstReportsCard extends StatelessWidget {
	const _DynamicGstReportsCard();
	@override
	Widget build(BuildContext context) {
		return Card(
			child: Padding(
				padding: const EdgeInsets.all(16),
				child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
					Row(children:[ Icon(Icons.assignment_outlined, color: Theme.of(context).colorScheme.onSurfaceVariant), const SizedBox(width:8), Text('GST Reports', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface)) ]),
					const SizedBox(height: 12),
					Text('Detailed GST computations removed (service file deleted).', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
					const SizedBox(height: 8),
					Text('Restore by re-adding gstr3b_service.dart or integrating backend API.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
				]),
			),
		);
	}
}

class _PnLCard extends StatelessWidget {
	final double revenue; final double expenses; final double netProfit;
	const _PnLCard({required this.revenue, required this.expenses, required this.netProfit});
	@override
	Widget build(BuildContext context) {
		final total = (revenue + expenses).clamp(1, 1 << 31);
		return Card(
			child: Padding(
				padding: const EdgeInsets.all(16),
				child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
					Text('Profit & Loss', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface)),
					const SizedBox(height: 12),
					Wrap(spacing: 12, runSpacing: 12, children: [
						_MetricTile(title: 'Revenue', value: '₹${revenue.toStringAsFixed(0)}', icon: Icons.trending_up),
						_MetricTile(title: 'Expenses', value: '₹${expenses.toStringAsFixed(0)}', icon: Icons.trending_down),
						_MetricTile(title: 'Net Profit', value: '₹${netProfit.toStringAsFixed(0)}', icon: Icons.account_balance_wallet_outlined),
					]),
					const SizedBox(height: 12),
					LayoutBuilder(builder: (context, constraints) {
						final maxW = constraints.maxWidth;
						return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
							_Bar(label: 'Revenue', color: Theme.of(context).colorScheme.primary, width: maxW * (revenue / total), value: revenue),
							const SizedBox(height: 8),
							_Bar(label: 'Expenses', color: Theme.of(context).colorScheme.error, width: maxW * (expenses / total), value: expenses),
						]);
					}),
					const SizedBox(height: 8),
					Text('Demo chart — replace with charts later.\nTODO: Pull real P&L from backend.', style: context.texts.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
				]),
			),
		);
	}
}


class _TaxSummaryCard extends StatelessWidget {
	final _TaxSummary summary; const _TaxSummaryCard({required this.summary});
	@override
	Widget build(BuildContext context) {
		final net = (summary.gstPayable - summary.itc).clamp(0, double.infinity);
		return Card(
			child: Padding(
				padding: const EdgeInsets.all(16),
				child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
					Text('Tax & Liability Summary', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface)),
					const SizedBox(height: 8),
					Wrap(spacing: 12, runSpacing: 12, children: [
						_MetricTile(title: 'GST Payable', value: '₹${summary.gstPayable.toStringAsFixed(0)}', icon: Icons.account_balance_outlined),
						_MetricTile(title: 'Input Tax Credit', value: '₹${summary.itc.toStringAsFixed(0)}', icon: Icons.credit_score_outlined),
						_MetricTile(title: 'Net Liability', value: '₹${net.toStringAsFixed(0)}', icon: Icons.scale_outlined),
					]),
				]),
			),
		);
	}
}

class _ExportCard extends StatelessWidget {
	const _ExportCard();
	@override
	Widget build(BuildContext context) {
		return Card(
			child: Padding(
				padding: const EdgeInsets.all(16),
				child: Row(children: [
					Icon(Icons.file_download_outlined, color: Theme.of(context).colorScheme.onSurfaceVariant), const SizedBox(width: 8),
					Text('Export', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface)), const Spacer(),
					OutlinedButton.icon(
					  style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.onSurface),
					  onPressed: () {}, icon: const Icon(Icons.grid_on_outlined), label: const Text('CSV')),
					const SizedBox(width: 8),
					OutlinedButton.icon(
					  style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.onSurface),
					  onPressed: () {}, icon: const Icon(Icons.table_chart_outlined), label: const Text('Excel')),
				]),
			),
		);
	}
}


class _CashBookCard extends StatelessWidget {
	final Stream<List<_LedgerEntry>> stream;
	const _CashBookCard({required this.stream});
	@override
	Widget build(BuildContext context) {
		return Card(
			child: Padding(
				padding: const EdgeInsets.all(12),
				child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
					Text('Balance Sheet', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface)),
					const SizedBox(height: 8),
					StreamBuilder<List<_LedgerEntry>>(
						stream: stream,
						builder: (context, snap) {
							if (snap.hasError) return Text('Error: ${snap.error}');
							if (!snap.hasData) return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
							final entries = snap.data!;
							double running = 0;
														return SingleChildScrollView(
								scrollDirection: Axis.horizontal,
																child: DataTableTheme(
																	data: DataTableThemeData(
																		headingTextStyle: Theme.of(context).textTheme.labelMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface),
																		dataTextStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface),
																	),
																	child: DataTable(columns: const [
																		DataColumn(label: Text('Date')),
																		DataColumn(label: Text('Description')),
																		DataColumn(label: Text('Payment Method')),
																		DataColumn(label: Text('In')),
																		DataColumn(label: Text('Out')),
																		DataColumn(label: Text('Balance')),
																	], rows: [
																		for (final e in entries)
																			() {
																				running += e.inAmt - e.outAmt;
																				return DataRow(cells: [
																					DataCell(Text(e.date.toLocal().toString().split(' ').first)),
																					DataCell(Text(e.desc)),
																					DataCell(Text(e.paymentMethod ?? '-')),
																					DataCell(Text(e.inAmt == 0 ? '-' : '₹${e.inAmt.toStringAsFixed(0)}')),
																					DataCell(Text(e.outAmt == 0 ? '-' : '₹${e.outAmt.toStringAsFixed(0)}')),
																					DataCell(Text('₹${running.toStringAsFixed(0)}')),
																				]);
																			}(),
																	]),
																),
							);
						},
					),
				]),
			),
		);
	}
}

class _MetricTile extends StatelessWidget {
	final String title; final String value; final IconData icon;
	const _MetricTile({required this.title, required this.value, required this.icon});
	@override
	Widget build(BuildContext context) {
		return Container(
			padding: const EdgeInsets.all(12),
			decoration: BoxDecoration(
				borderRadius: BorderRadius.circular(8),
				color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
			),
			child: Row(mainAxisSize: MainAxisSize.min, children: [
				Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant), const SizedBox(width: 8),
				Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
					Text(title, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
					Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface)),
				]),
			]),
		);
	}
}

class _Bar extends StatelessWidget {
	final String label; final Color color; final double width; final double value;
	const _Bar({required this.label, required this.color, required this.width, required this.value});
	@override
	Widget build(BuildContext context) {
		return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
			Text('$label (₹${value.toStringAsFixed(0)})', style: context.texts.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)), const SizedBox(height: 4),
			ConstrainedBox(constraints: const BoxConstraints(minWidth: 20, maxHeight: 14), child: Container(
				height: 14, width: width, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
			)),
		]);
	}
}

// ===== Demo data classes =====
// Legacy _GstRow model removed (dynamic card now computes live values).
// Removed _Expense and _Credit models along with related UI cards to fulfill
// requirement: eliminate Manual Expenses and Outstanding Credits sections.
class _TaxSummary { final double gstPayable; final double itc; const _TaxSummary({required this.gstPayable, required this.itc}); }
class _LedgerEntry {
	final DateTime date; final String desc; final double inAmt; final double outAmt; final String? paymentMethod;
	_LedgerEntry({required this.date, required this.desc, required this.inAmt, required this.outAmt, this.paymentMethod});
}

// ===== TODO placeholders (models/services) =====
// Models would live here if needed in the future.
// Services would live here (e.g., AccountingService) to fetch/report data.
