import 'dart:async';

import 'package:flutter/material.dart';
import 'package:my_nas/features/video/presentation/providers/video_player_provider.dart';

/// 手势类型
enum GestureType {
  none,
  brightness,
  volume,
  seek,
}

/// 手势控制器状态
class GestureControllerState {
  const GestureControllerState({
    this.gestureType = GestureType.none,
    this.brightness = 0.5,
    this.volume = 1.0,
    this.seekPosition = Duration.zero,
    this.seekDelta = Duration.zero,
    this.isVisible = false,
  });

  final GestureType gestureType;
  final double brightness;
  final double volume;
  final Duration seekPosition;
  final Duration seekDelta;
  final bool isVisible;

  GestureControllerState copyWith({
    GestureType? gestureType,
    double? brightness,
    double? volume,
    Duration? seekPosition,
    Duration? seekDelta,
    bool? isVisible,
  }) =>
      GestureControllerState(
        gestureType: gestureType ?? this.gestureType,
        brightness: brightness ?? this.brightness,
        volume: volume ?? this.volume,
        seekPosition: seekPosition ?? this.seekPosition,
        seekDelta: seekDelta ?? this.seekDelta,
        isVisible: isVisible ?? this.isVisible,
      );
}

/// 视频手势控制器
class VideoGestureController extends StatefulWidget {
  const VideoGestureController({
    required this.child,
    required this.playerState,
    required this.onVolumeChange,
    required this.onSeek,
    required this.onTap,
    required this.onDoubleTap,
    this.onBrightnessChange,
    this.enableGestures = true,
    super.key,
  });

  final Widget child;
  final VideoPlayerState playerState;
  final ValueChanged<double> onVolumeChange;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onTap;
  final void Function(TapDownDetails) onDoubleTap;
  final ValueChanged<double>? onBrightnessChange;
  final bool enableGestures;

  @override
  State<VideoGestureController> createState() => _VideoGestureControllerState();
}

class _VideoGestureControllerState extends State<VideoGestureController> {
  GestureControllerState _state = const GestureControllerState();
  Offset? _startPosition;
  double _startVolume = 1;
  double _startBrightness = 0.5;
  Duration _startSeekPosition = Duration.zero;

  Timer? _hideTimer;

  // 手势灵敏度
  static const double _verticalSensitivity = 0.01;
  static const double _horizontalSensitivity = 1; // 每像素对应的秒数

  @override
  void initState() {
    super.initState();
    _state = _state.copyWith(volume: widget.playerState.volume);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _state = _state.copyWith(isVisible: false, gestureType: GestureType.none);
        });
      }
    });
  }

  void _onPanStart(DragStartDetails details) {
    _startPosition = details.localPosition;
    _startVolume = widget.playerState.volume;
    _startBrightness = _state.brightness;
    _startSeekPosition = widget.playerState.position;
    _hideTimer?.cancel();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_startPosition == null) return;

    final screenSize = MediaQuery.of(context).size;
    final dx = details.localPosition.dx - _startPosition!.dx;
    final dy = details.localPosition.dy - _startPosition!.dy;

    // 判断手势类型
    if (_state.gestureType == GestureType.none) {
      if (dx.abs() > dy.abs() && dx.abs() > 20) {
        // 水平滑动 - 快进/快退
        setState(() {
          _state = _state.copyWith(
            gestureType: GestureType.seek,
            isVisible: true,
          );
        });
      } else if (dy.abs() > 20) {
        // 垂直滑动
        if (_startPosition!.dx < screenSize.width / 2) {
          // 左侧 - 亮度控制
          setState(() {
            _state = _state.copyWith(
              gestureType: GestureType.brightness,
              isVisible: true,
            );
          });
        } else {
          // 右侧 - 音量控制
          setState(() {
            _state = _state.copyWith(
              gestureType: GestureType.volume,
              isVisible: true,
            );
          });
        }
      }
    }

    // 根据手势类型更新状态
    switch (_state.gestureType) {
      case GestureType.brightness:
        final newBrightness = (_startBrightness - dy * _verticalSensitivity).clamp(0.0, 1.0);
        setState(() {
          _state = _state.copyWith(brightness: newBrightness);
        });
        widget.onBrightnessChange?.call(newBrightness);

      case GestureType.volume:
        final newVolume = (_startVolume - dy * _verticalSensitivity).clamp(0.0, 1.0);
        setState(() {
          _state = _state.copyWith(volume: newVolume);
        });
        widget.onVolumeChange(newVolume);

      case GestureType.seek:
        final seekSeconds = (dx * _horizontalSensitivity / 10).round();
        final seekDelta = Duration(seconds: seekSeconds);
        final newPosition = _startSeekPosition + seekDelta;
        final clampedPosition = Duration(
          milliseconds: newPosition.inMilliseconds.clamp(
            0,
            widget.playerState.duration.inMilliseconds,
          ),
        );
        setState(() {
          _state = _state.copyWith(
            seekPosition: clampedPosition,
            seekDelta: seekDelta,
          );
        });

      case GestureType.none:
        break;
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (_state.gestureType == GestureType.seek) {
      // 执行跳转
      widget.onSeek(_state.seekPosition);
    }

    _startPosition = null;
    _startHideTimer();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onDoubleTapDown: widget.onDoubleTap,
        onPanStart: widget.enableGestures ? _onPanStart : null,
        onPanUpdate: widget.enableGestures ? _onPanUpdate : null,
        onPanEnd: widget.enableGestures ? _onPanEnd : null,
        child: Stack(
          children: [
            widget.child,

            // 手势反馈层
            if (_state.isVisible) _buildGestureOverlay(),
          ],
        ),
      );

  Widget _buildGestureOverlay() {
    switch (_state.gestureType) {
      case GestureType.brightness:
        return _BrightnessOverlay(brightness: _state.brightness);
      case GestureType.volume:
        return _VolumeOverlay(volume: _state.volume);
      case GestureType.seek:
        return _SeekOverlay(
          position: _state.seekPosition,
          delta: _state.seekDelta,
          duration: widget.playerState.duration,
        );
      case GestureType.none:
        return const SizedBox.shrink();
    }
  }
}

