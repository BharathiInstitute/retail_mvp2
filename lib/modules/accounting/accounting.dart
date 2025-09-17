import 'package:flutter/material.dart';

// Consolidated Accounting module in a single file.
// This merges prior UI screens and keeps placeholders for models/services.

// ===== Accounting Module (main screen) =====
class AccountingModuleScreen extends StatefulWidget {
	const AccountingModuleScreen({super.key});
	@override
	State<AccountingModuleScreen> createState() => _AccountingModuleScreenState();
}

class _AccountingModuleScreenState extends State<AccountingModuleScreen> with SingleTickerProviderStateMixin {
	final Map<String, double> _salesByMode = {
		'Cash': 12500,
		'UPI': 18250,
		'Card': 9400,
	};

	final List<_GstRow> _gstr1 = const [
		_GstRow(section: 'B2B', invoiceCount: 8, taxable: 145000, tax: 26100),
		_GstRow(section: 'B2C', invoiceCount: 42, taxable: 210000, tax: 37800),
	];
	final List<_GstRow> _gstr3b = const [
		_GstRow(section: 'Outward Supplies', invoiceCount: 50, taxable: 355000, tax: 63900),
		_GstRow(section: 'Zero-rated', invoiceCount: 2, taxable: 12000, tax: 0),
	];

	double revenue = 480000;
	double expenses = 325000;

	final List<_Expense> _expenses = [
		_Expense(date: DateTime.now().subtract(const Duration(days: 1)), category: 'Rent', amount: 35000, notes: 'September'),
		_Expense(date: DateTime.now().subtract(const Duration(days: 2)), category: 'Utilities', amount: 6500, notes: 'Electricity'),
		_Expense(date: DateTime.now().subtract(const Duration(days: 2)), category: 'Supplies', amount: 12000, notes: 'Packaging'),
	];

	final _TaxSummary taxSummary = const _TaxSummary(gstPayable: 68000, itc: 42000);

	final List<_Credit> _credits = [
		_Credit(customer: 'Alice', invoiceId: 'INV-1024', amount: 5400, dueDate: DateTime.now().add(const Duration(days: 7))),
		_Credit(customer: 'Bob', invoiceId: 'INV-1027', amount: 8300, dueDate: DateTime.now().add(const Duration(days: 10))),
	];

	final List<_LedgerEntry> _ledger = [
		_LedgerEntry(date: DateTime.now().subtract(const Duration(days: 2)), desc: 'Opening Balance', inAmt: 50000, outAmt: 0),
		_LedgerEntry(date: DateTime.now().subtract(const Duration(days: 2)), desc: 'Sales (Cash)', inAmt: 8200, outAmt: 0),
		_LedgerEntry(date: DateTime.now().subtract(const Duration(days: 1)), desc: 'Purchase', inAmt: 0, outAmt: 12000),
		_LedgerEntry(date: DateTime.now().subtract(const Duration(days: 1)), desc: 'Sales (Cash)', inAmt: 11200, outAmt: 0),
		_LedgerEntry(date: DateTime.now(), desc: 'Rent', inAmt: 0, outAmt: 35000),
		_LedgerEntry(date: DateTime.now(), desc: 'Sales (Cash)', inAmt: 9300, outAmt: 0),
	];

	late TabController _tabController;
	@override
	void initState() { super.initState(); _tabController = TabController(length: 2, vsync: this); }
	@override
	void dispose() { _tabController.dispose(); super.dispose(); }

	double get _todayTotal => _salesByMode.values.fold(0.0, (a, b) => a + b);
	bool get _reconciled => true;

	void _addDummyExpense() {
		setState(() {
			_expenses.insert(0, _Expense(date: DateTime.now(), category: 'Misc', amount: 2500, notes: 'Added manually (demo)'));
		});
		ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Expense added (demo)')));
	}

