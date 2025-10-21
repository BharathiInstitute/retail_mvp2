import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme_utils.dart';
import 'package:go_router/go_router.dart';
import 'package:retail_mvp2/core/auth/auth.dart';
import 'dashboard_providers.dart';

// Consolidated Dashboard module in a single file.
// Includes DashboardScreen and all helper widgets.

class DashboardScreen extends ConsumerWidget {
	const DashboardScreen({super.key});

	@override
	Widget build(BuildContext context, WidgetRef ref) {
		// Observe auth state (not used for branching yet, but available)
		final _ = ref.watch(authStateProvider);
	// Role-based UI removed; full owner view shown for all users.

		final salesAgg = ref.watch(salesAggregateProvider);

		final topProductsAsync = ref.watch(topSellingProductsProvider);
		final alertsAsync = ref.watch(inventoryAlertsProvider);

		// Daily revenue vs target (target static demo, actual from sales aggregate)
		const dailyTarget = 10000.0;
		final double dailyActual = salesAgg.asData?.value['today'] ?? 0;

		// Payment split (live from ledger)
		final splitAsync = ref.watch(paymentSplitProvider);

		final page = Padding(
			padding: const EdgeInsets.all(16),
			child: LayoutBuilder(builder: (context, c) {
				final isWide = c.maxWidth >= 1100;

				final summary = salesAgg.when(
					data: (m) => _SummaryRow(
						 today: [0, m['today'] ?? 0],
						 week: [0, m['week'] ?? 0],
						 month: [0, m['month'] ?? 0],
					),
					loading: () => const SizedBox(height: 90, child: Center(child: CircularProgressIndicator())),
					error: (e,_) => SizedBox(height: 90, child: Center(child: Text('Error loading sales: $e'))),
				);

				final topProductsTable = topProductsAsync.when(
				  data: (rows) => _TopProductsTable(rows: [for (final r in rows) _P(name: r['name'] as String, units: (r['units'] as double).round(), revenue: r['revenue'] as double)]),
				  loading: () => const SizedBox(height: 180, child: Center(child: CircularProgressIndicator())),
				  error: (e,_) => SizedBox(height: 80, child: Center(child: Text('Top products error: $e'))),
				);
				final alertsTable = alertsAsync.when(
				  data: (rows) => _AlertsTable(rows: [for (final r in rows) _A(product: r['product'] as String, sku: r['sku'] as String, stock: r['stock'] as int, expiry: r['expiry'] as String, status: r['status'] as String)]),
				  loading: () => const SizedBox(height: 160, child: Center(child: CircularProgressIndicator())),
				  error: (e,_) => SizedBox(height: 80, child: Center(child: Text('Alerts error: $e'))),
				);
				final revenueVsTarget = _RevenueVsTargetChart(actual: dailyActual, target: dailyTarget);
				final paymentSplit = splitAsync.when(
				  data: (m) => _PaymentSplitDonut(cash: m['cash'] ?? 0, upi: m['upi'] ?? 0, card: m['card'] ?? 0),
				  loading: () => const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
				  error: (e,_) => SizedBox(height: 80, child: Center(child: Text('Payment split error: $e'))),
				);
				final quickLinks = _QuickLinks(onGo: (r) => context.go(r));
				final export = const _ExportRow();

				if (isWide) {
					return ListView(
						children: [
							Text('Dashboard', style: context.texts.headlineMedium?.copyWith(color: context.colors.onSurface, fontWeight: FontWeight.w700)),
							const SizedBox(height: 12),
							summary,
							const SizedBox(height: 12),
							Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
								Expanded(flex: 3, child: Column(children: [revenueVsTarget, const SizedBox(height: 12), topProductsTable])),
								const SizedBox(width: 12),
								Expanded(flex: 2, child: Column(children: [paymentSplit, const SizedBox(height: 12), alertsTable, const SizedBox(height: 12), export, const SizedBox(height: 4), quickLinks])),
							]),
						],
					);
				}

				// Narrow
				return ListView(
					children: [
						Text('Dashboard', style: context.texts.headlineMedium?.copyWith(color: context.colors.onSurface, fontWeight: FontWeight.w700)),
						const SizedBox(height: 12),
						summary,
						const SizedBox(height: 12),
						revenueVsTarget,
						const SizedBox(height: 12),
						topProductsTable,
						const SizedBox(height: 12),
						paymentSplit,
						const SizedBox(height: 12),
						alertsTable,
						const SizedBox(height: 12),
						export,
						const SizedBox(height: 4),
						quickLinks,
					],
				);
			}),
		);

		return page;
	}
}

