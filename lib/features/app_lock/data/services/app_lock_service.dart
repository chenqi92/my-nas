import 'dart:convert';

import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:local_auth/local_auth.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/app_lock/data/services/app_lock_secure_store.dart';
import 'package:my_nas/features/app_lock/domain/app_lock_settings.dart';

/// 应用锁服务
///
/// 负责：
/// - 设置/校验 PIN（委托给 [AppLockSecureStore]）
/// - 持久化用户设置（Hive 'settings' box，与项目其它设置共用）
/// - 生物识别检测 + 调用 local_auth
class AppLockService {
  AppLockService({AppLockSecureStore? store, LocalAuthentication? localAuth})
    : _store = store ?? AppLockSecureStore(),
      _localAuth = localAuth ?? LocalAuthentication();

  final AppLockSecureStore _store;
  final LocalAuthentication _localAuth;

  static const _settingsKey = 'app_lock_settings_v1';

  Box<dynamic>? _settingsBox;

  Box<dynamic> _getBox() {
    final existing = _settingsBox;
    if (existing != null && existing.isOpen) return existing;
    final box = Hive.box<dynamic>('settings');
    _settingsBox = box;
    return box;
  }

  // ─── 设置持久化 ─────────────────────────────────────────

  AppLockSettings loadSettings() {
    try {
      final raw = _getBox().get(_settingsKey) as String?;
      if (raw == null || raw.isEmpty) return const AppLockSettings.disabled();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return AppLockSettings.fromJson(json);
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '加载应用锁设置失败，使用默认');
      return const AppLockSettings.disabled();
    }
  }

  Future<void> saveSettings(AppLockSettings settings) async {
    try {
      await _getBox().put(_settingsKey, jsonEncode(settings.toJson()));
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'appLock.saveSettings');
    }
  }

  // ─── PIN 管理 ──────────────────────────────────────────

  Future<bool> setPin(String pin) => _store.savePin(pin);

  Future<bool> verifyPin(String pin) => _store.verifyPin(pin);

  Future<bool> hasPin() => _store.hasPin();

  Future<void> clearPin() => _store.clearPin();

  // ─── 生物识别 ──────────────────────────────────────────

  /// 当前设备是否可用生物识别（硬件存在且至少录入了一种）
  Future<bool> isBiometricAvailable() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      if (!canCheck) return false;
      final supported = await _localAuth.isDeviceSupported();
      if (!supported) return false;
      final available = await _localAuth.getAvailableBiometrics();
      return available.isNotEmpty;
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '检测生物识别能力失败');
      return false;
    }
  }

  /// 触发生物识别。成功返回 true，用户取消 / 失败返回 false
  Future<bool> authenticateBiometric({required String reason}) async {
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } on Exception catch (e, st) {
      logger.w('AppLockService: 生物识别失败 $e');
      AppError.ignore(e, st, '生物识别失败');
      return false;
    }
  }
}
