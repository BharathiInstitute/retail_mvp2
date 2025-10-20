import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
// Auth providers
import 'core/auth/auth.dart';
// Permissions
import 'core/permissions.dart';
import 'core/app_keys.dart';

// Module screens used by the router
import 'modules/dashboard/dashboard.dart';
import 'modules/pos/pos_ui.dart';
import 'modules/pos/pos_cashier.dart';
import 'modules/inventory/Products/inventory.dart';
import 'modules/inventory/stock_movements_screen.dart';
import 'modules/inventory/transfers_screen.dart';
import 'modules/inventory/suppliers_screen.dart';
import 'modules/inventory/alerts_screen.dart';
import 'modules/inventory/audit_screen.dart';
import 'modules/invoices/sales_invoices.dart';
import 'modules/invoices/purchse_invoice.dart';
// Removed legacy invoices tabs; using standalone screens
import 'modules/crm/crm.dart';
import 'modules/accounting/accounting.dart';
import 'modules/loyalty/loyalty.dart';
import 'modules/admin/permissions_overview_tab.dart';
import 'modules/admin/users_tab.dart';
import 'modules/admin/permissions_tab.dart';
// Auth screens
import 'core/auth/login_screen.dart';
import 'core/auth/register_screen.dart';
import 'core/auth/forgot_password_screen.dart';

// ===== Inlined app state (from previous app_state.dart) =====
import 'dart:async';

// Use global keys from core/app_keys.dart

// Collapsible side menu state: false = icons-only (collapsed), true = icon + label (expanded)
final navRailExtendedProvider = StateProvider<bool>((ref) => false);
// Collapsible groups state
final posMenuExpandedProvider = StateProvider<bool>((ref) => true);
final inventoryMenuExpandedProvider = StateProvider<bool>((ref) => true);
final invoicesMenuExpandedProvider = StateProvider<bool>((ref) => true);
final adminMenuExpandedProvider = StateProvider<bool>((ref) => true);

