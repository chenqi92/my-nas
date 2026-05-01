import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/media_server_adapters/base/media_server_adapter.dart';
import 'package:my_nas/media_server_adapters/emby/emby_adapter.dart';
import 'package:my_nas/media_server_adapters/jellyfin/jellyfin_adapter.dart';
import 'package:my_nas/media_server_adapters/plex/plex_adapter.dart';
import 'package:my_nas/nas_adapters/base/nas_adapter.dart';
import 'package:my_nas/nas_adapters/base/nas_connection.dart';
import 'package:my_nas/nas_adapters/fnos/fnos_adapter.dart';
import 'package:my_nas/nas_adapters/ftp/ftp_adapter.dart';
import 'package:my_nas/nas_adapters/local/local_adapter.dart';
import 'package:my_nas/nas_adapters/qnap/qnap_adapter.dart';
import 'package:my_nas/nas_adapters/sftp/sftp_adapter.dart';
import 'package:my_nas/nas_adapters/smb/smb_adapter.dart';
import 'package:my_nas/nas_adapters/synology/synology_adapter.dart';
import 'package:my_nas/nas_adapters/ugreen/ugreen_adapter.dart';
import 'package:my_nas/nas_adapters/webdav/webdav_adapter.dart';
import 'package:my_nas/service_adapters/base/service_adapter.dart';
import 'package:my_nas/shared/widgets/stream_image.dart';

/// 源连接信息
class SourceConnection {
  const SourceConnection({
    required this.source,
    required this.adapter,
    this.status = SourceStatus.disconnected,
    this.errorMessage,
  });

  final SourceEntity source;
  final NasAdapter adapter;
  final SourceStatus status;
  final String? errorMessage;

  SourceConnection copyWith({
    SourceEntity? source,
    NasAdapter? adapter,
    SourceStatus? status,
    String? errorMessage,
  }) =>
      SourceConnection(
        source: source ?? this.source,
        adapter: adapter ?? this.adapter,
        status: status ?? this.status,
        errorMessage: errorMessage,
      );
}

/// 凭证信息
class SourceCredential {
  const SourceCredential({
    required this.password,
    this.deviceId,
  });

  factory SourceCredential.fromJson(Map<String, dynamic> json) =>
      SourceCredential(
        password: json['password'] as String,
        deviceId: json['deviceId'] as String?,
      );

  final String password;
  final String? deviceId;

  Map<String, dynamic> toJson() => {
        'password': password,
        'deviceId': deviceId,
      };
}

/// 媒体服务器连接信息
class MediaServerConnection {
  const MediaServerConnection({
    required this.source,
    required this.adapter,
    this.status = SourceStatus.disconnected,
    this.errorMessage,
  });

  final SourceEntity source;
  final MediaServerAdapter adapter;
  final SourceStatus status;
  final String? errorMessage;

  MediaServerConnection copyWith({
    SourceEntity? source,
    MediaServerAdapter? adapter,
    SourceStatus? status,
    String? errorMessage,
  }) =>
      MediaServerConnection(
        source: source ?? this.source,
        adapter: adapter ?? this.adapter,
        status: status ?? this.status,
        errorMessage: errorMessage,
      );
}

/// 源管理服务
class SourceManagerService {
  factory SourceManagerService() => _instance ??= SourceManagerService._();
  SourceManagerService._();

  static SourceManagerService? _instance;

  late Box<dynamic> _sourcesBox;
  late Box<dynamic> _libraryBox;
  bool _initialized = false;

  /// 初始化锁，防止并发初始化
  Future<void>? _initFuture;

  /// 安全存储（用于凭证和设备ID，不受应用沙箱影响）
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
    mOptions: MacOsOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  /// 凭证存储键前缀
  static const _credentialPrefix = 'source_credential_';

  /// 活跃的 NAS 连接
  final Map<String, SourceConnection> _connections = {};

  /// 活跃的媒体服务器连接
  final Map<String, MediaServerConnection> _mediaServerConnections = {};

  /// 安全存储是否可用
  bool _secureStorageAvailable = true;

