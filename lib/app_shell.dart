import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
// Auth providers
import 'core/auth/auth.dart';

// Module screens used by the router
import 'modules/dashboard/dashboard.dart';
import 'modules/pos/pos.dart';
import 'modules/inventory/inventory.dart';
import 'modules/billing/billing.dart';
import 'modules/crm/crm.dart';
import 'modules/accounting/accounting.dart';
import 'modules/loyalty/loyalty.dart';
import 'modules/admin/admin.dart';
// Auth screens
import 'modules/auth/login_screen.dart';
import 'modules/auth/register_screen.dart';
import 'modules/auth/forgot_password_screen.dart';

// ===== Inlined app state (from previous app_state.dart) =====
import 'dart:async';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((ref) {
  final authRepo = ref.watch(authRepositoryProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    debugLogDiagnostics: false,
    initialLocation: '/dashboard',
    refreshListenable: GoRouterRefreshStream(authRepo.authStateChanges()),
    redirect: (context, state) {
      // Simple auth guard
      final isLoggedIn = ref.read(authStateProvider) != null;
      final loggingIn = state.matchedLocation.startsWith('/login') ||
          state.matchedLocation.startsWith('/register') ||
          state.matchedLocation.startsWith('/forgot');
      if (!isLoggedIn && !loggingIn) return '/login';
      if (isLoggedIn && loggingIn) return '/dashboard';
      return null;
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
              path: '/billing',
              name: 'billing',
              pageBuilder: (context, state) => const NoTransitionPage(child: BillingListScreen()),
              routes: [
                GoRoute(
                  path: 'detail/:id',
                  name: 'invoice-detail',
                  builder: (context, state) => BillingListScreen(invoiceId: state.pathParameters['id']),
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
              pageBuilder: (context, state) => const NoTransitionPage(child: AdminModuleScreen()),
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
    _NavItem('Billing', Icons.receipt_long_outlined, '/billing', 3),
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
    final items = _allItems;

    // Compute selected index relative to full list (not filtered)
    int selectedIndex = items.indexWhere((e) => e.branchIndex == navigationShell.currentIndex);
    if (selectedIndex < 0) selectedIndex = 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Retail ERP MVP'),
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.search)),
          IconButton(onPressed: () {}, icon: const Icon(Icons.brightness_6)),
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
                  await ref.read(authRepositoryProvider).signOut();
                  if (context.mounted) context.go('/login');
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
                        onTap: () {
                          Navigator.of(context).pop();
                          _goBranch(context, e.branchIndex);
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
              onDestinationSelected: (i) => _goBranch(context, items[i].branchIndex),
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
              onDestinationSelected: (i) => _goBranch(context, items[i].branchIndex),
            ),
    );
  }
}

class _NavItem {
  final String label;
  final IconData icon;
  final String route;
  final int branchIndex; // index in GoRouter stateful shell
  const _NavItem(this.label, this.icon, this.route, this.branchIndex);
}