final appRouterProvider = Provider<GoRouter>((ref) {

  final router = GoRouter(
  navigatorKey: rootNavigatorKey,
    debugLogDiagnostics: false,
    initialLocation: '/dashboard',
    redirect: (context, state) {
      // Auth state
      final isLoggedIn = ref.read(authStateProvider) != null;
      final loggingIn = state.matchedLocation.startsWith('/login') ||
          state.matchedLocation.startsWith('/register') ||
          state.matchedLocation.startsWith('/forgot');

      // Not logged in: allow auth routes, otherwise send to /login
      if (!isLoggedIn) return loggingIn ? null : '/login';

      // If on login while logged in, only leave when we know where to go
      String? computeSafe(UserPermissions perms) {
        if (perms.can(ScreenKeys.dashboard, 'view')) return '/dashboard';
        if (perms.can(ScreenKeys.posMain, 'view')) return '/pos';
        if (perms.can(ScreenKeys.invProducts, 'view')) return '/inventory';
        if (perms.can(ScreenKeys.invSales, 'view') || perms.can(ScreenKeys.invPurchases, 'view')) return '/invoices';
        if (perms.can(ScreenKeys.crm, 'view')) return '/crm';
        if (perms.can(ScreenKeys.accounting, 'view')) return '/accounting';
        if (perms.can(ScreenKeys.loyalty, 'view')) return '/loyalty';
        if (perms.can(ScreenKeys.admin, 'view')) return '/admin';
        return null;
      }

      // Owner bypass: if owner, allow all routes (once value is available)
      final ownerAsync = ref.read(ownerProvider);
      if (ownerAsync.hasValue && (ownerAsync.value ?? false)) {
        if (loggingIn) return '/dashboard';
        return null;
      }

      // Wait for permissions to load before making decisions
      final permsAsync = ref.read(permissionsProvider);
      if (!permsAsync.hasValue) return null; // do nothing until perms known
      final perms = permsAsync.value ?? UserPermissions.empty;

      // If currently on an auth route and logged in, navigate to the first allowed screen if any
      if (loggingIn) {
        final safe = computeSafe(perms);
        // If no safe destination yet, stay on login to avoid loops
        return safe; // may be null
      }

      // Guard non-auth routes by view permission
      final loc = state.matchedLocation;
      bool allow;
      if (loc.startsWith('/invoices')) {
        allow = perms.can(ScreenKeys.invSales, 'view') || perms.can(ScreenKeys.invPurchases, 'view');
      } else {
        final key = screenKeyForPath(loc);
        allow = key == null ? true : perms.can(key, 'view');
      }
      if (allow) return null;

      // Otherwise redirect to a safe destination if available, else to /login (will hold there)
      return computeSafe(perms) ?? '/login';
    },
  routes: [
      // Public auth routes
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        name: 'register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/forgot',
        name: 'forgot',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),

      // Authenticated shell routes
      StatefulShellRoute.indexedStack(
        builder: (context, state, navShell) => AppShell(navigationShell: navShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/dashboard',
              name: 'dashboard',
              pageBuilder: (context, state) => const NoTransitionPage(child: DashboardScreen()),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/pos',
              name: 'pos',
              pageBuilder: (context, state) => const NoTransitionPage(child: PosPage()),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/pos-cashier',
              name: 'pos-cashier',
              pageBuilder: (context, state) => const NoTransitionPage(child: PosCashierScreen()),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/inventory',
              name: 'inventory',
              pageBuilder: (context, state) => const NoTransitionPage(child: InventoryScreen()),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/inventory/products',
              name: 'inventory-products',
              pageBuilder: (context, state) => const NoTransitionPage(child: ProductsStandaloneScreen()),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/inventory/stock-movement',
              name: 'inventory-stock-movement',
              pageBuilder: (context, state) => const NoTransitionPage(child: StockMovementsScreen()),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/inventory/stock-transfer',
              name: 'inventory-stock-transfer',
              pageBuilder: (context, state) => const NoTransitionPage(child: TransfersScreen()),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/inventory/suppliers',
              name: 'inventory-suppliers',
              pageBuilder: (context, state) => const NoTransitionPage(child: SuppliersScreen()),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/inventory/alerts',
              name: 'inventory-alerts',
              pageBuilder: (context, state) => const NoTransitionPage(child: AlertsScreen()),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/inventory/audit',
              name: 'inventory-audit',
              pageBuilder: (context, state) => const NoTransitionPage(child: AuditScreen()),
            ),
          ]),
          // Legacy /invoices route removed in favor of direct /invoices/sales and /invoices/purchases
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/invoices/sales',
              name: 'invoices-sales',
              pageBuilder: (context, state) => const NoTransitionPage(child: SalesInvoicesScreen()),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/invoices/purchases',
              name: 'invoices-purchases',
              pageBuilder: (context, state) => NoTransitionPage(child: const PurchasesInvoicesScreen()),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/crm',
              name: 'crm',
              pageBuilder: (context, state) => const NoTransitionPage(child: CrmListScreen()),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/accounting',
              name: 'accounting',
              pageBuilder: (context, state) => const NoTransitionPage(child: AccountingModuleScreen()),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/loyalty',
              name: 'loyalty',
              pageBuilder: (context, state) => const NoTransitionPage(child: LoyaltyModuleScreen()),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/admin',
              name: 'admin',
              pageBuilder: (context, state) => const NoTransitionPage(child: PermissionsOverviewPage()),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/admin/permissions-edit',
              name: 'admin-permissions-edit',
              pageBuilder: (context, state) => NoTransitionPage(child: const AdminPermissionsEditPage()),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/admin/users',
              name: 'admin-users',
              pageBuilder: (context, state) => const NoTransitionPage(child: AdminUsersPage()),
            ),
          ]),
        ],
      ),
    ],
  );

  // Refresh router when relevant providers change
  ref.listen(authStateProvider, (_, __) => router.refresh());
  ref.listen(permissionsProvider, (_, __) => router.refresh());
  ref.listen(ownerProvider, (_, __) => router.refresh());

  ref.onDispose(() {
    router.dispose();
  });

  return router;
});


// ===== Inlined common widgets (from previous common_widgets.dart) =====
class LoadingView extends StatelessWidget {
  final String message;
  const LoadingView({super.key, this.message = 'Loading...'});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(message),
          ],
        ),
      );
}

class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const ErrorView({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 36),
            const SizedBox(height: 8),
            Text(message),
            if (onRetry != null) ...[
              const SizedBox(height: 8),
              FilledButton(onPressed: onRetry, child: const Text('Retry')),
            ]
          ],
        ),
      );
}