  /// 检查并处理安全存储错误
  ///
  /// 返回 true 表示是可恢复的存储错误（应静默处理）
  bool _handleSecureStorageError(Object error, String operation) {
    if (error is PlatformException) {
      // Keychain entitlement 错误 (-34018)
      if (error.code == 'Unexpected security result code' ||
          (error.message?.contains('-34018') ?? false)) {
        logger.w(
          'SourceManagerService: 安全存储不可用 ($operation) - '
          '可能缺少 Keychain entitlement 权限，凭证保存功能已禁用',
        );
        _secureStorageAvailable = false;
        return true;
      }
    }
    return false;
  }

  /// 初始化
  ///
  /// 使用锁机制防止并发初始化，确保多个调用者等待同一个初始化过程
  Future<void> init() async {
    // 已初始化，直接返回
    if (_initialized) return;

    // 如果正在初始化中，等待现有的初始化完成
    if (_initFuture != null) {
      await _initFuture;
      return;
    }

    // 开始初始化，设置锁
    _initFuture = _doInit();
    try {
      await _initFuture;
    } finally {
      _initFuture = null;
    }
  }

  /// 实际执行初始化
  Future<void> _doInit() async {
    if (_initialized) return;

    // Hive.initFlutter() 已在 main.dart 中调用，这里直接打开 box
    _sourcesBox = await Hive.openBox('sources');
    _libraryBox = await Hive.openBox('media_library');
    _initialized = true;

    logger.i('SourceManagerService: 初始化完成');
  }

  // ============ 源管理 ============

