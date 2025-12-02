import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:retail_mvp2/core/user_permissions_provider.dart';
import 'package:retail_mvp2/core/theme/theme_extension_helpers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PermissionsTab extends ConsumerStatefulWidget {
  const PermissionsTab({super.key});
  @override
  ConsumerState<PermissionsTab> createState() => _PermissionsTabState();
}

/// When set to a userId, Permissions (Edit) tab should load that user's permissions
/// and select them automatically.
final permissionsEditTargetUserIdProvider = StateProvider<String?>((ref) => null);

class _PermissionsTabState extends ConsumerState<PermissionsTab> {
  String? _selectedUserId;
  String? _selectedUserName;
  String? _selectedUserEmail;
  Map<String, Map<String, bool>> _working = {};
  bool _saving = false;
  bool _selectedIsOwner = false;
  bool _forcedTarget = false; // when navigating from Overview, lock editing to that user

  static const _rows = <_ScreenRow>[
    _ScreenRow('Dashboard', ScreenKeys.dashboard, viewOnly: false),
    _ScreenRow('POS Main', ScreenKeys.posMain),
    _ScreenRow('POS Cashier', ScreenKeys.posCashier),
    _ScreenRow('Inventory (Products)', ScreenKeys.invProducts),
    _ScreenRow('Stock Movements', ScreenKeys.invStockMovements),
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
    // Populate selected user display/email for header
    final display = (userSnap.data()?['displayName'] as String?)?.trim();
    final email = (userSnap.data()?['email'] as String?)?.trim();
    final primary = (display != null && display.isNotEmpty)
        ? display
        : ((email != null && email.isNotEmpty) ? email : uid);
    setState(() { _selectedUserName = primary; _selectedUserEmail = email; });
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
    final cs = Theme.of(context).colorScheme;
    final sizes = context.sizes;
    // Watch for cross-tab triggers
    final targetUid = ref.watch(permissionsEditTargetUserIdProvider);
    if (targetUid != null && targetUid != _selectedUserId) {
      // Kick off load once and clear the target to avoid loops
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        setState(() { _selectedUserId = targetUid; _forcedTarget = true; });
        await _loadPerms(targetUid);
      });
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Modern action bar
        Container(
          padding: EdgeInsets.symmetric(horizontal: sizes.gapMd, vertical: sizes.gapSm),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: context.radiusMd,
            border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
          ),
          child: Row(children: [
            Expanded(
              child: _forcedTarget
                  ? _FixedUserHeader(name: _selectedUserName ?? 'User', email: _selectedUserEmail)
                  : _UserPicker(
                      selectedUid: _selectedUserId,
                      onSelected: (uid) {
                        setState(() => _selectedUserId = uid);
                        _loadPerms(uid);
                      },
                    ),
            ),
            if (_forcedTarget) ...[
              context.gapHSm,
              _ModernPermButton(
                icon: Icons.swap_horiz_rounded,
                label: 'Change user',
                color: cs.secondary,
                outlined: true,
                onTap: () {
                  ref.read(permissionsEditTargetUserIdProvider.notifier).state = null;
                  setState(() { _forcedTarget = false; });
                },
              ),
            ],
            const SizedBox(width: 10),
            _ModernPermButton(
              icon: Icons.save_rounded,
              label: 'Save',
              color: cs.primary,
              onTap: _selectedUserId == null || _saving || _selectedIsOwner ? null : _save,
            ),
          ]),
        ),
        SizedBox(height: sizes.gapMd),
        if (_selectedUserId == null)
          Center(child: Text('Select a user to edit permissions', style: TextStyle(fontSize: sizes.fontSm, color: cs.onSurfaceVariant)))
        else ...[
          if (_selectedIsOwner)
            Container(
              margin: EdgeInsets.only(bottom: sizes.gapSm),
              padding: EdgeInsets.all(sizes.gapSm),
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.08),
                borderRadius: context.radiusSm,
                border: Border.all(color: cs.primary.withOpacity(0.2)),
              ),
              child: Row(children: [
                Icon(Icons.verified_user_rounded, size: sizes.iconSm, color: cs.primary),
                SizedBox(width: sizes.gapSm),
                Expanded(
                  child: Text(
                    'Selected user is Owner. Owner has full access by default. Boxes are shown checked and cannot be edited.',
                    style: TextStyle(fontSize: sizes.fontXs, color: cs.primary),
                  ),
                ),
              ]),
            ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: context.radiusMd,
                border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
              ),
              child: ClipRRect(
                borderRadius: context.radiusMd,
                child: Scrollbar(
                  thumbVisibility: true,
                  trackVisibility: true,
                  interactive: true,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: _ModernPermissionsTable(
                      rows: _rows,
                      working: _working,
                      isOwner: _selectedIsOwner,
                      onSet: _set,
                    ),
                  ),
                ),
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
  final String? selectedUid;
  const _UserPicker({required this.onSelected, this.selectedUid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Text(
            'Error loading users: ${snap.error}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          );
        }
        if (!snap.hasData) return const LinearProgressIndicator(minHeight: 2);
        final items = snap.data!.docs;
        if (items.isEmpty) {
          return const Text('No users found');
        }
        // Removed unused variable 'ids'
        // Removed unused variable 'currentValue'
        return DropdownButtonFormField<String>(
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Select user'),
          // initialValue removed (unsupported)
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

class _FixedUserHeader extends StatelessWidget {
  final String name;
  final String? email;
  const _FixedUserHeader({required this.name, this.email});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sizes = context.sizes;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: sizes.gapSm, vertical: sizes.gapSm),
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(0.06),
        borderRadius: context.radiusSm,
        border: Border.all(color: cs.primary.withOpacity(0.2)),
      ),
      child: Row(children: [
        Icon(Icons.lock_rounded, size: sizes.iconSm, color: cs.primary),
        SizedBox(width: sizes.gapSm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(name, style: TextStyle(fontSize: sizes.fontSm, fontWeight: FontWeight.w600, color: cs.primary)),
            if (email != null && email!.isNotEmpty)
              Text(email!, style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurfaceVariant)),
          ]),
        ),
        Container(
          padding: EdgeInsets.symmetric(horizontal: sizes.gapSm, vertical: sizes.gapXs),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withOpacity(0.5),
            borderRadius: BorderRadius.circular(sizes.radiusSm),
          ),
          child: Text('Locked', style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurfaceVariant)),
        ),
      ]),
    );
  }
}

