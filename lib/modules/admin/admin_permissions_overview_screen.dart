import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:retail_mvp2/core/user_permissions_provider.dart';
import 'admin_permissions_screen.dart' show permissionsEditTargetUserIdProvider;
import 'package:retail_mvp2/core/theme/theme_config_and_providers.dart';
import 'package:retail_mvp2/core/theme/font_preference_controller.dart';
import 'package:retail_mvp2/core/theme/theme_extension_helpers.dart';
import 'package:retail_mvp2/modules/stores/providers.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
    final cs = Theme.of(context).colorScheme;
    final sizes = context.sizes;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Admin', style: TextStyle(fontSize: sizes.fontMd, fontWeight: FontWeight.w600, color: cs.onSurface)),
        actions: [
          _ModernAdminButton(
            icon: Icons.palette_rounded,
            label: 'Appearance',
            color: cs.primary,
            onTap: () async {
              await showDialog(context: context, builder: (_) => const _ThemeFontSettingsDialog());
            },
          ),
          SizedBox(width: sizes.gapMd),
        ],
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
          child: const PermissionsOverviewTab(),
        ),
      ),
    );
  }
}

class _ThemeFontSettingsDialog extends ConsumerStatefulWidget {
  const _ThemeFontSettingsDialog();
  @override
  ConsumerState<_ThemeFontSettingsDialog> createState() => _ThemeFontSettingsDialogState();
}

class _ThemeFontSettingsDialogState extends ConsumerState<_ThemeFontSettingsDialog> {
  late String _font;
  late ThemeMode _mode;

