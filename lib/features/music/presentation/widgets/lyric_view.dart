import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/music/data/services/lyric_service.dart';
import 'package:my_nas/features/music/presentation/providers/lyric_provider.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';
import 'package:my_nas/features/music/presentation/providers/music_settings_provider.dart';
import 'package:my_nas/features/music/presentation/widgets/karaoke_line_widget.dart';

/// Spotify 风格的歌词视图 - 现代化设计
/// 参考主流音乐APP的歌词展示方式：
/// - 当前歌词始终居中显示
/// - 平滑滚动动画
/// - 支持手动滚动后暂停自动滚动
class LyricView extends ConsumerStatefulWidget {
  const LyricView({
    super.key,
    this.onTap,
    this.showFullScreen = false,
  });

  /// 点击歌词回调
  final VoidCallback? onTap;

  /// 是否全屏模式
  final bool showFullScreen;

  @override
  ConsumerState<LyricView> createState() => _LyricViewState();
}

class _LyricViewState extends ConsumerState<LyricView>
    with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _listKey = GlobalKey();

  bool _userScrolling = false;
  DateTime? _lastUserScrollTime;

  // 双指缩放状态：基准值 = pinch 开始时的已存 scale；transient = 实时倍率
  double _pinchBaseScale = 1.0;
  double _pinchTransient = 1.0;
  bool _isPinching = false;

  late AnimationController _pulseController;
  Ticker? _scrollTicker;

  // 每行歌词的 GlobalKey，用于精确计算位置
  final Map<int, GlobalKey> _lineKeys = {};

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _scrollTicker = createTicker(_onScrollTick)..start();
  }

  @override
  void dispose() {
    _scrollTicker?.dispose();
    _scrollController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  /// 获取指定行的 key
  GlobalKey _getKeyForLine(int index) =>
      _lineKeys.putIfAbsent(index, GlobalKey.new);

  /// 估算行高（含 padding）
  double get _estimatedLineHeight => widget.showFullScreen ? 56.0 : 44.0;

  /// 60fps Ticker：基于当前播放位置在「当前行 → 下一行」之间线性插值滚动偏移，
  /// 实现连续平滑滚动而非按行跳变。
  void _onScrollTick(Duration _) {
    if (!_scrollController.hasClients) return;
    if (_userScrolling || _isPinching) return;
    if (_lastUserScrollTime != null) {
      final elapsed = DateTime.now().difference(_lastUserScrollTime!);
      if (elapsed.inSeconds < 3) return;
    }

    final lyricData = ref.read(currentLyricProvider).lyricData;
    if (lyricData.isEmpty) return;

    final position = ref.read(musicPlayerControllerProvider).position;
    final lines = lyricData.lines;
    final idx = lyricData.getCurrentLineIndex(position);
    if (idx < 0) return;

    // 行内进度 0..1：基于当前行 time 到下一行 time（或 endTime） 的占比
    double progress = 0;
    final cur = lines[idx];
    Duration? rangeEnd;
    if (idx + 1 < lines.length) {
      rangeEnd = lines[idx + 1].time;
    } else if (cur.endTime != null) {
      rangeEnd = cur.endTime;
    }
    if (rangeEnd != null && rangeEnd > cur.time) {
      final span = (rangeEnd - cur.time).inMicroseconds;
      final passed = (position - cur.time).inMicroseconds.clamp(0, span);
      progress = passed / span;
    }

    final lh = _estimatedLineHeight;
    final curOffset = idx * lh;
    final nextOffset = (idx + 1) * lh;
    final targetOffset = curOffset + (nextOffset - curOffset) * progress;

    final clamped = targetOffset.clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );

    // 用 jumpTo 才能跟上 60fps；与现有 offset 差距过小时跳过避免闪烁
    if ((_scrollController.offset - clamped).abs() < 0.5) return;
    _scrollController.jumpTo(clamped);
  }

  void _onScaleStart(ScaleStartDetails details) {
    // 仅响应 2 指及以上的捏合，单指交给 ListView 滚动
    if (details.pointerCount < 2) return;
    _pinchBaseScale =
        ref.read(musicSettingsProvider.select((s) => s.lyricsFontScale));
    _pinchTransient = 1.0;
    _isPinching = true;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (!_isPinching) return;
    if (details.pointerCount < 2) return;
    setState(() {
      _pinchTransient = details.scale;
    });
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (!_isPinching) return;
    _isPinching = false;
    final finalScale = (_pinchBaseScale * _pinchTransient).clamp(
      MusicSettings.minLyricsFontScale,
      MusicSettings.maxLyricsFontScale,
    );
    _pinchTransient = 1.0;
    setState(() {});
    AppError.fireAndForget(
      ref
          .read(musicSettingsProvider.notifier)
          .setLyricsFontScale(finalScale),
      action: 'lyricView.persistFontScale',
    );
  }

  @override
  Widget build(BuildContext context) {
    final lyricState = ref.watch(currentLyricProvider);
    final playerState = ref.watch(musicPlayerControllerProvider);
    final savedScale = ref.watch(
      musicSettingsProvider.select((s) => s.lyricsFontScale),
    );
    final effectiveScale = (_isPinching
            ? _pinchBaseScale * _pinchTransient
            : savedScale)
        .clamp(
      MusicSettings.minLyricsFontScale,
      MusicSettings.maxLyricsFontScale,
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (lyricState.isLoading) {
      return _buildLoadingState(isDark);
    }

    if (lyricState.lyricData.isEmpty) {
      return _buildNoLyric(isDark);
    }

    final lyrics = lyricState.lyricData;
    final currentIndex = lyrics.getCurrentLineIndex(playerState.position);

    // 滚动由 _onScrollTick 持续插值驱动，无需在 build 中显式 scrollTo

    // 计算视口高度用于 padding
    // 顶部 padding 较小，让当前歌词显示在屏幕上方约 1/3 处
    // 底部 padding 较大，为后续歌词预留滚动空间
    final screenHeight = MediaQuery.of(context).size.height;
    final topPadding = screenHeight * 0.28; // 28% 顶部空白
    final bottomPadding = screenHeight * 0.5; // 50% 底部空白

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is UserScrollNotification) {
          // 用户开始手动滚动
          _userScrolling = true;
          _lastUserScrollTime = DateTime.now();
        } else if (notification is ScrollEndNotification) {
          // 滚动结束后，延迟恢复自动滚动
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              setState(() {
                _userScrolling = false;
              });
            }
          });
        }
        return false;
      },
      child: GestureDetector(
        // 整个区域可点击返回唱片视图
        onTap: widget.onTap,
        // 双指捏合调节歌词字号
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onScaleEnd: _onScaleEnd,
        behavior: HitTestBehavior.translucent,
        child: ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.white,
              Colors.white,
              Colors.transparent,
            ],
            stops: const [0.0, 0.15, 0.85, 1.0],
          ).createShader(bounds),
          blendMode: BlendMode.dstIn,
          child: ListView.builder(
            key: _listKey,
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.only(
              top: topPadding,
              bottom: bottomPadding,
              left: widget.showFullScreen ? 32 : 24,
              right: widget.showFullScreen ? 32 : 24,
            ),
            itemCount: lyrics.lines.length,
            itemBuilder: (context, index) {
              final line = lyrics.lines[index];
              final isCurrent = index == currentIndex;
              final isPast = index < currentIndex;

              return _LyricLineWidget(
                key: _getKeyForLine(index),
                line: line,
                isCurrent: isCurrent,
                isPast: isPast,
                isDark: isDark,
                showFullScreen: widget.showFullScreen,
                fontScale: effectiveScale,
                onTap: () {
                  // 点击歌词跳转到对应位置（而不是切换视图）
                  ref.read(musicPlayerControllerProvider.notifier).seek(line.time);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState(bool isDark) => Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 脉冲动画
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) => Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(
                  alpha: 0.1 + (_pulseController.value * 0.1),
                ),
              ),
              child: Center(
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withValues(
                      alpha: 0.2 + (_pulseController.value * 0.1),
                    ),
                  ),
                  child: Icon(
                    Icons.lyrics_rounded,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            context.l10n.lyricViewLoadingText,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white60 : Colors.black45,
            ),
          ),
        ],
      ),
    );

  Widget _buildNoLyric(bool isDark) => GestureDetector(
      onTap: widget.onTap, // 点击切换回唱片视图
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 装饰性音符
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.primary.withValues(alpha: 0.15),
                    AppColors.secondary.withValues(alpha: 0.1),
                  ],
                ),
              ),
              child: Icon(
                Icons.music_note_rounded,
                size: 48,
                color: AppColors.primary.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              context.l10n.lyricContentEmptyHint,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.lyricViewHintClickToBack,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
          ],
        ),
      ),
    );
}

