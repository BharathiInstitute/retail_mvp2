import 'package:flutter/material.dart';
import '../theme/theme_utils.dart';

/// Global blocking overlay for initial page loads.
///
/// Shows a full-screen progress indicator until [loading] is false.
/// If [error] is provided, shows a simple error UI with [onRetry].
class PageLoaderOverlay extends StatelessWidget {
  final bool loading;
  final Object? error;
  final VoidCallback? onRetry;
  final Widget child;
  final Duration minVisible;
  final String? message;

  const PageLoaderOverlay({
    super.key,
    required this.loading,
    required this.child,
    this.error,
    this.onRetry,
    this.minVisible = const Duration(milliseconds: 250),
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Stack(children: [
        // Keep layout stable
        Positioned.fill(child: Container(color: Colors.transparent)),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              if (message != null) ...[
                context.gapVMd,
                Text(message!, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ],
          ),
        ),
      ]);
    }
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline),
            context.gapVSm,
            Text('$error'),
            context.gapVSm,
            if (onRetry != null)
              FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
    }
    return child;
  }
}
