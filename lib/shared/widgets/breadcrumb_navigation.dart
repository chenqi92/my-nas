import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/utils/platform_capabilities.dart';

/// 面包屑项
class BreadcrumbItem {
  const BreadcrumbItem({
    required this.label,
    required this.path,
    this.icon,
  });

  /// 显示文本
  final String label;

  /// 路径
  final String path;

  /// 可选图标
  final IconData? icon;
}

/// 面包屑导航配置
class BreadcrumbConfig {
  const BreadcrumbConfig({
    this.separator = const Icon(Icons.chevron_right, size: 18),
    this.height = 40,
    this.itemSpacing = 4,
    this.horizontalPadding = 16,
    this.showHomeIcon = true,
    this.homeIcon = Icons.home_rounded,
    this.maxVisibleItems = 0,
    this.collapsedIcon = Icons.more_horiz_rounded,
  });

  /// 分隔符组件
  final Widget separator;

  /// 高度
  final double height;

  /// 项目间距
  final double itemSpacing;

  /// 水平内边距
  final double horizontalPadding;

  /// 是否显示首页图标
  final bool showHomeIcon;

  /// 首页图标
  final IconData homeIcon;

  /// 最大可见项目数（0 表示不限制）
  /// 超出后会折叠中间项目
  final int maxVisibleItems;

  /// 折叠时的图标
  final IconData collapsedIcon;
}

/// 面包屑导航
///
/// 桌面端显示完整路径导航
/// 移动端可选择显示或隐藏
///
/// 用法：
/// ```dart
/// BreadcrumbNavigation(
///   items: [
///     BreadcrumbItem(label: '根目录', path: '/'),
///     BreadcrumbItem(label: '文档', path: '/documents'),
///     BreadcrumbItem(label: '工作', path: '/documents/work'),
///   ],
///   onItemTap: (item) => navigateTo(item.path),
/// )
/// ```
class BreadcrumbNavigation extends StatelessWidget {
  const BreadcrumbNavigation({
    required this.items,
    required this.onItemTap,
    this.config = const BreadcrumbConfig(),
    this.showOnMobile = false,
    this.backgroundColor,
    super.key,
  });

  /// 面包屑项列表
  final List<BreadcrumbItem> items;

  /// 点击项目回调
  final void Function(BreadcrumbItem item) onItemTap;

  /// 配置
  final BreadcrumbConfig config;

  /// 是否在移动端显示
  final bool showOnMobile;

  /// 背景色
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    // 移动端默认不显示
    if (!showOnMobile && !PlatformCapabilities.isDesktop) {
      return const SizedBox.shrink();
    }

    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = backgroundColor ??
        (isDark ? AppColors.darkSurface : Colors.grey[100]);

    // 构建显示的项目列表（可能需要折叠）
    final displayItems = _buildDisplayItems();

    return Container(
      height: config.height,
      color: bgColor,
      padding: EdgeInsets.symmetric(horizontal: config.horizontalPadding),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: _buildBreadcrumbWidgets(context, displayItems, isDark),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建显示的项目列表
  List<_DisplayItem> _buildDisplayItems() {
    if (config.maxVisibleItems <= 0 || items.length <= config.maxVisibleItems) {
      // 不需要折叠
      return items.map(_DisplayItem.item).toList();
    }

    // 需要折叠：保留首尾，中间用折叠项代替
    final result = <_DisplayItem>[];
    final keepStart = (config.maxVisibleItems / 2).ceil();
    final keepEnd = config.maxVisibleItems - keepStart;

    // 添加开头的项目
    for (var i = 0; i < keepStart && i < items.length; i++) {
      result.add(_DisplayItem.item(items[i]));
    }

    // 添加折叠项
    final collapsedItems = items.sublist(keepStart, items.length - keepEnd);
    if (collapsedItems.isNotEmpty) {
      result.add(_DisplayItem.collapsed(collapsedItems));
    }

    // 添加结尾的项目
    for (var i = items.length - keepEnd; i < items.length; i++) {
      if (i >= keepStart) {
        result.add(_DisplayItem.item(items[i]));
      }
    }

    return result;
  }

  List<Widget> _buildBreadcrumbWidgets(
    BuildContext context,
    List<_DisplayItem> displayItems,
    bool isDark,
  ) {
    final widgets = <Widget>[];

    for (var i = 0; i < displayItems.length; i++) {
      final displayItem = displayItems[i];
      final isLast = i == displayItems.length - 1;

      if (displayItem.isCollapsed) {
        // 折叠项
        widgets.add(_CollapsedBreadcrumb(
          items: displayItem.collapsedItems!,
          onItemTap: onItemTap,
          icon: config.collapsedIcon,
          isDark: isDark,
        ));
      } else {
        // 普通项
        final item = displayItem.item!;
        final isFirst = i == 0;

        widgets.add(_BreadcrumbItemWidget(
          item: item,
          isLast: isLast,
          isFirst: isFirst,
          onTap: isLast ? null : () => onItemTap(item),
          showHomeIcon: config.showHomeIcon && isFirst,
          homeIcon: config.homeIcon,
          isDark: isDark,
        ));
      }

      // 添加分隔符（最后一项不需要）
      if (!isLast) {
        widgets.add(Padding(
          padding: EdgeInsets.symmetric(horizontal: config.itemSpacing),
          child: IconTheme(
            data: IconThemeData(
              color: isDark ? Colors.white38 : Colors.black38,
            ),
            child: config.separator,
          ),
        ));
      }
    }

    return widgets;
  }
}

/// 显示项（可能是普通项或折叠项）
class _DisplayItem {
  _DisplayItem.item(this.item) : collapsedItems = null;
  _DisplayItem.collapsed(this.collapsedItems) : item = null;

