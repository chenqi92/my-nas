import 'dart:io';

import 'package:flutter/services.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/domain/entities/hdr_capability.dart';

/// 显示能力检测服务
///
/// 检测设备的 HDR 显示能力
class DisplayCapabilityService {
  factory DisplayCapabilityService() => _instance ??= DisplayCapabilityService._();
  DisplayCapabilityService._();

  static DisplayCapabilityService? _instance;

  static const _channel = MethodChannel('com.kkape.mynas/display_capability');

  /// 缓存的 HDR 能力
  HdrCapability? _cachedCapability;

  /// 上次检测时间
  DateTime? _lastDetectionTime;

  /// 缓存有效期（5分钟）
  static const _cacheValidDuration = Duration(minutes: 5);

  /// 检测 HDR 能力
  ///
  /// 会缓存结果，避免频繁调用原生代码
  Future<HdrCapability> detectHdrCapability({bool forceRefresh = false}) async {
    // 检查缓存是否有效
    if (!forceRefresh &&
        _cachedCapability != null &&
        _lastDetectionTime != null &&
        DateTime.now().difference(_lastDetectionTime!) < _cacheValidDuration) {
      return _cachedCapability!;
    }

    try {
      // Windows 和 Linux 暂不支持原生检测
      if (Platform.isWindows || Platform.isLinux) {
        _cachedCapability = _getDesktopFallbackCapability();
        _lastDetectionTime = DateTime.now();
        return _cachedCapability!;
      }

      // iOS/macOS/Android 调用原生代码检测
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('getHdrCapability');
      _cachedCapability = HdrCapability.fromMap(result);
      _lastDetectionTime = DateTime.now();

      logger.i('DisplayCapabilityService: 检测到 HDR 能力 - $_cachedCapability');
      return _cachedCapability!;
    } on PlatformException catch (e, st) {
      AppError.ignore(e, st, 'HDR 能力检测失败（平台不支持）');
      _cachedCapability = const HdrCapability(isSupported: false);
      _lastDetectionTime = DateTime.now();
      return _cachedCapability!;
    } on MissingPluginException catch (e, st) {
      AppError.ignore(e, st, 'HDR 能力检测失败（插件未注册）');
      _cachedCapability = const HdrCapability(isSupported: false);
      _lastDetectionTime = DateTime.now();
      return _cachedCapability!;
    } catch (e, st) {
      AppError.ignore(e, st, 'HDR 能力检测失败');
      _cachedCapability = const HdrCapability(isSupported: false);
      _lastDetectionTime = DateTime.now();
      return _cachedCapability!;
    }
  }

  /// 获取桌面端回退能力
  ///
  /// Windows/Linux 暂时无法检测，返回保守估计
  HdrCapability _getDesktopFallbackCapability() =>
      // 桌面端假设可能支持 HDR，让用户手动选择
      // 这样用户可以选择直通或色调映射
      const HdrCapability(
        isSupported: true,
        supportedTypes: [HdrType.hdr10, HdrType.hlg],
        maxLuminance: 0, // 未知
      );

  /// 清除缓存
  void clearCache() {
    _cachedCapability = null;
    _lastDetectionTime = null;
  }

  /// 判断是否应该使用 HDR 直通
  ///
  /// [videoHdrType] 视频的 HDR 类型
  /// [capability] 设备的 HDR 能力
  bool shouldUseHdrPassthrough(HdrType videoHdrType, HdrCapability capability) {
    if (!capability.isSupported) return false;
    if (videoHdrType == HdrType.none) return false;

    // 检查设备是否支持该 HDR 类型
    return capability.supportedTypes.contains(videoHdrType);
  }
}
