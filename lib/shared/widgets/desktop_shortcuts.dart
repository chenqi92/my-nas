import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// 切换主 tab 的 Intent。
///
/// 由 [DesktopShortcuts] 在桌面 / Web 上注册 Cmd+1..5（macOS）/
/// Ctrl+1..5（Windows / Linux）触发。
class _SwitchTabIntent extends Intent {
  const _SwitchTabIntent(this.index);

  final int index;
}

/// 对当前 branch navigator 执行 maybePop 的 Intent。
///
/// 绑定到 Esc，方便桌面用户快速关闭详情 / 弹窗。
class _PopRouteIntent extends Intent {
  const _PopRouteIntent();
}

/// 包装 [child]，在桌面 / Web 平台上注册全局快捷键：
///
/// - Cmd/Ctrl + 1..5 → 切到对应主 tab
/// - Cmd/Ctrl + , → 跳到「我的 / 设置」tab（macOS 经典）
/// - Esc → 当前 navigator pop
///
/// 移动平台（iOS / Android）直接返回 [child]，不消费任何按键事件，
/// 避免与系统手势 / IME 冲突。
class DesktopShortcuts extends StatelessWidget {
  const DesktopShortcuts({
    required this.child,
    required this.onSwitchTab,
    super.key,
  });

  final Widget child;

  /// 触发切 tab，由 MainScaffold 调用 navigationShell.goBranch。
  final ValueChanged<int> onSwitchTab;

  @override
  Widget build(BuildContext context) {
    if (!_isShortcutsTarget) {
      return child;
    }

    final shortcuts = <ShortcutActivator, Intent>{
      for (var i = 0; i < _digitKeys.length; i++) ...{
        SingleActivator(_digitKeys[i], meta: true): _SwitchTabIntent(i),
        SingleActivator(_digitKeys[i], control: true): _SwitchTabIntent(i),
      },
      // Cmd/Ctrl + , → 跳到「我的 / 设置」tab（macOS 经典快捷键）。
      // 「我的」是第 5 个 tab，索引 4。
      const SingleActivator(LogicalKeyboardKey.comma, meta: true):
          _SwitchTabIntent(4),
      const SingleActivator(LogicalKeyboardKey.comma, control: true):
          _SwitchTabIntent(4),
      const SingleActivator(LogicalKeyboardKey.escape): _PopRouteIntent(),
    };

    return Shortcuts(
      shortcuts: shortcuts,
      child: Actions(
        actions: <Type, Action<Intent>>{
          _SwitchTabIntent: CallbackAction<_SwitchTabIntent>(
            onInvoke: (intent) {
              onSwitchTab(intent.index);
              return null;
            },
          ),
          _PopRouteIntent: CallbackAction<_PopRouteIntent>(
            onInvoke: (_) {
              final router = GoRouter.maybeOf(context);
              final navigator =
                  router?.routerDelegate.navigatorKey.currentState;
              if (navigator != null && navigator.canPop()) {
                navigator.maybePop();
              }
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          // 拦截已注册的快捷键，让其它键盘事件穿透到子树。
          skipTraversal: true,
          canRequestFocus: false,
          child: child,
        ),
      ),
    );
  }

  static bool get _isShortcutsTarget {
    if (kIsWeb) return true;
    return defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  /// digit1..digit5 → tab index 0..4
  ///
  /// 用 List 而非 Map，规避 const map key 必须是 primitive 类型的限制
  /// （[LogicalKeyboardKey] 自定义了 `==`）。
  static const List<LogicalKeyboardKey> _digitKeys = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
  ];
}
