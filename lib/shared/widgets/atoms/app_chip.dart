import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/design_tokens.dart';

/// 设计稿 `.chip` 原子：12px 圆角胶囊。
/// - [active]=true 时背景换 accent、文字换 accentContrast（active 态）。
/// - [onTap] 非空时可点击（InkWell 自带按压/hover 涟漪）。
/// - 可选 [icon] 前置图标 / [trailing] 后置 widget。
class AppChip extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final bg = active ? t.accent : t.chipBg;
    final fg = active ? t.accentContrast : t.text1;
    final padding = compact
        ? const EdgeInsets.symmetric(horizontal: 9, vertical: 3)
        : const EdgeInsets.symmetric(horizontal: 11, vertical: 5);

    final body = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 5),
        ],
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: active ? FontWeight.w600 : FontWeight.w500,
            color: fg,
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 6),
          trailing!,
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

    if (onTap == null) return chip;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
        child: chip,
      ),
    );
  }
}
