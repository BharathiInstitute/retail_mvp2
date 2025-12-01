import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/theme_utils.dart';

/// Global loading state
class GlobalLoadingState {
  final bool isLoading;
  final String? message;
  final double? progress; // 0.0 to 1.0, null = indeterminate

  const GlobalLoadingState({
    this.isLoading = false,
    this.message,
    this.progress,
  });

  GlobalLoadingState copyWith({
    bool? isLoading,
    String? message,
    double? progress,
    bool clearProgress = false,
  }) {
    return GlobalLoadingState(
      isLoading: isLoading ?? this.isLoading,
      message: message ?? this.message,
      progress: clearProgress ? null : (progress ?? this.progress),
    );
  }
}

/// Global loading notifier
class GlobalLoadingNotifier extends StateNotifier<GlobalLoadingState> {
  GlobalLoadingNotifier() : super(const GlobalLoadingState());

  /// Show loading overlay
  void show({String? message, double? progress}) {
    state = GlobalLoadingState(
      isLoading: true,
      message: message,
      progress: progress,
    );
  }

  /// Update message or progress while loading
  void update({String? message, double? progress}) {
    if (!state.isLoading) return;
    state = state.copyWith(message: message, progress: progress);
  }

  /// Hide loading overlay
  void hide() {
    state = const GlobalLoadingState();
  }

  /// Execute an async action with loading overlay
  Future<T?> run<T>(
    Future<T> Function() action, {
    String? message,
    String? successMessage,
    String? errorMessage,
    void Function(T result)? onSuccess,
    void Function(Object error)? onError,
  }) async {
    show(message: message);
    try {
      final result = await action();
      hide();
      onSuccess?.call(result);
      return result;
    } catch (e) {
      hide();
      onError?.call(e);
      rethrow;
    }
  }
}

/// Global loading provider
final globalLoadingProvider =
    StateNotifierProvider<GlobalLoadingNotifier, GlobalLoadingState>((ref) {
  return GlobalLoadingNotifier();
});

/// Global loading overlay widget - wrap your app with this
class GlobalLoadingOverlay extends ConsumerWidget {
  final Widget child;

  const GlobalLoadingOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loadingState = ref.watch(globalLoadingProvider);

    return Stack(
      children: [
        child,
        if (loadingState.isLoading)
          Positioned.fill(
            child: _LoadingOverlayContent(
              message: loadingState.message,
              progress: loadingState.progress,
            ),
          ),
      ],
    );
  }
}

class _LoadingOverlayContent extends StatelessWidget {
  final String? message;
  final double? progress;

  const _LoadingOverlayContent({this.message, this.progress});

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final sizes = context.sizes;

    return Container(
      color: Colors.black54,
      child: Center(
        child: Card(
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(sizes.radiusLg),
          ),
          child: Padding(
            padding: EdgeInsets.all(sizes.gapXl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (progress != null)
                  SizedBox(
                    width: 56,
                    height: 56,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 4,
                          valueColor: AlwaysStoppedAnimation(cs.primary),
                          backgroundColor: cs.surfaceContainerHighest,
                        ),
                        Text(
                          '${(progress! * 100).toInt()}%',
                          style: context.boldSm,
                        ),
                      ],
                    ),
                  )
                else
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: CircularProgressIndicator(
                      strokeWidth: 4,
                      valueColor: AlwaysStoppedAnimation(cs.primary),
                    ),
                  ),
                if (message != null) ...[
                  SizedBox(height: sizes.gapMd),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 200),
                    child: Text(
                      message!,
                      style: context.subtleMd,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Extension for easy access from WidgetRef
extension GlobalLoadingExtension on WidgetRef {
  /// Show global loading overlay
  void showLoading({String? message, double? progress}) {
    read(globalLoadingProvider.notifier).show(message: message, progress: progress);
  }

  /// Update loading message/progress
  void updateLoading({String? message, double? progress}) {
    read(globalLoadingProvider.notifier).update(message: message, progress: progress);
  }

  /// Hide global loading overlay
  void hideLoading() {
    read(globalLoadingProvider.notifier).hide();
  }

  /// Run async action with loading overlay
  Future<T?> runWithLoading<T>(
    Future<T> Function() action, {
    String? message,
    void Function(T result)? onSuccess,
    void Function(Object error)? onError,
  }) {
    return read(globalLoadingProvider.notifier).run(
      action,
      message: message,
      onSuccess: onSuccess,
      onError: onError,
    );
  }
}
