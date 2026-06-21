import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:my_nas/core/utils/platform_capabilities.dart';

/// 悬停效果类型
enum HoverEffect {
  /// 无效果
  none,

  /// 缩放效果
  scale,

  /// 高亮效果（背景变亮/变暗）
  highlight,

  /// 阴影效果
  shadow,

  /// 边框效果
  border,

  /// 组合效果（缩放 + 阴影）
  combined,
}

/// 鼠标光标类型
enum HoverCursor {
  /// 默认光标
  normal,

  /// 手型光标（可点击）
  pointer,

  /// 文本选择光标
  text,

  /// 拖动光标
  grab,

  /// 正在拖动光标
  grabbing,

  /// 禁止光标
  forbidden,

  /// 缩放光标
  resize,
}

/// 可悬停组件
///
/// 为子组件添加桌面端悬停效果，移动端不显示悬停效果
/// 支持多种悬停效果和鼠标光标定制
///
/// 示例：
/// ```dart
/// HoverableWidget(
///   effect: HoverEffect.combined,
///   cursor: HoverCursor.pointer,
///   onTap: () => print('clicked'),
///   child: Card(...),
/// )
/// ```
class HoverableWidget extends StatefulWidget {
  const HoverableWidget({
    super.key,
    required this.child,
    this.effect = HoverEffect.combined,
    this.cursor = HoverCursor.pointer,
    this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.onHover,
    this.enabled = true,
    this.scaleFactor = 1.02,
    this.shadowElevation = 8.0,
    this.highlightColor,
    this.borderColor,
    this.borderRadius,
    this.animationDuration = const Duration(milliseconds: 150),
    this.animationCurve = Curves.easeOut,
    this.showOverlay = false,
    this.overlayBuilder,
  });

  /// 子组件
  final Widget child;

  /// 悬停效果类型
  final HoverEffect effect;

  /// 鼠标光标类型
  final HoverCursor cursor;

  /// 点击回调
  final VoidCallback? onTap;

  /// 双击回调
  final VoidCallback? onDoubleTap;

  /// 长按回调（移动端）/ 右键回调（桌面端）
  final VoidCallback? onLongPress;

  /// 右键回调（仅桌面端）
  final VoidCallback? onSecondaryTap;

  /// 悬停状态变化回调
  final ValueChanged<bool>? onHover;

  /// 是否启用悬停效果
  final bool enabled;

  /// 缩放因子（仅 scale 和 combined 效果）
  final double scaleFactor;

  /// 阴影高度（仅 shadow 和 combined 效果）
  final double shadowElevation;

  /// 高亮颜色（仅 highlight 效果）
  final Color? highlightColor;

  /// 边框颜色（仅 border 效果）
  final Color? borderColor;

  /// 边框圆角
  final BorderRadius? borderRadius;

  /// 动画时长
  final Duration animationDuration;

  /// 动画曲线
  final Curve animationCurve;

  /// 是否在悬停时显示覆盖层
  final bool showOverlay;

  /// 覆盖层构建器
  final Widget Function(BuildContext context, bool isHovering)? overlayBuilder;

  @override
  State<HoverableWidget> createState() => _HoverableWidgetState();
}

