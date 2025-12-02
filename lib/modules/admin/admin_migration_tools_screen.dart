import 'package:flutter/material.dart';

/// Placeholder screen for admin migration tools.
/// Added to satisfy router reference in `app_shell.dart`.
class MigrationToolsScreen extends StatelessWidget {
  const MigrationToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Migration Tools')),
      body: const Center(
        child: Text('Migration tools are not implemented yet.'),
      ),
    );
  }
}
