import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';

/// 自适应按钮类型
enum AdaptiveButtonType {
  /// 填充按钮（主要操作）
  filled,

  /// 轮廓按钮（次要操作）
  outlined,

  /// 文字按钮（三级操作）
  text,

  /// 图标按钮
  icon,

  /// 带图标的填充按钮
  filledIcon,

  /// 带图标的轮廓按钮
  outlinedIcon,

  /// 带图标的文字按钮
  textIcon,
}

/// 自适应按钮尺寸
enum AdaptiveButtonSize {
  /// 小尺寸
  small,

  /// 中等尺寸（默认）
  medium,

  /// 大尺寸
  large,
}

/// 自适应按钮
///
/// 根据平台自动调整触摸目标大小：
/// - 移动端：48dp 最小触摸目标
/// - 桌面端：32dp 最小触摸目标
///
/// 示例：
/// ```dart
/// AdaptiveButton(
///   type: AdaptiveButtonType.filled,
///   onPressed: () {},
///   label: '保存',
///   icon: Icons.save,
/// )
/// ```
class AdaptiveButton extends StatelessWidget {
  const AdaptiveButton({
    super.key,
    required this.onPressed,
    this.type = AdaptiveButtonType.filled,
    this.size = AdaptiveButtonSize.medium,
    this.label,
    this.icon,
    this.tooltip,
    this.isDestructive = false,
    this.isLoading = false,
    this.enabled = true,
    this.expanded = false,
  }) : assert(
          label != null || icon != null,
          'Either label or icon must be provided',
        );

  /// 点击回调
  final VoidCallback? onPressed;

  /// 按钮类型
  final AdaptiveButtonType type;

  /// 按钮尺寸
  final AdaptiveButtonSize size;

  /// 文字标签
  final String? label;

  /// 图标
  final IconData? icon;

  /// 工具提示
  final String? tooltip;

  /// 是否为危险操作
  final bool isDestructive;

  /// 是否正在加载
  final bool isLoading;

  /// 是否启用
  final bool enabled;

  /// 是否撑满宽度
  final bool expanded;

  /// 快捷构造函数：图标按钮
  const AdaptiveButton.icon({
    super.key,
    required this.onPressed,
    required IconData this.icon,
    this.tooltip,
    this.size = AdaptiveButtonSize.medium,
    this.isDestructive = false,
    this.isLoading = false,
    this.enabled = true,
  })  : type = AdaptiveButtonType.icon,
        label = null,
        expanded = false;

  /// 快捷构造函数：填充按钮
  const AdaptiveButton.filled({
    super.key,
    required this.onPressed,
    required String this.label,
    this.icon,
    this.tooltip,
    this.size = AdaptiveButtonSize.medium,
    this.isDestructive = false,
    this.isLoading = false,
    this.enabled = true,
    this.expanded = false,
  }) : type = icon != null ? AdaptiveButtonType.filledIcon : AdaptiveButtonType.filled;

  /// 快捷构造函数：轮廓按钮
  const AdaptiveButton.outlined({
    super.key,
    required this.onPressed,
    required String this.label,
    this.icon,
    this.tooltip,
    this.size = AdaptiveButtonSize.medium,
    this.isDestructive = false,
    this.isLoading = false,
    this.enabled = true,
    this.expanded = false,
  }) : type = icon != null ? AdaptiveButtonType.outlinedIcon : AdaptiveButtonType.outlined;

  /// 快捷构造函数：文字按钮
  const AdaptiveButton.text({
    super.key,
    required this.onPressed,
    required String this.label,
    this.icon,
    this.tooltip,
    this.size = AdaptiveButtonSize.medium,
    this.isDestructive = false,
    this.isLoading = false,
    this.enabled = true,
    this.expanded = false,
  }) : type = icon != null ? AdaptiveButtonType.textIcon : AdaptiveButtonType.text;

  @override
  Widget build(BuildContext context) {
    final isDesktop = context.isDesktopLayout;
    final effectiveOnPressed = enabled && !isLoading ? onPressed : null;

    // 根据平台和尺寸计算按钮尺寸
    final buttonHeight = _getButtonHeight(isDesktop);
    final iconSize = _getIconSize(isDesktop);
    final padding = _getPadding(isDesktop);
    final fontSize = _getFontSize(isDesktop);

    // 构建内容
    Widget? iconWidget;
    if (isLoading) {
      iconWidget = SizedBox(
        width: iconSize,
        height: iconSize,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: _getLoadingColor(context),
        ),
      );
    } else if (icon != null) {
      iconWidget = Icon(icon, size: iconSize);
    }

