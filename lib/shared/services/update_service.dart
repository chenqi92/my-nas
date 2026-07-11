import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// 更新配置
class UpdateConfig {
  const UpdateConfig({
    this.owner = 'chenqi92',
    this.repo = 'my-nas',
    this.appStoreId,
    this.checkTimeout = const Duration(seconds: 30),
    this.downloadTimeout = const Duration(minutes: 30),
    this.maxRetries = 1,
    this.retryDelay = const Duration(seconds: 2),
  });

  /// GitHub 仓库所有者
  final String owner;

  /// GitHub 仓库名
  final String repo;

  /// App Store ID（iOS 上架后填入）
  /// 例如: '123456789'
  final String? appStoreId;

  /// 检查更新超时时间
  final Duration checkTimeout;

  /// 下载超时时间
  final Duration downloadTimeout;

  /// 最大重试次数
  final int maxRetries;

  /// 重试间隔
  final Duration retryDelay;

  /// GitHub API URL
  String get apiUrl =>
      'https://api.github.com/repos/$owner/$repo/releases/latest';

  /// GitHub Releases 页面 URL
  String get releasesUrl => 'https://github.com/$owner/$repo/releases';

  /// App Store URL
  String? get appStoreUrl =>
      appStoreId != null ? 'https://apps.apple.com/app/id$appStoreId' : null;

  /// 是否已配置 App Store
  bool get hasAppStoreConfig => appStoreId != null && appStoreId!.isNotEmpty;
}

