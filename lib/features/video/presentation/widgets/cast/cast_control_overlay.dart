import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/video/domain/entities/cast_device.dart';
import 'package:my_nas/features/video/presentation/providers/cast_provider.dart';
import 'package:my_nas/features/video/presentation/theme/video_player_colors.dart';

/// 投屏控制覆盖层
/// 当投屏时显示在视频播放器上方，显示投屏状态和控制
class CastControlOverlay extends ConsumerWidget {
  const CastControlOverlay({
    super.key,
    this.onStopCasting,
    this.showVolumeControl = true,
  });

  /// 停止投屏回调
  final VoidCallback? onStopCasting;

  /// 是否显示音量控制
  final bool showVolumeControl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final castState = ref.watch(castProvider);
    final session = castState.session;

    if (session == null) return const SizedBox.shrink();

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: VideoPlayerColors.controlsGradient,
      ),
      child: SafeArea(
        child: Column(
          children: [
            // 顶部：设备信息
            _buildHeader(context, ref, session),

            // 中间：主控制区
            Expanded(
              child: _buildMainControls(context, ref, session),
            ),

            // 底部：进度条和时间
            _buildProgressBar(context, ref, session),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref, CastSession session) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            // 返回按钮
            IconButton(
              onPressed: () {
                ref.read(castProvider.notifier).stop();
                onStopCasting?.call();
              },
              icon: const Icon(Icons.arrow_back_rounded, color: VideoPlayerColors.primary),
            ),

            // 投屏图标
            const Icon(
              Icons.cast_connected,
              color: VideoPlayerColors.secondary,
              size: 18,
            ),
            const SizedBox(width: 8),

            // 设备和视频信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.videoTitle,
                    style: VideoPlayerColors.titleTextStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '投屏至 ${session.device.name}',
                    style: VideoPlayerColors.subtitleTextStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _buildMainControls(BuildContext context, WidgetRef ref, CastSession session) =>
      Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 播放状态指示
            _buildStatusIndicator(session),
            const SizedBox(height: 24),

            // 播放控制按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 后退 10 秒
                IconButton(
                  onPressed: () {
                    final newPosition = session.position - const Duration(seconds: 10);
                    ref.read(castProvider.notifier).seek(
                          newPosition < Duration.zero ? Duration.zero : newPosition,
                        );
                  },
                  iconSize: 48,
                  icon: const Icon(Icons.replay_10, color: VideoPlayerColors.primary),
                ),

                const SizedBox(width: 24),

                // 播放/暂停
                IconButton(
                  onPressed: () => ref.read(castProvider.notifier).togglePlayPause(),
                  iconSize: 64,
                  icon: Icon(
                    session.isPlaying ? Icons.pause_circle_rounded : Icons.play_circle_rounded,
                    color: VideoPlayerColors.primary,
                  ),
                ),

                const SizedBox(width: 24),

                // 前进 10 秒
                IconButton(
                  onPressed: () {
                    final newPosition = session.position + const Duration(seconds: 10);
                    ref.read(castProvider.notifier).seek(
                          newPosition > session.duration ? session.duration : newPosition,
                        );
                  },
                  iconSize: 48,
                  icon: const Icon(Icons.forward_10, color: VideoPlayerColors.primary),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // 音量控制
            if (showVolumeControl) _buildVolumeControl(context, ref, session),
          ],
        ),
      );

  Widget _buildStatusIndicator(CastSession session) {
    final (text, color) = switch (session.playbackState) {
      CastPlaybackState.loading => ('加载中...', VideoPlayerColors.secondary),
      CastPlaybackState.playing => ('播放中', VideoPlayerColors.primary),
      CastPlaybackState.paused => ('已暂停', VideoPlayerColors.secondary),
      CastPlaybackState.stopped => ('已停止', VideoPlayerColors.disabled),
      CastPlaybackState.error => (session.errorMessage ?? '播放出错', VideoPlayerColors.error),
      CastPlaybackState.idle => ('已连接', VideoPlayerColors.secondary),
    };

    return Text(
      text,
      style: TextStyle(color: color, fontSize: 14),
    );
  }

  Widget _buildVolumeControl(BuildContext context, WidgetRef ref, CastSession session) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        constraints: const BoxConstraints(maxWidth: 300),
        child: Row(
          children: [
            Icon(
              session.volume == 0
                  ? Icons.volume_off_rounded
                  : session.volume < 0.5
                      ? Icons.volume_down_rounded
                      : Icons.volume_up_rounded,
              color: VideoPlayerColors.primary,
              size: 20,
            ),
            Expanded(
              child: Slider(
                value: session.volume,
                onChanged: (value) => ref.read(castProvider.notifier).setVolume(value),
                activeColor: VideoPlayerColors.sliderActive,
                inactiveColor: VideoPlayerColors.sliderInactive,
              ),
            ),
          ],
        ),
      );

  Widget _buildProgressBar(BuildContext context, WidgetRef ref, CastSession session) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Text(
              _formatDuration(session.position),
              style: VideoPlayerColors.timeTextStyle,
            ),
            Expanded(
              child: SliderTheme(
                data: VideoPlayerColors.getSliderTheme(context),
                child: Slider(
                  value: session.duration.inMilliseconds > 0 ? session.progress.clamp(0.0, 1.0) : 0.0,
                  onChanged: session.duration.inMilliseconds > 0
                      ? (value) {
                          final position = Duration(
                            milliseconds: (value * session.duration.inMilliseconds).round(),
                          );
                          ref.read(castProvider.notifier).seek(position);
                        }
                      : null,
                ),
              ),
            ),
            Text(
              _formatDuration(session.duration),
              style: VideoPlayerColors.timeTextStyle,
            ),
          ],
        ),
      );

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

