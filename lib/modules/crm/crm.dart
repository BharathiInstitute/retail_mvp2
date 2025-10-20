import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../core/app_keys.dart';

// CRM: List customers from Firestore with search/filter, add, edit, and delete.

class CrmListScreen extends StatefulWidget {
	const CrmListScreen({super.key});

	@override
	State<CrmListScreen> createState() => _CrmListScreenState();
}

class _CrmListScreenState extends State<CrmListScreen> {
	String query = '';
	LoyaltyFilter loyaltyFilter = LoyaltyFilter.all;

	Stream<List<CrmCustomer>> _customerStream() {
		final col = FirebaseFirestore.instance.collection('customers');
		// Order by name if available; otherwise map and sort client-side.
		return col.snapshots().map((s) {
			final list = s.docs.map((d) => CrmCustomer.fromDoc(d)).toList();
			list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
			return list;
		});
	}

	List<CrmCustomer> _applyFilters(List<CrmCustomer> input) {
		final q = query.trim().toLowerCase();
		return input.where((c) {
			final matchesQuery = q.isEmpty ||
					c.name.toLowerCase().contains(q) ||
					c.phone.toLowerCase().contains(q) ||
					c.email.toLowerCase().contains(q);
			final matchesLoyalty =
					loyaltyFilter == LoyaltyFilter.all || loyaltyFilter.status == c.status;
			return matchesQuery && matchesLoyalty;
		}).toList();
	}

	void _showCsvDialog(String csv) {
		final dlgCtx = rootNavigatorKey.currentContext;
		if (dlgCtx == null) return;
		showDialog(
			context: dlgCtx,
			builder: (_) => AlertDialog(
				title: const Text('Export CSV'),
				content: SizedBox(width: 600, child: SingleChildScrollView(child: Text(csv))),
				actions: const [CloseButton()],
			),
		);
	}

	Future<void> _exportCsv() async {
		final snap = await FirebaseFirestore.instance.collection('customers').get();
		final list = snap.docs.map((d) => CrmCustomer.fromDoc(d)).toList()
			..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
		final header = 'Name,Phone,Email,Loyalty,TotalSpend,LastVisit';
		final rows = list.map((c) =>
				'${_csv(c.name)},${_csv(c.phone)},${_csv(c.email)},${c.status.label},${c.totalSpend.toStringAsFixed(2)},${_fmtDate(c.lastVisit)}');
		final csv = ([header, ...rows]).join('\n');
		// Show in a separate helper to avoid context-after-await lint
		_showCsvDialog(csv);
	}

	Future<void> _quickAddCustomer() async {
				final messenger = scaffoldMessengerKey.currentState;
				final bsCtx = rootNavigatorKey.currentContext; if (bsCtx == null) return;
				final newCustomer = await showModalBottomSheet<CrmCustomer>(
			context: bsCtx,
			isScrollControlled: true,
			builder: (dialogCtx) => Padding(
				padding: EdgeInsets.only(bottom: MediaQuery.of(dialogCtx).viewInsets.bottom),
				child: const _QuickAddCustomerForm(),
			),
		);
			if (newCustomer != null) {
				messenger?.showSnackBar(SnackBar(content: Text('Customer ${newCustomer.name} added')));
			}
	}

	Future<void> _editCustomer(CrmCustomer c) async {
				final messenger = scaffoldMessengerKey.currentState;
				final bsCtx2 = rootNavigatorKey.currentContext; if (bsCtx2 == null) return;
				final edited = await showModalBottomSheet<CrmCustomer>(
			context: bsCtx2,
			isScrollControlled: true,
			builder: (dialogCtx) => Padding(
				padding: EdgeInsets.only(bottom: MediaQuery.of(dialogCtx).viewInsets.bottom),
				child: _EditCustomerForm(customer: c),
			),
		);
			if (edited != null) {
				messenger?.showSnackBar(SnackBar(content: Text('Customer ${edited.name} updated')));
			}
	}