  /// 获取所有源
  Future<List<SourceEntity>> getSources() async {
    if (!_initialized) await init();

    final data = _sourcesBox.get('list') as List<dynamic>?;
    if (data == null) return [];

    try {
      return data
          .map((e) => SourceEntity.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } on Exception catch (e, st) {
      // 捕获所有错误，包括 TypeError（类型转换失败）
      logger.e('SourceManagerService: 解析源列表失败', e, st);
      return [];
    }
  }

  /// 添加源
  Future<void> addSource(SourceEntity source) async {
    if (!_initialized) await init();

    final sources = await getSources();
    sources.add(source);
    await _saveSources(sources);

    logger.i('SourceManagerService: 添加源 ${source.name}');
  }

  /// 更新源
  Future<void> updateSource(SourceEntity source) async {
    if (!_initialized) await init();

    final sources = await getSources();
    final index = sources.indexWhere((s) => s.id == source.id);
    if (index != -1) {
      sources[index] = source;
      await _saveSources(sources);
      logger.i('SourceManagerService: 更新源 ${source.name}');
    }
  }

  /// 删除源
  Future<void> removeSource(String sourceId) async {
    logger.i('SourceManagerService: 开始删除源 $sourceId');

    if (!_initialized) await init();

    try {
      // 断开连接
      logger.d('SourceManagerService: 断开连接...');
      await disconnect(sourceId);
    } on Exception catch (e) {
      logger.w('SourceManagerService: 断开连接时出错 (继续删除)', e);
    }

    try {
      // 删除凭证
      logger.d('SourceManagerService: 删除凭证...');
      await removeCredential(sourceId);
    } on Exception catch (e) {
      logger.w('SourceManagerService: 删除凭证时出错 (继续删除)', e);
    }

    // 删除源
    logger.d('SourceManagerService: 从列表中删除源...');
    final sources = await getSources();
    final originalCount = sources.length;
    sources.removeWhere((s) => s.id == sourceId);
    logger.d('SourceManagerService: 源数量 $originalCount -> ${sources.length}');
    await _saveSources(sources);

    try {
      // 删除关联的媒体库路径
      logger.d('SourceManagerService: 删除关联的媒体库路径...');
      final config = await getMediaLibraryConfig();
      final newConfig = config.removePathsForSource(sourceId);
      await saveMediaLibraryConfig(newConfig);
    } on Exception catch (e) {
      logger.w('SourceManagerService: 删除媒体库路径时出错', e);
    }

    logger.i('SourceManagerService: 删除源完成 $sourceId');
  }

  Future<void> _saveSources(List<SourceEntity> sources) async {
    await _sourcesBox.put('list', sources.map((s) => s.toJson()).toList());
    // 确保数据已写入磁盘
    await _sourcesBox.flush();
    logger.d('SourceManagerService: 源列表已保存到磁盘');
  }

  // ============ 凭证管理（使用安全存储）============

  /// 保存凭证到安全存储
  ///
  /// 返回 true 表示保存成功，false 表示存储不可用
  Future<bool> saveCredential(String sourceId, SourceCredential credential) async {
    if (!_secureStorageAvailable) {
      logger.d('SourceManagerService: 安全存储不可用，跳过保存凭证 $sourceId');
      return false;
    }

    try {
      final key = '$_credentialPrefix$sourceId';
      final value = jsonEncode(credential.toJson());
      await _secureStorage.write(key: key, value: value);
      logger.i('SourceManagerService: 保存凭证到安全存储 $sourceId (deviceId: ${credential.deviceId != null ? "有" : "无"})');
      return true;
    } on Exception catch (e) {
      if (_handleSecureStorageError(e, 'saveCredential')) {
        return false;
      }
      rethrow;
    }
  }

  /// 从安全存储获取凭证
  Future<SourceCredential?> getCredential(String sourceId) async {
    if (!_secureStorageAvailable) {
      return null;
    }

    try {
      final key = '$_credentialPrefix$sourceId';
      final value = await _secureStorage.read(key: key);
      if (value == null) {
        logger.d('SourceManagerService: 未找到凭证 $sourceId');
        return null;
      }

      final json = jsonDecode(value) as Map<String, dynamic>;
      final credential = SourceCredential.fromJson(json);
      logger.d('SourceManagerService: 读取凭证成功 $sourceId (deviceId: ${credential.deviceId != null ? "有" : "无"})');
      return credential;
    } on Exception catch (e) {
      if (_handleSecureStorageError(e, 'getCredential')) {
        return null;
      }
      logger.e('SourceManagerService: 读取/解析凭证失败', e);
      return null;
    }
  }

  /// 从安全存储删除凭证
  Future<void> removeCredential(String sourceId) async {
    if (!_secureStorageAvailable) {
      return;
    }

    try {
      final key = '$_credentialPrefix$sourceId';
      await _secureStorage.delete(key: key);
      logger.i('SourceManagerService: 删除凭证 $sourceId');
    } on Exception catch (e) {
      if (!_handleSecureStorageError(e, 'removeCredential')) {
        logger.e('SourceManagerService: 删除凭证失败', e);
      }
    }
  }

  /// 更新设备ID（保留密码）
  Future<void> updateDeviceId(String sourceId, String deviceId) async {
    final credential = await getCredential(sourceId);
    if (credential != null) {
      await saveCredential(
        sourceId,
        SourceCredential(
          password: credential.password,
          deviceId: deviceId,
        ),
      );
      logger.i('SourceManagerService: 更新设备ID $sourceId');
    } else {
      logger.w('SourceManagerService: 无法更新设备ID，未找到凭证 $sourceId');
    }
  }

  /// 检查安全存储是否可用
  bool get isSecureStorageAvailable => _secureStorageAvailable;

  // ============ 连接管理 ============

  /// 获取源的连接
  SourceConnection? getConnection(String sourceId) => _connections[sourceId];

  /// 获取所有活跃连接
  List<SourceConnection> getActiveConnections() =>
      _connections.values.where((c) => c.status == SourceStatus.connected).toList();

  /// 连接到源
  Future<SourceConnection> connect(
    SourceEntity source, {
    required String password,
    bool saveCredential = true,
  }) async {
    logger.i('SourceManagerService: 连接到 ${source.name}');

    // 创建适配器
    final adapter = _createAdapter(source.type);

    // 更新状态为连接中
    _connections[source.id] = SourceConnection(
      source: source,
      adapter: adapter,
      status: SourceStatus.connecting,
    );

    // 总是尝试获取已保存的设备ID（用于跳过2FA）
    final savedCredential = await getCredential(source.id);
    final deviceId = savedCredential?.deviceId;

    logger.d('SourceManagerService: 连接配置 - rememberDevice: ${source.rememberDevice}, deviceId: ${deviceId != null ? "有" : "无"}');

    final config = ConnectionConfig(
      type: _getAdapterType(source.type),
      host: source.host,
      port: source.port,
      username: source.username,
      password: password,
      useSsl: source.useSsl,
      verifySSL: false,
      deviceId: deviceId,
      enableDeviceToken: source.rememberDevice,
    );

    try {
      final result = await adapter.connect(config);

      final connection = switch (result) {
        ConnectionSuccess(:final deviceId) => () {
            // 总是保存凭证（包括新的 deviceId）
            if (saveCredential) {
              // 如果连接返回了新的 deviceId，使用新的；否则保留旧的
              final newDeviceId = deviceId ?? savedCredential?.deviceId;
              this.saveCredential(
                source.id,
                SourceCredential(password: password, deviceId: newDeviceId),
              );
            }

            // 更新最后连接时间
            updateSource(source.copyWith(lastConnected: DateTime.now()));

            return SourceConnection(
              source: source,
              adapter: adapter,
              status: SourceStatus.connected,
            );
          }(),
        ConnectionFailure(:final error) => SourceConnection(
            source: source,
            adapter: adapter,
            status: SourceStatus.error,
            errorMessage: error,
          ),
        ConnectionRequires2FA() => SourceConnection(
            source: source,
            adapter: adapter,
            status: SourceStatus.requires2FA,
          ),
      };

      _connections[source.id] = connection;
      return connection;
    } on Exception catch (e) {
      final connection = SourceConnection(
        source: source,
        adapter: adapter,
        status: SourceStatus.error,
        errorMessage: e.toString(),
      );
      _connections[source.id] = connection;
      return connection;
    }
  }

  /// 二次验证
  ///
  /// [rememberDevice] 是否记住此设备，如果为 true，下次连接时将跳过 2FA
  Future<SourceConnection> verify2FA(
    String sourceId,
    String otpCode, {
    bool rememberDevice = false,
    String? password,
  }) async {
    final connection = _connections[sourceId];
    if (connection == null) {
      throw StateError('未找到连接');
    }

    final adapter = connection.adapter;
    ConnectionResult? result;

    if (adapter is SynologyAdapter) {
      result = await adapter.verify2FA(
        otpCode,
        rememberDevice: rememberDevice,
      );
    } else if (adapter is UGreenAdapter) {
      result = await adapter.verify2FA(
        otpCode,
        rememberDevice: rememberDevice,
      );
    } else if (adapter is QnapAdapter) {
      result = await adapter.verify2FA(
        otpCode,
        rememberDevice: rememberDevice,
      );
    }

    if (result != null) {
      SourceConnection newConnection;

      switch (result) {
        case ConnectionSuccess(:final deviceId):
          // 2FA 成功后，保存/更新凭证（包括设备ID）
          if (deviceId != null) {
            logger.i('SourceManagerService: 2FA 成功，保存设备ID');
            // 获取现有凭证中的密码，必须等待完成
            final credential = await getCredential(sourceId);
            if (credential != null) {
              await saveCredential(
                sourceId,
                SourceCredential(
                  password: password ?? credential.password,
                  deviceId: deviceId,
                ),
              );
            } else if (password != null) {
              await saveCredential(
                sourceId,
                SourceCredential(password: password, deviceId: deviceId),
              );
            }
          }

          // 更新最后连接时间
          await updateSource(
              connection.source.copyWith(lastConnected: DateTime.now()));

          newConnection = connection.copyWith(
            status: SourceStatus.connected,
          );

        case ConnectionFailure(:final error):
          newConnection = connection.copyWith(
            status: SourceStatus.error,
            errorMessage: error,
          );

        case ConnectionRequires2FA():
          newConnection = connection.copyWith(
            status: SourceStatus.error,
            errorMessage: '二次验证失败',
          );
      }

      _connections[sourceId] = newConnection;
      return newConnection;
    }

    throw UnsupportedError('该源类型不支持二次验证');
  }

  /// 断开连接
  Future<void> disconnect(String sourceId) async {
    // 尝试断开 NAS 连接
    final connection = _connections[sourceId];
    if (connection != null) {
      await connection.adapter.disconnect();
      await connection.adapter.dispose();
      _connections.remove(sourceId);
      logger.i('SourceManagerService: 断开 NAS 连接 $sourceId');
      return;
    }

    // 尝试断开媒体服务器连接
    final mediaServerConnection = _mediaServerConnections[sourceId];
    if (mediaServerConnection != null) {
      await mediaServerConnection.adapter.disconnect();
      await mediaServerConnection.adapter.dispose();
      _mediaServerConnections.remove(sourceId);
      logger.i('SourceManagerService: 断开媒体服务器连接 $sourceId');
    }
  }

  // ============ 媒体服务器连接管理 ============

  /// 检查源类型是否为媒体服务器
  bool isMediaServerType(SourceType type) => switch (type) {
        SourceType.jellyfin ||
        SourceType.emby ||
        SourceType.plex =>
          true,
        _ => false,
      };

  /// 获取媒体服务器连接
  MediaServerConnection? getMediaServerConnection(String sourceId) =>
      _mediaServerConnections[sourceId];

  /// 获取所有活跃的媒体服务器连接
  List<MediaServerConnection> getActiveMediaServerConnections() =>
      _mediaServerConnections.values
          .where((c) => c.status == SourceStatus.connected)
          .toList();

  /// 连接到媒体服务器
  ///
  /// 适用于 Jellyfin、Emby、Plex 等媒体服务器类型
  Future<MediaServerConnection> connectMediaServer(
    SourceEntity source, {
    String? password,
    String? apiKey,
    bool saveCredential = true,
  }) async {
    logger.i('SourceManagerService: 连接到媒体服务器 ${source.name}');

    if (!isMediaServerType(source.type)) {
      throw UnsupportedError('${source.type.displayName} 不是媒体服务器类型');
    }

    // 创建适配器
    final adapter = _createMediaServerAdapter(source.type);

    // 更新状态为连接中
    _mediaServerConnections[source.id] = MediaServerConnection(
      source: source,
      adapter: adapter,
      status: SourceStatus.connecting,
    );

    // 构建连接配置
    final config = ServiceConnectionConfig(
      baseUrl: source.baseUrl,
      username: source.username.isNotEmpty ? source.username : null,
      password: password,
      apiKey: apiKey ?? source.apiKey,
      extraConfig: source.extraConfig,
    );

    try {
      final result = await adapter.connect(config);

      final connection = result.when(
        success: (_) {
          // 保存凭证
          if (saveCredential && password != null) {
            this.saveCredential(
              source.id,
              SourceCredential(password: password),
            );
          }

          // 更新最后连接时间
          updateSource(source.copyWith(lastConnected: DateTime.now()));

          return MediaServerConnection(
            source: source,
            adapter: adapter,
            status: SourceStatus.connected,
          );
        },
        failure: (error) => MediaServerConnection(
          source: source,
          adapter: adapter,
          status: SourceStatus.error,
          errorMessage: error,
        ),
      );

      _mediaServerConnections[source.id] = connection;
      return connection;
    } on Exception catch (e) {
      final connection = MediaServerConnection(
        source: source,
        adapter: adapter,
        status: SourceStatus.error,
        errorMessage: e.toString(),
      );
      _mediaServerConnections[source.id] = connection;
      return connection;
    }
  }

  /// 创建媒体服务器适配器
  MediaServerAdapter _createMediaServerAdapter(SourceType type) => switch (type) {
        SourceType.jellyfin => JellyfinAdapter(),
        SourceType.emby => EmbyAdapter(),
        SourceType.plex => PlexAdapter(),
        _ => throw UnsupportedError('${type.displayName} 不是媒体服务器类型'),
      };

  /// 检查连接健康状态
  ///
  /// 返回 true 表示连接健康，false 表示连接已断开或异常
  Future<bool> checkConnectionHealth(String sourceId) async {
    final connection = _connections[sourceId];
    if (connection == null || connection.status != SourceStatus.connected) {
      return false;
    }

    try {
      return await connection.adapter.checkConnectionHealth();
    } on Exception catch (e, st) {
      logger.w('SourceManagerService: 检查连接健康状态失败', e, st);
      return false;
    }
  }

  /// 重新连接
  ///
  /// 断开现有连接并重新建立连接。如果提供了密码则使用提供的密码，
  /// 否则尝试从安全存储中获取保存的凭证。
  ///
  /// 返回新的连接对象
  Future<SourceConnection?> reconnect(String sourceId, {String? password}) async {
    logger.i('SourceManagerService: 开始重连 $sourceId');

    // 获取源信息
    final sources = await getSources();
    final source = sources.where((s) => s.id == sourceId).firstOrNull;
    if (source == null) {
      logger.e('SourceManagerService: 重连失败 - 源不存在 $sourceId');
      return null;
    }

    // 获取密码
    var pwd = password;
    if (pwd == null) {
      final credential = await getCredential(sourceId);
      if (credential == null) {
        // 本地存储不需要密码
        if (source.type == SourceType.local) {
          pwd = '';
        } else {
          logger.e('SourceManagerService: 重连失败 - 没有保存的凭证 $sourceId');
          return null;
        }
      } else {
        pwd = credential.password;
      }
    }

    // 断开现有连接（如果有）
    try {
      await disconnect(sourceId);
    } on Exception catch (e, st) {
      logger.w('SourceManagerService: 断开连接时出错（继续重连）', e, st);
    }

    // 重新连接
    try {
      final connection = await connect(
        source,
        password: pwd,
        saveCredential: false, // 凭证已保存，不需要再次保存
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          logger.w('SourceManagerService: 重连超时 $sourceId');
          // 注意：这里不创建新适配器，返回 null 表示超时
          // 由调用方处理超时情况
          throw TimeoutException('重连超时');
        },
      );

      if (connection.status == SourceStatus.connected) {
        logger.i('SourceManagerService: 重连成功 $sourceId');
      } else {
        logger.e('SourceManagerService: 重连失败 $sourceId: ${connection.errorMessage}');
      }

      return connection;
    } on TimeoutException {
      logger.e('SourceManagerService: 重连超时 $sourceId');
      return null;
    } on Exception catch (e, st) {
      logger.e('SourceManagerService: 重连异常 $sourceId', e, st);
      return null;
    }
  }

