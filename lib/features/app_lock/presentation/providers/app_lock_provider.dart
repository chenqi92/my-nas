import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/app_lock/data/services/app_lock_service.dart';
import 'package:my_nas/features/app_lock/domain/app_lock_settings.dart';
import 'package:my_nas/features/app_lock/domain/app_lock_state.dart';

final appLockServiceProvider = Provider<AppLockService>(
  (_) => AppLockService(),
);

final appLockProvider = StateNotifierProvider<AppLockNotifier, AppLockState>(
  (ref) => AppLockNotifier(ref.read(appLockServiceProvider)),
);

class AppLockNotifier extends StateNotifier<AppLockState> {
  AppLockNotifier(this._service) : super(const AppLockState.initial()) {
    _init();
  }

  final AppLockService _service;

  /// 后台暂停时间戳，用于计算超时
  DateTime? _pausedAt;

  /// 锁定窗口计时器，到点自动清 lockoutUntil
  Timer? _lockoutTimer;

  static const _maxFailedAttempts = 5;
  static const _lockoutDuration = Duration(seconds: 30);

  void _init() {
    final settings = _service.loadSettings();
    state = state.copyWith(
      settings: settings,
      phase: settings.enabled ? AppLockPhase.locked : AppLockPhase.disabled,
    );
  }

  // ─── 状态查询 ──────────────────────────────────────────

  bool get isEnabled => state.settings.enabled;

  bool get isLocked => state.isLocked;

  // ─── 设置 ────────────────────────────────────────────

  /// 首次启用（已通过 setup_pin_page 设置过 PIN 后调用）
  Future<void> enableLock({required bool biometricEnabled}) async {
    final settings = state.settings.copyWith(
      enabled: true,
      biometricEnabled: biometricEnabled,
    );
    await _service.saveSettings(settings);
    state = state.copyWith(settings: settings, phase: AppLockPhase.unlocked);
  }

  /// 关闭应用锁（调用方需自行确认 PIN 已验证通过）
  Future<void> disableLock() async {
    await _service.clearPin();
    const settings = AppLockSettings.disabled();
    await _service.saveSettings(settings);
    state = AppLockState(
      phase: AppLockPhase.disabled,
      settings: settings,
      failedAttempts: 0,
      lockoutUntil: null,
    );
  }

  Future<void> setTimeout(AppLockTimeout timeout) async {
    final settings = state.settings.copyWith(timeout: timeout);
    await _service.saveSettings(settings);
    state = state.copyWith(settings: settings);
  }

  Future<void> setBiometricEnabled({required bool value}) async {
    final settings = state.settings.copyWith(biometricEnabled: value);
    await _service.saveSettings(settings);
    state = state.copyWith(settings: settings);
  }

  // ─── PIN 设置 / 校验 ───────────────────────────────────

  Future<bool> savePin(String pin) => _service.setPin(pin);

  Future<bool> hasPin() => _service.hasPin();

  /// 解锁尝试。返回 true 表示成功
  Future<bool> tryUnlockWithPin(String pin) async {
    if (state.isLockedOut) return false;
    final ok = await _service.verifyPin(pin);
    if (ok) {
      state = state.copyWith(
        phase: AppLockPhase.unlocked,
        failedAttempts: 0,
        clearLockoutUntil: true,
      );
      return true;
    }
    final attempts = state.failedAttempts + 1;
    if (attempts >= _maxFailedAttempts) {
      final until = DateTime.now().add(_lockoutDuration);
      state = state.copyWith(failedAttempts: attempts, lockoutUntil: until);
      _scheduleLockoutReset(_lockoutDuration);
    } else {
      state = state.copyWith(failedAttempts: attempts);
    }
    return false;
  }

  Future<bool> tryUnlockWithBiometric() async {
    if (!state.settings.biometricEnabled) return false;
    final ok = await _service.authenticateBiometric(reason: '解锁 MyNAS');
    if (ok) {
      state = state.copyWith(
        phase: AppLockPhase.unlocked,
        failedAttempts: 0,
        clearLockoutUntil: true,
      );
    }
    return ok;
  }

  Future<bool> isBiometricAvailable() => _service.isBiometricAvailable();

  void _scheduleLockoutReset(Duration after) {
    _lockoutTimer?.cancel();
    _lockoutTimer = Timer(after, () {
      if (mounted) {
        state = state.copyWith(failedAttempts: 0, clearLockoutUntil: true);
      }
    });
  }

  // ─── 生命周期：被 AppLockGate 调用 ─────────────────────

  void onAppPaused() {
    if (!state.settings.enabled) return;
    _pausedAt = DateTime.now();
  }

  void onAppResumed() {
    if (!state.settings.enabled) return;
    final pausedAt = _pausedAt;
    final timeout = state.settings.timeout;

    // 应用未真正进过 paused（首次启动 / 已被锁定 / 设置为不在后台锁）
    if (pausedAt == null) {
      if (state.phase == AppLockPhase.unlocked) return;
      state = state.copyWith(phase: AppLockPhase.locked);
      return;
    }

    _pausedAt = null;

    if (timeout == AppLockTimeout.onlyOnExit) return;

    final elapsed = DateTime.now().difference(pausedAt);
    final threshold = Duration(seconds: timeout.seconds);
    if (elapsed >= threshold) {
      state = state.copyWith(phase: AppLockPhase.locked);
    }
  }

  /// 冷启动时由 AppLockGate 调用：如果设置启用则一开始就锁
  void lockNow() {
    if (!state.settings.enabled) return;
    state = state.copyWith(phase: AppLockPhase.locked);
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    super.dispose();
  }
}
