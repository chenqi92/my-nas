import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/storage/secure_storage_options.dart';
import 'package:my_nas/core/utils/logger.dart';

/// 安全存储异常
///
/// 当 Keychain/安全存储不可用时抛出
class SecureStorageException implements Exception {
  const SecureStorageException(this.message, {this.originalError});

  final String message;
  final Object? originalError;

  @override
  String toString() => message;

  /// 是否是 Keychain entitlement 错误
  bool get isKeychainEntitlementError {
    final error = originalError;
    if (error != null && isSecureStorageUnavailableError(error)) return true;
    if (error is PlatformException) {
      // macOS/iOS Keychain entitlement 错误码
      return error.code == 'Unexpected security result code' ||
          (error.message?.contains('-34018') ?? false) ||
          (error.message?.contains('entitlement') ?? false);
    }
    return false;
  }
}

/// 认证凭证存储服务
///
/// 使用安全存储来保存用户凭证和设备信息
class AuthStorageService {
  AuthStorageService() : _storage = defaultSecureStorage;

  final ResilientSecureStorage _storage;

  /// Keychain/Secure Storage 是否可用
  bool _storageAvailable = true;

  /// 是否已切换到本地降级存储
  bool _fallbackActive = false;

  /// 本地降级存储 box（懒加载，仅在 Keychain 不可用时打开）
  Box<String>? _fallbackBox;

  /// 降级 box 初始化锁，防止并发重复初始化
  Future<Box<String>>? _fallbackInit;

  static const _fallbackBoxName = 'auth_fallback_v1';

  /// 检查并处理存储错误
  ///
  /// 返回 true 表示是可恢复的存储错误（已切换到降级存储或可静默处理）
  /// 返回 false 表示其他错误（应重新抛出）
  bool _handleStorageError(Object error, String operation) {
    if (isSecureStorageUnavailableError(error) || error is PlatformException) {
      // Keychain entitlement 错误 (-34018)：常见于 macOS 未配置 keychain entitlement
      if (isSecureStorageUnavailableError(error) ||
          (error is PlatformException &&
              (error.message?.contains('entitlement') ?? false))) {
        if (_storageAvailable) {
          logger.w(
            'AuthStorageService: 系统 Keychain 不可用 ($operation) - '
            '可能缺少 Keychain entitlement，已切换到本地加密存储兜底。 '
            '注意：本地加密强度低于系统 Keychain，仅作降级方案。',
          );
        }
        _storageAvailable = false;
        _fallbackActive = true;
        return true;
      }
    }
    return false;
  }

  /// 派生本地降级存储的 AES key
  ///
  /// 注意：仅作降级使用，安全级别低于系统 Keychain。
  /// key 由设备主机名 + 固定 salt 派生，攻击者反编译应用并拿到设备
  /// 后可还原。设计目的是避免明文持久化凭证，而非抵抗本地攻击者。
  List<int> _deriveFallbackKey() {
    final material = '${Platform.localHostname}|mynas-auth-fallback|v1';
    return sha256.convert(utf8.encode(material)).bytes;
  }

  /// 获取或初始化降级 box
  Future<Box<String>> _getFallbackBox() async {
    if (_fallbackBox != null && _fallbackBox!.isOpen) return _fallbackBox!;
    return _fallbackInit ??= _openFallbackBox();
  }

  Future<Box<String>> _openFallbackBox() async {
    try {
      final cipher = HiveAesCipher(_deriveFallbackKey());
      final box = await Hive.openBox<String>(
        _fallbackBoxName,
        encryptionCipher: cipher,
      );
      _fallbackBox = box;
      return box;
    } finally {
      _fallbackInit = null;
    }
  }

  /// 安全执行存储读取操作
  Future<String?> _safeRead(String key) async {
    if (_fallbackActive) {
      return _fallbackRead(key);
    }
    try {
      return await _storage.read(key: key);
    } on Exception catch (e) {
      if (_handleStorageError(e, 'read($key)')) {
        return _fallbackRead(key);
      }
      rethrow;
    }
  }

  /// 安全执行存储写入操作
  Future<bool> _safeWrite(String key, String value) async {
    if (_fallbackActive) {
      return _fallbackWrite(key, value);
    }
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

  /// 安全执行存储删除操作
  Future<bool> _safeDelete(String key) async {
    if (_fallbackActive) {
      return _fallbackDelete(key);
    }
    try {
      await _storage.delete(key: key);
      return true;
    } on Exception catch (e) {
      if (_handleStorageError(e, 'delete($key)')) {
        return _fallbackDelete(key);
      }
      rethrow;
    }
  }

  Future<String?> _fallbackRead(String key) async {
    try {
      final box = await _getFallbackBox();
      return box.get(key);
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'authStorage.fallbackRead', {'key': key});
      return null;
    }
  }

