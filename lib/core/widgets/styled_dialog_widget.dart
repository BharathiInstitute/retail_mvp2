import 'package:flutter/material.dart';
import 'package:retail_mvp2/core/theme/theme_config_and_providers.dart';
import 'package:retail_mvp2/core/theme/theme_extension_helpers.dart';

/// Dialog size variants
enum DialogSize { sm, md, lg, xl }

/// A themed dialog widget with consistent styling.
/// 
/// Usage:
/// ```dart
/// showAppDialog(
///   context: context,
///   title: 'Confirm Delete',
///   content: Text('Are you sure?'),
///   actions: [
///     AppDialogAction(label: 'Cancel', onPressed: () => Navigator.pop(context)),
///     AppDialogAction(label: 'Delete', onPressed: () {}, isDestructive: true),
///   ],
/// );
/// ```
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    this.title,
    this.titleWidget,
    required this.content,
    this.actions = const [],
    this.size = DialogSize.md,
    this.showCloseButton = true,
    this.scrollable = false,
  });

  /// Dialog title text
  final String? title;
  
  /// Custom title widget (overrides title)
  final Widget? titleWidget;
  
  /// Dialog content
  final Widget content;
  
  /// Action buttons
  final List<Widget> actions;
  
  /// Size variant
  final DialogSize size;
  
  /// Show close button in header
  final bool showCloseButton;
  
  /// Make content scrollable
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final sizes = context.sizes;
    final cs = context.colors;
    
    // Size-based width
    final maxWidth = switch (size) {
      DialogSize.sm => sizes.dialogWidthSm,
      DialogSize.md => sizes.dialogWidthMd,
      DialogSize.lg => sizes.dialogWidthLg,
      DialogSize.xl => sizes.dialogWidthLg * 1.25,
    };
    
    Widget dialogContent = content;
    if (scrollable) {
      dialogContent = SingleChildScrollView(child: content);
    }
    
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.all(sizes.gapLg),
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(sizes.radiusLg),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            if (title != null || titleWidget != null || showCloseButton) ...[
              Padding(
                padding: EdgeInsets.fromLTRB(
                  sizes.gapLg, 
                  sizes.gapMd, 
                  showCloseButton ? sizes.gapSm : sizes.gapLg, 
                  sizes.gapSm,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: titleWidget ?? Text(
                        title ?? '',
                        style: context.heading3,
                      ),
                    ),
                    if (showCloseButton)
                      IconButton(
                        icon: Icon(Icons.close, size: sizes.iconMd),
                        onPressed: () => Navigator.of(context).pop(),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        splashRadius: sizes.iconMd,
                      ),
                  ],
                ),
              ),
              Divider(height: 1, color: cs.outlineVariant.withOpacity(0.3)),
            ],
            
            // Content
            Flexible(
              child: Padding(
                padding: EdgeInsets.all(sizes.gapLg),
                child: dialogContent,
              ),
            ),
            
            // Actions
            if (actions.isNotEmpty) ...[
              Divider(height: 1, color: cs.outlineVariant.withOpacity(0.3)),
              Padding(
                padding: EdgeInsets.all(sizes.gapMd),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (int i = 0; i < actions.length; i++) ...[
                      if (i > 0) SizedBox(width: sizes.gapSm),
                      actions[i],
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Show a themed dialog
Future<T?> showAppDialog<T>({
  required BuildContext context,
  String? title,
  Widget? titleWidget,
  required Widget content,
  List<Widget> actions = const [],
  DialogSize size = DialogSize.md,
  bool showCloseButton = true,
  bool scrollable = false,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (context) => AppDialog(
      title: title,
      titleWidget: titleWidget,
      content: content,
      actions: actions,
      size: size,
      showCloseButton: showCloseButton,
      scrollable: scrollable,
    ),
  );
}

/// Confirmation dialog helper
Future<bool> showConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool isDestructive = false,
}) async {
  final sizes = Theme.of(context).extension<AppSizes>();
  final result = await showAppDialog<bool>(
    context: context,
    title: title,
    size: DialogSize.sm,
    content: Text(message, style: sizes != null 
      ? TextStyle(fontSize: sizes.fontMd)
      : null),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: Text(cancelLabel),
      ),
      ElevatedButton(
        onPressed: () => Navigator.of(context).pop(true),
        style: ElevatedButton.styleFrom(
          backgroundColor: isDestructive 
            ? Theme.of(context).colorScheme.error 
            : Theme.of(context).colorScheme.primary,
          foregroundColor: isDestructive 
            ? Theme.of(context).colorScheme.onError 
            : Theme.of(context).colorScheme.onPrimary,
        ),
        child: Text(confirmLabel),
      ),
    ],
  );
  return result ?? false;
}

/// Alert dialog helper
Future<void> showAlertDialog({
  required BuildContext context,
  required String title,
  required String message,
  String buttonLabel = 'OK',
}) {
  return showAppDialog(
    context: context,
    title: title,
    size: DialogSize.sm,
    showCloseButton: false,
    content: Text(message),
    actions: [
      ElevatedButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(buttonLabel),
      ),
    ],
  );
}

/// A bottom sheet variant
class AppBottomSheet extends StatelessWidget {
  const AppBottomSheet({
    super.key,
    this.title,
    required this.child,
    this.showDragHandle = true,
    this.showCloseButton = false,
  });

  final String? title;
  final Widget child;
  final bool showDragHandle;
  final bool showCloseButton;

  @override
  Widget build(BuildContext context) {
    final sizes = context.sizes;
    final cs = context.colors;
    
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(sizes.radiusLg)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDragHandle) ...[
            SizedBox(height: sizes.gapSm),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
          if (title != null || showCloseButton) ...[
            Padding(
              padding: EdgeInsets.fromLTRB(
                sizes.gapLg,
                sizes.gapMd,
                showCloseButton ? sizes.gapSm : sizes.gapLg,
                sizes.gapSm,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title ?? '', style: context.heading3),
                  ),
                  if (showCloseButton)
                    IconButton(
                      icon: Icon(Icons.close, size: sizes.iconMd),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                ],
              ),
            ),
            Divider(height: 1, color: cs.outlineVariant.withOpacity(0.3)),
          ],
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(sizes.gapLg),
              child: child,
            ),
          ),
          // Safe area for bottom
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}

/// Show a themed bottom sheet
Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required Widget child,
  String? title,
  bool showDragHandle = true,
  bool showCloseButton = false,
  bool isScrollControlled = true,
  bool isDismissible = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    isDismissible: isDismissible,
    backgroundColor: Colors.transparent,
    builder: (context) => AppBottomSheet(
      title: title,
      showDragHandle: showDragHandle,
      showCloseButton: showCloseButton,
      child: child,
    ),
  );
}
