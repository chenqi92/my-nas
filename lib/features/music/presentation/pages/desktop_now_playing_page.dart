import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/music/data/services/lyric_service.dart'
    show LyricLine;
import 'package:my_nas/features/music/domain/entities/music_item.dart';
import 'package:my_nas/features/music/presentation/providers/lyric_provider.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';
import 'package:my_nas/features/music/presentation/widgets/music_cover.dart';
import 'package:my_nas/features/video/presentation/widgets/cast/cast_device_sheet.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';
import 'package:my_nas/shared/widgets/atoms/app_progress_bar.dart';

/// 桌面端「正在播放」全屏。设计稿 media2.jsx (NowPlaying)：
/// 左 340x340 大封面 + 标题 / 艺人 / 专辑，右 maskImage 歌词三态，
/// 顶部小工具条（返回 / 桌面歌词 toggle / 投屏），底部进度 + 控制条。
class DesktopNowPlayingPage extends ConsumerWidget {
  const DesktopNowPlayingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DesignTokens.of(context);
    final music = ref.watch(currentMusicProvider);
    final state = ref.watch(musicPlayerControllerProvider);
    final notifier = ref.read(musicPlayerControllerProvider.notifier);
    final lyric = ref.watch(currentLyricProvider).lyricData;
    final lines = lyric.lines;
    final currentLine = music == null
        ? -1
        : lyric.getCurrentLineIndex(state.position);
    // 封面三路兼容（内嵌字节 / file:// / 网络）；本地 NAS 封面不再留白。
    final bgImage = musicCoverProvider(music);

    return Scaffold(
      backgroundColor: t.bg,
      body: Stack(
        children: [
          if (bgImage != null) ...[
            Positioned.fill(
              child: ColorFiltered(
                // np-bg saturate(140%)：仅提升背景图饱和度（亮度保持）。
                colorFilter: const ColorFilter.matrix(<double>[
                  1.31496, -0.28608, -0.02888, 0, 0,
                  -0.08504, 1.11392, -0.02888, 0, 0,
                  -0.08504, -0.28608, 1.37112, 0, 0,
                  0, 0, 0, 1, 0,
                ]),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      image: bgImage,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ),
            const Positioned.fill(child: BackdropAndScrim()),
          ] else
            const Positioned.fill(child: SizedBox.shrink()),
          ColoredBox(color: Colors.black.withValues(alpha: 0.55)),
          SafeArea(
            child: Column(
              children: [
                _Top(
                  t: t,
                  onClose: () {
                    if (GoRouter.of(context).canPop()) {
                      GoRouter.of(context).pop();
                    } else {
                      GoRouter.of(context).go('/music');
                    }
                  },
                  onCast: () => _openCast(context),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 80),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: _ArtAndTitle(
                            music: music,
                            title: music?.title ?? music?.name ?? '未播放',
                            subtitle: [
                              music?.artist,
                              music?.album,
                            ].whereType<String>().join(' · '),
                          ),
                        ),
                        const SizedBox(width: 60),
                        Expanded(
                          child: _Lyrics(
                            lines: lines,
                            currentLine: currentLine,
                            onSeek: notifier.seek,
                            t: t,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _Controls(
                  position: state.position,
                  duration: state.duration,
                  isPlaying: state.isPlaying,
                  playMode: state.playMode,
                  onPrev: notifier.playPrevious,
                  onNext: notifier.playNext,
                  onToggle: notifier.playOrPause,
                  onSeek: notifier.seek,
                  onSetPlayMode: notifier.setPlayMode,
                  t: t,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 正在播放页投屏：弹出投屏设备选择 sheet（复用视频侧 CastDeviceSheet）。
void _openCast(BuildContext context) {
  showAdaptiveModalSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => CastDeviceSheet(
      onDeviceSelected: (_) => Navigator.of(ctx).pop(),
    ),
  );
}

class BackdropAndScrim extends StatelessWidget {
  const BackdropAndScrim({super.key});

  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            // 设计固定 scrim：rgba(6,7,11,.6) → rgba(6,7,11,.92)。
            colors: [
              Color(0x9906070B),
              Color(0xEB06070B),
            ],
          ),
        ),
      );
}

class _Top extends StatelessWidget {
  const _Top({required this.t, required this.onClose, required this.onCast});
  final DesignTokens t;
  final VoidCallback onClose;
  final VoidCallback onCast;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(28, 22, 28, 22),
        child: Row(
          children: [
            IconButton(
              onPressed: onClose,
              icon: Icon(Icons.keyboard_arrow_down_rounded,
                  color: t.text0, size: 22),
            ),
            const SizedBox(width: 6),
            Text(
              '正在播放',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: t.text2,
                letterSpacing: 0.6,
              ),
            ),
            const Spacer(),
            Consumer(
              builder: (context, ref, _) {
                final on = ref.watch(desktopLyricFloatProvider);
                return IconButton(
                  onPressed: () => ref
                      .read(desktopLyricFloatProvider.notifier)
                      .update((v) => !v),
                  icon: Icon(
                    on ? Icons.lyrics_rounded : Icons.lyrics_outlined,
                    color: on ? t.accentBright : t.text1,
                    size: 18,
                  ),
                  tooltip: on ? '关闭桌面歌词' : '桌面歌词',
                );
              },
            ),
            IconButton(
              onPressed: onCast,
              icon: Icon(Icons.cast_rounded, color: t.text1, size: 18),
              tooltip: '投屏',
            ),
          ],
        ),
      );
}

class _ArtAndTitle extends StatelessWidget {
  const _ArtAndTitle({
    required this.music,
    required this.title,
    required this.subtitle,
  });

  final MusicItem? music;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.7),
                blurRadius: 60,
                offset: const Offset(0, 24),
              ),
            ],
          ),
          child: MusicCoverImage(
            music: music,
            size: 340,
            radius: 20,
            iconSize: 64,
          ),
        ),
        const SizedBox(height: 26),
        Text(
          title,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            color: t.text0,
            letterSpacing: -0.4,
          ),
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 15, color: t.text1),
          ),
        ],
      ],
    );
  }
}