  Future<bool> _fallbackWrite(String key, String value) async {
    try {
      final box = await _getFallbackBox();
      await box.put(key, value);
      return true;
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'authStorage.fallbackWrite', {'key': key});
      return false;
    }
  }

  Future<bool> _fallbackDelete(String key) async {
    try {
      final box = await _getFallbackBox();
      await box.delete(key);
      return true;
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'authStorage.fallbackDelete', {'key': key});
      return false;
    }
  }

  // 存储键
  static const _keyCredentials = 'auth_credentials';
  static const _keyDeviceId = 'auth_device_id';
  static const _keyRememberLogin = 'auth_remember_login';
  static const _keyRememberDevice = 'auth_remember_device';
  static const _keyLastConnectionId = 'auth_last_connection_id';

  /// 获取设备名称
  String get deviceName {
    try {
      return Platform.localHostname;
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '获取设备名称失败，使用默认名称');
      return 'MyNAS-Client';
    }
  }

  /// 保存登录凭证
  ///
  /// 返回 true 表示保存成功，false 表示存储不可用
  Future<bool> saveCredentials({
    required String connectionId,
    required String username,
    required String password,
  }) async {
    logger.i('AuthStorageService: 保存凭证 for $connectionId');

    final credentials = {
      'connectionId': connectionId,
      'username': username,
      'password': password,
      'savedAt': DateTime.now().toIso8601String(),
    };

    final success = await _safeWrite(_keyCredentials, jsonEncode(credentials));
    if (success) {
      await _safeWrite(_keyLastConnectionId, connectionId);
    }
    return success;
  }

  /// 获取保存的凭证
  Future<SavedCredentials?> getCredentials() async {
    final data = await _safeRead(_keyCredentials);
    if (data == null) return null;

    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      return SavedCredentials(
        connectionId: json['connectionId'] as String,
        username: json['username'] as String,
        password: json['password'] as String,
      );
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'parseCredentials');
      return null;
    }
  }

  /// 清除保存的凭证
  Future<void> clearCredentials() async {
    logger.i('AuthStorageService: 清除凭证');
    await _safeDelete(_keyCredentials);
    await _safeDelete(_keyLastConnectionId);
  }

  /// 保存设备ID（用于跳过二次验证）
  ///
  /// 返回 true 表示保存成功，false 表示存储不可用
  Future<bool> saveDeviceId(String connectionId, String deviceId) async {
    logger.i('AuthStorageService: 保存设备ID for $connectionId');

    // 读取现有设备ID映射
    final existing = await _getDeviceIdMap();
    existing[connectionId] = deviceId;

    return _safeWrite(_keyDeviceId, jsonEncode(existing));
  }

  /// 获取设备ID
  Future<String?> getDeviceId(String connectionId) async {
    final deviceMap = await _getDeviceIdMap();
    return deviceMap[connectionId];
  }

  Future<Map<String, String>> _getDeviceIdMap() async {
    final data = await _safeRead(_keyDeviceId);
    if (data == null) return {};

    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      return json.map((k, v) => MapEntry(k, v as String));
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '解析设备ID映射失败，返回空map');
      return {};
    }
  }

  /// 清除特定连接的设备ID
  Future<void> clearDeviceId(String connectionId) async {
    logger.i('AuthStorageService: 清除设备ID for $connectionId');
    final existing = await _getDeviceIdMap();
    existing.remove(connectionId);
    await _safeWrite(_keyDeviceId, jsonEncode(existing));
  }

  /// 设置记住登录状态
  Future<void> setRememberLogin({required bool value}) async {
    await _safeWrite(_keyRememberLogin, value.toString());

    // 如果关闭记住登录，清除凭证
    if (!value) {
      await clearCredentials();
    }
  }

  /// 获取记住登录状态
  Future<bool> getRememberLogin() async {
    final value = await _safeRead(_keyRememberLogin);
    return value == 'true';
  }

  /// 设置记住设备状态
  Future<void> setRememberDevice({required bool value}) async {
    await _safeWrite(_keyRememberDevice, value.toString());
  }

  /// 获取记住设备状态
  Future<bool> getRememberDevice() async {
    final value = await _safeRead(_keyRememberDevice);
    return value == 'true';
  }

  /// 获取最后连接的ID
  Future<String?> getLastConnectionId() async =>
      _safeRead(_keyLastConnectionId);

  /// 清除所有认证数据
  Future<void> clearAll() async {
    logger.i('AuthStorageService: 清除所有认证数据');
    await _safeDelete(_keyCredentials);
    await _safeDelete(_keyDeviceId);
    await _safeDelete(_keyRememberLogin);
    await _safeDelete(_keyRememberDevice);
    await _safeDelete(_keyLastConnectionId);
  }

  /// 检查系统级安全存储 (Keychain) 是否可用
  bool get isStorageAvailable => _storageAvailable;

  /// 是否正在使用本地降级存储
  ///
  /// true 表示因 Keychain 不可用已切换至本地加密 box，
  /// UI 层可据此向用户提示"自动登录处于降级模式，安全性低于系统 Keychain"。
  bool get isUsingFallbackStorage => _fallbackActive;
}

/// 保存的凭证
class SavedCredentials {
  const SavedCredentials({
    required this.connectionId,
    required this.username,
    required this.password,
  });

  final String connectionId;
  final String username;
  final String password;
}
