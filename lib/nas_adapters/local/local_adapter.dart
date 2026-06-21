import 'dart:io';

import 'package:my_nas/core/constants/app_constants.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_adapter.dart';
import 'package:my_nas/nas_adapters/base/nas_connection.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/nas_adapters/local/api/local_file_api.dart';
import 'package:my_nas/nas_adapters/local/local_file_system.dart';
import 'package:my_nas/nas_adapters/mobile/file_systems/mobile_composite_file_system.dart';
import 'package:my_nas/nas_adapters/mobile/file_systems/mobile_gallery_file_system.dart';

/// 本地存储适配器
///
/// 支持访问本地文件系统，跨平台兼容：
/// - Windows: 访问所有驱动器和用户目录
/// - macOS: 访问用户目录和外接卷宗
/// - Linux: 访问用户目录和挂载点
/// - Android/iOS: 访问系统相册（照片和视频）
///
/// 注意：在移动端（iOS/Android），本适配器使用系统相册 API 访问照片和视频，
/// 而不是文件系统。这是因为移动端无法直接访问相册目录。
class LocalAdapter implements NasAdapter {
  LocalAdapter() {
    logger.i('LocalAdapter: 初始化适配器');
    _api = LocalFileApi();
  }

  late final LocalFileApi _api;
  late NasFileSystem _fileSystem;

  /// 移动端复合文件系统（用于访问相册、音乐库、文件）
  MobileCompositeFileSystem? _mobileFileSystem;

  ConnectionConfig? _config;
  ServerInfo? _serverInfo;
  bool _connected = false;

  @override
  NasAdapterInfo get info => NasAdapterInfo(
        type: NasAdapterType.local,
        name: appL10n.localAdapterName,
        version: AppConstants.appVersion,
      );

  @override
  bool get isConnected => _connected;

  @override
  ConnectionConfig? get connection => _config;

  LocalFileApi get api => _api;

  /// 获取移动端相册文件系统（用于 Live Photo 等特殊功能）
  ///
  /// 仅在移动端（iOS/Android）可用，桌面端返回 null
  MobileGalleryFileSystem? get galleryFileSystem =>
      _mobileFileSystem?.galleryFileSystem;

  /// 请求相册权限（照片/视频媒体库需要）
  ///
  /// 仅在用户将本机添加到照片或视频媒体库时调用
  /// 桌面端始终返回 true（不需要权限）
  Future<bool> requestGalleryPermission() async {
    if (_mobileFileSystem == null) return true; // 桌面端不需要权限
    return _mobileFileSystem!.requestGalleryPermission();
  }

  /// 请求音乐库权限（音乐媒体库需要）
  ///
  /// 仅在用户将本机添加到音乐媒体库时调用
  /// 桌面端始终返回 true（不需要权限）
  Future<bool> requestMusicPermission() async {
    if (_mobileFileSystem == null) return true; // 桌面端不需要权限
    return _mobileFileSystem!.requestMusicPermission();
  }

  @override
  Future<ConnectionResult> connect(ConnectionConfig config) async {
    logger.i('LocalAdapter: 开始连接本地存储');

    _config = config;

    // 移动端使用复合文件系统（相册 + 音乐库 + 文件）
    if (Platform.isIOS || Platform.isAndroid) {
      logger.i('LocalAdapter: 移动端 - 使用复合文件系统');
      _mobileFileSystem = MobileCompositeFileSystem();

      // 仅初始化，不请求权限（权限会在用户添加媒体库时按需请求）
      await _mobileFileSystem!.initialize();

      _fileSystem = _mobileFileSystem!;
    } else {
      // 桌面端使用本地文件系统
      logger.i('LocalAdapter: 桌面端 - 使用本地文件系统');
      _fileSystem = LocalFileSystem(api: _api);
    }

    _connected = true;

    // 获取系统信息
    _serverInfo = ServerInfo(
      hostname: _getHostname(),
      model: _getPlatformName(),
      version: Platform.operatingSystemVersion,
    );

    logger.i('LocalAdapter: 连接成功 - ${_serverInfo!.hostname}');

    return ConnectionSuccess(
      sessionId: 'local_${DateTime.now().millisecondsSinceEpoch}',
      serverInfo: _serverInfo,
    );
  }

  /// 获取复合文件系统（仅移动端可用）
  MobileCompositeFileSystem? get mobileFileSystem => _mobileFileSystem;

  @override
  Future<void> disconnect() async {
    if (!_connected) return;
    _connected = false;
    _config = null;
    _serverInfo = null;
    _mobileFileSystem = null;
    logger.i('LocalAdapter: 已断开连接');
  }

  @override
  Future<bool> checkConnectionHealth() async {
    // 本地存储始终可用
    if (!_connected) {
      logger.d('LocalAdapter: 连接健康检查 - 未连接');
      return false;
    }
    logger.d('LocalAdapter: 连接健康检查 - 正常');
    return true;
  }

  @override
  NasFileSystem get fileSystem {
    if (!_connected) {
      throw StateError(appL10n.localAdapterErrorNotConnected);
    }
    return _fileSystem;
  }

  @override
  MediaService? get mediaService => null;

  @override
  ToolsService? get toolsService => null;

  @override
  Future<StorageInfo?> getStorageInfo() async => null;

  @override
  Future<void> dispose() async {
    await disconnect();
  }

  String _getHostname() {
    try {
      return Platform.localHostname;
    } on Exception catch (_) {
      return '本地设备';
    }
  }

  String _getPlatformName() {
    if (Platform.isWindows) return 'Windows';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    return Platform.operatingSystem;
  }
}
