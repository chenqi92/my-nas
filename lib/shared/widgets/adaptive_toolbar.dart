import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/utils/platform_capabilities.dart';
import 'package:my_nas/shared/widgets/adaptive_button.dart';

/// 工具栏项类型
enum ToolbarItemType {
  /// 图标按钮
  icon,

  /// 带文字的按钮（桌面端显示文字）
  iconText,

  /// 分隔符
  divider,

  /// 自定义组件
  custom,

  /// 弹性空间
  spacer,
}

/// 工具栏项
class ToolbarItem {
  const ToolbarItem._({
    required this.type,
    this.icon,
    this.label,
    this.tooltip,
    this.onPressed,
    this.isDestructive = false,
    this.enabled = true,
    this.child,
    this.flex = 1,
  });

  /// 图标按钮
  const ToolbarItem.icon({
    required IconData icon,
    required VoidCallback? onPressed,
    String? tooltip,
    bool isDestructive = false,
    bool enabled = true,
  }) : this._(
          type: ToolbarItemType.icon,
          icon: icon,
          onPressed: onPressed,
          tooltip: tooltip,
          isDestructive: isDestructive,
          enabled: enabled,
        );

  /// 带文字的按钮（桌面端显示文字）
  const ToolbarItem.iconText({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    String? tooltip,
    bool isDestructive = false,
    bool enabled = true,
  }) : this._(
          type: ToolbarItemType.iconText,
          icon: icon,
          label: label,
          onPressed: onPressed,
          tooltip: tooltip,
          isDestructive: isDestructive,
          enabled: enabled,
        );

  /// 分隔符
  const ToolbarItem.divider()
      : this._(
          type: ToolbarItemType.divider,
        );

  /// 弹性空间
  const ToolbarItem.spacer({int flex = 1})
      : this._(
          type: ToolbarItemType.spacer,
          flex: flex,
        );

  /// 自定义组件
  const ToolbarItem.custom({required Widget child})
      : this._(
          type: ToolbarItemType.custom,
          child: child,
        );

  final ToolbarItemType type;
  final IconData? icon;
  final String? label;
  final String? tooltip;
  final VoidCallback? onPressed;
  final bool isDestructive;
  final bool enabled;
  final Widget? child;
  final int flex;
}

/// 自适应工具栏
///
/// 根据平台自动调整布局：
/// - 移动端：仅显示图标
/// - 桌面端：显示图标 + 文字标签
///
/// 示例：
/// ```dart
/// AdaptiveToolbar(
///   items: [
///     ToolbarItem.iconText(
///       icon: Icons.add_rounded,
///       label: '新建',
///       onPressed: () {},
///     ),
///     ToolbarItem.divider(),
///     ToolbarItem.icon(
///       icon: Icons.delete_rounded,
///       tooltip: '删除',
///       onPressed: () {},
///       isDestructive: true,
///     ),
///   ],
/// )
/// ```
class AdaptiveToolbar extends StatelessWidget {
  const AdaptiveToolbar({
    super.key,
    required this.items,
    this.padding,
    this.spacing,
    this.backgroundColor,
    this.elevation = 0,
    this.showLabelsOnMobile = false,
    this.compact = false,
  });

  /// 工具栏项
  final List<ToolbarItem> items;

  /// 内边距
  final EdgeInsetsGeometry? padding;

  /// 按钮间距
  final double? spacing;

  /// 背景颜色
  final Color? backgroundColor;

  /// 阴影高度
  final double elevation;

  /// 是否在移动端也显示文字标签
  final bool showLabelsOnMobile;

  /// 是否使用紧凑模式
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isDesktop = PlatformCapabilities.isDesktop;
    final showLabels = isDesktop || showLabelsOnMobile;
    final effectiveSpacing = spacing ?? AppSpacing.toolbarButtonSpacing;
    final effectivePadding = padding ??
        EdgeInsets.symmetric(
          horizontal: isDesktop ? AppSpacing.lg : AppSpacing.md,
          vertical: isDesktop ? AppSpacing.sm : AppSpacing.xs,
        );

    final buttonSize = compact
        ? AdaptiveButtonSize.small
        : AdaptiveButtonSize.medium;