/// 更新信息
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.releaseNotes,
    required this.releaseDate,
    required this.downloadUrl,
    required this.fileName,
    required this.fileSize,
    required this.htmlUrl,
    this.isMandatory = false,
    this.allAssets = const [],
    this.sha256,
  });

  final String version;
  final String releaseNotes;
  final DateTime releaseDate;
  final String downloadUrl;
  final String fileName;
  final int fileSize;
  final String htmlUrl;
  final bool isMandatory;
  final List<AssetInfo> allAssets;
  final String? sha256;

  String get fileSizeText {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    }
    if (fileSize < 1024 * 1024 * 1024) {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

/// 资源文件信息
class AssetInfo {
  const AssetInfo({
    required this.name,
    required this.downloadUrl,
    required this.size,
    required this.platform,
    this.architecture,
    this.sha256,
  });

  final String name;
  final String downloadUrl;
  final int size;
  final String platform;
  final String? architecture;
  final String? sha256;
}

class _UpdateContentRange {
  const _UpdateContentRange({
    required this.start,
    required this.end,
    required this.total,
  });

  final int start;
  final int end;
  final int total;
}

class _UpdateDownloadOperation {
  _UpdateDownloadOperation(this.generation);

  final int generation;
  final Completer<void> cancelled = Completer<void>();
  final Completer<void> completed = Completer<void>();
  http.Client? client;

  bool get isCancelled => cancelled.isCompleted;

  void cancel() {
    if (!cancelled.isCompleted) cancelled.complete();
    client?.close();
    client = null;
  }
}

class _UpdateDownloadCancelled implements Exception {
  const _UpdateDownloadCancelled();
}

/// 更新状态
enum UpdateStatus {
  idle,
  checking,
  available,
  notAvailable,
  downloading,
  readyToInstall,
  installing,
  error,
}

/// 更新错误类型
enum UpdateErrorType {
  network,
  timeout,
  noRelease,
  noPlatformAsset,
  downloadFailed,
  installFailed,
  cancelled,
  unknown,
}

/// 更新错误
class UpdateError {
  const UpdateError({
    required this.type,
    required this.message,
    this.originalError,
  });

  final UpdateErrorType type;
  final String message;
  final Object? originalError;

  String get userFriendlyMessage {
    switch (type) {
      case UpdateErrorType.network:
        return appL10n.updateServiceNetworkError;
      case UpdateErrorType.timeout:
        return appL10n.updateServiceTimeoutError;
      case UpdateErrorType.noRelease:
        return appL10n.updateServiceNoReleaseError;
      case UpdateErrorType.noPlatformAsset:
        return appL10n.updateServiceNoPlatformAssetError;
      case UpdateErrorType.downloadFailed:
        return appL10n.updateServiceDownloadFailedError;
      case UpdateErrorType.installFailed:
        return appL10n.updateServiceInstallFailedError;
      case UpdateErrorType.cancelled:
        return appL10n.updateServiceCancelledError;
      case UpdateErrorType.unknown:
        return message;
    }
  }
}

/// 平台架构信息
class PlatformArchitecture {
  PlatformArchitecture._();

  /// 获取当前系统架构
  static String get current {
    if (kIsWeb) return 'web';

    if (Platform.isMacOS || Platform.isIOS) {
      // macOS/iOS 通过 uname 获取架构
      final result = Process.runSync('uname', ['-m']);
      final arch = result.stdout.toString().trim().toLowerCase();
      if (arch.contains('arm64') || arch.contains('aarch64')) {
        return 'arm64';
      }
      return 'x86_64';
    }

    if (Platform.isAndroid) {
      // Android 通过系统属性获取
      // 常见架构: arm64-v8a, armeabi-v7a, x86_64, x86
      final result = Process.runSync('getprop', ['ro.product.cpu.abi']);
      final abi = result.stdout.toString().trim().toLowerCase();
      if (abi.contains('arm64') || abi.contains('v8a')) {
        return 'arm64-v8a';
      } else if (abi.contains('armeabi') || abi.contains('v7a')) {
        return 'armeabi-v7a';
      } else if (abi.contains('x86_64')) {
        return 'x86_64';
      } else if (abi.contains('x86')) {
        return 'x86';
      }
      return 'arm64-v8a'; // 默认
    }

    if (Platform.isWindows) {
      // Windows 目前主要是 x64
      final arch = Platform.environment['PROCESSOR_ARCHITECTURE'] ?? '';
      if (arch.toLowerCase().contains('arm')) {
        return 'arm64';
      }
      return 'x64';
    }

    if (Platform.isLinux) {
      final result = Process.runSync('uname', ['-m']);
      final arch = result.stdout.toString().trim().toLowerCase();
      if (arch.contains('aarch64') || arch.contains('arm64')) {
        return 'arm64';
      }
      return 'x64';
    }

    return 'unknown';
  }

  /// 获取平台名称
  static String get platformName {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }
}

/// 更新服务
class UpdateService extends ChangeNotifier {
  factory UpdateService({UpdateConfig? config}) {
    _instance ??= UpdateService._(config ?? const UpdateConfig());
    return _instance!;
  }

  UpdateService._(this._config);

  static UpdateService? _instance;

  final UpdateConfig _config;

  UpdateStatus _status = UpdateStatus.idle;
  UpdateInfo? _updateInfo;
  UpdateError? _error;
  double _downloadProgress = 0;
  String? _downloadedFilePath;
  bool _isCancelled = false;
  int _downloadGeneration = 0;
  _UpdateDownloadOperation? _activeDownload;

  // Getters
  UpdateConfig get config => _config;
  UpdateStatus get status => _status;
  UpdateInfo? get updateInfo => _updateInfo;
  UpdateError? get error => _error;
  String? get errorMessage => _error?.userFriendlyMessage;
  double get downloadProgress => _downloadProgress;
  String? get downloadedFilePath => _downloadedFilePath;
  bool get hasUpdate =>
      _status == UpdateStatus.available ||
      _status == UpdateStatus.readyToInstall;
  bool get isChecking => _status == UpdateStatus.checking;
  bool get isDownloading => _status == UpdateStatus.downloading;

  /// 检查更新（带重试机制）
  Future<void> checkForUpdates({bool silent = false}) async {
    if (_status == UpdateStatus.checking ||
        _status == UpdateStatus.downloading) {
      return;
    }

    _status = UpdateStatus.checking;
    _error = null;
    _isCancelled = false;
    notifyListeners();

    for (var attempt = 1; attempt <= _config.maxRetries; attempt++) {
      try {
        await _doCheckForUpdates();
        return; // 成功则返回
      } on Exception catch (e, st) {
        AppError.ignore(e, st, '检查更新失败 (尝试 $attempt/${_config.maxRetries})');

        if (_isCancelled) {
          _setError(
            UpdateErrorType.cancelled,
            appL10n.updateServiceCheckCancelledError,
          );
          return;
        }

        if (attempt < _config.maxRetries) {
          await Future<void>.delayed(_config.retryDelay);
        } else {
          _handleCheckError(e);
        }
      }
    }
  }

  Future<void> _doCheckForUpdates() async {
    final response = await http
        .get(
          Uri.parse(_config.apiUrl),
          headers: {'Accept': 'application/vnd.github.v3+json'},
        )
        .timeout(_config.checkTimeout);

    if (response.statusCode == 404) {
      throw Exception(appL10n.updateServiceNoReleaseError);
    }

    if (response.statusCode != 200) {
      throw Exception(appL10n.updateServiceGithubApiError(response.statusCode));
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final tagName = (data['tag_name'] as String).replaceFirst('v', '');
    final (latestVersion, latestBuild) = _parseVersion(tagName);

    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;
    final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 1;

    logger.i(
      'UpdateService: 当前版本 $currentVersion+$currentBuild, '
      '最新版本 $latestVersion+$latestBuild',
    );

    if (_isNewerVersion(
      latestVersion,
      latestBuild,
      currentVersion,
      currentBuild,
    )) {
      final assets = data['assets'] as List<dynamic>;
      final allAssets = _parseAllAssets(assets);
      final asset = _findBestPlatformAsset(assets);

      if (asset != null) {
        final expectedSha256 = await _resolveSha256ForAsset(asset, assets);
        final displayVersion = latestBuild > 1
            ? '$latestVersion (build $latestBuild)'
            : latestVersion;

        _updateInfo = UpdateInfo(
          version: displayVersion,
          releaseNotes:
              data['body'] as String? ??
              appL10n.updateServiceNoReleaseNotesDefault,
          releaseDate: DateTime.parse(data['published_at'] as String),
          downloadUrl: asset['browser_download_url'] as String,
          fileName: asset['name'] as String,
          fileSize: asset['size'] as int,
          htmlUrl: data['html_url'] as String? ?? _config.releasesUrl,
          allAssets: allAssets,
          sha256: expectedSha256,
        );
        _status = UpdateStatus.available;
        logger.i('UpdateService: 发现新版本 $displayVersion');
      } else if (Platform.isIOS) {
        // iOS 没有安装包时，仍然显示有更新（引导到 App Store 或 GitHub）
        final displayVersion = latestBuild > 1
            ? '$latestVersion (build $latestBuild)'
            : latestVersion;

        _updateInfo = UpdateInfo(
          version: displayVersion,
          releaseNotes:
              data['body'] as String? ??
              appL10n.updateServiceNoReleaseNotesDefault,
          releaseDate: DateTime.parse(data['published_at'] as String),
          downloadUrl: '',
          fileName: '',
          fileSize: 0,
          htmlUrl: data['html_url'] as String? ?? _config.releasesUrl,
          allAssets: allAssets,
        );
        _status = UpdateStatus.available;
        logger.i('UpdateService: iOS 发现新版本 $displayVersion (无直接下载)');
      } else {
        _status = UpdateStatus.notAvailable;
        _setError(
          UpdateErrorType.noPlatformAsset,
          appL10n.updateServiceNoPlatformAssetDetailError(
            '${PlatformArchitecture.platformName}-${PlatformArchitecture.current}',
          ),
        );
        logger.w('UpdateService: 未找到当前平台的安装包');
      }
    } else {
      _status = UpdateStatus.notAvailable;
      logger.i('UpdateService: 当前已是最新版本');
    }

    notifyListeners();
  }

  /// 解析所有资源文件
  List<AssetInfo> _parseAllAssets(List<dynamic> assets) {
    final result = <AssetInfo>[];
    for (final asset in assets) {
      if (asset is! Map<String, dynamic>) continue;
      final name = (asset['name'] as String).toLowerCase();
      final (platform, arch) = _detectPlatformFromName(name);
      result.add(
        AssetInfo(
          name: asset['name'] as String,
          downloadUrl: asset['browser_download_url'] as String,
          size: asset['size'] as int,
          platform: platform,
          architecture: arch,
          sha256: _sha256FromAsset(asset),
        ),
      );
    }
    return result;
  }

  String? _sha256FromAsset(Map<String, dynamic> asset) {
    final digest = asset['digest'] as String?;
    if (digest == null || digest.isEmpty) return null;

    final normalized = digest.trim().toLowerCase();
    final value = normalized.startsWith('sha256:')
        ? normalized.substring('sha256:'.length)
        : normalized;
    return _isSha256(value) ? value : null;
  }

  Future<String?> _resolveSha256ForAsset(
    Map<String, dynamic> asset,
    List<dynamic> assets,
  ) async {
    final inlineDigest = _sha256FromAsset(asset);
    if (inlineDigest != null) return inlineDigest;

    final checksumAsset = _findChecksumAsset(asset, assets);
    if (checksumAsset == null) return null;

    try {
      final response = await http
          .get(Uri.parse(checksumAsset['browser_download_url'] as String))
          .timeout(_config.checkTimeout);
      if (response.statusCode != 200) return null;
      return _parseChecksumText(response.body, asset['name'] as String? ?? '');
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'UpdateService: 下载校验文件失败');
      return null;
    }
  }

  Map<String, dynamic>? _findChecksumAsset(
    Map<String, dynamic> targetAsset,
    List<dynamic> assets,
  ) {
    final targetName = (targetAsset['name'] as String? ?? '').toLowerCase();
    if (targetName.isEmpty) return null;

    final exactNames = {
      '$targetName.sha256',
      '$targetName.sha256sum',
      '$targetName.sha256.txt',
    };

    Map<String, dynamic>? fallback;
    for (final asset in assets) {
      if (asset is! Map<String, dynamic>) continue;
      final name = (asset['name'] as String? ?? '').toLowerCase();
      if (exactNames.contains(name)) return asset;
      if (name.contains('sha256') ||
          name.contains('checksum') ||
          name.contains('checksums')) {
        fallback ??= asset;
      }
    }
    return fallback;
  }

  String? _parseChecksumText(String text, String targetFileName) {
    final target = targetFileName.toLowerCase();
    final hashPattern = RegExp(r'\b[a-fA-F0-9]{64}\b');
    final lines = text.split(RegExp(r'[\r\n]+'));

    for (final line in lines) {
      final hash = hashPattern.firstMatch(line)?.group(0)?.toLowerCase();
      if (hash == null) continue;
      if (target.isEmpty || line.toLowerCase().contains(target)) {
        return hash;
      }
    }

    final trimmed = text.trim().toLowerCase();
    return _isSha256(trimmed) ? trimmed : null;
  }

  bool _isSha256(String value) =>
      RegExp(r'^[a-f0-9]{64}$').hasMatch(value.toLowerCase());

  /// 从文件名检测平台和架构
  (String platform, String? arch) _detectPlatformFromName(String name) {
    if (name.contains('android')) {
      if (name.contains('arm64') || name.contains('v8a')) {
        return ('android', 'arm64-v8a');
      } else if (name.contains('armeabi') || name.contains('v7a')) {
        return ('android', 'armeabi-v7a');
      } else if (name.contains('x86_64')) {
        return ('android', 'x86_64');
      } else if (name.contains('universal')) {
        return ('android', 'universal');
      }
      return ('android', null);
    }

    if (name.contains('ios') || name.contains('.ipa')) {
      return ('ios', 'arm64');
    }

    if (name.contains('macos') || name.contains('darwin')) {
      if (name.contains('arm64')) {
        return ('macos', 'arm64');
      } else if (name.contains('x86_64') || name.contains('intel')) {
        return ('macos', 'x86_64');
      }
      return ('macos', null);
    }

    if (name.contains('windows') ||
        name.contains('win64') ||
        name.contains('win32')) {
      if (name.contains('arm64')) {
        return ('windows', 'arm64');
      }
      return ('windows', 'x64');
    }

    if (name.contains('linux')) {
      if (name.contains('arm64') || name.contains('aarch64')) {
        return ('linux', 'arm64');
      }
      return ('linux', 'x64');
    }

    return ('unknown', null);
  }

  /// 查找当前平台的最佳安装包
  Map<String, dynamic>? _findBestPlatformAsset(List<dynamic> assets) {
    final platform = PlatformArchitecture.platformName;
    final arch = PlatformArchitecture.current;

    logger.d('UpdateService: 查找平台资源 platform=$platform, arch=$arch');

    // 获取平台特定的文件模式和优先级
    final patterns = _getPlatformPatterns(platform, arch);

    // 按优先级查找
    for (final pattern in patterns) {
      for (final asset in assets) {
        if (asset is! Map<String, dynamic>) continue;
        final name = (asset['name'] as String).toLowerCase();
        if (name.contains(pattern)) {
          logger.d('UpdateService: 找到匹配资源 $name (pattern: $pattern)');
          return asset;
        }
      }
    }

    return null;
  }

  /// 获取平台特定的文件名模式（按优先级排序）
  List<String> _getPlatformPatterns(String platform, String arch) {
    switch (platform) {
      case 'android':
        // Android 优先精确匹配架构，然后是通用包
        return [
          'android-$arch',
          arch, // arm64-v8a, armeabi-v7a, x86_64
          'android-universal',
          'universal',
          'android',
          '.apk',
        ];

      case 'macos':
        // macOS 优先匹配架构
        if (arch == 'arm64') {
          return [
            'macos-arm64',
            'darwin-arm64',
            'apple-silicon',
            '-arm64.dmg',
            '-arm64.zip',
            'macos',
            'darwin',
            '.dmg',
          ];
        } else {
          return [
            'macos-x86_64',
            'macos-intel',
            'darwin-x86_64',
            '-x86_64.dmg',
            '-x86_64.zip',
            'macos',
            'darwin',
            '.dmg',
          ];
        }

      case 'windows':
        // Windows 优先 EXE 安装包
        return [
          'windows-x64-setup',
          '-setup.exe',
          'windows-x64',
          'windows',
          'win64',
          '.exe',
          '.msix',
        ];

      case 'linux':
        if (arch == 'arm64') {
          return [
            'linux-arm64',
            'linux-aarch64',
            '-arm64.tar.gz',
            '-arm64.appimage',
            '-arm64.deb',
          ];
        } else {
          return [
            'linux-x64',
            'linux-x86_64',
            '-x64.tar.gz',
            '-x64.appimage',
            '-x64.deb',
            'linux',
            '.appimage',
            '.deb',
            '.tar.gz',
          ];
        }

      case 'ios':
        // iOS 不支持侧载，返回空
        return [];

      default:
        return [];
    }
  }

  void _handleCheckError(Exception e) {
    if (e is TimeoutException) {
      _setError(UpdateErrorType.timeout, appL10n.updateServiceTimeoutError);
    } else if (e is SocketException) {
      _setError(UpdateErrorType.network, appL10n.updateServiceNetworkError);
    } else if (e.toString().contains('未找到发布版本')) {
      _setError(UpdateErrorType.noRelease, appL10n.updateServiceNoReleaseError);
    } else {
      _setError(UpdateErrorType.unknown, e.toString());
    }
    notifyListeners();
  }

  void _setError(UpdateErrorType type, String message) {
    _error = UpdateError(type: type, message: message);
    _status = UpdateStatus.error;
  }

  /// 下载更新（带重试和断点续传支持）
  Future<void> downloadUpdate() async {
    if (_updateInfo == null) {
      return;
    }

    final previousOperation = _activeDownload;
    if (previousOperation != null) {
      if (_status == UpdateStatus.downloading) return;
      await previousOperation.completed.future;
      if (_updateInfo == null || _status == UpdateStatus.downloading) return;
    }

    if (_updateInfo!.downloadUrl.isEmpty) {
      _setError(
        UpdateErrorType.downloadFailed,
        appL10n.updateServiceNoDownloadLinkError,
      );
      notifyListeners();
      return;
    }

    final operation = _UpdateDownloadOperation(++_downloadGeneration);
    _activeDownload = operation;

    _status = UpdateStatus.downloading;
    _downloadProgress = 0;
    _error = null;
    _isCancelled = false;
    notifyListeners();

    try {
      for (var attempt = 1; attempt <= _config.maxRetries; attempt++) {
        try {
          _ensureActiveDownload(operation);
          await _doDownloadUpdate(operation);
          return;
        } on Exception catch (e, st) {
          if (!_isActiveDownload(operation) || e is _UpdateDownloadCancelled) {
            AppError.ignore(e, st, '用户取消下载更新');
            return;
          }

          // 最后一次重试失败时上报错误
          if (attempt >= _config.maxRetries) {
            AppError.handle(e, st, 'downloadUpdate', {'attempt': attempt});
            _setError(
              UpdateErrorType.downloadFailed,
              appL10n.updateServiceDownloadFailedWithCodeError(e),
            );
            notifyListeners();
          } else {
            AppError.ignore(
              e,
              st,
              '下载失败，重试中 (尝试 $attempt/${_config.maxRetries})',
            );
            await Future.any<void>([
              Future<void>.delayed(_config.retryDelay),
              operation.cancelled.future,
            ]);
            _ensureActiveDownload(operation);
          }
        }
      }
    } on _UpdateDownloadCancelled {
      return;
    } finally {
      operation.client?.close();
      operation.client = null;
      if (identical(_activeDownload, operation)) _activeDownload = null;
      if (!operation.completed.isCompleted) operation.completed.complete();
    }
  }

  bool _isActiveDownload(_UpdateDownloadOperation operation) =>
      identical(_activeDownload, operation) &&
      operation.generation == _downloadGeneration &&
      !operation.isCancelled;

  void _ensureActiveDownload(_UpdateDownloadOperation operation) {
    if (!_isActiveDownload(operation)) throw const _UpdateDownloadCancelled();
  }

  Future<void> _doDownloadUpdate(_UpdateDownloadOperation operation) async {
    final info = _updateInfo!;
    final request = http.Request('GET', Uri.parse(_updateInfo!.downloadUrl));

    // 检查是否有已下载的部分（断点续传）
    final dir = await _getDownloadDirectory();
    _ensureActiveDownload(operation);
    final file = File('${dir.path}/${info.fileName}');
    var existingLength = 0;

    if (await file.exists()) {
      _ensureActiveDownload(operation);
      existingLength = await file.length();
      _ensureActiveDownload(operation);
      final mayBeComplete = info.fileSize > 0
          ? existingLength >= info.fileSize
          : existingLength > 0;
      if (mayBeComplete) {
        try {
          await _verifyDownloadedUpdate(file, info);
          _ensureActiveDownload(operation);
          _downloadedFilePath = file.path;
          _status = UpdateStatus.readyToInstall;
          _downloadProgress = 1.0;
          logger.i('UpdateService: 文件已存在且校验通过 ${file.path}');
          return;
        } on Exception catch (e, st) {
          _ensureActiveDownload(operation);
          AppError.ignore(e, st, 'UpdateService: 删除校验失败的旧更新包');
          await _deleteUpdateFile(file);
          _ensureActiveDownload(operation);
          existingLength = 0;
        }
      }

      if (existingLength > 0) {
        request.headers['Range'] = 'bytes=$existingLength-';
        logger.i('UpdateService: 断点续传从 $existingLength 字节开始');
      }
    }

    final client = http.Client();
    operation.client = client;
    var timedOut = false;
    final timeoutTimer = Timer(_config.downloadTimeout, () {
      if (!_isActiveDownload(operation)) return;
      timedOut = true;
      client.close();
    });

    try {
      final response = await client.send(request);
      _ensureActiveDownload(operation);

      if (response.statusCode != 200 && response.statusCode != 206) {
        throw Exception(
          appL10n.updateServiceDownloadFailedWithStatusError(
            response.statusCode,
          ),
        );
      }

      _UpdateContentRange? contentRange;
      if (response.statusCode == 206) {
        final contentRangeValue = response.headers['content-range'];
        contentRange = _parseUpdateContentRange(contentRangeValue);
        final expectedLength = contentRange == null
            ? null
            : contentRange.end - contentRange.start + 1;
        final validRange =
            contentRange != null &&
            contentRange.start == existingLength &&
            (info.fileSize <= 0 || contentRange.total == info.fileSize) &&
            (response.contentLength == null ||
                response.contentLength == expectedLength);
        if (!validRange) {
          await _deleteUpdateFile(file);
          _ensureActiveDownload(operation);
          throw FormatException(
            'Invalid Content-Range for offset $existingLength: '
            '$contentRangeValue',
          );
        }
      } else if (existingLength > 0) {
        // 服务器忽略 Range：覆盖旧文件，从 0 开始计算进度。
        existingLength = 0;
      }

      final isResuming = response.statusCode == 206 && existingLength > 0;
      final totalSize = info.fileSize > 0
          ? info.fileSize
          : contentRange?.total ?? response.contentLength ?? 0;
      final sink = file.openWrite(
        mode: isResuming ? FileMode.append : FileMode.write,
      );
      var received = isResuming ? existingLength : 0;

      try {
        await for (final chunk in response.stream) {
          _ensureActiveDownload(operation);
          sink.add(chunk);
          received += chunk.length;
          if (totalSize > 0) {
            _downloadProgress = (received / totalSize).clamp(0.0, 1.0);
          }
          notifyListeners();
        }
      } finally {
        await sink.close();
      }
      _ensureActiveDownload(operation);
      if (timedOut) {
        throw TimeoutException(
          'Update download timed out after ${_config.downloadTimeout}',
        );
      }
    } catch (e) {
      if (!_isActiveDownload(operation)) {
        throw const _UpdateDownloadCancelled();
      }
      if (timedOut) {
        throw TimeoutException(
          'Update download timed out after ${_config.downloadTimeout}',
        );
      }
      rethrow;
    } finally {
      timeoutTimer.cancel();
      client.close();
      if (identical(operation.client, client)) operation.client = null;
    }

    try {
      _ensureActiveDownload(operation);
      await _verifyDownloadedUpdate(file, info);
      _ensureActiveDownload(operation);
    } on Exception {
      _ensureActiveDownload(operation);
      await _deleteUpdateFile(file);
      _ensureActiveDownload(operation);
      rethrow;
    }
    _downloadedFilePath = file.path;
    _status = UpdateStatus.readyToInstall;
    _downloadProgress = 1.0;
    logger.i('UpdateService: 下载完成 ${file.path}');
    notifyListeners();
  }

  _UpdateContentRange? _parseUpdateContentRange(String? value) {
    if (value == null) return null;
    final match = RegExp(
      r'^bytes\s+(\d+)-(\d+)/(\d+)$',
      caseSensitive: false,
    ).firstMatch(value.trim());
    if (match == null) return null;

    final start = int.tryParse(match.group(1)!);
    final end = int.tryParse(match.group(2)!);
    final total = int.tryParse(match.group(3)!);
    if (start == null ||
        end == null ||
        total == null ||
        end < start ||
        total <= end) {
      return null;
    }
    return _UpdateContentRange(start: start, end: end, total: total);
  }

  Future<void> _deleteUpdateFile(File file) async {
    if (await file.exists()) await file.delete();
  }

  Future<void> _verifyDownloadedUpdate(File file, UpdateInfo info) async {
    final actualLength = await file.length();
    if (info.fileSize > 0 && actualLength != info.fileSize) {
      throw Exception('更新包大小不匹配，期望 ${info.fileSize} 字节，实际 $actualLength 字节');
    }

    final expectedSha256 = info.sha256?.trim().toLowerCase();
    if (expectedSha256 == null || expectedSha256.isEmpty) {
      throw Exception('更新包缺少 SHA-256 校验信息，已拒绝安装');
    }
    if (!_isSha256(expectedSha256)) {
      throw Exception('更新包 SHA-256 校验信息无效，已拒绝安装');
    }

    final actualSha256 = await _calculateFileSha256(file);
    if (actualSha256 != expectedSha256) {
      throw Exception('更新包 SHA-256 校验失败，已拒绝安装');
    }
  }

  Future<String> _calculateFileSha256(File file) async {
    final digest = await crypto.sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  /// 取消下载
  void cancelDownload() {
    _isCancelled = true;
    _downloadGeneration++;
    _activeDownload?.cancel();
    _status = UpdateStatus.available;
    _downloadProgress = 0;
    notifyListeners();
  }

  /// 安装更新
  Future<bool> installUpdate() async {
    if (_downloadedFilePath == null) return false;

    final downloadedFile = File(_downloadedFilePath!);
    try {
      final info = _updateInfo;
      if (info == null) throw StateError('Missing update info');
      await _verifyDownloadedUpdate(downloadedFile, info);
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'verifyUpdateBeforeInstall', {
        'filePath': _downloadedFilePath,
      });
      try {
        await _deleteUpdateFile(downloadedFile);
      } on Exception catch (deleteError, deleteStack) {
        AppError.ignore(deleteError, deleteStack, '删除校验失败的更新包失败');
      }
      _downloadedFilePath = null;
      _setError(
        UpdateErrorType.downloadFailed,
        appL10n.updateServiceDownloadFailedWithCodeError(e),
      );
      notifyListeners();
      return false;
    }

    _status = UpdateStatus.installing;
    notifyListeners();

    try {
      bool success;
      if (Platform.isWindows) {
        success = await _installWindows();
      } else if (Platform.isMacOS) {
        success = await _installMacOS();
      } else if (Platform.isLinux) {
        success = await _installLinux();
      } else if (Platform.isAndroid) {
        success = await _installAndroid();
      } else {
        success = false;
      }

      if (!success) {
        _status = UpdateStatus.readyToInstall;
      }

      return success;
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'installUpdate', {
        'filePath': _downloadedFilePath,
      });
      _setError(
        UpdateErrorType.installFailed,
        appL10n.updateServiceInstallFailedWithErrorError(e),
      );
      _status = UpdateStatus.readyToInstall;
      notifyListeners();
      return false;
    }
  }

  /// Windows 安装
  Future<bool> _installWindows() async {
    final file = _downloadedFilePath!;

    if (file.endsWith('.exe')) {
      // 运行安装程序
      await Process.start(file, [], mode: ProcessStartMode.detached);
      exit(0);
    } else if (file.endsWith('.msix') || file.endsWith('.msixbundle')) {
      // MSIX 安装
      final result = await Process.run('powershell', [
        '-Command',
        'Add-AppxPackage',
        '-Path',
        file,
      ]);
      return result.exitCode == 0;
    } else if (file.endsWith('.zip')) {
      // 便携版 - 打开文件夹让用户手动替换
      await Process.run('explorer', ['/select,', file]);
      return true;
    }
    return false;
  }

  /// macOS 安装
  Future<bool> _installMacOS() async {
    final file = _downloadedFilePath!;

    if (file.endsWith('.dmg')) {
      // 挂载 DMG 并打开
      await Process.run('open', [file]);
      return true;
    } else if (file.endsWith('.zip')) {
      // 打开 Finder
      await Process.run('open', ['-R', file]);
      return true;
    }
    return false;
  }

  /// Linux 安装
  Future<bool> _installLinux() async {
    final file = _downloadedFilePath!;

    if (file.endsWith('.deb')) {
      // Debian/Ubuntu - 使用 pkexec 提权
      final result = await Process.run('pkexec', ['dpkg', '-i', file]);
      return result.exitCode == 0;
    } else if (file.toLowerCase().endsWith('.appimage')) {
      // 设置执行权限并运行
      await Process.run('chmod', ['+x', file]);
      await Process.start(file, [], mode: ProcessStartMode.detached);
      exit(0);
    } else if (file.endsWith('.tar.gz')) {
      // 打开文件管理器
      await Process.run('xdg-open', [File(file).parent.path]);
      return true;
    }
    return false;
  }

  /// Android 安装
  Future<bool> _installAndroid() async {
    final file = _downloadedFilePath!;

    if (file.endsWith('.apk')) {
      // 使用 open_filex 打开 APK 文件进行安装
      final result = await OpenFilex.open(file);
      logger.i(
        'UpdateService: Android 安装结果 ${result.type} - ${result.message}',
      );
      return result.type == ResultType.done;
    }
    return false;
  }

  /// 解析版本号（支持格式：0.1.5 或 0.1.5-build.2）
  (String version, int build) _parseVersion(String tagVersion) {
    if (tagVersion.contains('-build.')) {
      final parts = tagVersion.split('-build.');
      final version = parts[0];
      final build = int.tryParse(parts[1]) ?? 1;
      return (version, build);
    }
    return (tagVersion, 1);
  }

  /// 比较版本号（包含 build number）
  bool _isNewerVersion(
    String latestVersion,
    int latestBuild,
    String currentVersion,
    int currentBuild,
  ) {
    final latestParts = latestVersion
        .split('.')
        .map((p) => int.tryParse(p) ?? 0)
        .toList();
    final currentParts = currentVersion
        .split('.')
        .map((p) => int.tryParse(p) ?? 0)
        .toList();

    // 首先比较主版本号
    for (var i = 0; i < latestParts.length && i < currentParts.length; i++) {
      if (latestParts[i] > currentParts[i]) return true;
      if (latestParts[i] < currentParts[i]) return false;
    }

    // 如果主版本号长度不同
    if (latestParts.length != currentParts.length) {
      return latestParts.length > currentParts.length;
    }

    // 主版本号相同，比较 build number
    return latestBuild > currentBuild;
  }

  /// 获取下载目录
  Future<Directory> _getDownloadDirectory() async {
    if (Platform.isAndroid) {
      // Android 使用外部存储的 Download 目录
      final dir = await getExternalStorageDirectory();
      if (dir != null) {
        final downloadDir = Directory(
          '${dir.parent.parent.parent.parent.path}/Download',
        );
        if (await downloadDir.exists()) {
          return downloadDir;
        }
      }
      return getApplicationDocumentsDirectory();
    } else if (Platform.isIOS) {
      return getApplicationDocumentsDirectory();
    } else {
      // 桌面平台使用下载文件夹
      final dir = await getDownloadsDirectory();
      return dir ?? await getApplicationDocumentsDirectory();
    }
  }

  /// 重置状态
  void reset() {
    _isCancelled = true;
    _downloadGeneration++;
    _activeDownload?.cancel();
    _status = UpdateStatus.idle;
    _updateInfo = null;
    _error = null;
    _downloadProgress = 0;
    _downloadedFilePath = null;
    _isCancelled = false;
    notifyListeners();
  }

  /// 清理下载的文件
  Future<void> cleanUp() async {
    if (_downloadedFilePath != null) {
      try {
        final file = File(_downloadedFilePath!);
        if (await file.exists()) {
          await file.delete();
        }
      } on Exception catch (e, st) {
        AppError.ignore(e, st, '清理下载文件失败');
      }
      _downloadedFilePath = null;
    }
  }

  /// 获取当前平台和架构信息
  static String getPlatformInfo() =>
      '${PlatformArchitecture.platformName}-${PlatformArchitecture.current}';
}