	@override
	Widget build(BuildContext context) {
		final isWide = MediaQuery.of(context).size.width >= 1000;
		final netProfit = revenue - expenses;

		final salesCard = _DailySalesCard(salesByMode: _salesByMode, total: _todayTotal, reconciled: _reconciled);
		final gstrCard = _GstReportsCard(tabController: _tabController, gstr1: _gstr1, gstr3b: _gstr3b);
		final pnlCard = _PnLCard(revenue: revenue, expenses: expenses, netProfit: netProfit);
		final expensesCard = _ExpensesCard(expenses: _expenses, onAdd: _addDummyExpense);
		final taxCard = _TaxSummaryCard(summary: taxSummary);
		final exportCard = const _ExportCard();
		final creditsCard = _OutstandingCreditsCard(credits: _credits);
	final cashBookCard = _CashBookCard(entries: _ledger);

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
							expensesCard, const SizedBox(height: 12), creditsCard, const SizedBox(height: 12), cashBookCard,
						]),
					),
				]),
			);
		}

		return ListView(padding: const EdgeInsets.all(16), children: [
			salesCard, const SizedBox(height: 12), gstrCard, const SizedBox(height: 12), pnlCard, const SizedBox(height: 12),
			taxCard, const SizedBox(height: 12), exportCard, const SizedBox(height: 12), expensesCard, const SizedBox(height: 12),
			creditsCard, const SizedBox(height: 12), cashBookCard,
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
class _DailySalesCard extends StatelessWidget {
	final Map<String, double> salesByMode; final double total; final bool reconciled;
	const _DailySalesCard({required this.salesByMode, required this.total, required this.reconciled});
	@override
	Widget build(BuildContext context) {
		return Card(
			child: Padding(
				padding: const EdgeInsets.all(16),
				child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
					Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
						Text("Today's Sales Summary", style: Theme.of(context).textTheme.titleMedium),
						Chip(
							avatar: Icon(reconciled ? Icons.verified_outlined : Icons.error_outline, size: 16, color: reconciled ? Colors.green : Colors.red),
							label: Text(reconciled ? 'Reconciled' : 'Unreconciled'),
							side: BorderSide(color: (reconciled ? Colors.green : Colors.red).withValues(alpha: .4)),
						),
					]),
					const SizedBox(height: 12),
					Wrap(spacing: 12, runSpacing: 12, children: [
						for (final e in salesByMode.entries)
							_MetricTile(title: e.key, value: '₹${e.value.toStringAsFixed(0)}', icon: e.key == 'Cash' ? Icons.currency_rupee : (e.key == 'UPI' ? Icons.qr_code_scanner : Icons.credit_card)),
						_MetricTile(title: 'Total', value: '₹${total.toStringAsFixed(0)}', icon: Icons.summarize_outlined),
					]),
				]),
			),
		);
	}
}

class _GstReportsCard extends StatelessWidget {
	final TabController tabController; final List<_GstRow> gstr1; final List<_GstRow> gstr3b;
	const _GstReportsCard({required this.tabController, required this.gstr1, required this.gstr3b});
	DataTable _table(List<_GstRow> rows) {
		return DataTable(columns: const [
			DataColumn(label: Text('Section')), DataColumn(label: Text('Invoices')),
			DataColumn(label: Text('Taxable Value')), DataColumn(label: Text('Tax Amount')),
		], rows: [ for (final r in rows) DataRow(cells: [
			DataCell(Text(r.section)), DataCell(Text('${r.invoiceCount}')),
			DataCell(Text('₹${r.taxable.toStringAsFixed(0)}')), DataCell(Text('₹${r.tax.toStringAsFixed(0)}')),
		]) ]);
	}
	@override
	Widget build(BuildContext context) {
		return Card(
			child: Padding(
				padding: const EdgeInsets.all(12),
				child: Column(children: [
					TabBar(controller: tabController, labelColor: Theme.of(context).colorScheme.primary, tabs: const [Tab(text: 'GSTR-1'), Tab(text: 'GSTR-3B')]),
					SizedBox(height: 220, child: TabBarView(controller: tabController, children: [
						SingleChildScrollView(child: _table(gstr1)), SingleChildScrollView(child: _table(gstr3b)),
					])),
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
					Text('Profit & Loss', style: Theme.of(context).textTheme.titleMedium),
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
							_Bar(label: 'Revenue', color: Colors.indigo, width: maxW * (revenue / total), value: revenue),
							const SizedBox(height: 8),
							_Bar(label: 'Expenses', color: Colors.orange, width: maxW * (expenses / total), value: expenses),
						]);
					}),
					const SizedBox(height: 8),
					Text('Demo chart — replace with charts later.\nTODO: Pull real P&L from backend.', style: Theme.of(context).textTheme.bodySmall),
				]),
			),
		);
	}
}

