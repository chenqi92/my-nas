import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// TV 可聚焦包装器：将任意 widget 转换为 D-pad 可导航的卡片。
///
/// - **焦点高亮**：获得焦点时显示 1.05 倍缩放 + 2px 白边框，未聚焦时保持原尺寸。
/// - **SELECT 激活**：D-pad 中键（SELECT/OK）和回车键触发 [onPressed]。
/// - **自动跳转**：如果外层包装了 [TvFocusScroll]，则焦点时自动滚动到视口。
///
/// 使用场景：
/// - 视频卡片、音乐封面、设置行、任何需要 D-pad 选中的元素。
/// - 不要包装已有焦点语义的 widget（Button / TextField 等），否则双层焦点。
///
/// 示例：
/// ```dart
/// TvFocusable(
///   onPressed: () => _playVideo(item),
///   child: VideoCard(item: item),
/// )
/// ```
class TvFocusable extends StatefulWidget {
  const TvFocusable({
    required this.child,
    required this.onPressed,
    this.autofocus = false,
    this.focusNode,
    super.key,
  });

  final Widget child;
  final VoidCallback onPressed;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable>
    with SingleTickerProviderStateMixin {
  late final FocusNode _focusNode;
  late final AnimationController _scaleController;
  late final Animation<double> _scaleAnimation;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChange);

    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    if (widget.focusNode == null) _focusNode.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus != _isFocused) {
      setState(() => _isFocused = _focusNode.hasFocus);
      if (_isFocused) {
        _scaleController.forward();
      } else {
        _scaleController.reverse();
      }
    }
  }

  @override
  Widget build(BuildContext context) => FocusableActionDetector(
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        onShowFocusHighlight: (highlight) => {},
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => widget.onPressed(),
          ),
        },
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        },
        child: AnimatedBuilder(
          animation: _scaleAnimation,
          builder: (context, child) => Transform.scale(
            scale: _scaleAnimation.value,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: _isFocused
                    ? Border.all(color: Colors.white, width: 2)
                    : null,
                borderRadius: BorderRadius.circular(8),
              ),
              child: child,
            ),
          ),
          child: widget.child,
        ),
      );
}
