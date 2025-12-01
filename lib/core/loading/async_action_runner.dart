import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Result of an async action
sealed class ActionResult<T> {
  const ActionResult();
}

class ActionSuccess<T> extends ActionResult<T> {
  final T data;
  const ActionSuccess(this.data);
}

class ActionError<T> extends ActionResult<T> {
  final Object error;
  final StackTrace? stackTrace;
  const ActionError(this.error, [this.stackTrace]);
}

/// Extension for running async actions with proper error handling
extension AsyncActionExtension on WidgetRef {
  /// Run an async action with standardized error handling
  /// 
  /// Returns the result or null if failed.
  /// Shows snackbar on success/error if messages are provided.
  Future<T?> runAction<T>({
    required BuildContext context,
    required Future<T> Function() action,
    String? successMessage,
    String? errorMessage,
    bool showErrorDetails = false,
    VoidCallback? onSuccess,
    void Function(Object error)? onError,
  }) async {
    try {
      final result = await action();
      
      if (successMessage != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(successMessage)),
        );
      }
      onSuccess?.call();
      return result;
    } catch (e, st) {
      final msg = errorMessage ?? 'An error occurred';
      final details = showErrorDetails ? ': $e' : '';
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$msg$details'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      onError?.call(e);
      debugPrint('Action error: $e\n$st');
      return null;
    }
  }

  /// Run a delete action with confirmation dialog
  Future<bool> runDeleteAction({
    required BuildContext context,
    required String itemName,
    required Future<void> Function() action,
    String? successMessage,
    String? errorMessage,
  }) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: Text('Are you sure you want to delete $itemName?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return false;

    final result = await runAction(
      context: context,
      action: () async {
        await action();
        return true;
      },
      successMessage: successMessage ?? '$itemName deleted',
      errorMessage: errorMessage ?? 'Failed to delete $itemName',
    );

    return result == true;
  }

  /// Run a save action (create or update)
  Future<T?> runSaveAction<T>({
    required BuildContext context,
    required Future<T> Function() action,
    bool isCreate = false,
    String? itemName,
    String? successMessage,
    String? errorMessage,
  }) async {
    final defaultSuccess = isCreate 
        ? '${itemName ?? 'Item'} created'
        : '${itemName ?? 'Item'} saved';
    final defaultError = isCreate
        ? 'Failed to create ${itemName ?? 'item'}'
        : 'Failed to save ${itemName ?? 'item'}';

    return runAction(
      context: context,
      action: action,
      successMessage: successMessage ?? defaultSuccess,
      errorMessage: errorMessage ?? defaultError,
    );
  }
}

/// Mixin for StatefulWidget to handle async actions with loading state
mixin AsyncActionMixin<T extends StatefulWidget> on State<T> {
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _loadingMessage;
  String? get loadingMessage => _loadingMessage;

  /// Run an async action with loading state
  Future<R?> runAsync<R>({
    required Future<R> Function() action,
    String? loadingMessage,
    String? successMessage,
    String? errorMessage,
    VoidCallback? onSuccess,
    void Function(Object error)? onError,
  }) async {
    if (_isLoading) return null;

    setState(() {
      _isLoading = true;
      _loadingMessage = loadingMessage;
    });

    try {
      final result = await action();
      
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingMessage = null;
        });

        if (successMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(successMessage)),
          );
        }
        onSuccess?.call();
      }
      return result;
    } catch (e, st) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingMessage = null;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage ?? 'Error: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        onError?.call(e);
      }
      debugPrint('Async action error: $e\n$st');
      return null;
    }
  }
}

/// Helper for optimistic updates
class OptimisticUpdate<T> {
  final T originalValue;
  final T optimisticValue;
  final Future<void> Function() serverAction;
  final void Function(T value) updateState;
  final void Function(Object error)? onError;

  OptimisticUpdate({
    required this.originalValue,
    required this.optimisticValue,
    required this.serverAction,
    required this.updateState,
    this.onError,
  });

  /// Execute optimistic update
  Future<bool> execute() async {
    // Apply optimistic update immediately
    updateState(optimisticValue);

    try {
      // Sync with server
      await serverAction();
      return true;
    } catch (e) {
      // Rollback on failure
      updateState(originalValue);
      onError?.call(e);
      return false;
    }
  }
}

/// Extension for List optimistic operations
extension OptimisticListExtension<T> on List<T> {
  /// Optimistically add item
  Future<bool> optimisticAdd({
    required T item,
    required Future<void> Function() serverAction,
    required void Function(List<T>) updateState,
    void Function(Object)? onError,
  }) {
    final original = List<T>.from(this);
    return OptimisticUpdate<List<T>>(
      originalValue: original,
      optimisticValue: [...this, item],
      serverAction: serverAction,
      updateState: updateState,
      onError: onError,
    ).execute();
  }

  /// Optimistically remove item
  Future<bool> optimisticRemove({
    required T item,
    required Future<void> Function() serverAction,
    required void Function(List<T>) updateState,
    void Function(Object)? onError,
  }) {
    final original = List<T>.from(this);
    return OptimisticUpdate<List<T>>(
      originalValue: original,
      optimisticValue: where((e) => e != item).toList(),
      serverAction: serverAction,
      updateState: updateState,
      onError: onError,
    ).execute();
  }

  /// Optimistically update item
  Future<bool> optimisticUpdate({
    required T oldItem,
    required T newItem,
    required Future<void> Function() serverAction,
    required void Function(List<T>) updateState,
    void Function(Object)? onError,
  }) {
    final original = List<T>.from(this);
    return OptimisticUpdate<List<T>>(
      originalValue: original,
      optimisticValue: map((e) => e == oldItem ? newItem : e).toList(),
      serverAction: serverAction,
      updateState: updateState,
      onError: onError,
    ).execute();
  }
}