    // 根据类型构建按钮
    Widget button;
    switch (type) {
      case AdaptiveButtonType.icon:
        button = _buildIconButton(
          context,
          iconWidget: iconWidget!,
          iconSize: iconSize,
          buttonSize: buttonHeight,
          onPressed: effectiveOnPressed,
        );

      case AdaptiveButtonType.filled:
      case AdaptiveButtonType.filledIcon:
        button = _buildFilledButton(
          context,
          iconWidget: iconWidget,
          padding: padding,
          height: buttonHeight,
          fontSize: fontSize,
          onPressed: effectiveOnPressed,
        );

      case AdaptiveButtonType.outlined:
      case AdaptiveButtonType.outlinedIcon:
        button = _buildOutlinedButton(
          context,
          iconWidget: iconWidget,
          padding: padding,
          height: buttonHeight,
          fontSize: fontSize,
          onPressed: effectiveOnPressed,
        );

      case AdaptiveButtonType.text:
      case AdaptiveButtonType.textIcon:
        button = _buildTextButton(
          context,
          iconWidget: iconWidget,
          padding: padding,
          height: buttonHeight,
          fontSize: fontSize,
          onPressed: effectiveOnPressed,
        );
    }

    // 添加工具提示
    if (tooltip != null) {
      button = Tooltip(
        message: tooltip!,
        child: button,
      );
    }

    // 撑满宽度
    if (expanded) {
      button = SizedBox(
        width: double.infinity,
        child: button,
      );
    }

    return button;
  }

  double _getButtonHeight(bool isDesktop) {
    switch (size) {
      case AdaptiveButtonSize.small:
        return isDesktop ? 28 : 36;
      case AdaptiveButtonSize.medium:
        return isDesktop ? 36 : 44;
      case AdaptiveButtonSize.large:
        return isDesktop ? 44 : 52;
    }
  }

  double _getIconSize(bool isDesktop) {
    switch (size) {
      case AdaptiveButtonSize.small:
        return isDesktop ? 16 : 18;
      case AdaptiveButtonSize.medium:
        return isDesktop ? 18 : 22;
      case AdaptiveButtonSize.large:
        return isDesktop ? 22 : 26;
    }
  }

  EdgeInsets _getPadding(bool isDesktop) {
    switch (size) {
      case AdaptiveButtonSize.small:
        return EdgeInsets.symmetric(
          horizontal: isDesktop ? 12 : 16,
          vertical: isDesktop ? 4 : 6,
        );
      case AdaptiveButtonSize.medium:
        return EdgeInsets.symmetric(
          horizontal: isDesktop ? 16 : 20,
          vertical: isDesktop ? 8 : 10,
        );
      case AdaptiveButtonSize.large:
        return EdgeInsets.symmetric(
          horizontal: isDesktop ? 24 : 28,
          vertical: isDesktop ? 12 : 14,
        );
    }
  }

  double _getFontSize(bool isDesktop) {
    switch (size) {
      case AdaptiveButtonSize.small:
        return isDesktop ? 12 : 14;
      case AdaptiveButtonSize.medium:
        return isDesktop ? 14 : 16;
      case AdaptiveButtonSize.large:
        return isDesktop ? 16 : 18;
    }
  }

  Color _getLoadingColor(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    switch (type) {
      case AdaptiveButtonType.filled:
      case AdaptiveButtonType.filledIcon:
        return colorScheme.onPrimary;
      default:
        return isDestructive ? colorScheme.error : colorScheme.primary;
    }
  }

  ButtonStyle _getButtonStyle(
    BuildContext context, {
    required EdgeInsets padding,
    required double height,
    required double fontSize,
    bool isFilled = false,
    bool isOutlined = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final foregroundColor = isDestructive
        ? colorScheme.error
        : (isFilled ? colorScheme.onPrimary : colorScheme.primary);
    final backgroundColor =
        isFilled ? (isDestructive ? colorScheme.error : colorScheme.primary) : null;

    return ButtonStyle(
      minimumSize: WidgetStateProperty.all(Size(0, height)),
      padding: WidgetStateProperty.all(padding),
      textStyle: WidgetStateProperty.all(TextStyle(fontSize: fontSize)),
      foregroundColor: WidgetStateProperty.all(foregroundColor),
      backgroundColor: backgroundColor != null ? WidgetStateProperty.all(backgroundColor) : null,
      side: isOutlined
          ? WidgetStateProperty.all(BorderSide(
              color: isDestructive ? colorScheme.error : colorScheme.outline,
            ))
          : null,
    );
  }

  Widget _buildIconButton(
    BuildContext context, {
    required Widget iconWidget,
    required double iconSize,
    required double buttonSize,
    required VoidCallback? onPressed,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = isDestructive ? colorScheme.error : null;

    return SizedBox(
      width: buttonSize,
      height: buttonSize,
      child: IconButton(
        onPressed: onPressed,
        icon: iconWidget,
        iconSize: iconSize,
        color: color,
        padding: EdgeInsets.zero,
        constraints: BoxConstraints(
          minWidth: buttonSize,
          minHeight: buttonSize,
        ),
      ),
    );
  }

  Widget _buildFilledButton(
    BuildContext context, {
    required Widget? iconWidget,
    required EdgeInsets padding,
    required double height,
    required double fontSize,
    required VoidCallback? onPressed,
  }) {
    final style = _getButtonStyle(
      context,
      padding: padding,
      height: height,
      fontSize: fontSize,
      isFilled: true,
    );

    if (iconWidget != null && label != null) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: iconWidget,
        label: Text(label!),
        style: style,
      );
    }

    return FilledButton(
      onPressed: onPressed,
      style: style,
      child: Text(label!),
    );
  }

  Widget _buildOutlinedButton(
    BuildContext context, {
    required Widget? iconWidget,
    required EdgeInsets padding,
    required double height,
    required double fontSize,
    required VoidCallback? onPressed,
  }) {
    final style = _getButtonStyle(
      context,
      padding: padding,
      height: height,
      fontSize: fontSize,
      isOutlined: true,
    );

    if (iconWidget != null && label != null) {
      return OutlinedButton.icon(
        onPressed: onPressed,
        icon: iconWidget,
        label: Text(label!),
        style: style,
      );
    }

    return OutlinedButton(
      onPressed: onPressed,
      style: style,
      child: Text(label!),
    );
  }

  Widget _buildTextButton(
    BuildContext context, {
    required Widget? iconWidget,
    required EdgeInsets padding,
    required double height,
    required double fontSize,
    required VoidCallback? onPressed,
  }) {
    final style = _getButtonStyle(
      context,
      padding: padding,
      height: height,
      fontSize: fontSize,
    );

    if (iconWidget != null && label != null) {
      return TextButton.icon(
        onPressed: onPressed,
        icon: iconWidget,
        label: Text(label!),
        style: style,
      );
    }

    return TextButton(
      onPressed: onPressed,
      style: style,
      child: Text(label!),
    );
  }
}