// ===== Inlined app root (from previous app.dart) =====
class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'Retail ERP MVP',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: scaffoldMessengerKey,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      routerConfig: router,
    );
  }
}

class AppShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;
  const AppShell({super.key, required this.navigationShell});

  void _goTo(BuildContext context, String route) {
    // Use root context to avoid nested navigator issues
  final rootCtx = rootNavigatorKey.currentContext ?? context;
    GoRouter.of(rootCtx).go(route);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWide = MediaQuery.of(context).size.width >= 900;
    // Avoid rebuilding AppShell based on providers that don't affect layout
    // Note: Permissions are enforced per screen; the side menu itself shows all entries for discoverability.
    return Scaffold(
      appBar: AppBar(
        title: const Text('Retail ERP MVP'),
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.brightness_6)),
        ],
      ),
      drawer: isWide ? null : Drawer(child: SafeArea(child: _SideMenu(isWide: false, onGo: (r) async {
        final tapCtx = context; await Navigator.of(tapCtx).maybePop(); if (!tapCtx.mounted) return; _goTo(tapCtx, r);
      })) ),
      body: Row(
        children: [
          if (isWide) SizedBox(width: 220, child: _SideMenu(isWide: true, onGo: (r) => _goTo(context, r))),
          Expanded(child: navigationShell),
        ],
      ),
      bottomNavigationBar: null,
    );
  }
}

class _SideMenu extends ConsumerWidget {
  final bool isWide;
  final void Function(String route) onGo;
  const _SideMenu({required this.isWide, required this.onGo});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
  // Watch permission-related providers so the menu updates when they load
  final user = ref.watch(authStateProvider);
  final perms = ref.watch(permissionsProvider).asData?.value ?? UserPermissions.empty;
  final isOwner = ref.watch(ownerProvider).asData?.value ?? false;
    final currentPath = GoRouterState.of(context).matchedLocation;

