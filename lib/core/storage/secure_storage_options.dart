import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:my_nas/core/utils/logger.dart';

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

final defaultSecureStorage = ResilientSecureStorage(
  const FlutterSecureStorage(
    aOptions: secureStorageAndroidOptions,
    iOptions: secureStorageIOSOptions,
    mOptions: secureStorageMacOsOptions,
  ),
);

/// OS-backed secure storage with a macOS Debug-only encrypted fallback.
///
/// A locally built macOS app cannot claim the Keychain entitlement without a
/// valid Apple development identity. Release/Profile builds remain on Keychain;
/// only unsigned Debug builds fall back to a device-bound encrypted Hive box.
class ResilientSecureStorage {
  ResilientSecureStorage(this._storage);

  final FlutterSecureStorage _storage;

  static const _fallbackBoxName = 'secure_storage_debug_fallback_v1';
  Box<String>? _fallbackBox;
  Future<Box<String>>? _fallbackInit;
  bool _fallbackActive = false;

  bool get _canUseFallback => kDebugMode && Platform.isMacOS;

  List<int> _deriveFallbackKey() {
    final material =
        '${Platform.localHostname}|mynas-secure-storage-debug-fallback|v1';
    return sha256.convert(utf8.encode(material)).bytes;
  }

  Future<Box<String>> _getFallbackBox() async {
    if (_fallbackBox != null && _fallbackBox!.isOpen) return _fallbackBox!;
    return _fallbackInit ??= _openFallbackBox();
  }

  Future<Box<String>> _openFallbackBox() async {
    try {
      final box = await Hive.openBox<String>(
        _fallbackBoxName,
        encryptionCipher: HiveAesCipher(_deriveFallbackKey()),
      );
      _fallbackBox = box;
      return box;
    } finally {
      _fallbackInit = null;
    }
  }

  bool _activateFallback(Object error, String operation) {
    if (!_canUseFallback || !isSecureStorageUnavailableError(error)) {
      return false;
    }
    if (!_fallbackActive) {
      logger.w(
        'ResilientSecureStorage: macOS Debug Keychain 不可用 ($operation)， '
        '已切换到本机 AES 加密存储。正式构建仍使用系统 Keychain。',
      );
    }
    _fallbackActive = true;
    return true;
  }

  void _activatePersistedFallback(String operation) {
    if (!_fallbackActive) {
      logger.w(
        'ResilientSecureStorage: macOS Debug Keychain 无该条目 ($operation)， '
        '已从本机 AES 加密存储恢复。正式构建仍使用系统 Keychain。',
      );
    }
    _fallbackActive = true;
  }

  Future<String?> _readPersistedFallback(String key) async {
    if (!_canUseFallback) return null;
    try {
      final value = (await _getFallbackBox()).get(key);
      if (value != null) _activatePersistedFallback('read');
      return value;
    } on Exception catch (error) {
      logger.w('ResilientSecureStorage: 读取 macOS Debug 加密备用存储失败', error);
      return null;
    }
  }

  Future<void> _deletePersistedFallback(String key) async {
    if (!_canUseFallback) return;
    try {
      await (await _getFallbackBox()).delete(key);
    } on Exception catch (error) {
      logger.w('ResilientSecureStorage: 删除 macOS Debug 加密备用存储失败', error);
    }
  }

  Future<void> write({required String key, required String value}) async {
    if (_fallbackActive) {
      await (await _getFallbackBox()).put(key, value);
      return;
    }
    try {
      await _storage.write(key: key, value: value);
    } on Exception catch (error) {
      if (!_activateFallback(error, 'write')) rethrow;
      await (await _getFallbackBox()).put(key, value);
    }
  }

  Future<String?> read({required String key}) async {
    if (_fallbackActive) return (await _getFallbackBox()).get(key);
    try {
      final value = await _storage.read(key: key);
      // Unsigned macOS Debug builds may successfully return null from
      // Keychain on a later process even though an earlier write had to use
      // the encrypted fallback. Recover that persisted value across restarts.
      return value ?? await _readPersistedFallback(key);
    } on Exception catch (error) {
      if (!_activateFallback(error, 'read')) rethrow;
      return (await _getFallbackBox()).get(key);
    }
  }

  Future<void> delete({required String key}) async {
    if (_fallbackActive) {
      await (await _getFallbackBox()).delete(key);
      return;
    }
    try {
      await _storage.delete(key: key);
      // Remove a value left by an earlier fallback process as well, otherwise
      // it could reappear after the primary Keychain entry is deleted.
      await _deletePersistedFallback(key);
    } on Exception catch (error) {
      if (!_activateFallback(error, 'delete')) rethrow;
      await (await _getFallbackBox()).delete(key);
    }
  }

  Future<void> deleteAll() async {
    if (_fallbackActive) {
      await (await _getFallbackBox()).clear();
      return;
    }
    try {
      await _storage.deleteAll();
      if (_canUseFallback) {
        try {
          await (await _getFallbackBox()).clear();
        } on Exception catch (error) {
          logger.w('ResilientSecureStorage: 清空 macOS Debug 加密备用存储失败', error);
        }
      }
    } on Exception catch (error) {
      if (!_activateFallback(error, 'deleteAll')) rethrow;
      await (await _getFallbackBox()).clear();
    }
  }

  Future<bool> containsKey({required String key}) async =>
      await read(key: key) != null;

  Future<Map<String, String>> readAll() async {
    if (_fallbackActive) {
      return Map<String, String>.from((await _getFallbackBox()).toMap());
    }
    try {
      final values = await _storage.readAll();
      if (values.isNotEmpty || !_canUseFallback) return values;
      final fallbackValues = Map<String, String>.from(
        (await _getFallbackBox()).toMap(),
      );
      if (fallbackValues.isNotEmpty) _activatePersistedFallback('readAll');
      return fallbackValues;
    } on Exception catch (error) {
      if (!_activateFallback(error, 'readAll')) rethrow;
      return Map<String, String>.from((await _getFallbackBox()).toMap());
    }
  }
}

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
  ResilientSecureStorage storage, {
  required String key,
  required String value,
}) async {
  await storage.write(key: key, value: value);
  final persistedValue = await storage.read(key: key);
  if (persistedValue == value) return;

  final error = SecureStoragePersistenceException(key);
  if (!storage._activateFallback(error, 'write verification')) throw error;

  // A Keychain write can report success while silently discarding the value.
  // Once the Debug fallback is active, retry the write there and verify it too.
  await storage.write(key: key, value: value);
  if (await storage.read(key: key) != value) throw error;
}

/// Whether an error means the OS-backed secret store is unavailable.
bool isSecureStorageUnavailableError(Object error) {
  if (error is SecureStoragePersistenceException) return true;
  if (error is! PlatformException) return false;
  return error.code == 'Unexpected security result code' ||
      (error.message?.contains('-34018') ?? false);
}
