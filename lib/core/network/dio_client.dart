import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:my_nas/core/constants/app_constants.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/errors/exceptions.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/network/resolved_http_client.dart';
import 'package:my_nas/core/network/tls_trust_store.dart';
import 'package:my_nas/core/utils/logger.dart';

class DioClient {
  DioClient({String? baseUrl, bool allowSelfSigned = false}) {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl ?? '',
        connectTimeout: AppConstants.connectionTimeout,
        receiveTimeout: AppConstants.receiveTimeout,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    _dio.interceptors.addAll([
      _LoggingInterceptor(),
      _TlsTrustInterceptor(_dio, allowSelfSigned: allowSelfSigned),
      _ErrorInterceptor(),
    ]);

    // Always install the endpoint-pin callback. In strict mode it only accepts
    // certificates that the user explicitly trusted for this host:port.
    setAllowSelfSignedCert(allow: allowSelfSigned);
  }

  late final Dio _dio;

  Dio get dio => _dio;

  /// Creates a Dio instance that participates in the app-wide HTTPS trust
  /// prompt without changing the caller's existing response/error semantics.
  static Dio createTlsAware({
    BaseOptions? options,
    bool allowSelfSigned = false,
  }) {
    final dio = Dio(options);
    configureTls(dio, allowSelfSigned: allowSelfSigned);
    return dio;
  }

  /// Adds endpoint certificate pinning, one-tap trust, automatic retry, and
  /// application Hosts mapping to an existing Dio instance.
  static Dio configureTls(Dio dio, {bool allowSelfSigned = false}) {
    if (!dio.interceptors.any(
      (interceptor) => interceptor is _TlsTrustInterceptor,
    )) {
      dio.interceptors.insert(
        0,
        _TlsTrustInterceptor(dio, allowSelfSigned: allowSelfSigned),
      );
    }
    _replaceAdapter(dio, _tlsAdapter(allowSelfSigned: allowSelfSigned));
    return dio;
  }

  void updateBaseUrl(String baseUrl) {
    logger.i('DioClient: 更新 baseUrl => $baseUrl');
    _dio.options.baseUrl = baseUrl;
  }

  void updateHeaders(Map<String, dynamic> headers) {
    _dio.options.headers.addAll(headers);
  }

  void addInterceptor(Interceptor interceptor) {
    _dio.interceptors.add(interceptor);
  }

  /// 设置是否允许自签名证书
  void setAllowSelfSignedCert({required bool allow}) {
    logger.i(
      allow ? 'DioClient: 允许自签名 SSL 证书' : 'DioClient: 使用系统校验和已保存的 HTTPS 证书指纹',
    );
    _replaceHttpClientAdapter(_tlsAdapter(allowSelfSigned: allow));
  }

  static IOHttpClientAdapter _tlsAdapter({required bool allowSelfSigned}) =>
      IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient()
            ..badCertificateCallback = (cert, host, port) {
              final accepted = TlsTrustStore.allowsInvalidCertificate(
                cert,
                host,
                port,
                allowSelfSigned: allowSelfSigned,
              );
              if (accepted) {
                logger.w('DioClient: 接受已固定的证书 - host: $host, port: $port');
              }
              return accepted;
            };
          ResolvedHttpClient.apply(client, allowSelfSigned: allowSelfSigned);
          return client;
        },
      );

  void _replaceHttpClientAdapter(IOHttpClientAdapter adapter) {
    _replaceAdapter(_dio, adapter);
  }

  static void _replaceAdapter(Dio dio, IOHttpClientAdapter adapter) {
    final oldAdapter = dio.httpClientAdapter;
    dio.httpClientAdapter = adapter;
    oldAdapter.close(force: true);
  }
}

class _TlsTrustInterceptor extends Interceptor {
  _TlsTrustInterceptor(this._dio, {required bool allowSelfSigned})
    : _allowSelfSigned = allowSelfSigned;

  static const _retryKey = 'mynas.tlsTrustRetried';

