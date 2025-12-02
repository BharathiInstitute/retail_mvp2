import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
// Auth providers
import 'core/auth/auth_repository_and_provider.dart';
// Permissions
import 'core/user_permissions_provider.dart';
import 'core/global_navigator_keys.dart';
import 'core/theme/theme_config_and_providers.dart';
import 'core/theme/theme_extension_helpers.dart';
import 'core/theme/font_preference_controller.dart';
import 'core/widgets/display_settings_dialog.dart';
import 'core/loading/fullscreen_loading_overlay.dart';

// Module screens used by the router
import 'modules/dashboard/dashboard_screen.dart';
import 'modules/pos/pos_ui.dart';
import 'modules/pos/pos_desktop_split_layout.dart';
import 'modules/pos/pos_cashier.dart';
import 'modules/pos/pos_mobile_layout.dart';
import 'modules/inventory/Products/inventory.dart';
import 'modules/inventory/stock_transfer_screen.dart';
import 'modules/inventory/supplier_management_screen.dart';
import 'modules/inventory/inventory_alerts_screen.dart';
import 'modules/inventory/inventory_audit_screen.dart';
import 'modules/invoices/sales_invoices_screen.dart';
// import 'modules/sales/sales_tab.dart'; // Commented out - file deleted
import 'modules/invoices/purchase_invoices_screen.dart';
// Removed legacy invoices tabs; using standalone screens
import 'modules/crm/crm_screen.dart';
import 'modules/accounting/accounting_screen.dart';
import 'modules/loyalty/loyalty_screen.dart';
import 'modules/admin/admin_permissions_overview_screen.dart';
import 'modules/admin/admin_users_screen.dart';
import 'modules/admin/admin_permissions_screen.dart';
import 'modules/admin/admin_migration_tools_screen.dart';
import 'modules/pos/printing/receipt_format_screen.dart';
import 'modules/stores/store_selector_screen.dart';
import 'modules/stores/store_create_screen.dart';
import 'modules/stores/providers.dart';
// Auth screens
import 'core/auth/login_page.dart';
import 'core/auth/register_page.dart';
import 'core/auth/forgot_password_page.dart';

// ===== Inlined app state (from previous app_state.dart) =====

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

  // If already logged in and currently on an auth route, immediately go to /stores
  // Do this BEFORE waiting on permissions or owner state to avoid getting stuck on login
  if (loggingIn) return '/stores';

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
      final isStoreOwner = ref.read(storeOwnerProvider);
      if ((ownerAsync.hasValue && (ownerAsync.value ?? false)) || isStoreOwner) {
        if (loggingIn) return '/dashboard';
        return null;
      }

      // Wait for permissions to load before making decisions
      final permsAsync = ref.read(permissionsProvider);
      if (!permsAsync.hasValue) return null; // do nothing until perms known
      final perms = permsAsync.value ?? UserPermissions.empty;

      // No longer on auth route here

      // Enforce store selection for store-scoped areas: if user has no memberships, go to /stores; if multiple and none selected, go to /stores
      final membershipsAsync = ref.read(myMembershipsProvider);
      if (membershipsAsync.hasValue) {
        final memberships = membershipsAsync.value ?? const [];
        final sel = ref.read(selectedStoreIdProvider);
        final onStores = state.matchedLocation.startsWith('/stores');
        if (memberships.isEmpty) {
          // User has no stores: keep them in /stores to create or request access
          if (!onStores) return '/stores';
        } else if (sel == null) {
          // Auto-select single membership; otherwise, ask user to pick
          if (memberships.length == 1) {
            ref.read(selectedStoreIdProvider.notifier).state = memberships.first.storeId;
            // If we are on the stores page and just auto-selected the only store, go to dashboard
            if (onStores) return '/dashboard';
          } else if (!onStores) {
            return '/stores';
          }
        }
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
      // Auth-protected, top-level (no shell) Stores routes to appear immediately after login without side menu
      GoRoute(
        path: '/stores',
        name: 'stores',
        builder: (context, state) => const MyStoresScreen(),
      ),
      GoRoute(
        path: '/stores/new',
        name: 'stores-new',
        builder: (context, state) => const CreateStoreScreen(),
      ),
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
              pageBuilder: (context, state) => const NoTransitionPage(child: _PosEntry()),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/pos-tab',
              name: 'pos-tab',
              pageBuilder: (context, state) => const NoTransitionPage(child: PosTwoSectionTabPage()),
            ),
          ]),
          // Explicit mobile POS route to allow directly opening the mobile layout from the side menu
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/pos-mobile',
              name: 'pos-mobile',
              pageBuilder: (context, state) => const NoTransitionPage(child: PosMobilePage()),
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
              path: '/invoices/sales-tab',
              name: 'invoices-sales-tab',
              pageBuilder: (context, state) => const NoTransitionPage(child: SalesInvoicesScreen()), // Changed from SalesTabPage
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
              path: '/admin/migration',
              name: 'admin-migration',
              pageBuilder: (context, state) => const NoTransitionPage(child: MigrationToolsScreen()),
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
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/admin/print-settings',
              name: 'admin-print-settings',
              pageBuilder: (context, state) => NoTransitionPage(child: ReceiptSettingsScreen()),
            ),
          ]),
        ],
      ),
    ],
  );

  // Refresh router when relevant providers change
  ref.listen(authStateProvider, (_, __) => router.refresh());
  ref.listen(permissionsProvider, (_, __) {
    if (ref.read(authStateProvider) != null) router.refresh();
  });
  ref.listen(ownerProvider, (_, __) {
    if (ref.read(authStateProvider) != null) router.refresh();
  });

  ref.onDispose(() {
    router.dispose();
  });

  return router;
});

