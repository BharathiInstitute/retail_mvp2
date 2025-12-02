import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/theme/theme_extension_helpers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../modules/stores/providers.dart';
import 'package:retail_mvp2/core/firestore_store_collections.dart';
import '../../core/global_navigator_keys.dart';
import '../../core/paging/infinite_scroll_controller.dart';
import '../../core/loading/page_loading_state_widget.dart';
import '../../core/firebase/firestore_pagination_helper.dart';

// CRM: List customers from Firestore with search/filter, add, edit, and delete.

// Provider that watches store changes and recreates the pager automatically
final crmCustomersPagedProvider = ChangeNotifierProvider.autoDispose<PagedListController<CrmCustomer>>((ref) {
  final storeId = ref.watch(selectedStoreIdProvider);
  
  final Query<Map<String, dynamic>>? base =
      (storeId == null) ? null : StoreRefs.of(storeId).customers().orderBy('name');

  final controller = PagedListController<CrmCustomer>(
    pageSize: 50,
    loadPage: (cursor) async {
      if (base == null) {
        return (<CrmCustomer>[], null);
      }
      final (items, next) = await fetchFirestorePage<CrmCustomer>(
        base: base,
        after: cursor as DocumentSnapshot<Map<String, dynamic>>?,
        pageSize: 50,
        map: (doc) => CrmCustomer.fromDoc(doc),
      );
      return (items, next);
    },
  );

  Future.microtask(controller.resetAndLoad);
  ref.onDispose(controller.dispose);
  return controller;
});

class CrmListScreen extends ConsumerStatefulWidget {
	const CrmListScreen({super.key});

	@override
	ConsumerState<CrmListScreen> createState() => _CrmListScreenState();
}

class _CrmListScreenState extends ConsumerState<CrmListScreen> {
	String query = '';
	LoyaltyFilter loyaltyFilter = LoyaltyFilter.all;
	final ScrollController _scrollCtrl = ScrollController();
	Timer? _searchDebounce;

