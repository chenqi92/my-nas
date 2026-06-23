import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:my_nas/core/utils/debug_log.dart';

/// 翻页效果模式
enum PageFlipMode {
  /// 仿真翻页（书页卷曲效果）
  simulation,

  /// 覆盖翻页
  cover,
}

/// 翻页方向
enum FlipDirection {
  /// 向左翻（下一页）
  forward,

  /// 向右翻（上一页）
  backward,
}

/// 页面翻转效果 Widget
///
/// 使用简单的滑动动画实现翻页效果，无延迟响应
class PageFlipEffect extends StatefulWidget {
  const PageFlipEffect({
    required this.child,
    required this.onNextPage,
    required this.onPrevPage,
    this.mode = PageFlipMode.simulation,
    this.enabled = true,
    this.animationDuration = const Duration(milliseconds: 300),
    this.dragThreshold = 0.2,
    this.onTap,
    this.backgroundColor = Colors.white,
    super.key,
  });

  /// 当前页面内容
  final Widget child;

  /// 下一页回调
  final Future<void> Function() onNextPage;

  /// 上一页回调
  final Future<void> Function() onPrevPage;

  /// 翻页模式
  final PageFlipMode mode;

  /// 是否启用翻页效果
  final bool enabled;

  /// 动画时长
  final Duration animationDuration;

  /// 拖动阈值（超过此比例触发翻页）
  final double dragThreshold;

  /// 点击事件回调
  final void Function(TapUpDetails details)? onTap;

  /// 背景颜色
  final Color backgroundColor;

  @override
  State<PageFlipEffect> createState() => _PageFlipEffectState();
}

