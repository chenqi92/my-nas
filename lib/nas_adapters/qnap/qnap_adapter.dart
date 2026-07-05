import 'package:my_nas/core/constants/app_constants.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/network/dio_client.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_adapter.dart';
import 'package:my_nas/nas_adapters/base/nas_connection.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/nas_adapters/qnap/api/qnap_api.dart';
import 'package:my_nas/nas_adapters/qnap/qnap_file_system.dart';
import 'package:my_nas/nas_adapters/qnap/qnap_media_service.dart';

/// 威联通 QNAP NAS 适配器
class QnapAdapter implements NasAdapter {
  QnapAdapter() {
    logger.i('QnapAdapter: 初始化适配器');
    _dioClient = DioClient();
    _api = QnapApi(dio: _dioClient.dio);
  }

  late final DioClient _dioClient;
  late final QnapApi _api;
  late QnapFileSystem _fileSystem;
  QnapMediaService? _mediaService;

  ConnectionConfig? _config;
  ServerInfo? _serverInfo;
  bool _connected = false;

  @override
  NasAdapterInfo get info => NasAdapterInfo(
    type: NasAdapterType.qnap,
    name: 'QNAP NAS',
    version: AppConstants.appVersion,
    // 基于 File Station HTTP API（get_list 媒体过滤 + get_viewer 流地址）
    // 实现媒体库浏览与播放，无需依赖已停更的 Music/Photo/Video Station 套件
    supportsMediaService: true,
  );

  @override
  bool get isConnected => _connected;

  @override
  ConnectionConfig? get connection => _config;

  QnapApi get api => _api;

  @override
  Future<ConnectionResult> connect(ConnectionConfig config) async {
    logger
      ..i('QnapAdapter: 开始连接')
      ..i('QnapAdapter: 目标地址 => ${config.baseUrl}')
      ..i('QnapAdapter: 用户名 => ${config.username}')
      ..i('QnapAdapter: 使用 SSL => ${config.useSsl}')
      ..i('QnapAdapter: 验证 SSL => ${config.verifySSL}');

    _config = config;
    _dioClient
      ..updateBaseUrl(config.baseUrl)
      ..setAllowSelfSignedCert(allow: !config.verifySSL);
    if (!config.verifySSL) {
      logger.i('QnapAdapter: 跳过 SSL 证书验证');
    }

    // 尝试登录
    logger.i('QnapAdapter: 开始登录认证...');
    final authResult = await _api.login(
      account: config.username,
      password: config.password,
    );

    logger.i('QnapAdapter: 登录结果 => ${authResult.runtimeType}');

    return switch (authResult) {
      QnapAuthSuccess(:final sid) => await _handleLoginSuccess(sid),
      QnapAuthFailure(:final error) => () {
        logger.e('QnapAdapter: 登录失败 => $error');
        return ConnectionFailure(error: error);
      }(),
      QnapAuthRequires2FA() => () {
        logger.i('QnapAdapter: 需要二次验证');
        return const ConnectionRequires2FA(methods: [TwoFactorMethod.totp]);
      }(),
    };
  }

  Future<ConnectionResult> verify2FA(
    String otpCode, {
    bool rememberDevice = false,
  }) async {
    if (_config == null) {
      return ConnectionFailure(error: appL10n.qnapAdapterConnectNotCalledError);
    }

    final authResult = await _api.login(
      account: _config!.username,
      password: _config!.password,
      otpCode: otpCode,
      rememberMe: rememberDevice,
    );

    return switch (authResult) {
      QnapAuthSuccess(:final sid) => await _handleLoginSuccess(sid),
      QnapAuthFailure(:final error) => ConnectionFailure(error: error),
      QnapAuthRequires2FA() => ConnectionFailure(
        error: appL10n.qnapAdapter2FAVerificationFailed,
      ),
    };
  }

  Future<ConnectionResult> _handleLoginSuccess(String sid) async {
    _connected = true;
    _fileSystem = QnapFileSystem(api: _api);
    _mediaService = QnapMediaService(_api);

    // 获取服务器信息
    try {
      final sysInfo = await _api.getSystemInfo();
      _serverInfo = ServerInfo(
        hostname: sysInfo.hostname,
        model: sysInfo.model,
        version: sysInfo.version,
        serial: sysInfo.serial,
      );
    } on Exception catch (e, st) {
      // 获取服务器信息失败不影响连接
      AppError.ignore(e, st, '获取服务器信息失败不影响连接');
    }

    return ConnectionSuccess(sessionId: sid, serverInfo: _serverInfo);
  }

  @override
  Future<void> disconnect() async {
    if (!_connected) return;
    await _api.logout();
    _connected = false;
    _config = null;
    _serverInfo = null;
    _mediaService = null;
  }

  @override
  Future<bool> checkConnectionHealth() async {
    if (!_connected) {
      logger.d('QnapAdapter: 连接健康检查 - 未连接');
      return false;
    }

    try {
      // 尝试获取系统信息来验证连接是否有效
      await _api.getSystemInfo().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw Exception(appL10n.qnapAdapterHealthCheckTimeout);
        },
      );
      logger.d('QnapAdapter: 连接健康检查 - 正常');
      return true;
    } on Exception catch (e) {
      logger.w('QnapAdapter: 连接健康检查 - 失败', e);
      _connected = false;
      return false;
    }
  }

  @override
  NasFileSystem get fileSystem {
    if (!_connected) {
      throw StateError(appL10n.qnapAdapterNotConnectedError);
    }
    return _fileSystem;
  }

  @override
  MediaService? get mediaService => _connected ? _mediaService : null;

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
