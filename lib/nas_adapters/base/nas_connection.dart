import 'package:my_nas/nas_adapters/base/nas_adapter.dart';

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
  });

  factory ConnectionConfig.fromJson(
    Map<String, dynamic> json, {
    required String password,
  }) =>
      ConnectionConfig(
        type: NasAdapterType.values.byName(json['type'] as String),
        host: json['host'] as String,
        port: json['port'] as int,
        username: json['username'] as String,
        password: password,
        useSsl: json['useSsl'] as bool? ?? true,
        verifySSL: json['verifySSL'] as bool? ?? true,
        quickConnectId: json['quickConnectId'] as String?,
        basePath: json['basePath'] as String?,
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

  String get baseUrl {
    // 容错：如果用户把完整 URL（含协议/端口/路径）填到了 host 字段，自动拆解。
    var effectiveProtocol = useSsl ? 'https' : 'http';
    var effectiveHost = host;
    var effectivePort = port;
    var pathFromHost = '';

    final lowerHost = host.toLowerCase();
    if (lowerHost.startsWith('http://') || lowerHost.startsWith('https://')) {
      final parsed = Uri.tryParse(host);
      if (parsed != null && parsed.host.isNotEmpty) {
        effectiveProtocol = parsed.scheme;
        effectiveHost = parsed.host;
        if (parsed.hasPort) {
          effectivePort = parsed.port;
        }
        pathFromHost = parsed.path;
      }
    } else if (host.contains('/')) {
      // 不带协议但带路径，如 webdav.123pan.cn/webdav
      final slashIdx = host.indexOf('/');
      effectiveHost = host.substring(0, slashIdx);
      pathFromHost = host.substring(slashIdx);
    }

    final root = '$effectiveProtocol://$effectiveHost:$effectivePort';

    // 合并 host 中带的路径与显式 basePath，去重、规范化
    final combined = StringBuffer();
    void append(String? seg) {
      if (seg == null || seg.isEmpty) return;
      var s = seg.startsWith('/') ? seg : '/$seg';
      if (s.endsWith('/') && s.length > 1) s = s.substring(0, s.length - 1);
      // 避免重复拼接（如 host 已含 /webdav 且 basePath 也是 /webdav）
      if (combined.toString().endsWith(s)) return;
      combined.write(s);
    }

    append(pathFromHost);
    append(basePath);

    return '$root$combined';
  }

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
  }) =>
      ConnectionConfig(
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
  const ConnectionFailure({
    required this.error,
    this.code,
  });

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
enum TwoFactorMethod {
  totp,
  email,
  sms,
}