    return Material(
      elevation: elevation,
      color: backgroundColor ?? Colors.transparent,
      child: Padding(
        padding: effectivePadding,
        child: Row(
          children: [
            for (int i = 0; i < items.length; i++) ...[
              if (i > 0 && items[i].type != ToolbarItemType.divider && items[i - 1].type != ToolbarItemType.divider)
                SizedBox(width: effectiveSpacing),
              _buildItem(context, items[i], showLabels, buttonSize, isDesktop),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildItem(
    BuildContext context,
    ToolbarItem item,
    bool showLabels,
    AdaptiveButtonSize buttonSize,
    bool isDesktop,
  ) {
    switch (item.type) {
      case ToolbarItemType.icon:
        return AdaptiveIconButton(
          icon: item.icon!,
          onPressed: item.onPressed,
          tooltip: item.tooltip,
          size: buttonSize,
          isDestructive: item.isDestructive,
          enabled: item.enabled,
        );

      case ToolbarItemType.iconText:
        if (showLabels) {
          return _ToolbarTextButton(
            icon: item.icon!,
            label: item.label!,
            onPressed: item.onPressed,
            tooltip: item.tooltip,
            isDestructive: item.isDestructive,
            enabled: item.enabled,
            compact: compact,
          );
        } else {
          return AdaptiveIconButton(
            icon: item.icon!,
            onPressed: item.onPressed,
            tooltip: item.tooltip ?? item.label,
            size: buttonSize,
            isDestructive: item.isDestructive,
            enabled: item.enabled,
          );
        }

      case ToolbarItemType.divider:
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: isDesktop ? 8 : 4),
          child: SizedBox(
            height: isDesktop ? 24 : 32,
            child: VerticalDivider(
              width: 1,
              thickness: 1,
              color: Theme.of(context).dividerColor,
            ),
          ),
        );

      case ToolbarItemType.spacer:
        return Spacer(flex: item.flex);

      case ToolbarItemType.custom:
        return item.child!;
    }
  }
}

/// 工具栏带文字按钮
class _ToolbarTextButton extends StatefulWidget {
  const _ToolbarTextButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tooltip,
    this.isDestructive = false,
    this.enabled = true,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool isDestructive;
  final bool enabled;
  final bool compact;

  @override
  State<_ToolbarTextButton> createState() => _ToolbarTextButtonState();
}

class _ToolbarTextButtonState extends State<_ToolbarTextButton> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final isDesktop = PlatformCapabilities.isDesktop;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final iconSize = widget.compact ? 16.0 : 18.0;
    final fontSize = widget.compact ? 12.0 : 13.0;
    final padding = widget.compact
        ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
        : const EdgeInsets.symmetric(horizontal: 12, vertical: 6);

    final foregroundColor = !widget.enabled
        ? colorScheme.onSurface.withValues(alpha: 0.38)
        : (widget.isDestructive ? colorScheme.error : colorScheme.onSurface);

    final backgroundColor = _isHovering && widget.enabled
        ? (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05))
        : Colors.transparent;

    Widget button = MouseRegion(
      cursor: widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: isDesktop ? (_) => setState(() => _isHovering = true) : null,
      onExit: isDesktop ? (_) => setState(() => _isHovering = false) : null,
      child: GestureDetector(
        onTap: widget.enabled ? widget.onPressed : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: padding,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: iconSize,
                color: foregroundColor,
              ),
              SizedBox(width: widget.compact ? 4 : 6),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: fontSize,
                  color: foregroundColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      button = Tooltip(
        message: widget.tooltip!,
        child: button,
      );
    }

    return button;
  }
}

/// 搜索工具栏
///
/// 带有搜索框的工具栏
class SearchToolbar extends StatelessWidget {
  const SearchToolbar({
    super.key,
    required this.controller,
    this.onChanged,
    this.onSubmitted,
    this.hintText = '搜索',
    this.leading,
    this.trailing,
    this.padding,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final String hintText;
  final List<ToolbarItem>? leading;
  final List<ToolbarItem>? trailing;
  final EdgeInsetsGeometry? padding;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final isDesktop = PlatformCapabilities.isDesktop;
    final effectivePadding = padding ??
        EdgeInsets.symmetric(
          horizontal: isDesktop ? AppSpacing.lg : AppSpacing.md,
          vertical: isDesktop ? AppSpacing.sm : AppSpacing.xs,
        );

    return Padding(
      padding: effectivePadding,
      child: Row(
        children: [
          if (leading != null) ...[
            for (final item in leading!)
              _buildToolbarItem(context, item, isDesktop),
            SizedBox(width: isDesktop ? 12 : 8),
          ],
          Expanded(
            child: _SearchField(
              controller: controller,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              hintText: hintText,
              autofocus: autofocus,
            ),
          ),
          if (trailing != null) ...[
            SizedBox(width: isDesktop ? 12 : 8),
            for (final item in trailing!)
              _buildToolbarItem(context, item, isDesktop),
          ],
        ],
      ),
    );
  }

  Widget _buildToolbarItem(BuildContext context, ToolbarItem item, bool isDesktop) {
    switch (item.type) {
      case ToolbarItemType.icon:
        return AdaptiveIconButton(
          icon: item.icon!,
          onPressed: item.onPressed,
          tooltip: item.tooltip,
          size: AdaptiveButtonSize.medium,
          isDestructive: item.isDestructive,
          enabled: item.enabled,
        );
      case ToolbarItemType.divider:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: SizedBox(
            height: 24,
            child: VerticalDivider(
              width: 1,
              color: Theme.of(context).dividerColor,
            ),
          ),
        );
      case ToolbarItemType.custom:
        return item.child!;
      default:
        return const SizedBox.shrink();
    }
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    this.onChanged,
    this.onSubmitted,
    this.hintText = '搜索',
    this.autofocus = false,
  });

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final String hintText;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final isDesktop = PlatformCapabilities.isDesktop;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      height: isDesktop ? 36 : 44,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        autofocus: autofocus,
        style: TextStyle(fontSize: isDesktop ? 14 : 16),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(
            color: isDark ? Colors.white38 : Colors.black38,
            fontSize: isDesktop ? 14 : 16,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: isDesktop ? 18 : 22,
            color: isDark ? Colors.white54 : Colors.black54,
          ),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, child) {
              if (value.text.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: Icon(
                  Icons.close_rounded,
                  size: isDesktop ? 16 : 20,
                ),
                onPressed: () {
                  controller.clear();
                  onChanged?.call('');
                },
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(
                  minWidth: isDesktop ? 32 : 40,
                  minHeight: isDesktop ? 32 : 40,
                ),
              );
            },
          ),
          contentPadding: EdgeInsets.symmetric(
            horizontal: isDesktop ? 12 : 16,
            vertical: 0,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(isDesktop ? 8 : 10),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.05),
        ),
      ),
    );
  }
}
