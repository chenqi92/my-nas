import 'package:flutter/material.dart';
import 'package:my_nas/core/utils/platform_capabilities.dart';

/// 主从视图布局配置
class MasterDetailConfig {
  const MasterDetailConfig({
    this.masterMinWidth = 280,
    this.masterMaxWidth = 400,
    this.masterFlex = 1,
    this.detailFlex = 2,
    this.breakpoint = 900,
    this.showDivider = true,
    this.dividerColor,
    this.animationDuration = const Duration(milliseconds: 200),
  });

  /// 主列表最小宽度
  final double masterMinWidth;

  /// 主列表最大宽度
  final double masterMaxWidth;

  /// 主列表 flex 权重
  final int masterFlex;

  /// 详情区 flex 权重
  final int detailFlex;

  /// 切换到分屏的断点宽度
  final double breakpoint;

  /// 是否显示分隔线
  final bool showDivider;

  /// 分隔线颜色
  final Color? dividerColor;

  /// 动画时长
  final Duration animationDuration;
}

/// 主从视图布局
///
/// 桌面端大屏：左侧列表 + 右侧详情（分屏）
/// 移动端/小屏：单页面导航
///
/// 用法：
/// ```dart
/// MasterDetailLayout<MyItem>(
///   items: items,
///   selectedItem: selectedItem,
///   onItemSelected: (item) => setState(() => selectedItem = item),
///   masterBuilder: (context, item, isSelected) => ListTile(
///     title: Text(item.name),
///     selected: isSelected,
///   ),
///   detailBuilder: (context, item) => ItemDetailPage(item: item),
///   emptyDetailBuilder: (context) => Center(child: Text('请选择一项')),
/// )
/// ```
class MasterDetailLayout<T> extends StatefulWidget {
  const MasterDetailLayout({
    required this.items,
    required this.selectedItem,
    required this.onItemSelected,
    required this.masterBuilder,
    required this.detailBuilder,
    this.emptyDetailBuilder,
    this.masterHeader,
    this.detailHeader,
    this.config = const MasterDetailConfig(),
    this.onBackFromDetail,
    super.key,
  });

  /// 列表项
  final List<T> items;

  /// 当前选中的项
  final T? selectedItem;

  /// 选中项变化回调
  final void Function(T item) onItemSelected;

  /// 列表项构建器
  final Widget Function(BuildContext context, T item, bool isSelected) masterBuilder;

  /// 详情页构建器
  final Widget Function(BuildContext context, T item) detailBuilder;

  /// 空详情页构建器（未选中任何项时显示）
  final Widget Function(BuildContext context)? emptyDetailBuilder;

  /// 列表头部组件
  final Widget? masterHeader;

  /// 详情页头部组件
  final Widget? detailHeader;

  /// 布局配置
  final MasterDetailConfig config;

  /// 从详情页返回的回调（仅移动端）
  final VoidCallback? onBackFromDetail;

  @override
  State<MasterDetailLayout<T>> createState() => _MasterDetailLayoutState<T>();
}

class _MasterDetailLayoutState<T> extends State<MasterDetailLayout<T>> {
  /// 是否使用分屏布局
  bool _useSplitView(BuildContext context) {
    if (!PlatformCapabilities.isDesktop) return false;
    final width = MediaQuery.of(context).size.width;
    return width >= widget.config.breakpoint;
  }

  @override
  Widget build(BuildContext context) {
    if (_useSplitView(context)) {
      return _buildSplitView(context);
    } else {
      return _buildStackView(context);
    }
  }

  /// 分屏视图（桌面端大屏）
  Widget _buildSplitView(BuildContext context) {
    final config = widget.config;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dividerColor = config.dividerColor ??
        (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1));