  /// 确保连接健康，如果不健康则自动重连
  ///
  /// 返回连接是否健康（原本健康或重连成功）
  Future<bool> ensureConnectionHealthy(String sourceId) async {
    // 先检查连接是否健康
    final isHealthy = await checkConnectionHealth(sourceId);
    if (isHealthy) {
      return true;
    }

    logger.i('SourceManagerService: 连接不健康，尝试重连 $sourceId');

    // 尝试重连
    final newConnection = await reconnect(sourceId);
    return newConnection?.status == SourceStatus.connected;
  }

  /// 断开所有连接
  Future<void> disconnectAll() async {
    // 断开 NAS 连接
    for (final sourceId in _connections.keys.toList()) {
      await disconnect(sourceId);
    }
    // 断开媒体服务器连接
    for (final sourceId in _mediaServerConnections.keys.toList()) {
      await disconnect(sourceId);
    }
    // 清理图片内存缓存
    StreamImage.clearCache();
    logger.i('SourceManagerService: 已清理图片内存缓存');
  }

  /// 自动连接所有启用自动连接的源
  ///
  /// 会尝试使用保存的凭证和设备ID自动连接，如果有设备ID则可以跳过2FA
  /// 本地存储不需要凭证，会直接连接
  /// 使用并行连接以避免单个源阻塞其他源
  Future<void> autoConnectAll() async {
    final sources = await getSources();
    final autoConnectSources = sources.where((s) => s.autoConnect).toList();
    logger.i('SourceManagerService: 开始自动连接 ${autoConnectSources.length} 个源');

    // 并行连接所有源，每个连接有独立的超时
    final futures = autoConnectSources.map(_autoConnectSource);
    await Future.wait(futures);

    logger.i('SourceManagerService: 自动连接完成');
  }

