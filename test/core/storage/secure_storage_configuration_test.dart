import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/core/storage/secure_storage_options.dart';

void main() {
  const keychainGroup = r'$(AppIdentifierPrefix)group.com.kkape.mynas.app';

  test('signed Apple app configurations enable the shared Keychain group', () {
    const signedEntitlementFiles = <String>[
      'ios/Runner/Runner.entitlements',
      'macos/Runner/DebugProfile.entitlements',
      'macos/Runner/Release.entitlements',
    ];

    for (final path in signedEntitlementFiles) {
      final contents = File(path).readAsStringSync();
      expect(contents, contains('<key>keychain-access-groups</key>'));
      expect(contents, contains(keychainGroup), reason: path);
    }
  });

  test('ad-hoc macOS Debug avoids restricted signing entitlements', () {
    final entitlements = File(
      'macos/Runner/RunnerDebug.entitlements',
    ).readAsStringSync();
    expect(entitlements, isNot(contains('<key>keychain-access-groups</key>')));
    expect(entitlements, isNot(contains(keychainGroup)));

    final project = File(
      'macos/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    expect(project, contains('CODE_SIGNING_ALLOWED = NO;'));
    expect(project, contains('CODE_SIGNING_REQUIRED = NO;'));

    final scheme = File(
      'macos/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme',
    ).readAsStringSync();
    expect(scheme, contains('Ad-hoc Sign Debug App'));
    expect(scheme, contains('/usr/bin/codesign --force --deep --sign -'));
    expect(scheme, isNot(contains('--entitlements')));
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
