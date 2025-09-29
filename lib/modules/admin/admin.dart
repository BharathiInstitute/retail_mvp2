import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'rbac/admin_rbac_providers.dart';
import 'users/user_list_screen.dart';
import 'permissions/action_permissions_matrix_screen.dart';

class AdminDashboard extends ConsumerStatefulWidget {
  const AdminDashboard({super.key});
  @override
  ConsumerState<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends ConsumerState<AdminDashboard> with SingleTickerProviderStateMixin {
  late TabController _tab;
  final tabs = const [
    Tab(text: 'Users'),
    Tab(text: 'Action Permissions'),
  ];
  final _descs = const [
    'Manage users, roles and store memberships.',
    'Fine-grained action permissions (matrix by role).',
  ];
  @override
  void initState() {
    super.initState();
  _tab = TabController(length: tabs.length, vsync: this);
  }
  @override
  void dispose() { _tab.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final caps = ref.watch(capabilitiesProvider);
    // Trigger bootstrap owner creation if no users exist yet.
    ref.watch(bootstrapOwnerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin'),
        bottom: TabBar(controller: _tab, tabs: tabs),
        actions: [ if (caps.manageUsers) IconButton(onPressed: (){}, icon: const Icon(Icons.settings_suggest_outlined)) ],
      ),
      body: Column(children:[
        Material(color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(.4), child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal:16, vertical: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children:[
            const Icon(Icons.info_outline, size:18), const SizedBox(width:8),
            Expanded(child: Text(_descs[_tab.index], style: Theme.of(context).textTheme.bodySmall)),
          ]),
        )),
        Expanded(child: TabBarView(controller: _tab, children: const [
          Padding(padding: EdgeInsets.all(16), child: UserListScreen()),
          Padding(padding: EdgeInsets.all(16), child: ActionPermissionsMatrixScreen()),
        ])),
      ]),
    );
  }
}