/// 歌词区：可滚动 + 点击行 seek + 当前行自动居中（用真实行高，
/// 不再用固定 48px 偏移，带翻译/长行也能正确居中）。
class _Lyrics extends StatefulWidget {
  const _Lyrics({
    required this.lines,
    required this.currentLine,
    required this.onSeek,
    required this.t,
  });

  final List<LyricLine> lines;
  final int currentLine;
  final ValueChanged<Duration> onSeek;
  final DesignTokens t;

  @override
  State<_Lyrics> createState() => _LyricsState();
}

class _LyricsState extends State<_Lyrics> {
  final _controller = ScrollController();
  final _rowKeys = <int, GlobalKey>{};

  @override
  void didUpdateWidget(_Lyrics oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentLine != widget.currentLine) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _centerActiveLine());
    }
  }

  void _centerActiveLine() {
    final ctx = _rowKeys[widget.currentLine]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: const Duration(milliseconds: 380),
      curve: DesignTokens.ease,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final lines = widget.lines;
    if (lines.isEmpty) {
      return Center(
        child: Text(
          '暂无歌词',
          style: TextStyle(fontSize: 16, color: t.text3),
        ),
      );
    }
    return ClipRect(
      child: ShaderMask(
        shaderCallback: (rect) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black,
            Colors.black,
            Colors.transparent,
          ],
          stops: [0.0, 0.25, 0.75, 1.0],
        ).createShader(rect),
        blendMode: BlendMode.dstIn,
        child: SizedBox(
          height: 420,
          child: ListView.builder(
            controller: _controller,
            padding: const EdgeInsets.symmetric(vertical: 180),
            itemCount: lines.length,
            itemBuilder: (_, i) {
              final key = _rowKeys.putIfAbsent(i, () => GlobalKey());
              return _LyricRow(
                key: key,
                text: lines[i].text,
                translation: lines[i].translation,
                active: i == widget.currentLine,
                onTap: () => widget.onSeek(lines[i].time),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LyricRow extends StatelessWidget {
  const _LyricRow({
    required this.text,
    required this.translation,
    required this.active,
    required this.onTap,
    super.key,
  });

  final String text;
  final String? translation;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 220),
              curve: DesignTokens.ease,
              style: TextStyle(
                fontSize: active ? 26 : 22,
                fontWeight: FontWeight.w700,
                color: active ? t.text0 : t.text3,
              ),
              child: Text(text),
            ),
            if (translation != null && translation!.isNotEmpty) ...[
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 220),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: active ? t.text1 : t.text3,
                ),
                child: Text(translation!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.position,
    required this.duration,
    required this.isPlaying,
    required this.playMode,
    required this.onPrev,
    required this.onNext,
    required this.onToggle,
    required this.onSeek,
    required this.onSetPlayMode,
    required this.t,
  });

  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final PlayMode playMode;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToggle;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<PlayMode> onSetPlayMode;
  final DesignTokens t;

  @override
  Widget build(BuildContext context) {
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;
    final isShuffle = playMode == PlayMode.shuffle;
    final isRepeatOne = playMode == PlayMode.repeatOne;
    return Padding(
      padding: const EdgeInsets.fromLTRB(80, 18, 80, 32),
      child: Column(
        children: [
          Row(
            children: [
              _time(_fmt(position)),
              const SizedBox(width: 14),
              Expanded(
                child: _SeekBar(
                  progress: progress,
                  duration: duration,
                  onSeek: onSeek,
                ),
              ),
              const SizedBox(width: 14),
              _time(_fmt(duration)),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                // 随机：开则回到列表循环，关则切随机。
                onPressed: () => onSetPlayMode(
                    isShuffle ? PlayMode.loop : PlayMode.shuffle),
                tooltip: isShuffle ? '关闭随机' : '随机播放',
                icon: Icon(
                  Icons.shuffle_rounded,
                  color: isShuffle ? t.accentBright : t.text1,
                  size: 18,
                ),
              ),
              const SizedBox(width: 14),
              IconButton(
                onPressed: onPrev,
                icon: Icon(Icons.skip_previous_rounded,
                    color: t.text0, size: 28),
              ),
              const SizedBox(width: 8),
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: t.accent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: t.accent.withValues(alpha: 0.45),
                      blurRadius: 18,
                    ),
                  ],
                ),
                child: IconButton(
                  onPressed: onToggle,
                  icon: Icon(
                    isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: t.accentContrast,
                    size: 32,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: onNext,
                icon: Icon(Icons.skip_next_rounded,
                    color: t.text0, size: 28),
              ),
              const SizedBox(width: 14),
              IconButton(
                // 循环：单曲循环 ↔ 列表循环。
                onPressed: () => onSetPlayMode(
                    isRepeatOne ? PlayMode.loop : PlayMode.repeatOne),
                tooltip: isRepeatOne ? '单曲循环' : '列表循环',
                icon: Icon(
                  isRepeatOne ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                  color: isRepeatOne ? t.accentBright : t.text1,
                  size: 18,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _time(String text) => Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: t.text2,
          fontFeatures: const [FontFeature.tabularFigures()],
          fontFamily: 'SF Mono',
          fontFamilyFallback: const ['Menlo'],
        ),
      );

  static String _fmt(Duration d) {
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }
}

/// 进度条：点击 / 拖动定位（seek）。视觉沿用 [AppProgressBar]。
class _SeekBar extends StatelessWidget {
  const _SeekBar({
    required this.progress,
    required this.duration,
    required this.onSeek,
  });

  final double progress;
  final Duration duration;
  final ValueChanged<Duration> onSeek;

  void _seekTo(double dx, double width) {
    if (duration.inMilliseconds <= 0 || width <= 0) return;
    final frac = (dx / width).clamp(0.0, 1.0);
    onSeek(Duration(milliseconds: (duration.inMilliseconds * frac).round()));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _seekTo(d.localPosition.dx, w),
          onHorizontalDragUpdate: (d) => _seekTo(d.localPosition.dx, w),
          child: SizedBox(
            height: 16,
            child: Center(child: AppProgressBar(value: progress, height: 5)),
          ),
        );
      },
    );
  }
}
