import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';

/// Android TV / Google TV / 电视盒子检测
///
/// 通过系统 feature（leanback / television）判断是否运行在电视设备上。
/// 检测结果在 [init] 中缓存，之后可通过 [isAndroidTv] 同步读取。
/// [init] 需在 app 初始化阶段（main.dart 的 _initApp）调用一次。
class TvCapabilities {
  TvCapabilities._();

  static bool _isAndroidTv = false;
  static bool _initialized = false;

  /// 是否运行在 Android TV / Google TV / 电视盒子上
  ///
  /// [init] 完成前恒为 false。
  static bool get isAndroidTv => _isAndroidTv;

  /// 探测当前设备是否为电视，结果缓存到 [isAndroidTv]
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    if (kIsWeb || !Platform.isAndroid) return;

    _isAndroidTv = await AppError.guard(
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

  /// 仅供测试使用：重置缓存状态
  @visibleForTesting
  static void resetForTest() {
    _isAndroidTv = false;
    _initialized = false;
  }
}
