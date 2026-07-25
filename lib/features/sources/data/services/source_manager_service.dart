import 'dart:async';
import 'dart:convert';

import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/network/http_client.dart';
import 'package:my_nas/core/network/tls_trust_store.dart';
import 'package:my_nas/core/storage/secure_storage_options.dart';
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
import 'package:my_nas/nas_adapters/upnp/upnp_adapter.dart';
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
  }) => SourceConnection(
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
    this.accessToken,
    this.refreshToken,
    this.apiKey,
    this.extraSecrets = const {},
  });

  factory SourceCredential.fromJson(Map<String, dynamic> json) =>
      SourceCredential(
        password: json['password'] as String? ?? '',
        deviceId: json['deviceId'] as String?,
        accessToken: json['accessToken'] as String?,
        refreshToken: json['refreshToken'] as String?,
        apiKey: json['apiKey'] as String?,
        extraSecrets: json['extraSecrets'] == null
            ? const {}
            : Map<String, dynamic>.from(json['extraSecrets'] as Map),
      );

  final String password;
  final String? deviceId;
  final String? accessToken;
  final String? refreshToken;
  final String? apiKey;
  final Map<String, dynamic> extraSecrets;

  bool get hasSecrets =>
      password.isNotEmpty ||
      accessToken != null ||
      refreshToken != null ||
      apiKey != null ||
      extraSecrets.isNotEmpty;

  SourceCredential merge(SourceCredential newer) => SourceCredential(
    password: newer.password.isNotEmpty ? newer.password : password,
    deviceId: newer.deviceId ?? deviceId,
    accessToken: newer.accessToken ?? accessToken,
    refreshToken: newer.refreshToken ?? refreshToken,
    apiKey: newer.apiKey ?? apiKey,
    extraSecrets: {...extraSecrets, ...newer.extraSecrets},
  );

  SourceCredential copyWith({String? deviceId, bool clearDeviceId = false}) =>
      SourceCredential(
        password: password,
        deviceId: clearDeviceId ? null : (deviceId ?? this.deviceId),
        accessToken: accessToken,
        refreshToken: refreshToken,
        apiKey: apiKey,
        extraSecrets: extraSecrets,
      );

  Map<String, dynamic> toJson() => {
    'password': password,
    if (deviceId != null) 'deviceId': deviceId,
    if (accessToken != null) 'accessToken': accessToken,
    if (refreshToken != null) 'refreshToken': refreshToken,
    if (apiKey != null) 'apiKey': apiKey,
    if (extraSecrets.isNotEmpty) 'extraSecrets': extraSecrets,
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
  }) => MediaServerConnection(
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
  static final _secureStorage = defaultSecureStorage;

  /// 凭证存储键前缀
  static const _credentialPrefix = 'source_credential_';

  /// 活跃的 NAS 连接
  final Map<String, SourceConnection> _connections = {};

  /// 同一来源只允许一个登录流程，避免并发登录使旧会话立即失效。
  final Map<String, Future<SourceConnection>> _connectionAttempts = {};

  /// 活跃的媒体服务器连接
  final Map<String, MediaServerConnection> _mediaServerConnections = {};

  final Map<String, Future<MediaServerConnection>>
  _mediaServerConnectionAttempts = {};

  /// 安全存储是否可用
  bool _secureStorageAvailable = true;

  /// 检查并处理安全存储错误
  ///
  /// 返回 true 表示是可恢复的存储错误（应静默处理）
  bool _handleSecureStorageError(Object error, String operation) {
    if (isSecureStorageUnavailableError(error)) {
      logger.w(
        'SourceManagerService: 安全存储不可用 ($operation) - '
        '可能缺少 Keychain entitlement 权限，凭证保存功能已禁用',
      );
      _secureStorageAvailable = false;
      return true;
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
    await TlsTrustStore.load();
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
      final persistedSources = <SourceEntity>[];
      for (var index = 0; index < data.length; index++) {
        try {
          final raw = data[index];
          if (raw is! Map) throw const FormatException('连接源记录不是对象');
          persistedSources.add(
            SourceEntity.fromJson(Map<String, dynamic>.from(raw)),
          );
        } on Exception catch (e, st) {
          // 单条旧版/损坏配置不应让其他连接源全部消失。
          // 该原始记录会在下次保存时由 _persistSanitizedSources 保留。
          logger.e('SourceManagerService: 跳过无法解析的源记录 #$index', e, st);
        }
      }
      final hydratedSources = <SourceEntity>[];
      var hasLegacySecrets = false;
      var migratedAllLegacySecrets = true;

      for (final source in persistedSources) {
        try {
          final legacyCredential = _credentialFromSource(source);
          if (legacyCredential.hasSecrets) {
            hasLegacySecrets = true;
            if (!await saveCredential(source.id, legacyCredential)) {
              migratedAllLegacySecrets = false;
            }
          }
          final credential = await getCredential(source.id);
          hydratedSources.add(_hydrateSource(source, credential));
        } on Exception catch (e, st) {
          // 安全存储的单条读写故障不能隐藏整个连接源列表。
          if (_credentialFromSource(source).hasSecrets) {
            hasLegacySecrets = true;
            migratedAllLegacySecrets = false;
          }
          logger.e('SourceManagerService: 凭证迁移/读取失败 ${source.id}', e, st);
          hydratedSources.add(source);
        }
      }

      if (hasLegacySecrets && migratedAllLegacySecrets) {
        try {
          await _persistSanitizedSources(persistedSources);
          logger.i('SourceManagerService: 已将旧版源密钥迁移到安全存储');
        } on Exception catch (e, st) {
          logger.e('SourceManagerService: 保存密钥迁移结果失败', e, st);
        }
      }
      return hydratedSources;
    } catch (e, st) {
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
    for (final source in sources) {
      final credential = _credentialFromSource(source);
      final stored = await _replaceSourceSecrets(source.id, credential);
      if (credential.hasSecrets && !stored) {
        throw StateError('安全存储不可用，无法安全保存 ${source.displayName} 的凭证');
      }
    }
    await _persistSanitizedSources(sources);
  }

  Future<void> _persistSanitizedSources(List<SourceEntity> sources) async {
    final unparsedRecords = _unparsedPersistedSourceRecords();
    await _sourcesBox.put('list', [
      ...sources.map((source) => source.toJson(includeSecrets: false)),
      ...unparsedRecords,
    ]);
    // 确保数据已写入磁盘
    await _sourcesBox.flush();
    logger.d('SourceManagerService: 源列表已保存到磁盘');
  }

  List<dynamic> _unparsedPersistedSourceRecords() {
    final rawRecords = _sourcesBox.get('list');
    if (rawRecords is! List) return const [];
    final unparsed = <dynamic>[];
    for (final raw in rawRecords) {
      try {
        if (raw is! Map) throw const FormatException('连接源记录不是对象');
        SourceEntity.fromJson(Map<String, dynamic>.from(raw));
      } on Exception {
        unparsed.add(raw);
      }
    }
    return unparsed;
  }

  SourceCredential _credentialFromSource(SourceEntity source) {
    final extraSecrets = <String, dynamic>{};
    final config = source.extraConfig;
    final legacyPassword = config?['password'];
    if (config != null) {
      for (final key in SourceEntity.sensitiveExtraConfigKeys) {
        if (key == 'password') continue;
        final value = config[key];
        if (value != null) extraSecrets[key] = value;
      }
    }
    return SourceCredential(
      password: legacyPassword is String ? legacyPassword : '',
      accessToken: source.accessToken,
      refreshToken: source.refreshToken,
      apiKey: source.apiKey,
      extraSecrets: extraSecrets,
    );
  }

  SourceEntity _hydrateSource(
    SourceEntity source,
    SourceCredential? credential,
  ) {
    if (credential == null) return source;
    final extraConfig = <String, dynamic>{
      ...?source.extraConfig,
      ...credential.extraSecrets,
    };
    return source.copyWith(
      accessToken: credential.accessToken,
      refreshToken: credential.refreshToken,
      apiKey: credential.apiKey,
      extraConfig: extraConfig.isEmpty ? null : extraConfig,
    );
  }

  // ============ 凭证管理（使用安全存储）============

  /// Replaces secrets represented by [SourceEntity] while preserving the
  /// password and remembered device stored alongside them.
  Future<bool> _replaceSourceSecrets(
    String sourceId,
    SourceCredential sourceSecrets,
  ) async {
    if (!_secureStorageAvailable) return false;
    try {
      final existing = await getCredential(sourceId);
      if (existing == null && !sourceSecrets.hasSecrets) return true;
      final replacement = SourceCredential(
        password: existing?.password ?? '',
        deviceId: existing?.deviceId,
        accessToken: sourceSecrets.accessToken,
        refreshToken: sourceSecrets.refreshToken,
        apiKey: sourceSecrets.apiKey,
        extraSecrets: sourceSecrets.extraSecrets,
      );
      final key = '$_credentialPrefix$sourceId';
      await writeSecureValueVerified(
        _secureStorage,
        key: key,
        value: jsonEncode(replacement.toJson()),
      );
      return true;
    } on Exception catch (e) {
      if (_handleSecureStorageError(e, 'replaceSourceSecrets')) return false;
      rethrow;
    }
  }

  /// 保存凭证到安全存储
  ///
  /// 返回 true 表示保存成功，false 表示存储不可用
  Future<bool> saveCredential(
    String sourceId,
    SourceCredential credential,
  ) async {
    if (!_secureStorageAvailable) {
      logger.d('SourceManagerService: 安全存储不可用，跳过保存凭证 $sourceId');
      return false;
    }

    try {
      final key = '$_credentialPrefix$sourceId';
      final existing = await getCredential(sourceId);
      final merged = existing?.merge(credential) ?? credential;
      final value = jsonEncode(merged.toJson());
      await writeSecureValueVerified(_secureStorage, key: key, value: value);
      logger.i(
        'SourceManagerService: 保存凭证到安全存储 $sourceId (deviceId: ${merged.deviceId != null ? "有" : "无"})',
      );
      return true;
    } on Exception catch (e) {
      if (_handleSecureStorageError(e, 'saveCredential')) {
        return false;
      }
      rethrow;
    }
  }

  /// Saves a credential and reports an unavailable secret store as an error.
  /// UI flows should use this method so they never claim a password was saved
  /// when Keychain/Keystore silently rejected it.
  Future<void> saveCredentialRequired(
    String sourceId,
    SourceCredential credential,
  ) async {
    if (!await saveCredential(sourceId, credential)) {
      throw StateError(appL10n.sourcesSecurityStorageUnavailable);
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
      logger.d(
        'SourceManagerService: 读取凭证成功 $sourceId (deviceId: ${credential.deviceId != null ? "有" : "无"})',
      );
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
      await saveCredentialRequired(
        sourceId,
        credential.copyWith(deviceId: deviceId),
      );
      logger.i('SourceManagerService: 更新设备ID $sourceId');
    } else {
      logger.w('SourceManagerService: 无法更新设备ID，未找到凭证 $sourceId');
    }
  }

  /// 清除已记住的设备 ID，同时保留其他凭证。
  Future<void> clearDeviceId(String sourceId) async {
    final credential = await getCredential(sourceId);
    if (credential == null || credential.deviceId == null) return;
    try {
      final key = '$_credentialPrefix$sourceId';
      final value = jsonEncode(
        credential.copyWith(clearDeviceId: true).toJson(),
      );
      await writeSecureValueVerified(_secureStorage, key: key, value: value);
      logger.i('SourceManagerService: 清除设备ID $sourceId');
    } on Exception catch (e) {
      if (!_handleSecureStorageError(e, 'clearDeviceId')) rethrow;
    }
  }

  /// 检查安全存储是否可用
  bool get isSecureStorageAvailable => _secureStorageAvailable;

  // ============ 连接管理 ============

  /// 获取源的连接
  SourceConnection? getConnection(String sourceId) => _connections[sourceId];

  /// 获取所有活跃连接
  List<SourceConnection> getActiveConnections() => _connections.values
      .where((c) => c.status == SourceStatus.connected)
      .toList();

  /// 连接到源
  Future<SourceConnection> connect(
    SourceEntity source, {
    required String password,
    bool saveCredential = true,
  }) async {
    final pending = _connectionAttempts[source.id];
    if (pending != null) return pending;
    final future = _connect(
      source,
      password: password,
      saveCredential: saveCredential,
    );
    _connectionAttempts[source.id] = future;
    try {
      return await future;
    } finally {
      if (identical(_connectionAttempts[source.id], future)) {
        unawaited(_connectionAttempts.remove(source.id));
      }
    }
  }

  Future<SourceConnection> _connect(
    SourceEntity source, {
    required String password,
    required bool saveCredential,
  }) async {
    logger.i('SourceManagerService: 连接到 ${source.name}');

    final previous = _connections.remove(source.id);
    if (previous != null) {
      await _disposeNasAdapter(previous.adapter);
    }

    // 创建适配器
    final adapter = _createAdapter(source.type);

    // 更新状态为连接中
    _connections[source.id] = SourceConnection(
      source: source,
      adapter: adapter,
      status: SourceStatus.connecting,
    );

    final savedCredential = await getCredential(source.id);
    final deviceId = source.rememberDevice ? savedCredential?.deviceId : null;
    if (!source.rememberDevice && savedCredential?.deviceId != null) {
      await clearDeviceId(source.id);
    }

    logger.d(
      'SourceManagerService: 连接配置 - rememberDevice: ${source.rememberDevice}, deviceId: ${deviceId != null ? "有" : "无"}',
    );

    final config = ConnectionConfig(
      type: _getAdapterType(source.type),
      host: source.host,
      port: source.port,
      username: source.username,
      password: password,
      useSsl: source.useSsl,
      verifySSL: !InsecureHttpClient.trustSelfSigned,
      deviceId: deviceId,
      enableDeviceToken: source.rememberDevice,
      basePath: source.extraConfig?['basePath'] as String?,
      extraConfig: source.extraConfig,
    );

    try {
      final result = await adapter.connect(config);

      final SourceConnection connection;
      switch (result) {
        case ConnectionSuccess(:final deviceId):
          // 总是保存凭证（包括新的 deviceId）
          if (saveCredential) {
            // 如果连接返回了新的 deviceId，使用新的；否则保留旧的
            final newDeviceId = source.rememberDevice
                ? deviceId ?? savedCredential?.deviceId
                : null;
            await saveCredentialRequired(
              source.id,
              SourceCredential(password: password, deviceId: newDeviceId),
            );
          }

          // 更新最后连接时间
          await updateSource(source.copyWith(lastConnected: DateTime.now()));

          connection = SourceConnection(
            source: source,
            adapter: adapter,
            status: SourceStatus.connected,
          );
        case ConnectionFailure(:final error):
          await _disposeNasAdapter(adapter);
          connection = SourceConnection(
            source: source,
            adapter: adapter,
            status: SourceStatus.error,
            errorMessage: error,
          );
        case ConnectionRequires2FA():
          connection = SourceConnection(
            source: source,
            adapter: adapter,
            status: SourceStatus.requires2FA,
          );
      }

      _connections[source.id] = connection;
      return connection;
    } on Exception catch (e) {
      await _disposeNasAdapter(adapter);
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

  Future<void> _disposeNasAdapter(NasAdapter adapter) async {
    try {
      await adapter.disconnect();
    } on Exception catch (e, st) {
      logger.w('SourceManagerService: 断开 NAS 适配器失败', e, st);
    }
    try {
      await adapter.dispose();
    } on Exception catch (e, st) {
      logger.w('SourceManagerService: 释放 NAS 适配器失败', e, st);
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
      throw StateError(appL10n.sourceManagerErrorConnectionNotFound);
    }

    final adapter = connection.adapter;
    ConnectionResult? result;

    if (adapter is SynologyAdapter) {
      result = await adapter.verify2FA(otpCode, rememberDevice: rememberDevice);
    } else if (adapter is UGreenAdapter) {
      result = await adapter.verify2FA(otpCode, rememberDevice: rememberDevice);
    } else if (adapter is QnapAdapter) {
      result = await adapter.verify2FA(otpCode, rememberDevice: rememberDevice);
    } else if (adapter is FnOSAdapter) {
      result = await adapter.verify2FA(otpCode);
    }

    if (result != null) {
      SourceConnection newConnection;

      switch (result) {
        case ConnectionSuccess(:final deviceId):
          // 2FA 成功后，保存/更新凭证（包括设备ID）
          if (rememberDevice && deviceId != null) {
            logger.i('SourceManagerService: 2FA 成功，保存设备ID');
            // 获取现有凭证中的密码，必须等待完成
            final credential = await getCredential(sourceId);
            if (credential != null) {
              await saveCredentialRequired(
                sourceId,
                SourceCredential(
                  password: password ?? credential.password,
                  deviceId: deviceId,
                ),
              );
            } else if (password != null) {
              await saveCredentialRequired(
                sourceId,
                SourceCredential(password: password, deviceId: deviceId),
              );
            }
          } else if (!rememberDevice) {
            await clearDeviceId(sourceId);
          }

          // 更新最后连接时间
          await updateSource(
            connection.source.copyWith(lastConnected: DateTime.now()),
          );

          newConnection = connection.copyWith(status: SourceStatus.connected);

        case ConnectionFailure(:final error):
          newConnection = connection.copyWith(
            status: SourceStatus.error,
            errorMessage: error,
          );

        case ConnectionRequires2FA():
          newConnection = connection.copyWith(
            status: SourceStatus.error,
            errorMessage: appL10n.sourceManager2FAVerificationFailed,
          );
      }

      _connections[sourceId] = newConnection;
      return newConnection;
    }

    throw UnsupportedError(appL10n.sourceManagerError2FANotSupported);
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
    SourceType.jellyfin || SourceType.emby || SourceType.plex => true,
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
    final pending = _mediaServerConnectionAttempts[source.id];
    if (pending != null) return pending;
    final future = _connectMediaServer(
      source,
      password: password,
      apiKey: apiKey,
      saveCredential: saveCredential,
    );
    _mediaServerConnectionAttempts[source.id] = future;
    try {
      return await future;
    } finally {
      if (identical(_mediaServerConnectionAttempts[source.id], future)) {
        unawaited(_mediaServerConnectionAttempts.remove(source.id));
      }
    }
  }

  Future<MediaServerConnection> _connectMediaServer(
    SourceEntity source, {
    String? password,
    String? apiKey,
    required bool saveCredential,
  }) async {
    logger.i('SourceManagerService: 连接到媒体服务器 ${source.name}');

    if (!isMediaServerType(source.type)) {
      throw UnsupportedError(
        appL10n.sourceManagerErrorNotMediaServerType(source.type.displayName),
      );
    }

    final previous = _mediaServerConnections.remove(source.id);
    if (previous != null) {
      await _disposeMediaServerAdapter(previous.adapter);
    }

    // 创建适配器
    final adapter = _createMediaServerAdapter(source.type);

    // 更新状态为连接中
    _mediaServerConnections[source.id] = MediaServerConnection(
      source: source,
      adapter: adapter,
      status: SourceStatus.connecting,
    );

    final savedCredential = await getCredential(source.id);
    final resolvedPassword = password ?? savedCredential?.password;
    final resolvedApiKey = apiKey ?? source.apiKey ?? savedCredential?.apiKey;

    // 构建连接配置
    final serviceExtraConfig = <String, dynamic>{
      ...?source.extraConfig,
      if (source.accessToken?.isNotEmpty ?? false)
        'accessToken': source.accessToken,
      if (source.refreshToken?.isNotEmpty ?? false)
        'refreshToken': source.refreshToken,
    };

    final config = ServiceConnectionConfig(
      baseUrl: source.baseUrl,
      username: source.username.isNotEmpty ? source.username : null,
      password: resolvedPassword,
      apiKey: resolvedApiKey,
      extraConfig: serviceExtraConfig.isEmpty ? null : serviceExtraConfig,
      verifySSL: !InsecureHttpClient.trustSelfSigned,
    );

    try {
      final result = await adapter.connect(config);

      final connection = result.when(
        success: (_) => MediaServerConnection(
          source: source,
          adapter: adapter,
          status: SourceStatus.connected,
        ),
        failure: (error) => MediaServerConnection(
          source: source,
          adapter: adapter,
          status: SourceStatus.error,
          errorMessage: error,
        ),
      );

      if (connection.status == SourceStatus.connected) {
        // 保存凭证
        if (saveCredential && resolvedPassword != null) {
          await saveCredentialRequired(
            source.id,
            SourceCredential(password: resolvedPassword),
          );
        }
        // 更新最后连接时间
        await updateSource(source.copyWith(lastConnected: DateTime.now()));
      } else {
        await _disposeMediaServerAdapter(adapter);
      }

      _mediaServerConnections[source.id] = connection;
      return connection;
    } on Exception catch (e) {
      await _disposeMediaServerAdapter(adapter);
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

  Future<void> _disposeMediaServerAdapter(MediaServerAdapter adapter) async {
    try {
      await adapter.disconnect();
    } on Exception catch (e, st) {
      logger.w('SourceManagerService: 断开媒体服务器适配器失败', e, st);
    }
    try {
      await adapter.dispose();
    } on Exception catch (e, st) {
      logger.w('SourceManagerService: 释放媒体服务器适配器失败', e, st);
    }
  }

  /// 创建媒体服务器适配器
  MediaServerAdapter _createMediaServerAdapter(SourceType type) =>
      switch (type) {
        SourceType.jellyfin => JellyfinAdapter(),
        SourceType.emby => EmbyAdapter(),
        SourceType.plex => PlexAdapter(),
        _ => throw UnsupportedError(
          appL10n.sourceManagerErrorNotMediaServerType(type.displayName),
        ),
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
  Future<SourceConnection?> reconnect(
    String sourceId, {
    String? password,
  }) async {
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
      if (credential != null) {
        pwd = credential.password;
      } else if (!source.usesPasswordAuthentication) {
        pwd = '';
      } else {
        logger.e('SourceManagerService: 重连失败 - 没有保存的凭证 $sourceId');
        return null;
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
      final connection =
          await connect(
            source,
            password: pwd,
            saveCredential: false, // 凭证已保存，不需要再次保存
          ).timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              logger.w('SourceManagerService: 重连超时 $sourceId');
              // 注意：这里不创建新适配器，返回 null 表示超时
              // 由调用方处理超时情况
              throw TimeoutException(
                appL10n.sourceManagerErrorReconnectTimeout,
              );
            },
          );

      if (connection.status == SourceStatus.connected) {
        logger.i('SourceManagerService: 重连成功 $sourceId');
      } else {
        logger.e(
          'SourceManagerService: 重连失败 $sourceId: ${connection.errorMessage}',
        );
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
        logger.i(
          'SourceManagerService: 自动连接 ${source.type.displayName} ${source.name}',
        );
        try {
          final connection = await connect(
            source,
            password: '',
            saveCredential: false,
          ).timeout(timeout);

          if (connection.status == SourceStatus.connected) {
            logger.i('SourceManagerService: ${source.name} 自动连接成功');
          } else {
            logger.e(
              'SourceManagerService: ${source.name} 连接失败: ${connection.errorMessage}',
            );
          }
        } on TimeoutException {
          logger.w('SourceManagerService: ${source.name} 连接超时');
        }
        return;
      }

      final credential = await getCredential(source.id);
      if (credential != null || !source.usesPasswordAuthentication) {
        logger.i(
          'SourceManagerService: 自动连接 ${source.name} (deviceId: ${credential?.deviceId != null ? "有" : "无"})',
        );

        // 带重试的连接逻辑
        SourceConnection? connection;
        for (var attempt = 1; attempt <= maxRetries; attempt++) {
          if (attempt > 1) {
            logger.i(
              'SourceManagerService: ${source.name} 重试连接 (第 $attempt 次)',
            );
            // 重试前等待一小段时间
            await Future<void>.delayed(const Duration(seconds: 2));
          }

          try {
            // saveCredential=true 确保如果连接返回新的 deviceId，会被保存
            connection = await connect(
              source,
              password: credential?.password ?? '',
              saveCredential:
                  credential != null || source.usesPasswordAuthentication,
            ).timeout(timeout);

            // 如果连接成功或者需要2FA，不再重试
            if (connection.status == SourceStatus.connected ||
                connection.status == SourceStatus.requires2FA) {
              break;
            }
          } on TimeoutException {
            logger.w(
              'SourceManagerService: ${source.name} 连接超时 (第 $attempt 次)',
            );
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
              logger.w(
                'SourceManagerService: ${source.name} 需要2FA (deviceId 可能已失效)',
              );
            case SourceStatus.error:
              logger.e(
                'SourceManagerService: ${source.name} 连接失败: ${connection.errorMessage}',
              );
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
    SourceType.upnp => UpnpAdapter(),
    SourceType.local => LocalAdapter(),
    // 尚未接入的通用协议
    SourceType.nfs => throw UnsupportedError(
      appL10n.sourceManagerErrorProtocolNotImplemented(type.displayName),
    ),
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
    SourceType.opensubtitles => throw UnsupportedError(
      appL10n.sourceManagerErrorServiceTypeNotSupportedNas(type.displayName),
    ),
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
    SourceType.upnp => NasAdapterType.upnp,
    SourceType.local => NasAdapterType.local,
    // 尚未接入的通用协议
    SourceType.nfs => throw UnsupportedError(
      appL10n.sourceManagerErrorProtocolNotImplemented(type.displayName),
    ),
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
    SourceType.opensubtitles => throw UnsupportedError(
      appL10n.sourceManagerErrorServiceTypeNotSupportedNasType(
        type.displayName,
      ),
    ),
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
      final config = MediaLibraryConfig.fromJson(
        Map<String, dynamic>.from(data as Map),
      );
      logger.i(
        'SourceManagerService: 解析媒体库配置成功 - 视频路径: ${config.videoPaths.length}, 音乐路径: ${config.musicPaths.length}',
      );
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
