import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/features/music/data/services/fingerprint/fingerprint_service.dart';
import 'package:path/path.dart' as p;

/// 桌面端指纹服务实现
///
/// 使用 fpcalc 命令行工具生成音频指纹
/// fpcalc 是 Chromaprint 官方工具，内置 FFmpeg 解码支持
class FingerprintServiceDesktop implements FingerprintService {
  FingerprintServiceDesktop._() {
    _checkAvailability();
  }

  static FingerprintServiceDesktop? _instance;

  /// 获取单例实例
  static FingerprintServiceDesktop get instance =>
      _instance ??= FingerprintServiceDesktop._();

  String? _fpcalcPath;
  bool _available = false;

  @override
  bool get isAvailable => _available;

  /// 检查 fpcalc 是否可用
  void _checkAvailability() {
    _fpcalcPath = _findFpcalc();
    _available = _fpcalcPath != null;
    if (_available) {
      debugPrint('fpcalc found at: $_fpcalcPath');
    } else {
      debugPrint('fpcalc not found. Audio fingerprinting will be unavailable.');
    }
  }

  /// 查找 fpcalc 可执行文件
  String? _findFpcalc() {
    // 首先检查应用内置的 fpcalc
    final bundledPaths = _getBundledFpcalcPaths();
    for (final path in bundledPaths) {
      if (File(path).existsSync()) {
        return path;
      }
    }

    // 然后检查系统 PATH
    final result = Process.runSync(
      Platform.isWindows ? 'where' : 'which',
      ['fpcalc'],
      runInShell: true,
    );
    if (result.exitCode == 0) {
      final path = (result.stdout as String).trim().split('\n').first;
      if (File(path).existsSync()) {
        return path;
      }
    }

    // 检查常见安装路径
    final commonPaths = _getCommonFpcalcPaths();
    for (final path in commonPaths) {
      if (File(path).existsSync()) {
        return path;
      }
    }

    return null;
  }

  /// 获取内置 fpcalc 路径
  List<String> _getBundledFpcalcPaths() {
    final executable = Platform.resolvedExecutable;
    final appDir = p.dirname(executable);

    if (Platform.isMacOS) {
      // macOS app bundle 结构
      final resourcesDir = p.join(appDir, '..', 'Resources');
      final frameworksDir = p.join(appDir, '..', 'Frameworks');
      return [
        p.join(resourcesDir, 'fpcalc'),
        p.join(frameworksDir, 'fpcalc'),
        p.join(appDir, 'fpcalc'),
      ];
    } else if (Platform.isWindows) {
      return [
        p.join(appDir, 'fpcalc.exe'),
        p.join(appDir, 'bin', 'fpcalc.exe'),
      ];
    } else if (Platform.isLinux) {
      return [
        p.join(appDir, 'fpcalc'),
        p.join(appDir, 'lib', 'fpcalc'),
        p.join(appDir, 'bin', 'fpcalc'),
      ];
    }
    return [];
  }

  /// 获取常见系统安装路径
  List<String> _getCommonFpcalcPaths() {
    if (Platform.isMacOS) {
      return [
        '/usr/local/bin/fpcalc',
        '/opt/homebrew/bin/fpcalc',
        '/usr/bin/fpcalc',
      ];
    } else if (Platform.isWindows) {
      final programFiles = Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
      final programFilesX86 = Platform.environment['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)';
      return [
        r'C:\fpcalc\fpcalc.exe',
        '$programFiles\\Chromaprint\\fpcalc.exe',
        '$programFilesX86\\Chromaprint\\fpcalc.exe',
        '$programFiles\\MusicBrainz Picard\\fpcalc.exe',
        '$programFilesX86\\MusicBrainz Picard\\fpcalc.exe',
      ];
    } else if (Platform.isLinux) {
      return [
        '/usr/bin/fpcalc',
        '/usr/local/bin/fpcalc',
        '/snap/bin/fpcalc',
      ];
    }
    return [];
  }

  @override
  Future<FingerprintData> generateFingerprint(
    String filePath, {
    int maxDuration = 120,
  }) async {
    if (!_available || _fpcalcPath == null) {
      throw FingerprintUnavailableException(appL10n.fingerprintServiceUnavailable);
    }

    // 检查文件是否存在
    if (!await File(filePath).exists()) {
      throw FingerprintGenerationException(appL10n.fingerprintAudioFileNotFound(filePath));
    }

    try {
      // 调用 fpcalc
      final result = await Process.run(
        _fpcalcPath!,
        [
          '-json', // JSON 输出格式
          '-length', maxDuration.toString(), // 最大分析时长
          filePath,
        ],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );

      if (result.exitCode != 0) {
        final stderr = result.stderr as String;
        throw FingerprintGenerationException(
          appL10n.fingerprintGenerationFailed(
            stderr.isNotEmpty ? stderr : appL10n.fingerprintGenerationUnknownError,
          ),
        );
      }

      // 解析 JSON 输出
      final stdout = result.stdout as String;
      if (stdout.trim().isEmpty) {
        throw FingerprintGenerationException(appL10n.fingerprintOutputEmpty);
      }

      final json = jsonDecode(stdout) as Map<String, dynamic>;
      final fingerprint = json['fingerprint'] as String?;
      final duration = (json['duration'] as num?)?.toInt();

      if (fingerprint == null || fingerprint.isEmpty) {
        throw FingerprintGenerationException(appL10n.fingerprintInvalid);
      }

      return FingerprintData(
        fingerprint: fingerprint,
        duration: duration ?? 0,
      );
    } on FormatException catch (e) {
      throw FingerprintGenerationException(appL10n.fingerprintParsingFailed, cause: e);
    } on ProcessException catch (e) {
      throw FingerprintGenerationException(appL10n.fingerprintExecutionFailed, cause: e);
    }
  }

  @override
  Future<FingerprintData> generateFingerprintFromStream(
    Stream<List<int>> audioStream, {
    required int sampleRate,
    required int channels,
  }) async {
    // fpcalc 不直接支持流输入
    // 如果需要此功能，应使用 FFI 实现
    throw FingerprintGenerationException(
      appL10n.fingerprintStreamNotSupported,
    );
  }

  @override
  void dispose() {
    _instance = null;
  }

  /// 手动设置 fpcalc 路径
  void setFpcalcPath(String path) {
    if (File(path).existsSync()) {
      _fpcalcPath = path;
      _available = true;
    }
  }

  /// 获取 fpcalc 版本信息
  Future<String?> getVersion() async {
    if (!_available || _fpcalcPath == null) return null;

    try {
      final result = await Process.run(_fpcalcPath!, ['-version']);
      if (result.exitCode == 0) {
        return (result.stdout as String).trim();
      }
    } on Exception {
      // ignore
    }
    return null;
  }
}