	Future<void> _deleteCustomer(CrmCustomer c) async {
		if (!mounted) return;
		bool deleting = false;
			final rootMessenger = scaffoldMessengerKey.currentState;
			final dlgRoot = rootNavigatorKey.currentContext; if (dlgRoot == null) return;
			final confirm = await showDialog<bool>(
			context: dlgRoot,
			barrierDismissible: !deleting,
			builder: (dialogCtx) => StatefulBuilder(
				builder: (dialogCtx, setLocal) {
												return PopScope(
							canPop: !deleting,
													onPopInvokedWithResult: (didPop, result) {},
							child: AlertDialog(
							title: const Text('Delete Customer'),
							content: Column(
								mainAxisSize: MainAxisSize.min,
								children: [
									Text('Are you sure you want to delete "${c.name}"?'),
									if (deleting) const Padding(padding: EdgeInsets.only(top:12), child: LinearProgressIndicator(minHeight: 3)),
								],
							),
							actions: [
								TextButton(onPressed: deleting ? null : () => Navigator.pop(dialogCtx, false), child: const Text('Cancel')),
								FilledButton.tonal(
																		onPressed: deleting ? null : () async {
										setLocal(() => deleting = true);
										try {
											// Ensure we are authenticated (anonymous if necessary) so rules allow delete.
											final auth = FirebaseAuth.instance;
											if (auth.currentUser == null) { await auth.signInAnonymously(); }
											if (c.id.isEmpty) { throw Exception('Missing document id'); }
																					await FirebaseFirestore.instance.collection('customers').doc(c.id).delete();
																					rootNavigatorKey.currentState?.pop(true);
										} catch (e) {
																					// Use global messenger to avoid using dialog context after awaits
																					scaffoldMessengerKey.currentState?.showSnackBar(
																							SnackBar(content: Text(e.toString().contains('permission-denied')
																									? 'Permission denied deleting customer.'
																									: 'Delete failed: $e')),
																					);
										} finally {
																					if (dialogCtx.mounted) setLocal(() => deleting = false);
										}
									},
									child: deleting ? const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)) : const Text('Delete'),
								),
							],
						),
					);
				},
			),
		);
		if (confirm == true && mounted) {
			rootMessenger?.showSnackBar(SnackBar(content: Text('Deleted ${c.name}')));
		}
	}

	@override
	Widget build(BuildContext context) {
		final listPanel = Card(
			child: Column(
				children: [
					Padding(
						padding: const EdgeInsets.all(12.0),
						child: Wrap(
							spacing: 8,
							runSpacing: 8,
							crossAxisAlignment: WrapCrossAlignment.center,
							children: [
								SizedBox(
									width: 280,
									child: TextField(
										decoration: const InputDecoration(
											prefixIcon: Icon(Icons.search),
											labelText: 'Search (name, phone, email)',
										),
										onChanged: (v) => setState(() => query = v),
									),
								),
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
								ElevatedButton.icon(
									onPressed: _quickAddCustomer,
									icon: const Icon(Icons.person_add),
									label: const Text('Add Customer'),
								),
								OutlinedButton.icon(
									onPressed: _exportCsv,
									icon: const Icon(Icons.file_download),
									label: const Text('Export CSV'),
								),
							],
						),
					),
					const Divider(height: 1),
					Expanded(
						child: StreamBuilder<List<CrmCustomer>>(
							stream: _customerStream(),
							builder: (context, snapshot) {
								if (snapshot.hasError) {
									return Center(child: Text('Error: ${snapshot.error}'));
								}
								if (!snapshot.hasData) {
									return const Center(
										child: Padding(
											padding: EdgeInsets.all(24.0),
											child: CircularProgressIndicator(),
										),
									);
								}
								final list = _applyFilters(snapshot.data!);
								if (list.isEmpty) return const Center(child: Text('No customers'));
								return Scrollbar(
									thumbVisibility: true,
									child: ListView.separated(
										itemCount: list.length,
										separatorBuilder: (_, __) => const Divider(height: 1),
										itemBuilder: (_, i) {
											final c = list[i];
											return ListTile(
												onTap: () => _editCustomer(c.copy()),
												onLongPress: () => _deleteCustomer(c),
												leading: CircleAvatar(child: Text(c.initials)),
												title: Row(
													children: [
														Expanded(child: Text(c.name)),
														_loyaltyChip(c.status),
													],
												),
												subtitle: Text('${c.email} • ${c.phone}'),
												trailing: Column(
													mainAxisAlignment: MainAxisAlignment.center,
													crossAxisAlignment: CrossAxisAlignment.end,
													children: [
														Text('₹${c.totalSpend.toStringAsFixed(2)}'),
														Text('Last: ${_fmtDate(c.lastVisit)}', style: const TextStyle(fontSize: 12)),
													],
												),
											);
										},
									),
								);
							},
						),
					),
				],
			),
		);

		return Padding(padding: const EdgeInsets.all(12), child: listPanel);
	}
}

