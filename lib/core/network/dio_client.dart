import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:my_nas/core/constants/app_constants.dart';
import 'package:my_nas/core/errors/exceptions.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/core/network/tls_trust_store.dart';

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

    _dio.interceptors.addAll([_LoggingInterceptor(), _ErrorInterceptor()]);

    if (allowSelfSigned) {
      setAllowSelfSignedCert(allow: true);
    }
  }

  late final Dio _dio;

  Dio get dio => _dio;

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
    if (allow) {
      logger.i('DioClient: 允许自签名 SSL 证书');
      _replaceHttpClientAdapter(
        IOHttpClientAdapter(
          createHttpClient: () {
            final client = HttpClient()
              ..badCertificateCallback = (cert, host, port) {
                final accepted = TlsTrustStore.allowsInvalidCertificate(
                  cert,
                  host,
                  port,
                  allowSelfSigned: true,
                );
                if (accepted) {
                  logger.w('DioClient: 接受已固定的自签名证书 - host: $host, port: $port');
                }
                return accepted;
              };
            return client;
          },
        ),
      );
    } else {
      logger.i('DioClient: 使用系统 SSL 证书校验');
      _replaceHttpClientAdapter(IOHttpClientAdapter());
    }
  }

  void _replaceHttpClientAdapter(IOHttpClientAdapter adapter) {
    final oldAdapter = _dio.httpClientAdapter;
    _dio.httpClientAdapter = adapter;
    oldAdapter.close(force: true);
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
    final exception = switch (err.type) {
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
        message: err.message ?? appL10n.dioErrorUnknown,
        stackTrace: err.stackTrace,
        statusCode: err.response?.statusCode,
      ),
    };

    handler.reject(
      DioException(
        requestOptions: err.requestOptions,
        error: exception,
        type: err.type,
        response: err.response,
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
