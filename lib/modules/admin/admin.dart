import 'package:flutter/material.dart';
import 'permissions_overview_tab.dart';
import 'users_tab.dart';
import 'permissions_tab.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin')),
      body: const Padding(
        padding: EdgeInsets.all(16),
        child: PermissionsOverviewTab(),
      ),
    );
  }
}

class AdminUsersPage extends StatelessWidget {
  const AdminUsersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin · Users')),
      body: const Padding(
        padding: EdgeInsets.all(16),
        child: UsersTab(),
      ),
    );
  }
}

class AdminPermissionsEditPage extends StatelessWidget {
  const AdminPermissionsEditPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Permissions (Edit)')),
      body: const Padding(
        padding: EdgeInsets.all(16),
        child: PermissionsTab(),
      ),
    );
  }
}
