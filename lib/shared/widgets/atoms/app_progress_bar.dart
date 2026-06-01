import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/design_tokens.dart';

/// 设计稿 `.bar` 原子：横向进度条 +（可选）accent 渐变。
class AppProgressBar extends StatelessWidget {
  const AppProgressBar({
    required this.value,
    this.height = 5,
    this.gradient = true,
    this.color,
    super.key,
  });

  /// 0.0 .. 1.0，超出会被 clamp。
  final double value;
  final double height;

  /// `true` 走 accent-deep → accent-bright 线性渐变；`false` 走纯色。
  final bool gradient;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final v = value.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: height,
        color: t.insetBg,
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: v == 0 ? 0.0001 : v,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: gradient && color == null
                  ? LinearGradient(colors: [t.accentDeep, t.accentBright])
                  : null,
              color: color ?? (gradient ? null : t.accent),
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}
