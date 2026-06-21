import 'dart:io';

import 'package:flutter/services.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/features/music/data/services/fingerprint/fingerprint_service.dart';

/// 移动端指纹服务实现
///
/// 使用平台通道调用原生 Chromaprint 库
/// Android: 使用 JNI 调用 libchromaprint.so
/// iOS: 使用静态链接的 Chromaprint framework
class FingerprintServiceMobile implements FingerprintService {
  FingerprintServiceMobile._() {
    _checkAvailability();
  }

  static FingerprintServiceMobile? _instance;

  /// 获取单例实例
  static FingerprintServiceMobile get instance =>
      _instance ??= FingerprintServiceMobile._();

  static const _channel = MethodChannel('com.mynas.fingerprint/chromaprint');

  bool _available = false;

  @override
  bool get isAvailable => _available;

  /// 检查原生库是否可用
  Future<void> _checkAvailability() async {
    try {
      final result = await _channel.invokeMethod<bool>('isAvailable');
      _available = result ?? false;
    } on PlatformException {
      _available = false;
    } on MissingPluginException {
      _available = false;
    }
  }

  @override
  Future<FingerprintData> generateFingerprint(
    String filePath, {
    int maxDuration = 120,
  }) async {
    if (!_available) {
      throw FingerprintUnavailableException(appL10n.fingerprintMobileServiceUnavailable);
    }

    // 检查文件是否存在
    if (!await File(filePath).exists()) {
      throw FingerprintGenerationException(appL10n.fingerprintAudioFileNotFound(filePath));
    }

    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'generateFingerprint',
        {
          'filePath': filePath,
          'maxDuration': maxDuration,
        },
      );

      if (result == null) {
        throw FingerprintGenerationException(appL10n.fingerprintEmptyResult);
      }

      final fingerprint = result['fingerprint'] as String?;
      final duration = result['duration'] as int?;

      if (fingerprint == null || fingerprint.isEmpty) {
        final error = result['error'] as String?;
        throw FingerprintGenerationException(error ?? appL10n.fingerprintInvalid);
      }

      return FingerprintData(
        fingerprint: fingerprint,
        duration: duration ?? 0,
      );
    } on PlatformException catch (e) {
      throw FingerprintGenerationException(
        appL10n.fingerprintPlatformCallFailed(e.message ?? ''),
        cause: e,
      );
    }
  }

  @override
  Future<FingerprintData> generateFingerprintFromStream(
    Stream<List<int>> audioStream, {
    required int sampleRate,
    required int channels,
  }) async {
    if (!_available) {
      throw FingerprintUnavailableException(appL10n.fingerprintMobileServiceUnavailable);
    }

    // 收集所有音频数据
    final chunks = <int>[];
    await for (final chunk in audioStream) {
      chunks.addAll(chunk);
      // 限制数据量（最多 120 秒 * 44100 Hz * 2 channels * 2 bytes）
      if (chunks.length > 120 * 44100 * 2 * 2) {
        break;
      }
    }

    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'generateFingerprintFromPCM',
        {
          'pcmData': chunks,
          'sampleRate': sampleRate,
          'channels': channels,
        },
      );

      if (result == null) {
        throw FingerprintGenerationException(appL10n.fingerprintEmptyResult);
      }

      final fingerprint = result['fingerprint'] as String?;
      final duration = result['duration'] as int?;

      if (fingerprint == null || fingerprint.isEmpty) {
        final error = result['error'] as String?;
        throw FingerprintGenerationException(error ?? appL10n.fingerprintInvalid);
      }

      return FingerprintData(
        fingerprint: fingerprint,
        duration: duration ?? 0,
      );
    } on PlatformException catch (e) {
      throw FingerprintGenerationException(
        appL10n.fingerprintPlatformCallFailed(e.message ?? ''),
        cause: e,
      );
    }
  }

  @override
  void dispose() {
    _instance = null;
  }
}
