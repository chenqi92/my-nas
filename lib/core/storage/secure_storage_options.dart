import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Shared secure storage configuration for credentials and other sensitive data.
///
/// Android v10 uses RSA OAEP + AES-GCM by default. Backup-protected migration
/// keeps existing v9 encryptedSharedPreferences data recoverable if the app is
/// killed during cipher migration.
const secureStorageAndroidOptions = AndroidOptions(
  migrateOnAlgorithmChange: true,
  migrateWithBackup: true,
);

const secureStorageIOSOptions = IOSOptions(
  accessibility: KeychainAccessibility.first_unlock_this_device,
);

const secureStorageMacOsOptions = MacOsOptions(
  accessibility: KeychainAccessibility.first_unlock_this_device,
);

const defaultSecureStorage = FlutterSecureStorage(
  aOptions: secureStorageAndroidOptions,
  iOptions: secureStorageIOSOptions,
  mOptions: secureStorageMacOsOptions,
);

/// Thrown when the platform reports a successful write but the secret cannot
/// be read back. This is how a missing Apple Keychain entitlement can surface.
class SecureStoragePersistenceException implements Exception {
  const SecureStoragePersistenceException(this.key);

  final String key;

  @override
  String toString() => '安全存储写入校验失败（key: $key）';
}

/// Writes a secret and verifies that it was actually persisted.
///
/// Some Keychain configurations return from `write` without throwing while
/// silently discarding the value. Never log [value] from this helper.
Future<void> writeSecureValueVerified(
  FlutterSecureStorage storage, {
  required String key,
  required String value,
}) async {
  await storage.write(key: key, value: value);
  final persistedValue = await storage.read(key: key);
  if (persistedValue != value) {
    throw SecureStoragePersistenceException(key);
  }
}

/// Whether an error means the OS-backed secret store is unavailable.
bool isSecureStorageUnavailableError(Object error) {
  if (error is SecureStoragePersistenceException) return true;
  if (error is! PlatformException) return false;
  return error.code == 'Unexpected security result code' ||
      (error.message?.contains('-34018') ?? false);
}
