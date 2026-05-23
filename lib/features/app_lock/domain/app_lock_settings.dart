import 'package:equatable/equatable.dart';

/// 后台超时后自动锁定的策略
enum AppLockTimeout {
  /// 立即锁定（默认）
  immediate(0),

  /// 1 分钟后
  oneMinute(60),

  /// 5 分钟后
  fiveMinutes(300),

  /// 15 分钟后
  fifteenMinutes(900),

  /// 仅在应用关闭后才锁
  onlyOnExit(-1);

  const AppLockTimeout(this.seconds);

  /// 超时秒数；-1 表示永不在后台超时（仅退出后锁）
  final int seconds;

  bool get locksOnBackground => seconds >= 0;
}

/// 应用锁设置
///
/// 持久化用 JSON 序列化，存在 Hive 'settings' box。
class AppLockSettings extends Equatable {
  const AppLockSettings({
    required this.enabled,
    required this.biometricEnabled,
    required this.timeout,
  });

  const AppLockSettings.disabled()
    : enabled = false,
      biometricEnabled = false,
      timeout = AppLockTimeout.immediate;

  factory AppLockSettings.fromJson(Map<String, dynamic> json) =>
      AppLockSettings(
        enabled: json['enabled'] as bool? ?? false,
        biometricEnabled: json['biometricEnabled'] as bool? ?? false,
        timeout: _parseTimeout(json['timeout'] as String?),
      );

  static AppLockTimeout _parseTimeout(String? name) {
    if (name == null) return AppLockTimeout.immediate;
    for (final v in AppLockTimeout.values) {
      if (v.name == name) return v;
    }
    return AppLockTimeout.immediate;
  }

  final bool enabled;
  final bool biometricEnabled;
  final AppLockTimeout timeout;

  AppLockSettings copyWith({
    bool? enabled,
    bool? biometricEnabled,
    AppLockTimeout? timeout,
  }) => AppLockSettings(
    enabled: enabled ?? this.enabled,
    biometricEnabled: biometricEnabled ?? this.biometricEnabled,
    timeout: timeout ?? this.timeout,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'biometricEnabled': biometricEnabled,
    'timeout': timeout.name,
  };

  @override
  List<Object?> get props => [enabled, biometricEnabled, timeout];
}
