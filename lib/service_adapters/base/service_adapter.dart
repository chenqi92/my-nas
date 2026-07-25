import 'package:my_nas/core/network/http_client.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';

/// 服务适配器基础接口
///
/// 用于非文件系统类型的服务源，如下载工具、媒体追踪、媒体管理等
abstract class ServiceAdapter {
  /// 适配器信息
  ServiceAdapterInfo get info;

  /// 是否已连接
  bool get isConnected;

  /// 当前连接配置
  ServiceConnectionConfig? get connection;

  /// 连接到服务
  Future<ServiceConnectionResult> connect(ServiceConnectionConfig config);

  /// 断开连接
  Future<void> disconnect();

  /// 释放资源
  Future<void> dispose();
}

/// 适配器信息
class ServiceAdapterInfo {
  const ServiceAdapterInfo({
    required this.name,
    required this.type,
    this.version,
    this.description,
  });

  final String name;
  final SourceType type;
  final String? version;
  final String? description;
}

/// 服务连接配置
class ServiceConnectionConfig {
  const ServiceConnectionConfig({
    required this.baseUrl,
    this.username,
    this.password,
    this.apiKey,
    this.extraConfig,
    this.verifySSL = true,
  });

  /// 从 SourceEntity 创建配置
  factory ServiceConnectionConfig.fromSource(
    SourceEntity source, {
    String? password,
  }) => ServiceConnectionConfig(
    baseUrl: source.baseUrl,
    username: source.username,
    password: password,
    apiKey: source.apiKey,
    extraConfig: source.extraConfig,
    verifySSL: !InsecureHttpClient.trustSelfSigned,
  );

  final String baseUrl;
  final String? username;
  final String? password;
  final String? apiKey;
  final Map<String, dynamic>? extraConfig;
  final bool verifySSL;

  /// 创建一份更新后的连接配置。
  ///
  /// 媒体服务器在账号登录后会取得运行期 access token；将它合并回配置，
  /// 可以让 WebSocket 等连接后的能力复用同一份认证信息。
  ServiceConnectionConfig copyWith({
    String? baseUrl,
    String? username,
    String? password,
    String? apiKey,
    Map<String, dynamic>? extraConfig,
    bool? verifySSL,
  }) => ServiceConnectionConfig(
    baseUrl: baseUrl ?? this.baseUrl,
    username: username ?? this.username,
    password: password ?? this.password,
    apiKey: apiKey ?? this.apiKey,
    extraConfig: extraConfig ?? this.extraConfig,
    verifySSL: verifySSL ?? this.verifySSL,
  );
}

/// 服务连接结果（sealed class 用于类型安全的错误处理）
sealed class ServiceConnectionResult {
  const ServiceConnectionResult();

  /// 连接成功时的处理
  T when<T>({
    required T Function(ServiceAdapter adapter) success,
    required T Function(String error) failure,
  }) => switch (this) {
    ServiceConnectionSuccess(:final adapter) => success(adapter),
    ServiceConnectionFailure(:final error) => failure(error),
  };
}

/// 连接成功
class ServiceConnectionSuccess extends ServiceConnectionResult {
  const ServiceConnectionSuccess(this.adapter);
  final ServiceAdapter adapter;
}

/// 连接失败
class ServiceConnectionFailure extends ServiceConnectionResult {
  const ServiceConnectionFailure(this.error);
  final String error;
}
