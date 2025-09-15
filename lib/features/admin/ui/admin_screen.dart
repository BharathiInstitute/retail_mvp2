import 'package:flutter/material.dart';

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: ListView(children: const [
        ListTile(
          leading: Icon(Icons.group_outlined),
          title: Text('Users'),
          subtitle: Text('TODO: Manage users and roles'),
        ),
        Divider(),
        ListTile(
          leading: Icon(Icons.business_outlined),
          title: Text('Tenants'),
          subtitle: Text('TODO: Tenant setup and settings'),
        ),
        Divider(),
        ListTile(
          leading: Icon(Icons.settings_outlined),
          title: Text('Settings'),
          subtitle: Text('TODO: App settings'),
        ),
      ]),
    );
  }
}
