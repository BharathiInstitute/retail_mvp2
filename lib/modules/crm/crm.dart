import 'package:flutter/material.dart';

// Consolidated CRM module in a single file.
// Includes CrmListScreen, CustomerProfilePage, and all related models/helpers.

class CrmListScreen extends StatefulWidget {
	const CrmListScreen({super.key});
	@override
	State<CrmListScreen> createState() => _CrmListScreenState();
}

class _CrmListScreenState extends State<CrmListScreen> {
	final List<CrmCustomer> customers = [];
	String query = '';
	LoyaltyFilter loyaltyFilter = LoyaltyFilter.all;

	@override
	void initState() {
		super.initState();
		customers.addAll(_seedCustomers());
	}

	List<CrmCustomer> get filtered {
		final q = query.trim().toLowerCase();
		return customers.where((c) {
			final matchesQuery = q.isEmpty || c.name.toLowerCase().contains(q) || c.phone.toLowerCase().contains(q) || c.email.toLowerCase().contains(q);
			final matchesLoyalty = loyaltyFilter == LoyaltyFilter.all || loyaltyFilter.status == c.status;
			return matchesQuery && matchesLoyalty;
		}).toList();
	}

	void _exportCsv() {
		final header = 'Name,Phone,Email,Loyalty,TotalSpend,LastVisit';
		final rows = customers.map((c) => '${_csv(c.name)},${_csv(c.phone)},${_csv(c.email)},${c.status.name.toUpperCase()},${c.totalSpend.toStringAsFixed(2)},${_fmtDate(c.lastVisit)}');
		final csv = ([header, ...rows]).join('\n');
		showDialog(context: context, builder: (_) => AlertDialog(title: const Text('Export CSV (demo)'), content: SizedBox(width: 600, child: SingleChildScrollView(child: Text(csv))), actions: const [CloseButton()]));
	}

	void _quickAddCustomer() async {
		final newCustomer = await showModalBottomSheet<CrmCustomer>(
			context: context,
			isScrollControlled: true,
			builder: (_) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom), child: _QuickAddCustomerForm()),
		);
		if (newCustomer != null && mounted) {
			setState(() => customers.insert(0, newCustomer));
			ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Customer ${newCustomer.name} added')));
		}
	}

	void _openProfile(CrmCustomer c) async {
		final updated = await Navigator.of(context).push<CrmCustomer>(MaterialPageRoute(builder: (_) => CustomerProfilePage(customer: c)));
		if (updated != null && mounted) {
			setState(() { final idx = customers.indexWhere((x) => x.id == updated.id); if (idx >= 0) customers[idx] = updated; });
		}
	}

	@override
	Widget build(BuildContext context) {
		final isWide = MediaQuery.of(context).size.width > 900;
		final listView = Card(
			child: Column(children: [
				Padding(
					padding: const EdgeInsets.all(12.0),
					child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
						SizedBox(width: 280, child: TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Search customers (name, phone, email)'), onChanged: (v) => setState(() => query = v))),
						DropdownButton<LoyaltyFilter>(
							value: loyaltyFilter,
							items: const [
								DropdownMenuItem(value: LoyaltyFilter.all, child: Text('All')),
								DropdownMenuItem(value: LoyaltyFilter.bronze, child: Text('Bronze')),
								DropdownMenuItem(value: LoyaltyFilter.silver, child: Text('Silver')),
								DropdownMenuItem(value: LoyaltyFilter.gold, child: Text('Gold')),
							],
							onChanged: (v) => setState(() => loyaltyFilter = v ?? LoyaltyFilter.all),
						),
						const SizedBox(width: 8),
						ElevatedButton.icon(onPressed: _quickAddCustomer, icon: const Icon(Icons.person_add), label: const Text('Add Customer')),
						OutlinedButton.icon(onPressed: _exportCsv, icon: const Icon(Icons.file_download), label: const Text('Export CSV')),
					]),
				),
				const Divider(height: 1),
				Expanded(
					child: Scrollbar(
						thumbVisibility: true,
						child: ListView.separated(
							itemCount: filtered.length,
							separatorBuilder: (_, __) => const Divider(height: 1),
							itemBuilder: (_, i) {
								final c = filtered[i];
								return ListTile(
									onTap: () => _openProfile(c.copy()),
									leading: CircleAvatar(child: Text(c.initials)),
									title: Row(children: [Expanded(child: Text(c.name)), _loyaltyChip(c.status)]),
									subtitle: Text('${c.email} • ${c.phone}'),
									trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [Text('₹${c.totalSpend.toStringAsFixed(2)}'), Text('Last: ${_fmtDate(c.lastVisit)}', style: const TextStyle(fontSize: 12))]),
								);
							},
						),
					),
				),
			]),
		);

		if (isWide) return Padding(padding: const EdgeInsets.all(12), child: Row(children: [Expanded(child: listView)]));
		return Padding(padding: const EdgeInsets.all(12), child: listView);
	}
}