// Add form
class _QuickAddCustomerForm extends StatefulWidget {
	const _QuickAddCustomerForm();
	@override
	State<_QuickAddCustomerForm> createState() => _QuickAddCustomerFormState();
}

class _QuickAddCustomerFormState extends State<_QuickAddCustomerForm> {
	final _formKey = GlobalKey<FormState>();
	final nameCtrl = TextEditingController();
	final phoneCtrl = TextEditingController();
	final emailCtrl = TextEditingController();
	bool _saving = false;

	@override
	void dispose() {
		nameCtrl.dispose();
		phoneCtrl.dispose();
		emailCtrl.dispose();
		super.dispose();
	}

	Future<void> _submit() async {
		if (!_formKey.currentState!.validate()) return;
		setState(() => _saving = true);
		try {
			final auth = FirebaseAuth.instance;
			if (auth.currentUser == null) {
				await auth.signInAnonymously();
			}

			final now = DateTime.now();
			final data = {
				'name': nameCtrl.text.trim(),
				'phone': phoneCtrl.text.trim(),
				'email': emailCtrl.text.trim(),
				'status': 'bronze',
				'totalSpend': 0.0,
				'lastVisit': Timestamp.fromDate(now),
				'preferences': '',
				'notes': '',
				'smsOptIn': false,
				'emailOptIn': false,
				'createdAt': FieldValue.serverTimestamp(),
				'updatedAt': FieldValue.serverTimestamp(),
			};
			final doc = await FirebaseFirestore.instance.collection('customers').add(data);

			final created = CrmCustomer(
				id: doc.id,
				name: data['name'] as String,
				phone: data['phone'] as String,
				email: data['email'] as String,
				status: LoyaltyStatus.bronze,
				totalSpend: 0.0,
				loyaltyPoints: 0.0,
				lastVisit: now,
				preferences: '',
				notes: '',
				smsOptIn: false,
				emailOptIn: false,
				history: const [],
			);
			if (mounted) Navigator.pop(context, created);
		} catch (e) {
			if (!mounted) return;
			final msg = e.toString().contains('permission-denied')
					? 'Permission denied. Make sure Firestore rules are deployed and Anonymous sign-in is enabled.'
					: 'Failed to add customer: $e';
			ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
		} finally {
			if (mounted) setState(() => _saving = false);
		}
	}

	@override
	Widget build(BuildContext context) {
		return Padding(
			padding: const EdgeInsets.all(16.0),
			child: Form(
				key: _formKey,
				child: Column(
					mainAxisSize: MainAxisSize.min,
					children: [
						Text('Add Customer', style: Theme.of(context).textTheme.titleMedium),
						const SizedBox(height: 8),
						TextFormField(
							controller: nameCtrl,
							decoration: const InputDecoration(labelText: 'Name'),
							validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter name' : null,
						),
						TextFormField(
							controller: phoneCtrl,
							decoration: const InputDecoration(labelText: 'Phone'),
							keyboardType: TextInputType.phone,
							validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter phone' : null,
						),
						TextFormField(
							controller: emailCtrl,
							decoration: const InputDecoration(labelText: 'Email'),
							keyboardType: TextInputType.emailAddress,
							validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter email' : null,
						),
						const SizedBox(height: 12),
						Row(
							mainAxisAlignment: MainAxisAlignment.end,
							children: [
								TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
								const SizedBox(width: 8),
								ElevatedButton(
									onPressed: _saving ? null : _submit,
									child: _saving
											? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
											: const Text('Add'),
								),
							],
						),
					],
				),
			),
		);
	}
}

// Edit form (upsert)
class _EditCustomerForm extends StatefulWidget {
	final CrmCustomer customer;
	const _EditCustomerForm({required this.customer});
	@override
	State<_EditCustomerForm> createState() => _EditCustomerFormState();
}

class _EditCustomerFormState extends State<_EditCustomerForm> {
	final _formKey = GlobalKey<FormState>();
	late final TextEditingController nameCtrl;
	late final TextEditingController phoneCtrl;
	late final TextEditingController emailCtrl;
	bool _saving = false;