/// 迷你投屏控制条
/// 可以显示在视频列表等页面底部
class MiniCastControlBar extends ConsumerWidget {
  const MiniCastControlBar({
    super.key,
    this.onTap,
  });

  /// 点击回调
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final castState = ref.watch(castProvider);
    final session = castState.session;

    if (session == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: VideoPlayerColors.darkBackground,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // 动画波纹指示器
            _AnimatedCastIndicator(isPlaying: session.isPlaying),
            const SizedBox(width: 12),

            // 视频标题和设备
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    session.videoTitle,
                    style: VideoPlayerColors.titleTextStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${session.device.name} · ${session.device.protocol.label}',
                    style: VideoPlayerColors.subtitleTextStyle,
                  ),
                ],
              ),
            ),

            // 播放控制
            IconButton(
              onPressed: () => ref.read(castProvider.notifier).togglePlayPause(),
              icon: Icon(
                session.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: VideoPlayerColors.primary,
              ),
              visualDensity: VisualDensity.compact,
            ),

            // 停止按钮
            IconButton(
              onPressed: () => ref.read(castProvider.notifier).stop(),
              icon: const Icon(Icons.stop_rounded, color: VideoPlayerColors.primary),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

/// 投屏动画指示器
class _AnimatedCastIndicator extends StatefulWidget {
  const _AnimatedCastIndicator({required this.isPlaying});

  final bool isPlaying;

  @override
  State<_AnimatedCastIndicator> createState() => _AnimatedCastIndicatorState();
}

class _AnimatedCastIndicatorState extends State<_AnimatedCastIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    if (widget.isPlaying) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(_AnimatedCastIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: VideoPlayerColors.castIndicatorBg,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 波纹效果
              if (widget.isPlaying) ...[
                _buildRipple(0.0),
                _buildRipple(0.33),
                _buildRipple(0.66),
              ],
              // 图标
              const Icon(
                Icons.cast_connected,
                color: VideoPlayerColors.primary,
                size: 18,
              ),
            ],
          ),
        ),
      );

  Widget _buildRipple(double delay) {
    final animation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Interval(delay, delay + 0.5, curve: Curves.easeOut),
      ),
    );

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) => Container(
        width: 36 * animation.value,
        height: 36 * animation.value,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: VideoPlayerColors.primary.withValues(alpha: 1.0 - animation.value),
            width: 2,
          ),
        ),
      ),
    );
  }
}