    return LayoutBuilder(
      builder: (context, constraints) {
        // 计算主列表宽度：按比例分配，但限制在 min-max 范围内
        final totalFlex = config.masterFlex + config.detailFlex;
        final flexWidth = constraints.maxWidth * config.masterFlex / totalFlex;
        final masterWidth = flexWidth.clamp(config.masterMinWidth, config.masterMaxWidth);

        return Row(
          children: [
            // 主列表
            SizedBox(
              width: masterWidth,
              child: _buildMasterList(context),
            ),
            // 分隔线
            if (config.showDivider)
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: dividerColor,
              ),
            // 详情区域
            Expanded(
              child: _buildDetailPane(context),
            ),
          ],
        );
      },
    );
  }

  /// 堆叠视图（移动端/小屏）- 使用页面导航
  Widget _buildStackView(BuildContext context) {
    // 如果有选中项，直接显示详情页（由外部处理导航）
    // 这里只返回列表，让外部处理详情页的显示
    return _buildMasterList(context);
  }

  /// 构建主列表
  Widget _buildMasterList(BuildContext context) => Column(
      children: [
        if (widget.masterHeader != null) widget.masterHeader!,
        Expanded(
          child: ListView.builder(
            itemCount: widget.items.length,
            itemBuilder: (context, index) {
              final item = widget.items[index];
              final isSelected = widget.selectedItem == item;
              return GestureDetector(
                onTap: () => widget.onItemSelected(item),
                child: widget.masterBuilder(context, item, isSelected),
              );
            },
          ),
        ),
      ],
    );

  /// 构建详情面板
  Widget _buildDetailPane(BuildContext context) {
    final selectedItem = widget.selectedItem;

    return AnimatedSwitcher(
      duration: widget.config.animationDuration,
      child: selectedItem != null
          ? Column(
              key: ValueKey(selectedItem),
              children: [
                if (widget.detailHeader != null) widget.detailHeader!,
                Expanded(child: widget.detailBuilder(context, selectedItem)),
              ],
            )
          : widget.emptyDetailBuilder?.call(context) ??
              const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.touch_app_outlined, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text(
                      '选择一项查看详情',
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  ],
                ),
              ),
    );
  }
}

/// 带有内置导航的主从视图
///
/// 自动处理移动端的页面导航
class MasterDetailScaffold<T> extends StatefulWidget {
  const MasterDetailScaffold({
    required this.items,
    required this.masterBuilder,
    required this.detailBuilder,
    this.masterTitle,
    this.detailTitle,
    this.emptyDetailBuilder,
    this.masterActions,
    this.detailActions,
    this.config = const MasterDetailConfig(),
    this.initialSelectedItem,
    this.onItemSelected,
    super.key,
  });

  /// 列表项
  final List<T> items;

  /// 列表项构建器
  final Widget Function(BuildContext context, T item, bool isSelected) masterBuilder;

  /// 详情页构建器
  final Widget Function(BuildContext context, T item) detailBuilder;

  /// 主列表标题
  final String? masterTitle;

  /// 详情页标题（可以是回调以根据选中项动态生成）
  final String Function(T item)? detailTitle;

  /// 空详情页构建器
  final Widget Function(BuildContext context)? emptyDetailBuilder;

  /// 主列表操作按钮
  final List<Widget>? masterActions;

  /// 详情页操作按钮
  final List<Widget> Function(T item)? detailActions;

  /// 布局配置
  final MasterDetailConfig config;

  /// 初始选中项
  final T? initialSelectedItem;

  /// 选中项变化回调
  final void Function(T item)? onItemSelected;

  @override
  State<MasterDetailScaffold<T>> createState() => _MasterDetailScaffoldState<T>();
}

class _MasterDetailScaffoldState<T> extends State<MasterDetailScaffold<T>> {
  T? _selectedItem;

  @override
  void initState() {
    super.initState();
    _selectedItem = widget.initialSelectedItem;
  }

  bool _useSplitView(BuildContext context) {
    if (!PlatformCapabilities.isDesktop) return false;
    final width = MediaQuery.of(context).size.width;
    return width >= widget.config.breakpoint;
  }

