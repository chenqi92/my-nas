import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/utils/hive_utils.dart';

/// 「动态取色氛围光」开关：播放时桌面外壳的氛围光是否随封面 / 台标动态取色。
/// 对应设计稿 set-appearance 的「动态取色氛围光（APP-05）」。持久化于 settings box，
/// 默认开启。
final dynamicAmbientProvider =
    StateNotifierProvider<DynamicAmbientNotifier, bool>(
  (ref) => DynamicAmbientNotifier(),
);

class DynamicAmbientNotifier extends StateNotifier<bool> {
  DynamicAmbientNotifier() : super(true) {
    _load();
  }

  static const _key = 'dynamic_ambient_enabled';

  Future<void> _load() async {
    try {
      final box = await HiveUtils.getSettingsBox();
      final v = box.get(_key) as bool?;
      if (v != null) state = v;
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '加载动态取色氛围光设置失败，使用默认值');
    }
  }

  Future<void> setEnabled({required bool enabled}) async {
    state = enabled;
    try {
      final box = await HiveUtils.getSettingsBox();
      await box.put(_key, enabled);
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '保存动态取色氛围光设置失败');
    }
  }
}