class CustomerProfilePage extends StatefulWidget {
	final CrmCustomer customer; const CustomerProfilePage({super.key, required this.customer});
	@override
	State<CustomerProfilePage> createState() => _CustomerProfilePageState();
}

class _CustomerProfilePageState extends State<CustomerProfilePage> {
	late CrmCustomer c; late TextEditingController notesCtrl; late TextEditingController prefsCtrl;
	@override
	void initState() { super.initState(); c = widget.customer.copy(); notesCtrl = TextEditingController(text: c.notes); prefsCtrl = TextEditingController(text: c.preferences); }
	@override
	void dispose() { notesCtrl.dispose(); prefsCtrl.dispose(); super.dispose(); }
	@override
	Widget build(BuildContext context) {
		return Scaffold(
			appBar: AppBar(title: const Text('Customer Profile'), actions: [TextButton.icon(onPressed: () { c = c.copyWith(notes: notesCtrl.text.trim(), preferences: prefsCtrl.text.trim()); Navigator.pop(context, c); }, icon: const Icon(Icons.save), label: const Text('Save', style: TextStyle(color: Colors.white)))]),
			body: Scrollbar(
				thumbVisibility: true,
				child: SingleChildScrollView(
					padding: const EdgeInsets.all(16),
					child: Column(
						crossAxisAlignment: CrossAxisAlignment.start,
						children: [
							Card(
								child: ListTile(
									leading: CircleAvatar(child: Text(c.initials)),
									title: Row(
										children: [
											Expanded(child: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold))),
											_loyaltyChip(c.status),
										],
									),
									subtitle: Column(
										crossAxisAlignment: CrossAxisAlignment.start,
										children: [
											const SizedBox(height: 4),
											Text(c.email),
											Text(c.phone),
										],
									),
								),
							),
							const SizedBox(height: 12),
							Row(
								children: [
									Expanded(child: _summaryCard('Total Spend', '₹${c.totalSpend.toStringAsFixed(2)}', Icons.payments)),
									const SizedBox(width: 12),
									Expanded(child: _summaryCard('Last Visit', _fmtDate(c.lastVisit), Icons.event_available)),
								],
							),
							const SizedBox(height: 12),
							Card(
								child: Padding(
									padding: const EdgeInsets.all(12.0),
									child: Column(
										crossAxisAlignment: CrossAxisAlignment.start,
										children: [
											const Text('Preferences & Notes', style: TextStyle(fontWeight: FontWeight.bold)),
											const SizedBox(height: 8),
											TextField(controller: prefsCtrl, decoration: const InputDecoration(labelText: 'Preferences'), maxLines: 2),
											const SizedBox(height: 8),
											TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Notes'), maxLines: 3),
											const SizedBox(height: 8),
											SwitchListTile(
												value: c.smsOptIn,
												onChanged: (v) => setState(() => c = c.copyWith(smsOptIn: v)),
												title: const Text('SMS Marketing Consent'),
											),
											SwitchListTile(
												value: c.emailOptIn,
												onChanged: (v) => setState(() => c = c.copyWith(emailOptIn: v)),
												title: const Text('Email Marketing Consent'),
											),
										],
									),
								),
							),
							const SizedBox(height: 12),
							Card(
								child: Padding(
									padding: const EdgeInsets.all(12.0),
									child: Column(
										crossAxisAlignment: CrossAxisAlignment.start,
										children: [
											const Text('Purchase History', style: TextStyle(fontWeight: FontWeight.bold)),
											const SizedBox(height: 8),
											SingleChildScrollView(
												scrollDirection: Axis.horizontal,
												child: DataTable(
													columns: const [
														DataColumn(label: Text('Date')),
														DataColumn(label: Text('Product')),
														DataColumn(label: Text('Amount')),
													],
													rows: [
														for (final p in c.history)
															DataRow(
																cells: [
																	DataCell(Text(_fmtDate(p.date))),
																	DataCell(Text(p.product)),
																	DataCell(Text('₹${p.amount.toStringAsFixed(2)}')),
																],
															),
													],
												),
											),
										],
									),
								),
							),
						],
					),
				),
			),
		);
	}

	Widget _summaryCard(String title, String value, IconData icon) => Card(child: ListTile(leading: Icon(icon), title: Text(title), subtitle: Text(value, style: const TextStyle(fontWeight: FontWeight.bold))));
}