class _ExpensesCard extends StatelessWidget {
	final List<_Expense> expenses; final VoidCallback onAdd;
	const _ExpensesCard({required this.expenses, required this.onAdd});
	@override
	Widget build(BuildContext context) {
		return Card(
			child: Padding(
				padding: const EdgeInsets.all(12),
				child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
					Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
						Text('Manual Expenses', style: Theme.of(context).textTheme.titleMedium),
						FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Add Expense')),
					]),
					const SizedBox(height: 8),
					ListView.separated(
						itemCount: expenses.length, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
						separatorBuilder: (_, __) => const Divider(height: 1),
						itemBuilder: (context, i) { final e = expenses[i]; return ListTile(
							leading: const Icon(Icons.receipt_long_outlined),
							title: Text('${e.category} • ₹${e.amount.toStringAsFixed(0)}'),
							subtitle: Text('${e.date.toLocal()} — ${e.notes}'),
						); },
					),
					const SizedBox(height: 8),
					Text('Demo only — no backend writes.', style: Theme.of(context).textTheme.bodySmall),
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
					Text('Tax & Liability Summary', style: Theme.of(context).textTheme.titleMedium),
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
					const Icon(Icons.file_download_outlined), const SizedBox(width: 8),
					Text('Export', style: Theme.of(context).textTheme.titleMedium), const Spacer(),
					OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.grid_on_outlined), label: const Text('CSV')),
					const SizedBox(width: 8),
					OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.table_chart_outlined), label: const Text('Excel')),
				]),
			),
		);
	}
}

class _OutstandingCreditsCard extends StatelessWidget {
	final List<_Credit> credits; const _OutstandingCreditsCard({required this.credits});
	@override
	Widget build(BuildContext context) {
		return Card(
			child: Padding(
				padding: const EdgeInsets.all(12),
				child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
					Text('Outstanding Credits', style: Theme.of(context).textTheme.titleMedium),
					const SizedBox(height: 8),
					ListView.separated(
						itemCount: credits.length, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
						separatorBuilder: (_, __) => const Divider(height: 1),
						itemBuilder: (context, i) { final c = credits[i]; return ListTile(
							leading: const Icon(Icons.person_outline),
							title: Text('${c.customer} — ₹${c.amount.toStringAsFixed(0)}'),
							subtitle: Text('Invoice: ${c.invoiceId} | Due: ${c.dueDate.toLocal()}'),
						); },
					),
				]),
			),
		);
	}
}

class _CashBookCard extends StatelessWidget {
	final List<_LedgerEntry> entries;
	const _CashBookCard({required this.entries});
	@override
	Widget build(BuildContext context) {
		double running = 0;
		return Card(
			child: Padding(
				padding: const EdgeInsets.all(12),
				child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
					Text('Cash Book', style: Theme.of(context).textTheme.titleMedium),
					const SizedBox(height: 8),
					DataTable(columns: const [
						DataColumn(label: Text('Date')),
						DataColumn(label: Text('Description')),
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
									DataCell(Text(e.inAmt == 0 ? '-' : '₹${e.inAmt.toStringAsFixed(0)}')),
									DataCell(Text(e.outAmt == 0 ? '-' : '₹${e.outAmt.toStringAsFixed(0)}')),
									DataCell(Text('₹${running.toStringAsFixed(0)}')),
								]);
							}(),
					]),
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
				color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .5),
			),
			child: Row(mainAxisSize: MainAxisSize.min, children: [
				Icon(icon, size: 18), const SizedBox(width: 8),
				Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
					Text(title, style: Theme.of(context).textTheme.labelMedium),
					Text(value, style: Theme.of(context).textTheme.titleMedium),
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
			Text('$label (₹${value.toStringAsFixed(0)})'), const SizedBox(height: 4),
			ConstrainedBox(constraints: const BoxConstraints(minWidth: 20, maxHeight: 14), child: Container(
				height: 14, width: width, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
			)),
		]);
	}
}

// ===== Demo data classes =====
class _GstRow { final String section; final int invoiceCount; final double taxable; final double tax;
	const _GstRow({required this.section, required this.invoiceCount, required this.taxable, required this.tax}); }
class _Expense { final DateTime date; final String category; final double amount; final String notes;
	_Expense({required this.date, required this.category, required this.amount, required this.notes}); }
class _TaxSummary { final double gstPayable; final double itc; const _TaxSummary({required this.gstPayable, required this.itc}); }
class _Credit { final String customer; final String invoiceId; final double amount; final DateTime dueDate;
	_Credit({required this.customer, required this.invoiceId, required this.amount, required this.dueDate}); }
class _LedgerEntry { final DateTime date; final String desc; final double inAmt; final double outAmt;
	_LedgerEntry({required this.date, required this.desc, required this.inAmt, required this.outAmt}); }

// ===== TODO placeholders (models/services) =====
// Models would live here if needed in the future.
// Services would live here (e.g., AccountingService) to fetch/report data.
