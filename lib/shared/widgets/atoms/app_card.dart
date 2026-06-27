import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/design_tokens.dart';

/// 设计稿 `.card` 原子：不透明卡片 + hairline 描边 + 轻阴影。
/// 经典与玻璃两种模式都用 `cardBg`，二者由 [DesignTokens] 内部区分。
///
/// 可交互卡片（[onTap] 非空）会随指针 hover 自动切换 `cardBgHover`；
/// 外部 [hover]=true 可强制 hover 视觉（用于受控高亮）。
class AppCard extends StatefulWidget {
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
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final r = widget.radius ?? DesignTokens.radius;
    final br = BorderRadius.circular(r);
    final hovered = _hovering || widget.hover;
    final bg = hovered
        ? t.cardBgHover
        : widget.selected
        ? t.chipBgActive
        : t.cardBg;
    final borderColor = widget.selected ? t.accent : t.cardBorder;

    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: DesignTokens.ease,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: br,
        border: Border.all(
          color: borderColor,
          width: widget.selected ? 1.2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.36 : 0.045),
            blurRadius: isDark ? 24 : 14,
            offset: const Offset(0, 7),
            spreadRadius: -12,
          ),
        ],
      ),
      child: widget.child,
    );

    if (widget.onTap == null) return card;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(onTap: widget.onTap, borderRadius: br, child: card),
      ),
    );
  }
}
