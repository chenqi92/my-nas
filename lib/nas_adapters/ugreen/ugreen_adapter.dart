import 'package:my_nas/core/constants/app_constants.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/network/dio_client.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_adapter.dart';
import 'package:my_nas/nas_adapters/base/nas_connection.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/nas_adapters/ugreen/api/ugreen_api.dart';
import 'package:my_nas/nas_adapters/ugreen/ugreen_file_system.dart';
import 'package:my_nas/nas_adapters/webdav/webdav_file_system.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;

/// 绿联 NAS 适配器
///
/// 使用 UGOS API 进行认证，文件操作优先使用 UGOS API，
/// 如果失败则回退到 WebDAV。
class UGreenAdapter implements NasAdapter {
  UGreenAdapter() {
    logger.i('UGreenAdapter: 初始化适配器');
    _dioClient = DioClient();
    _api = UGreenApi(dio: _dioClient.dio);
  }

  late final DioClient _dioClient;
  late final UGreenApi _api;
  NasFileSystem? _fileSystem;
  webdav.Client? _webdavClient;

  ConnectionConfig? _config;
  ServerInfo? _serverInfo;
  bool _connected = false;
  bool _useWebDav = false;

  @override
  NasAdapterInfo get info => NasAdapterInfo(
    type: NasAdapterType.ugreen,
    name: appL10n.ugreenAdapterName,
    version: AppConstants.appVersion,
  );

  @override
  bool get isConnected => _connected;

  @override
  ConnectionConfig? get connection => _config;

  UGreenApi get api => _api;

  @override
  Future<ConnectionResult> connect(ConnectionConfig config) async {
    logger
      ..i('UGreenAdapter: 开始连接')
      ..i('UGreenAdapter: 目标地址 => ${config.baseUrl}')
      ..i('UGreenAdapter: 用户名 => ${config.username}')
      ..i('UGreenAdapter: 使用 SSL => ${config.useSsl}');

    _config = config;
    _dioClient
      ..updateBaseUrl(config.baseUrl)
      ..setAllowSelfSignedCert(allow: !config.verifySSL);
    if (!config.verifySSL) {
      logger.i('UGreenAdapter: 跳过 SSL 证书验证');
    }

    // 尝试登录
    logger.i('UGreenAdapter: 开始登录认证...');
    final authResult = await _api.login(
      username: config.username,
      password: config.password,
    );

    logger.i('UGreenAdapter: 登录结果 => ${authResult.runtimeType}');

    return switch (authResult) {
      UGreenAuthSuccess(:final token) => await _handleLoginSuccess(
        config,
        token,
      ),
      UGreenAuthFailure(:final error) => () {
        logger.e('UGreenAdapter: 登录失败 => $error');
        return ConnectionFailure(error: error);
      }(),
      UGreenAuthRequires2FA() => () {
        logger.i('UGreenAdapter: 需要二次验证');
        return const ConnectionRequires2FA(methods: [TwoFactorMethod.totp]);
      }(),
    };
  }

  /// 二次验证
  Future<ConnectionResult> verify2FA(
    String otpCode, {
    bool rememberDevice = false,
  }) async {
    if (_config == null) {
      return ConnectionFailure(error: appL10n.ugreenConnectNotCalledError);
    }

    final authResult = await _api.login(
      username: _config!.username,
      password: _config!.password,
      otpCode: otpCode,
    );

    return switch (authResult) {
      UGreenAuthSuccess(:final token) => await _handleLoginSuccess(
        _config!,
        token,
      ),
      UGreenAuthFailure(:final error) => ConnectionFailure(error: error),
      UGreenAuthRequires2FA() => ConnectionFailure(
        error: appL10n.ugreen2FAVerifyFailedError,
      ),
    };
  }

  Future<ConnectionResult> _handleLoginSuccess(
    ConnectionConfig config,
    String token,
  ) async {
    _connected = true;

    // 获取服务器信息
    try {
      final deviceInfo = await _api.getDeviceInfo();
      _serverInfo = ServerInfo(
        hostname: deviceInfo.hostname,
        model: deviceInfo.model,
        version: deviceInfo.version,
        serial: deviceInfo.serial,
      );
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '获取设备信息失败不影响连接');
    }

