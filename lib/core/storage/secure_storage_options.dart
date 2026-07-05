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
