import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/capabilities_provider.dart';

typedef CapabilitySelector = bool Function(Capabilities c);

class CapabilityGuard extends ConsumerWidget {
  final CapabilitySelector selector;
  final Widget child;
  final Widget? fallback;
  const CapabilityGuard({super.key, required this.selector, required this.child, this.fallback});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(capabilitiesProvider);
    final allowed = selector(caps);
    if (allowed) return child;
    return fallback ?? Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.lock_outline, size: 36),
        const SizedBox(height: 12),
        Text('Access Denied', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text('You do not have permission for this section.', style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }
}