class _HoverableWidgetState extends State<HoverableWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _shadowAnimation;
  late Animation<double> _highlightAnimation;
  late Animation<double> _borderAnimation;

  bool _isHovering = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.animationDuration,
      vsync: this,
    );

    _setupAnimations();
  }

  void _setupAnimations() {
    final curved = CurvedAnimation(
      parent: _controller,
      curve: widget.animationCurve,
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: widget.scaleFactor,
    ).animate(curved);

    _shadowAnimation = Tween<double>(
      begin: 0.0,
      end: widget.shadowElevation,
    ).animate(curved);

    _highlightAnimation = Tween<double>(
      begin: 0.0,
      end: 0.08,
    ).animate(curved);

    _borderAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(curved);
  }

  @override
  void didUpdateWidget(HoverableWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animationDuration != widget.animationDuration ||
        oldWidget.animationCurve != widget.animationCurve ||
        oldWidget.scaleFactor != widget.scaleFactor ||
        oldWidget.shadowElevation != widget.shadowElevation) {
      _controller.duration = widget.animationDuration;
      _setupAnimations();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onEnter(PointerEnterEvent event) {
    if (!widget.enabled) return;
    setState(() => _isHovering = true);
    _controller.forward();
    widget.onHover?.call(true);
  }

  void _onExit(PointerExitEvent event) {
    if (!widget.enabled) return;
    setState(() => _isHovering = false);
    _controller.reverse();
    widget.onHover?.call(false);
  }

  MouseCursor _getCursor() {
    if (!widget.enabled) return SystemMouseCursors.basic;

    switch (widget.cursor) {
      case HoverCursor.normal:
        return SystemMouseCursors.basic;
      case HoverCursor.pointer:
        return SystemMouseCursors.click;
      case HoverCursor.text:
        return SystemMouseCursors.text;
      case HoverCursor.grab:
        return SystemMouseCursors.grab;
      case HoverCursor.grabbing:
        return SystemMouseCursors.grabbing;
      case HoverCursor.forbidden:
        return SystemMouseCursors.forbidden;
      case HoverCursor.resize:
        return SystemMouseCursors.resizeColumn;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = PlatformCapabilities.isDesktop;

    // 移动端直接返回 GestureDetector
    if (!isDesktop) {
      return GestureDetector(
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        onLongPress: widget.onLongPress,
        child: widget.child,
      );
    }

    // 桌面端添加悬停效果
    return MouseRegion(
      cursor: _getCursor(),
      onEnter: _onEnter,
      onExit: _onExit,
      child: GestureDetector(
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        onLongPress: widget.onLongPress,
        onSecondaryTap: widget.onSecondaryTap ?? widget.onLongPress,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) => _buildWithEffect(context, child!),
          child: widget.child,
        ),
      ),
    );
  }

  Widget _buildWithEffect(BuildContext context, Widget child) {
    if (!widget.enabled || widget.effect == HoverEffect.none) {
      return _wrapWithOverlay(child);
    }

    var result = child;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    switch (widget.effect) {
      case HoverEffect.none:
        break;

      case HoverEffect.scale:
        result = Transform.scale(
          scale: _scaleAnimation.value,
          child: result,
        );

      case HoverEffect.highlight:
        final highlightColor = widget.highlightColor ??
            (isDark ? Colors.white : Colors.black);
        result = DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            color: highlightColor.withValues(alpha: _highlightAnimation.value),
          ),
          child: result,
        );

      case HoverEffect.shadow:
        result = DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1 + _shadowAnimation.value * 0.015),
                blurRadius: _shadowAnimation.value,
                offset: Offset(0, _shadowAnimation.value * 0.5),
              ),
            ],
          ),
          child: result,
        );

      case HoverEffect.border:
        final borderColor = widget.borderColor ??
            Theme.of(context).colorScheme.primary;
        result = DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            border: Border.all(
              color: borderColor.withValues(alpha: _borderAnimation.value),
              width: 2,
            ),
          ),
          child: result,
        );

      case HoverEffect.combined:
        result = Transform.scale(
          scale: _scaleAnimation.value,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1 + _shadowAnimation.value * 0.012),
                  blurRadius: 4 + _shadowAnimation.value,
                  offset: Offset(0, 2 + _shadowAnimation.value * 0.4),
                ),
              ],
            ),
            child: result,
          ),
        );
    }

    return _wrapWithOverlay(result);
  }

  Widget _wrapWithOverlay(Widget child) {
    if (!widget.showOverlay || widget.overlayBuilder == null) {
      return child;
    }

    return Stack(
      children: [
        child,
        Positioned.fill(
          child: AnimatedOpacity(
            opacity: _isHovering ? 1.0 : 0.0,
            duration: widget.animationDuration,
            child: widget.overlayBuilder!(context, _isHovering),
          ),
        ),
      ],
    );
  }
}

/// 悬停高亮包装器
///
/// 简化版的悬停效果，仅添加背景高亮
class HoverHighlight extends StatefulWidget {
  const HoverHighlight({
    super.key,
    required this.child,
    this.onTap,
    this.enabled = true,
    this.borderRadius,
    this.hoverColor,
    this.splashColor,
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool enabled;
  final BorderRadius? borderRadius;
  final Color? hoverColor;
  final Color? splashColor;

  @override
  State<HoverHighlight> createState() => _HoverHighlightState();
}

class _HoverHighlightState extends State<HoverHighlight> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hoverColor = widget.hoverColor ??
        (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.04));

