import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/utils/hive_utils.dart';

/// 支持自签名证书的 HTTP 客户端
class InsecureHttpClient {
  InsecureHttpClient._();

  static http.Client? _client;

  /// 是否信任 HTTPS 自签名证书。
  ///
  /// 历史上网络层恒为放行（true），故默认保持 true 以不改变现状行为；可通过
  /// 「设置 · 数据源 · 信任自签名证书」持久化开关切换（见
  /// `trustSelfSignedCertProvider`）。该值在 [badCertificateCallback] 中被同步读取，
  /// 因此用静态字段缓存（关闭时拒绝自签名证书 = 默认安全校验）。
  static bool trustSelfSigned = true;

  static const _trustKey = 'trust_self_signed_cert';

  /// 在应用启动时从持久化存储恢复「信任自签名证书」开关。
  /// 需在首次发起 HTTPS 请求前调用（settings box 已打开）。失败时保持默认 true。
  static Future<void> loadTrustSetting() async {
    try {
      final box = await HiveUtils.getSettingsBox();
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
      ..badCertificateCallback = (cert, host, port) => trustSelfSigned;

    _client = IOClient(httpClient);
    return _client!;
  }

  /// GET 请求
  static Future<http.Response> get(Uri url, {Map<String, String>? headers}) => client.get(url, headers: headers);

  /// POST 请求
  static Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) => client.post(url, headers: headers, body: body);

  /// PUT 请求
  static Future<http.Response> put(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) => client.put(url, headers: headers, body: body);

  /// DELETE 请求
  static Future<http.Response> delete(
    Uri url, {
    Map<String, String>? headers,
  }) => client.delete(url, headers: headers);

  /// 关闭客户端
  static void close() {
    _client?.close();
    _client = null;
  }
}
