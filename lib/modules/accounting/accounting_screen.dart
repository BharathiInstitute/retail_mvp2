import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import '../inventory/Products/inventory.dart' show selectedStoreProvider;
import 'package:retail_mvp2/core/firestore_store_collections.dart';
import '../../core/theme/theme_extension_helpers.dart';
// Removed import 'gstr3b_service.dart'; file deleted. Replacing GST summary logic with placeholders.

// Consolidated Accounting module in a single file.
// This merges prior UI screens and keeps placeholders for models/services.

// ===== Accounting Module (main screen) =====
class AccountingModuleScreen extends ConsumerStatefulWidget {
  const AccountingModuleScreen({super.key});
  @override
	ConsumerState<AccountingModuleScreen> createState() => _AccountingModuleScreenState();
}

class _AccountingModuleScreenState extends ConsumerState<AccountingModuleScreen> {

// Static GST rows removed; replaced with dynamic computation card.

	// Cache streams to avoid recreating on every build
	String? _cachedStoreId;
	Stream<List<_LedgerEntry>>? _cachedLedgerStream;
	Stream<double>? _cachedStockValueStream;

	double revenue = 480000;
	double expenses = 325000;

	final _TaxSummary taxSummary = const _TaxSummary(gstPayable: 68000, itc: 42000);