class _QuickAddCustomerForm extends StatefulWidget { @override State<_QuickAddCustomerForm> createState() => _QuickAddCustomerFormState(); }
class _QuickAddCustomerFormState extends State<_QuickAddCustomerForm> {
	final _formKey = GlobalKey<FormState>(); final nameCtrl = TextEditingController(); final phoneCtrl = TextEditingController(); final emailCtrl = TextEditingController();
	@override void dispose() { nameCtrl.dispose(); phoneCtrl.dispose(); emailCtrl.dispose(); super.dispose(); }
	@override Widget build(BuildContext context) { return Padding(padding: const EdgeInsets.all(16.0), child: Form(key: _formKey, child: Column(mainAxisSize: MainAxisSize.min, children: [Text('Add Customer', style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: 8), TextFormField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter name' : null), TextFormField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Phone'), keyboardType: TextInputType.phone, validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter phone' : null), TextFormField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Email'), keyboardType: TextInputType.emailAddress, validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter email' : null), const SizedBox(height: 12), Row(mainAxisAlignment: MainAxisAlignment.end, children: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), const SizedBox(width: 8), ElevatedButton(onPressed: () { if (_formKey.currentState!.validate()) { final now = DateTime.now(); final c = CrmCustomer(id: UniqueKey().toString(), name: nameCtrl.text.trim(), phone: phoneCtrl.text.trim(), email: emailCtrl.text.trim(), status: LoyaltyStatus.bronze, totalSpend: 0, lastVisit: now, preferences: '', notes: '', smsOptIn: false, emailOptIn: false, history: [],); Navigator.pop(context, c); } }, child: const Text('Add')) ])] ) )); }
}

// Data & Utilities
enum LoyaltyStatus { bronze, silver, gold }
extension LoyaltyStatusX on LoyaltyStatus { String get label => switch (this) { LoyaltyStatus.bronze => 'Bronze', LoyaltyStatus.silver => 'Silver', LoyaltyStatus.gold => 'Gold' }; }
enum LoyaltyFilter { all, bronze, silver, gold }
extension LoyaltyFilterX on LoyaltyFilter { LoyaltyStatus? get status => switch (this) { LoyaltyFilter.bronze => LoyaltyStatus.bronze, LoyaltyFilter.silver => LoyaltyStatus.silver, LoyaltyFilter.gold => LoyaltyStatus.gold, LoyaltyFilter.all => null, }; }

class PurchaseRecord { final DateTime date; final String product; final double amount; const PurchaseRecord({required this.date, required this.product, required this.amount}); }
class CrmCustomer {
	final String id; final String name; final String phone; final String email; final LoyaltyStatus status; final double totalSpend; final DateTime lastVisit; final String preferences; final String notes; final bool smsOptIn; final bool emailOptIn; final List<PurchaseRecord> history;
	CrmCustomer({required this.id, required this.name, required this.phone, required this.email, required this.status, required this.totalSpend, required this.lastVisit, required this.preferences, required this.notes, required this.smsOptIn, required this.emailOptIn, required this.history});
	CrmCustomer copy() => copyWith();
	CrmCustomer copyWith({String? id, String? name, String? phone, String? email, LoyaltyStatus? status, double? totalSpend, DateTime? lastVisit, String? preferences, String? notes, bool? smsOptIn, bool? emailOptIn, List<PurchaseRecord>? history,}) => CrmCustomer(id: id ?? this.id, name: name ?? this.name, phone: phone ?? this.phone, email: email ?? this.email, status: status ?? this.status, totalSpend: totalSpend ?? this.totalSpend, lastVisit: lastVisit ?? this.lastVisit, preferences: preferences ?? this.preferences, notes: notes ?? this.notes, smsOptIn: smsOptIn ?? this.smsOptIn, emailOptIn: emailOptIn ?? this.emailOptIn, history: history ?? this.history);
	String get initials { final parts = name.split(' ').where((e) => e.isNotEmpty).toList(); if (parts.isEmpty) return '?'; if (parts.length == 1) return parts.first[0].toUpperCase(); return (parts[0][0] + parts[1][0]).toUpperCase(); }
}

List<CrmCustomer> _seedCustomers() { final now = DateTime.now(); return [
	CrmCustomer(id: 'c1', name: 'Rahul Sharma', phone: '+91 98765 43210', email: 'rahul@example.com', status: LoyaltyStatus.gold, totalSpend: 24500.50, lastVisit: now.subtract(const Duration(days: 3)), preferences: 'Prefers home care products', notes: 'Allergic to certain fragrances', smsOptIn: true, emailOptIn: true, history: [PurchaseRecord(date: DateTime(2025, 9, 1), product: 'Detergent Pack', amount: 799.0), PurchaseRecord(date: DateTime(2025, 8, 22), product: 'Hair Oil', amount: 299.0), PurchaseRecord(date: DateTime(2025, 8, 10), product: 'Groceries', amount: 2150.0)],),
	CrmCustomer(id: 'c2', name: 'Priya Singh', phone: '+91 91234 56789', email: 'priya@example.com', status: LoyaltyStatus.silver, totalSpend: 11230.00, lastVisit: now.subtract(const Duration(days: 7)), preferences: 'Loves snacks and beverages', notes: 'Ask about new tea varieties', smsOptIn: true, emailOptIn: false, history: [PurchaseRecord(date: DateTime(2025, 9, 5), product: 'Green Tea', amount: 450.0), PurchaseRecord(date: DateTime(2025, 8, 30), product: 'Cookies', amount: 199.0)],),
	CrmCustomer(id: 'c3', name: 'Amit Verma', phone: '+91 99870 12345', email: 'amit@example.com', status: LoyaltyStatus.bronze, totalSpend: 3500.75, lastVisit: now.subtract(const Duration(days: 15)), preferences: 'Budget-friendly items', notes: 'Prefers weekend shopping', smsOptIn: false, emailOptIn: true, history: [PurchaseRecord(date: DateTime(2025, 8, 12), product: 'Soap Pack', amount: 150.0)],),
	CrmCustomer(id: 'c4', name: 'Neha Kapoor', phone: '+91 98123 45678', email: 'neha@example.com', status: LoyaltyStatus.silver, totalSpend: 8620.00, lastVisit: now.subtract(const Duration(days: 2)), preferences: 'Organic products', notes: 'Responds well to SMS offers', smsOptIn: true, emailOptIn: false, history: [PurchaseRecord(date: DateTime(2025, 9, 12), product: 'Organic Honey', amount: 399.0)],),
	CrmCustomer(id: 'c5', name: 'Sanjay Mehta', phone: '+91 90000 11111', email: 'sanjay@example.com', status: LoyaltyStatus.gold, totalSpend: 18750.25, lastVisit: now.subtract(const Duration(days: 1)), preferences: 'Personal care and grooming', notes: 'Likes combo offers', smsOptIn: true, emailOptIn: true, history: [PurchaseRecord(date: DateTime(2025, 9, 10), product: 'Shaving Kit', amount: 1250.0)],),
]; }

Widget _loyaltyChip(LoyaltyStatus status) { Color color; switch (status) { case LoyaltyStatus.bronze: color = Colors.brown; break; case LoyaltyStatus.silver: color = Colors.blueGrey; break; case LoyaltyStatus.gold: color = Colors.amber; break; } return Chip(label: Text(status.label), backgroundColor: color.withValues(alpha: 0.15)); }
String _csv(String s) => '"${s.replaceAll('"', '""')}"';
String _fmtDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
