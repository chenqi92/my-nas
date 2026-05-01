import 'dart:async';

import 'package:my_nas/core/constants/app_constants.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/network/dio_client.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_adapter.dart';
import 'package:my_nas/nas_adapters/base/nas_connection.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/nas_adapters/synology/api/synology_api.dart';
import 'package:my_nas/nas_adapters/synology/synology_file_system.dart';
import 'package:my_nas/nas_adapters/synology/synology_media_service.dart';

/// 群晖 NAS 适配器
class SynologyAdapter implements NasAdapter {
  SynologyAdapter() {
    logger.i('SynologyAdapter: 初始化适配器');
    _dioClient = DioClient(allowSelfSigned: true);
    _api = SynologyApi(dio: _dioClient.dio);
  }

  late final DioClient _dioClient;
  late final SynologyApi _api;
  late SynologyFileSystem _fileSystem;
  SynologyMediaService? _mediaService;

  ConnectionConfig? _config;
  ServerInfo? _serverInfo;
  bool _connected = false;

  /// 会话刷新锁，防止多个请求同时刷新会话
  Completer<String?>? _sessionRefreshCompleter;

  @override
  NasAdapterInfo get info => NasAdapterInfo(
        type: NasAdapterType.synology,
        name: '群晖 Synology',
        version: AppConstants.appVersion,
        supportsMediaService: true,
      );

  @override
  bool get isConnected => _connected;

  @override
  ConnectionConfig? get connection => _config;

  SynologyApi get api => _api;

  @override
  Future<ConnectionResult> connect(ConnectionConfig config) async {
    logger..i('SynologyAdapter: 开始连接')
    ..i('SynologyAdapter: 目标地址 => ${config.baseUrl}')
    ..i('SynologyAdapter: 用户名 => ${config.username}')
    ..i('SynologyAdapter: 使用 SSL => ${config.useSsl}')
    ..i('SynologyAdapter: 验证 SSL => ${config.verifySSL}');

    _config = config;
    _dioClient.updateBaseUrl(config.baseUrl);

    // 如果不验证 SSL，添加相应配置
    if (!config.verifySSL) {
      logger.i('SynologyAdapter: 跳过 SSL 证书验证');
      _dioClient.setAllowSelfSignedCert(allow: true);
    }

    // 尝试登录
    logger.i('SynologyAdapter: 开始登录认证...');
    final authResult = await _api.login(
      account: config.username,
      password: config.password,
      deviceId: config.deviceId,
      deviceName: config.deviceName,
      enableDeviceToken: config.enableDeviceToken,
    );

    logger.i('SynologyAdapter: 登录结果 => ${authResult.runtimeType}');

    return switch (authResult) {
      AuthSuccess(:final sid, :final deviceId) =>
        await _handleLoginSuccess(sid, deviceId: deviceId),
      AuthFailure(:final error) => () {
          logger.e('SynologyAdapter: 登录失败 => $error');
          return ConnectionFailure(error: error);
        }(),
      AuthRequires2FA() => () {
          logger.i('SynologyAdapter: 需要二次验证');
          return const ConnectionRequires2FA(
            methods: [TwoFactorMethod.totp],
          );
        }(),
    };
  }

  Future<ConnectionResult> verify2FA(
    String otpCode, {
    bool rememberDevice = false,
    String? deviceName,
  }) async {
    if (_config == null) {
      return const ConnectionFailure(error: '请先调用 connect');
    }

    // 如果需要记住设备，必须提供设备名称
    // 优先使用传入的设备名，其次使用配置中的设备名，最后使用默认名称
    final effectiveDeviceName = rememberDevice
        ? (deviceName ?? _config!.deviceName ?? 'MyNAS-${DateTime.now().millisecondsSinceEpoch}')
        : null;

    logger.d('SynologyAdapter: verify2FA - rememberDevice=$rememberDevice, deviceName=$effectiveDeviceName');

    final authResult = await _api.login(
      account: _config!.username,
      password: _config!.password,
      otpCode: otpCode,
      deviceName: effectiveDeviceName,
      enableDeviceToken: rememberDevice,
    );

    return switch (authResult) {
      AuthSuccess(:final sid, :final deviceId) =>
        await _handleLoginSuccess(sid, deviceId: deviceId),
      AuthFailure(:final error) => ConnectionFailure(error: error),
      AuthRequires2FA() => const ConnectionFailure(error: '二次验证失败'),
    };
  }

