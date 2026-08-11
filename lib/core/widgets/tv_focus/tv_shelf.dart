import 'package:flutter/material.dart';

/// TV 横向货架（Shelf）：水平滚动的卡片列表，支持 D-pad 左右导航。
///
/// - **焦点分组**：每个货架是独立的 [FocusTraversalGroup]，左右键在货架内循环，
///   上下键跳到其他货架。
/// - **自动滚动**：内部自动包装 [TvFocusScroll]，无需手动嵌套。
/// - **布局**：固定高度 [height]，内部用 [ListView.builder] 横向铺开，item 间距
///   [spacing]。
///
/// 使用场景：
/// - TV 首页「继续观看」「最近添加」等横向滚动货架。
/// - 每个 item 应该是 [TvFocusable] 包装的卡片。
///
/// 示例：
/// ```dart
/// TvShelf(
///   height: 200,
///   itemCount: items.length,
///   itemBuilder: (context, i) => TvFocusable(
///     onPressed: () => _play(items[i]),
///     child: VideoCard(items[i]),
///   ),
/// )
/// ```
class TvShelf extends StatelessWidget {
  const TvShelf({
    required this.itemCount,
    required this.itemBuilder,
    this.height = 200,
    this.spacing = 16,
    this.padding = const EdgeInsets.symmetric(horizontal: 48),
    super.key,
  });

  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final double height;
  final double spacing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: SizedBox(
          height: height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: padding,
            itemCount: itemCount,
            separatorBuilder: (context, index) => SizedBox(width: spacing),
            itemBuilder: itemBuilder,
          ),
        ),
      );
}
