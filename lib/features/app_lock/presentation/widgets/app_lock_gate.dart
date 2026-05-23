import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/app_lock/domain/app_lock_state.dart';
import 'package:my_nas/features/app_lock/presentation/pages/unlock_page.dart';
import 'package:my_nas/features/app_lock/presentation/providers/app_lock_provider.dart';
import 'package:secure_application/secure_application.dart';

/// 应用锁路由门 + 应用切换器遮蔽
///
/// 在状态为 [AppLockPhase.locked] 时遮盖 child 并显示 [UnlockPage]。
/// 同时在支持的平台（iOS / Android / Windows）通过 [SecureApplication]
/// 让应用切换器 / 任务列表不显示内容（Android: FLAG_SECURE；iOS: 切到
/// 后台时显示原生 frost view）。macOS / Linux 不支持 secure_application，
/// 此时只走 Stack overlay 部分。
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  static bool get supportsSecureApplication =>
      Platform.isIOS || Platform.isAndroid || Platform.isWindows;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate> {
  final SecureApplicationController _secureController =
      SecureApplicationController(SecureApplicationState());

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appLockProvider);

    // 设置变化时同步 secure_application 的 secure 状态
    ref.listen(appLockProvider, (prev, next) {
      if (prev?.settings.enabled != next.settings.enabled) {
        if (next.settings.enabled) {
          _secureController.secure();
        } else {
          _secureController.open();
        }
      }
    });

    final core = Stack(
      children: [
        widget.child,
        if (state.phase == AppLockPhase.locked)
          const Positioned.fill(child: UnlockPage()),
      ],
    );

    if (!AppLockGate.supportsSecureApplication) return core;

    return SecureApplication(
      secureApplicationController: _secureController,
      nativeRemoveDelay: 300,
      onNeedUnlock: (_) async => null,
      child: core,
    );
  }
}

/// 监听应用生命周期，把 paused/resumed 转发给 [AppLockNotifier]
class AppLockLifecycleListener extends ConsumerStatefulWidget {
  const AppLockLifecycleListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLockLifecycleListener> createState() =>
      _AppLockLifecycleListenerState();
}

class _AppLockLifecycleListenerState
    extends ConsumerState<AppLockLifecycleListener>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(appLockProvider.notifier).lockNow();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final notifier = ref.read(appLockProvider.notifier);
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        notifier.onAppPaused();
      case AppLifecycleState.resumed:
        notifier.onAppResumed();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