	Stream<List<_LedgerEntry>> _salesStream(String storeId) {
		final col = StoreRefs.of(storeId).invoices().orderBy('timestampMs', descending: false);
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

	Stream<List<_LedgerEntry>> _purchaseStream(String storeId) {
		final col = StoreRefs.of(storeId).purchaseInvoices().orderBy('timestampMs', descending: false);
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

	Stream<List<_LedgerEntry>> _buildLedgerStream(String storeId) {
		// Merge sales and purchases streams using combineLatest pattern
		final sales$ = _salesStream(storeId);
		final purchases$ = _purchaseStream(storeId);
		
		// Use a broadcast stream controller that properly handles multiple listeners
		final controller = StreamController<List<_LedgerEntry>>.broadcast();
		List<_LedgerEntry> latestSales = [];
		List<_LedgerEntry> latestPurchases = [];
		
		void emit() {
			final all = [...latestSales, ...latestPurchases];
			all.sort((a, b) => a.date.compareTo(b.date));
			controller.add(all);
		}
		
		final sub1 = sales$.listen((s) {
			latestSales = s;
			emit();
		}, onError: (e) => controller.addError(e));
		
		final sub2 = purchases$.listen((p) {
			latestPurchases = p;
			emit();
		}, onError: (e) => controller.addError(e));
		
		controller.onCancel = () {
			sub1.cancel();
			sub2.cancel();
			controller.close();
		};
		
		return controller.stream;
	}

	Stream<double> _buildStockValueStream(String storeId) {
		final col = StoreRefs.of(storeId).products();
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
		final cs = Theme.of(context).colorScheme;

	final selStoreId = ref.watch(selectedStoreProvider);
	
	// Cache streams - only recreate when store changes
	if (selStoreId != _cachedStoreId) {
		_cachedStoreId = selStoreId;
		_cachedLedgerStream = selStoreId == null ? null : _buildLedgerStream(selStoreId);
		_cachedStockValueStream = selStoreId == null ? null : _buildStockValueStream(selStoreId).asBroadcastStream();
	}
	
	final ledgerStream = _cachedLedgerStream ?? const Stream<List<_LedgerEntry>>.empty();
	final stockValueStream = _cachedStockValueStream;

	final salesCard = _TotalSummaryCard(ledgerStream: ledgerStream, stockValueStream: stockValueStream);
		final gstrCard = _DynamicGstReportsCard();
		final pnlCard = _PnLCard(revenue: revenue, expenses: expenses, netProfit: netProfit);
		final taxCard = _TaxSummaryCard(summary: taxSummary);
		final exportCard = const _ExportCard();
	final cashBookCard = _CashBookCard(stream: ledgerStream);

		return Container(
			decoration: BoxDecoration(
				gradient: LinearGradient(
					begin: Alignment.topCenter,
					end: Alignment.bottomCenter,
					colors: [cs.primary.withOpacity(0.04), cs.surface],
					stops: const [0.0, 0.3],
				),
			),
			child: isWide
				? Padding(
						padding: context.padLg,
						child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
							Expanded(
								flex: 2,
								child: ListView(children: [
									salesCard, context.gapVMd, gstrCard, context.gapVMd,
									pnlCard, context.gapVMd, taxCard, context.gapVMd, exportCard,
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
					)
				: ListView(padding: context.padLg, children: [
						salesCard,
						context.gapVMd,
						pnlCard,
						context.gapVMd,
						taxCard,
						context.gapVMd,
						cashBookCard,
					]),
		);
	}
}

// ===== Additional simple screen =====
class AccountingReportsScreen extends StatelessWidget {
	const AccountingReportsScreen({super.key});
	@override
	Widget build(BuildContext context) {
		final reports = const ['P&L', 'GSTR', 'Reconciliation'];
		return ListView.separated(
			padding: context.padMd,
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
		final cs = Theme.of(context).colorScheme;
		return Container(
			padding: context.padMd,
			decoration: BoxDecoration(
				color: cs.surface,
				borderRadius: context.radiusMd,
				border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
			),
			child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
				Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
					Row(children: [
						Container(
							padding: const EdgeInsets.all(6),
							decoration: BoxDecoration(
								color: cs.primary.withOpacity(0.1),
								borderRadius: context.radiusSm,
							),
							child: Icon(Icons.account_balance_wallet_rounded, size: 14, color: cs.primary),
						),
					context.gapHSm,
					Text('Total Summary', style: TextStyle(fontSize: context.sizes.fontSm, fontWeight: FontWeight.w700, color: cs.onSurface)),
				]),
				Container(
					padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
					decoration: BoxDecoration(
						color: cs.tertiary.withOpacity(0.1),
						borderRadius: context.radiusMd,
					),
					child: Row(mainAxisSize: MainAxisSize.min, children: [
						Icon(Icons.sync_rounded, size: 10, color: cs.tertiary),
						const SizedBox(width: 3),
						Text('Live', style: TextStyle(fontSize: context.sizes.fontXs, fontWeight: FontWeight.w600, color: cs.tertiary)),
						]),
					),
				]),
				const SizedBox(height: 10),
				StreamBuilder<List<_LedgerEntry>>(
					stream: ledgerStream,
					builder: (context, ledgerSnap) {
						if (ledgerSnap.hasError) return Text('Error: ${ledgerSnap.error}', style: TextStyle(color: cs.error));
						if (!ledgerSnap.hasData) return const SizedBox(height: 80, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
						final effectiveStockStream = stockValueStream ?? Stream<double>.value(0);
						return StreamBuilder<double>(
							stream: effectiveStockStream,
							builder: (context, stockSnap) {
								if (stockSnap.hasError) return Text('Stock error: ${stockSnap.error}', style: TextStyle(color: cs.error));
								if (!stockSnap.hasData) return const SizedBox(height: 80, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));

								final entries = ledgerSnap.data!;
								// stockSnap.data available for future stock value display

								final Map<String, double> netByMethod = {};
								for (final e in entries) {
									final m = (e.paymentMethod ?? 'Unknown').isEmpty ? 'Unknown' : e.paymentMethod!;
									final delta = e.inAmt - e.outAmt;
									netByMethod[m] = (netByMethod[m] ?? 0) + delta;
								}
								for (final k in ['Cash','UPI','Card']) { netByMethod.putIfAbsent(k, () => 0); }

								return LayoutBuilder(
									builder: (context, constraints) {
										final isNarrow = constraints.maxWidth < 560;
										final tiles = <Widget>[
											for (final e in netByMethod.entries)
												_ModernMetricTile(
													title: e.key,
													value: '₹${e.value.toStringAsFixed(0)}',
													icon: e.key == 'Cash'
															? Icons.currency_rupee_rounded
															: (e.key == 'UPI' ? Icons.qr_code_scanner_rounded : Icons.credit_card_rounded),
													color: e.key == 'Cash' ? cs.primary : (e.key == 'UPI' ? cs.secondary : cs.tertiary),
												),
										];
										if (isNarrow) {
											return SingleChildScrollView(
												scrollDirection: Axis.horizontal,
												child: Row(
													children: [
														for (int i = 0; i < tiles.length; i++)
															Padding(
																padding: EdgeInsets.only(right: i == tiles.length - 1 ? 0 : 10),
																child: tiles[i],
															),
													],
												),
											);
										}
										return Row(
											children: [
												for (int i = 0; i < tiles.length; i++)
													Expanded(
														child: Padding(
															padding: EdgeInsets.only(right: i == tiles.length - 1 ? 0 : 10),
															child: tiles[i],
														),
													),
											],
										);
									},
								);
							},
						);
					},
				),
				context.gapVMd,
				// Progress bar showing distribution
				StreamBuilder<List<_LedgerEntry>>(
					stream: ledgerStream,
					builder: (context, snap) {
						if (!snap.hasData) return const SizedBox();
						final entries = snap.data!;
						final Map<String, double> netByMethod = {};
						for (final e in entries) {
							final m = (e.paymentMethod ?? 'Unknown').isEmpty ? 'Unknown' : e.paymentMethod!;
							netByMethod[m] = (netByMethod[m] ?? 0) + (e.inAmt - e.outAmt).abs();
						}
						final total = netByMethod.values.fold(0.0, (a, b) => a + b).clamp(1, double.infinity);
						return Container(
							height: 6,
							decoration: BoxDecoration(borderRadius: BorderRadius.circular(3)),
							clipBehavior: Clip.antiAlias,
							child: Row(
								children: [
									if (netByMethod['Unknown'] != null)
										Expanded(
											flex: ((netByMethod['Unknown']! / total) * 100).round().clamp(1, 100),
											child: Container(color: cs.primary),
										),
									if (netByMethod['Cash'] != null)
										Expanded(
											flex: ((netByMethod['Cash']! / total) * 100).round().clamp(1, 100),
											child: Container(color: cs.secondary),
										),
									if (netByMethod['UPI'] != null)
										Expanded(
											flex: ((netByMethod['UPI']! / total) * 100).round().clamp(1, 100),
											child: Container(color: cs.tertiary),
										),
									if (netByMethod['Card'] != null)
										Expanded(
											flex: ((netByMethod['Card']! / total) * 100).round().clamp(1, 100),
											child: Container(color: cs.error),
										),
								],
							),
						);
					},
				),
			]),
		);
	}
}

class _DynamicGstReportsCard extends StatelessWidget {
	const _DynamicGstReportsCard();
	@override
	Widget build(BuildContext context) {
		final cs = Theme.of(context).colorScheme;
		return Container(
			padding: context.padMd,
			decoration: BoxDecoration(
				color: cs.surface,
				borderRadius: context.radiusMd,
				border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
			),
			child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
				Row(children: [
					Container(
						padding: const EdgeInsets.all(6),
						decoration: BoxDecoration(
							color: cs.secondary.withOpacity(0.1),
							borderRadius: context.radiusSm,
						),
						child: Icon(Icons.assignment_rounded, size: 14, color: cs.secondary),
					),
				context.gapHSm,
				Text('GST Reports', style: TextStyle(fontSize: context.sizes.fontSm, fontWeight: FontWeight.w700, color: cs.onSurface)),
			]),
			const SizedBox(height: 10),
			Container(
				padding: const EdgeInsets.all(10),
				decoration: BoxDecoration(
					color: cs.surfaceContainerHighest.withOpacity(0.3),
					borderRadius: context.radiusSm,
				),
				child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
					Text('Detailed GST computations removed (service file deleted).', style: TextStyle(fontSize: context.sizes.fontXs, color: cs.onSurfaceVariant)),
					context.gapVXs,
					Text('Restore by re-adding gstr3b_service.dart or integrating backend API.', style: TextStyle(fontSize: context.sizes.fontXs, color: cs.onSurfaceVariant.withOpacity(0.7))),
					]),
				),
			]),
		);
	}
}

