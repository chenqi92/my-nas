import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/core/network/dio_client.dart';

void main() {
  test('setAllowSelfSignedCert can restore system certificate validation', () {
    final client = DioClient();

    expect(
      (client.dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient,
      isNull,
    );

    client.setAllowSelfSignedCert(allow: true);
    expect(
      (client.dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient,
      isNotNull,
    );

    client.setAllowSelfSignedCert(allow: false);
    expect(
      (client.dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient,
      isNull,
    );
  });
}
