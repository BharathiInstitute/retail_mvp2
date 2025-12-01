import 'package:flutter/material.dart';
import 'package:retail_mvp2/core/theme/theme_utils.dart';

/// Size variants for empty state
enum EmptyStateSize { sm, md, lg }

/// A themed empty state widget for showing when there's no data.
/// 
/// Usage:
/// ```dart
/// AppEmptyState(
///   icon: Icons.inbox,
///   title: 'No items yet',
///   subtitle: 'Add your first item to get started',
///   action: AppButton(label: 'Add Item', onPressed: () {}),
/// )
/// ```
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    this.size = EmptyStateSize.md,
  });

  /// Icon to display
  final IconData icon;
  
  /// Main title text
  final String title;
  
  /// Optional subtitle/description
  final String? subtitle;
  
  /// Optional action button
  final Widget? action;
  
  /// Size variant
  final EmptyStateSize size;

  @override
  Widget build(BuildContext context) {
    final sizes = context.sizes;
    final cs = context.colors;
    
    // Size-based dimensions
    final (iconSize, titleStyle, subtitleStyle, gap) = switch (size) {
      EmptyStateSize.sm => (sizes.iconLg, context.boldSm, context.subtleXs, sizes.gapSm),
      EmptyStateSize.md => (sizes.iconXl, context.boldMd, context.subtleSm, sizes.gapMd),
      EmptyStateSize.lg => (sizes.iconXl * 1.5, context.heading3, context.subtleMd, sizes.gapLg),
    };
    
    return Center(
      child: Padding(
        padding: EdgeInsets.all(sizes.gapLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(sizes.gapMd),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: iconSize,
                color: cs.onSurfaceVariant.withOpacity(0.5),
              ),
            ),
            SizedBox(height: gap),
            Text(
              title,
              style: titleStyle,
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              SizedBox(height: sizes.gapXs),
              Text(
                subtitle!,
                style: subtitleStyle,
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              SizedBox(height: gap),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// A loading indicator with optional message
class AppLoadingState extends StatelessWidget {
  const AppLoadingState({
    super.key,
    this.message,
    this.size = EmptyStateSize.md,
  });

  final String? message;
  final EmptyStateSize size;

  @override
  Widget build(BuildContext context) {
    final sizes = context.sizes;
    
    final (indicatorSize, textStyle, gap) = switch (size) {
      EmptyStateSize.sm => (20.0, context.subtleSm, sizes.gapSm),
      EmptyStateSize.md => (32.0, context.subtleMd, sizes.gapMd),
      EmptyStateSize.lg => (48.0, context.subtleLg, sizes.gapLg),
    };
    
    return Center(
      child: Padding(
        padding: EdgeInsets.all(sizes.gapLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: indicatorSize,
              height: indicatorSize,
              child: CircularProgressIndicator(
                strokeWidth: indicatorSize / 10,
                valueColor: AlwaysStoppedAnimation(context.colors.primary),
              ),
            ),
            if (message != null) ...[
              SizedBox(height: gap),
              Text(message!, style: textStyle, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}

/// An error state widget
class AppErrorState extends StatelessWidget {
  const AppErrorState({
    super.key,
    required this.message,
    this.details,
    this.onRetry,
    this.size = EmptyStateSize.md,
  });

  final String message;
  final String? details;
  final VoidCallback? onRetry;
  final EmptyStateSize size;

  @override
  Widget build(BuildContext context) {
    final sizes = context.sizes;
    final cs = context.colors;
    
    final (iconSize, titleStyle, detailsStyle, gap) = switch (size) {
      EmptyStateSize.sm => (sizes.iconLg, context.boldSm, context.subtleXs, sizes.gapSm),
      EmptyStateSize.md => (sizes.iconXl, context.boldMd, context.subtleSm, sizes.gapMd),
      EmptyStateSize.lg => (sizes.iconXl * 1.5, context.heading3, context.subtleMd, sizes.gapLg),
    };
    
    return Center(
      child: Padding(
        padding: EdgeInsets.all(sizes.gapLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(sizes.gapMd),
              decoration: BoxDecoration(
                color: cs.errorContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline,
                size: iconSize,
                color: cs.error,
              ),
            ),
            SizedBox(height: gap),
            Text(
              message,
              style: titleStyle.copyWith(color: cs.error),
              textAlign: TextAlign.center,
            ),
            if (details != null) ...[
              SizedBox(height: sizes.gapXs),
              Text(
                details!,
                style: detailsStyle,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (onRetry != null) ...[
              SizedBox(height: gap),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A no results state for search
class AppNoResultsState extends StatelessWidget {
  const AppNoResultsState({
    super.key,
    this.query,
    this.onClear,
    this.size = EmptyStateSize.md,
  });

  final String? query;
  final VoidCallback? onClear;
  final EmptyStateSize size;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: Icons.search_off,
      title: query != null ? 'No results for "$query"' : 'No results found',
      subtitle: 'Try adjusting your search or filters',
      size: size,
      action: onClear != null 
        ? TextButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.clear),
            label: const Text('Clear search'),
          )
        : null,
    );
  }
}

/// A coming soon placeholder
class AppComingSoonState extends StatelessWidget {
  const AppComingSoonState({
    super.key,
    this.feature,
    this.size = EmptyStateSize.md,
  });

  final String? feature;
  final EmptyStateSize size;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: Icons.construction,
      title: 'Coming Soon',
      subtitle: feature != null 
        ? '$feature is under development'
        : 'This feature is under development',
      size: size,
    );
  }
}
