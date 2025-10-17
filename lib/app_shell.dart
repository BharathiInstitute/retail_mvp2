import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
// Auth providers
import 'core/auth/auth.dart';
// Permissions
import 'core/permissions.dart';

// Module screens used by the router
import 'modules/dashboard/dashboard.dart';
import 'modules/pos/pos_ui.dart';
import 'modules/pos/pos_cashier.dart';
import 'modules/inventory/Products/inventory.dart';
import 'modules/invoices/sales_invoices.dart';
import 'modules/invoices/invoices_tabs.dart';
import 'modules/crm/crm.dart';
import 'modules/accounting/accounting.dart';
import 'modules/loyalty/loyalty.dart';
import 'modules/admin/admin.dart';
// Auth screens
import 'core/auth/login_screen.dart';
import 'core/auth/register_screen.dart';
import 'core/auth/forgot_password_screen.dart';

// ===== Inlined app state (from previous app_state.dart) =====
import 'dart:async';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((ref) {
  final authRepo = ref.watch(authRepositoryProvider);
  final permsAsync = ref.watch(permissionsProvider);
  final isOwnerAsync = ref.watch(ownerProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    debugLogDiagnostics: false,
    initialLocation: '/dashboard',
    refreshListenable: GoRouterRefreshStream(authRepo.authStateChanges()),
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

      // Owner bypass: if owner, allow all routes
      if (isOwnerAsync.hasValue && (isOwnerAsync.value ?? false)) {
        if (loggingIn) return '/dashboard';
        return null;
      }

      // Wait for permissions to load before making decisions
      if (!permsAsync.hasValue) return loggingIn ? null : null;
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
              path: '/inventory',
              name: 'inventory',
              pageBuilder: (context, state) => const NoTransitionPage(child: InventoryScreen()),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/invoices',
              name: 'invoices',
              pageBuilder: (context, state) => const NoTransitionPage(child: InvoicesTabsScreen()),
              routes: [
                GoRoute(
                  path: 'detail/:id',
                  name: 'invoice-detail',
                  builder: (context, state) => InvoicesListScreen(invoiceId: state.pathParameters['id']),
                ),
              ],
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
              pageBuilder: (context, state) => const NoTransitionPage(child: AdminDashboard()),
            ),
          ]),
        ],
      ),
    ],
  );
});

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }
  late final StreamSubscription<dynamic> _subscription;
  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

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

  // Map branches to labels/icons and route paths to mirror the provided example.
  static const List<_NavItem> _allItems = [
    _NavItem('Dashboard', Icons.dashboard_outlined, '/dashboard', 0),
    _NavItem('POS', Icons.point_of_sale_outlined, '/pos', 1),
    _NavItem('Inventory', Icons.inventory_2_outlined, '/inventory', 2),
    // Renamed from Billing -> Invoices and route updated to /invoices
    _NavItem('Invoices', Icons.receipt_long_outlined, '/invoices', 3),
    _NavItem('CRM', Icons.people_alt_outlined, '/crm', 4),
    _NavItem('Accounting', Icons.account_balance_outlined, '/accounting', 5),
    _NavItem('Loyalty', Icons.card_giftcard_outlined, '/loyalty', 6),
    _NavItem('Admin', Icons.admin_panel_settings_outlined, '/admin', 7),
  ];

  void _goBranch(BuildContext context, int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWide = MediaQuery.of(context).size.width >= 900;
    final user = ref.watch(authStateProvider);
    final permsAsync = ref.watch(permissionsProvider);
    final isOwner = ref.watch(ownerProvider).asData?.value ?? false;
    final perms = permsAsync.asData?.value ?? UserPermissions.empty;
    bool canViewRoute(String route) {
      if (isOwner) return true; // owner bypass in nav gating
      if (route.startsWith('/invoices')) {
        return perms.can(ScreenKeys.invSales, 'view') || perms.can(ScreenKeys.invPurchases, 'view');
      }
      final key = screenKeyForPath(route);
      return key == null ? true : perms.can(key, 'view');
    }
    final items = _allItems; // Keep all items visible; block navigation if not allowed

    // Compute selected index relative to full list (not filtered)
    int selectedIndex = items.indexWhere((e) => e.branchIndex == navigationShell.currentIndex);
    if (selectedIndex < 0) selectedIndex = 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Retail ERP MVP'),
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.brightness_6)),
          // Cashier icon placed beside theme toggle as requested
          Tooltip(
            message: 'Cashier',
            child: IconButton(
              icon: const Icon(Icons.account_circle_outlined),
              onPressed: () {
                // Open cashier screen on top of current route stack
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PosCashierScreen()),
                );
              },
            ),
          ),
          if (user != null)
            PopupMenuButton<String>(
              itemBuilder: (context) => [
                PopupMenuItem<String>(
                  value: 'email',
                  enabled: false,
                  child: Text(user.email ?? 'Signed in'),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem<String>(value: 'signout', child: Text('Sign out')),
              ],
              onSelected: (v) async {
                if (v == 'signout') {
                  // Sign out; router redirect will navigate to /login automatically
                  try {
                    // Ensure no SnackBars are shown/left over during logout
                    final messenger = ScaffoldMessenger.maybeOf(context);
                    messenger?.clearSnackBars();
                    // Proactively navigate to login on the root navigator to avoid
                    // any transient lookups on deactivated contexts.
                    final rootCtx = _rootNavigatorKey.currentContext;
                    if (rootCtx != null) {
                      GoRouter.of(rootCtx).go('/login');
                    }
                    // Sign out without awaiting to prevent running code after this
                    // widget is unmounted during redirect.
                    // ignore: discarded_futures
                    Future.microtask(() => ref.read(authRepositoryProvider).signOut());
                  } catch (_) {
                    // Ignore sign-out error to avoid context access after widget deactivation
                  }
                }
              },
              icon: const Icon(Icons.person_outline),
            )
          else
            TextButton(
              onPressed: () => context.go('/login'),
              child: const Text('Sign in'),
            ),
        ],
      ),
      drawer: isWide
          ? null
          : Drawer(
              child: SafeArea(
                child: ListView(
                  children: [
                    const SizedBox(height: 8),
                    for (final e in items)
                      ListTile(
                        leading: Icon(e.icon),
                        title: Text(e.label),
                        selected: navigationShell.currentIndex == e.branchIndex,
                        enabled: canViewRoute(e.route),
                        onTap: () async {
                          if (!canViewRoute(e.route)) {
                            final m = ScaffoldMessenger.maybeOf(context);
                            m?.showSnackBar(const SnackBar(content: Text('No access to this screen')));
                            return;
                          }
                          final tapCtx = context; // capture before async gap
                          // Avoid popping the last page off the GoRouter stack.
                          await Navigator.of(tapCtx).maybePop();
                          if (!tapCtx.mounted) return;
                          _goBranch(tapCtx, e.branchIndex);
                        },
                      ),
                  ],
                ),
              ),
            ),
      body: Row(
        children: [
          if (isWide)
            NavigationRail(
              selectedIndex: selectedIndex,
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final e in items)
                  NavigationRailDestination(icon: Icon(e.icon), label: Text(e.label)),
              ],
              onDestinationSelected: (i) {
                final target = items[i];
                if (!canViewRoute(target.route)) {
                  final m = ScaffoldMessenger.maybeOf(context);
                  m?.showSnackBar(const SnackBar(content: Text('No access to this screen')));
                  return;
                }
                _goBranch(context, target.branchIndex);
              },
            ),
          Expanded(child: navigationShell),
        ],
      ),
      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              selectedIndex: selectedIndex,
              destinations: [
                for (final e in items)
                  NavigationDestination(icon: Icon(e.icon), label: e.label),
              ],
              onDestinationSelected: (i) {
                final target = items[i];
                if (!canViewRoute(target.route)) {
                  final m = ScaffoldMessenger.maybeOf(context);
                  m?.showSnackBar(const SnackBar(content: Text('No access to this screen')));
                  return;
                }
                _goBranch(context, target.branchIndex);
              },
            ),
    );
  }
}

// Lightweight launcher page hosting the simple flow upload screen inside existing shell.
class _NavItem {
  final String label;
  final IconData icon;
  final String route;
  final int branchIndex; // index in GoRouter stateful shell
  const _NavItem(this.label, this.icon, this.route, this.branchIndex);
}
