import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/shared/widgets/hoverable_widget.dart';

/// 表格列定义
class TableColumn<T> {
  const TableColumn({
    required this.id,
    required this.title,
    required this.cellBuilder,
    this.width,
    this.flex = 1,
    this.minWidth = 80,
    this.sortable = false,
    this.alignment = Alignment.centerLeft,
    this.headerBuilder,
    this.comparator,
  });

  /// 列 ID
  final String id;

  /// 列标题
  final String title;

  /// 单元格构建器
  final Widget Function(BuildContext context, T item, int index) cellBuilder;

  /// 固定宽度（优先于 flex）
  final double? width;

  /// 弹性比例
  final int flex;

  /// 最小宽度
  final double minWidth;

  /// 是否可排序
  final bool sortable;

  /// 对齐方式
  final Alignment alignment;

  /// 自定义表头构建器
  final Widget Function(BuildContext context, bool isAscending)? headerBuilder;

  /// 排序比较器
  final int Function(T a, T b)? comparator;
}

/// 排序状态
class SortState {
  const SortState({
    required this.columnId,
    required this.ascending,
  });

  final String columnId;
  final bool ascending;

  SortState copyWith({String? columnId, bool? ascending}) => SortState(
      columnId: columnId ?? this.columnId,
      ascending: ascending ?? this.ascending,
    );
}

/// 自适应表格视图
///
/// 桌面端显示带有可排序表头的表格视图
/// 适用于文件列表、音乐列表等需要显示多列数据的场景
///
/// 示例：
/// ```dart
/// AdaptiveTableView<MusicFile>(
///   items: musicFiles,
///   columns: [
///     TableColumn(
///       id: 'name',
///       title: '名称',
///       flex: 3,
///       sortable: true,
///       cellBuilder: (context, item, index) => Text(item.name),
///     ),
///     TableColumn(
///       id: 'artist',
///       title: '艺术家',
///       flex: 2,
///       cellBuilder: (context, item, index) => Text(item.artist ?? ''),
///     ),
///     TableColumn(
///       id: 'duration',
///       title: '时长',
///       width: 80,
///       cellBuilder: (context, item, index) => Text(item.durationFormatted),
///     ),
///   ],
///   onTap: (item, index) => playMusic(item),
/// )
/// ```
class AdaptiveTableView<T> extends StatefulWidget {
  const AdaptiveTableView({
    super.key,
    required this.items,
    required this.columns,
    this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.onSort,
    this.initialSortState,
    this.selectedIndex,
    this.selectedIndices,
    this.multiSelect = false,
    this.onSelectionChanged,
    this.rowHeight,
    this.headerHeight,
    this.showHeader = true,
    this.showDividers = true,
    this.alternateRowColors = true,
    this.stickyHeader = true,
    this.padding,
    this.controller,
    this.physics,
    this.shrinkWrap = false,
  });

  /// 数据项列表
  final List<T> items;

  /// 列定义
  final List<TableColumn<T>> columns;

  /// 点击回调
  final void Function(T item, int index)? onTap;

  /// 双击回调
  final void Function(T item, int index)? onDoubleTap;

  /// 长按回调
  final void Function(T item, int index)? onLongPress;

  /// 右键回调
  final void Function(T item, int index)? onSecondaryTap;

  /// 排序回调
  final void Function(SortState sortState)? onSort;

  /// 初始排序状态
  final SortState? initialSortState;

  /// 选中的单个索引
  final int? selectedIndex;

  /// 选中的多个索引
  final Set<int>? selectedIndices;

  /// 是否多选模式
  final bool multiSelect;

  /// 选择变化回调
  final void Function(Set<int> indices)? onSelectionChanged;

  /// 行高
  final double? rowHeight;

  /// 表头高度
  final double? headerHeight;

  /// 是否显示表头
  final bool showHeader;

  /// 是否显示分隔线
  final bool showDividers;

  /// 是否交替行颜色
  final bool alternateRowColors;

  /// 表头是否固定
  final bool stickyHeader;

  /// 内边距
  final EdgeInsetsGeometry? padding;

  /// 滚动控制器
  final ScrollController? controller;

  /// 滚动物理特性
  final ScrollPhysics? physics;

