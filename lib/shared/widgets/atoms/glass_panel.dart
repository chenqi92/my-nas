import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/design_tokens.dart';

/// 设计稿 `.panel` 原子：玻璃下 BackdropFilter + 半透明 tint + hairline 描边，
/// 经典下退化为不透明 + 阴影。
///
/// 字段映射：
/// - `bg/border/blurSigma` 全部从 [DesignTokens] 取，调用方一般不传。
/// - 用 [strong]=true 走 `panelBgStrong`（dock / drawer / 浮层用）。
/// - 用 [radius] 控制圆角，默认 `DesignTokens.radiusLg`。
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    required this.child,
    this.strong = false,
    this.radius,
    this.padding,
    this.margin,
    this.border = true,
    this.constraints,
    super.key,
  });

  final Widget child;
  final bool strong;
  final double? radius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final bool border;
  final BoxConstraints? constraints;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final r = radius ?? DesignTokens.radiusLg;
    final bg = strong ? t.panelBgStrong : t.panelBg;
    final borderRadius = BorderRadius.circular(r);

    Widget content = Container(
      padding: padding,
      constraints: constraints,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: borderRadius,
        border: border ? Border.all(color: t.panelBorder, width: 1) : null,
        // 经典模式才需要阴影；收紧为带负 spread 的轻柔投影，避免浅色下
        // 出现过重的深色光晕。
        boxShadow: t.panelBlurSigma > 0
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.38 : 0.045),
                  blurRadius: isDark ? 26 : 14,
                  offset: const Offset(0, 7),
                  spreadRadius: -11,
                ),
              ],
      ),
      child: child,
    );

    if (t.panelBlurSigma > 0) {
      content = ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: t.panelBlurSigma,
            sigmaY: t.panelBlurSigma,
          ),
          child: content,
        ),
      );
    }

    return margin == null ? content : Padding(padding: margin!, child: content);
  }
}
