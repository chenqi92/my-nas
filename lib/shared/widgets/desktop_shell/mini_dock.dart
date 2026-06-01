import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';
import 'package:my_nas/shared/widgets/atoms/app_progress_bar.dart';
import 'package:my_nas/shared/widgets/atoms/glass_panel.dart';

/// 设计稿 `.dock`：固定底部居中 680px 浮层音乐迷你播放器。
/// 仅在有当前播放歌曲时显示；点击封面或音乐按钮进入 NowPlaying 全屏。
class MiniDock extends ConsumerWidget {
  const MiniDock({
    required this.onOpenNowPlaying,
    required this.onOpenCast,
    super.key,
  });

  final VoidCallback onOpenNowPlaying;
  final VoidCallback onOpenCast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final music = ref.watch(currentMusicProvider);
    if (music == null) return const SizedBox.shrink();

    final t = DesignTokens.of(context);
    final state = ref.watch(musicPlayerControllerProvider);
    final notifier = ref.read(musicPlayerControllerProvider.notifier);

    final w = MediaQuery.of(context).size.width;
    final maxW = (w - 60) < 680 ? (w - 60) : 680.0;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: GlassPanel(
            strong: true,
            radius: 16,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                _Cover(coverUrl: music.coverUrl, onTap: onOpenNowPlaying),
                const SizedBox(width: 12),
                SizedBox(
                  width: 148,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        music.title ?? music.name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: t.text0,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        music.artist ?? '',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: t.text2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _Btn(
                  icon: Icons.skip_previous_rounded,
                  onTap: notifier.playPrevious,
                ),
                _PlayBtn(
                  playing: state.isPlaying,
                  onTap: notifier.playOrPause,
                ),
                _Btn(
                  icon: Icons.skip_next_rounded,
                  onTap: notifier.playNext,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    children: [
                      _Time(text: _fmt(state.position)),
                      const SizedBox(width: 9),
                      Expanded(
                        child: AppProgressBar(value: state.progress),
                      ),
                      const SizedBox(width: 9),
                      _Time(text: _fmt(state.duration)),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                _Btn(
                    icon: Icons.lyrics_outlined, onTap: onOpenNowPlaying),
                _Btn(icon: Icons.cast_rounded, onTap: onOpenCast),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _fmt(Duration d) {
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.coverUrl, required this.onTap});
  final String? coverUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: t.insetBg,
          borderRadius: BorderRadius.circular(9),
          image: (coverUrl != null && coverUrl!.isNotEmpty)
              ? DecorationImage(
                  image: NetworkImage(coverUrl!),
                  fit: BoxFit.cover,
                )
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: (coverUrl == null || coverUrl!.isEmpty)
            ? Icon(Icons.music_note_rounded, color: t.text3)
            : null,
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  const _Btn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        hoverColor: t.chipBg,
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(icon, size: 17, color: t.text2),
        ),
      ),
    );
  }
}

class _PlayBtn extends StatelessWidget {
  const _PlayBtn({required this.playing, required this.onTap});
  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: t.accent,
        shape: const CircleBorder(),
        elevation: 4,
        shadowColor: t.accent.withValues(alpha: 0.45),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 22,
              color: t.accentContrast,
            ),
          ),
        ),
      ),
    );
  }
}

class _Time extends StatelessWidget {
  const _Time({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return SizedBox(
      width: 38,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: t.text2,
          fontFeatures: const [FontFeature.tabularFigures()],
          fontFamily: 'SF Mono',
          fontFamilyFallback: const ['Menlo', 'monospace'],
        ),
      ),
    );
  }
}
