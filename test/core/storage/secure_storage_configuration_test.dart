import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/core/storage/secure_storage_options.dart';

void main() {
  const keychainGroup = r'$(AppIdentifierPrefix)group.com.kkape.mynas.app';

  test('all Apple app configurations enable the shared Keychain group', () {
    const entitlementFiles = <String>[
      'ios/Runner/Runner.entitlements',
      'macos/Runner/DebugProfile.entitlements',
      'macos/Runner/RunnerDebug.entitlements',
      'macos/Runner/Release.entitlements',
    ];

    for (final path in entitlementFiles) {
      final contents = File(path).readAsStringSync();
      expect(contents, contains('<key>keychain-access-groups</key>'));
      expect(contents, contains(keychainGroup), reason: path);
    }
  });

  test(
    'silent secure-storage write failures are classified as unavailable',
    () {
      expect(
        isSecureStorageUnavailableError(
          const SecureStoragePersistenceException('credential-key'),
        ),
        isTrue,
      );
    },
  );
}