    return MouseRegion(
      cursor: widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: widget.enabled ? (_) => setState(() => _isHovering = true) : null,
      onExit: widget.enabled ? (_) => setState(() => _isHovering = false) : null,
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            color: _isHovering ? hoverColor : Colors.transparent,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// 悬停缩放包装器
///
/// 简化版的悬停效果，仅添加缩放
class HoverScale extends StatefulWidget {
  const HoverScale({
    super.key,
    required this.child,
    this.onTap,
    this.enabled = true,
    this.scale = 1.03,
    this.duration = const Duration(milliseconds: 150),
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool enabled;
  final double scale;
  final Duration duration;

  @override
  State<HoverScale> createState() => _HoverScaleState();
}

class _HoverScaleState extends State<HoverScale> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final isDesktop = PlatformCapabilities.isDesktop;

    if (!isDesktop) {
      return GestureDetector(
        onTap: widget.onTap,
        child: widget.child,
      );
    }

    return MouseRegion(
      cursor: widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: widget.enabled ? (_) => setState(() => _isHovering = true) : null,
      onExit: widget.enabled ? (_) => setState(() => _isHovering = false) : null,
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        child: AnimatedScale(
          scale: _isHovering && widget.enabled ? widget.scale : 1.0,
          duration: widget.duration,
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}

/// 悬停卡片组件
///
/// 带有完整悬停效果的卡片组件，适用于网格布局中的卡片
class HoverCard extends StatefulWidget {
  const HoverCard({
    super.key,
    required this.child,
    this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.enabled = true,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.elevation = 2.0,
    this.hoverElevation = 8.0,
    this.scale = 1.02,
    this.duration = const Duration(milliseconds: 150),
    this.showOverlayOnHover = false,
    this.overlayBuilder,
    this.backgroundColor,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTap;
  final bool enabled;
  final BorderRadius borderRadius;
  final double elevation;
  final double hoverElevation;
  final double scale;
  final Duration duration;
  final bool showOverlayOnHover;
  final Widget Function(BuildContext context)? overlayBuilder;
  final Color? backgroundColor;

  @override
  State<HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<HoverCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _elevationAnimation;

  bool _isHovering = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );

    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: widget.scale,
    ).animate(curved);

    _elevationAnimation = Tween<double>(
      begin: widget.elevation,
      end: widget.hoverElevation,
    ).animate(curved);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onEnter(PointerEnterEvent event) {
    if (!widget.enabled) return;
    setState(() => _isHovering = true);
    _controller.forward();
  }

  void _onExit(PointerExitEvent event) {
    if (!widget.enabled) return;
    setState(() => _isHovering = false);
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = PlatformCapabilities.isDesktop;
    final cs = Theme.of(context).colorScheme;

    final backgroundColor = widget.backgroundColor ?? cs.surface;

    Widget card = AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Transform.scale(
        scale: isDesktop ? _scaleAnimation.value : 1.0,
        child: Material(
          color: backgroundColor,
          borderRadius: widget.borderRadius,
          elevation: isDesktop ? _elevationAnimation.value : widget.elevation,
          shadowColor: Colors.black.withValues(alpha: 0.2),
          child: ClipRRect(
            borderRadius: widget.borderRadius,
            child: Stack(
              children: [
                child!,
                if (widget.showOverlayOnHover && widget.overlayBuilder != null)
                  Positioned.fill(
                    child: AnimatedOpacity(
                      opacity: _isHovering ? 1.0 : 0.0,
                      duration: widget.duration,
                      child: widget.overlayBuilder!(context),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      child: widget.child,
    );

    if (isDesktop) {
      card = MouseRegion(
        cursor: widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: _onEnter,
        onExit: _onExit,
        child: card,
      );
    }

    return GestureDetector(
      onTap: widget.onTap,
      onDoubleTap: widget.onDoubleTap,
      onLongPress: widget.onLongPress,
      onSecondaryTap: isDesktop ? (widget.onSecondaryTap ?? widget.onLongPress) : null,
      child: card,
    );
  }
}
