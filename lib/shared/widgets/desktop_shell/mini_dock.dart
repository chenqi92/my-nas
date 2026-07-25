import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';
import 'package:my_nas/features/music/presentation/providers/desktop_lyric_provider.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';
import 'package:my_nas/features/music/presentation/widgets/music_cover.dart';
import 'package:my_nas/shared/widgets/atoms/app_progress_bar.dart';
import 'package:my_nas/shared/widgets/atoms/glass_panel.dart';

/// 设计稿 `.dock`：固定底部居中 720px 浮层音乐迷你播放器。
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
    final desktopLyric = ref.watch(desktopLyricProvider);

    final w = MediaQuery.of(context).size.width;
    final maxW = (w - 60) < 720 ? (w - 60) : 720.0;

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
                _Cover(music: music, onTap: onOpenNowPlaying),
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
                        style: TextStyle(fontSize: 11.5, color: t.text2),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _Btn(
                  icon: Icons.skip_previous_rounded,
                  tooltip: '上一首',
                  onTap: notifier.playPrevious,
                ),
                _Btn(
                  icon: Icons.replay_10_rounded,
                  tooltip: '快退 10 秒',
                  width: 28,
                  onTap: () {
                    final target = state.position - const Duration(seconds: 10);
                    notifier.seek(target.isNegative ? Duration.zero : target);
                  },
                ),
                _PlayBtn(playing: state.isPlaying, onTap: notifier.playOrPause),
                _Btn(
                  icon: Icons.forward_10_rounded,
                  tooltip: '快进 10 秒',
                  width: 28,
                  onTap: () {
                    final target = state.position + const Duration(seconds: 10);
                    notifier.seek(
                      target > state.duration ? state.duration : target,
                    );
                  },
                ),
                _Btn(
                  icon: Icons.skip_next_rounded,
                  tooltip: '下一首',
                  onTap: notifier.playNext,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    children: [
                      _Time(text: _fmt(state.position)),
                      const SizedBox(width: 9),
                      Expanded(
                        child: _SeekProgress(
                          progress: state.progress,
                          duration: state.duration,
                          onSeek: notifier.seek,
                        ),
                      ),
                      const SizedBox(width: 9),
                      _Time(text: _fmt(state.duration)),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                _Btn(
                  icon: Icons.lyrics_outlined,
                  tooltip: '歌词',
                  onTap: onOpenNowPlaying,
                ),
                _Btn(
                  icon: desktopLyric.isVisible
                      ? Icons.desktop_windows_rounded
                      : Icons.desktop_windows_outlined,
                  tooltip: desktopLyric.isVisible ? '关闭桌面歌词' : '桌面歌词',
                  onTap: desktopLyric.isInitialized
                      ? ref.read(desktopLyricProvider.notifier).toggle
                      : () {},
                ),
                _Btn(
                  icon: Icons.cast_rounded,
                  tooltip: '投屏',
                  onTap: onOpenCast,
                ),
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

/// 迷你播放器进度条也支持点击和拖动定位，避免必须先进入全屏播放器
/// 才能快进或回退。
class _SeekProgress extends StatelessWidget {
  const _SeekProgress({
    required this.progress,
    required this.duration,
    required this.onSeek,
  });

  final double progress;
  final Duration duration;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    final enabled = duration.inMilliseconds > 0;

    void seekTo(double dx, double width) {
      if (!enabled || width <= 0) return;
      final ratio = (dx / width).clamp(0.0, 1.0);
      onSeek(Duration(milliseconds: (duration.inMilliseconds * ratio).round()));
    }

    void seekBy(double delta) {
      final ratio = (progress + delta).clamp(0.0, 1.0);
      onSeek(Duration(milliseconds: (duration.inMilliseconds * ratio).round()));
    }

    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '播放进度',
      hint: '上下调整 10%，点击或拖动可定位',
      enabled: enabled,
      onIncrease: enabled ? () => seekBy(0.1) : null,
      onDecrease: enabled ? () => seekBy(-0.1) : null,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        child: LayoutBuilder(
          builder: (context, constraints) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: enabled
                ? (details) =>
                      seekTo(details.localPosition.dx, constraints.maxWidth)
                : null,
            onHorizontalDragUpdate: enabled
                ? (details) =>
                      seekTo(details.localPosition.dx, constraints.maxWidth)
                : null,
            child: SizedBox(
              height: 24,
              child: Center(child: AppProgressBar(value: progress, height: 4)),
            ),
          ),
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.music, required this.onTap});
  final MusicItem music;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      // 封面三路兼容（内嵌字节 / file:// 本地 / 网络），网络走磁盘缓存。
      child: MusicCoverImage(music: music, size: 46, radius: 9),
    ),
  );
}

class _Btn extends StatelessWidget {
  const _Btn({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.width = 32,
  });
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final double width;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        hoverColor: t.chipBg,
        child: SizedBox(
          width: width,
          height: 32,
          child: Icon(icon, size: 17, color: t.text2),
        ),
      ),
    );
    return tooltip == null
        ? button
        : Semantics(
            button: true,
            label: tooltip,
            excludeSemantics: true,
            onTap: onTap,
            child: Tooltip(message: tooltip, child: button),
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
    return Semantics(
      button: true,
      label: playing ? '暂停' : '播放',
      excludeSemantics: true,
      onTap: onTap,
      child: Padding(
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