/// Standalone page for /admin/permissions-edit
class AdminPermissionsEditPage extends StatelessWidget {
  const AdminPermissionsEditPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sizes = context.sizes;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Permissions (Edit)', style: TextStyle(fontSize: sizes.fontMd, fontWeight: FontWeight.w600, color: cs.onSurface)),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [cs.primary.withOpacity(0.04), cs.surface],
            stops: const [0.0, 0.3],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(sizes.gapMd),
          child: const PermissionsTab(),
        ),
      ),
    );
  }
}

// Modern permission button widget
class _ModernPermButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool outlined;
  const _ModernPermButton({required this.icon, required this.label, required this.color, this.onTap, this.outlined = false});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sizes = context.sizes;
    final disabled = onTap == null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: context.radiusSm,
        child: Container(
          height: sizes.buttonHeightSm,
          padding: EdgeInsets.symmetric(horizontal: sizes.gapSm),
          decoration: BoxDecoration(
            color: disabled ? cs.surfaceContainerHighest.withOpacity(0.3) : (outlined ? Colors.transparent : color.withOpacity(0.1)),
            borderRadius: context.radiusSm,
            border: Border.all(color: disabled ? cs.outlineVariant.withOpacity(0.3) : (outlined ? cs.outlineVariant.withOpacity(0.5) : color.withOpacity(0.3))),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: sizes.iconSm, color: disabled ? cs.onSurfaceVariant.withOpacity(0.5) : (outlined ? cs.onSurfaceVariant : color)),
            SizedBox(width: sizes.gapXs),
            Text(label, style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w500, color: disabled ? cs.onSurfaceVariant.withOpacity(0.5) : (outlined ? cs.onSurface : color))),
          ]),
        ),
      ),
    );
  }
}

