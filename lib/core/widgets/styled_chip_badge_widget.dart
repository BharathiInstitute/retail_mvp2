import 'package:flutter/material.dart';
import 'package:retail_mvp2/core/theme/theme_utils.dart';

/// Chip size variants
enum ChipSize { sm, md, lg }

/// Chip style variants
enum ChipVariant { filled, outlined, soft }

/// A themed chip/badge widget with consistent styling.
/// 
/// Usage:
/// ```dart
/// AppChip(
///   label: 'Active',
///   color: Colors.green,
///   size: ChipSize.sm,
/// )
/// ```
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    this.color,
    this.size = ChipSize.md,
    this.variant = ChipVariant.soft,
    this.icon,
    this.onTap,
    this.onDelete,
  });

  /// Chip label text
  final String label;
  
  /// Chip color (defaults to primary)
  final Color? color;
  
  /// Size variant
  final ChipSize size;
  
  /// Style variant
  final ChipVariant variant;
  
  /// Optional leading icon
  final IconData? icon;
  
  /// Tap callback
  final VoidCallback? onTap;
  
  /// Delete callback (shows X button)
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final sizes = context.sizes;
    final cs = context.colors;
    final effectiveColor = color ?? cs.primary;
    
    // Size-based dimensions
    final (vPad, hPad, fontSize, iconSize) = switch (size) {
      ChipSize.sm => (2.0, sizes.gapXs, sizes.fontXs, sizes.iconXs),
      ChipSize.md => (4.0, sizes.gapSm, sizes.fontSm, sizes.iconSm),
      ChipSize.lg => (6.0, sizes.gapMd, sizes.fontMd, sizes.iconMd),
    };
    
    // Variant-based colors
    final (bgColor, fgColor, borderColor) = switch (variant) {
      ChipVariant.filled => (effectiveColor, _contrastColor(effectiveColor), Colors.transparent),
      ChipVariant.outlined => (Colors.transparent, effectiveColor, effectiveColor),
      ChipVariant.soft => (effectiveColor.withOpacity(0.15), effectiveColor, Colors.transparent),
    };
    
    Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: iconSize, color: fgColor),
          SizedBox(width: sizes.gapXs),
        ],
        Text(
          label,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w500,
            color: fgColor,
          ),
        ),
        if (onDelete != null) ...[
          SizedBox(width: sizes.gapXs),
          GestureDetector(
            onTap: onDelete,
            child: Icon(Icons.close, size: iconSize, color: fgColor),
          ),
        ],
      ],
    );
    
    final chip = Container(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(sizes.radiusSm),
        border: borderColor != Colors.transparent 
          ? Border.all(color: borderColor, width: 1)
          : null,
      ),
      child: content,
    );
    
    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(sizes.radiusSm),
          child: chip,
        ),
      );
    }
    
    return chip;
  }
  
  /// Get contrasting text color
  Color _contrastColor(Color bg) {
    return bg.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
  }
}

/// Status chip with predefined colors
class AppStatusChip extends StatelessWidget {
  const AppStatusChip({
    super.key,
    required this.status,
    this.size = ChipSize.sm,
  });

  final StatusType status;
  final ChipSize size;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    
    final (label, color, icon) = switch (status) {
      StatusType.active => ('Active', appColors.success, Icons.check_circle_outline),
      StatusType.inactive => ('Inactive', context.colors.outline, Icons.remove_circle_outline),
      StatusType.pending => ('Pending', appColors.warning, Icons.access_time),
      StatusType.error => ('Error', context.colors.error, Icons.error_outline),
      StatusType.success => ('Success', appColors.success, Icons.check_circle),
      StatusType.warning => ('Warning', appColors.warning, Icons.warning_amber),
      StatusType.info => ('Info', context.colors.primary, Icons.info_outline),
    };
    
    return AppChip(
      label: label,
      color: color,
      icon: icon,
      size: size,
      variant: ChipVariant.soft,
    );
  }
}

/// Predefined status types
enum StatusType { active, inactive, pending, error, success, warning, info }

/// Badge for counts (e.g., notification count)
class AppBadge extends StatelessWidget {
  const AppBadge({
    super.key,
    required this.count,
    this.color,
    this.maxCount = 99,
    this.showZero = false,
    this.size = ChipSize.sm,
  });

  final int count;
  final Color? color;
  final int maxCount;
  final bool showZero;
  final ChipSize size;

  @override
  Widget build(BuildContext context) {
    if (count == 0 && !showZero) return const SizedBox.shrink();
    
    final sizes = context.sizes;
    final cs = context.colors;
    final effectiveColor = color ?? cs.error;
    
    final displayCount = count > maxCount ? '$maxCount+' : count.toString();
    
    final (minSize, fontSize) = switch (size) {
      ChipSize.sm => (16.0, sizes.fontXs),
      ChipSize.md => (20.0, sizes.fontSm),
      ChipSize.lg => (24.0, sizes.fontMd),
    };
    
    return Container(
      constraints: BoxConstraints(minWidth: minSize, minHeight: minSize),
      padding: EdgeInsets.symmetric(horizontal: sizes.gapXs),
      decoration: BoxDecoration(
        color: effectiveColor,
        borderRadius: BorderRadius.circular(minSize / 2),
      ),
      alignment: Alignment.center,
      child: Text(
        displayCount,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Selectable chip for filters
class AppFilterChip extends StatelessWidget {
  const AppFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.icon,
    this.size = ChipSize.md,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final IconData? icon;
  final ChipSize size;

  @override
  Widget build(BuildContext context) {
    final sizes = context.sizes;
    final cs = context.colors;
    
    final (vPad, hPad, fontSize, iconSize) = switch (size) {
      ChipSize.sm => (4.0, sizes.gapSm, sizes.fontSm, sizes.iconSm),
      ChipSize.md => (6.0, sizes.gapMd, sizes.fontMd, sizes.iconMd),
      ChipSize.lg => (8.0, sizes.gapLg, sizes.fontLg, sizes.iconLg),
    };
    
    return Material(
      color: selected ? cs.primaryContainer : cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(sizes.radiusMd),
      child: InkWell(
        onTap: () => onSelected(!selected),
        borderRadius: BorderRadius.circular(sizes.radiusMd),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(sizes.radiusMd),
            border: Border.all(
              color: selected ? cs.primary : cs.outline.withOpacity(0.3),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: iconSize,
                  color: selected ? cs.primary : cs.onSurfaceVariant,
                ),
                SizedBox(width: sizes.gapXs),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? cs.primary : cs.onSurface,
                ),
              ),
              if (selected) ...[
                SizedBox(width: sizes.gapXs),
                Icon(Icons.check, size: iconSize, color: cs.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