// Track logout progress to prevent double taps and re-entrancy during sign-out
final logoutInProgressProvider = StateProvider<bool>((ref) => false);


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
            context.gapVMd,
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
            Icon(Icons.error_outline, size: context.sizes.iconXl),
            context.gapVSm,
            Text(message),
            if (onRetry != null) ...[
              context.gapVSm,
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
    // Initialize store selection persistence
    // ignore: unused_result
    ref.watch(selectedStorePersistInitProvider);
    final router = ref.watch(appRouterProvider);
    final fontKey = ref.watch(fontProvider);
    final density = ref.watch(uiDensityProvider);
    return MaterialApp.router(
      title: 'Retail ERP MVP',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: scaffoldMessengerKey,
      themeMode: ref.watch(themeModeProvider),
      theme: AppTheme.light(context, fontKey: fontKey, density: density),
      darkTheme: AppTheme.dark(context, fontKey: fontKey, density: density),
      routerConfig: router,
      builder: (context, child) => GlobalLoadingOverlay(child: child ?? const SizedBox.shrink()),
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
    // If we are on the standalone Stores routes, render the child directly (no app bar, no side menu)
    final currentPath = GoRouterState.of(context).matchedLocation;
    if (currentPath.startsWith('/stores')) {
      return navigationShell; // MyStores/CreateStore provide their own Scaffold
    }
    // Avoid rebuilding AppShell based on providers that don't affect layout
    // Note: Permissions are enforced per screen; the side menu itself shows all entries for discoverability.
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Text(
            'Retail ERP MVP',
            style: context.texts.titleLarge?.copyWith(
              color: context.colors.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          context.gapHMd,
          // Current store indicator + quick switch
          Consumer(builder: (context, ref, _) {
            final selId = ref.watch(selectedStoreIdProvider);
            final selDoc = ref.watch(selectedStoreDocProvider);
            final isLoading = selId != null && selDoc.isLoading;
            final name = selId == null
                ? 'No store selected'
                : (selDoc.asData?.value?.name ?? 'Loading…');
            return OutlinedButton.icon(
              onPressed: () => GoRouter.of(context).go('/stores'),
              icon: Icon(Icons.store_mall_directory_outlined, size: context.sizes.iconSm, color: context.colors.primary),
              label: Row(children: [
                Text(name, overflow: TextOverflow.ellipsis),
                if (isLoading) ...[
                  context.gapHSm,
                  const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ]),
              style: OutlinedButton.styleFrom(
                visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
            );
          }),
          const SizedBox(width: 6),
          // Quick switcher dropdown
          Consumer(builder: (context, ref, _) {
            final storesAsync = ref.watch(myStoresProvider);
            return PopupMenuButton<String>(
              tooltip: 'Switch store',
              icon: Icon(Icons.arrow_drop_down_circle_outlined, size: context.sizes.iconMd),
              onSelected: (id) {
                ref.read(selectedStoreIdProvider.notifier).state = id;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Store switched')));
                // After switching stores, go to a safe landing
                _goTo(context, '/dashboard');
              },
              itemBuilder: (context) {
                return storesAsync.when(
                  data: (items) => items.isEmpty
                      ? [const PopupMenuItem<String>(enabled: false, child: Text('No stores'))]
                      : items
                          .map((e) => PopupMenuItem<String>(
                                value: e.store.id,
                                child: Row(
                                  children: [
                                    Icon(Icons.store_outlined, size: context.sizes.iconSm),
                                    context.gapHSm,
                                    Expanded(child: Text(e.store.name, overflow: TextOverflow.ellipsis)),
                                    context.gapHSm,
                                    Text(e.role, style: Theme.of(context).textTheme.labelSmall),
                                  ],
                                ),
                              ))
                          .toList(),
                  loading: () => [const PopupMenuItem<String>(enabled: false, child: Text('Loading...'))],
                  error: (e, _) => [PopupMenuItem<String>(enabled: false, child: Text('Error: $e'))],
                );
              },
            );
          }),
        ]),
        actions: [
          // Density quick toggle
          Consumer(builder: (context, ref, _) {
            final density = ref.watch(uiDensityProvider);
            return IconButton(
              onPressed: () {
                // Cycle through densities
                final next = switch (density) {
                  UIDensity.compact => UIDensity.normal,
                  UIDensity.normal => UIDensity.comfortable,
                  UIDensity.comfortable => UIDensity.compact,
                };
                ref.read(uiDensityProvider.notifier).set(next);
              },
              icon: Icon(density.icon),
              tooltip: 'UI Density: ${density.label}',
            );
          }),
          // Theme toggle
          IconButton(
            onPressed: () => ref.read(themeModeProvider.notifier).cycle(),
            icon: const Icon(Icons.brightness_6),
            tooltip: 'Toggle theme',
          ),
          // Full settings dialog
          IconButton(
            onPressed: () => SettingsDialog.show(context),
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Display Settings',
          ),
        ],
      ),
      drawer: isWide ? null : Drawer(child: SafeArea(child: _SideMenu(isWide: false, onGo: (r) async {
        final tapCtx = context; await Navigator.of(tapCtx).maybePop(); if (!tapCtx.mounted) return; _goTo(tapCtx, r);
      })) ),
      body: Row(
        children: [
          if (isWide)
            Consumer(builder: (context, ref, _) {
              final extended = ref.watch(navRailExtendedProvider);
              final width = extended ? 220.0 : 64.0;
              return SizedBox(width: width, child: _SideMenu(isWide: true, onGo: (r) => _goTo(context, r)));
            }),
          Expanded(child: navigationShell),
        ],
      ),
      bottomNavigationBar: null,
    );
  }
}

