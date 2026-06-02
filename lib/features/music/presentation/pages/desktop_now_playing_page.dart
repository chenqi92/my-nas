import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/music/data/services/lyric_service.dart'
    show LyricLine;
import 'package:my_nas/features/music/presentation/providers/lyric_provider.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';
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

    return Scaffold(
      backgroundColor: t.bg,
      body: Stack(
        children: [
          if (music != null && music.coverUrl != null)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: NetworkImage(music.coverUrl!),
                    fit: BoxFit.cover,
                  ),
                ),
                child: BackdropAndScrim(t: t),
              ),
            )
          else
            const Positioned.fill(child: SizedBox.shrink()),
          ColoredBox(color: Colors.black.withValues(alpha: 0.55)),
          SafeArea(
            child: Column(
              children: [
                _Top(t: t, onClose: () {
                  if (GoRouter.of(context).canPop()) {
                    GoRouter.of(context).pop();
                  } else {
                    GoRouter.of(context).go('/music');
                  }
                }),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 80),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: _ArtAndTitle(
                            coverUrl: music?.coverUrl,
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
                  onPrev: notifier.playPrevious,
                  onNext: notifier.playNext,
                  onToggle: notifier.playOrPause,
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

class BackdropAndScrim extends StatelessWidget {
  const BackdropAndScrim({required this.t, super.key});
  final DesignTokens t;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              t.bg.withValues(alpha: 0.6),
              t.bg.withValues(alpha: 0.92),
            ],
          ),
        ),
      );
}

class _Top extends StatelessWidget {
  const _Top({required this.t, required this.onClose});
  final DesignTokens t;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
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
                letterSpacing: 1.2,
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
              onPressed: () {},
              icon: Icon(Icons.cast_rounded, color: t.text1, size: 18),
              tooltip: '投屏',
            ),
          ],
        ),
      );
}

class _ArtAndTitle extends StatelessWidget {
  const _ArtAndTitle({
    required this.coverUrl,
    required this.title,
    required this.subtitle,
  });

  final String? coverUrl;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 340,
          height: 340,
          decoration: BoxDecoration(
            color: t.insetBg,
            borderRadius: BorderRadius.circular(20),
            image: (coverUrl != null && coverUrl!.isNotEmpty)
                ? DecorationImage(
                    image: NetworkImage(coverUrl!),
                    fit: BoxFit.cover,
                  )
                : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.7),
                blurRadius: 60,
                offset: const Offset(0, 24),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: (coverUrl == null || coverUrl!.isEmpty)
              ? Icon(Icons.music_note_rounded,
                  size: 64, color: t.text3)
              : null,
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

class _Lyrics extends StatelessWidget {
  const _Lyrics({
    required this.lines,
    required this.currentLine,
    required this.t,
  });

  final List<LyricLine> lines;
  final int currentLine;
  final DesignTokens t;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) {
      return Center(
        child: Text(
          '暂无歌词',
          style: TextStyle(fontSize: 16, color: t.text3),
        ),
      );
    }
    final offset = 160 - (currentLine.clamp(0, lines.length - 1)) * 48.0;
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
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 380),
            curve: DesignTokens.ease,
            transform: Matrix4.translationValues(0, offset, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                for (var i = 0; i < lines.length; i++)
                  _LyricRow(
                    text: lines[i].text,
                    translation: lines[i].translation,
                    active: i == currentLine,
                  ),
              ],
            ),
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
  });

  final String text;
  final String? translation;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Padding(
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
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: active ? t.text1 : t.text3,
              ),
              child: Text(translation!),
            ),
          ],
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.position,
    required this.duration,
    required this.isPlaying,
    required this.onPrev,
    required this.onNext,
    required this.onToggle,
    required this.t,
  });

  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToggle;
  final DesignTokens t;

  @override
  Widget build(BuildContext context) {
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(80, 18, 80, 32),
      child: Column(
        children: [
          Row(
            children: [
              _time(_fmt(position)),
              const SizedBox(width: 14),
              Expanded(child: AppProgressBar(value: progress, height: 5)),
              const SizedBox(width: 14),
              _time(_fmt(duration)),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () {},
                icon: Icon(Icons.shuffle_rounded, color: t.text1, size: 18),
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
                onPressed: () {},
                icon: Icon(Icons.repeat_rounded, color: t.text1, size: 18),
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
