import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/design_tokens.dart';

/// 设计稿 `.dot` 原子：连接/状态指示点。
enum DotStatus { ok, warn, err, off, accent, hot }

class StatusDot extends StatelessWidget {
  const StatusDot(this.status, {this.size = 7, this.glow = true, super.key});

  final DotStatus status;
  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final color = switch (status) {
      DotStatus.ok => t.ok,
      DotStatus.warn => t.warn,
      DotStatus.err => t.err,
      DotStatus.off => t.text3,
      DotStatus.accent => t.accent,
      DotStatus.hot => t.hot,
    };

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: glow && status != DotStatus.off
            ? [BoxShadow(color: color, blurRadius: 7)]
            : null,
      ),
    );
  }
}

/// 直播红点带 pulse 动画。
class LiveDot extends StatefulWidget {
  const LiveDot({this.size = 8, super.key});

  final double size;

  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) {
        final v = 0.35 + (1 - _c.value) * 0.65;
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: t.hot.withValues(alpha: v),
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: t.hot, blurRadius: 8 * v)],
          ),
        );
      },
    );
  }
}
