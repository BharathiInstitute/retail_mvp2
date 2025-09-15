import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_providers.dart';

class AppShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;
  const AppShell({super.key, required this.navigationShell});

  static const _destinations = [
    NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
    NavigationDestination(icon: Icon(Icons.point_of_sale_outlined), label: 'POS'),
    NavigationDestination(icon: Icon(Icons.inventory_2_outlined), label: 'Inventory'),
    NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'Billing'),
    NavigationDestination(icon: Icon(Icons.people_alt_outlined), label: 'CRM'),
    NavigationDestination(icon: Icon(Icons.account_balance_outlined), label: 'Accounting'),
    NavigationDestination(icon: Icon(Icons.card_giftcard_outlined), label: 'Loyalty'),
    NavigationDestination(icon: Icon(Icons.admin_panel_settings_outlined), label: 'Admin'),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Retail ERP MVP'),
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.search)),
          IconButton(onPressed: () {}, icon: const Icon(Icons.brightness_6)),
          PopupMenuButton<String>(
            onSelected: (v) {
              final repo = ref.read(authRepositoryProvider);
              switch (v) {
                case 'admin':
                  repo.signInAsAdmin();
                  break;
                case 'guest':
                  repo.signInAnonymously();
                  break;
                case 'signout':
                  repo.signOut();
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'admin', child: Text('Sign in as Admin')),
              PopupMenuItem(value: 'guest', child: Text('Sign in as Guest')),
              PopupMenuItem(value: 'signout', child: Text('Sign out')),
            ],
            icon: const Icon(Icons.person_outline),
          ),
        ],
      ),
      drawer: isWide ? null : Drawer(
        child: ListView(
          children: [
            const DrawerHeader(child: Text('Modules')),
            for (int i = 0; i < _destinations.length; i++)
              ListTile(
                leading: _destinations[i].icon,
                title: Text(_destinations[i].label),
                selected: navigationShell.currentIndex == i,
                onTap: () {
                  Navigator.of(context).pop();
                  _goBranch(context, i);
                },
              ),
          ],
        ),
      ),
      body: Row(
        children: [
          if (isWide)
            NavigationRail(
              selectedIndex: navigationShell.currentIndex,
              labelType: NavigationRailLabelType.all,
              destinations: _destinations
                  .map((d) => NavigationRailDestination(icon: d.icon, label: Text(d.label)))
                  .toList(),
              onDestinationSelected: (i) => _goBranch(context, i),
            ),
          Expanded(child: navigationShell),
        ],
      ),
      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              selectedIndex: navigationShell.currentIndex,
              destinations: _destinations,
              onDestinationSelected: (i) => _goBranch(context, i),
            ),
    );
  }
}