class _SummaryRow extends StatelessWidget {
	final List<double> today;
	final List<double> week;
	final List<double> month;
	const _SummaryRow({required this.today, required this.week, required this.month});

	@override
	Widget build(BuildContext context) {
		final c = Theme.of(context).colorScheme;
		return Row(children: [
			Expanded(child: _MiniLineCard(title: 'Today', values: today, bg: c.primaryContainer, fg: c.onPrimaryContainer)),
			const SizedBox(width: 12),
			Expanded(child: _MiniLineCard(title: 'This Week', values: week, bg: c.secondaryContainer, fg: c.onSecondaryContainer)),
			const SizedBox(width: 12),
			Expanded(child: _MiniLineCard(title: 'This Month', values: month, bg: c.tertiaryContainer, fg: c.onTertiaryContainer)),
		]);
	}
}

class _MiniLineCard extends StatelessWidget {
	final String title;
	final List<double> values;
	final Color bg;
	final Color fg;
	const _MiniLineCard({required this.title, required this.values, required this.bg, required this.fg});
	@override
	Widget build(BuildContext context) {
		final total = values.isEmpty ? 0.0 : values.last;
		return Card(
			color: bg,
			child: Padding(
				padding: const EdgeInsets.all(12),
				child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
					Text(title, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: fg)),
					const SizedBox(height: 6),
					Text('₹${total.toStringAsFixed(0)}', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: fg, fontWeight: FontWeight.w800)),
					const SizedBox(height: 8),
					SizedBox(height: 40, child: CustomPaint(painter: _LinePainter(values: values, color: fg))),
				]),
			),
		);
	}
}

class _LinePainter extends CustomPainter {
	final List<double> values;
	final Color color;
	_LinePainter({required this.values, required this.color});
	@override
	void paint(Canvas canvas, Size size) {
		if (values.isEmpty) return;
		final p = Paint()
			..color = color.withValues(alpha: 0.9)
			..strokeWidth = 2
			..style = PaintingStyle.stroke;
		final path = Path();
		final maxV = values.reduce((a, b) => a > b ? a : b);
		for (int i = 0; i < values.length; i++) {
			final x = size.width * (i / (values.length - 1));
			final y = size.height - (values[i] / (maxV == 0 ? 1 : maxV)) * size.height;
			if (i == 0) {
				path.moveTo(x, y);
			} else {
				path.lineTo(x, y);
			}
		}
		// slight smoothing with a transparent overlay line
		canvas.drawPath(path, p);
	}
	@override
	bool shouldRepaint(covariant _LinePainter old) => old.values != values || old.color != color;
}

class _RevenueVsTargetChart extends StatelessWidget {
	final double target;
	final double actual;
	const _RevenueVsTargetChart({required this.target, required this.actual});
	@override
	Widget build(BuildContext context) {
		final c = Theme.of(context).colorScheme;
		final maxV = math.max(1.0, math.max(target, actual));
		return Card(
			child: Padding(
				padding: const EdgeInsets.all(12),
				child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
					Row(children: [
						Icon(Icons.query_stats, color: c.primary),
						const SizedBox(width: 8),
						Text('Daily Revenue vs Target', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: c.onSurface, fontWeight: FontWeight.w700)),
					]),
					const SizedBox(height: 12),
					SizedBox(
						height: 160,
						child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
							Expanded(child: _Bar(label: 'Target', value: target / maxV, color: c.outlineVariant, valueLabel: '₹${target.toStringAsFixed(0)}')),
							const SizedBox(width: 12),
							Expanded(child: _Bar(label: 'Actual', value: actual / maxV, color: c.primary, valueLabel: '₹${actual.toStringAsFixed(0)}')),
						]),
					),
				]),
			),
		);
	}
}

