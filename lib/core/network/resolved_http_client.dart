import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:my_nas/core/errors/exceptions.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/network/hosts_resolver_service.dart';
import 'package:my_nas/core/network/tls_trust_store.dart';

/// 支持应用内 hosts 映射的 HTTP 客户端
///
/// 实现原理：注入 [HttpClient.connectionFactory]，在 TCP 建连前把请求 URL 中的
/// host 替换为 [HostsResolverService] 中配置的 IP；HTTPS 由 dart:io 内部用
/// 原始 URL 的 host 做 SNI 和证书校验，所以证书不会被拒。
///
/// 用法：
/// ```dart
/// final response = await ResolvedHttpClient.get(uri);
/// ```
class ResolvedHttpClient {
  ResolvedHttpClient._();

  static http.Client? _client;

  /// 共享的 [http.Client]，按需懒加载。
  ///
  /// 复用同一个客户端可让 HTTP 连接池生效。
  static http.Client get client {
    if (_client != null) return _client!;

    final httpClient = HttpClient()
      ..badCertificateCallback =
          (certificate, host, port) => TlsTrustStore.allowsInvalidCertificate(
                certificate,
                host,
                port,
                allowSelfSigned: false,
              );
    apply(httpClient);

    _client = IOClient(httpClient);
    return _client!;
  }

  /// 包装外部传入的 HttpClient（用于 dio 等需要传入自定义 HttpClient 的场景）
  ///
  /// 调用方完全控制 HttpClient 的生命周期，本函数只是注入 connectionFactory。
  static void apply(HttpClient httpClient, {bool allowSelfSigned = false}) {
    httpClient.connectionFactory =
        (uri, proxyHost, proxyPort) => _connectionFactory(
              uri,
              proxyHost,
              proxyPort,
              allowSelfSigned: allowSelfSigned,
            );
  }

  static Future<ConnectionTask<Socket>> _connectionFactory(
    Uri uri,
    String? proxyHost,
    int? proxyPort, {
    required bool allowSelfSigned,
  }) async {
    // 走代理时跳过 hosts 映射 —— 代理服务器自己负责解析目标域名
    if (proxyHost != null && proxyPort != null) {
      return Socket.startConnect(proxyHost, proxyPort);
    }

    final resolved = HostsResolverService.instance.resolve(uri.host);
    final targetHost = resolved ?? uri.host;
    final socketTask = await Socket.startConnect(targetHost, uri.port);
    if (uri.scheme.toLowerCase() != 'https') return socketTask;

    // Supplying HttpClient.connectionFactory makes Dart expect an already
    // secure socket for direct HTTPS connections. Upgrade explicitly while
    // retaining the original host for SNI/certificate validation, even when
    // the TCP destination came from the application Hosts mapping.
    final secureSocket = socketTask.socket.then<Socket>(
      (socket) => SecureSocket.secure(
        socket,
        host: uri.host,
        onBadCertificate: (certificate) =>
            TlsTrustStore.allowsInvalidCertificate(
          certificate,
          uri.host,
          uri.port,
          allowSelfSigned: allowSelfSigned,
        ),
      ),
    );
    return ConnectionTask.fromSocket<Socket>(secureSocket, socketTask.cancel);
  }

  static Future<http.Response> get(Uri url, {Map<String, String>? headers}) =>
      _withTlsRetry(url, () => client.get(url, headers: headers));

  static Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) =>
      _withTlsRetry(url, () => client.post(url, headers: headers, body: body));

  static Future<http.Response> put(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) =>
      _withTlsRetry(url, () => client.put(url, headers: headers, body: body));

  static Future<http.Response> delete(
    Uri url, {
    Map<String, String>? headers,
  }) =>
      _withTlsRetry(url, () => client.delete(url, headers: headers));

  static Future<T> _withTlsRetry<T>(
    Uri url,
    Future<T> Function() request,
  ) async {
    try {
      return await request();
    } on Exception catch (error, stackTrace) {
      if (url.scheme.toLowerCase() != 'https') rethrow;
      final decision = await TlsTrustStore.requestTrustForEndpoint(url);
      if (decision == TlsTrustDecision.trusted) return request();
      if (decision == TlsTrustDecision.declined) {
        throw TlsCertificateTrustDeclinedException(
          message: appL10n.tlsCertificateTrustDeclined,
          stackTrace: stackTrace,
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  static void close() {
    _client?.close();
    _client = null;
  }
}