  Future<ConnectionResult> _handleLoginSuccess(
    String sid, {
    String? deviceId,
  }) async {
    _connected = true;
    _fileSystem = SynologyFileSystem(api: _api);

    // 设置会话刷新回调
    _api.setSessionRefreshCallback(_refreshSession);

    // 获取服务器信息
    try {
      final dsmInfo = await _api.getDsmInfo();
      _serverInfo = ServerInfo(
        hostname: dsmInfo.hostname,
        model: dsmInfo.model,
        version: dsmInfo.version,
        serial: dsmInfo.serial,
      );
    } on Exception catch (e, st) {
      // 获取服务器信息失败不影响连接
      AppError.ignore(e, st, '获取服务器信息失败不影响连接');
    }

    return ConnectionSuccess(
      sessionId: sid,
      serverInfo: _serverInfo,
      deviceId: deviceId,
    );
  }

  /// 刷新会话（重新登录）
  ///
  /// 使用锁机制确保多个请求同时检测到会话过期时，只有一个请求执行刷新，
  /// 其他请求等待刷新结果。
  Future<String?> _refreshSession() async {
    // 如果已有刷新操作在进行中，等待其完成
    if (_sessionRefreshCompleter != null) {
      logger.d('SynologyAdapter: 等待现有会话刷新完成...');
      return _sessionRefreshCompleter!.future;
    }

    final config = _config;
    if (config == null) {
      logger.w('SynologyAdapter: 无法刷新会话，配置为空');
      return null;
    }

    // 创建新的刷新操作
    _sessionRefreshCompleter = Completer<String?>();
    logger.i('SynologyAdapter: 正在刷新会话...');

    try {
      final authResult = await _api.login(
        account: config.username,
        password: config.password,
        deviceId: config.deviceId,
        deviceName: config.deviceName,
        enableDeviceToken: config.enableDeviceToken,
      );

      final result = switch (authResult) {
        AuthSuccess(:final sid) => () {
            logger.i('SynologyAdapter: 会话刷新成功');
            return sid;
          }(),
        AuthFailure(:final error) => () {
            logger.e('SynologyAdapter: 会话刷新失败 => $error');
            _connected = false;
            return null;
          }(),
        AuthRequires2FA() => () {
            // 如果需要 2FA，无法自动刷新
            logger.w('SynologyAdapter: 会话刷新需要 2FA，无法自动完成');
            _connected = false;
            return null;
          }(),
      };

      _sessionRefreshCompleter!.complete(result);
      return result;
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '会话刷新失败');
      _sessionRefreshCompleter!.complete(null);
      return null;
    } finally {
      // 延迟清除 completer，给等待中的请求一些时间获取结果
      Future<void>.delayed(const Duration(milliseconds: 100), () {
        _sessionRefreshCompleter = null;
      });
    }
  }

  @override
  Future<void> disconnect() async {
    if (!_connected) return;
    _api.setSessionRefreshCallback(null);
    await _api.logout();
    _connected = false;
    _config = null;
    _serverInfo = null;
    // 媒体服务依赖 _api 的会话；登出后丢弃缓存实例，下次 connect 后重建
    _mediaService = null;
  }

  @override
  Future<bool> checkConnectionHealth() async {
    if (!_connected) {
      logger.d('SynologyAdapter: 连接健康检查 - 未连接');
      return false;
    }

    try {
      // 尝试获取 DSM 信息来验证连接是否有效
      await _api.getDsmInfo().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw Exception('连接健康检查超时');
        },
      );
      logger.d('SynologyAdapter: 连接健康检查 - 正常');
      return true;
    } on Exception catch (e) {
      logger.w('SynologyAdapter: 连接健康检查 - 失败', e);
      _connected = false;
      return false;
    }
  }

  @override
  NasFileSystem get fileSystem {
    if (!_connected) {
      throw StateError('未连接到 NAS');
    }
    return _fileSystem;
  }

  @override
  MediaService? get mediaService {
    if (!_connected) return null;
    return _mediaService ??= SynologyMediaService(_api);
  }

  @override
  ToolsService? get toolsService => null;

  @override
  Future<StorageInfo?> getStorageInfo() async {
    if (!_connected) return null;

    try {
      final volumes = await _api.getVolumeInfo();
      if (volumes.isEmpty) return null;

      // 计算所有卷的总容量和已使用容量
      var totalBytes = 0;
      var usedBytes = 0;
      final volumeInfoList = <VolumeInfo>[];

      for (final vol in volumes) {
        totalBytes += vol.totalSize;
        usedBytes += vol.usedSize;
        volumeInfoList.add(
          VolumeInfo(
            id: vol.id,
            name: vol.volumePath.isNotEmpty ? vol.volumePath : vol.id,
            totalBytes: vol.totalSize,
            usedBytes: vol.usedSize,
            status: vol.status,
            fileSystem: vol.fsType,
          ),
        );
      }

      return StorageInfo(
        totalBytes: totalBytes,
        usedBytes: usedBytes,
        volumes: volumeInfoList,
      );
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '获取存储信息失败');
      return null;
    }
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    _dioClient.dio.close();
  }
}
