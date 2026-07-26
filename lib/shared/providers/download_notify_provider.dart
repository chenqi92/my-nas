import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/utils/hive_utils.dart';

/// 「下载完成通知」开关：下载任务完成时是否发送系统通知并显示应用内提示。
/// 持久化于 settings box，默认开启。系统通知不可用时仍保留应用内提示。
final downloadNotifyProvider =
    StateNotifierProvider<DownloadNotifyNotifier, bool>(
      (ref) => DownloadNotifyNotifier(),
    );

class DownloadNotifyNotifier extends StateNotifier<bool> {
  DownloadNotifyNotifier() : super(true) {
    _load();
  }

  static const _key = 'download_complete_notify';

  Future<void> _load() async {
    try {
      final box = await HiveUtils.getSettingsBox();
      final v = box.get(_key) as bool?;
      if (v != null) state = v;
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '加载下载完成通知设置失败，使用默认值');
    }
  }

  Future<void> setEnabled({required bool enabled}) async {
    state = enabled;
    try {
      final box = await HiveUtils.getSettingsBox();
      await box.put(_key, enabled);
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '保存下载完成通知设置失败');
    }
  }
}