    // 测试 UGOS 文件 API 是否可用
    _useWebDav = false;
    try {
      logger.i('UGreenAdapter: 测试 UGOS 文件 API...');
      final shares = await _api.listShares();
      if (shares.isNotEmpty) {
        logger.i('UGreenAdapter: UGOS 文件 API 可用，找到 ${shares.length} 个共享文件夹');
        _fileSystem = UGreenFileSystem(api: _api);
      } else {
        // 可能 API 返回空，尝试列出根目录
        final rootFiles = await _api.listDirectory('/');
        if (rootFiles.isNotEmpty) {
          logger.i('UGreenAdapter: UGOS 文件 API 可用');
          _fileSystem = UGreenFileSystem(api: _api);
        } else {
          logger.w('UGreenAdapter: UGOS 文件 API 返回空，切换到 WebDAV');
          _useWebDav = true;
        }
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'UGOS 文件 API 不可用，切换到 WebDAV');
      _useWebDav = true;
    }

    // 如果 UGOS API 不可用，初始化 WebDAV
    if (_useWebDav) {
      try {
        await _initWebDav(config);
      } on Exception catch (e, st) {
        AppError.handle(e, st, 'UGreenAdapter._initWebDav');
        // 仍然标记为已连接，但文件操作可能失败
      }
    }

    return ConnectionSuccess(sessionId: token, serverInfo: _serverInfo);
  }

  /// 初始化 WebDAV 客户端
  Future<void> _initWebDav(ConnectionConfig config) async {
    logger.i('UGreenAdapter: 初始化 WebDAV 连接...');

    // 绿联 UGOS WebDAV 路径通常是 /webdav 或 /dav
    final webdavPaths = ['/webdav', '/dav', '/'];
    final scheme = config.useSsl ? 'https' : 'http';

    for (final davPath in webdavPaths) {
      try {
        final webdavUrl = '$scheme://${config.host}:${config.port}$davPath';
        logger.d('UGreenAdapter: 尝试 WebDAV => $webdavUrl');

        _webdavClient = webdav.newClient(
          webdavUrl,
          user: config.username,
          password: config.password,
        );

        // 验证 WebDAV 连接
        await _webdavClient!.ping();
        final files = await _webdavClient!.readDir('/');

        logger.i('UGreenAdapter: WebDAV 连接成功 (${files.length} 项)');
        _fileSystem = WebDavFileSystem(
          client: _webdavClient!,
          baseUrl: webdavUrl,
          username: config.username,
          password: config.password,
        );
        return;
      } on Exception catch (e, st) {
        AppError.ignore(e, st, 'WebDAV $davPath 失败，继续尝试其他路径');
      }
    }

    throw Exception(appL10n.ugreenWebdavConnectionFailedError);
  }

  @override
  Future<void> disconnect() async {
    if (!_connected) return;
    await _api.logout();
    _connected = false;
    _config = null;
    _serverInfo = null;
    _fileSystem = null;
    _webdavClient = null;
    _useWebDav = false;
    logger.i('UGreenAdapter: 已断开连接');
  }

  @override
  Future<bool> checkConnectionHealth() async {
    if (!_connected) {
      logger.d('UGreenAdapter: 连接健康检查 - 未连接');
      return false;
    }

    try {
      if (_useWebDav && _webdavClient != null) {
        // 使用 WebDAV ping 检查
        await _webdavClient!.ping().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            throw Exception(appL10n.ugreenConnectionHealthCheckTimeoutError);
          },
        );
      } else {
        // 使用 UGOS API 检查
        await _api.getDeviceInfo().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            throw Exception(appL10n.ugreenConnectionHealthCheckTimeoutError);
          },
        );
      }
      logger.d('UGreenAdapter: 连接健康检查 - 正常');
      return true;
    } on Exception catch (e) {
      logger.w('UGreenAdapter: 连接健康检查 - 失败', e);
      _connected = false;
      return false;
    }
  }

  @override
  NasFileSystem get fileSystem {
    if (!_connected) {
      throw StateError(appL10n.ugreenNotConnectedError);
    }
    if (_fileSystem == null) {
      throw StateError(appL10n.ugreenFileSystemNotInitializedError);
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
    _dioClient.dio.close();
  }
}