/// 自适应图标按钮
///
/// 简化版的图标按钮，根据平台自动调整大小
class AdaptiveIconButton extends StatelessWidget {
  const AdaptiveIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = AdaptiveButtonSize.medium,
    this.color,
    this.backgroundColor,
    this.isDestructive = false,
    this.enabled = true,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final AdaptiveButtonSize size;
  final Color? color;
  final Color? backgroundColor;
  final bool isDestructive;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final isDesktop = context.isDesktopLayout;
    final colorScheme = Theme.of(context).colorScheme;

    // 计算尺寸
    double buttonSize;
    double iconSize;

    switch (size) {
      case AdaptiveButtonSize.small:
        buttonSize = isDesktop ? 28 : 36;
        iconSize = isDesktop ? 16 : 20;
      case AdaptiveButtonSize.medium:
        buttonSize = isDesktop ? 36 : 44;
        iconSize = isDesktop ? 20 : 24;
      case AdaptiveButtonSize.large:
        buttonSize = isDesktop ? 44 : 52;
        iconSize = isDesktop ? 24 : 28;
    }

    final effectiveColor = isDestructive
        ? colorScheme.error
        : (color ?? colorScheme.onSurface);

    Widget button = SizedBox(
      width: buttonSize,
      height: buttonSize,
      child: IconButton(
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon),
        iconSize: iconSize,
        color: effectiveColor,
        padding: EdgeInsets.zero,
        style: backgroundColor != null
            ? IconButton.styleFrom(backgroundColor: backgroundColor)
            : null,
        constraints: BoxConstraints(
          minWidth: buttonSize,
          minHeight: buttonSize,
        ),
      ),
    );

    if (tooltip != null) {
      button = Tooltip(
        message: tooltip!,
        child: button,
      );
    }

    return button;
  }
}

/// 自适应按钮组
///
/// 水平排列多个按钮，根据平台调整间距
class AdaptiveButtonGroup extends StatelessWidget {
  const AdaptiveButtonGroup({
    super.key,
    required this.children,
    this.alignment = MainAxisAlignment.end,
    this.spacing,
  });

  final List<Widget> children;
  final MainAxisAlignment alignment;
  final double? spacing;

  @override
  Widget build(BuildContext context) {
    final effectiveSpacing = spacing ?? AppSpacing.toolbarButtonSpacing;

    return Row(
      mainAxisAlignment: alignment,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(width: effectiveSpacing),
          children[i],
        ],
      ],
    );
  }
}
