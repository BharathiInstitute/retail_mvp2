import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth/auth.dart';

// Screen keys (final list)
class ScreenKeys {
  static const dashboard = 'dashboard';
  static const posMain = 'pos.main';
  static const posCashier = 'pos.cashier';
  static const invProducts = 'inventory.products';
  static const invStockMovements = 'inventory.stock-movements';
  static const invSuppliers = 'inventory.suppliers';
  static const invAlerts = 'inventory.alerts';
  static const invAudit = 'inventory.audit';
  static const invSales = 'invoices.sales';
  static const invPurchases = 'invoices.purchases';
  static const crm = 'crm.main';
  static const accounting = 'accounting.main';
  static const loyalty = 'loyalty.main';
  static const loyaltySettings = 'loyalty.settings';
  static const admin = 'admin.main';
}

class ScreenPerm {
  final bool view;
  final bool create;
  final bool edit;
  final bool delete;
  const ScreenPerm({this.view=false, this.create=false, this.edit=false, this.delete=false});

  factory ScreenPerm.fromMap(Map<String, dynamic>? m) => ScreenPerm(
        view: m?['view'] == true,
        create: m?['create'] == true,
        edit: m?['edit'] == true,
        delete: m?['delete'] == true,
      );

  Map<String, dynamic> toMap() => {
        'view': view,
        'create': create,
        'edit': edit,
        'delete': delete,
      };
}

class UserPermissions {
  final Map<String, ScreenPerm> modules;
  const UserPermissions(this.modules);
  static const empty = UserPermissions({});

  bool can(String screenKey, String action) {
    final p = modules[screenKey];
    if (p == null) return false;
    switch (action) {
      case 'view':
        return p.view;
      case 'create':
        return p.create && p.view; // enforce view dependency
      case 'edit':
        return p.edit && p.view;
      case 'delete':
        return p.delete && p.view;
    }
    return false;
  }
}

final permissionsProvider = StreamProvider<UserPermissions>((ref) {
  final auth = ref.watch(authStateProvider);
  if (auth == null) {
    // Immediately emit empty perms when signed out to unblock UI/router
    return Stream<UserPermissions>.value(UserPermissions.empty);
  }
  final doc = FirebaseFirestore.instance.collection('user_permissions').doc(auth.uid);
  return doc.snapshots().map((snap) {
    final data = snap.data();
    final modules = (data?['modules'] as Map<String, dynamic>?) ?? const {};
    final parsed = <String, ScreenPerm>{};
    modules.forEach((k, v) {
      if (v is Map<String, dynamic>) parsed[k] = ScreenPerm.fromMap(v);
    });
    return UserPermissions(parsed);
  }).handleError((_, __) => UserPermissions.empty);
});

// Owner provider: true if users/{uid}.role == 'owner'
final ownerProvider = StreamProvider<bool>((ref) {
  final auth = ref.watch(authStateProvider);
  if (auth == null) {
    // When signed out, immediately emit false
    return Stream<bool>.value(false);
  }
  final doc = FirebaseFirestore.instance.collection('users').doc(auth.uid);
  return doc.snapshots().map((s) => (s.data()?['role'] ?? '') == 'owner').handleError((_, __) => false);
});

class PermissionAware extends ConsumerWidget {
  final String screenKey;
  final String action; // 'view' | 'create' | 'edit' | 'delete'
  final Widget child;
  final Widget? fallback;
  const PermissionAware({super.key, required this.screenKey, required this.action, required this.child, this.fallback});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ownerAsync = ref.watch(ownerProvider);
    if (ownerAsync.asData?.value == true) return child; // owner bypass
    final permsAsync = ref.watch(permissionsProvider);
    return permsAsync.when(
      data: (perms) => perms.can(screenKey, action) ? child : (fallback ?? const SizedBox.shrink()),
      loading: () => fallback ?? const SizedBox.shrink(),
      error: (_, __) => fallback ?? const SizedBox.shrink(),
    );
  }
}

// Utility for mapping routes to screen keys
String? screenKeyForPath(String path) {
  if (path.startsWith('/dashboard')) return ScreenKeys.dashboard;
  if (path.startsWith('/pos-cashier')) return ScreenKeys.posCashier;
  if (path.startsWith('/pos')) return ScreenKeys.posMain;
  // Inventory detailed routes first
  if (path.startsWith('/inventory/stock-movement')) return ScreenKeys.invStockMovements;
  if (path.startsWith('/inventory/suppliers')) return ScreenKeys.invSuppliers;
  if (path.startsWith('/inventory/alerts')) return ScreenKeys.invAlerts;
  if (path.startsWith('/inventory/audit')) return ScreenKeys.invAudit;
  if (path.startsWith('/inventory/products') || path == '/inventory') return ScreenKeys.invProducts;
  if (path.startsWith('/crm')) return ScreenKeys.crm;
  if (path.startsWith('/accounting')) return ScreenKeys.accounting;
  if (path.startsWith('/loyalty')) return ScreenKeys.loyalty;
  if (path.startsWith('/admin')) return ScreenKeys.admin;
  if (path.startsWith('/invoices')) return null; // handled specially: sales OR purchases
  return null;
}

bool allowInvoicesView(UserPermissions perms) {
  return perms.can(ScreenKeys.invSales, 'view') || perms.can(ScreenKeys.invPurchases, 'view');
}
