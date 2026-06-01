import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/design_tokens.dart';

/// 设计稿 `.card` 原子：不透明卡片 + hairline 描边 + 轻阴影。
/// 经典与玻璃两种模式都用 `cardBg`，二者由 [DesignTokens] 内部区分。
class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.radius,
    this.hover = false,
    this.selected = false,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double? radius;
  final bool hover;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final r = radius ?? DesignTokens.radius;
    final br = BorderRadius.circular(r);
    final bg = hover
        ? t.cardBgHover
        : selected
            ? t.chipBgActive
            : t.cardBg;
    final borderColor = selected ? t.accent : t.cardBorder;

    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: DesignTokens.ease,
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: br,
        border: Border.all(color: borderColor, width: selected ? 1.2 : 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );

    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: br,
        child: card,
      ),
    );
  }
}