  final BreadcrumbItem? item;
  final List<BreadcrumbItem>? collapsedItems;

  bool get isCollapsed => collapsedItems != null;
}

/// 面包屑项组件
class _BreadcrumbItemWidget extends StatefulWidget {
  const _BreadcrumbItemWidget({
    required this.item,
    required this.isLast,
    required this.isFirst,
    required this.onTap,
    required this.showHomeIcon,
    required this.homeIcon,
    required this.isDark,
  });

  final BreadcrumbItem item;
  final bool isLast;
  final bool isFirst;
  final VoidCallback? onTap;
  final bool showHomeIcon;
  final IconData homeIcon;
  final bool isDark;

  @override
  State<_BreadcrumbItemWidget> createState() => _BreadcrumbItemWidgetState();
}

class _BreadcrumbItemWidgetState extends State<_BreadcrumbItemWidget> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final textColor = widget.isLast
        ? (widget.isDark ? Colors.white : Colors.black87)
        : (widget.isDark ? Colors.white70 : Colors.black54);

    final hoverColor = widget.isDark
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.05);

    return MouseRegion(
      cursor: widget.isLast ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _isHovering && !widget.isLast ? hoverColor : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.showHomeIcon && widget.isFirst) ...[
                Icon(
                  widget.homeIcon,
                  size: 16,
                  color: textColor,
                ),
                const SizedBox(width: 4),
              ] else if (widget.item.icon != null) ...[
                Icon(
                  widget.item.icon,
                  size: 16,
                  color: textColor,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                widget.item.label,
                style: TextStyle(
                  fontSize: 13,
                  color: textColor,
                  fontWeight: widget.isLast ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 折叠的面包屑项（点击展开菜单）
class _CollapsedBreadcrumb extends StatefulWidget {
  const _CollapsedBreadcrumb({
    required this.items,
    required this.onItemTap,
    required this.icon,
    required this.isDark,
  });

  final List<BreadcrumbItem> items;
  final void Function(BreadcrumbItem item) onItemTap;
  final IconData icon;
  final bool isDark;

  @override
  State<_CollapsedBreadcrumb> createState() => _CollapsedBreadcrumbState();
}

class _CollapsedBreadcrumbState extends State<_CollapsedBreadcrumb> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final hoverColor = widget.isDark
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.05);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onTap: _showMenu,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _isHovering ? hoverColor : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            widget.icon,
            size: 18,
            color: widget.isDark ? Colors.white54 : Colors.black45,
          ),
        ),
      ),
    );
  }

  void _showMenu() {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    showMenu<BreadcrumbItem>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy + size.height,
        position.dx + size.width,
        position.dy + size.height,
      ),
      items: widget.items.map((item) => PopupMenuItem<BreadcrumbItem>(
          value: item,
          child: Row(
            children: [
              if (item.icon != null) ...[
                Icon(item.icon, size: 16),
                const SizedBox(width: 8),
              ],
              Text(item.label),
            ],
          ),
        )).toList(),
    ).then((selectedItem) {
      if (selectedItem != null) {
        widget.onItemTap(selectedItem);
      }
    });
  }
}

