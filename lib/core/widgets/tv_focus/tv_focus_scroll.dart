import 'package:flutter/material.dart';

/// TV 焦点自动滚动包装器：当内部任意子孙获得焦点时，滚动容器以确保其完整可见。
///
/// - **触发时机**：内部 [TvFocusable] 或任何 [FocusNode] 获得焦点时。
/// - **滚动策略**：调用 [Scrollable.ensureVisible]，使用 `alignment: 0.5` 居中对齐，
///   动画时长 300ms，曲线 `easeInOut`。
/// - **使用场景**：包装 [ListView]、[GridView]、[SingleChildScrollView] 等可滚动容器。
///
/// 实现原理：
/// - 通过 [FocusScope.of(context)] 监听焦点树变化。
/// - 焦点变化时，检查新焦点节点是否在当前子树内。
/// - 如果是，调用 [Scrollable.ensureVisible] 滚动到该节点的 [RenderObject]。
///
/// 示例：
/// ```dart
/// TvFocusScroll(
///   child: ListView.builder(
///     itemCount: items.length,
///     itemBuilder: (context, i) => TvFocusable(
///       onPressed: () => _select(i),
///       child: ItemCard(items[i]),
///     ),
///   ),
/// )
/// ```
class TvFocusScroll extends StatefulWidget {
  const TvFocusScroll({
    required this.child,
    this.alignment = 0.5,
    this.duration = const Duration(milliseconds: 300),
    this.curve = Curves.easeInOut,
    super.key,
  });

  final Widget child;
  final double alignment;
  final Duration duration;
  final Curve curve;

  @override
  State<TvFocusScroll> createState() => _TvFocusScrollState();
}

class _TvFocusScrollState extends State<TvFocusScroll> {
  FocusNode? _lastFocusedNode;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _attachFocusListener();
  }

  @override
  void dispose() {
    _detachFocusListener();
    super.dispose();
  }

  void _attachFocusListener() {
    _detachFocusListener();
    final scope = FocusScope.of(context);
    _lastFocusedNode = scope.focusedChild;
    scope.addListener(_onFocusChange);
  }

  void _detachFocusListener() {
    if (_lastFocusedNode != null) {
      FocusScope.of(context).removeListener(_onFocusChange);
      _lastFocusedNode = null;
    }
  }

  void _onFocusChange() {
    final scope = FocusScope.of(context);
    final newFocus = scope.focusedChild;

    if (newFocus != _lastFocusedNode && newFocus != null) {
      _lastFocusedNode = newFocus;

      if (newFocus.context != null && mounted) {
        final renderObject = newFocus.context!.findRenderObject();
        if (renderObject != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Scrollable.ensureVisible(
              newFocus.context!,
              alignment: widget.alignment,
              duration: widget.duration,
              curve: widget.curve,
            );
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
