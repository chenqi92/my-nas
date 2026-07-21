import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:my_nas/core/constants/app_constants.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/network/tls_trust_store.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_adapter.dart';
import 'package:my_nas/nas_adapters/base/nas_connection.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/nas_adapters/fnos/api/fnos_api.dart';
import 'package:my_nas/nas_adapters/fnos/fnos_file_system.dart';

/// 飞牛 NAS (fnOS) 适配器
///
/// fnOS 是国产 NAS 系统，基于 Debian
/// 默认端口: 5666
class FnOSAdapter implements NasAdapter {
  FnOSAdapter() {
    logger.i('FnOSAdapter: 初始化适配器');
  }

  Dio? _dio;
  FnOSApi? _api;
  FnOSFileSystem? _fileSystem;
  ConnectionConfig? _config;
  bool _connected = false;

  @override
  NasAdapterInfo get info => NasAdapterInfo(
    type: NasAdapterType.fnos,
    name: appL10n.fnosAdapterName,
    version: AppConstants.appVersion,
  );

  @override
  bool get isConnected => _connected;

  @override
  ConnectionConfig? get connection => _config;

  @override
  Future<ConnectionResult> connect(ConnectionConfig config) async {
    logger
      ..i('FnOSAdapter: 开始连接')
      ..i('FnOSAdapter: 目标地址 => ${config.baseUrl}')
      ..i('FnOSAdapter: 用户名 => ${config.username}');

    _config = config;

    try {
      // 初始化 Dio
      _dio = Dio(
        BaseOptions(
          baseUrl: config.baseUrl,
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 60),
        ),
      );

      // 自签名证书支持
      if (!config.verifySSL) {
        (_dio!.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
          final client = HttpClient()
            ..badCertificateCallback = (cert, host, port) =>
                TlsTrustStore.allowsInvalidCertificate(
                  cert,
                  host,
                  port,
                  allowSelfSigned: true,
                );
          return client;
        };
      }

      // 初始化 API
      _api = FnOSApi(dio: _dio!);

      // 登录认证
      final result = await _api!.login(
        username: config.username,
        password: config.password,
      );

      switch (result) {
        case FnOSAuthSuccess():
          return await _completeConnection(result);

        case FnOSAuthFailure():
          logger.e('FnOSAdapter: 登录失败 => ${result.error}');
          return ConnectionFailure(error: result.error, code: result.code);

        case FnOSAuthRequires2FA():
          logger.i('FnOSAdapter: 需要二次验证');
          return const ConnectionRequires2FA(methods: [TwoFactorMethod.totp]);
      }
    } on DioException catch (e) {
      logger.e('FnOSAdapter: 网络错误', e);
      _connected = false;
      await _cleanup();
      return ConnectionFailure(error: _parseError(e));
    } on Exception catch (e) {
      logger.e('FnOSAdapter: 连接失败', e);
      _connected = false;
      await _cleanup();
      return ConnectionFailure(error: e.toString());
    }
  }

  Future<ConnectionResult> verify2FA(String otpCode) async {
    final config = _config;
    if (config == null || _api == null) {
      return ConnectionFailure(error: appL10n.fnosNetworkError);
    }
    final result = await _api!.login(
      username: config.username,
      password: config.password,
      otpCode: otpCode,
    );
    return switch (result) {
      FnOSAuthSuccess() => await _completeConnection(result),
      FnOSAuthFailure(:final error, :final code) => ConnectionFailure(
        error: error,
        code: code,
      ),
      FnOSAuthRequires2FA() => ConnectionFailure(
        error: appL10n.sourceManager2FAVerificationFailed,
      ),
    };
  }

  Future<ConnectionResult> _completeConnection(FnOSAuthSuccess result) async {
    logger.i('FnOSAdapter: 登录成功，验证文件 API');
    // A successful auth endpoint is insufficient: unsupported firmware can
    // still reject every file API. A valid empty list is accepted.
    await _api!.listShares();
    final deviceInfo = await _api!.getDeviceInfo();
    _fileSystem = FnOSFileSystem(api: _api!);
    _connected = true;
    return ConnectionSuccess(
      sessionId: result.token,
      serverInfo: ServerInfo(
        hostname: deviceInfo.hostname,
        model: deviceInfo.model ?? 'fnOS NAS',
        version: deviceInfo.version,
        serial: deviceInfo.serial,
      ),
    );
  }

  String _parseError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return appL10n.fnosConnectTimeoutError;
    }
    if (e.type == DioExceptionType.connectionError) {
      return appL10n.fnosServerConnectionError;
    }
    return e.message ?? appL10n.fnosNetworkError;
  }

  @override
  Future<void> disconnect() async {
    if (_dio == null && _api == null) return;

    await _cleanup();
    _connected = false;
    _config = null;
    logger.i('FnOSAdapter: 已断开连接');
  }

  Future<void> _cleanup() async {
    try {
      await _api?.logout();
    } on Exception catch (e) {
      logger.w('FnOSAdapter: 登出时出错', e);
    }

    _dio?.close();
    _dio = null;
    _api = null;
    _fileSystem = null;
    _connected = false;
  }

  @override
  Future<bool> checkConnectionHealth() async {
    if (!_connected || _api == null) {
      logger.d('FnOSAdapter: 连接健康检查 - 未连接');
      return false;
    }

    try {
      await _api!.listShares().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw Exception(appL10n.fnosHealthCheckTimeoutError);
        },
      );
      logger.d('FnOSAdapter: 连接健康检查 - 正常');
      return true;
    } on Exception catch (e) {
      logger.w('FnOSAdapter: 连接健康检查 - 失败', e);
      _connected = false;
      return false;
    }
  }

  @override
  NasFileSystem get fileSystem {
    if (!_connected || _fileSystem == null) {
      throw StateError(appL10n.fnosNotConnectedError);
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
