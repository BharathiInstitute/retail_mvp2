import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:retail_mvp2/core/permissions.dart';

class PermissionsTab extends ConsumerStatefulWidget {
  const PermissionsTab({super.key});
  @override
  ConsumerState<PermissionsTab> createState() => _PermissionsTabState();
}

class _PermissionsTabState extends ConsumerState<PermissionsTab> {
  String? _selectedUserId;
  Map<String, Map<String, bool>> _working = {};
  bool _saving = false;
  bool _selectedIsOwner = false;

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

  Map<String, Map<String, bool>> _allTrue() {
    final map = <String, Map<String, bool>>{};
    for (final row in _rows) {
      map[row.key] = {'view': true, 'create': true, 'edit': true, 'delete': true};
    }
    return map;
  }

  Future<void> _loadPerms(String uid) async {
    // Check role first
    final userSnap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final role = (userSnap.data()?['role'] ?? '') as String;
    final isOwner = role == 'owner';
    if (isOwner) {
      setState(() { _selectedIsOwner = true; _working = _allTrue(); });
      return;
    }

    final doc = await FirebaseFirestore.instance.collection('user_permissions').doc(uid).get();
    final data = doc.data();
    final modules = (data?['modules'] as Map<String, dynamic>?) ?? {};
    final map = <String, Map<String, bool>>{};
    for (final row in _rows) {
      final v = modules[row.key] as Map<String, dynamic>?;
      map[row.key] = {
        'view': v?['view'] == true,
        'create': v?['create'] == true,
        'edit': v?['edit'] == true,
        'delete': v?['delete'] == true,
      };
    }
    setState(() { _selectedIsOwner = false; _working = map; });
  }

  Future<void> _save() async {
    if (_selectedUserId == null || _selectedIsOwner) return; // owner immutable
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('user_permissions').doc(_selectedUserId).set({
        'modules': _working,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permissions saved')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _set(String key, String action, bool value, {bool viewOnly = false}) {
    final row = _working[key] ?? {'view': false, 'create': false, 'edit': false, 'delete': false};
    if (action == 'view') {
      row['view'] = value;
      if (!value) {
        row['create'] = false;
        row['edit'] = false;
        row['delete'] = false;
      }
    } else {
      if (value) row['view'] = true; // auto enable view when others set
      row[action] = value;
    }
    if (viewOnly) {
      row['create'] = false; row['edit'] = false; row['delete'] = false;
    }
    setState(() => _working[key] = row);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: _UserPicker(
              onSelected: (uid) {
                setState(() => _selectedUserId = uid);
                _loadPerms(uid);
              },
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: _selectedUserId == null || _saving || _selectedIsOwner ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save'),
          ),
        ]),
        const SizedBox(height: 16),
        if (_selectedUserId == null)
          const Text('Select a user to edit permissions')
        else ...[
          if (_selectedIsOwner)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                const Icon(Icons.verified_user, color: Colors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Selected user is Owner. Owner has full access by default. Boxes are shown checked and cannot be edited.',
                    style: TextStyle(color: Theme.of(context).colorScheme.primary),
                  ),
                ),
              ]),
            ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Screen')),
                  DataColumn(label: Text('View')),
                  DataColumn(label: Text('Create')),
                  DataColumn(label: Text('Edit')),
                  DataColumn(label: Text('Delete')),
                ],
                rows: [
                  for (final r in _rows)
                    DataRow(cells: [
                      DataCell(Text(r.label)),
                      DataCell(Checkbox(
                        value: _working[r.key]?['view'] ?? false,
                        onChanged: _selectedIsOwner
                            ? null
                            : (v) => _set(r.key, 'view', v ?? false, viewOnly: r.viewOnly),
                      )),
                      DataCell(Checkbox(
                        value: _working[r.key]?['create'] ?? false,
                        onChanged: _selectedIsOwner
                            ? null
                            : (r.viewOnly
                                ? null
                                : (_working[r.key]?['view'] == true
                                    ? (v) => _set(r.key, 'create', v ?? false)
                                    : null)),
                      )),
                      DataCell(Checkbox(
                        value: _working[r.key]?['edit'] ?? false,
                        onChanged: _selectedIsOwner
                            ? null
                            : (r.viewOnly
                                ? null
                                : (_working[r.key]?['view'] == true
                                    ? (v) => _set(r.key, 'edit', v ?? false)
                                    : null)),
                      )),
                      DataCell(Checkbox(
                        value: _working[r.key]?['delete'] ?? false,
                        onChanged: _selectedIsOwner
                            ? null
                            : (r.viewOnly
                                ? null
                                : (_working[r.key]?['view'] == true
                                    ? (v) => _set(r.key, 'delete', v ?? false)
                                    : null)),
                      )),
                    ])
                ],
              ),
            ),
          ),
        ]
      ],
    );
  }
}

class _UserPicker extends StatelessWidget {
  final void Function(String uid) onSelected;
  const _UserPicker({required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Text('Error loading users: ${snap.error}', style: const TextStyle(color: Colors.red));
        }
        if (!snap.hasData) return const LinearProgressIndicator(minHeight: 2);
        final items = snap.data!.docs;
        if (items.isEmpty) {
          return const Text('No users found');
        }
        return DropdownButtonFormField<String>(
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Select user'),
          items: [
            for (final d in items)
              (){
                final m = d.data();
                final display = (m['displayName'] as String?)?.trim();
                final email = (m['email'] as String?)?.trim();
                final primary = (display != null && display.isNotEmpty)
                    ? display
                    : (email != null && email.isNotEmpty)
                        ? email
                        : d.id;
                final secondary = (email != null && email.isNotEmpty && email != primary) ? email : null;
                return DropdownMenuItem(
                  value: d.id,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(primary),
                      if (secondary != null)
                        Text(
                          secondary,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                );
              }()
          ],
          onChanged: (v) {
            if (v != null) onSelected(v);
          },
        );
      },
    );
  }
}

class _ScreenRow {
  final String label;
  final String key;
  final bool viewOnly;
  const _ScreenRow(this.label, this.key, {this.viewOnly = false});
}

