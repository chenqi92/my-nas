import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/errors/exceptions.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/network/tls_trust_store.dart';
import 'package:my_nas/core/utils/hive_utils.dart';

/// 支持自签名证书的 HTTP 客户端
class InsecureHttpClient {
  InsecureHttpClient._();

  static http.Client? _client;

  /// 是否信任 HTTPS 自签名证书。
  ///
  /// 默认使用系统证书校验；只有用户显式开启
  /// 「设置 · 数据源 · 信任自签名证书」时才放行无效证书（见
  /// `trustSelfSignedCertProvider`）。该值在 [badCertificateCallback] 中被同步读取，
  /// 因此用静态字段缓存（关闭时拒绝自签名证书 = 默认安全校验）。
  static bool trustSelfSigned = false;

  static const _trustKey = 'trust_self_signed_cert';

  /// 在应用启动时从持久化存储恢复「信任自签名证书」开关。
  /// 需在首次发起 HTTPS 请求前调用（settings box 已打开）。失败时保持默认 false。
  static Future<void> loadTrustSetting() async {
    try {
      final box = await HiveUtils.getSettingsBox();
      await TlsTrustStore.load();
      final v = box.get(_trustKey) as bool?;
      if (v != null) trustSelfSigned = v;
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '加载信任自签名证书设置失败，使用默认值');
    }
  }

  /// 获取 HTTP 客户端：HTTPS 自签名证书是否放行随 [trustSelfSigned] 实时生效。
  static http.Client get client {
    if (_client != null) return _client!;

    final httpClient = HttpClient()
      ..badCertificateCallback =
          (cert, host, port) => TlsTrustStore.allowsInvalidCertificate(
                cert,
                host,
                port,
                allowSelfSigned: trustSelfSigned,
              );

    _client = IOClient(httpClient);
    return _client!;
  }

  /// Creates an isolated client for an adapter with an explicit TLS policy.
  static http.Client createClient({required bool allowSelfSigned}) {
    final httpClient = HttpClient()
      ..badCertificateCallback =
          (cert, host, port) => TlsTrustStore.allowsInvalidCertificate(
                cert,
                host,
                port,
                allowSelfSigned: allowSelfSigned,
              );
    return IOClient(httpClient);
  }

  /// GET 请求
  static Future<http.Response> get(Uri url, {Map<String, String>? headers}) =>
      _withTlsRetry(url, () => client.get(url, headers: headers));

  /// POST 请求
  static Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) =>
      _withTlsRetry(url, () => client.post(url, headers: headers, body: body));

  /// PUT 请求
  static Future<http.Response> put(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) =>
      _withTlsRetry(url, () => client.put(url, headers: headers, body: body));

  /// DELETE 请求
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
      if (url.scheme.toLowerCase() != 'https' ||
          !TlsTrustStore.isCertificateValidationError(error)) {
        rethrow;
      }
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

  /// 关闭客户端
  static void close() {
    _client?.close();
    _client = null;
  }
}
