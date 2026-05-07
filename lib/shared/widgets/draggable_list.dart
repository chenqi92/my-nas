import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';

/// 可拖放列表
///
/// 支持拖放排序的列表组件，仅桌面端启用拖放
///
/// 示例：
/// ```dart
/// DraggableList<MusicFile>(
///   items: playlist,
///   itemBuilder: (context, item, index, isDragging) => ListTile(
///     title: Text(item.name),
///   ),
///   onReorder: (oldIndex, newIndex) {
///     // 更新列表顺序
///   },
/// )
/// ```
class DraggableList<T> extends StatefulWidget {
  const DraggableList({
    super.key,
    required this.items,
    required this.itemBuilder,
    required this.onReorder,
    this.itemExtent,
    this.shrinkWrap = false,
    this.physics,
    this.padding,
    this.scrollController,
    this.enableDrag = true,
    this.dragHandleBuilder,
    this.onDragStart,
    this.onDragEnd,
    this.proxyDecorator,
  });

  /// 数据列表
  final List<T> items;

  /// 项目构建器
  /// [isDragging] 表示当前项是否正在被拖动
  final Widget Function(BuildContext context, T item, int index, bool isDragging) itemBuilder;

  /// 重新排序回调
  final void Function(int oldIndex, int newIndex) onReorder;

  /// 固定项目高度
  final double? itemExtent;

  /// 是否收缩包裹
  final bool shrinkWrap;

  /// 滚动物理特性
  final ScrollPhysics? physics;

  /// 内边距
  final EdgeInsets? padding;

  /// 滚动控制器
  final ScrollController? scrollController;

  /// 是否启用拖放（默认桌面端启用）
  final bool enableDrag;

  /// 拖动手柄构建器（如果提供，只有手柄区域可以拖动）
  final Widget Function(BuildContext context)? dragHandleBuilder;

  /// 拖动开始回调
  final void Function(int index)? onDragStart;

  /// 拖动结束回调
  final void Function(int index)? onDragEnd;

  /// 拖动代理装饰器
  final Widget Function(Widget child, int index, Animation<double> animation)? proxyDecorator;

  @override
  State<DraggableList<T>> createState() => _DraggableListState<T>();
}

class _DraggableListState<T> extends State<DraggableList<T>> {
  int? _draggingIndex;

