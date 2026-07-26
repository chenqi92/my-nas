import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/core/network/dio_client.dart';

void main() {
  test('strict mode keeps the endpoint certificate pin callback installed', () {
    final client = DioClient();

    expect(
      (client.dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient,
      isNotNull,
    );

    client.setAllowSelfSignedCert(allow: true);
    expect(
      (client.dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient,
      isNotNull,
    );

    client.setAllowSelfSignedCert(allow: false);
    expect(
      (client.dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient,
      isNotNull,
    );
  });

  test('shared TLS configuration is idempotent', () {
    final dio = DioClient.createTlsAware();
    final interceptorCount = dio.interceptors.length;

    expect(
      (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient,
      isNotNull,
    );
    expect(interceptorCount, greaterThan(0));

    DioClient.configureTls(dio);
    expect(dio.interceptors, hasLength(interceptorCount));

    dio.close(force: true);
  });
}
