import 'dart:io';

import 'package:flutter/services.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/domain/entities/audio_capability.dart';

/// 音频输出能力检测服务
///
/// 检测设备的音频直通能力
class AudioOutputCapabilityService {
  factory AudioOutputCapabilityService() =>
      _instance ??= AudioOutputCapabilityService._();
  AudioOutputCapabilityService._();

  static AudioOutputCapabilityService? _instance;

  static const _channel = MethodChannel('com.kkape.mynas/audio_capability');

  /// 缓存的音频能力
  AudioPassthroughCapability? _cachedCapability;

  /// 上次检测时间
  DateTime? _lastDetectionTime;

  /// 缓存有效期（1分钟，因为音频设备可能频繁切换）
  static const _cacheValidDuration = Duration(minutes: 1);

  /// 检测音频直通能力
  ///
  /// 会缓存结果，但缓存时间较短以响应设备切换
  Future<AudioPassthroughCapability> detectPassthroughCapability({
    bool forceRefresh = false,
  }) async {
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
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('getPassthroughCapability');
      _cachedCapability = AudioPassthroughCapability.fromMap(result);
      _lastDetectionTime = DateTime.now();

      logger.i('AudioOutputCapabilityService: 检测到音频能力 - $_cachedCapability');
      return _cachedCapability!;
    } on PlatformException catch (e, st) {
      AppError.ignore(e, st, '音频能力检测失败（平台不支持）');
      _cachedCapability = const AudioPassthroughCapability(isSupported: false);
      _lastDetectionTime = DateTime.now();
      return _cachedCapability!;
    } on MissingPluginException catch (e, st) {
      AppError.ignore(e, st, '音频能力检测失败（插件未注册）');
      _cachedCapability = const AudioPassthroughCapability(isSupported: false);
      _lastDetectionTime = DateTime.now();
      return _cachedCapability!;
    } catch (e, st) {
      AppError.ignore(e, st, '音频能力检测失败');
      _cachedCapability = const AudioPassthroughCapability(isSupported: false);
      _lastDetectionTime = DateTime.now();
      return _cachedCapability!;
    }
  }

  /// 获取桌面端回退能力
  ///
  /// Windows/Linux 暂时无法检测，返回保守估计
  // 桌面端假设可能支持直通，让用户手动选择
  AudioPassthroughCapability _getDesktopFallbackCapability() =>
      const AudioPassthroughCapability(
        isSupported: true,
        supportedCodecs: [
          AudioCodec.ac3,
          AudioCodec.eac3,
          AudioCodec.dts,
          AudioCodec.dtsHd,
          AudioCodec.truehd,
        ],
        outputDevice: AudioOutputDevice.unknown,
        maxChannels: 8,
      );

  /// 清除缓存
  void clearCache() {
    _cachedCapability = null;
    _lastDetectionTime = null;
  }

  /// 判断是否应该使用音频直通
  ///
  /// [audioCodec] 视频的音频编码
  /// [capability] 设备的音频能力
  bool shouldUseAudioPassthrough(
    AudioCodec audioCodec,
    AudioPassthroughCapability capability,
  ) {
    if (!capability.isSupported) return false;
    if (!audioCodec.supportsPassthrough) return false;

    // 检查设备是否支持该编码的直通
    return capability.supportedCodecs.contains(audioCodec);
  }

  /// 获取可用的直通编码列表
  ///
  /// 根据视频音频编码和设备能力返回实际可用的编码
  List<AudioCodec> getAvailablePassthroughCodecs(
    AudioCodec? videoAudioCodec,
    AudioPassthroughCapability capability,
  ) {
    if (!capability.isSupported) return [];

    // 如果视频音频编码已知，只返回支持该编码的列表
    if (videoAudioCodec != null) {
      if (capability.supportedCodecs.contains(videoAudioCodec)) {
        return [videoAudioCodec];
      }
      return [];
    }

    // 返回设备支持的所有直通编码
    return capability.supportedCodecs;
  }
}
