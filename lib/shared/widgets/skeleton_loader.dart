import 'package:flutter/material.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';

/// 骨架屏加载效果
class SkeletonLoader extends StatefulWidget {
  const SkeletonLoader({
    required this.child,
    this.baseColor,
    this.highlightColor,
    super.key,
  });

  final Widget child;
  final Color? baseColor;
  final Color? highlightColor;

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader>
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

    _animation = Tween<double>(begin: -1, end: 2).animate(
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
    final baseColor = widget.baseColor ?? context.placeholderColor;
    final highlightColor = widget.highlightColor ?? context.placeholderHighlightColor;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) => ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
              colors: [
                baseColor,
                highlightColor,
                baseColor,
              ],
              stops: [
                (_animation.value - 0.3).clamp(0.0, 1.0),
                _animation.value.clamp(0.0, 1.0),
                (_animation.value + 0.3).clamp(0.0, 1.0),
              ],
            ).createShader(bounds),
          blendMode: BlendMode.srcATop,
          child: widget.child,
        ),
    );
  }
}

/// 骨架屏占位块
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    this.width,
    this.height,
    this.borderRadius = 8,
    super.key,
  });

  final double? width;
  final double? height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.placeholderColor,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
}

/// 文件列表骨架屏
class FileListSkeleton extends StatelessWidget {
  const FileListSkeleton({
    this.itemCount = 8,
    this.isGridView = false,
    super.key,
  });

  final int itemCount;
  final bool isGridView;

  @override
  Widget build(BuildContext context) => SkeletonLoader(
      child: isGridView ? _buildGridSkeleton(context) : _buildListSkeleton(context),
    );

  Widget _buildListSkeleton(BuildContext context) => ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: itemCount,
      itemBuilder: (context, index) => _FileListItemSkeleton(index: index),
    );

  Widget _buildGridSkeleton(BuildContext context) => GridView.builder(
      padding: const EdgeInsets.all(16),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 120,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) => _FileGridItemSkeleton(index: index),
    );
}

class _FileListItemSkeleton extends StatelessWidget {
  const _FileListItemSkeleton({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final placeholderColor = context.placeholderColor;
    final placeholderLightColor = context.placeholderHighlightColor;
    // 交错的透明度，让骨架屏更自然
    final opacity = 1.0 - (index * 0.08).clamp(0.0, 0.4);

    return Opacity(
      opacity: opacity,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // 图标占位
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: placeholderColor,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题占位
                  Container(
                    width: double.infinity,
                    height: 16,
                    decoration: BoxDecoration(
                      color: placeholderColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 副标题占位
                  Container(
                    width: 100,
                    height: 12,
                    decoration: BoxDecoration(
                      color: placeholderLightColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileGridItemSkeleton extends StatelessWidget {
  const _FileGridItemSkeleton({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final placeholderColor = context.placeholderColor;
    final placeholderLightColor = context.placeholderHighlightColor;
    final opacity = 1.0 - (index * 0.06).clamp(0.0, 0.4);

    return Opacity(
      opacity: opacity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: placeholderLightColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 图标占位
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: placeholderColor,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 12),
            // 标题占位
            Container(
              width: 60,
              height: 12,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: placeholderColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