class _Bar extends StatelessWidget {
	final String label;
	final double value; // 0..1
	final Color color;
	final String valueLabel;
	const _Bar({required this.label, required this.value, required this.color, required this.valueLabel});
	@override
	Widget build(BuildContext context) {
		final base = Theme.of(context).colorScheme.surfaceContainerHighest;
		return Column(mainAxisAlignment: MainAxisAlignment.end, children: [
			Expanded(
				child: Align(
					alignment: Alignment.bottomCenter,
						child: Container(
							height: 120 * value,
							decoration: BoxDecoration(color: color.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(8)),
							child: Center(
								child: Builder(builder: (ctx) {
									final cs = Theme.of(ctx).colorScheme;
									final on = color.computeLuminance() < 0.5 ? cs.onPrimary : cs.onSurface;
									return Text(
										valueLabel,
										style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: on, fontWeight: FontWeight.w600),
									);
								}),
							),
						),
				),
			),
			const SizedBox(height: 8),
			Container(height: 4, decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(2))),
			const SizedBox(height: 8),
			Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface)),
		]);
	}
}

class _PaymentSplitDonut extends StatelessWidget {
	final double cash, upi, card; // percents sum ~100
	const _PaymentSplitDonut({required this.cash, required this.upi, required this.card});
	@override
	Widget build(BuildContext context) {
		final c = Theme.of(context).colorScheme;
		final total = math.max(1.0, cash + upi + card);
		final slices = [cash / total, upi / total, card / total];
		return Card(
			child: Padding(
				padding: const EdgeInsets.all(12),
				child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
					Row(children: [
						Icon(Icons.pie_chart, color: c.primary),
						const SizedBox(width: 8),
						Text('Payment Split', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: c.onSurface, fontWeight: FontWeight.w700)),
					]),
					const SizedBox(height: 12),
					Row(children: [
						SizedBox(width: 160, height: 160, child: CustomPaint(painter: _PiePainter(colors: [c.tertiary, c.primary, c.secondary], slices: slices))),
						const SizedBox(width: 16),
						Expanded(child: Wrap(spacing: 12, runSpacing: 8, children: [
							_Legend(color: c.tertiary, label: 'Cash ${cash.toStringAsFixed(0)}%'),
							_Legend(color: c.primary, label: 'UPI ${upi.toStringAsFixed(0)}%'),
							_Legend(color: c.secondary, label: 'Card ${card.toStringAsFixed(0)}%'),
						])),
					]),
				]),
			),
		);
	}
}

class _PiePainter extends CustomPainter {
	final List<double> slices;
	final List<Color> colors;
	_PiePainter({required this.slices, required this.colors});
	@override
	void paint(Canvas canvas, Size size) {
		final rect = Offset.zero & size;
		final center = rect.center;
		final radius = math.min(size.width, size.height) / 2;
		final paint = Paint()..style = PaintingStyle.fill;
		var start = -math.pi / 2;
		for (int i = 0; i < slices.length; i++) {
			final sweep = (slices[i] * 2 * math.pi).clamp(0.0, 2 * math.pi);
			paint.color = colors[i % colors.length];
			canvas.drawArc(Rect.fromCircle(center: center, radius: radius), start, sweep, true, paint);
			start += sweep;
		}
		// donut hole
		canvas.saveLayer(rect, Paint());
		final clear = Paint()..blendMode = BlendMode.clear;
		canvas.drawCircle(center, radius * .55, clear);
		canvas.restore();
	}
	@override
	bool shouldRepaint(covariant _PiePainter old) => old.slices != slices || old.colors != colors;
}

class _Legend extends StatelessWidget {
	final Color color; final String label;
	const _Legend({required this.color, required this.label});
	@override
	Widget build(BuildContext context) {
		return Row(mainAxisSize: MainAxisSize.min, children: [
			Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
			const SizedBox(width: 6),
			Text(label, style: context.texts.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
		]);
	}
}

class _TopProductsTable extends StatelessWidget {
	final List<_P> rows;
	const _TopProductsTable({required this.rows});
	@override
	Widget build(BuildContext context) {
		final title = Row(children: [
			Icon(Icons.leaderboard, color: Theme.of(context).colorScheme.primary),
			const SizedBox(width: 8),
			Text('Top-selling Products', style: context.texts.titleMedium?.copyWith(color: context.colors.onSurface, fontWeight: FontWeight.w700)),
		]);
		return Card(
			child: Padding(
				padding: const EdgeInsets.all(12),
				child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
					title,
					const SizedBox(height: 8),
					DataTableTheme(
						data: DataTableThemeData(
							headingTextStyle: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w700),
							dataTextStyle: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface),
						),
						child: SingleChildScrollView(
							scrollDirection: Axis.horizontal,
							child: DataTable(columns: const [
								DataColumn(label: Text('Product Name')),
								DataColumn(label: Text('Units Sold')),
								DataColumn(label: Text('Revenue (₹)')),
							], rows: [
								for (final p in rows)
									DataRow(cells: [
										DataCell(Text(p.name)),
										DataCell(Text(p.units.toString())),
										DataCell(Text(p.revenue.toStringAsFixed(2))),
									]),
							]),
						),
					),
				]),
			),
		);
	}
}

