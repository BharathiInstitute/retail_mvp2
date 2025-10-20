import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:retail_mvp2/core/permissions.dart';
import 'permissions_tab.dart' show permissionsEditTargetUserIdProvider;

class PermissionsOverviewTab extends ConsumerStatefulWidget {
  const PermissionsOverviewTab({super.key});

  @override
  ConsumerState<PermissionsOverviewTab> createState() => _PermissionsOverviewTabState();
}

/// Standalone page wrapper for Admin overview route
class PermissionsOverviewPage extends ConsumerWidget {
  const PermissionsOverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin')),
      body: const Padding(
        padding: EdgeInsets.all(16),
        child: PermissionsOverviewTab(),
      ),
    );
  }
}

class _PermissionsOverviewTabState extends ConsumerState<PermissionsOverviewTab> {
  final ScrollController _hCtrl = ScrollController();
  final ScrollController _vCtrl = ScrollController();

  static const _rows = <_ScreenRow>[
    _ScreenRow('Dashboard', ScreenKeys.dashboard, viewOnly: false),
    _ScreenRow('POS Main', ScreenKeys.posMain),
    _ScreenRow('POS Cashier', ScreenKeys.posCashier),
    _ScreenRow('Inventory (Products)', ScreenKeys.invProducts),
    _ScreenRow('Stock Movements', ScreenKeys.invStockMovements),
    _ScreenRow('Transfers', ScreenKeys.invTransfers),
    _ScreenRow('Suppliers', ScreenKeys.invSuppliers),
    _ScreenRow('Alerts', ScreenKeys.invAlerts),
    _ScreenRow('Audit', ScreenKeys.invAudit),
    _ScreenRow('Sales Invoices', ScreenKeys.invSales),
    _ScreenRow('Purchase Invoices', ScreenKeys.invPurchases),
    _ScreenRow('CRM', ScreenKeys.crm),
    _ScreenRow('Accounting', ScreenKeys.accounting, viewOnly: true),
    _ScreenRow('Loyalty', ScreenKeys.loyalty),
    _ScreenRow('Loyalty Settings', ScreenKeys.loyaltySettings),
    _ScreenRow('Admin', ScreenKeys.admin),
  ];