  final Dio _dio;
  final bool _allowSelfSigned;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.requestOptions.extra[_retryKey] == true ||
        !_shouldInspectCertificate(err)) {
      handler.next(err);
      return;
    }
    AppError.fireAndForget(
      _requestTrustAndRetry(err, handler),
      action: 'dioClient.requestTlsTrustAndRetry',
    );
  }

  bool _shouldInspectCertificate(DioException err) {
    if (err.response != null ||
        err.requestOptions.uri.scheme.toLowerCase() != 'https') {
      return false;
    }
    if (TlsTrustStore.isCertificateValidationError(err.error)) return true;

    // On some Dart/Android stacks a rejected certificate is surfaced by Dio
    // only as this generic HttpException. The follow-up TLS probe is safe: it
    // has no HTTP request or credentials and returns notRequired when the
    // endpoint certificate is system-valid.
    final message = '${err.error} ${err.message}'.toLowerCase();
    return message.contains('connection closed before full header') ||
        message.contains('connection terminated during handshake');
  }

  Future<void> _requestTrustAndRetry(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    try {
      final decision = await TlsTrustStore.requestTrustForEndpoint(
        err.requestOptions.uri,
      );
      if (decision == TlsTrustDecision.declined) {
        handler.reject(
          DioException(
            requestOptions: err.requestOptions,
            response: err.response,
            type: err.type,
            stackTrace: err.stackTrace,
            message: appL10n.tlsCertificateTrustDeclined,
            error: TlsCertificateTrustDeclinedException(
              message: appL10n.tlsCertificateTrustDeclined,
              stackTrace: err.stackTrace,
            ),
          ),
        );
        return;
      }
      if (decision != TlsTrustDecision.trusted) {
        handler.next(err);
        return;
      }

      err.requestOptions.extra[_retryKey] = true;
      // Dart's HttpClient can retain the failed TLS connection/session. A new
      // adapter guarantees the retry performs a fresh handshake that consults
      // the certificate pin saved just above.
      DioClient._replaceAdapter(
        _dio,
        DioClient._tlsAdapter(allowSelfSigned: _allowSelfSigned),
      );
      final response = await _dio.fetch<dynamic>(err.requestOptions);
      handler.resolve(response);
    } on DioException catch (retryError, st) {
      AppError.ignore(retryError, st, 'TLS 信任后重试仍失败，交回 Dio 错误链处理');
      handler.next(retryError);
    } on Object catch (e, st) {
      AppError.handle(e, st, 'dioClient.requestTlsTrustAndRetry', {
        'uri': err.requestOptions.uri.toString(),
      });
      handler.next(err);
    }
  }
}

class _LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    logger.d('REQUEST[${options.method}] => PATH: ${options.path}');
    super.onRequest(options, handler);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    logger.d(
      'RESPONSE[${response.statusCode}] => PATH: ${response.requestOptions.path}',
    );
    super.onResponse(response, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    logger.e(
      'ERROR[${err.response?.statusCode}] => PATH: ${err.requestOptions.path}',
      err,
      err.stackTrace,
    );
    super.onError(err, handler);
  }
}

class _ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final exception = err.error is TlsCertificateTrustDeclinedException
        ? err.error! as TlsCertificateTrustDeclinedException
        : TlsTrustStore.isCertificateValidationError(err.error)
        ? TlsCertificateException(
            message: appL10n.tlsCertificateValidationFailed,
            stackTrace: err.stackTrace,
          )
        : switch (err.type) {
            DioExceptionType.connectionTimeout ||
            DioExceptionType.sendTimeout ||
            DioExceptionType.receiveTimeout => NetworkException(
              message: appL10n.dioErrorConnectionTimeout,
              stackTrace: err.stackTrace,
            ),
            DioExceptionType.connectionError => NetworkException(
              message: appL10n.dioErrorNetworkFailed,
              stackTrace: err.stackTrace,
            ),
            DioExceptionType.badResponse => _handleBadResponse(err),
            DioExceptionType.cancel => NetworkException(
              message: appL10n.dioErrorCancelled,
              stackTrace: err.stackTrace,
            ),
            _ => ServerException(
              message:
                  err.message ??
                  err.error?.toString() ??
                  appL10n.dioErrorUnknown,
              stackTrace: err.stackTrace,
              statusCode: err.response?.statusCode,
            ),
          };

    handler.reject(
      DioException(
        requestOptions: err.requestOptions,
        error: exception,
        message: exception.message,
        type: err.type,
        response: err.response,
        stackTrace: err.stackTrace,
      ),
    );
  }

  AppException _handleBadResponse(DioException err) {
    final statusCode = err.response?.statusCode;
    return switch (statusCode) {
      401 => AuthException(
        message: appL10n.dioErrorAuthFailed,
        stackTrace: err.stackTrace,
      ),
      403 => AuthException(
        message: appL10n.dioErrorForbidden,
        stackTrace: err.stackTrace,
      ),
      404 => ServerException(
        message: appL10n.dioErrorNotFound,
        statusCode: statusCode,
        stackTrace: err.stackTrace,
      ),
      final code when code != null && code >= 500 => ServerException(
        message: appL10n.dioErrorServer,
        statusCode: code,
        stackTrace: err.stackTrace,
      ),
      _ => ServerException(
        message: err.message ?? appL10n.dioErrorRequestFailed,
        statusCode: statusCode,
        stackTrace: err.stackTrace,
      ),
    };
  }
}