  @override
  void initState() {
    super.initState();
    _font = ref.read(fontProvider);
    _mode = ref.read(themeModeProvider);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sizes = context.sizes;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: context.radiusMd),
      child: Container(
        width: 360,
        padding: EdgeInsets.all(sizes.gapLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.palette_rounded, size: sizes.iconMd, color: cs.primary),
              SizedBox(width: sizes.gapSm),
              Text('Appearance Settings', style: TextStyle(fontSize: sizes.fontSm, fontWeight: FontWeight.w600, color: cs.onSurface)),
            ]),
            SizedBox(height: sizes.gapLg),
            Text('Theme', style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w500, color: cs.onSurfaceVariant)),
            SizedBox(height: sizes.gapSm),
            Row(children: [
              _ThemeOption(label: 'System', selected: _mode == ThemeMode.system, onTap: () => setState(() => _mode = ThemeMode.system)),
              SizedBox(width: sizes.gapSm),
              _ThemeOption(label: 'Light', selected: _mode == ThemeMode.light, onTap: () => setState(() => _mode = ThemeMode.light)),
              SizedBox(width: sizes.gapSm),
              _ThemeOption(label: 'Dark', selected: _mode == ThemeMode.dark, onTap: () => setState(() => _mode = ThemeMode.dark)),
            ]),
            SizedBox(height: sizes.gapMd),
            Text('Font', style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w500, color: cs.onSurfaceVariant)),
            SizedBox(height: sizes.gapSm),
            Container(
              height: sizes.inputHeightSm,
              padding: EdgeInsets.symmetric(horizontal: sizes.gapMd),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(0.4),
                borderRadius: context.radiusSm,
                border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _font,
                  isExpanded: true,
                  style: TextStyle(fontSize: sizes.fontSm, color: cs.onSurface),
                  dropdownColor: cs.surface,
                  iconSize: sizes.iconSm,
                  iconEnabledColor: cs.onSurfaceVariant,
                  onChanged: (v) => setState(() => _font = v ?? _font),
                  items: const [
                    DropdownMenuItem(value: 'inter', child: Text('Inter')),
                    DropdownMenuItem(value: 'roboto', child: Text('Roboto')),
                    DropdownMenuItem(value: 'poppins', child: Text('Poppins')),
                    DropdownMenuItem(value: 'montserrat', child: Text('Montserrat')),
                  ],
                ),
              ),
            ),
            SizedBox(height: sizes.gapLg),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Close', style: TextStyle(fontSize: sizes.fontSm, color: cs.onSurfaceVariant)),
              ),
              SizedBox(width: sizes.gapSm),
              _ModernAdminButton(
                icon: Icons.check_rounded,
                label: 'Apply',
                color: cs.primary,
                onTap: () async {
                  await ref.read(themeModeProvider.notifier).set(_mode);
                  await ref.read(fontProvider.notifier).set(_font);
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ]),
          ],
        ),
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
    final cs = Theme.of(context).colorScheme;
    final sizes = context.sizes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: sizes.gapMd, vertical: sizes.gapSm),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: context.radiusMd,
            border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
          ),
          child: Row(children: [
            Icon(Icons.admin_panel_settings_rounded, size: sizes.iconSm, color: cs.primary),
            SizedBox(width: sizes.gapSm),
            Text('Permissions Overview', style: TextStyle(fontSize: sizes.fontSm, fontWeight: FontWeight.w600, color: cs.onSurface)),
          ]),
        ),
        SizedBox(height: sizes.gapSm),
        Expanded(
          child: Builder(builder: (context) {
            final selStoreId = ref.watch(selectedStoreIdProvider);
            if (selStoreId == null || selStoreId.isEmpty) {
              return Center(
                child: Text(
                  'Select a store to view permissions',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                ),
              );
            }
            // Listen to active members of selected store
            final membersQ = FirebaseFirestore.instance
                .collection('store_users')
                .where('storeId', isEqualTo: selStoreId)
                .where('status', isEqualTo: 'active');
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: membersQ.snapshots(),
              builder: (context, mSnap) {
                if (mSnap.hasError) return Center(child: Text('Error loading members: ${mSnap.error}'));
                if (!mSnap.hasData) return const Center(child: CircularProgressIndicator());
                final mdocs = mSnap.data!.docs;
                if (mdocs.isEmpty) return const Center(child: Text('No users in this store'));

                // Build uid list and role-by-uid map
                final uidRole = <String, String>{
                  for (final d in mdocs) ((d.data()['userId'] ?? d.id) as String): ((d.data()['role'] ?? '') as String),
                };
                final uids = uidRole.keys.toList();

                Future<Map<String, QueryDocumentSnapshot<Map<String, dynamic>>>> fetchUsers() async {
                  final fs = FirebaseFirestore.instance;
                  final Map<String, QueryDocumentSnapshot<Map<String, dynamic>>> out = {};
                  // chunk whereIn (<=10)
                  for (var i = 0; i < uids.length; i += 10) {
                    final chunk = uids.sublist(i, i + 10 > uids.length ? uids.length : i + 10);
                    final snap = await fs.collection('users').where(FieldPath.documentId, whereIn: chunk).get();
                    for (final d in snap.docs) { out[d.id] = d; }
                  }
                  return out;
                }

                return FutureBuilder<Map<String, QueryDocumentSnapshot<Map<String, dynamic>>>>(
                  future: fetchUsers(),
                  builder: (context, uSnap) {
                    if (uSnap.hasError) return Center(child: Text('Error loading profiles: ${uSnap.error}'));
                    if (!uSnap.hasData) return const Center(child: CircularProgressIndicator());
                    final usersById = uSnap.data!;

                    // Precompute user headers from membership + profiles
                    final userHeaders = <_UserHeader>[];
                    for (final uid in uids) {
                      final role = (uidRole[uid] ?? '').trim();
                      final doc = usersById[uid];
                      String displayName = '';
                      String email = '';
                      if (doc != null) {
                        final ud = doc.data();
                        displayName = (ud['displayName'] as String?)?.trim() ?? '';
                        email = (ud['email'] as String?)?.trim() ?? '';
                      }
                      // Fallback to auth display/email when it's me
                      final me = FirebaseAuth.instance.currentUser;
                      if (email.isEmpty && me != null && me.uid == uid) {
                        email = (me.email ?? '').trim();
                      }
                      if (displayName.isEmpty && me != null && me.uid == uid) {
                        displayName = (me.displayName ?? '').trim();
                      }
                      final label = displayName.isNotEmpty ? displayName : (email.isNotEmpty ? email : uid);
                      userHeaders.add(_UserHeader(id: uid, label: label, role: role, email: email));
                    }

                    // Layout constants
                    const double actionColWidth = 160;
                    const double userColWidth = 150;
                    final double contentWidth = actionColWidth + userHeaders.length * userColWidth;

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

                        return LayoutBuilder(
                          builder: (context, constraints) {
                            // Use full width if content is smaller than available space
                            final double totalWidth = contentWidth < constraints.maxWidth ? constraints.maxWidth : contentWidth;
                            
                            return PrimaryScrollController(
                              controller: _vCtrl,
                              child: Scrollbar(
                                thumbVisibility: true,
                                child: SingleChildScrollView(
                                  padding: EdgeInsets.zero,
                                  child: Scrollbar(
                                    controller: _hCtrl,
                                    thumbVisibility: true,
                                    trackVisibility: true,
                                    interactive: true,
                                    scrollbarOrientation: ScrollbarOrientation.bottom,
                                    notificationPredicate: (notif) => notif.metrics.axis == Axis.horizontal,
                                    child: SingleChildScrollView(
                                      controller: _hCtrl,
                                      scrollDirection: Axis.horizontal,
                                      child: SizedBox(
                                        width: totalWidth,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            // Modern user header row
                                            Container(
                                              margin: EdgeInsets.only(bottom: sizes.gapMd),
                                              padding: EdgeInsets.symmetric(vertical: sizes.gapMd),
                                              decoration: BoxDecoration(
                                                color: cs.surface,
                                                borderRadius: context.radiusMd,
                                                border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
                                              ),
                                              child: Row(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  SizedBox(
                                                    width: actionColWidth,
                                                    child: Padding(
                                                      padding: EdgeInsets.only(left: sizes.gapMd, top: sizes.gapSm),
                                                      child: Text('Action', style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
                                                    ),
                                                  ),
                                                  for (final u in userHeaders)
                                                    _ModernUserColumn(user: u, width: userColWidth, ref: ref),
                                                ],
                                              ),
                                            ),
                                        for (final row in _rows)
                                          Container(
                                            margin: EdgeInsets.only(bottom: sizes.gapSm),
                                            decoration: BoxDecoration(
                                              color: cs.surfaceContainerHighest.withOpacity(0.4),
                                              borderRadius: context.radiusSm,
                                            ),
                                            child: Padding(
                                              padding: EdgeInsets.symmetric(horizontal: sizes.gapMd, vertical: sizes.gapSm),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(row.label, style: TextStyle(fontSize: sizes.fontSm, fontWeight: FontWeight.w600, color: cs.onSurface)),
                                                  SizedBox(height: sizes.gapSm),
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
                                        // Empty space at end for scroll padding
                                        const SizedBox(height: 120),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          }),
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
    final cs = Theme.of(context).colorScheme;
    final sizes = context.sizes;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: sizes.gapXs),
      child: Row(
        children: [
          SizedBox(width: actionColWidth, child: Text(label, style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurfaceVariant))),
          for (final u in userHeaders)
            SizedBox(
              width: userColWidth,
              child: Center(
                child: IgnorePointer(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: Checkbox(
                      value: pick(_resolve(u)),
                      onChanged: (_) {},
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      side: BorderSide(color: cs.outlineVariant, width: 1.5),
                    ),
                  ),
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

// Modern user column widget for header
class _ModernUserColumn extends ConsumerWidget {
  final _UserHeader user;
  final double width;
  final WidgetRef ref;
  const _ModernUserColumn({required this.user, required this.width, required this.ref});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final sizes = context.sizes;
    return Container(
      width: width,
      padding: EdgeInsets.symmetric(horizontal: sizes.gapSm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                user.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: sizes.fontSm, fontWeight: FontWeight.w600, color: cs.onSurface),
              ),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  ref.read(permissionsEditTargetUserIdProvider.notifier).state = user.id;
                  GoRouter.of(context).go('/admin/permissions-edit');
                },
                borderRadius: BorderRadius.circular(sizes.radiusSm),
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: cs.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(sizes.radiusSm),
                  ),
                  child: Icon(Icons.edit_rounded, size: sizes.iconSm, color: cs.primary),
                ),
              ),
            ),
          ]),
          SizedBox(height: sizes.gapXs),
          if (user.role.isNotEmpty)
            Container(
              padding: EdgeInsets.symmetric(horizontal: sizes.gapXs, vertical: 2),
              decoration: BoxDecoration(
                color: cs.secondary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(sizes.radiusSm),
              ),
              child: Text(user.role, style: TextStyle(fontSize: sizes.fontXs - 2, fontWeight: FontWeight.w500, color: cs.secondary)),
            ),
          SizedBox(height: sizes.gapXs),
          if (user.email.isNotEmpty)
            Text(
              user.email,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

// Modern admin button widget
class _ModernAdminButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ModernAdminButton({required this.icon, required this.label, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final sizes = context.sizes;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: context.radiusSm,
        child: Container(
          height: sizes.buttonHeightSm,
          padding: EdgeInsets.symmetric(horizontal: sizes.gapSm),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: context.radiusSm,
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: sizes.iconSm, color: color),
            SizedBox(width: sizes.gapXs),
            Text(label, style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w500, color: color)),
          ]),
        ),
      ),
    );
  }
}

// Theme option toggle widget
class _ThemeOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ThemeOption({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sizes = context.sizes;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: context.radiusLg,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: sizes.gapMd, vertical: sizes.gapSm),
          decoration: BoxDecoration(
            color: selected ? cs.primary.withOpacity(0.1) : cs.surfaceContainerHighest.withOpacity(0.4),
            borderRadius: context.radiusLg,
            border: Border.all(color: selected ? cs.primary.withOpacity(0.5) : cs.outlineVariant.withOpacity(0.3)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (selected) ...[
              Icon(Icons.check_rounded, size: sizes.iconSm, color: cs.primary),
              SizedBox(width: sizes.gapXs),
            ],
            Text(label, style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w500, color: selected ? cs.primary : cs.onSurface)),
          ]),
        ),
      ),
    );
  }
}
