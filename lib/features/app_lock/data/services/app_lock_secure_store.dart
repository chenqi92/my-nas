import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/storage/fallback_box_key.dart';
import 'package:my_nas/core/storage/secure_storage_options.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/pbkdf2.dart';
import 'package:pointycastle/macs/hmac.dart';

class _Pbkdf2Request {
  const _Pbkdf2Request({
    required this.pin,
    required this.salt,
    required this.iterations,
    required this.hashLengthBytes,
  });

  final String pin;
  final Uint8List salt;
  final int iterations;
  final int hashLengthBytes;
}

Uint8List _derivePbkdf2InIsolate(_Pbkdf2Request request) {
  final params = Pbkdf2Parameters(
    request.salt,
    request.iterations,
    request.hashLengthBytes,
  );
  final kdf = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))..init(params);
  return kdf.process(Uint8List.fromList(utf8.encode(request.pin)));
}

/// 应用锁安全存储
///
/// 仅存 PIN 的 PBKDF2-HMAC-SHA256 哈希 + salt，永不保存明文 PIN。
/// 复用 AuthStorageService 的"Keychain → Hive AES 降级"模式：当系统
/// 安全存储不可用（macOS 未配置 entitlement 等）时切到本地加密 box，
/// 安全级别低于 Keychain 但避免明文持久化。
class AppLockSecureStore {
  AppLockSecureStore() : _storage = defaultSecureStorage;

  final ResilientSecureStorage _storage;

  bool _storageAvailable = true;
  bool _fallbackActive = false;
  Box<String>? _fallbackBox;
  Future<Box<String>>? _fallbackInit;

  static const _fallbackBoxName = 'app_lock_fallback_v1';
  static const _keyHash = 'app_lock_pin_hash';
  static const _keySalt = 'app_lock_pin_salt';

  /// PBKDF2 迭代次数。100k 是当前对移动设备友好的最低基线。
  static const _pbkdf2Iterations = 100000;
  static const _saltLengthBytes = 16;
  static const _hashLengthBytes = 32;

  bool _handleStorageError(Object error, String operation) {
    if (isSecureStorageUnavailableError(error) || error is PlatformException) {
      if (isSecureStorageUnavailableError(error) ||
          (error is PlatformException &&
              (error.message?.contains('entitlement') ?? false))) {
        if (_storageAvailable) {
          logger.w(
            'AppLockSecureStore: 系统安全存储不可用 ($operation)， '
            '已切换到本地加密降级 box',
          );
        }
        _storageAvailable = false;
        _fallbackActive = true;
        return true;
      }
    }
    return false;
  }

  Future<Box<String>> _getFallbackBox() async {
    if (_fallbackBox != null && _fallbackBox!.isOpen) return _fallbackBox!;
    return _fallbackInit ??= _openFallbackBox();
  }

  Future<Box<String>> _openFallbackBox() async {
    try {
      final box = await FallbackBoxKey.openBox(
        _fallbackBoxName,
        domain: 'mynas-app-lock-fallback',
        legacyMaterial: '${Platform.localHostname}|mynas-app-lock-fallback|v1',
      );
      _fallbackBox = box;
      return box;
    } finally {
      _fallbackInit = null;
    }
  }

  Future<String?> _safeRead(String key) async {
    if (_fallbackActive) return _fallbackRead(key);
    try {
      return await _storage.read(key: key);
    } on Exception catch (e) {
      if (_handleStorageError(e, 'read($key)')) return _fallbackRead(key);
      rethrow;
    }
  }

  Future<bool> _safeWrite(String key, String value) async {
    if (_fallbackActive) return _fallbackWrite(key, value);
    try {
      await writeSecureValueVerified(_storage, key: key, value: value);
      return true;
    } on Exception catch (e) {
      if (_handleStorageError(e, 'write($key)')) {
        return _fallbackWrite(key, value);
      }
      rethrow;
    }
  }

  Future<bool> _safeDelete(String key) async {
    if (_fallbackActive) return _fallbackDelete(key);
    try {
      await _storage.delete(key: key);
      return true;
    } on Exception catch (e) {
      if (_handleStorageError(e, 'delete($key)')) return _fallbackDelete(key);
      rethrow;
    }
  }

  Future<String?> _fallbackRead(String key) async {
    try {
      final box = await _getFallbackBox();
      return box.get(key);
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'appLock.fallbackRead', {'key': key});
      return null;
    }
  }

  Future<bool> _fallbackWrite(String key, String value) async {
    try {
      final box = await _getFallbackBox();
      await box.put(key, value);
      return true;
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'appLock.fallbackWrite', {'key': key});
      return false;
    }
  }

  Future<bool> _fallbackDelete(String key) async {
    try {
      final box = await _getFallbackBox();
      await box.delete(key);
      return true;
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'appLock.fallbackDelete', {'key': key});
      return false;
    }
  }

  // ─── PIN 哈希存取 ─────────────────────────────────────────

  Uint8List _generateSalt() {
    final random = Random.secure();
    final bytes = Uint8List(_saltLengthBytes);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes;
  }

  Future<Uint8List> _pbkdf2(String pin, Uint8List salt) =>
      compute<_Pbkdf2Request, Uint8List>(
        _derivePbkdf2InIsolate,
        _Pbkdf2Request(
          pin: pin,
          salt: salt,
          iterations: _pbkdf2Iterations,
          hashLengthBytes: _hashLengthBytes,
        ),
      );

  /// 保存新 PIN。同时生成新 salt + 计算并存储哈希
  Future<bool> savePin(String pin) async {
    final salt = _generateSalt();
    final hash = await _pbkdf2(pin, salt);
    final okSalt = await _safeWrite(_keySalt, base64Encode(salt));
    if (!okSalt) return false;
    final okHash = await _safeWrite(_keyHash, base64Encode(hash));
    if (!okHash) {
      await _safeDelete(_keySalt);
      return false;
    }
    return true;
  }

  /// 校验 PIN 是否正确
  Future<bool> verifyPin(String pin) async {
    final saltStr = await _safeRead(_keySalt);
    final hashStr = await _safeRead(_keyHash);
    if (saltStr == null || hashStr == null) return false;
    try {
      final salt = base64Decode(saltStr);
      final expected = base64Decode(hashStr);
      final actual = await _pbkdf2(pin, salt);
      return _constantTimeEquals(actual, expected);
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'appLock.verifyPin');
      return false;
    }
  }

  bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// 是否已设置过 PIN
  Future<bool> hasPin() async {
    final hash = await _safeRead(_keyHash);
    return hash != null && hash.isNotEmpty;
  }

  /// 清除已保存的 PIN（关闭应用锁时调用）
  Future<void> clearPin() async {
    await _safeDelete(_keyHash);
    await _safeDelete(_keySalt);
  }
}
