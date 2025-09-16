import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// Feature screens used by the router
import 'features/dashboard/dashboard.dart';
import 'features/pos/pos.dart';
import 'features/inventory/inventory.dart';
import 'features/billing/billing.dart';
import 'features/crm/crm.dart';
import 'features/accounting/accounting.dart';
import 'features/loyalty/loyalty.dart';
import 'features/admin/admin.dart';

// ===== Inlined app state (from previous app_state.dart) =====
import 'dart:async';
// Models
enum UserRole { admin, manager, cashier, viewer }

class AuthUser {
  final String uid;
  final String? displayName;
  final String? email;
  final UserRole role;
  const AuthUser({required this.uid, this.displayName, this.email, this.role = UserRole.viewer});
}

// Repository
class MockAuthRepository {
  final _controller = StreamController<AuthUser?>.broadcast();
  AuthUser? _current;

  Stream<AuthUser?> get stream => _controller.stream;
  AuthUser? get currentUser => _current;

  Future<void> signInAnonymously() async {
    _current = const AuthUser(uid: 'anon', displayName: 'Guest', role: UserRole.viewer);
    _controller.add(_current);
  }

  Future<void> signInAsAdmin() async {
    _current = const AuthUser(uid: 'admin1', displayName: 'Admin', email: 'admin@example.com', role: UserRole.admin);
    _controller.add(_current);
  }

  Future<void> signInAsManager() async {
    _current = const AuthUser(uid: 'mgr1', displayName: 'Manager', email: 'manager@example.com', role: UserRole.manager);
    _controller.add(_current);
  }

  Future<void> signOut() async {
    _current = null;
    _controller.add(null);
  }

  void dispose() {
    _controller.close();
  }
}

final authRepositoryProvider = Provider<MockAuthRepository>((ref) {
  final repo = MockAuthRepository();
  ref.onDispose(repo.dispose);
  return repo;
});

// Providers
class AuthStateNotifier extends StateNotifier<AuthUser?> {
  final MockAuthRepository repo;
  late final StreamSubscription<AuthUser?> _sub;

  AuthStateNotifier(this.repo) : super(repo.currentUser) {
    _sub = repo.stream.listen((user) => state = user);
    repo.signInAnonymously();
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final authStateProvider = StateNotifierProvider<AuthStateNotifier, AuthUser?>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  return AuthStateNotifier(repo);
});

final userRoleProvider = Provider<UserRole>((ref) {
  final user = ref.watch(authStateProvider);
  return user?.role ?? UserRole.viewer;
});

// ===== Inlined router (from previous app_router.dart) =====
final _rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((ref) {
  final authRepo = ref.watch(authRepositoryProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    debugLogDiagnostics: false,
    initialLocation: '/dashboard',
    refreshListenable: GoRouterRefreshStream(authRepo.stream),
    redirect: (context, state) {
      return null;
    },
    routes: [
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
    final role = ref.watch(userRoleProvider);
  // Show all menu items and allow navigation to Admin for demo access
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
          PopupMenuButton<UserRole>(
            initialValue: role,
            onSelected: (r) {
              final repo = ref.read(authRepositoryProvider);
              switch (r) {
                case UserRole.admin:
                  repo.signInAsAdmin();
                  break;
                case UserRole.manager:
                  repo.signInAsManager();
                  break;
                case UserRole.cashier:
                case UserRole.viewer:
                  repo.signInAnonymously();
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: UserRole.admin, child: Text('Role: Admin')),
              PopupMenuItem(value: UserRole.manager, child: Text('Role: Manager')),
              PopupMenuItem(value: UserRole.viewer, child: Text('Role: Guest')),
            ],
            icon: const Icon(Icons.person_outline),
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