// Route entry that picks the POS layout based on width
class _PosEntry extends StatelessWidget {
  const _PosEntry();
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w < 700) {
      return const PosMobilePage();
    }
    final isTablet = w >= 700 && w < 1280;
    if (isTablet) {
      return const PosTwoSectionTabPage();
    }
    return const PosPage();
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
  final isStoreOwner = ref.watch(storeOwnerProvider);
    final currentPath = GoRouterState.of(context).matchedLocation;

    final extended = ref.watch(navRailExtendedProvider);

    Widget header() {
      if (!extended) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Row(
          children: [
            CircleAvatar(radius: 16, child: Text(((user?.email ?? 'U').isNotEmpty ? (user?.email ?? 'U')[0] : 'U').toUpperCase())),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Builder(builder: (context) {
                  final displayName = (user?.displayName?.trim().isNotEmpty ?? false)
                      ? user!.displayName!.trim()
                      : ((user?.email ?? 'User').split('@').first);
                  return Text(
                    displayName,
                    style: context.texts.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: context.colors.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  );
                }),
                if ((user?.email ?? '').isNotEmpty)
                  Text(
                    user!.email!,
                    style: context.texts.bodySmall?.copyWith(color: context.colors.onSurfaceVariant, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
              ]),
            ),
          ],
        ),
      );
    }

  bool canView(String? key) => key == null ? true : (isOwner || isStoreOwner || perms.can(key, 'view'));

    Widget item(String label, IconData icon, String route, {String? screenKey, int indent = 0}) {
      final isStoreOwner = ref.watch(storeOwnerProvider);
      final canAccess = screenKey == null ? true : (isOwner || perms.can(screenKey, 'view') || route.startsWith('/invoices') && allowInvoicesView(perms));
      final allowed = canAccess || isStoreOwner; // store owner bypass
      final selected = currentPath == route || (route != '/' && currentPath.startsWith(route));
      final sizes = context.sizes;
      final tile = ListTile(
        dense: true,
        visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
        minLeadingWidth: 0,
        contentPadding: extended
            ? EdgeInsets.only(left: 12.0 + indent * 14.0, right: 12)
            : const EdgeInsets.symmetric(horizontal: 8),
        leading: Icon(
          icon,
          size: sizes.iconMd,
          color: selected
              ? context.colors.primary
              : (allowed ? context.colors.onSurfaceVariant : context.colors.onSurfaceVariant),
        ),
        title: extended
            ? Text(
                label,
                style: context.texts.bodySmall?.copyWith(
                  color: context.colors.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              )
            : null,
        trailing: extended && !allowed
            ? Icon(Icons.lock_outline, size: sizes.iconSm, color: context.colors.onSurfaceVariant)
            : null,
        selected: selected,
        onTap: () {
          if (allowed) {
            onGo(route);
          } else {
            final m = ScaffoldMessenger.maybeOf(context);
            m?.showSnackBar(const SnackBar(content: Text('No access to this screen')));
          }
        },
      );
      return extended ? tile : Tooltip(message: label, child: tile);
    }

    Widget groupHeader(String label, IconData icon, StateProvider<bool> expandState, {bool disabled = false}) {
      final expanded = ref.watch(expandState);
      final sizes = context.sizes;
      final tile = ListTile(
        dense: true,
        visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
        contentPadding: extended ? const EdgeInsets.symmetric(horizontal: 12) : const EdgeInsets.symmetric(horizontal: 8),
        leading: Icon(
          icon,
          size: sizes.iconMd,
          color: disabled ? context.colors.onSurfaceVariant : context.colors.onSurface,
        ),
        title: extended
            ? Text(
                label,
                style: context.texts.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: disabled ? context.colors.onSurfaceVariant : context.colors.onSurface,
                ),
              )
            : null,
        trailing: extended
            ? Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                size: sizes.iconSm,
                color: disabled ? context.colors.onSurfaceVariant : context.colors.onSurface,
              )
            : null,
        onTap: disabled ? null : () => ref.read(expandState.notifier).state = !expanded,
      );
      return extended ? tile : Tooltip(message: label, child: tile);
    }

    // Determine screen type for responsive menu items
    final screenType = Breakpoints.of(context);
    final isDesktop = screenType == ScreenType.desktop;
    final isTablet = screenType == ScreenType.tablet;
    final isMobile = screenType == ScreenType.mobile;

    List<Widget> children = [
      if (user != null) header(),
      item('My Stores', Icons.storefront_outlined, '/stores'),
      item('Dashboard', Icons.dashboard_outlined, '/dashboard', screenKey: ScreenKeys.dashboard),

      // POS group
  if (isOwner || isStoreOwner || (perms != UserPermissions.empty && (canView(ScreenKeys.posMain) || canView(ScreenKeys.posCashier)))) ...[
        groupHeader('POS', Icons.point_of_sale_outlined, posMenuExpandedProvider),
        if (ref.watch(posMenuExpandedProvider)) ...[
          // Desktop: show POS Main & Cashier
          if (isDesktop) item('POS Main', Icons.store_mall_directory_outlined, '/pos', screenKey: ScreenKeys.posMain, indent: 1),
          if (isDesktop) item('POS Cashier', Icons.account_circle_outlined, '/pos-cashier', screenKey: ScreenKeys.posCashier, indent: 1),
          // Tablet: show POS Tab only
          if (isTablet) item('POS Tab', Icons.tablet_mac_outlined, '/pos-tab', screenKey: ScreenKeys.posMain, indent: 1),
          // Mobile: show POS Mobile only
          if (isMobile) item('POS Mobile', Icons.phone_iphone_outlined, '/pos-mobile', screenKey: ScreenKeys.posMain, indent: 1),
        ],
      ],

      // Inventory group
  if (isOwner || isStoreOwner || (perms != UserPermissions.empty && (canView(ScreenKeys.invProducts) || canView(ScreenKeys.invStockMovements) || canView(ScreenKeys.invSuppliers) || canView(ScreenKeys.invAlerts) || canView(ScreenKeys.invAudit)))) ...[
        groupHeader('Inventory', Icons.inventory_2_outlined, inventoryMenuExpandedProvider),
        if (ref.watch(inventoryMenuExpandedProvider)) ...[
          item('Products', Icons.list_alt_outlined, '/inventory/products', screenKey: ScreenKeys.invProducts, indent: 1),
          item('Stock Movement', Icons.swap_vert_outlined, '/inventory/stock-movement', screenKey: ScreenKeys.invStockMovements, indent: 1),
          item('Suppliers', Icons.local_shipping_outlined, '/inventory/suppliers', screenKey: ScreenKeys.invSuppliers, indent: 1),
          item('Alerts', Icons.notifications_active_outlined, '/inventory/alerts', screenKey: ScreenKeys.invAlerts, indent: 1),
          item('Audit', Icons.rule_folder_outlined, '/inventory/audit', screenKey: ScreenKeys.invAudit, indent: 1),
        ],
      ],

      // Invoices group
  if (isOwner || isStoreOwner || (perms != UserPermissions.empty && (isOwner || allowInvoicesView(perms)))) ...[
        groupHeader('Invoices', Icons.receipt_long_outlined, invoicesMenuExpandedProvider),
        if (ref.watch(invoicesMenuExpandedProvider)) ...[
          // Desktop: show Sales (desktop version)
          if (isDesktop) item('Sales', Icons.trending_up_outlined, '/invoices/sales', screenKey: ScreenKeys.invSales, indent: 1),
          // Tablet: show Sales Tab
          if (isTablet) item('Sales', Icons.tablet_mac_outlined, '/invoices/sales-tab', screenKey: ScreenKeys.invSales, indent: 1),
          // Mobile: show Sales (mobile-friendly version)
          if (isMobile) item('Sales', Icons.trending_up_outlined, '/invoices/sales', screenKey: ScreenKeys.invSales, indent: 1),
          // Purchases shown on all screen sizes
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
          item('Receipt Settings', Icons.receipt_long_outlined, '/admin/print-settings', screenKey: ScreenKeys.admin, indent: 1),
          if (isOwner) item('Migration', Icons.auto_fix_high_outlined, '/admin/migration', screenKey: ScreenKeys.admin, indent: 1),
        ],
      ],
      const Divider(height: 8),
      if (user != null)
        Builder(builder: (context) {
          final extended = ref.watch(navRailExtendedProvider);
          final loggingOut = ref.watch(logoutInProgressProvider);
          final tile = ListTile(
            dense: true,
            visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
            minLeadingWidth: 0,
            contentPadding: extended ? const EdgeInsets.symmetric(horizontal: 12) : const EdgeInsets.symmetric(horizontal: 8),
            leading: Icon(Icons.logout, size: context.sizes.iconMd, color: context.colors.onSurface),
            title: extended
                ? Text(
                    'Logout',
                    style: context.texts.bodySmall?.copyWith(color: context.colors.onSurface, fontWeight: FontWeight.w700),
                  )
                : null,
            enabled: !loggingOut,
            onTap: loggingOut
                ? null
                : () async {
                    // Debounce logout to avoid repeated sign-outs and route churn
                    ref.read(logoutInProgressProvider.notifier).state = true;
                    try {
                      final messenger = scaffoldMessengerKey.currentState;
                      messenger?.clearSnackBars();
                      // Ensure no lingering focus from previous routes
                      FocusManager.instance.primaryFocus?.unfocus();
                      // Close any open drawers before navigating away to avoid overlay/barrier lingering
                      final nav = rootNavigatorKey.currentState;
                      if (nav != null) {
                        await nav.maybePop();
                      }
                      // Sign out first to avoid redirecting back to a protected route while still logged in.
                      await ref.read(authRepositoryProvider).signOut();
                      // Immediately invalidate derived auth-dependent providers to break listeners fast.
                      ref.invalidate(permissionsProvider);
                      ref.invalidate(ownerProvider);
                      ref.invalidate(authStateProvider);
                      // Give the framework a moment to settle route pops/animations (drawer closing, etc.)
                      await Future<void>.delayed(const Duration(milliseconds: 50));
                      // Hard-close any remaining overlays on root navigator to avoid stuck modal barriers
                      final rootNav = rootNavigatorKey.currentState;
                      if (rootNav != null) {
                        while (rootNav.canPop()) {
                          rootNav.pop();
                        }
                      }
                      // Replace the entire stack with /login on the root router (no back to protected screens)
                      final router = ref.read(appRouterProvider);
                      {
                        // Schedule navigation on next frame to avoid racing with disposals
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          router.replace('/login');
                          // Ensure redirect guards see the latest state
                          router.refresh();
                        });
                        // Also queue a microtask as a fallback in case of long frame
                        Future.microtask(() { try { router.replace('/login'); router.refresh(); } catch (_) {} });
                      }
                    } catch (_) {
                      // no-op
                    } finally {
                      ref.read(logoutInProgressProvider.notifier).state = false;
                    }
                  },
          );
          return extended ? tile : Tooltip(message: 'Logout', child: tile);
        }),
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