    Widget header() {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Row(
          children: [
            CircleAvatar(radius: 16, child: Text(((user?.email ?? 'U').isNotEmpty ? (user?.email ?? 'U')[0] : 'U').toUpperCase())),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text((user?.displayName?.isNotEmpty ?? false) ? user!.displayName! : (user?.email ?? 'User'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                if ((user?.email ?? '').isNotEmpty) Text(user!.email!, style: const TextStyle(fontSize: 12, color: Colors.grey), overflow: TextOverflow.ellipsis),
              ]),
            ),
          ],
        ),
      );
    }

    bool canView(String? key) => key == null ? true : (isOwner || perms.can(key, 'view'));

    Widget item(String label, IconData icon, String route, {String? screenKey, int indent = 0}) {
      final enabled = screenKey == null ? true : (isOwner || perms.can(screenKey, 'view') || route.startsWith('/invoices') && allowInvoicesView(perms));
      final selected = currentPath == route || (route != '/' && currentPath.startsWith(route));
      return ListTile(
        dense: true,
        visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
        contentPadding: EdgeInsets.only(left: 12.0 + indent * 14.0, right: 12),
        leading: Icon(icon, size: 20),
        title: Text(label, style: const TextStyle(fontSize: 13)),
        selected: selected,
        enabled: enabled,
        onTap: enabled ? () => onGo(route) : () {
          final m = ScaffoldMessenger.maybeOf(context); m?.showSnackBar(const SnackBar(content: Text('No access to this screen')));
        },
      );
    }

    Widget groupHeader(String label, IconData icon, StateProvider<bool> expandState, {bool disabled = false}) {
      final expanded = ref.watch(expandState);
      return ListTile(
        dense: true,
        visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: Icon(icon, size: 20),
        title: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: disabled ? Colors.grey : null)),
        trailing: Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 18, color: disabled ? Colors.grey : null),
        enabled: !disabled,
        onTap: disabled ? null : () => ref.read(expandState.notifier).state = !expanded,
      );
    }

    List<Widget> children = [
      if (user != null) header(),
      item('Dashboard', Icons.dashboard_outlined, '/dashboard', screenKey: ScreenKeys.dashboard),

      // POS group
      if (perms != UserPermissions.empty && (canView(ScreenKeys.posMain) || canView(ScreenKeys.posCashier))) ...[
        groupHeader('POS', Icons.point_of_sale_outlined, posMenuExpandedProvider),
        if (ref.watch(posMenuExpandedProvider)) ...[
          item('POS Main', Icons.store_mall_directory_outlined, '/pos', screenKey: ScreenKeys.posMain, indent: 1),
          item('POS Cashier', Icons.account_circle_outlined, '/pos-cashier', screenKey: ScreenKeys.posCashier, indent: 1),
        ],
      ],

      // Inventory group
      if (perms != UserPermissions.empty && (canView(ScreenKeys.invProducts) || canView(ScreenKeys.invStockMovements) || canView(ScreenKeys.invTransfers) || canView(ScreenKeys.invSuppliers) || canView(ScreenKeys.invAlerts) || canView(ScreenKeys.invAudit))) ...[
        groupHeader('Inventory', Icons.inventory_2_outlined, inventoryMenuExpandedProvider),
        if (ref.watch(inventoryMenuExpandedProvider)) ...[
          item('Products', Icons.list_alt_outlined, '/inventory/products', screenKey: ScreenKeys.invProducts, indent: 1),
          item('Stock Movement', Icons.swap_vert_outlined, '/inventory/stock-movement', screenKey: ScreenKeys.invStockMovements, indent: 1),
          item('Stock Transfer', Icons.compare_arrows_outlined, '/inventory/stock-transfer', screenKey: ScreenKeys.invTransfers, indent: 1),
          item('Suppliers', Icons.local_shipping_outlined, '/inventory/suppliers', screenKey: ScreenKeys.invSuppliers, indent: 1),
          item('Alerts', Icons.notifications_active_outlined, '/inventory/alerts', screenKey: ScreenKeys.invAlerts, indent: 1),
          item('Audit', Icons.rule_folder_outlined, '/inventory/audit', screenKey: ScreenKeys.invAudit, indent: 1),
        ],
      ],

      // Invoices group
      if (perms != UserPermissions.empty && (isOwner || allowInvoicesView(perms))) ...[
        groupHeader('Invoices', Icons.receipt_long_outlined, invoicesMenuExpandedProvider),
        if (ref.watch(invoicesMenuExpandedProvider)) ...[
          item('Sales', Icons.trending_up_outlined, '/invoices/sales', screenKey: ScreenKeys.invSales, indent: 1),
          item('Purchases', Icons.shopping_cart_outlined, '/invoices/purchases', screenKey: ScreenKeys.invPurchases, indent: 1),
        ],
      ],

      item('Accounting', Icons.account_balance_outlined, '/accounting', screenKey: ScreenKeys.accounting),
      item('CRM', Icons.people_alt_outlined, '/crm', screenKey: ScreenKeys.crm),
      item('Loyalty', Icons.card_giftcard_outlined, '/loyalty', screenKey: ScreenKeys.loyalty),

      // Admin group
      if (perms != UserPermissions.empty && canView(ScreenKeys.admin)) ...[
        groupHeader('Admin', Icons.admin_panel_settings_outlined, adminMenuExpandedProvider),
        if (ref.watch(adminMenuExpandedProvider)) ...[
          item('Permissions', Icons.security_outlined, '/admin', screenKey: ScreenKeys.admin, indent: 1),
          item('Users', Icons.group_outlined, '/admin/users', screenKey: ScreenKeys.admin, indent: 1),
        ],
      ],
      const Divider(height: 8),
      if (user != null)
        ListTile(
          dense: true,
          visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
          leading: const Icon(Icons.logout, size: 20),
          title: const Text('Logout', style: TextStyle(fontSize: 13)),
          onTap: () async {
            try {
              final messenger = ScaffoldMessenger.maybeOf(context); messenger?.clearSnackBars();
              final rootCtx = rootNavigatorKey.currentContext; if (rootCtx != null) { GoRouter.of(rootCtx).go('/login'); }
              Future.microtask(() => ref.read(authRepositoryProvider).signOut());
            } catch (_) {}
          },
        ),
    ];

    return Column(
      children: [
        Expanded(
          child: ListView(
            children: children,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Tooltip(
            message: ref.watch(navRailExtendedProvider) ? 'Collapse menu' : 'Expand menu',
            child: IconButton(
              icon: Icon(ref.watch(navRailExtendedProvider) ? Icons.chevron_left : Icons.chevron_right),
              onPressed: () {
                final current = ref.read(navRailExtendedProvider);
                ref.read(navRailExtendedProvider.notifier).state = !current;
              },
            ),
          ),
        ),
      ],
    );
  }
}