// Modern permissions table widget
class _ModernPermissionsTable extends StatelessWidget {
  final List<_ScreenRow> rows;
  final Map<String, Map<String, bool>> working;
  final bool isOwner;
  final void Function(String key, String action, bool value, {bool viewOnly}) onSet;
  const _ModernPermissionsTable({required this.rows, required this.working, required this.isOwner, required this.onSet});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sizes = context.sizes;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Header row
      Container(
        padding: EdgeInsets.symmetric(horizontal: sizes.gapMd, vertical: sizes.gapSm),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withOpacity(0.3),
        ),
        child: Row(children: [
          SizedBox(width: 160, child: Text('Screen', style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant))),
          SizedBox(width: 80, child: Center(child: Text('View', style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)))),
          SizedBox(width: 80, child: Center(child: Text('Create', style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)))),
          SizedBox(width: 80, child: Center(child: Text('Edit', style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)))),
          SizedBox(width: 80, child: Center(child: Text('Delete', style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)))),
        ]),
      ),
      // Data rows
      for (int i = 0; i < rows.length; i++)
        _buildRow(context, rows[i], i.isEven),
    ]);
  }

  Widget _buildRow(BuildContext context, _ScreenRow r, bool isEven) {
    final cs = Theme.of(context).colorScheme;
    final sizes = context.sizes;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: sizes.gapMd, vertical: sizes.gapXs),
      color: isEven ? Colors.transparent : cs.surfaceContainerHighest.withOpacity(0.15),
      child: Row(children: [
        SizedBox(width: 160, child: Text(r.label, style: TextStyle(fontSize: sizes.fontSm, color: cs.onSurface))),
        SizedBox(width: 80, child: Center(child: _MiniCheckbox(
          value: working[r.key]?['view'] ?? false,
          onChanged: isOwner ? null : (v) => onSet(r.key, 'view', v ?? false, viewOnly: r.viewOnly),
        ))),
        SizedBox(width: 80, child: Center(child: _MiniCheckbox(
          value: working[r.key]?['create'] ?? false,
          onChanged: isOwner ? null : (r.viewOnly ? null : (working[r.key]?['view'] == true ? (v) => onSet(r.key, 'create', v ?? false, viewOnly: false) : null)),
        ))),
        SizedBox(width: 80, child: Center(child: _MiniCheckbox(
          value: working[r.key]?['edit'] ?? false,
          onChanged: isOwner ? null : (r.viewOnly ? null : (working[r.key]?['view'] == true ? (v) => onSet(r.key, 'edit', v ?? false, viewOnly: false) : null)),
        ))),
        SizedBox(width: 80, child: Center(child: _MiniCheckbox(
          value: working[r.key]?['delete'] ?? false,
          onChanged: isOwner ? null : (r.viewOnly ? null : (working[r.key]?['view'] == true ? (v) => onSet(r.key, 'delete', v ?? false, viewOnly: false) : null)),
        ))),
      ]),
    );
  }
}

class _MiniCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool?>? onChanged;
  const _MiniCheckbox({required this.value, this.onChanged});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final disabled = onChanged == null;
    return SizedBox(
      width: 20,
      height: 20,
      child: Checkbox(
        value: value,
        onChanged: onChanged,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        side: BorderSide(color: disabled ? cs.outlineVariant.withOpacity(0.5) : cs.primary.withOpacity(0.5), width: 1.5),
      ),
    );
  }
}

