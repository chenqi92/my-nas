import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/core/theme/dynamic_accent_provider.dart';
import 'package:my_nas/core/theme/dynamic_accent_service.dart';

/// 设计稿 `.ambient`：动态径向氛围光层。绑定 [DynamicAccentProvider]
/// 的当前 RGB，仅在 `on=true && 有播放` 时显示。
///
/// 放在 [Stack] 最底层，sidebar/topbar/content 都在它之上。
class AmbientLayer extends ConsumerWidget {
  const AmbientLayer({required this.on, super.key});

  final bool on;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = ref.watch(musicDynamicAccentValueProvider);
    final t = DesignTokens.of(context);
    final rgb = accent == DynamicAccent.fallback ? t.accent : accent.accent;

    return IgnorePointer(
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 900),
        curve: DesignTokens.ease,
        opacity: on ? 1.0 : 0.0,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 1400),
          curve: DesignTokens.ease,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, 1.1),
              radius: 1.4,
              colors: [
                rgb.withValues(alpha: 0.18),
                rgb.withValues(alpha: 0.0),
              ],
              stops: const [0.0, 0.7],
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.85, -1.1),
                radius: 1.1,
                colors: [
                  rgb.withValues(alpha: 0.10),
                  rgb.withValues(alpha: 0.0),
                ],
                stops: const [0.0, 0.7],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
