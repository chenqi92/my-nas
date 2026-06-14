import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/utils/hive_utils.dart';

/// 玻璃材质参数（仅 Glass 风格下生效）。三项独立持久化于 settings box：
/// 模糊强度、材质不透明度、平台玻璃优化（启用模糊）。默认值保持现状外观不变。
///
/// 模式参考 [dynamicAmbientProvider]。

/// 模糊强度缩放（0.5–1.5，默认 1.0）：最终 sigma = baseSigma × 此值。
final glassBlurScaleProvider =
    StateNotifierProvider<_DoubleSettingNotifier, double>(
  (ref) => _DoubleSettingNotifier(
    key: 'glass_blur_scale',
    defaultValue: 1.0,
    min: 0.5,
    max: 1.5,
    failHint: '玻璃模糊强度',
  ),
);

/// 材质不透明度缩放（0.5–1.5，默认 1.0）：面板背景 alpha × 此值（clamp 0–1）。
final glassOpacityScaleProvider =
    StateNotifierProvider<_DoubleSettingNotifier, double>(
  (ref) => _DoubleSettingNotifier(
    key: 'glass_opacity_scale',
    defaultValue: 1.0,
    min: 0.5,
    max: 1.5,
    failHint: '玻璃材质不透明度',
  ),
);

/// 平台玻璃优化 / 启用模糊（默认 true）：关闭后玻璃面板不再做高斯模糊。
final glassBlurEnabledProvider =
    StateNotifierProvider<_BoolSettingNotifier, bool>(
  (ref) => _BoolSettingNotifier(
    key: 'glass_blur_enabled',
    defaultValue: true,
    failHint: '平台玻璃优化',
  ),
);

class _DoubleSettingNotifier extends StateNotifier<double> {
  _DoubleSettingNotifier({
    required this.key,
    required double defaultValue,
    required this.min,
    required this.max,
    required this.failHint,
  }) : super(defaultValue) {
    _load();
  }

  final String key;
  final double min;
  final double max;
  final String failHint;

  Future<void> _load() async {
    try {
      final box = await HiveUtils.getSettingsBox();
      final v = box.get(key);
      if (v is num) state = v.toDouble().clamp(min, max);
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '加载$failHint设置失败，使用默认值');
    }
  }

  Future<void> setValue(double value) async {
    final clamped = value.clamp(min, max);
    state = clamped;
    try {
      final box = await HiveUtils.getSettingsBox();
      await box.put(key, clamped);
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '保存$failHint设置失败');
    }
  }
}

class _BoolSettingNotifier extends StateNotifier<bool> {
  _BoolSettingNotifier({
    required this.key,
    required bool defaultValue,
    required this.failHint,
  }) : super(defaultValue) {
    _load();
  }

  final String key;
  final String failHint;

  Future<void> _load() async {
    try {
      final box = await HiveUtils.getSettingsBox();
      final v = box.get(key) as bool?;
      if (v != null) state = v;
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '加载$failHint设置失败，使用默认值');
    }
  }

  Future<void> setEnabled({required bool enabled}) async {
    state = enabled;
    try {
      final box = await HiveUtils.getSettingsBox();
      await box.put(key, enabled);
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '保存$failHint设置失败');
    }
  }
}
