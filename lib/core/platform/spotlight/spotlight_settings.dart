import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/utils/hive_utils.dart';

/// 持久化在 settings box 的 key。
const String _kEnabledKey = 'spotlight_index_enabled';

/// Spotlight 索引开关（默认关闭，避免首次启动卡顿）。
///
/// 切换后由调用方负责触发全量重建 / 清空索引。
class SpotlightSettingsNotifier extends Notifier<bool> {
  Box<dynamic>? _box;

  @override
  bool build() {
    // 同步读取已打开的 settings box；尚未 init 时按默认值（关闭）返回。
    if (Hive.isBoxOpen('settings')) {
      _box = Hive.box<dynamic>('settings');
      return _box!.get(_kEnabledKey, defaultValue: false) as bool;
    }
    // 异步打开 box 后刷新一次状态。
    _initAsync();
    return false;
  }

  Future<void> _initAsync() async {
    try {
      _box = await HiveUtils.getSettingsBox();
      final saved = _box!.get(_kEnabledKey, defaultValue: false) as bool;
      if (saved != state) state = saved;
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'SpotlightSettings._initAsync');
    }
  }

  Future<void> setEnabled(bool value) async {
    if (state == value) return;
    state = value;
    _box ??= await HiveUtils.getSettingsBox();
    await _box!.put(_kEnabledKey, value);
  }
}

final spotlightEnabledProvider =
    NotifierProvider<SpotlightSettingsNotifier, bool>(
  SpotlightSettingsNotifier.new,
);
