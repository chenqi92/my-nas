import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/utils/platform_capabilities.dart';
import 'package:my_nas/shared/widgets/hoverable_widget.dart';

/// 列表项类型
enum AdaptiveListTileType {
  /// 标准列表项
  standard,

  /// 紧凑列表项
  compact,

  /// 单行列表项
  singleLine,

  /// 双行列表项
  twoLine,

  /// 三行列表项
  threeLine,
}

/// 自适应列表项
///
/// 根据平台自动调整高度和间距：
/// - 移动端：更高的触摸目标，更大的间距
/// - 桌面端：更紧凑的布局，添加悬停效果
///
/// 示例：
/// ```dart
/// AdaptiveListTile(
///   title: '文件名.txt',
///   subtitle: '1.2 MB',
///   leading: Icon(Icons.file_copy),
///   onTap: () {},
/// )
/// ```
class AdaptiveListTile extends StatelessWidget {
  const AdaptiveListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.type = AdaptiveListTileType.standard,
    this.selected = false,
    this.enabled = true,
    this.dense,
    this.contentPadding,
    this.hoverEffect = true,
    this.showDivider = false,
  });

  /// 标题
  final Widget title;

  /// 副标题
  final Widget? subtitle;

  /// 前置组件
  final Widget? leading;

  /// 尾部组件
  final Widget? trailing;

  /// 点击回调
  final VoidCallback? onTap;

  /// 长按回调（移动端）
  final VoidCallback? onLongPress;

  /// 右键回调（桌面端）
  final VoidCallback? onSecondaryTap;

  /// 列表项类型
  final AdaptiveListTileType type;

  /// 是否选中
  final bool selected;

  /// 是否启用
  final bool enabled;

  /// 是否使用紧凑模式（覆盖默认值）
  final bool? dense;

  /// 自定义内边距
  final EdgeInsetsGeometry? contentPadding;

  /// 是否启用悬停效果
  final bool hoverEffect;

  /// 是否显示分隔线
  final bool showDivider;

  /// 从数据快速创建
  factory AdaptiveListTile.simple({
    Key? key,
    required String title,
    String? subtitle,
    IconData? leadingIcon,
    IconData? trailingIcon,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
    bool selected = false,
    bool enabled = true,
  }) => AdaptiveListTile(
      key: key,
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      leading: leadingIcon != null ? Icon(leadingIcon) : null,
      trailing: trailingIcon != null ? Icon(trailingIcon) : null,
      onTap: onTap,
      onLongPress: onLongPress,
      selected: selected,
      enabled: enabled,
    );

  @override
  Widget build(BuildContext context) {
    final isDesktop = PlatformCapabilities.isDesktop;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 计算高度和间距
    final height = _getHeight(isDesktop);
    final padding = contentPadding ?? _getPadding(isDesktop);
    final effectiveDense = dense ?? isDesktop;

    // 构建列表项
    Widget tile = SizedBox(
      height: _shouldUseFixedHeight() ? height : null,
      child: ListTile(
        title: _buildTitle(context, isDesktop),
        subtitle: _buildSubtitle(context, isDesktop),
        leading: _buildLeading(context, isDesktop),
        trailing: _buildTrailing(context, isDesktop),
        onTap: enabled ? onTap : null,
        onLongPress: enabled ? onLongPress : null,
        selected: selected,
        enabled: enabled,
        dense: effectiveDense,
        contentPadding: padding,
        visualDensity: isDesktop ? VisualDensity.compact : VisualDensity.standard,
        selectedTileColor: isDark
            ? AppColors.primary.withValues(alpha: 0.15)
            : AppColors.primary.withValues(alpha: 0.1),
        hoverColor: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.03),
      ),
    );

    // 桌面端添加悬停效果和右键支持
    if (isDesktop && hoverEffect) {
      tile = HoverHighlight(
        onTap: enabled ? onTap : null,
        enabled: enabled,
        borderRadius: BorderRadius.circular(8),
        child: GestureDetector(
          onSecondaryTap: enabled ? (onSecondaryTap ?? onLongPress) : null,
          child: tile,
        ),
      );
    }

    // 添加分隔线
    if (showDivider) {
      tile = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          tile,
          Divider(
            height: 1,
            indent: leading != null ? (isDesktop ? 52 : 72) : 16,
            endIndent: 16,
          ),
        ],
      );
    }

    return tile;
  }

  bool _shouldUseFixedHeight() {
    switch (type) {
      case AdaptiveListTileType.standard:
      case AdaptiveListTileType.compact:
      case AdaptiveListTileType.singleLine:
        return true;
      case AdaptiveListTileType.twoLine:
      case AdaptiveListTileType.threeLine:
        return false;
    }
  }

  double _getHeight(bool isDesktop) {
    switch (type) {
      case AdaptiveListTileType.compact:
        return AppSpacing.compactListItemHeight;
      case AdaptiveListTileType.singleLine:
        return AppSpacing.singleLineListItemHeight;
      case AdaptiveListTileType.twoLine:
        return AppSpacing.twoLineListItemHeight;
      case AdaptiveListTileType.threeLine:
        return AppSpacing.threeLineListItemHeight;
      case AdaptiveListTileType.standard:
        return AppSpacing.listItemHeight;
    }
  }

  EdgeInsets _getPadding(bool isDesktop) => EdgeInsets.symmetric(
      horizontal: AppSpacing.listItemHorizontalPadding,
      vertical: AppSpacing.listItemVerticalPadding / 2,
    );

  Widget _buildTitle(BuildContext context, bool isDesktop) {
    if (title is Text) {
      final textWidget = title as Text;
      return Text(
        textWidget.data ?? '',
        style: (textWidget.style ?? Theme.of(context).textTheme.bodyLarge)?.copyWith(
          fontSize: isDesktop ? 14 : 16,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    return title;
  }

  Widget? _buildSubtitle(BuildContext context, bool isDesktop) {
    if (subtitle == null) return null;

    if (subtitle is Text) {
      final textWidget = subtitle! as Text;
      return Text(
        textWidget.data ?? '',
        style: (textWidget.style ?? Theme.of(context).textTheme.bodySmall)?.copyWith(
          fontSize: isDesktop ? 12 : 14,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        maxLines: type == AdaptiveListTileType.threeLine ? 2 : 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    return subtitle;
  }

  Widget? _buildLeading(BuildContext context, bool isDesktop) {
    if (leading == null) return null;

    final iconSize = AppSpacing.leadingIconSize;

    if (leading is Icon) {
      final iconWidget = leading! as Icon;
      return Icon(
        iconWidget.icon,
        size: iconSize,
        color: iconWidget.color,
      );
    }

    return leading;
  }

  Widget? _buildTrailing(BuildContext context, bool isDesktop) {
    if (trailing == null) return null;

    final iconSize = AppSpacing.trailingIconSize;

    if (trailing is Icon) {
      final iconWidget = trailing! as Icon;
      return Icon(
        iconWidget.icon,
        size: iconSize,
        color: iconWidget.color ?? Theme.of(context).colorScheme.onSurfaceVariant,
      );
    }

    return trailing;
  }
}

/// 自适应列表组
///
/// 带有标题的列表项组
class AdaptiveListGroup extends StatelessWidget {
  const AdaptiveListGroup({
    super.key,
    required this.children,
    this.title,
    this.trailing,
    this.padding,
    this.showDividers = false,
  });

  final List<Widget> children;
  final String? title;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;
  final bool showDividers;

  @override
  Widget build(BuildContext context) {
    final isDesktop = PlatformCapabilities.isDesktop;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null)
          Padding(
            padding: padding ?? EdgeInsets.symmetric(
              horizontal: AppSpacing.listItemHorizontalPadding,
              vertical: AppSpacing.sectionSpacing / 2,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title!,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontSize: isDesktop ? 12 : 14,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.darkOnSurfaceVariant
                          : AppColors.lightOnSurfaceVariant,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ...children,
      ],
    );
  }
}

/// 自适应开关列表项
class AdaptiveSwitchListTile extends StatelessWidget {
  const AdaptiveSwitchListTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.leading,
    this.enabled = true,
    this.dense,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;
  final bool? dense;

  @override
  Widget build(BuildContext context) {
    final isDesktop = PlatformCapabilities.isDesktop;
    final effectiveDense = dense ?? isDesktop;

    return SwitchListTile(
      title: title,
      subtitle: subtitle,
      secondary: leading,
      value: value,
      onChanged: enabled ? onChanged : null,
      dense: effectiveDense,
      contentPadding: EdgeInsets.symmetric(
        horizontal: AppSpacing.listItemHorizontalPadding,
      ),
      visualDensity: isDesktop ? VisualDensity.compact : VisualDensity.standard,
    );
  }
}

/// 自适应复选框列表项
class AdaptiveCheckboxListTile extends StatelessWidget {
  const AdaptiveCheckboxListTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.leading,
    this.enabled = true,
    this.dense,
    this.tristate = false,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final bool? value;
  final ValueChanged<bool?>? onChanged;
  final bool enabled;
  final bool? dense;
  final bool tristate;

  @override
  Widget build(BuildContext context) {
    final isDesktop = PlatformCapabilities.isDesktop;
    final effectiveDense = dense ?? isDesktop;

    return CheckboxListTile(
      title: title,
      subtitle: subtitle,
      secondary: leading,
      value: value,
      onChanged: enabled ? onChanged : null,
      dense: effectiveDense,
      tristate: tristate,
      contentPadding: EdgeInsets.symmetric(
        horizontal: AppSpacing.listItemHorizontalPadding,
      ),
      visualDensity: isDesktop ? VisualDensity.compact : VisualDensity.standard,
      controlAffinity: ListTileControlAffinity.leading,
    );
  }
}

/// 自适应单选列表项
class AdaptiveRadioListTile<T> extends StatelessWidget {
  const AdaptiveRadioListTile({
    super.key,
    required this.title,
    required this.value,
    required this.groupValue,
    required this.onChanged,
    this.subtitle,
    this.leading,
    this.enabled = true,
    this.dense,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final T value;
  final T? groupValue;
  final ValueChanged<T?>? onChanged;
  final bool enabled;
  final bool? dense;

  @override
  Widget build(BuildContext context) {
    final isDesktop = PlatformCapabilities.isDesktop;
    final effectiveDense = dense ?? isDesktop;

    // RadioListTile 在 Flutter 3.32+ 标记 groupValue / onChanged 为 deprecated，
    // 推荐迁移到 RadioGroup 包装。本文件保留旧 API 以避免 listtile 形态大改，
    // 后续可专门迁移。
    // ignore: deprecated_member_use
    return RadioListTile<T>(
      title: title,
      subtitle: subtitle,
      secondary: leading,
      value: value,
      // ignore: deprecated_member_use
      groupValue: groupValue,
      // ignore: deprecated_member_use
      onChanged: enabled ? onChanged : null,
      dense: effectiveDense,
      contentPadding: EdgeInsets.symmetric(
        horizontal: AppSpacing.listItemHorizontalPadding,
      ),
      visualDensity: isDesktop ? VisualDensity.compact : VisualDensity.standard,
      controlAffinity: ListTileControlAffinity.leading,
    );
  }
}