  @override
  Widget build(BuildContext context) {
    final isDesktop = context.isDesktopLayout;
    final enableDrag = widget.enableDrag && isDesktop;

    if (!enableDrag) {
      // 移动端使用普通列表
      return ListView.builder(
        controller: widget.scrollController,
        shrinkWrap: widget.shrinkWrap,
        physics: widget.physics,
        padding: widget.padding,
        itemExtent: widget.itemExtent,
        itemCount: widget.items.length,
        itemBuilder: (context, index) =>
            widget.itemBuilder(context, widget.items[index], index, false),
      );
    }

    // 桌面端使用可拖放列表
    return ReorderableListView.builder(
      scrollController: widget.scrollController,
      shrinkWrap: widget.shrinkWrap,
      physics: widget.physics,
      padding: widget.padding,
      itemExtent: widget.itemExtent,
      itemCount: widget.items.length,
      onReorder: _handleReorder,
      proxyDecorator: widget.proxyDecorator ?? _defaultProxyDecorator,
      buildDefaultDragHandles: widget.dragHandleBuilder == null,
      itemBuilder: (context, index) {
        final item = widget.items[index];
        final isDragging = _draggingIndex == index;

        Widget child = widget.itemBuilder(context, item, index, isDragging);

        // 如果提供了拖动手柄，添加手柄
        if (widget.dragHandleBuilder != null) {
          child = Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: widget.dragHandleBuilder!(context),
                ),
              ),
              Expanded(child: child),
            ],
          );
        }

        return KeyedSubtree(
          key: ValueKey(item),
          child: child,
        );
      },
    );
  }

  void _handleReorder(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    widget.onReorder(oldIndex, newIndex);
  }

  Widget _defaultProxyDecorator(
    Widget child,
    int index,
    Animation<double> animation,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final scale = Tween<double>(begin: 1, end: 1.02).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOut),
        );

        return Transform.scale(
          scale: scale.value,
          child: Material(
            elevation: 8 * animation.value,
            shadowColor: Colors.black.withValues(alpha: 0.2),
            color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
            borderRadius: BorderRadius.circular(8),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// 可拖放网格
///
/// 支持拖放排序的网格组件
class DraggableGrid<T> extends StatefulWidget {
  const DraggableGrid({
    super.key,
    required this.items,
    required this.itemBuilder,
    required this.onReorder,
    required this.crossAxisCount,
    this.mainAxisSpacing = 8,
    this.crossAxisSpacing = 8,
    this.childAspectRatio = 1,
    this.shrinkWrap = false,
    this.physics,
    this.padding,
    this.scrollController,
    this.enableDrag = true,
    this.onDragStart,
    this.onDragEnd,
  });

  final List<T> items;
  final Widget Function(BuildContext context, T item, int index, bool isDragging) itemBuilder;
  final void Function(int oldIndex, int newIndex) onReorder;
  final int crossAxisCount;
  final double mainAxisSpacing;
  final double crossAxisSpacing;
  final double childAspectRatio;
  final bool shrinkWrap;
  final ScrollPhysics? physics;
  final EdgeInsets? padding;
  final ScrollController? scrollController;
  final bool enableDrag;
  final void Function(int index)? onDragStart;
  final void Function(int index)? onDragEnd;

  @override
  State<DraggableGrid<T>> createState() => _DraggableGridState<T>();
}

class _DraggableGridState<T> extends State<DraggableGrid<T>> {
  @override
  Widget build(BuildContext context) {
    final isDesktop = context.isDesktopLayout;
    final enableDrag = widget.enableDrag && isDesktop;

    if (!enableDrag) {
      return GridView.builder(
        controller: widget.scrollController,
        shrinkWrap: widget.shrinkWrap,
        physics: widget.physics,
        padding: widget.padding,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: widget.crossAxisCount,
          mainAxisSpacing: widget.mainAxisSpacing,
          crossAxisSpacing: widget.crossAxisSpacing,
          childAspectRatio: widget.childAspectRatio,
        ),
        itemCount: widget.items.length,
        itemBuilder: (context, index) =>
            widget.itemBuilder(context, widget.items[index], index, false),
      );
    }

    // 桌面端使用自定义拖放网格
    return _DraggableGridView<T>(
      items: widget.items,
      itemBuilder: widget.itemBuilder,
      onReorder: widget.onReorder,
      crossAxisCount: widget.crossAxisCount,
      mainAxisSpacing: widget.mainAxisSpacing,
      crossAxisSpacing: widget.crossAxisSpacing,
      childAspectRatio: widget.childAspectRatio,
      shrinkWrap: widget.shrinkWrap,
      physics: widget.physics,
      padding: widget.padding,
      scrollController: widget.scrollController,
    );
  }
}

/// 自定义拖放网格视图
class _DraggableGridView<T> extends StatefulWidget {
  const _DraggableGridView({
    required this.items,
    required this.itemBuilder,
    required this.onReorder,
    required this.crossAxisCount,
    this.mainAxisSpacing = 8,
    this.crossAxisSpacing = 8,
    this.childAspectRatio = 1,
    this.shrinkWrap = false,
    this.physics,
    this.padding,
    this.scrollController,
  });

  final List<T> items;
  final Widget Function(BuildContext context, T item, int index, bool isDragging) itemBuilder;
  final void Function(int oldIndex, int newIndex) onReorder;
  final int crossAxisCount;
  final double mainAxisSpacing;
  final double crossAxisSpacing;
  final double childAspectRatio;
  final bool shrinkWrap;
  final ScrollPhysics? physics;
  final EdgeInsets? padding;
  final ScrollController? scrollController;

  @override
  State<_DraggableGridView<T>> createState() => _DraggableGridViewState<T>();
}

class _DraggableGridViewState<T> extends State<_DraggableGridView<T>> {
  int? _draggingIndex;
  int? _targetIndex;

  @override
  Widget build(BuildContext context) => GridView.builder(
      controller: widget.scrollController,
      shrinkWrap: widget.shrinkWrap,
      physics: widget.physics,
      padding: widget.padding,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: widget.crossAxisCount,
        mainAxisSpacing: widget.mainAxisSpacing,
        crossAxisSpacing: widget.crossAxisSpacing,
        childAspectRatio: widget.childAspectRatio,
      ),
      itemCount: widget.items.length,
      itemBuilder: (context, index) {
        final item = widget.items[index];
        final isDragging = _draggingIndex == index;
        final isTarget = _targetIndex == index;

        return DragTarget<int>(
          onWillAcceptWithDetails: (details) {
            if (details.data != index) {
              setState(() => _targetIndex = index);
              return true;
            }
            return false;
          },
          onLeave: (_) {
            if (_targetIndex == index) {
              setState(() => _targetIndex = null);
            }
          },
          onAcceptWithDetails: (details) {
            widget.onReorder(details.data, index);
            setState(() {
              _draggingIndex = null;
              _targetIndex = null;
            });
          },
          builder: (context, candidateData, rejectedData) {
            Widget child = widget.itemBuilder(context, item, index, isDragging);

            // 目标位置高亮
            if (isTarget && candidateData.isNotEmpty) {
              child = Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: child,
              );
            }

            return Draggable<int>(
              data: index,
              onDragStarted: () {
                setState(() => _draggingIndex = index);
                HapticFeedback.lightImpact();
              },
              onDragEnd: (_) {
                setState(() {
                  _draggingIndex = null;
                  _targetIndex = null;
                });
              },
              feedback: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: _calculateItemWidth(context),
                  child: Opacity(
                    opacity: 0.9,
                    child: widget.itemBuilder(context, item, index, true),
                  ),
                ),
              ),
              childWhenDragging: Opacity(
                opacity: 0.3,
                child: child,
              ),
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: child,
              ),
            );
          },
        );
      },
    );

  double _calculateItemWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final padding = widget.padding;
    final horizontalPadding = padding is EdgeInsets
        ? padding.horizontal
        : 0.0;
    final totalSpacing = (widget.crossAxisCount - 1) * widget.crossAxisSpacing;
    return (screenWidth - horizontalPadding - totalSpacing) / widget.crossAxisCount;
  }
}

/// 拖动手柄组件
class DragHandle extends StatelessWidget {
  const DragHandle({
    super.key,
    this.size = 24,
    this.color,
  });

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ??
        Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5);

    return SizedBox(
      width: size,
      height: size,
      child: Icon(
        Icons.drag_indicator_rounded,
        size: size * 0.8,
        color: effectiveColor,
      ),
    );
  }
}