  /// 自动连接单个源（带超时处理和重试机制）
  ///
  /// 优化：减少超时时间，避免在网络不可用时长时间阻塞
  /// 用户可以在应用启动后手动重新连接
  Future<void> _autoConnectSource(SourceEntity source) async {
    // 服务类源（下载器、媒体管理等）使用各自的 ServiceAdapter，不走此连接流程
    // 它们有独立的连接管理机制
    if (source.isServiceSource) {
      logger.d('SourceManagerService: 跳过服务类源 ${source.name}，使用专用连接方式');
      return;
    }

    // 如果已连接，跳过自动连接，避免重复登录导致旧会话失效
    final existing = _connections[source.id];
    if (existing?.status == SourceStatus.connected) {
      logger.d('SourceManagerService: ${source.name} 已连接，跳过自动连接');
      return;
    }

    // 减少超时时间，避免非内网环境下等待过久
    // 如果网络可用，这个时间足够完成连接
    // 如果网络不可用，快速失败让用户可以正常使用本地数据
    final timeout = switch (source.type) {
      SourceType.smb || SourceType.webdav => const Duration(seconds: 10),
      _ => const Duration(seconds: 6),
    };

    // 减少重试次数，避免在网络不可用时等待过久
    // 用户可以稍后手动重新连接
    const maxRetries = 1;

    try {
      // 本地存储不需要凭证，直接连接
      if (source.type == SourceType.local) {
        logger.i('SourceManagerService: 自动连接 ${source.type.displayName} ${source.name}');
        try {
          final connection = await connect(
            source,
            password: '',
            saveCredential: false,
          ).timeout(timeout);

          if (connection.status == SourceStatus.connected) {
            logger.i('SourceManagerService: ${source.name} 自动连接成功');
          } else {
            logger.e('SourceManagerService: ${source.name} 连接失败: ${connection.errorMessage}');
          }
        } on TimeoutException {
          logger.w('SourceManagerService: ${source.name} 连接超时');
        }
        return;
      }

      final credential = await getCredential(source.id);
      if (credential != null) {
        logger.i('SourceManagerService: 自动连接 ${source.name} (deviceId: ${credential.deviceId != null ? "有" : "无"})');

        // 带重试的连接逻辑
        SourceConnection? connection;
        for (var attempt = 1; attempt <= maxRetries; attempt++) {
          if (attempt > 1) {
            logger.i('SourceManagerService: ${source.name} 重试连接 (第 $attempt 次)');
            // 重试前等待一小段时间
            await Future<void>.delayed(const Duration(seconds: 2));
          }

          try {
            // saveCredential=true 确保如果连接返回新的 deviceId，会被保存
            connection = await connect(
              source,
              password: credential.password,
            ).timeout(timeout);

            // 如果连接成功或者需要2FA，不再重试
            if (connection.status == SourceStatus.connected ||
                connection.status == SourceStatus.requires2FA) {
              break;
            }
          } on TimeoutException {
            logger.w('SourceManagerService: ${source.name} 连接超时 (第 $attempt 次)');
            // 超时时不创建无效的 SourceConnection，继续重试或退出
            if (attempt == maxRetries) {
              logger.e('SourceManagerService: ${source.name} 连接超时，已达最大重试次数');
            }
          }
        }

        // 记录最终连接结果
        if (connection != null) {
          switch (connection.status) {
            case SourceStatus.connected:
              logger.i('SourceManagerService: ${source.name} 自动连接成功');
            case SourceStatus.requires2FA:
              logger.w('SourceManagerService: ${source.name} 需要2FA (deviceId 可能已失效)');
            case SourceStatus.error:
              logger.e('SourceManagerService: ${source.name} 连接失败: ${connection.errorMessage}');
            default:
              break;
          }
        }
      } else {
        logger.d('SourceManagerService: ${source.name} 没有保存的凭证，跳过自动连接');
      }
    } on Exception catch (e, st) {
      // 捕获所有错误，包括 TypeError
      logger.e('SourceManagerService: 自动连接异常 ${source.name}', e, st);
    }
  }

