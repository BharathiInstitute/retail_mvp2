import 'package:flutter/material.dart';
import 'users_tab.dart';
import 'permissions_tab.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Users'),
              Tab(text: 'Permissions'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            const Padding(padding: EdgeInsets.all(16), child: UsersTab()),
            const Padding(padding: EdgeInsets.all(16), child: PermissionsTab()),
          ],
        ),
      ),
    );
  }
}
