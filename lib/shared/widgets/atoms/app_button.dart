import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/design_tokens.dart';

/// 设计稿 `.btn` 系列原子按钮。
///
/// 对应 `styles.css`：
/// - [AppButtonVariant.filled] → `.btn`：segOnBg 底 + .5px hairline 边。
/// - [AppButtonVariant.primary] → `.btn-primary`：accent 渐变 + accentContrast 字。
/// - [AppButtonVariant.ghost] → `.btn-ghost`：透明底/边，hover 显 chipBg。
enum AppButtonVariant { filled, primary, ghost }

class AppButton extends StatefulWidget {
  const AppButton({
    required this.label,
    this.icon,
    this.onPressed,
    this.variant = AppButtonVariant.filled,
    this.dense = false,
    super.key,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;

  /// 更紧凑（用于工具条），padding 略小。
  final bool dense;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final disabled = widget.onPressed == null;
    final isPrimary = widget.variant == AppButtonVariant.primary;
    final isGhost = widget.variant == AppButtonVariant.ghost;

    final Color fg;
    final Color? bg;
    final Gradient? gradient;
    final Color borderColor;
    final List<BoxShadow>? shadow;

    switch (widget.variant) {
      case AppButtonVariant.primary:
        fg = t.accentContrast;
        bg = null;
        gradient = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(t.accent, Colors.white, 0.12)!,
            t.accent,
          ],
        );
        borderColor = Colors.transparent;
        shadow = [
          BoxShadow(
            color: t.accent.withValues(alpha: 0.4),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ];
      case AppButtonVariant.ghost:
        fg = t.text0;
        bg = _hovering ? t.chipBg : Colors.transparent;
        gradient = null;
        borderColor = Colors.transparent;
        shadow = null;
      case AppButtonVariant.filled:
        fg = t.text0;
        bg = _hovering ? t.cardBgHover : t.segOnBg;
        gradient = null;
        borderColor = t.hairline;
        shadow = [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ];
    }

    final body = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.icon != null) ...[
          Icon(widget.icon, size: 15, color: fg),
          const SizedBox(width: 7),
        ],
        Text(
          widget.label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: isPrimary ? FontWeight.w600 : FontWeight.w500,
            color: fg,
          ),
        ),
      ],
    );

    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: MouseRegion(
        cursor: disabled ? MouseCursor.defer : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: disabled ? null : widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: DesignTokens.ease,
            padding: EdgeInsets.symmetric(
              horizontal: widget.dense ? 10 : 13,
              vertical: widget.dense ? 5 : 6,
            ),
            decoration: BoxDecoration(
              color: bg,
              gradient: gradient,
              borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
              border: isGhost
                  ? null
                  : Border.all(color: borderColor, width: 0.5),
              boxShadow: shadow,
            ),
            child: body,
          ),
        ),
      ),
    );
  }
}