	@override
	void initState() {
		super.initState();
		_scrollCtrl.addListener(_maybeLoadMore);
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

	@override
	void dispose() {
		_scrollCtrl.dispose();
		_searchDebounce?.cancel();
		super.dispose();
	}

	void _maybeLoadMore() {
		if (!_scrollCtrl.hasClients) return;
		if (_scrollCtrl.position.extentAfter < 600) {
			ref.read(crmCustomersPagedProvider).loadMore();
		}
	}

	void _onSearchChangedDebounced(String v) {
		setState(() => query = v);
		_searchDebounce?.cancel();
		_searchDebounce = Timer(const Duration(milliseconds: 300), () {
			ref.read(crmCustomersPagedProvider).resetAndLoad();
		});
	}

	void _showCsvDialog(String csv) {
		final dlgCtx = rootNavigatorKey.currentContext;
		if (dlgCtx == null) return;
		showDialog(
			context: dlgCtx,
			builder: (_) => AlertDialog(
				title: Text('Export CSV', style: context.texts.titleMedium?.copyWith(color: context.colors.onSurface, fontWeight: FontWeight.w700)),
				content: DefaultTextStyle(
					style: (context.texts.bodyMedium ?? const TextStyle()).copyWith(color: context.colors.onSurface),
					child: SizedBox(width: 600, child: SingleChildScrollView(child: Text(csv))),
				),
				actions: const [CloseButton()],
			),
		);
	}

	Future<void> _exportCsv() async {
		final storeId = ref.read(selectedStoreIdProvider);
		if (storeId == null) return;
		final snap = await StoreRefs.of(storeId).customers().get();
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
				final storeId = ref.read(selectedStoreIdProvider);
				if (storeId == null) {
					messenger?.showSnackBar(const SnackBar(content: Text('No store selected')));
					return;
				}
				final newCustomer = await showModalBottomSheet<CrmCustomer>(
			context: bsCtx,
			isScrollControlled: true,
			builder: (dialogCtx) => Padding(
				padding: EdgeInsets.only(bottom: MediaQuery.of(dialogCtx).viewInsets.bottom),
				child: _QuickAddCustomerForm(storeId: storeId),
			),
		);
			if (newCustomer != null) {
				messenger?.showSnackBar(SnackBar(content: Text('Customer ${newCustomer.name} added')));
			}
	}

	Future<void> _editCustomer(CrmCustomer c) async {
				final messenger = scaffoldMessengerKey.currentState;
				final bsCtx2 = rootNavigatorKey.currentContext; if (bsCtx2 == null) return;
				final storeId = ref.read(selectedStoreIdProvider);
				if (storeId == null) {
					messenger?.showSnackBar(const SnackBar(content: Text('No store selected')));
					return;
				}
				final edited = await showModalBottomSheet<CrmCustomer>(
			context: bsCtx2,
			isScrollControlled: true,
			builder: (dialogCtx) => Padding(
				padding: EdgeInsets.only(bottom: MediaQuery.of(dialogCtx).viewInsets.bottom),
				child: _EditCustomerForm(customer: c, storeId: storeId),
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
							title: Text('Delete Customer', style: context.texts.titleMedium?.copyWith(color: context.colors.onSurface, fontWeight: FontWeight.w700)),
							content: DefaultTextStyle(
								style: (context.texts.bodyMedium ?? const TextStyle()).copyWith(color: context.colors.onSurface),
								child: Column(
								mainAxisSize: MainAxisSize.min,
								children: [
									Text('Are you sure you want to delete "${c.name}"?'),
									if (deleting) const Padding(padding: EdgeInsets.only(top:12), child: LinearProgressIndicator(minHeight: 3)),
								],
							),
							),
							actions: [
								TextButton(onPressed: deleting ? null : () => Navigator.pop(dialogCtx, false), child: const Text('Cancel')),
								FilledButton(
									style: FilledButton.styleFrom(backgroundColor: context.colors.error, foregroundColor: context.colors.onError),
									onPressed: deleting ? null : () async {
										setLocal(() => deleting = true);
										try {
											// Ensure we are authenticated (anonymous if necessary) so rules allow delete.
											final auth = FirebaseAuth.instance;
											if (auth.currentUser == null) { await auth.signInAnonymously(); }
											if (c.id.isEmpty) { throw Exception('Missing document id'); }
																			final storeId = ref.read(selectedStoreIdProvider);
																			if (storeId == null) { throw Exception('No store selected'); }
																						await StoreRefs.of(storeId).customers().doc(c.id).delete();
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
		final cs = Theme.of(context).colorScheme;
		final isMobile = MediaQuery.of(context).size.width < 560;
		
		return Container(
			decoration: BoxDecoration(
				gradient: LinearGradient(
					begin: Alignment.topCenter,
					end: Alignment.bottomCenter,
					colors: [cs.primary.withOpacity(0.04), cs.surface],
					stops: const [0.0, 0.3],
				),
			),
			child: Padding(
				padding: EdgeInsets.all(isMobile ? 8 : 12),
				child: Column(children: [
					// Modern search/action bar
					Container(
						padding: EdgeInsets.symmetric(horizontal: context.sizes.gapMd, vertical: context.sizes.gapSm),
						decoration: BoxDecoration(
							color: cs.surface,
							borderRadius: context.radiusMd,
							border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
						),
						child: SingleChildScrollView(
							scrollDirection: Axis.horizontal,
							child: Row(children: [
								// Search field
								Container(
									width: isMobile ? 200 : 260,
									height: context.sizes.inputHeightSm,
									decoration: BoxDecoration(
										color: cs.surfaceContainerHighest.withOpacity(0.4),
										borderRadius: context.radiusSm,
									),
									child: TextField(
										style: TextStyle(fontSize: context.sizes.fontSm, color: cs.onSurface),
										decoration: InputDecoration(
											prefixIcon: Icon(Icons.search_rounded, size: context.sizes.iconSm, color: cs.onSurfaceVariant),
											hintText: 'Search (name, phone, email)',
											hintStyle: TextStyle(fontSize: context.sizes.fontXs, color: cs.onSurfaceVariant),
											isDense: true,
											border: InputBorder.none,
											contentPadding: EdgeInsets.symmetric(vertical: context.sizes.gapSm),
										),
										onChanged: _onSearchChangedDebounced,
									),
								),
								SizedBox(width: context.sizes.gapSm),
								// Loyalty filter dropdown
								Container(
									height: context.sizes.inputHeightSm,
									padding: EdgeInsets.symmetric(horizontal: context.sizes.gapSm),
									decoration: BoxDecoration(
										color: cs.surfaceContainerHighest.withOpacity(0.4),
										borderRadius: context.radiusSm,
									),
									child: DropdownButtonHideUnderline(
										child: DropdownButton<LoyaltyFilter>(
												value: loyaltyFilter,
												style: TextStyle(fontSize: context.sizes.fontSm, color: cs.onSurface),
											dropdownColor: cs.surface,
											iconSize: 18,
											iconEnabledColor: cs.onSurfaceVariant,
											items: const [
												DropdownMenuItem(value: LoyaltyFilter.all, child: Text('All')),
												DropdownMenuItem(value: LoyaltyFilter.bronze, child: Text('Bronze')),
												DropdownMenuItem(value: LoyaltyFilter.silver, child: Text('Silver')),
												DropdownMenuItem(value: LoyaltyFilter.gold, child: Text('Gold')),
											],
											onChanged: (v) => setState(() => loyaltyFilter = v ?? LoyaltyFilter.all),
										),
									),
								),
								const SizedBox(width: 10),
								// Add Customer button
								_ModernActionButton(
									icon: Icons.person_add_rounded,
									label: 'Add Customer',
									color: cs.primary,
									onTap: _quickAddCustomer,
								),
								context.gapHSm,
								// Export button
								_ModernActionButton(
									icon: Icons.download_rounded,
									label: 'Export CSV',
									color: cs.secondary,
									onTap: _exportCsv,
									outlined: true,
								),
							]),
						),
					),
					SizedBox(height: context.sizes.gapSm),
					// Customer list
					Expanded(
						child: Container(
							decoration: BoxDecoration(
								color: cs.surface,
								borderRadius: context.radiusMd,
								border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
							),
							child: ClipRRect(
								borderRadius: context.radiusMd,
								child: Builder(builder: (context) {
									final pager = ref.watch(crmCustomersPagedProvider);
									final state = pager.state;
									final list = _applyFilters(state.items);
									return PageLoaderOverlay(
										loading: state.items.isEmpty && state.loading,
										error: state.items.isEmpty ? state.error : null,
										onRetry: () => ref.read(crmCustomersPagedProvider).resetAndLoad(),
											child: list.isEmpty
												? Center(child: Text('No customers', style: TextStyle(fontSize: context.sizes.fontSm, color: cs.onSurfaceVariant)))
											: ListView.builder(
													controller: _scrollCtrl,
													itemCount: list.length,
													itemBuilder: (_, i) => _ModernCustomerTile(
														customer: list[i],
														onTap: () => _editCustomer(list[i].copy()),
														onLongPress: () => _deleteCustomer(list[i]),
														isEven: i.isEven,
													),
												),
									);
								}),
							),
						),
					),
				]),
			),
		);
	}
}

// Add form
class _QuickAddCustomerForm extends StatefulWidget {
	final String storeId;
	const _QuickAddCustomerForm({required this.storeId});
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
			final doc = await StoreRefs.of(widget.storeId).customers().add(data);

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
												Text(
													'Add Customer',
													style: (context.texts.titleMedium ?? const TextStyle()).copyWith(
														color: context.colors.onSurface,
														fontWeight: FontWeight.w600,
													),
												),
						context.gapVSm,
												TextFormField(
													controller: nameCtrl,
													style: (context.texts.bodyMedium ?? const TextStyle()).copyWith(color: context.colors.onSurface),
													decoration: InputDecoration(
														labelText: 'Name',
														labelStyle: (context.texts.bodySmall ?? const TextStyle()).copyWith(color: context.colors.onSurfaceVariant),
														hintStyle: (context.texts.bodySmall ?? const TextStyle()).copyWith(color: context.colors.onSurfaceVariant),
													),
													validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter name' : null,
												),
												TextFormField
												(
													controller: phoneCtrl,
													style: (context.texts.bodyMedium ?? const TextStyle()).copyWith(color: context.colors.onSurface),
													decoration: InputDecoration(
														labelText: 'Phone',
														labelStyle: (context.texts.bodySmall ?? const TextStyle()).copyWith(color: context.colors.onSurfaceVariant),
														hintStyle: (context.texts.bodySmall ?? const TextStyle()).copyWith(color: context.colors.onSurfaceVariant),
													),
													keyboardType: TextInputType.phone,
													validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter phone' : null,
												),
												TextFormField(
													controller: emailCtrl,
													style: (context.texts.bodyMedium ?? const TextStyle()).copyWith(color: context.colors.onSurface),
													decoration: InputDecoration(
														labelText: 'Email',
														labelStyle: (context.texts.bodySmall ?? const TextStyle()).copyWith(color: context.colors.onSurfaceVariant),
														hintStyle: (context.texts.bodySmall ?? const TextStyle()).copyWith(color: context.colors.onSurfaceVariant),
													),
													keyboardType: TextInputType.emailAddress,
													validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter email' : null,
												),
						context.gapVMd,
						Row(
							mainAxisAlignment: MainAxisAlignment.end,
							children: [
								TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
								context.gapHSm,
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
	final String storeId;
	const _EditCustomerForm({required this.customer, required this.storeId});
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

			final customers = StoreRefs.of(widget.storeId).customers();
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
												Text(
													'Edit Customer',
													style: (context.texts.titleMedium ?? const TextStyle()).copyWith(
														color: context.colors.onSurface,
														fontWeight: FontWeight.w600,
													),
												),
						context.gapVSm,
												TextFormField(
													controller: nameCtrl,
													style: (context.texts.bodyMedium ?? const TextStyle()).copyWith(color: context.colors.onSurface),
													decoration: InputDecoration(
														labelText: 'Name',
														labelStyle: (context.texts.bodySmall ?? const TextStyle()).copyWith(color: context.colors.onSurfaceVariant),
														hintStyle: (context.texts.bodySmall ?? const TextStyle()).copyWith(color: context.colors.onSurfaceVariant),
													),
													validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter name' : null,
												),
												TextFormField(
													controller: phoneCtrl,
													style: (context.texts.bodyMedium ?? const TextStyle()).copyWith(color: context.colors.onSurface),
													decoration: InputDecoration(
														labelText: 'Phone',
														labelStyle: (context.texts.bodySmall ?? const TextStyle()).copyWith(color: context.colors.onSurfaceVariant),
														hintStyle: (context.texts.bodySmall ?? const TextStyle()).copyWith(color: context.colors.onSurfaceVariant),
													),
													keyboardType: TextInputType.phone,
													validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter phone' : null,
												),
												TextFormField(
													controller: emailCtrl,
													style: (context.texts.bodyMedium ?? const TextStyle()).copyWith(color: context.colors.onSurface),
													decoration: InputDecoration(
														labelText: 'Email',
														labelStyle: (context.texts.bodySmall ?? const TextStyle()).copyWith(color: context.colors.onSurfaceVariant),
														hintStyle: (context.texts.bodySmall ?? const TextStyle()).copyWith(color: context.colors.onSurfaceVariant),
													),
													keyboardType: TextInputType.emailAddress,
													validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter email' : null,
												),
						context.gapVSm,
						// Loyalty status display (read-only)
						Align(
							alignment: Alignment.centerLeft,
							child: Text(
								'Loyalty: ${widget.customer.status.label}',
								style: Theme.of(context).textTheme.labelSmall?.copyWith(fontStyle: FontStyle.italic),
							),
						),
						context.gapVMd,
						Row(
							mainAxisAlignment: MainAxisAlignment.end,
							children: [
								TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
								context.gapHSm,
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
	return Builder(builder: (context) {
		final cs = Theme.of(context).colorScheme;
		Color color;
		switch (status) {
			case LoyaltyStatus.bronze:
				color = const Color(0xFFCD7F32);
				break;
			case LoyaltyStatus.silver:
				color = const Color(0xFF808080);
				break;
			case LoyaltyStatus.gold:
				color = const Color(0xFFD4AF37);
				break;
		}
		return Builder(builder: (context) {
			final sizes = context.sizes;
			return Container(
				padding: EdgeInsets.symmetric(horizontal: sizes.gapSm, vertical: sizes.gapXs),
				decoration: BoxDecoration(
					color: color.withOpacity(0.12),
					borderRadius: context.radiusMd,
					border: Border.all(color: color.withOpacity(0.3)),
				),
				child: Text(status.label, style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w600, color: cs.onSurface)),
			);
		});
	});
}

// Modern action button widget
class _ModernActionButton extends StatelessWidget {
	final IconData icon;
	final String label;
	final Color color;
	final VoidCallback onTap;
	final bool outlined;
	const _ModernActionButton({required this.icon, required this.label, required this.color, required this.onTap, this.outlined = false});
	@override
	Widget build(BuildContext context) {
		final cs = Theme.of(context).colorScheme;
		final sizes = context.sizes;
		return Material(
			color: Colors.transparent,
			child: InkWell(
				onTap: onTap,
				borderRadius: context.radiusSm,
				child: Container(
					height: sizes.inputHeightSm,
					padding: EdgeInsets.symmetric(horizontal: sizes.gapMd),
					decoration: BoxDecoration(
						color: outlined ? Colors.transparent : color.withOpacity(0.1),
						borderRadius: context.radiusSm,
						border: Border.all(color: outlined ? cs.outlineVariant.withOpacity(0.5) : color.withOpacity(0.3)),
					),
					child: Row(mainAxisSize: MainAxisSize.min, children: [
						Icon(icon, size: sizes.iconSm, color: outlined ? cs.onSurfaceVariant : color),
						SizedBox(width: sizes.gapSm),
						Text(label, style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w500, color: outlined ? cs.onSurface : color)),
					]),
				),
			),
		);
	}
}

// Modern customer tile widget
class _ModernCustomerTile extends StatelessWidget {
	final CrmCustomer customer;
	final VoidCallback onTap;
	final VoidCallback onLongPress;
	final bool isEven;
	const _ModernCustomerTile({required this.customer, required this.onTap, required this.onLongPress, required this.isEven});
	@override
	Widget build(BuildContext context) {
		final cs = Theme.of(context).colorScheme;
		final sizes = context.sizes;
		final c = customer;
		return Material(
			color: isEven ? Colors.transparent : cs.surfaceContainerHighest.withOpacity(0.2),
			child: InkWell(
				onTap: onTap,
				onLongPress: onLongPress,
				child: Padding(
					padding: EdgeInsets.symmetric(horizontal: sizes.gapMd, vertical: sizes.gapSm),
					child: Row(children: [
						// Avatar
						Container(
							width: 36,
							height: 36,
							decoration: BoxDecoration(
								color: cs.primary.withOpacity(0.1),
								borderRadius: context.radiusSm,
							),
							child: Center(child: Text(c.initials, style: TextStyle(fontSize: sizes.fontSm, fontWeight: FontWeight.w600, color: cs.primary))),
						),
						SizedBox(width: sizes.gapMd),
						// Name & contact info
						Expanded(
							child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
								Text(c.name, style: TextStyle(fontSize: sizes.fontSm, fontWeight: FontWeight.w600, color: cs.onSurface)),
								SizedBox(height: sizes.gapXs),
								Text('${c.email} • ${c.phone}', style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurfaceVariant), overflow: TextOverflow.ellipsis),
							]),
						),
						SizedBox(width: sizes.gapMd),
						// Loyalty badge
						_loyaltyChip(c.status),
						SizedBox(width: sizes.gapMd),
						// Spend & last visit
						Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
							Text('₹${c.totalSpend.toStringAsFixed(2)}', style: TextStyle(fontSize: sizes.fontSm, fontWeight: FontWeight.w600, color: cs.onSurface)),
							const SizedBox(height: 2),
							Text('Last: ${_fmtDate(c.lastVisit)}', style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurfaceVariant)),
						]),
					]),
				),
			),
		);
	}
}

String _csv(String s) => '"${s.replaceAll('"', '""')}"';
String _fmtDate(DateTime d) =>
		'${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

