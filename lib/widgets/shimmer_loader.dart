import 'package:flutter/material.dart';
import 'package:digi_sanchika/utils/app_theme.dart';

/// Animated shimmer skeleton — drop in wherever you have a loading state.
///
/// Usage:
///   ShimmerLoader(child: _buildSkeletonCard())
///   ShimmerBox(width: double.infinity, height: 18)     // inline block
///   ShimmerListLoader(itemCount: 5)                    // full list skeleton
class ShimmerLoader extends StatefulWidget {
  final Widget child;
  const ShimmerLoader({super.key, required this.child});

  @override
  State<ShimmerLoader> createState() => _ShimmerLoaderState();
}

class _ShimmerLoaderState extends State<ShimmerLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _anim = Tween<double>(begin: -2, end: 2).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment(_anim.value - 1, 0),
          end: Alignment(_anim.value + 1, 0),
          colors: const [
            Color(0xFFECEFF9),
            Color(0xFFFFFFFF),
            Color(0xFFECEFF9),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(bounds),
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// A single shimmer placeholder block (rounded rectangle).
class ShimmerBox extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const ShimmerBox({
    super.key,
    required this.width,
    required this.height,
    this.radius = AppRadius.xs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFECEFF9),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Full-page list of document card skeletons.
class ShimmerListLoader extends StatelessWidget {
  final int itemCount;
  const ShimmerListLoader({super.key, this.itemCount = 6});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoader(
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: itemCount,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, _) => _DocumentCardSkeleton(),
      ),
    );
  }
}

/// A single document-card-shaped skeleton.
class _DocumentCardSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const ShimmerBox(width: 44, height: 44, radius: AppRadius.sm),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    ShimmerBox(width: double.infinity, height: 14),
                    SizedBox(height: 6),
                    ShimmerBox(width: 120, height: 11),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const ShimmerBox(width: 52, height: 22, radius: AppRadius.pill),
            ],
          ),
          const SizedBox(height: 14),
          const ShimmerBox(width: double.infinity, height: 1),
          const SizedBox(height: 12),
          Row(
            children: const [
              ShimmerBox(width: 70, height: 22, radius: AppRadius.pill),
              SizedBox(width: 8),
              ShimmerBox(width: 90, height: 22, radius: AppRadius.pill),
              SizedBox(width: 8),
              ShimmerBox(width: 60, height: 22, radius: AppRadius.pill),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: const [
              Expanded(child: ShimmerBox(width: double.infinity, height: 34)),
              SizedBox(width: 8),
              Expanded(child: ShimmerBox(width: double.infinity, height: 34)),
              SizedBox(width: 8),
              Expanded(child: ShimmerBox(width: double.infinity, height: 34)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Folder grid skeleton — 2-column grid.
class ShimmerFolderGridLoader extends StatelessWidget {
  final int itemCount;
  const ShimmerFolderGridLoader({super.key, this.itemCount = 6});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoader(
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 1.1,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: itemCount,
        itemBuilder: (_, _) => Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.border),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ShimmerBox(width: 44, height: 44, radius: AppRadius.sm),
              SizedBox(height: 10),
              ShimmerBox(width: 80, height: 12),
              SizedBox(height: 6),
              ShimmerBox(width: 50, height: 10),
            ],
          ),
        ),
      ),
    );
  }
}

/// Notification item skeleton.
class ShimmerNotificationLoader extends StatelessWidget {
  final int itemCount;
  const ShimmerNotificationLoader({super.key, this.itemCount = 5});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoader(
      child: ListView.separated(
        padding: const EdgeInsets.all(14),
        itemCount: itemCount,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, _) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ShimmerBox(width: 38, height: 38, radius: AppRadius.sm),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    ShimmerBox(width: double.infinity, height: 13),
                    SizedBox(height: 6),
                    ShimmerBox(width: double.infinity, height: 11),
                    SizedBox(height: 4),
                    ShimmerBox(width: 90, height: 10),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