/// 亮度调节覆盖层
class _BrightnessOverlay extends StatelessWidget {
  const _BrightnessOverlay({required this.brightness});

  final double brightness;

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                brightness > 0.7
                    ? Icons.brightness_high
                    : brightness > 0.3
                        ? Icons.brightness_medium
                        : Icons.brightness_low,
                color: Colors.white,
                size: 36,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: 120,
                child: _ProgressBar(value: brightness),
              ),
              const SizedBox(height: 8),
              Text(
                '${(brightness * 100).round()}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
}

/// 音量调节覆盖层
class _VolumeOverlay extends StatelessWidget {
  const _VolumeOverlay({required this.volume});

  final double volume;

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                volume == 0
                    ? Icons.volume_off_rounded
                    : volume < 0.3
                        ? Icons.volume_mute
                        : volume < 0.7
                            ? Icons.volume_down_rounded
                            : Icons.volume_up_rounded,
                color: Colors.white,
                size: 36,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: 120,
                child: _ProgressBar(value: volume),
              ),
              const SizedBox(height: 8),
              Text(
                '${(volume * 100).round()}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
}

/// 快进/快退覆盖层
class _SeekOverlay extends StatelessWidget {
  const _SeekOverlay({
    required this.position,
    required this.delta,
    required this.duration,
  });

  final Duration position;
  final Duration delta;
  final Duration duration;

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isForward = delta.inSeconds >= 0;
    final deltaSeconds = delta.inSeconds.abs();

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 图标和增量
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isForward ? Icons.fast_forward : Icons.fast_rewind,
                  color: Colors.white,
                  size: 32,
                ),
                const SizedBox(width: 8),
                Text(
                  '${isForward ? '+' : '-'}${deltaSeconds}s',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 当前位置 / 总时长
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatDuration(position),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  ' / ${_formatDuration(duration)}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 进度条
            SizedBox(
              width: 160,
              child: _ProgressBar(
                value: duration.inMilliseconds > 0 ? position.inMilliseconds / duration.inMilliseconds : 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 自定义进度条
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) => Container(
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(2),
        ),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: value.clamp(0.0, 1.0),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      );
}

/// 双击快进/快退动画覆盖层
class DoubleTapSeekOverlay extends StatefulWidget {
  const DoubleTapSeekOverlay({
    required this.isForward,
    required this.onComplete,
    this.seekInterval = 10,
    super.key,
  });

  final bool isForward;
  final VoidCallback onComplete;
  final int seekInterval;

  /// 根据秒数获取快退图标
  IconData get replayIcon => switch (seekInterval) {
        5 => Icons.replay_5,
        10 => Icons.replay_10,
        30 => Icons.replay_30,
        _ => Icons.replay,
      };

  /// 根据秒数获取快进图标
  IconData get forwardIcon => switch (seekInterval) {
        5 => Icons.forward_5,
        10 => Icons.forward_10,
        30 => Icons.forward_30,
        _ => Icons.forward,
      };

  /// 是否需要显示秒数标签
  bool get needsLabel => seekInterval != 5 && seekInterval != 10 && seekInterval != 30;

  @override
  State<DoubleTapSeekOverlay> createState() => _DoubleTapSeekOverlayState();
}

class _DoubleTapSeekOverlayState extends State<DoubleTapSeekOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _opacityAnimation = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _controller.forward().then((_) => widget.onComplete());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Opacity(
          opacity: _opacityAnimation.value,
          child: Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: widget.needsLabel
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          widget.isForward ? widget.forwardIcon : widget.replayIcon,
                          color: Colors.white,
                          size: 32,
                        ),
                        Text(
                          '${widget.seekInterval}s',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    )
                  : Icon(
                      widget.isForward ? widget.forwardIcon : widget.replayIcon,
                      color: Colors.white,
                      size: 40,
                    ),
            ),
          ),
        ),
      );
}