class _PnLCard extends StatelessWidget {
	final double revenue; final double expenses; final double netProfit;
	const _PnLCard({required this.revenue, required this.expenses, required this.netProfit});
	@override
	Widget build(BuildContext context) {
		final cs = Theme.of(context).colorScheme;
		final total = (revenue + expenses).clamp(1, 1 << 31);
		return Container(
			padding: context.padMd,
			decoration: BoxDecoration(
				color: cs.surface,
				borderRadius: context.radiusMd,
				border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
			),
			child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
				Row(children: [
					Container(
						padding: const EdgeInsets.all(6),
						decoration: BoxDecoration(
							color: cs.tertiary.withOpacity(0.1),
							borderRadius: context.radiusSm,
						),
						child: Icon(Icons.analytics_rounded, size: 14, color: cs.tertiary),
					),
				context.gapHSm,
				Text('Profit & Loss', style: TextStyle(fontSize: context.sizes.fontSm, fontWeight: FontWeight.w700, color: cs.onSurface)),
				]),
				const SizedBox(height: 10),
				LayoutBuilder(builder: (context, constraints) {
					final isNarrow = constraints.maxWidth < 560;
					final tiles = <Widget>[
						_ModernMetricTile(title: 'Revenue', value: '₹${revenue.toStringAsFixed(0)}', icon: Icons.trending_up_rounded, color: cs.primary),
						_ModernMetricTile(title: 'Expenses', value: '₹${expenses.toStringAsFixed(0)}', icon: Icons.trending_down_rounded, color: cs.error),
						_ModernMetricTile(title: 'Net Profit', value: '₹${netProfit.toStringAsFixed(0)}', icon: Icons.account_balance_wallet_rounded, color: netProfit >= 0 ? cs.primary : cs.error),
					];
					if (isNarrow) {
						return SingleChildScrollView(
							scrollDirection: Axis.horizontal,
							child: Row(children: [
								for (int i = 0; i < tiles.length; i++)
									Padding(padding: EdgeInsets.only(right: i == tiles.length - 1 ? 0 : 8), child: tiles[i]),
							]),
						);
					}
					return Row(children: [
						for (int i = 0; i < tiles.length; i++)
							Expanded(child: Padding(padding: EdgeInsets.only(right: i == tiles.length - 1 ? 0 : 8), child: tiles[i])),
					]);
				}),
				const SizedBox(height: 10),
				LayoutBuilder(builder: (context, constraints) {
					final maxW = constraints.maxWidth;
					return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
						_ModernBar(label: 'Revenue', color: cs.primary, width: maxW * (revenue / total), value: revenue),
						const SizedBox(height: 6),
						_ModernBar(label: 'Expenses', color: cs.error, width: maxW * (expenses / total), value: expenses),
					]);
				}),
			]),
		);
	}
}