	@override
	void initState() {
		super.initState();
		final c = widget.customer;
		nameCtrl = TextEditingController(text: c.name);
		phoneCtrl = TextEditingController(text: c.phone);
		emailCtrl = TextEditingController(text: c.email);
	}

	@override
	void dispose() {
		nameCtrl.dispose();
		phoneCtrl.dispose();
		emailCtrl.dispose();
		super.dispose();
	}

	Future<void> _submit() async {
		if (!_formKey.currentState!.validate()) return;
		setState(() => _saving = true);
		try {
			final auth = FirebaseAuth.instance;
			if (auth.currentUser == null) {
				await auth.signInAnonymously();
			}

			final customers = FirebaseFirestore.instance.collection('customers');
			final id = widget.customer.id.isNotEmpty ? widget.customer.id : null;
			final docRef = id != null ? customers.doc(id) : customers.doc();
			await docRef.set({
				'name': nameCtrl.text.trim(),
				'phone': phoneCtrl.text.trim(),
				'email': emailCtrl.text.trim(),
				// Loyalty status intentionally not editable here; keep existing value.
				'updatedAt': FieldValue.serverTimestamp(),
				if (id == null) 'createdAt': FieldValue.serverTimestamp(),
			}, SetOptions(merge: true));

			final updated = widget.customer.copyWith(
				id: docRef.id,
				name: nameCtrl.text.trim(),
				phone: phoneCtrl.text.trim(),
				email: emailCtrl.text.trim(),
				// status unchanged
			);
			if (mounted) Navigator.pop(context, updated);
		} catch (e) {
			if (!mounted) return;
			final msg = e.toString().contains('permission-denied')
					? 'Permission denied. Ensure rules are deployed and Anonymous sign-in is enabled.'
					: 'Failed to update customer: $e';
			ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
		} finally {
			if (mounted) setState(() => _saving = false);
		}
	}

	@override
	Widget build(BuildContext context) {
		return Padding(
			padding: const EdgeInsets.all(16.0),
			child: Form(
				key: _formKey,
				child: Column(
					mainAxisSize: MainAxisSize.min,
					children: [
						Text('Edit Customer', style: Theme.of(context).textTheme.titleMedium),
						const SizedBox(height: 8),
						TextFormField(
							controller: nameCtrl,
							decoration: const InputDecoration(labelText: 'Name'),
							validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter name' : null,
						),
						TextFormField(
							controller: phoneCtrl,
							decoration: const InputDecoration(labelText: 'Phone'),
							keyboardType: TextInputType.phone,
							validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter phone' : null,
						),
						TextFormField(
							controller: emailCtrl,
							decoration: const InputDecoration(labelText: 'Email'),
							keyboardType: TextInputType.emailAddress,
							validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter email' : null,
						),
						const SizedBox(height: 8),
						// Loyalty status display (read-only)
						Align(
							alignment: Alignment.centerLeft,
							child: Text('Loyalty: ${widget.customer.status.label}', style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic)),
						),
						const SizedBox(height: 12),
						Row(
							mainAxisAlignment: MainAxisAlignment.end,
							children: [
								TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
								const SizedBox(width: 8),
								ElevatedButton(
									onPressed: _saving ? null : _submit,
									child: _saving
											? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
											: const Text('Update'),
								),
							],
						),
					],
				),
			),
		);
	}
}

// Data & utilities
enum LoyaltyStatus { bronze, silver, gold }

extension LoyaltyStatusX on LoyaltyStatus {
	String get label => switch (this) {
				LoyaltyStatus.bronze => 'Bronze',
				LoyaltyStatus.silver => 'Silver',
				LoyaltyStatus.gold => 'Gold',
			};
}

enum LoyaltyFilter { all, bronze, silver, gold }

extension LoyaltyFilterX on LoyaltyFilter {
	LoyaltyStatus? get status => switch (this) {
				LoyaltyFilter.bronze => LoyaltyStatus.bronze,
				LoyaltyFilter.silver => LoyaltyStatus.silver,
				LoyaltyFilter.gold => LoyaltyStatus.gold,
				LoyaltyFilter.all => null,
			};
}

class PurchaseRecord {
	final DateTime date;
	final String product;
	final double amount;
	const PurchaseRecord({required this.date, required this.product, required this.amount});
}