  /// 是否收缩包裹
  final bool shrinkWrap;

  @override
  State<AdaptiveTableView<T>> createState() => _AdaptiveTableViewState<T>();
}

class _AdaptiveTableViewState<T> extends State<AdaptiveTableView<T>> {
  late SortState? _sortState;
  Set<int> _selectedIndices = {};

  @override
  void initState() {
    super.initState();
    _sortState = widget.initialSortState;
    if (widget.selectedIndices != null) {
      _selectedIndices = Set.from(widget.selectedIndices!);
    } else if (widget.selectedIndex != null) {
      _selectedIndices = {widget.selectedIndex!};
    }
  }

  @override
  void didUpdateWidget(AdaptiveTableView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndices != oldWidget.selectedIndices) {
      _selectedIndices = widget.selectedIndices != null
          ? Set.from(widget.selectedIndices!)
          : {};
    } else if (widget.selectedIndex != oldWidget.selectedIndex) {
      _selectedIndices = widget.selectedIndex != null ? {widget.selectedIndex!} : {};
    }
  }

  void _handleSort(TableColumn<T> column) {
    if (!column.sortable) return;

    setState(() {
      if (_sortState?.columnId == column.id) {
        _sortState = _sortState!.copyWith(ascending: !_sortState!.ascending);
      } else {
        _sortState = SortState(columnId: column.id, ascending: true);
      }
    });

    widget.onSort?.call(_sortState!);
  }

  void _handleTap(T item, int index) {
    if (widget.multiSelect) {
      setState(() {
        if (_selectedIndices.contains(index)) {
          _selectedIndices.remove(index);
        } else {
          _selectedIndices.add(index);
        }
      });
      widget.onSelectionChanged?.call(_selectedIndices);
    } else {
      widget.onTap?.call(item, index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = context.isDesktopLayout;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final rowHeight = widget.rowHeight ?? AppSpacing.listItemHeight;
    final headerHeight = widget.headerHeight ?? (isDesktop ? 40.0 : 48.0);

    Widget content;

    if (widget.stickyHeader && widget.showHeader) {
      content = Column(
        children: [
          _buildHeader(context, headerHeight, isDark),
          if (widget.showDividers)
            Divider(height: 1, color: isDark ? AppColors.darkOutlineVariant : AppColors.lightOutlineVariant),
          Expanded(
            child: _buildList(context, rowHeight, isDark),
          ),
        ],
      );
    } else {
      content = CustomScrollView(
        controller: widget.controller,
        physics: widget.physics,
        shrinkWrap: widget.shrinkWrap,
        slivers: [
          if (widget.showHeader)
            SliverToBoxAdapter(
              child: _buildHeader(context, headerHeight, isDark),
            ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _buildRow(context, index, rowHeight, isDark),
              childCount: widget.items.length,
            ),
          ),
        ],
      );
    }

    if (widget.padding != null) {
      content = Padding(padding: widget.padding!, child: content);
    }

    return content;
  }

  Widget _buildHeader(BuildContext context, double height, bool isDark) {
    final isDesktop = context.isDesktopLayout;

    return Container(
      height: height,
      color: isDark
          ? AppColors.darkSurfaceVariant.withValues(alpha: 0.5)
          : AppColors.lightSurfaceVariant.withValues(alpha: 0.5),
      child: Row(
        children: [
          for (final column in widget.columns)
            _buildHeaderCell(context, column, height, isDark, isDesktop),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(
    BuildContext context,
    TableColumn<T> column,
    double height,
    bool isDark,
    bool isDesktop,
  ) {
    final isSorted = _sortState?.columnId == column.id;
    final isAscending = _sortState?.ascending ?? true;

    Widget content;
    if (column.headerBuilder != null) {
      content = column.headerBuilder!(context, isAscending);
    } else {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            column.title,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: isDesktop ? 12 : 14,
              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
            ),
          ),
          if (column.sortable && isSorted) ...[
            const SizedBox(width: 4),
            Icon(
              isAscending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              size: isDesktop ? 14 : 16,
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ],
      );
    }

    Widget cell = Container(
      height: height,
      alignment: column.alignment,
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 12 : 16),
      child: content,
    );

    if (column.sortable) {
      cell = InkWell(
        onTap: () => _handleSort(column),
        child: cell,
      );
    }

    if (column.width != null) {
      return SizedBox(width: column.width, child: cell);
    }

    return Expanded(flex: column.flex, child: cell);
  }

  Widget _buildList(BuildContext context, double rowHeight, bool isDark) => ListView.builder(
      controller: widget.controller,
      physics: widget.physics,
      shrinkWrap: widget.shrinkWrap,
      itemCount: widget.items.length,
      itemBuilder: (context, index) => _buildRow(context, index, rowHeight, isDark),
    );

  Widget _buildRow(BuildContext context, int index, double rowHeight, bool isDark) {
    final item = widget.items[index];
    final isSelected = _selectedIndices.contains(index);
    final isDesktop = context.isDesktopLayout;

    // 交替行颜色
    Color? backgroundColor;
    if (isSelected) {
      backgroundColor = isDark
          ? AppColors.primary.withValues(alpha: 0.2)
          : AppColors.primary.withValues(alpha: 0.15);
    } else if (widget.alternateRowColors && index.isOdd) {
      backgroundColor = isDark
          ? Colors.white.withValues(alpha: 0.02)
          : Colors.black.withValues(alpha: 0.02);
    }

    Widget row = Container(
      height: rowHeight,
      color: backgroundColor,
      child: Row(
        children: [
          for (final column in widget.columns)
            _buildCell(context, column, item, index, isDesktop),
        ],
      ),
    );

    if (widget.showDividers) {
      row = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          row,
          Divider(
            height: 1,
            color: isDark
                ? AppColors.darkOutlineVariant.withValues(alpha: 0.5)
                : AppColors.lightOutlineVariant.withValues(alpha: 0.5),
          ),
        ],
      );
    }

    // 添加交互
    if (isDesktop) {
      row = HoverHighlight(
        onTap: () => _handleTap(item, index),
        child: GestureDetector(
          onDoubleTap: widget.onDoubleTap != null
              ? () => widget.onDoubleTap!(item, index)
              : null,
          onSecondaryTap: widget.onSecondaryTap != null
              ? () => widget.onSecondaryTap!(item, index)
              : (widget.onLongPress != null ? () => widget.onLongPress!(item, index) : null),
          child: row,
        ),
      );
    } else {
      row = InkWell(
        onTap: () => _handleTap(item, index),
        onDoubleTap: widget.onDoubleTap != null
            ? () => widget.onDoubleTap!(item, index)
            : null,
        onLongPress: widget.onLongPress != null
            ? () => widget.onLongPress!(item, index)
            : null,
        child: row,
      );
    }

    return row;
  }

  Widget _buildCell(
    BuildContext context,
    TableColumn<T> column,
    T item,
    int index,
    bool isDesktop,
  ) {
    final cell = Container(
      alignment: column.alignment,
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 12 : 16),
      child: column.cellBuilder(context, item, index),
    );

    if (column.width != null) {
      return SizedBox(width: column.width, child: cell);
    }

    return Expanded(flex: column.flex, child: cell);
  }
}

/// 简化的表格行组件
class TableRow<T> extends StatelessWidget {
  const TableRow({
    super.key,
    required this.item,
    required this.columns,
    this.height,
    this.selected = false,
    this.onTap,
  });

  final T item;
  final List<TableColumn<T>> columns;
  final double? height;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDesktop = context.isDesktopLayout;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rowHeight = height ?? AppSpacing.listItemHeight;

    return InkWell(
      onTap: onTap,
      child: Container(
        height: rowHeight,
        color: selected
            ? (isDark
                ? AppColors.primary.withValues(alpha: 0.2)
                : AppColors.primary.withValues(alpha: 0.15))
            : null,
        child: Row(
          children: [
            for (int i = 0; i < columns.length; i++)
              _buildCell(context, columns[i], isDesktop),
          ],
        ),
      ),
    );
  }

  Widget _buildCell(BuildContext context, TableColumn<T> column, bool isDesktop) {
    final cell = Container(
      alignment: column.alignment,
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 12 : 16),
      child: column.cellBuilder(context, item, 0),
    );

    if (column.width != null) {
      return SizedBox(width: column.width, child: cell);
    }

    return Expanded(flex: column.flex, child: cell);
  }
}
