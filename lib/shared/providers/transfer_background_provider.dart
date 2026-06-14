import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/utils/hive_utils.dart';
import 'package:my_nas/features/transfer/data/services/transfer_service.dart';

/// 「启动恢复」设置：启动时是否把上次未完成的传输任务恢复到队列。
///
/// 持久化于 settings box（key `transfer_resume_on_startup`），默认开启
/// （与现状一致——[TransferService.init] 始终加载未完成任务）。状态与
/// [TransferService.resumeOnStartup] 同步：构造 `_load` 时即写入静态字段
/// （启动即生效），[setEnabled] 同时写 Hive 与静态字段。
///
/// 关闭后：下次启动 [TransferService.init] 不再把未完成任务读回内存队列
/// （任务仍保留在数据库，不会丢失，只是不自动进入本次会话）。
final resumeOnStartupProvider =
    StateNotifierProvider<ResumeOnStartupNotifier, bool>(
  (ref) => ResumeOnStartupNotifier(),
);

class ResumeOnStartupNotifier extends StateNotifier<bool> {
  ResumeOnStartupNotifier() : super(_defaultValue) {
    TransferService.resumeOnStartup = state;
    _load();
  }

  static const _key = 'transfer_resume_on_startup';
  static const _defaultValue = true;

  Future<void> _load() async {
    try {
      final box = await HiveUtils.getSettingsBox();
      final v = box.get(_key) as bool?;
      if (v != null) {
        state = v;
        TransferService.resumeOnStartup = v;
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '加载启动恢复设置失败，使用默认值');
    }
  }

  Future<void> setEnabled({required bool enabled}) async {
    state = enabled;
    TransferService.resumeOnStartup = enabled;
    try {
      final box = await HiveUtils.getSettingsBox();
      await box.put(_key, enabled);
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '保存启动恢复设置失败');
    }
  }
}

/// 「后台传输」设置：窗口最小化 / 隐藏后是否继续传输。
///
/// 持久化于 settings box（key `transfer_background_enabled`），默认开启
/// （与现状一致——桌面传输是纯 Dart Future，窗口最小化本就持续运行）。
/// 状态与 [TransferService.backgroundTransfer] 同步：构造 `_load` 时即写入
/// 静态字段（启动即生效），[setEnabled] 同时写 Hive 与静态字段。
///
/// 关闭后：窗口最小化时 [TransferService.pauseActiveForBackground] 暂停正在
/// 进行的任务，窗口恢复时 [TransferService.resumeFromBackground] 仅恢复这批
/// 自动暂停的任务（不影响用户手动暂停的任务）。窗口监听在 app 启动时注册。
final backgroundTransferProvider =
    StateNotifierProvider<BackgroundTransferNotifier, bool>(
  (ref) => BackgroundTransferNotifier(),
);

class BackgroundTransferNotifier extends StateNotifier<bool> {
  BackgroundTransferNotifier() : super(_defaultValue) {
    TransferService.backgroundTransfer = state;
    _load();
  }

  static const _key = 'transfer_background_enabled';
  static const _defaultValue = true;

  Future<void> _load() async {
    try {
      final box = await HiveUtils.getSettingsBox();
      final v = box.get(_key) as bool?;
      if (v != null) {
        state = v;
        TransferService.backgroundTransfer = v;
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '加载后台传输设置失败，使用默认值');
    }
  }

  Future<void> setEnabled({required bool enabled}) async {
    state = enabled;
    TransferService.backgroundTransfer = enabled;
    try {
      final box = await HiveUtils.getSettingsBox();
      await box.put(_key, enabled);
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '保存后台传输设置失败');
    }
  }
}