class _PageFlipEffectState extends State<PageFlipEffect>
    with SingleTickerProviderStateMixin {
  /// 动画控制器
  late AnimationController _controller;

  /// 翻页方向
  FlipDirection? _direction;

  /// 是否正在动画中
  bool _isAnimating = false;

  /// 拖动起始位置
  Offset? _dragStart;

  /// 当前拖动进度 (0.0 - 1.0)
  double _dragProgress = 0.0;

  /// 动画开始时的进度
  double _animationStartProgress = 0.0;

  /// 是否应该完成翻页
  bool _shouldComplete = false;

  // 点击检测
  Offset? _tapDownPosition;
  DateTime? _tapDownTime;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    )..addListener(_onAnimationUpdate);
  }

  void _onAnimationUpdate() {
    if (!mounted) return;

    final t = Curves.easeOutCubic.transform(_controller.value);

    if (_shouldComplete) {
      _dragProgress = _animationStartProgress + (1.0 - _animationStartProgress) * t;
    } else {
      _dragProgress = _animationStartProgress * (1.0 - t);
    }

    // 动画完成
    if (_controller.value >= 1.0) {
      _onAnimationComplete();
    } else {
      setState(() {});
    }
  }

  Future<void> _onAnimationComplete() async {
    final direction = _direction;
    final shouldComplete = _shouldComplete;

    _isAnimating = false;

    if (shouldComplete && direction != null) {
      if (kDebugMode) {
        debugLog('[PageFlip] Animation complete, triggering ${direction == FlipDirection.forward ? 'nextPage' : 'prevPage'}');
      }
      // 先重置状态
      _reset();
      // 然后触发回调
      if (direction == FlipDirection.forward) {
        await widget.onNextPage();
      } else {
        await widget.onPrevPage();
      }
    } else {
      if (kDebugMode) {
        debugLog('[PageFlip] Animation complete, cancelled');
      }
      _reset();
    }
  }

  void _reset() {
    _direction = null;
    _dragStart = null;
    _dragProgress = 0.0;
    _shouldComplete = false;
    _controller.reset();
    if (mounted) setState(() {});
  }

  void _onDragStart(DragStartDetails details) {
    if (!widget.enabled || _isAnimating) return;
    _dragStart = details.localPosition;
    if (kDebugMode) {
      debugLog('[PageFlip] onDragStart: ${details.localPosition}');
    }
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!widget.enabled || _isAnimating || _dragStart == null) return;

    final size = MediaQuery.of(context).size;
    final dragDelta = details.localPosition.dx - _dragStart!.dx;
    final dragRatio = dragDelta.abs() / size.width;

    // 确定翻页方向
    if (_direction == null && dragRatio > 0.02) {
      _direction = dragDelta < 0 ? FlipDirection.forward : FlipDirection.backward;
    }

    if (_direction != null) {
      setState(() {
        _dragProgress = dragRatio.clamp(0.0, 1.0);
      });
    }
  }

  void _onDragEnd(DragEndDetails details) {
    if (!widget.enabled || _direction == null) {
      _reset();
      return;
    }

    _shouldComplete = _dragProgress > widget.dragThreshold;
    _isAnimating = true;
    _animationStartProgress = _dragProgress;

    if (kDebugMode) {
      debugLog('[PageFlip] onDragEnd: direction=$_direction, progress=$_dragProgress, shouldComplete=$_shouldComplete');
    }

    _controller.forward(from: 0);

    if (_shouldComplete) {
      HapticFeedback.lightImpact();
    }
  }

  void _onDragCancel() {
    if (_direction != null && !_isAnimating) {
      _isAnimating = true;
      _animationStartProgress = _dragProgress;
      _shouldComplete = false;
      _controller.forward(from: 0);
    } else {
      _reset();
    }
  }

  /// 触发点击翻页
  void _triggerTapFlip(FlipDirection direction) {
    if (_isAnimating || _direction != null) return;

    if (kDebugMode) {
      debugLog('[PageFlip] triggerTapFlip: $direction');
    }

    _direction = direction;
    _shouldComplete = true;
    _isAnimating = true;
    _animationStartProgress = 0.0;
    _dragProgress = 0.0;

    HapticFeedback.lightImpact();
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return GestureDetector(
        onTapUp: widget.onTap,
        child: widget.child,
      );
    }

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _tapDownPosition = event.localPosition;
        _tapDownTime = DateTime.now();
      },
      onPointerUp: (event) {
        if (_direction != null || _isAnimating) {
          _tapDownPosition = null;
          _tapDownTime = null;
          return;
        }

        if (_tapDownPosition != null && _tapDownTime != null) {
          final distance = (event.localPosition - _tapDownPosition!).distance;
          final duration = DateTime.now().difference(_tapDownTime!);

          if (distance < 20 && duration.inMilliseconds < 300) {
            final screenWidth = MediaQuery.of(context).size.width;
            final tapX = event.localPosition.dx;
            final ratio = tapX / screenWidth;

            if (ratio < 0.25) {
              _triggerTapFlip(FlipDirection.backward);
            } else if (ratio > 0.75) {
              _triggerTapFlip(FlipDirection.forward);
            } else {
              widget.onTap?.call(TapUpDetails(
                kind: event.kind,
                localPosition: event.localPosition,
                globalPosition: event.position,
              ));
            }
          }
        }
        _tapDownPosition = null;
        _tapDownTime = null;
      },
      onPointerCancel: (event) {
        _tapDownPosition = null;
        _tapDownTime = null;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: _onDragStart,
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        onHorizontalDragCancel: _onDragCancel,
        child: Stack(
          children: [
            // 当前页面内容
            widget.child,

            // 翻页动画层
            if (_direction != null && _dragProgress > 0)
              Positioned.fill(
                child: _buildFlipOverlay(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlipOverlay() {
    final size = MediaQuery.of(context).size;
    final isForward = _direction == FlipDirection.forward;

    if (widget.mode == PageFlipMode.simulation) {
      return _buildSimulationOverlay(size, isForward);
    }
    return _buildCoverOverlay(size, isForward);
  }

  /// 仿真翻页效果 - 使用渐变模拟页面翻起的阴影
  Widget _buildSimulationOverlay(Size size, bool isForward) {
    // 计算翻页边缘位置
    final edgePosition = isForward
        ? size.width * (1.0 - _dragProgress)
        : size.width * _dragProgress;

    return Stack(
      children: [
        // 翻起页面的阴影（模拟页面翻起效果）
        Positioned(
          left: isForward ? edgePosition - 60 : null,
          right: isForward ? null : size.width - edgePosition - 60,
          top: 0,
          bottom: 0,
          width: 120,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: isForward ? Alignment.centerRight : Alignment.centerLeft,
                end: isForward ? Alignment.centerLeft : Alignment.centerRight,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.15 * _dragProgress),
                  Colors.black.withValues(alpha: 0.3 * _dragProgress),
                  Colors.black.withValues(alpha: 0.15 * _dragProgress),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
              ),
            ),
          ),
        ),

        // 翻过区域的遮罩（模拟下一页露出）
        Positioned(
          left: isForward ? edgePosition : 0,
          right: isForward ? 0 : size.width - edgePosition,
          top: 0,
          bottom: 0,
          child: ColoredBox(
            color: widget.backgroundColor.withValues(alpha: 0.95),
          ),
        ),
      ],
    );
  }

  /// 覆盖翻页效果 - 简单的滑动遮罩
  Widget _buildCoverOverlay(Size size, bool isForward) {
    final offset = isForward
        ? size.width * (1.0 - _dragProgress)
        : -size.width * (1.0 - _dragProgress);

    return Transform.translate(
      offset: Offset(offset, 0),
      child: ColoredBox(
        color: widget.backgroundColor,
        child: Stack(
          children: [
            // 边缘阴影
            Positioned(
              left: isForward ? 0 : null,
              right: isForward ? null : 0,
              top: 0,
              bottom: 0,
              width: 20,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: isForward ? Alignment.centerLeft : Alignment.centerRight,
                    end: isForward ? Alignment.centerRight : Alignment.centerLeft,
                    colors: [
                      Colors.black.withValues(alpha: 0.2),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