class _TaxSummaryCard extends StatelessWidget {
	final _TaxSummary summary; const _TaxSummaryCard({required this.summary});
	@override
	Widget build(BuildContext context) {
		final cs = Theme.of(context).colorScheme;
		final net = (summary.gstPayable - summary.itc).clamp(0, double.infinity);
		return Container(
			padding: context.padMd,
			decoration: BoxDecoration(
				color: cs.surface,
				borderRadius: context.radiusMd,
				border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
			),
			child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
				Row(children: [
					Container(
						padding: const EdgeInsets.all(6),
						decoration: BoxDecoration(
							color: cs.error.withOpacity(0.1),
							borderRadius: context.radiusSm,
						),
						child: Icon(Icons.receipt_long_rounded, size: 14, color: cs.error),
					),
				context.gapHSm,
				Text('Tax & Liability', style: TextStyle(fontSize: context.sizes.fontSm, fontWeight: FontWeight.w700, color: cs.onSurface)),
				]),
				const SizedBox(height: 10),
				LayoutBuilder(builder: (context, constraints) {
					final isNarrow = constraints.maxWidth < 560;
					final tiles = <Widget>[
						_ModernMetricTile(title: 'GST Payable', value: '₹${summary.gstPayable.toStringAsFixed(0)}', icon: Icons.account_balance_rounded, color: cs.error),
						_ModernMetricTile(title: 'Input Tax Credit', value: '₹${summary.itc.toStringAsFixed(0)}', icon: Icons.credit_score_rounded, color: cs.primary),
						_ModernMetricTile(title: 'Net Liability', value: '₹${net.toStringAsFixed(0)}', icon: Icons.scale_rounded, color: cs.tertiary),
					];
					if (isNarrow) {
						return SingleChildScrollView(
							scrollDirection: Axis.horizontal,
							child: Row(children: [
								for (int i = 0; i < tiles.length; i++)
									Padding(padding: EdgeInsets.only(right: i == tiles.length - 1 ? 0 : 8), child: tiles[i]),
							]),
						);
					}
					return Row(children: [
						for (int i = 0; i < tiles.length; i++)
							Expanded(child: Padding(padding: EdgeInsets.only(right: i == tiles.length - 1 ? 0 : 8), child: tiles[i])),
					]);
				}),
			]),
		);
	}
}

