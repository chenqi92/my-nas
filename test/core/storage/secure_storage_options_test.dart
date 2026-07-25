import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';
import 'package:my_nas/core/storage/secure_storage_options.dart';

class _MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory hiveDirectory;

  setUp(() async {
    hiveDirectory = await Directory.systemTemp.createTemp(
      'my_nas_secure_storage_test_',
    );
    Hive.init(hiveDirectory.path);
  });

  tearDown(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  test(
    'macOS Debug encrypted fallback survives a new storage instance',
    () async {
      const key = 'source_credential_test';
      const secret = 'encrypted-test-secret';

      final unavailableKeychain = _MockFlutterSecureStorage();
      when(() => unavailableKeychain.write(key: key, value: secret)).thenThrow(
        PlatformException(code: 'Unexpected security result code'),
      );

      final firstProcess = ResilientSecureStorage(unavailableKeychain);
      await firstProcess.write(key: key, value: secret);

      // A later process may get a successful null from Keychain instead of
      // the original entitlement error. It must still recover the fallback.
      final emptyKeychain = _MockFlutterSecureStorage();
      when(() => emptyKeychain.read(key: key)).thenAnswer((_) async => null);
      when(() => emptyKeychain.delete(key: key)).thenAnswer((_) async {});

      final secondProcess = ResilientSecureStorage(emptyKeychain);
      expect(await secondProcess.read(key: key), secret);

      await secondProcess.delete(key: key);

      final thirdProcess = ResilientSecureStorage(emptyKeychain);
      expect(await thirdProcess.read(key: key), isNull);
    },
    skip: !Platform.isMacOS,
  );
}
