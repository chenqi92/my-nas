import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/utils/hive_utils.dart';

/// TV 模式的手动覆盖档位。
///
/// 存在的原因有两个：
/// 1. 部分电视盒子（尤其国产 ROM）不声明 leanback / television feature，
///    自动探测会漏判，用户需要能手动打开；
/// 2. 开发 / 验证时需要在手机或桌面上强制进入 TV 布局，否则只能靠电视实机。
enum TvModeOverride {
  /// 跟随系统 feature 探测结果
  auto,

  /// 强制按 TV 处理（用于漏判的盒子 / 桌面验证）
  forceOn,

  /// 强制不按 TV 处理（用于电视上临时切回手机布局）
  forceOff,
}

/// Android TV / Google TV / 电视盒子检测
///
/// 通过系统 feature（leanback / television）判断是否运行在电视设备上，
/// 并叠加用户可持久化的 [TvModeOverride]。
///
/// 检测结果在 [init] 中缓存，之后可通过 [isTvMode] 同步读取。
/// [init] 需在 app 初始化阶段（main.dart 的 _initApp）调用一次，且必须在
/// `Hive.initFlutter()` 之后（要读 settings box 里的 override）。
class TvCapabilities {
  TvCapabilities._();

  /// settings box 中持久化 override 的 key
  static const String _kOverrideKey = 'tv_mode_override';

  static bool _isTvDevice = false;
  static TvModeOverride _override = TvModeOverride.auto;
  static bool _initialized = false;

  /// 系统 feature 探测出的「这是电视硬件」结果，不受 override 影响。
  ///
  /// 只应在设置页展示「自动检测结果」时使用；布局判断请用 [isTvMode]。
  static bool get isTvDevice => _isTvDevice;

  /// 当前的手动覆盖档位
  static TvModeOverride get override => _override;

  /// 是否按电视（10-foot UI + D-pad）处理，override 优先于自动探测。
  ///
  /// [init] 完成前恒为 false。
  static bool get isTvMode =>
      resolveTvMode(_override, isTvDevice: _isTvDevice);

  /// override 与硬件探测结果的合并规则（纯函数，唯一定义处）。
  ///
  /// Riverpod 侧用它从 provider 的 override 状态推导布尔值，避免依赖静态字段的
  /// 写入时序。
  static bool resolveTvMode(
    TvModeOverride override, {
    required bool isTvDevice,
  }) =>
      switch (override) {
        TvModeOverride.forceOn => true,
        TvModeOverride.forceOff => false,
        TvModeOverride.auto => isTvDevice,
      };

  /// 探测当前设备是否为电视并载入持久化的 override。
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // override 先载入：它在所有平台都生效（桌面强制 TV 态用于验证），
    // 因此不能放在下面的 Android 门控之后。
    _override = await AppError.guard(
          _loadOverride,
          action: 'TvCapabilities.loadOverride',
          fallback: TvModeOverride.auto,
        ) ??
        TvModeOverride.auto;

    if (kIsWeb || !Platform.isAndroid) return;

    _isTvDevice = await AppError.guard(
          () async {
            final info = await DeviceInfoPlugin().androidInfo;
            final features = info.systemFeatures;
            return features.contains('android.software.leanback') ||
                features.contains('android.hardware.type.television');
          },
          action: 'TvCapabilities.init',
          fallback: false,
        ) ??
        false;
  }

  /// 写入并持久化 override。
  ///
  /// 调用方负责触发 UI 重建（见 `tvModeOverrideProvider`）：本类只持有值，
  /// 静态 getter 本身不具备可监听性。
  static Future<void> setOverride(TvModeOverride value) async {
    _override = value;
    await AppError.guard(
      () async {
        final box = await HiveUtils.getSettingsBox();
        await box.put(_kOverrideKey, value.name);
      },
      action: 'TvCapabilities.setOverride',
      extraData: {'override': value.name},
    );
  }

  static Future<TvModeOverride> _loadOverride() async {
    final box = await HiveUtils.getSettingsBox();
    final raw = box.get(_kOverrideKey);
    if (raw is! String) return TvModeOverride.auto;
    for (final mode in TvModeOverride.values) {
      if (mode.name == raw) return mode;
    }
    return TvModeOverride.auto;
  }

  /// 仅供测试使用：重置缓存状态
  @visibleForTesting
  static void resetForTest() {
    _isTvDevice = false;
    _override = TvModeOverride.auto;
    _initialized = false;
  }

  /// 仅供测试使用：直接注入状态，跳过 Hive / device_info 探测。
  @visibleForTesting
  static void debugSetForTest({
    bool? isTvDevice,
    TvModeOverride? override,
  }) {
    if (isTvDevice != null) _isTvDevice = isTvDevice;
    if (override != null) _override = override;
    _initialized = true;
  }
}