class _LyricLineWidget extends StatelessWidget {
  const _LyricLineWidget({
    required this.line,
    required this.isCurrent,
    required this.isPast,
    required this.isDark,
    required this.showFullScreen,
    required this.fontScale,
    required this.onTap,
    super.key,
  });

  final LyricLine line;
  final bool isCurrent;
  final bool isPast;
  final bool isDark;
  final bool showFullScreen;
  final double fontScale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 根据状态确定颜色和大小
    Color textColor;
    double fontSize;
    FontWeight fontWeight;

    if (isCurrent) {
      textColor = isDark ? Colors.white : Colors.black87;
      fontSize = showFullScreen ? 26 : 20;
      fontWeight = FontWeight.bold;
    } else if (isPast) {
      textColor = isDark
          ? Colors.white.withValues(alpha: 0.35)
          : Colors.black.withValues(alpha: 0.3);
      fontSize = showFullScreen ? 18 : 16;
      fontWeight = FontWeight.normal;
    } else {
      textColor = isDark
          ? Colors.white.withValues(alpha: 0.5)
          : Colors.black.withValues(alpha: 0.4);
      fontSize = showFullScreen ? 18 : 16;
      fontWeight = FontWeight.normal;
    }

    fontSize *= fontScale;

    // 当前行 + 字级歌词：走 Karaoke 渲染器
    final isWordLevel = isCurrent && line.isWordLevel;

