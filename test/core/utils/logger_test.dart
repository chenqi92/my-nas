import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/core/utils/logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mynas_logger_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          if (call.method == 'getApplicationCacheDirectory') {
            return tempDir.path;
          }
          return null;
        });
  });

  tearDown(() async {
    await logger.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('AppLogger redacts sensitive values before writing file logs', () async {
    await logger.initFileLogging();

    logger
      ..i(
        'headers = {Cookie: SID=secret; token=abc, '
        'x-api-key: top-secret, Authorization: Bearer auth-secret}',
      )
      ..w('url=https://example.com/path?token=query-secret&ok=1');

    await logger.close();

    final logPath = logger.logFilePath;
    expect(logPath, isNotNull);

    final content = await File(logPath!).readAsString();
    expect(content, contains('Cookie: <redacted>'));
    expect(content, contains('x-api-key: <redacted>'));
    expect(content, contains('Authorization: <redacted>'));
    expect(content, contains('token=<redacted>'));
    expect(content, isNot(contains('secret')));
  });
}
