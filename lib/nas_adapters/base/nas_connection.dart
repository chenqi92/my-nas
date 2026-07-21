import 'package:my_nas/nas_adapters/base/nas_adapter.dart';
import 'package:my_nas/core/network/network_endpoint.dart';

/// 连接配置
class ConnectionConfig {
  const ConnectionConfig({
    required this.type,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    this.useSsl = true,
    this.verifySSL = true,
    this.quickConnectId,
    this.deviceId,
    this.deviceName,
    this.enableDeviceToken = false,
    this.basePath,
    this.extraConfig,
  });

  factory ConnectionConfig.fromJson(
    Map<String, dynamic> json, {
    required String password,
  }) => ConnectionConfig(
    type: NasAdapterType.values.byName(json['type'] as String),
    host: json['host'] as String,
    port: json['port'] as int,
    username: json['username'] as String,
    password: password,
    useSsl: json['useSsl'] as bool? ?? true,
    verifySSL: json['verifySSL'] as bool? ?? true,
    quickConnectId: json['quickConnectId'] as String?,
    basePath: json['basePath'] as String?,
    extraConfig: json['extraConfig'] == null
        ? null
        : Map<String, dynamic>.from(json['extraConfig'] as Map),
  );

  final NasAdapterType type;
  final String host;
  final int port;
  final String username;
  final String password;
  final bool useSsl;
  final bool verifySSL;
  final String? quickConnectId;

  /// 设备ID，用于跳过二次验证
  final String? deviceId;

  /// 设备名称，用于记住设备
  final String? deviceName;

  /// 是否启用设备令牌
  final bool enableDeviceToken;

  /// 基础路径（如 WebDAV 的 /dav、/webdav），拼接到 baseUrl 末尾
  final String? basePath;

  /// Protocol-specific, non-secret settings such as FTP encryption mode.
  final Map<String, dynamic>? extraConfig;

  String get baseUrl => NetworkEndpoint.buildBaseUrl(
    host: host,
    port: port,
    useSsl: useSsl,
    basePath: basePath,
  );

  ConnectionConfig copyWith({
    NasAdapterType? type,
    String? host,
    int? port,
    String? username,
    String? password,
    bool? useSsl,
    bool? verifySSL,
    String? quickConnectId,
    String? deviceId,
    String? deviceName,
    bool? enableDeviceToken,
    String? basePath,
    Map<String, dynamic>? extraConfig,
  }) => ConnectionConfig(
    type: type ?? this.type,
    host: host ?? this.host,
    port: port ?? this.port,
    username: username ?? this.username,
    password: password ?? this.password,
    useSsl: useSsl ?? this.useSsl,
    verifySSL: verifySSL ?? this.verifySSL,
    quickConnectId: quickConnectId ?? this.quickConnectId,
    deviceId: deviceId ?? this.deviceId,
    deviceName: deviceName ?? this.deviceName,
    enableDeviceToken: enableDeviceToken ?? this.enableDeviceToken,
    basePath: basePath ?? this.basePath,
    extraConfig: extraConfig ?? this.extraConfig,
  );

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'host': host,
    'port': port,
    'username': username,
    'useSsl': useSsl,
    'verifySSL': verifySSL,
    'quickConnectId': quickConnectId,
    'basePath': basePath,
    'extraConfig': extraConfig,
  };
}

/// 连接结果
sealed class ConnectionResult {
  const ConnectionResult();
}

/// 连接成功
class ConnectionSuccess extends ConnectionResult {
  const ConnectionSuccess({
    required this.sessionId,
    this.serverInfo,
    this.deviceId,
  });

  final String sessionId;
  final ServerInfo? serverInfo;

  /// 设备ID，用于记住设备跳过二次验证
  final String? deviceId;
}

/// 连接失败
class ConnectionFailure extends ConnectionResult {
  const ConnectionFailure({required this.error, this.code});

  final String error;
  final int? code;
}

/// 需要二次验证
class ConnectionRequires2FA extends ConnectionResult {
  const ConnectionRequires2FA({required this.methods});

  final List<TwoFactorMethod> methods;
}

/// 服务器信息
class ServerInfo {
  const ServerInfo({
    required this.hostname,
    this.model,
    this.version,
    this.serial,
  });

  final String hostname;
  final String? model;
  final String? version;
  final String? serial;
}

/// 二次验证方式
enum TwoFactorMethod { totp, email, sms }