    final mainBody = isWordLevel
        ? KaraokeLineWidget(
            line: line,
            fontSize: fontSize,
            fontWeight: fontWeight,
            activeColor: textColor,
            inactiveColor: textColor.withValues(alpha: 0.35),
          )
        : AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: fontWeight,
              color: textColor,
              height: 1.4,
            ),
            child: Text(
              line.text,
              textAlign: TextAlign.center,
            ),
          );

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(
          vertical: showFullScreen ? 14 : 10,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            mainBody,
            if (line.hasTranslation) ...[
              const SizedBox(height: 4),
              Text(
                line.translation!,
                style: TextStyle(
                  fontSize: fontSize * 0.72,
                  fontWeight: FontWeight.normal,
                  color: textColor.withValues(alpha: 0.65),
                  height: 1.3,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 紧凑型歌词显示（用于播放页底部）- 现代化设计
class CompactLyricView extends ConsumerWidget {
  const CompactLyricView({
    super.key,
    this.onTap,
  });

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lyricState = ref.watch(currentLyricProvider);
    final playerState = ref.watch(musicPlayerControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (lyricState.lyricData.isEmpty) {
      return const SizedBox.shrink();
    }

    final currentLine = lyricState.lyricData.getCurrentLine(playerState.position);
    final nextLineIndex = lyricState.lyricData.getCurrentLineIndex(playerState.position) + 1;
    final nextLine = nextLineIndex < lyricState.lyricData.lines.length
        ? lyricState.lyricData.lines[nextLineIndex]
        : null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 当前歌词
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.3),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  )),
                  child: child,
                ),
              ),
              child: Text(
                currentLine?.text ?? '',
                key: ValueKey(currentLine?.time.inMilliseconds ?? 0),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // 下一句歌词预览
            if (nextLine != null) ...[
              const SizedBox(height: 6),
              Text(
                nextLine.text,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.4)
                      : Colors.black.withValues(alpha: 0.35),
                  height: 1.3,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 迷你歌词显示（用于迷你播放器等小空间）
class MiniLyricView extends ConsumerWidget {
  const MiniLyricView({
    super.key,
    this.style,
  });

  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lyricState = ref.watch(currentLyricProvider);
    final playerState = ref.watch(musicPlayerControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (lyricState.lyricData.isEmpty) {
      return const SizedBox.shrink();
    }

    final currentLine = lyricState.lyricData.getCurrentLine(playerState.position);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: Text(
        currentLine?.text ?? '',
        key: ValueKey(currentLine?.time.inMilliseconds ?? 0),
        style: style ??
            TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white60 : Colors.black45,
            ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
