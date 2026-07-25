import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:my_nas/core/storage/secure_storage_options.dart';
import 'package:my_nas/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('application reaches its first Flutter frame', (tester) async {
    final previousErrorWidgetBuilder = ErrorWidget.builder;
    await app.main(const []);
    await tester.pump(const Duration(seconds: 3));

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(tester.takeException(), isNull);

    const secureStorageTestKey =
        'com.kkape.mynas.integration_test.secure_storage';
    const secureStorageTestValue = 'verified';
    await defaultSecureStorage.delete(key: secureStorageTestKey);
    addTearDown(() => defaultSecureStorage.delete(key: secureStorageTestKey));
    await writeSecureValueVerified(
      defaultSecureStorage,
      key: secureStorageTestKey,
      value: secureStorageTestValue,
    );
    expect(
      await defaultSecureStorage.read(key: secureStorageTestKey),
      secureStorageTestValue,
    );
    await defaultSecureStorage.delete(key: secureStorageTestKey);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    ErrorWidget.builder = previousErrorWidgetBuilder;
  });
}
