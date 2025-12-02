import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth/auth_repository_and_provider.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:collection/collection.dart';
import '../modules/stores/providers.dart';

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

  // Merge two sources: custom claims and users/{uid}.role field
  // Emit true if either indicates 'owner'.
  final controller = StreamController<bool>();

  bool closed = false;
  void safeAdd(bool v) { if (!closed) controller.add(v); }

  Future<void> recompute() async {
    bool docOwner = false;
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(auth.uid).get();
      docOwner = (snap.data()?['role'] ?? '') == 'owner';
    } catch (_) {}
    bool claimOwner = false;
    try {
      final u = fb.FirebaseAuth.instance.currentUser;
      if (u != null) {
        final token = await u.getIdTokenResult(true);
        final role = (token.claims?["role"])?.toString();
        claimOwner = role == 'owner';
      }
    } catch (_) {}
    safeAdd(docOwner || claimOwner);
  }

  final fsSub = FirebaseFirestore.instance.collection('users').doc(auth.uid).snapshots().listen((_) { recompute(); });
  final idSub = fb.FirebaseAuth.instance.idTokenChanges().listen((_) { recompute(); });

  // Kick off initial compute
  // ignore: discarded_futures
  recompute();

  ref.onDispose(() {
    closed = true;
    fsSub.cancel();
    idSub.cancel();
    controller.close();
  });

  return controller.stream.distinct();
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
    final isStoreOwner = ref.watch(storeOwnerProvider);
    if (ownerAsync.asData?.value == true || isStoreOwner) return child; // owner or store-owner bypass
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

// True when the user is the owner for the currently selected store
final storeOwnerProvider = Provider<bool>((ref) {
  final selId = ref.watch(selectedStoreIdProvider);
  if (selId == null) return false;
  final memberships = ref.watch(myMembershipsProvider).asData?.value ?? const [];
  final m = memberships.firstWhereOrNull((e) => e.storeId == selId);
  return (m?.role ?? '') == 'owner' && (m?.status ?? 'active') == 'active';
});
