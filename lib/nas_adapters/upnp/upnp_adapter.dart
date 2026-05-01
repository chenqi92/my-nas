import 'dart:async';

import 'package:my_nas/core/constants/app_constants.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_adapter.dart';
import 'package:my_nas/nas_adapters/base/nas_connection.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/nas_adapters/upnp/upnp_content_directory_client.dart';
import 'package:my_nas/nas_adapters/upnp/upnp_device_description.dart';
import 'package:my_nas/nas_adapters/upnp/upnp_file_system.dart';

/// UPnP / DLNA NAS 适配器
///
/// 把 UPnP MediaServer 当作只读 NAS 源使用：
/// 1. 抓 [ConnectionConfig.host:port]/rootDesc.xml（路径可由 username 字段覆盖）
///    解析出 ContentDirectory 服务的 controlURL
/// 2. 通过 SOAP Browse 调用列目录、拿直链 URL
/// 3. 直接 HTTP GET res URL 流式读取媒体文件
///
/// 实现限制：
/// - 仅支持只读浏览（多数 MediaServer 不允许写）
/// - 不做 SSDP 自动发现——用户需在 host/port 中明确填入服务器地址
/// - 不支持 username/password 认证（标准 UPnP 协议无 HTTP Auth；如服务器特殊
///   要求，可后续扩展）
class UpnpAdapter implements NasAdapter {
  UpnpAdapter() {
    logger.i('UpnpAdapter: 初始化适配器');
  }

  UpnpDeviceFetcher? _fetcher;
  UpnpContentDirectoryClient? _client;
  UpnpFileSystem? _fileSystem;
  UpnpDeviceDescription? _description;
  ConnectionConfig? _config;
  bool _connected = false;

  @override
  NasAdapterInfo get info => NasAdapterInfo(
        type: NasAdapterType.upnp,
        name: 'UPnP / DLNA',
        version: AppConstants.appVersion,
      );

  @override
  bool get isConnected => _connected;

  @override
  ConnectionConfig? get connection => _config;

  @override
  Future<ConnectionResult> connect(ConnectionConfig config) async {
    logger
      ..i('UpnpAdapter: 开始连接')
      ..i('UpnpAdapter: 目标地址 => ${config.host}:${config.port}');

    _config = config;

    try {
      // 设备描述 URL：
      //   - username 字段非空 → 当作描述文档路径（如 "rootDesc.xml" 或完整 URL）
      //   - 否则用默认 "rootDesc.xml"
      final descPath = config.username.isNotEmpty ? config.username : 'rootDesc.xml';
      final descriptionUrl = descPath.startsWith('http')
          ? descPath
          : '${config.useSsl ? 'https' : 'http'}://${config.host}:${config.port == 0 ? 8200 : config.port}/${descPath.startsWith('/') ? descPath.substring(1) : descPath}';

      _fetcher = UpnpDeviceFetcher();
      _description = await _fetcher!.fetch(descriptionUrl);

      _client = UpnpContentDirectoryClient(
        controlUrl: _description!.contentDirectoryControlUrl,
      );
      _fileSystem = UpnpFileSystem(client: _client!);

      // 探活：浏览根容器
      await _client!.browse('0', requestedCount: 1);

      _connected = true;
      logger.i('UpnpAdapter: 连接成功 → ${_description!.friendlyName}');

      return ConnectionSuccess(
        sessionId: 'upnp-${DateTime.now().millisecondsSinceEpoch}',
        serverInfo: ServerInfo(
          hostname: config.host,
          model: _description!.modelName ?? 'UPnP MediaServer',
        ),
      );
    } on Exception catch (e) {
      logger.e('UpnpAdapter: 连接失败', e);
      _connected = false;
      await _cleanup();
      return ConnectionFailure(error: e.toString());
    }
  }

  Future<void> _cleanup() async {
    try {
      await _fileSystem?.dispose();
    } on Exception catch (e) {
      logger.w('UpnpAdapter: dispose fileSystem 出错', e);
    }
    _fetcher?.dispose();
    _fileSystem = null;
    _client = null;
    _fetcher = null;
    _description = null;
  }

  @override
  Future<void> disconnect() async {
    if (!_connected) return;
    await _cleanup();
    _connected = false;
    _config = null;
    logger.i('UpnpAdapter: 已断开连接');
  }

  @override
  Future<bool> checkConnectionHealth() async {
    if (!_connected || _client == null) return false;
    try {
      await _client!.browse('0', requestedCount: 1).timeout(
            const Duration(seconds: 5),
            onTimeout: () => throw Exception('健康检查超时'),
          );
      return true;
    } on Exception catch (e) {
      logger.w('UpnpAdapter: 连接健康检查失败', e);
      _connected = false;
      return false;
    }
  }

  @override
  NasFileSystem get fileSystem {
    if (!_connected || _fileSystem == null) {
      throw StateError('未连接到 UPnP MediaServer');
    }
    return _fileSystem!;
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
}
