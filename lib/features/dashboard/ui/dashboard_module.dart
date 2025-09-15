import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Deprecated: DashboardModuleScreen is no longer used. Use DashboardScreen instead.
@Deprecated('Use DashboardScreen instead')
class DashboardModuleScreen extends ConsumerWidget {
  const DashboardModuleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: Text(
          'DashboardModuleScreen is deprecated and not used.\nPlease use DashboardScreen.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}