class _ExportCard extends StatelessWidget {
	const _ExportCard();
	@override
	Widget build(BuildContext context) {
		final cs = Theme.of(context).colorScheme;
		return Container(
			padding: const EdgeInsets.all(10),
			decoration: BoxDecoration(
				color: cs.surface,
				borderRadius: context.radiusMd,
				border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
			),
			child: Row(children: [
				Container(
					padding: const EdgeInsets.all(6),
					decoration: BoxDecoration(
						color: cs.secondary.withOpacity(0.1),
						borderRadius: context.radiusSm,
					),
					child: Icon(Icons.download_rounded, size: 14, color: cs.secondary),
				),
			context.gapHSm,
			Text('Export', style: TextStyle(fontSize: context.sizes.fontSm, fontWeight: FontWeight.w700, color: cs.onSurface)),
				const Spacer(),
				_ModernExportButton(icon: Icons.grid_on_rounded, label: 'CSV', onTap: () {}),
				const SizedBox(width: 6),
				_ModernExportButton(icon: Icons.table_chart_rounded, label: 'Excel', onTap: () {}),
			]),
		);
	}
}

class _ModernExportButton extends StatelessWidget {
	final IconData icon; final String label; final VoidCallback onTap;
	const _ModernExportButton({required this.icon, required this.label, required this.onTap});
	@override
	Widget build(BuildContext context) {
		final cs = Theme.of(context).colorScheme;
		return Material(
			color: Colors.transparent,
			child: InkWell(
				onTap: onTap,
				borderRadius: context.radiusSm,
				child: Container(
					padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
					decoration: BoxDecoration(
						border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
						borderRadius: context.radiusSm,
					),
					child: Row(mainAxisSize: MainAxisSize.min, children: [
					Icon(icon, size: 12, color: cs.onSurfaceVariant),
					context.gapHXs,
					Text(label, style: TextStyle(fontSize: context.sizes.fontXs, fontWeight: FontWeight.w500, color: cs.onSurface)),
					]),
				),
			),
		);
	}
}


