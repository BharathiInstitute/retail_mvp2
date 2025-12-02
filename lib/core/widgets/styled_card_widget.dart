import 'package:flutter/material.dart';
import 'package:retail_mvp2/core/theme/theme_extension_helpers.dart';

/// Card size variants
enum CardSize { sm, md, lg }

/// A themed card widget with consistent styling and size variants.
/// 
/// Usage:
/// ```dart
/// AppCard(
///   child: Text('Content'),
///   size: CardSize.md,
///   onTap: () => print('tapped'),
/// )
/// ```
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.size = CardSize.md,
    this.padding,
    this.margin,
    this.onTap,
    this.onLongPress,
    this.color,
    this.borderColor,
    this.borderRadius,
    this.elevation,
    this.clipBehavior = Clip.antiAlias,
  });

  /// The content of the card
  final Widget child;
  
  /// Size variant affecting padding
  final CardSize size;
  
  /// Custom padding (overrides size-based padding)
  final EdgeInsets? padding;
  
  /// Margin around the card
  final EdgeInsets? margin;
  
  /// Tap callback
  final VoidCallback? onTap;
  
  /// Long press callback
  final VoidCallback? onLongPress;
  
  /// Background color (defaults to surfaceContainerLow)
  final Color? color;
  
  /// Border color (optional)
  final Color? borderColor;
  
  /// Custom border radius
  final BorderRadius? borderRadius;
  
  /// Card elevation (defaults to 0 for flat design)
  final double? elevation;
  
  /// Clip behavior
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final sizes = context.sizes;
    final cs = context.colors;
    
    // Size-based padding
    final effectivePadding = padding ?? switch (size) {
      CardSize.sm => EdgeInsets.all(sizes.cardPadSm),
      CardSize.md => EdgeInsets.all(sizes.cardPadMd),
      CardSize.lg => EdgeInsets.all(sizes.cardPadLg),
    };
    
    final effectiveRadius = borderRadius ?? BorderRadius.circular(sizes.radiusMd);
    
    final card = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: color ?? cs.surfaceContainerLow,
        borderRadius: effectiveRadius,
        border: borderColor != null 
          ? Border.all(color: borderColor!, width: 1)
          : Border.all(color: cs.outlineVariant.withOpacity(0.3), width: 1),
      ),
      clipBehavior: clipBehavior,
      child: Padding(
        padding: effectivePadding,
        child: child,
      ),
    );
    
    if (onTap != null || onLongPress != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: effectiveRadius,
          child: card,
        ),
      );
    }
    
    return card;
  }
}

/// A card variant with a header section
class AppCardWithHeader extends StatelessWidget {
  const AppCardWithHeader({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.size = CardSize.md,
    this.margin,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final CardSize size;
  final EdgeInsets? margin;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final sizes = context.sizes;
    
    return AppCard(
      size: size,
      margin: margin,
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: EdgeInsets.fromLTRB(
              sizes.cardPadMd, 
              sizes.cardPadMd, 
              sizes.cardPadMd, 
              sizes.gapSm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: context.boldMd),
                      if (subtitle != null) ...[
                        SizedBox(height: sizes.gapXs),
                        Text(subtitle!, style: context.subtleSm),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          
          Divider(height: 1, color: context.colors.outlineVariant.withOpacity(0.3)),
          
          // Content
          Padding(
            padding: EdgeInsets.all(sizes.cardPadMd),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// A stat card for displaying metrics
class AppStatCard extends StatelessWidget {
  const AppStatCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.iconColor,
    this.trend,
    this.trendPositive,
    this.onTap,
    this.size = CardSize.md,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? iconColor;
  final String? trend;
  final bool? trendPositive;
  final VoidCallback? onTap;
  final CardSize size;

  @override
  Widget build(BuildContext context) {
    final sizes = context.sizes;
    final cs = context.colors;
    
    return AppCard(
      size: size,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: sizes.iconSm, color: iconColor ?? cs.primary),
                SizedBox(width: sizes.gapSm),
              ],
              Expanded(
                child: Text(label, style: context.subtleSm, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          SizedBox(height: sizes.gapSm),
          Text(value, style: context.heading2),
          if (trend != null) ...[
            SizedBox(height: sizes.gapXs),
            Row(
              children: [
                Icon(
                  trendPositive == true ? Icons.trending_up : Icons.trending_down,
                  size: sizes.iconXs,
                  color: trendPositive == true ? context.appColors.success : cs.error,
                ),
                SizedBox(width: sizes.gapXs),
                Text(
                  trend!,
                  style: TextStyle(
                    fontSize: sizes.fontXs,
                    color: trendPositive == true ? context.appColors.success : cs.error,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
