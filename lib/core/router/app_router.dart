import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../widgets/app_shell.dart';
import '../../features/dashboard/ui/dashboard_screen.dart';
import '../../features/pos/ui/pos_screen.dart';
import '../../features/inventory/ui/inventory_screen.dart';
import '../../features/billing/ui/billing_list_screen.dart';
import '../../features/crm/ui/crm_list_screen.dart';
import '../../features/accounting/ui/accounting_module.dart';
import '../../features/loyalty/models/loyalty_module.dart';
import '../../features/admin/ui/admin_module.dart';
import '../providers/auth_providers.dart';
import '../guards/role_guard.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((ref) {
  final authRepo = ref.watch(authRepositoryProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    debugLogDiagnostics: false,
    initialLocation: '/dashboard',
  refreshListenable: GoRouterRefreshStream(authRepo.stream),
    redirect: (context, state) {
      // TODO: Implement actual auth redirect logic based on Firebase.
      // For shell, always allow.
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
              pageBuilder: (context, state) => const NoTransitionPage(child: PosScreen()),
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
                // Example nested route
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
              redirect: roleGuard(requiredRole: UserRole.admin),
            ),
          ]),
        ],
      ),
    ],
  );
});

// Helper class to refresh GoRouter using a stream
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