  NasAdapter _createAdapter(SourceType type) => switch (type) {
      SourceType.synology => SynologyAdapter(),
      SourceType.ugreen => UGreenAdapter(),
      SourceType.fnos => FnOSAdapter(),
      SourceType.qnap => QnapAdapter(),
      SourceType.webdav => WebDavAdapter(),
      SourceType.smb => SmbAdapter(),
      SourceType.ftp => FtpAdapter(),
      SourceType.sftp => SftpAdapter(),
      SourceType.local => LocalAdapter(),
      // 尚未接入的通用协议
      SourceType.nfs ||
      SourceType.upnp =>
        throw UnsupportedError('协议 ${type.displayName} 尚未实现'),
      // 服务类源不使用 NasAdapter，需要使用各自的 ServiceAdapter
      SourceType.qbittorrent ||
      SourceType.transmission ||
      SourceType.aria2 ||
      SourceType.trakt ||
      SourceType.nastool ||
      SourceType.moviepilot ||
      SourceType.jellyfin ||
      SourceType.emby ||
      SourceType.plex ||
      SourceType.ptSite ||
      SourceType.opensubtitles =>
        throw UnsupportedError('服务类源 ${type.displayName} 不支持 NasAdapter，请使用对应的 ServiceAdapter'),
    };