class _CashBookCard extends StatelessWidget {
	final Stream<List<_LedgerEntry>> stream;
	const _CashBookCard({required this.stream});
	@override
	Widget build(BuildContext context) {
		final cs = Theme.of(context).colorScheme;
		return Container(
			padding: context.padMd,
			decoration: BoxDecoration(
				color: cs.surface,
				borderRadius: context.radiusMd,
				border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
			),
			child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
				Row(children: [
					Container(
						padding: const EdgeInsets.all(6),
						decoration: BoxDecoration(
							color: cs.primary.withOpacity(0.1),
							borderRadius: context.radiusSm,
						),
						child: Icon(Icons.account_balance_wallet_rounded, size: 14, color: cs.primary),
					),
				context.gapHSm,
				Text('Balance Sheet', style: TextStyle(fontSize: context.sizes.fontSm, fontWeight: FontWeight.w700, color: cs.onSurface)),
				]),
				const SizedBox(height: 10),
				StreamBuilder<List<_LedgerEntry>>(
					stream: stream,
					builder: (context, snap) {
						if (snap.hasError) {
							return Container(
							padding: const EdgeInsets.all(10),
							decoration: BoxDecoration(color: cs.errorContainer.withOpacity(0.3), borderRadius: context.radiusSm),
							child: Text('Error: ${snap.error}', style: TextStyle(fontSize: context.sizes.fontXs, color: cs.error)),
							);
						}
						if (!snap.hasData) {
							return const SizedBox(height: 80, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
						}
						final entries = snap.data!;
						if (entries.isEmpty) {
							return Container(
							padding: context.padLg,
							decoration: BoxDecoration(color: cs.surfaceContainerHighest.withOpacity(0.3), borderRadius: context.radiusSm),
							child: Center(child: Text('No transactions yet', style: TextStyle(fontSize: context.sizes.fontXs, color: cs.onSurfaceVariant))),
							);
						}
						double running = 0;
						return ClipRRect(
							borderRadius: context.radiusSm,
							child: Container(
								decoration: BoxDecoration(
									border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
									borderRadius: context.radiusSm,
								),
								child: SingleChildScrollView(
									scrollDirection: Axis.horizontal,
									child: ConstrainedBox(
										constraints: const BoxConstraints(minWidth: 550),
										child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
											// Header row
											Container(
												decoration: BoxDecoration(
													color: cs.surfaceContainerHighest.withOpacity(0.5),
													border: Border(bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.3))),
												),
												child: Row(children: [
													_CashBookHeaderCell('Date', flex: 2),
													_CashBookHeaderCell('Description', flex: 3),
													_CashBookHeaderCell('Method', flex: 2),
													_CashBookHeaderCell('In', flex: 2, align: TextAlign.right),
													_CashBookHeaderCell('Out', flex: 2, align: TextAlign.right),
													_CashBookHeaderCell('Balance', flex: 2, align: TextAlign.right),
												]),
											),
											// Data rows
											...entries.map((e) {
												running += e.inAmt - e.outAmt;
												final idx = entries.indexOf(e);
												return Container(
													decoration: BoxDecoration(
														color: idx.isEven ? Colors.transparent : cs.surfaceContainerHighest.withOpacity(0.2),
														border: idx < entries.length - 1 ? Border(bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.2))) : null,
													),
													child: Row(children: [
														_CashBookDataCell(e.date.toLocal().toString().split(' ').first, flex: 2),
														_CashBookDataCell(e.desc, flex: 3),
														_CashBookDataCell(e.paymentMethod ?? '-', flex: 2),
														_CashBookDataCell(e.inAmt == 0 ? '-' : '₹${e.inAmt.toStringAsFixed(0)}', flex: 2, align: TextAlign.right, color: cs.primary),
														_CashBookDataCell(e.outAmt == 0 ? '-' : '₹${e.outAmt.toStringAsFixed(0)}', flex: 2, align: TextAlign.right, color: cs.error),
														_CashBookDataCell('₹${running.toStringAsFixed(0)}', flex: 2, align: TextAlign.right, bold: true),
													]),
												);
											}),
										]),
									),
								),
							),
						);
					},
				),
			]),
		);
	}
}

