import 'package:flutter/material.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/services/toast_service.dart';
import 'package:my_nas/shared/widgets/toast_widget.dart';

/// 全局 Toast 覆盖层
///
/// 包装应用内容，提供三个 Toast 显示区域：
/// - 顶部区域：移动端警告/错误消息
/// - 底部区域：移动端成功/信息消息
/// - 右下角区域：桌面端所有消息
class ToastOverlay extends StatefulWidget {
  const ToastOverlay({
    required this.child,
    required this.toastService,
    super.key,
  });

  /// 子组件（应用内容）
  final Widget child;

  /// Toast 服务实例
  final ToastService toastService;

  @override
  State<ToastOverlay> createState() => _ToastOverlayState();
}

class _ToastOverlayState extends State<ToastOverlay> {
  @override
  void initState() {
    super.initState();
    widget.toastService.addListener(_onToastChanged);
  }

  @override
  void dispose() {
    widget.toastService.removeListener(_onToastChanged);
    super.dispose();
  }

  void _onToastChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = context.isDesktop;
    final padding = MediaQuery.paddingOf(context);

    return Stack(
      children: [
        // 主内容
        widget.child,

        // 顶部 Toast 区域（移动端警告/错误）
        if (!isDesktop && widget.toastService.topMessages.isNotEmpty)
          Positioned(
            top: padding.top + 8,
            left: 0,
            right: 0,
            child: _ToastContainer(
              messages: widget.toastService.topMessages,
              position: ToastPosition.top,
              onDismiss: widget.toastService.dismiss,
            ),
          ),

        // 底部 Toast 区域（移动端成功/信息）
        if (!isDesktop && widget.toastService.bottomMessages.isNotEmpty)
          Positioned(
            bottom: padding.bottom + 80, // 留出底部导航栏空间
            left: 0,
            right: 0,
            child: _ToastContainer(
              messages: widget.toastService.bottomMessages,
              position: ToastPosition.bottom,
              onDismiss: widget.toastService.dismiss,
            ),
          ),

        // 右下角堆叠区域（桌面端）
        if (isDesktop && widget.toastService.stackMessages.isNotEmpty)
          Positioned(
            bottom: 24,
            right: 24,
            child: SizedBox(
              width: 380,
              child: _ToastContainer(
                messages: widget.toastService.stackMessages,
                position: ToastPosition.bottomRight,
                onDismiss: widget.toastService.dismiss,
              ),
            ),
          ),
      ],
    );
  }
}

/// Toast 容器组件
class _ToastContainer extends StatelessWidget {
  const _ToastContainer({
    required this.messages,
    required this.position,
    required this.onDismiss,
  });

  final List<ToastMessage> messages;
  final ToastPosition position;
  final void Function(String id) onDismiss;

  @override
  Widget build(BuildContext context) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final message in messages)
          AnimatedToastWidget(
            key: ValueKey(message.id),
            message: message,
            position: position,
            onDismiss: () => onDismiss(message.id),
          ),
      ],
    );
}

/// ToastOverlay 的便捷包装器
///
/// 用于在 MaterialApp.builder 中使用：
/// ```dart
/// MaterialApp(
///   builder: (context, child) {
///     return ToastOverlayWrapper(child: child);
///   },
/// )
/// ```
class ToastOverlayWrapper extends StatelessWidget {
  const ToastOverlayWrapper({
    required this.child,
    super.key,
  });

  final Widget? child;

  @override
  Widget build(BuildContext context) =>
      // ToastService 应该通过 Provider 或 GetIt 获取
      // 这里暂时直接创建，后续改为依赖注入
      ListenableBuilder(
        listenable: ToastServiceProvider.of(context),
        builder: (context, _) => ToastOverlay(
          toastService: ToastServiceProvider.of(context),
          child: child ?? const SizedBox.shrink(),
        ),
      );
}

/// Toast 服务提供者
///
/// 使用 InheritedWidget 将 ToastService 注入到 Widget 树中
class ToastServiceProvider extends InheritedWidget {
  const ToastServiceProvider({
    required this.service,
    required super.child,
    super.key,
  });

  final ToastService service;

  static ToastService of(BuildContext context) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<ToastServiceProvider>();
    assert(provider != null, 'No ToastServiceProvider found in context');
    return provider!.service;
  }

  static ToastService? maybeOf(BuildContext context) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<ToastServiceProvider>();
    return provider?.service;
  }

  @override
  bool updateShouldNotify(ToastServiceProvider oldWidget) => service != oldWidget.service;
}