  NasAdapterType _getAdapterType(SourceType type) => switch (type) {
      SourceType.synology => NasAdapterType.synology,
      SourceType.ugreen => NasAdapterType.ugreen,
      SourceType.fnos => NasAdapterType.fnos,
      SourceType.qnap => NasAdapterType.qnap,
      SourceType.webdav => NasAdapterType.webdav,
      SourceType.smb => NasAdapterType.smb,
      SourceType.ftp => NasAdapterType.ftp,
      SourceType.sftp => NasAdapterType.sftp,
      SourceType.local => NasAdapterType.local,
      // 尚未接入的通用协议
      SourceType.nfs ||
      SourceType.upnp =>
        throw UnsupportedError('协议 ${type.displayName} 尚未实现'),
      // 服务类源不使用 NasAdapterType
      SourceType.qbittorrent ||
      SourceType.transmission ||
      SourceType.aria2 ||
      SourceType.trakt ||
      SourceType.nastool ||
      SourceType.moviepilot ||
      SourceType.jellyfin ||
      SourceType.emby ||
      SourceType.plex ||
      SourceType.ptSite ||
      SourceType.opensubtitles =>
        throw UnsupportedError('服务类源 ${type.displayName} 不支持 NasAdapterType'),
    };

  // ============ 媒体库配置 ============