  @override
  void dispose() {
    _hCtrl.dispose();
    _vCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('Permissions Overview', style: Theme.of(context).textTheme.titleMedium),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, usersSnap) {
              if (usersSnap.hasError) {
                return Center(child: Text('Error loading users: ${usersSnap.error}'));
              }
              if (!usersSnap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final users = usersSnap.data!.docs;
              if (users.isEmpty) return const Center(child: Text('No users found'));

              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance.collection('user_permissions').snapshots(),
                builder: (context, permsSnap) {
                  if (permsSnap.hasError) {
                    return Center(child: Text('Error loading permissions: ${permsSnap.error}'));
                  }
                  final Map<String, Map<String, dynamic>> permsDocs = {
                    for (final d in (permsSnap.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]))
                      d.id: d.data(),
                  };

                  // Precompute user headers
                  final userHeaders = users.map((u) {
                    final ud = u.data();
                    final displayName = (ud['displayName'] as String?)?.trim() ?? '';
                    final email = (ud['email'] as String?)?.trim() ?? '';
                    final primary = displayName.isNotEmpty ? displayName : (email.isNotEmpty ? email : u.id);
                    final role = (ud['role'] as String?)?.trim() ?? '';
                    return _UserHeader(id: u.id, label: primary, role: role, email: email);
                  }).toList();

                  // Layout constants (slightly tighter)
                  const double actionColWidth = 140;
                  const double userColWidth = 120;
                  final double totalWidth = actionColWidth + userHeaders.length * userColWidth;

                  // Page-level vertical Scrollbar on right using PrimaryScrollController; shared horizontal controller for header/body
                  return PrimaryScrollController(
                    controller: _vCtrl,
                    child: Scrollbar(
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        padding: EdgeInsets.zero,
                        child: SingleChildScrollView(
                          controller: _hCtrl,
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: totalWidth,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                              // Top user header
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    SizedBox(width: actionColWidth, child: Text('Action', style: Theme.of(context).textTheme.labelLarge)),
                                    for (final u in userHeaders)
                                      SizedBox(
                                        width: userColWidth,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(u.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelLarge),
                                                ),
                                                IconButton(
                                                  tooltip: 'Edit permissions',
                                                  icon: const Icon(Icons.edit_outlined, size: 18),
                                                  onPressed: () {
                                                    // Set target user ID and switch to Edit tab (index 1)
                                                    ref.read(permissionsEditTargetUserIdProvider.notifier).state = u.id;
                                                    // Navigate to standalone edit screen
                                                    GoRouter.of(context).go('/admin/permissions-edit');
                                                  },
                                                ),
                                              ],
                                            ),
                                            if (u.role.isNotEmpty)
                                              Text(u.role, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                                            if (u.email.isNotEmpty)
                                              Text(u.email, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              // Cards body (no inner vertical scroll)
                              for (final row in _rows)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Card(
                                    elevation: 0,
                                    clipBehavior: Clip.antiAlias,
                                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(row.label, style: Theme.of(context).textTheme.titleSmall),
                                          const SizedBox(height: 6),
                                          _ModuleMatrix(
                                            row: row,
                                            userHeaders: userHeaders,
                                            permsDocs: permsDocs,
                                            actionColWidth: actionColWidth,
                                            userColWidth: userColWidth,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ModuleMatrix extends StatelessWidget {
  final _ScreenRow row;
  final List<_UserHeader> userHeaders;
  final Map<String, Map<String, dynamic>> permsDocs; // uid -> permissions doc data
  final double actionColWidth;
  final double userColWidth;
  const _ModuleMatrix({required this.row, required this.userHeaders, required this.permsDocs, required this.actionColWidth, required this.userColWidth});

  @override
  Widget build(BuildContext context) {
    // Header row with a fixed Action column then one column per user
    // Only the body rows; header is rendered once at the top.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _permRow(context, 'Access to View', (v) => v.view),
        _permRow(context, 'Access to Create', (v) => v.create),
        _permRow(context, 'Access to Edit', (v) => v.edit),
        _permRow(context, 'Access to Delete', (v) => v.delete),
      ],
    );
  }

  Widget _permRow(BuildContext context, String label, bool Function(_ResolvedPerm) pick) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: actionColWidth, child: Text(label)),
          for (final u in userHeaders)
            SizedBox(
              width: userColWidth,
              child: AbsorbPointer(
                child: Checkbox(
                  value: pick(_resolve(u)),
                  onChanged: null, // view-only
                ),
              ),
            ),
        ],
      ),
    );
  }

  _ResolvedPerm _resolve(_UserHeader u) {
    final isOwner = u.role == 'owner';
    if (isOwner) return const _ResolvedPerm(true, true, true, true);
    final module = (permsDocs[u.id]?['modules'] as Map<String, dynamic>?) ?? const {};
    final v = (module[row.key] as Map<String, dynamic>?) ?? const {};
    final view = v['view'] == true;
    final create = row.viewOnly ? false : (v['create'] == true) && view;
    final edit = row.viewOnly ? false : (v['edit'] == true) && view;
    final del = row.viewOnly ? false : (v['delete'] == true) && view;
    return _ResolvedPerm(view, create, edit, del);
  }
}

class _ResolvedPerm {
  final bool view;
  final bool create;
  final bool edit;
  final bool delete;
  const _ResolvedPerm(this.view, this.create, this.edit, this.delete);
}

class _UserHeader {
  final String id;
  final String label;
  final String role;
  final String email;
  const _UserHeader({required this.id, required this.label, required this.role, required this.email});
}

class _ScreenRow {
  final String label;
  final String key;
  final bool viewOnly;
  const _ScreenRow(this.label, this.key, {this.viewOnly = false});
}