class CrmCustomer {
	final String id;
	final String name;
	final String phone;
	final String email;
	final LoyaltyStatus status;
	final double totalSpend;
	final double loyaltyPoints; // added for consistency with POS
	final DateTime lastVisit;
	final String preferences;
	final String notes;
	final bool smsOptIn;
	final bool emailOptIn;
	final List<PurchaseRecord> history;

	CrmCustomer({
		required this.id,
		required this.name,
		required this.phone,
		required this.email,
		required this.status,
		required this.totalSpend,
		required this.loyaltyPoints,
		required this.lastVisit,
		required this.preferences,
		required this.notes,
		required this.smsOptIn,
		required this.emailOptIn,
		required this.history,
	});

	factory CrmCustomer.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
		final data = doc.data() ?? <String, dynamic>{};
		final statusStr = (data['status'] as String?)?.toLowerCase() ?? 'bronze';
		LoyaltyStatus parseStatus(String s) {
			switch (s) {
				case 'gold':
					return LoyaltyStatus.gold;
				case 'silver':
					return LoyaltyStatus.silver;
				default:
					return LoyaltyStatus.bronze;
			}
		}

		double toDouble(dynamic v) {
			if (v is num) return v.toDouble();
			if (v is String) return double.tryParse(v) ?? 0.0;
			return 0.0;
		}

		DateTime parseDate(dynamic v) {
			if (v is Timestamp) return v.toDate();
			if (v is DateTime) return v;
			return DateTime.fromMillisecondsSinceEpoch(0);
		}

		final hist = <PurchaseRecord>[]; // Not persisted yet

		return CrmCustomer(
			id: doc.id,
			name: (data['name'] as String?)?.trim().isNotEmpty == true ? (data['name'] as String).trim() : 'Unnamed',
			phone: (data['phone'] as String?)?.trim() ?? '',
			email: (data['email'] as String?)?.trim() ?? '',
			status: parseStatus(statusStr),
			totalSpend: toDouble(data['totalSpend']),
			loyaltyPoints: toDouble(data['loyaltyPoints']),
			lastVisit: parseDate(data['lastVisit']),
			preferences: (data['preferences'] as String?) ?? '',
			notes: (data['notes'] as String?) ?? '',
			smsOptIn: (data['smsOptIn'] as bool?) ?? false,
			emailOptIn: (data['emailOptIn'] as bool?) ?? false,
			history: hist,
		);
	}

	CrmCustomer copy() => copyWith();

	CrmCustomer copyWith({
		String? id,
		String? name,
		String? phone,
		String? email,
		LoyaltyStatus? status,
		double? totalSpend,
		double? loyaltyPoints,
		DateTime? lastVisit,
		String? preferences,
		String? notes,
		bool? smsOptIn,
		bool? emailOptIn,
		List<PurchaseRecord>? history,
	}) {
		return CrmCustomer(
			id: id ?? this.id,
			name: name ?? this.name,
			phone: phone ?? this.phone,
			email: email ?? this.email,
			status: status ?? this.status,
			totalSpend: totalSpend ?? this.totalSpend,
			loyaltyPoints: loyaltyPoints ?? this.loyaltyPoints,
			lastVisit: lastVisit ?? this.lastVisit,
			preferences: preferences ?? this.preferences,
			notes: notes ?? this.notes,
			smsOptIn: smsOptIn ?? this.smsOptIn,
			emailOptIn: emailOptIn ?? this.emailOptIn,
			history: history ?? this.history,
		);
	}

	String get initials {
		final parts = name.split(' ').where((e) => e.isNotEmpty).toList();
		if (parts.isEmpty) return '?';
		if (parts.length == 1) return parts.first[0].toUpperCase();
		return (parts[0][0] + parts[1][0]).toUpperCase();
	}
}

Widget _loyaltyChip(LoyaltyStatus status) {
	Color color;
	switch (status) {
		case LoyaltyStatus.bronze:
			color = Colors.brown;
			break;
		case LoyaltyStatus.silver:
			color = Colors.blueGrey;
			break;
		case LoyaltyStatus.gold:
			color = Colors.amber;
			break;
	}
		return Chip(label: Text(status.label), backgroundColor: color.withValues(alpha: 0.15));
}

String _csv(String s) => '"${s.replaceAll('"', '""')}"';
String _fmtDate(DateTime d) =>
		'${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