  /// 获取媒体库配置
  Future<MediaLibraryConfig> getMediaLibraryConfig() async {
    if (!_initialized) await init();

    final data = _libraryBox.get('config');
    logger.i('SourceManagerService: 读取媒体库配置 - $data');
    if (data == null) {
      logger.i('SourceManagerService: 媒体库配置为空，返回默认配置');
      return const MediaLibraryConfig();
    }

    try {
      final config = MediaLibraryConfig.fromJson(Map<String, dynamic>.from(data as Map));
      logger.i('SourceManagerService: 解析媒体库配置成功 - 视频路径: ${config.videoPaths.length}, 音乐路径: ${config.musicPaths.length}');
      return config;
    } on Exception catch (e, st) {
      // 捕获所有错误，包括 TypeError（类型转换失败）
      logger.e('SourceManagerService: 解析媒体库配置失败', e, st);
      return const MediaLibraryConfig();
    }
  }

  /// 保存媒体库配置
  Future<void> saveMediaLibraryConfig(MediaLibraryConfig config) async {
    if (!_initialized) await init();
    final json = config.toJson();
    logger.i('SourceManagerService: 保存媒体库配置 - $json');
    await _libraryBox.put('config', json);
    // 确保数据已写入磁盘
    await _libraryBox.flush();
    logger.i('SourceManagerService: 媒体库配置已保存');
  }
}
