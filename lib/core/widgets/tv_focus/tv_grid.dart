import 'package:flutter/material.dart';

/// TV 网格（Grid）：二维焦点导航的卡片网格，支持 D-pad 上下左右。
///
/// - **焦点遍历**：使用 [FocusTraversalGroup] + [OrderedTraversalPolicy] 确保
///   上下左右键按行列顺序导航。
/// - **自动滚动**：内部自动包装 [TvFocusScroll]，无需手动嵌套。
/// - **布局**：使用 [GridView.builder] + [SliverGridDelegateWithFixedCrossAxisCount]
///   实现固定列数的响应式网格。
///
/// 使用场景：
/// - TV 应用网格、视频库网格、相册网格等二维布局。
/// - 每个 item 应该是 [TvFocusable] 包装的卡片。
///
/// 示例：
/// ```dart
/// TvGrid(
///   crossAxisCount: 4,
///   itemCount: items.length,
///   itemBuilder: (context, i) => TvFocusable(
///     onPressed: () => _open(items[i]),
///     child: AppCard(items[i]),
///   ),
/// )
/// ```
class TvGrid extends StatelessWidget {
  const TvGrid({
    required this.itemCount,
    required this.itemBuilder,
    this.crossAxisCount = 4,
    this.mainAxisSpacing = 24,
    this.crossAxisSpacing = 24,
    this.childAspectRatio = 16 / 9,
    this.padding = const EdgeInsets.all(48),
    super.key,
  });

  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final int crossAxisCount;
  final double mainAxisSpacing;
  final double crossAxisSpacing;
  final double childAspectRatio;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: GridView.builder(
          padding: padding,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: mainAxisSpacing,
            crossAxisSpacing: crossAxisSpacing,
            childAspectRatio: childAspectRatio,
          ),
          itemCount: itemCount,
          itemBuilder: itemBuilder,
        ),
      );
}