class _CashBookHeaderCell extends StatelessWidget {
	final String text; final int flex; final TextAlign align;
	const _CashBookHeaderCell(this.text, {this.flex = 1, this.align = TextAlign.left});
	@override
	Widget build(BuildContext context) {
		final cs = Theme.of(context).colorScheme;
		return Expanded(
			flex: flex,
			child: Padding(
				padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
				child: Text(text, style: TextStyle(fontSize: context.sizes.fontXs, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant), textAlign: align),
			),
		);
	}
}

class _CashBookDataCell extends StatelessWidget {
	final String text; final int flex; final TextAlign align; final Color? color; final bool bold;
	const _CashBookDataCell(this.text, {this.flex = 1, this.align = TextAlign.left, this.color, this.bold = false});
	@override
	Widget build(BuildContext context) {
		final cs = Theme.of(context).colorScheme;
		return Expanded(
			flex: flex,
			child: Padding(
				padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
				child: Text(text, style: TextStyle(fontSize: context.sizes.fontXs, fontWeight: bold ? FontWeight.w600 : FontWeight.w400, color: color ?? cs.onSurface), textAlign: align, overflow: TextOverflow.ellipsis),
			),
		);
	}
}

class _ModernMetricTile extends StatelessWidget {
	final String title; final String value; final IconData icon; final Color color;
	const _ModernMetricTile({required this.title, required this.value, required this.icon, required this.color});
	@override
	Widget build(BuildContext context) {
		final cs = Theme.of(context).colorScheme;
		return Container(
			padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
			decoration: BoxDecoration(
				gradient: LinearGradient(
					begin: Alignment.topLeft,
					end: Alignment.bottomRight,
					colors: [color.withOpacity(0.08), color.withOpacity(0.02)],
				),
				borderRadius: context.radiusMd,
				border: Border.all(color: color.withOpacity(0.2)),
			),
			child: Row(mainAxisSize: MainAxisSize.min, children: [
				Container(
					padding: const EdgeInsets.all(6),
					decoration: BoxDecoration(
						color: color.withOpacity(0.15),
						borderRadius: context.radiusSm,
					),
					child: Icon(icon, size: 14, color: color),
				),
			context.gapHSm,
			Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
				Text(title, style: TextStyle(fontSize: context.sizes.fontXs, fontWeight: FontWeight.w500, color: cs.onSurfaceVariant)),
				Text(value, style: TextStyle(fontSize: context.sizes.fontSm, fontWeight: FontWeight.w700, color: cs.onSurface)),
			]),
			]),
		);
	}
}

class _ModernBar extends StatelessWidget {
	final String label; final Color color; final double width; final double value;
	const _ModernBar({required this.label, required this.color, required this.width, required this.value});
	@override
	Widget build(BuildContext context) {
		final cs = Theme.of(context).colorScheme;
		return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
			Row(children: [
				Text(label, style: TextStyle(fontSize: context.sizes.fontXs, fontWeight: FontWeight.w500, color: cs.onSurfaceVariant)),
				const Spacer(),
				Text('₹${value.toStringAsFixed(0)}', style: TextStyle(fontSize: context.sizes.fontXs, fontWeight: FontWeight.w600, color: cs.onSurface)),
			]),
			context.gapVXs,
			Container(
				height: 6,
				width: double.infinity,
				decoration: BoxDecoration(
					color: cs.surfaceContainerHighest.withOpacity(0.4),
					borderRadius: BorderRadius.circular(3),
				),
				child: Align(
					alignment: Alignment.centerLeft,
					child: AnimatedContainer(
						duration: const Duration(milliseconds: 400),
						height: 6,
						width: width.clamp(0, double.infinity),
						decoration: BoxDecoration(
							gradient: LinearGradient(colors: [color, color.withOpacity(0.7)]),
							borderRadius: BorderRadius.circular(3),
						),
					),
				),
			),
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
