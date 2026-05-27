import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/ui_style.dart';
import 'package:my_nas/shared/providers/ui_style_provider.dart';

/// 通用玻璃效果容器
/// 
/// 根据当前 UI 风格自动应用合适的视觉效果：
/// - Classic 模式：传统不透明背景
/// - Liquid Glass 模式：模糊背景 + 半透明 + 光晕边框
class GlassContainer extends ConsumerWidget {
  const GlassContainer({
    required this.child,
    super.key,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.padding,
    this.margin,
    this.tintColor,
    this.backgroundColor,
    this.border,
    this.constraints,
    this.width,
    this.height,
    this.clipBehavior = Clip.antiAlias,
  });

  /// 子组件
  final Widget child;

  /// 圆角
  final BorderRadius borderRadius;

  /// 内边距
  final EdgeInsetsGeometry? padding;

  /// 外边距
  final EdgeInsetsGeometry? margin;

  /// 染色颜色（仅玻璃模式生效）
  final Color? tintColor;

  /// 自定义背景色（覆盖默认计算的颜色）
  final Color? backgroundColor;

  /// 自定义边框
  final BoxBorder? border;

  /// 约束
  final BoxConstraints? constraints;

  /// 宽度
  final double? width;

  /// 高度
  final double? height;

  /// 裁剪行为
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiStyle = ref.watch(uiStyleProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final glassStyle = GlassTheme.getStyle(uiStyle, isDark: isDark);

    // 计算背景色
    final bgColor = backgroundColor ??
        GlassTheme.getBackgroundColor(
          glassStyle,
          isDark: isDark,
          tintColor: tintColor,
        );

    // 计算边框
    final effectiveBorder = border ??
        Border.all(
          color: GlassTheme.getBorderColor(glassStyle, isDark: isDark),
          width: glassStyle.enableBorderGlow ? 0.5 : 1.0,
        );

    // 构建装饰
    final decoration = BoxDecoration(
      color: bgColor,
      borderRadius: borderRadius,
      border: effectiveBorder,
      boxShadow: GlassTheme.getGlowShadows(
        glassStyle,
        isDark: isDark,
        glowColor: tintColor?.withValues(alpha: 0.1),
      ),
    );

    // 构建容器内容
    Widget content = Container(
      width: width,
      height: height,
      padding: padding,
      margin: margin,
      constraints: constraints,
      decoration: decoration,
      child: child,
    );

    // 如果需要模糊效果，包装 BackdropFilter
    if (glassStyle.needsBlur) {
      content = ClipRRect(
        borderRadius: borderRadius,
        clipBehavior: clipBehavior,
        child: BackdropFilter(
          filter: glassStyle.blurFilter!,
          child: content,
        ),
      );
    }

    return content;
  }
}

/// 玻璃效果底部弹窗容器
/// 专为底部弹窗优化的玻璃容器
class GlassBottomSheetContainer extends ConsumerWidget {
  const GlassBottomSheetContainer({
    required this.child,
    super.key,
    this.topBorderRadius = 24.0,
  });

  final Widget child;
  final double topBorderRadius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiStyle = ref.watch(uiStyleProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final glassStyle = GlassTheme.getStyle(uiStyle, isDark: isDark);

    final borderRadius = BorderRadius.vertical(
      top: Radius.circular(topBorderRadius),
    );

    // 计算背景色 - 底部弹窗使用稍高的不透明度
    final bgColor = glassStyle.needsBlur
        ? (isDark
            ? AppColors.darkSurface.withValues(
                alpha: (glassStyle.backgroundOpacity + 0.15).clamp(0.0, 1.0),
              )
            : AppColors.lightSurface.withValues(
                alpha: (glassStyle.backgroundOpacity + 0.1).clamp(0.0, 1.0),
              ))
        : (isDark ? AppColors.darkSurface : AppColors.lightSurface);

    final decoration = BoxDecoration(
      color: bgColor,
      borderRadius: borderRadius,
      border: Border(
        top: BorderSide(
          color: isDark
              ? AppColors.glassStroke
              : AppColors.lightOutline.withValues(alpha: 0.2),
        ),
      ),
    );

    Widget content = DecoratedBox(
      decoration: decoration,
      child: child,
    );

    if (glassStyle.needsBlur) {
      content = ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: glassStyle.blurFilter!,
          child: content,
        ),
      );
    }

    return content;
  }
}

/// 玻璃效果卡片
/// 常用于列表项、设置卡片等
class GlassCard extends ConsumerWidget {
  const GlassCard({
    required this.child,
    super.key,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.tintColor,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadius borderRadius;
  final Color? tintColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiStyle = ref.watch(uiStyleProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final glassStyle = GlassTheme.getStyle(uiStyle, isDark: isDark);

    // 卡片使用更轻微的效果
    final bgColor = glassStyle.needsBlur
        ? (isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.02))
        : (isDark
            ? AppColors.darkSurfaceVariant
            : AppColors.lightSurfaceVariant);

    final card = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: borderRadius,
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.04),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: borderRadius,
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );

    // 卡片通常不需要自己的模糊效果，依赖父容器
    return card;
  }
}