class _AlertsTable extends StatelessWidget {
	final List<_A> rows;
	const _AlertsTable({required this.rows});
	@override
	Widget build(BuildContext context) {
		final c = Theme.of(context).colorScheme;
		final title = Row(children: [
			Icon(Icons.warning_amber_rounded, color: c.error),
			const SizedBox(width: 8),
			Text('Low-stock & Expiry Alerts', style: context.texts.titleMedium?.copyWith(color: context.colors.onSurface, fontWeight: FontWeight.w700)),
		]);
		return Card(
			child: Padding(
				padding: const EdgeInsets.all(12),
				child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
					title,
					const SizedBox(height: 8),
					DataTableTheme(
						data: DataTableThemeData(
							headingTextStyle: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w700),
							dataTextStyle: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface),
						),
						child: SingleChildScrollView(
							scrollDirection: Axis.horizontal,
							child: DataTable(columns: const [
								DataColumn(label: Text('Product')),
								DataColumn(label: Text('SKU')),
								DataColumn(label: Text('Stock')),
								DataColumn(label: Text('Expiry Date')),
								DataColumn(label: Text('Status')),
							], rows: [
								for (final a in rows)
									DataRow(cells: [
										DataCell(Text(a.product)),
										DataCell(Text(a.sku)),
										DataCell(Text(a.stock.toString())),
										DataCell(Text(a.expiry)),
										DataCell(Text(a.status)),
									]),
							]),
						),
					),
				]),
			),
		);
	}
}

class _QuickLinks extends StatelessWidget {
	final void Function(String route) onGo;
	const _QuickLinks({required this.onGo});
	@override
	Widget build(BuildContext context) {
		return Card(
			child: Padding(
				padding: const EdgeInsets.all(12),
				child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
					Text('Quick Links', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: context.colors.onSurface, fontWeight: FontWeight.w700)),
					const SizedBox(height: 8),
					Wrap(spacing: 12, runSpacing: 12, children: [
						_LinkChip(icon: Icons.point_of_sale, label: 'POS', onTap: () => onGo('/pos')),
						_LinkChip(icon: Icons.inventory_2, label: 'Inventory', onTap: () => onGo('/inventory')),
						_LinkChip(icon: Icons.receipt_long, label: 'Reports', onTap: () {}),
					]),
				]),
			),
		);
	}
}

class _LinkChip extends StatelessWidget {
	final IconData icon; final String label; final VoidCallback onTap;
	const _LinkChip({required this.icon, required this.label, required this.onTap});
	@override
	Widget build(BuildContext context) {
		final tone = Theme.of(context).colorScheme;
		return InkWell(
			onTap: onTap,
			borderRadius: BorderRadius.circular(10),
			child: Ink(
				padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
				decoration: BoxDecoration(color: tone.surfaceContainerHighest, borderRadius: BorderRadius.circular(10), border: Border.all(color: tone.outlineVariant)),
				child: Row(mainAxisSize: MainAxisSize.min, children: [
					Icon(icon, color: tone.primary),
					const SizedBox(width: 8),
					Text(label, style: context.texts.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
				]),
			),
		);
	}
}

class _ExportRow extends StatelessWidget {
	const _ExportRow();
	@override
	Widget build(BuildContext context) {
		return Row(children: [
			FilledButton.icon(onPressed: () {}, icon: const Icon(Icons.picture_as_pdf), label: const Text('Export PDF')),
			const SizedBox(width: 8),
			OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.table_view), label: const Text('Export CSV')),
		]);
	}
}

class _P {
	final String name; final int units; final double revenue;
	const _P({required this.name, required this.units, required this.revenue});
}
class _A {
	final String product; final String sku; final int stock; final String expiry; final String status;
	const _A({required this.product, required this.sku, required this.stock, required this.expiry, required this.status});
}