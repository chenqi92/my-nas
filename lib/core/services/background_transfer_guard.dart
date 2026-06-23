import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/features/transfer/data/services/transfer_service.dart';
import 'package:window_manager/window_manager.dart';

/// 「后台传输」窗口守卫：窗口最小化 / 失焦时按设置暂停传输，恢复 / 聚焦时续传。
///
/// 仅作用于桌面平台（macOS / Windows / Linux）。是否暂停取决于
/// [TransferService.backgroundTransfer]——开态（默认）时 [TransferService] 的
/// pause / resume 方法本身是 no-op，守卫不改变现状；关态时窗口隐藏即暂停、
/// 恢复即续传。移动端 / Web 调用 [ensureStarted] 为 no-op。
class BackgroundTransferGuard with WindowListener {
  BackgroundTransferGuard._();

  static final BackgroundTransferGuard instance = BackgroundTransferGuard._();

  bool _started = false;

  /// 注册窗口监听（仅桌面、仅一次）。
  void ensureStarted() {
    if (_started) return;
    if (kIsWeb) return;
    if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) return;
    _started = true;
    windowManager.addListener(this);
  }

  @override
  void onWindowMinimize() {
    AppError.fireAndForget(
      TransferService().pauseActiveForBackground(),
      action: 'pauseTransferForBackground',
    );
  }

  @override
  void onWindowRestore() {
    AppError.fireAndForget(
      TransferService().resumeFromBackground(),
      action: 'resumeTransferFromBackground',
    );
  }
}