/// 从路径构建面包屑项列表的工具方法
List<BreadcrumbItem> buildBreadcrumbsFromPath(
  String path, {
  String rootLabel = '根目录',
  String separator = '/',
}) {
  // 添加根目录
  final items = <BreadcrumbItem>[]
    ..add(BreadcrumbItem(label: rootLabel, path: separator));

  if (path == separator || path.isEmpty) {
    return items;
  }

  // 分割路径
  final parts = path.split(separator).where((p) => p.isNotEmpty).toList();
  final currentPath = StringBuffer();

  for (final part in parts) {
    currentPath.write('$separator$part');
    items.add(BreadcrumbItem(
      label: part,
      path: currentPath.toString(),
    ));
  }

  return items;
}

/// 紧凑型面包屑（仅显示当前目录和返回按钮）
///
/// 适用于移动端或空间受限的场景
class CompactBreadcrumb extends StatelessWidget {
  const CompactBreadcrumb({
    required this.currentPath,
    required this.onBack,
    this.rootLabel = '根目录',
    this.height = 48,
    super.key,
  });

  final String currentPath;
  final VoidCallback? onBack;
  final String rootLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isRoot = currentPath == '/' || currentPath.isEmpty;
    final currentName = isRoot ? rootLabel : currentPath.split('/').last;

    return SizedBox(
      height: height,
      child: Row(
        children: [
          // 返回按钮
          if (!isRoot && onBack != null)
            IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
              iconSize: 20,
              tooltip: context.l10n.breadcrumbBackTooltip,
            )
          else
            const SizedBox(width: 16),

          // 当前目录名
          Expanded(
            child: Text(
              currentName,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// 面包屑导航栏（带返回按钮和操作按钮）
class BreadcrumbBar extends StatelessWidget {
  const BreadcrumbBar({
    required this.items,
    required this.onItemTap,
    this.onBack,
    this.actions,
    this.config = const BreadcrumbConfig(),
    this.showBackButton = true,
    this.backgroundColor,
    super.key,
  });

  final List<BreadcrumbItem> items;
  final void Function(BreadcrumbItem item) onItemTap;
  final VoidCallback? onBack;
  final List<Widget>? actions;
  final BreadcrumbConfig config;
  final bool showBackButton;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = backgroundColor ??
        (isDark ? AppColors.darkSurface : Colors.grey[100]);
    final canGoBack = items.length > 1 && onBack != null;

    return Container(
      height: config.height + 8,
      color: bgColor,
      padding: EdgeInsets.symmetric(horizontal: config.horizontalPadding / 2),
      child: Row(
        children: [
          // 返回按钮
          if (showBackButton)
            IconButton(
              onPressed: canGoBack ? onBack : null,
              icon: const Icon(Icons.arrow_back_rounded),
              iconSize: 20,
              tooltip: context.l10n.breadcrumbBackTooltip,
              color: canGoBack
                  ? (isDark ? Colors.white70 : Colors.black54)
                  : (isDark ? Colors.white24 : Colors.black26),
            ),

          // 面包屑导航
          Expanded(
            child: BreadcrumbNavigation(
              items: items,
              onItemTap: onItemTap,
              config: config.copyWith(horizontalPadding: 0),
              showOnMobile: true,
              backgroundColor: Colors.transparent,
            ),
          ),

          // 操作按钮
          if (actions != null) ...actions!,
        ],
      ),
    );
  }
}

/// 扩展 BreadcrumbConfig 的 copyWith 方法
extension BreadcrumbConfigCopyWith on BreadcrumbConfig {
  BreadcrumbConfig copyWith({
    Widget? separator,
    double? height,
    double? itemSpacing,
    double? horizontalPadding,
    bool? showHomeIcon,
    IconData? homeIcon,
    int? maxVisibleItems,
    IconData? collapsedIcon,
  }) =>
      BreadcrumbConfig(
        separator: separator ?? this.separator,
        height: height ?? this.height,
        itemSpacing: itemSpacing ?? this.itemSpacing,
        horizontalPadding: horizontalPadding ?? this.horizontalPadding,
        showHomeIcon: showHomeIcon ?? this.showHomeIcon,
        homeIcon: homeIcon ?? this.homeIcon,
        maxVisibleItems: maxVisibleItems ?? this.maxVisibleItems,
        collapsedIcon: collapsedIcon ?? this.collapsedIcon,
      );
}
