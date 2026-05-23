import 'package:equatable/equatable.dart';
import 'package:my_nas/features/app_lock/domain/app_lock_settings.dart';

/// 应用锁运行时状态机
///
/// - [disabled]：未启用，UI 全部直通
/// - [unlocked]：已启用且已解锁，主 UI 可见
/// - [locked]：已启用但需要解锁，UI 被锁屏遮罩
enum AppLockPhase { disabled, unlocked, locked }

class AppLockState extends Equatable {
  const AppLockState({
    required this.phase,
    required this.settings,
    required this.failedAttempts,
    required this.lockoutUntil,
  });

  const AppLockState.initial()
    : phase = AppLockPhase.disabled,
      settings = const AppLockSettings.disabled(),
      failedAttempts = 0,
      lockoutUntil = null;

  final AppLockPhase phase;
  final AppLockSettings settings;

  /// 当前会话连续输错次数。重置时机：成功解锁、显式重置、超过 30s 锁定窗口
  final int failedAttempts;

  /// 锁定到何时（连错 5 次后）。null 表示当前未在锁定窗口
  final DateTime? lockoutUntil;

  AppLockState copyWith({
    AppLockPhase? phase,
    AppLockSettings? settings,
    int? failedAttempts,
    DateTime? lockoutUntil,
    bool clearLockoutUntil = false,
  }) => AppLockState(
    phase: phase ?? this.phase,
    settings: settings ?? this.settings,
    failedAttempts: failedAttempts ?? this.failedAttempts,
    lockoutUntil: clearLockoutUntil ? null : lockoutUntil ?? this.lockoutUntil,
  );

  bool get isLocked => phase == AppLockPhase.locked;

  bool get isLockedOut {
    final until = lockoutUntil;
    if (until == null) return false;
    return DateTime.now().isBefore(until);
  }

  Duration get lockoutRemaining {
    final until = lockoutUntil;
    if (until == null) return Duration.zero;
    final diff = until.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  @override
  List<Object?> get props => [phase, settings, failedAttempts, lockoutUntil];
}