  void _selectItem(BuildContext context, T item) {
    setState(() => _selectedItem = item);
    widget.onItemSelected?.call(item);

    // 移动端/小屏时导航到详情页
    if (!_useSplitView(context)) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (ctx) => _buildDetailPage(ctx, item),
        ),
      );
    }
  }

  Widget _buildDetailPage(BuildContext context, T item) => Scaffold(
      appBar: AppBar(
        title: Text(widget.detailTitle?.call(item) ?? '详情'),
        actions: widget.detailActions?.call(item),
      ),
      body: widget.detailBuilder(context, item),
    );

  @override
  Widget build(BuildContext context) {
    if (_useSplitView(context)) {
      return _buildSplitView(context);
    } else {
      return _buildMasterPage(context);
    }
  }

  Widget _buildMasterPage(BuildContext context) => Scaffold(
      appBar: widget.masterTitle != null
          ? AppBar(
              title: Text(widget.masterTitle!),
              actions: widget.masterActions,
            )
          : null,
      body: ListView.builder(
        itemCount: widget.items.length,
        itemBuilder: (ctx, index) {
          final item = widget.items[index];
          final isSelected = _selectedItem == item;
          return GestureDetector(
            onTap: () => _selectItem(ctx, item),
            child: widget.masterBuilder(ctx, item, isSelected),
          );
        },
      ),
    );

  Widget _buildSplitView(BuildContext context) {
    final config = widget.config;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dividerColor = config.dividerColor ??
        (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1));

    return Scaffold(
      body: Row(
        children: [
          // 主列表区域
          SizedBox(
            width: config.masterMinWidth +
                (config.masterMaxWidth - config.masterMinWidth) *
                    (config.masterFlex / (config.masterFlex + config.detailFlex)),
            child: Column(
              children: [
                // 列表标题栏
                if (widget.masterTitle != null)
                  Container(
                    height: 56,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: dividerColor,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          widget.masterTitle!,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const Spacer(),
                        if (widget.masterActions != null) ...widget.masterActions!,
                      ],
                    ),
                  ),
                // 列表内容
                Expanded(
                  child: ListView.builder(
                    itemCount: widget.items.length,
                    itemBuilder: (ctx, index) {
                      final item = widget.items[index];
                      final isSelected = _selectedItem == item;
                      return GestureDetector(
                        onTap: () => _selectItem(ctx, item),
                        child: widget.masterBuilder(ctx, item, isSelected),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          // 分隔线
          if (config.showDivider)
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: dividerColor,
            ),
          // 详情区域
          Expanded(
            child: _buildDetailPane(context),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailPane(BuildContext context) {
    final selectedItem = _selectedItem;
    final config = widget.config;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dividerColor = config.dividerColor ??
        (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1));

    return AnimatedSwitcher(
      duration: config.animationDuration,
      child: selectedItem != null
          ? Column(
              key: ValueKey(selectedItem),
              children: [
                // 详情标题栏
                Container(
                  height: 56,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: dividerColor,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        widget.detailTitle?.call(selectedItem) ?? '详情',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const Spacer(),
                      if (widget.detailActions != null) ...widget.detailActions!.call(selectedItem),
                    ],
                  ),
                ),
                // 详情内容
                Expanded(child: widget.detailBuilder(context, selectedItem)),
              ],
            )
          : widget.emptyDetailBuilder?.call(context) ??
              const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.touch_app_outlined, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text(
                      '选择一项查看详情',
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  ],
                ),
              ),
    );
  }
}

/// 可调整大小的主从视图
///
/// 支持拖动分隔线调整两侧宽度
class ResizableMasterDetail extends StatefulWidget {
  const ResizableMasterDetail({
    required this.masterChild,
    required this.detailChild,
    this.initialMasterWidth = 320,
    this.minMasterWidth = 200,
    this.maxMasterWidth = 500,
    this.showDivider = true,
    this.dividerWidth = 8,
    super.key,
  });

  final Widget masterChild;
  final Widget detailChild;
  final double initialMasterWidth;
  final double minMasterWidth;
  final double maxMasterWidth;
  final bool showDivider;
  final double dividerWidth;

  @override
  State<ResizableMasterDetail> createState() => _ResizableMasterDetailState();
}

class _ResizableMasterDetailState extends State<ResizableMasterDetail> {
  late double _masterWidth;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _masterWidth = widget.initialMasterWidth;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        // 主区域
        SizedBox(
          width: _masterWidth,
          child: widget.masterChild,
        ),
        // 可拖动分隔线
        MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: GestureDetector(
            onHorizontalDragStart: (_) => setState(() => _isDragging = true),
            onHorizontalDragUpdate: (details) {
              setState(() {
                _masterWidth = (_masterWidth + details.delta.dx)
                    .clamp(widget.minMasterWidth, widget.maxMasterWidth);
              });
            },
            onHorizontalDragEnd: (_) => setState(() => _isDragging = false),
            child: Container(
              width: widget.dividerWidth,
              color: _isDragging
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)
                  : (widget.showDivider
                      ? (isDark
                          ? Colors.white.withValues(alpha: 0.1)
                          : Colors.black.withValues(alpha: 0.1))
                      : Colors.transparent),
              child: Center(
                child: Container(
                  width: 4,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _isDragging
                        ? Theme.of(context).colorScheme.primary
                        : (isDark ? Colors.white24 : Colors.black12),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ),
        // 详情区域
        Expanded(child: widget.detailChild),
      ],
    );
  }
}
