import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/music/presentation/providers/lyric_provider.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';
import 'package:my_nas/shared/widgets/atoms/glass_panel.dart';

/// 设计稿 app.css `.dlyric`：桌面端应用内歌词浮窗（底部居中玻璃药丸）。
///
/// 由 [desktopLyricFloatProvider] 控制显隐，仅在有歌曲且开关开启时渲染。
/// 内部独立 watch 播放位置 + 歌词，避免拖累整个外壳重建。
class DesktopLyricFloat extends ConsumerWidget {
  const DesktopLyricFloat({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DesignTokens.of(context);
    final lyric = ref.watch(currentLyricProvider).lyricData;
    final state = ref.watch(musicPlayerControllerProvider);
    final lines = lyric.lines;
    if (lines.isEmpty) return const SizedBox.shrink();

    final idx = lyric.getCurrentLineIndex(state.position);
    if (idx < 0 || idx >= lines.length) return const SizedBox.shrink();
    final line = lines[idx];
    final text = line.text.trim();
    if (text.isEmpty) return const SizedBox.shrink();
    final translation = line.translation?.trim();

    return Positioned(
      bottom: 100,
      left: 0,
      right: 0,
      child: Center(
        child: GlassPanel(
          strong: true,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: t.text0,
                ),
              ),
              if (translation != null && translation.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  translation,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: t.text2),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
