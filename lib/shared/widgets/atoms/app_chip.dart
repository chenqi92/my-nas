import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/design_tokens.dart';

/// 设计稿 `.chip` 原子：7px 圆角胶囊。
/// - [active]=true 时背景换 accent、文字换 accentContrast（active 态）。
/// - [onTap] 非空时可点击，并在 hover 时切到 cardBgHover + text0（对齐
///   `.chip:hover { color:var(--text-0); background:var(--card-bg-hover); }`）。
/// - 可选 [icon] 前置图标 / [trailing] 后置 widget。
class AppChip extends StatefulWidget {
  const AppChip({
    required this.label,
    this.icon,
    this.trailing,
    this.onTap,
    this.active = false,
    this.compact = false,
    super.key,
  });

  final String label;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool active;
  final bool compact;

  @override
  State<AppChip> createState() => _AppChipState();
}

class _AppChipState extends State<AppChip> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final hovered = _hovering && widget.onTap != null && !widget.active;
    final bg = widget.active
        ? t.accent
        : hovered
            ? t.cardBgHover
            : t.chipBg;
    final fg = widget.active
        ? t.accentContrast
        : hovered
            ? t.text0
            : t.text1;
    final padding = widget.compact
        ? const EdgeInsets.symmetric(horizontal: 9, vertical: 3)
        : const EdgeInsets.symmetric(horizontal: 11, vertical: 5);

    final body = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.icon != null) ...[
          Icon(widget.icon, size: 13, color: fg),
          const SizedBox(width: 6),
        ],
        Text(
          widget.label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: widget.active ? FontWeight.w600 : FontWeight.w500,
            color: fg,
          ),
        ),
        if (widget.trailing != null) ...[
          const SizedBox(width: 6),
          widget.trailing!,
        ],
      ],
    );

    final chip = AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: DesignTokens.ease,
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
      ),
      child: body,
    );

    if (widget.onTap == null) return chip;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
          child: chip,
        ),
      ),
    );
  }
}
