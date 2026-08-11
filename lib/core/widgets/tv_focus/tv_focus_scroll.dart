import 'package:flutter/material.dart';

/// TV 焦点自动滚动包装器：当内部任意子孙获得焦点时，滚动容器以确保其完整可见。
///
/// - **触发时机**：本子树内任意 [FocusNode]（通常是 [TvFocusable]）成为主焦点。
/// - **滚动策略**：调用 [Scrollable.ensureVisible]，默认 `alignment: 0.5` 居中，
///   动画 300ms / `easeInOut`。
/// - **使用场景**：包装 [ListView]、[GridView]、[SingleChildScrollView] 等可滚动容器。
///
/// 实现原理：
/// - 监听 [FocusManager.instance]（全局主焦点变化），而不是 `FocusScope.of(context)`。
///   这一点是必须的：`FocusScopeNode` 只在焦点**进出**该 scope 时通知监听者，
///   焦点在同一 scope 内的兄弟节点间移动时它的 `hasFocus` 不变、不会通知——
///   而「货架内左右键换卡片」恰好全是这种同 scope 内移动。
/// - 每次主焦点变化时判断新焦点是否落在本子树内（沿 Element 树上溯比对），
///   是则对它的 context 调 [Scrollable.ensureVisible]。
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
  void initState() {
    super.initState();
    // 订阅全局焦点管理器：dispose 时用同一个单例摘除，不依赖 context，
    // 因此不会在 element 已 deactivate 时做祖先查找。
    FocusManager.instance.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (!mounted) return;

    final focused = FocusManager.instance.primaryFocus;
    if (focused == null || focused == _lastFocusedNode) return;

    // 焦点可能落在尚未挂载的 item 上（ListView.builder 未构建到），
    // 或落在本子树之外（别的货架 / 导航 Rail），两种都不该滚本容器。
    final focusContext = focused.context;
    if (focusContext == null || !focusContext.mounted) return;
    if (!_isInSubtree(focusContext)) return;

    _lastFocusedNode = focused;
    if (focusContext.findRenderObject() == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 本帧之后 item 可能已被回收，重新取一次再滚。
      final ctx = focused.context;
      if (ctx == null || !ctx.mounted || ctx.findRenderObject() == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: widget.alignment,
        duration: widget.duration,
        curve: widget.curve,
      );
    });
  }

  /// [focusContext] 是否位于本 widget 之下。
  ///
  /// 沿 Element 树上溯比对身份：全局监听会收到整个 app 的焦点变化，必须先筛掉
  /// 不属于本容器的，否则多个 [TvFocusScroll] 会互相抢着滚动。
  bool _isInSubtree(BuildContext focusContext) {
    final self = context;
    var found = false;
    focusContext.visitAncestorElements((element) {
      if (element == self) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
