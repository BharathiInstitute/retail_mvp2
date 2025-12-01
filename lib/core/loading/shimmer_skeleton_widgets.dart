import 'package:flutter/material.dart';
import '../theme/theme_utils.dart';

/// Shimmer effect for skeleton loaders
class ShimmerEffect extends StatefulWidget {
  final Widget child;
  final Color? baseColor;
  final Color? highlightColor;

  const ShimmerEffect({
    super.key,
    required this.child,
    this.baseColor,
    this.highlightColor,
  });

  @override
  State<ShimmerEffect> createState() => _ShimmerEffectState();
}

class _ShimmerEffectState extends State<ShimmerEffect>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _animation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final base = widget.baseColor ?? cs.surfaceContainerHighest;
    final highlight = widget.highlightColor ?? cs.surface;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [base, highlight, base],
              stops: [
                (_animation.value - 0.3).clamp(0.0, 1.0),
                _animation.value.clamp(0.0, 1.0),
                (_animation.value + 0.3).clamp(0.0, 1.0),
              ],
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcATop,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Skeleton box placeholder
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double? height;
  final double borderRadius;

  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius = 4,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// Skeleton line (for text placeholders)
class SkeletonLine extends StatelessWidget {
  final double? width;
  final double height;

  const SkeletonLine({
    super.key,
    this.width,
    this.height = 14,
  });

  @override
  Widget build(BuildContext context) {
    return SkeletonBox(
      width: width,
      height: height,
      borderRadius: height / 2,
    );
  }
}

/// Skeleton circle (for avatars)
class SkeletonCircle extends StatelessWidget {
  final double size;

  const SkeletonCircle({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHighest,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// Skeleton for a list tile
class SkeletonListTile extends StatelessWidget {
  final bool hasLeading;
  final bool hasTrailing;
  final int titleLines;
  final int subtitleLines;

  const SkeletonListTile({
    super.key,
    this.hasLeading = true,
    this.hasTrailing = false,
    this.titleLines = 1,
    this.subtitleLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    final sizes = context.sizes;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: sizes.gapMd,
        vertical: sizes.gapSm,
      ),
      child: Row(
        children: [
          if (hasLeading) ...[
            const SkeletonCircle(size: 40),
            SizedBox(width: sizes.gapMd),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < titleLines; i++) ...[
                  SkeletonLine(
                    width: i == 0 ? null : MediaQuery.of(context).size.width * 0.6,
                    height: 16,
                  ),
                  if (i < titleLines - 1) SizedBox(height: sizes.gapXs),
                ],
                if (subtitleLines > 0) ...[
                  SizedBox(height: sizes.gapXs),
                  for (int i = 0; i < subtitleLines; i++) ...[
                    SkeletonLine(
                      width: MediaQuery.of(context).size.width * (0.4 + i * 0.1),
                      height: 12,
                    ),
                    if (i < subtitleLines - 1) SizedBox(height: sizes.gapXs),
                  ],
                ],
              ],
            ),
          ),
          if (hasTrailing) ...[
            SizedBox(width: sizes.gapMd),
            SkeletonBox(width: 60, height: 24, borderRadius: 4),
          ],
        ],
      ),
    );
  }
}

/// Skeleton for a card
class SkeletonCard extends StatelessWidget {
  final double? width;
  final double height;

  const SkeletonCard({
    super.key,
    this.width,
    this.height = 120,
  });

  @override
  Widget build(BuildContext context) {
    final sizes = context.sizes;

    return Container(
      width: width,
      height: height,
      padding: EdgeInsets.all(sizes.gapMd),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(sizes.radiusMd),
        border: Border.all(color: context.colors.outlineVariant.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SkeletonCircle(size: 32),
              SizedBox(width: sizes.gapSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SkeletonLine(height: 14),
                    SizedBox(height: sizes.gapXs),
                    SkeletonLine(width: 100, height: 10),
                  ],
                ),
              ),
            ],
          ),
          const Spacer(),
          const SkeletonLine(height: 12),
          SizedBox(height: sizes.gapXs),
          SkeletonLine(width: 150, height: 12),
        ],
      ),
    );
  }
}

/// Skeleton for a data table row
class SkeletonTableRow extends StatelessWidget {
  final int columns;
  final double rowHeight;

  const SkeletonTableRow({
    super.key,
    this.columns = 5,
    this.rowHeight = 48,
  });

  @override
  Widget build(BuildContext context) {
    final sizes = context.sizes;

    return Container(
      height: rowHeight,
      padding: EdgeInsets.symmetric(horizontal: sizes.gapMd),
      child: Row(
        children: List.generate(columns, (i) {
          return Expanded(
            flex: i == 0 ? 2 : 1,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: sizes.gapSm),
              child: SkeletonLine(
                width: i == 0 ? null : 60,
                height: 14,
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Skeleton list builder
class SkeletonList extends StatelessWidget {
  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final bool enableShimmer;

  const SkeletonList({
    super.key,
    this.itemCount = 5,
    required this.itemBuilder,
    this.enableShimmer = true,
  });

  /// Factory for list tile skeletons
  factory SkeletonList.listTiles({
    int itemCount = 5,
    bool hasLeading = true,
    bool hasTrailing = false,
    bool enableShimmer = true,
  }) {
    return SkeletonList(
      itemCount: itemCount,
      enableShimmer: enableShimmer,
      itemBuilder: (_, __) => SkeletonListTile(
        hasLeading: hasLeading,
        hasTrailing: hasTrailing,
      ),
    );
  }

  /// Factory for table row skeletons
  factory SkeletonList.tableRows({
    int itemCount = 10,
    int columns = 5,
    bool enableShimmer = true,
  }) {
    return SkeletonList(
      itemCount: itemCount,
      enableShimmer: enableShimmer,
      itemBuilder: (_, __) => SkeletonTableRow(columns: columns),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: itemCount,
      itemBuilder: itemBuilder,
    );

    if (enableShimmer) {
      return ShimmerEffect(child: list);
    }
    return list;
  }
}
