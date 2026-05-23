import 'package:my_nas/core/sync/snapshot_change_tracker.dart';
import 'package:my_nas/core/sync/syncable_module.dart';
import 'package:my_nas/core/utils/hive_utils.dart';

/// 同步全局应用设置：主题模式 + 配色方案。
///
/// 数据来源：`settings` Hive box 中的 `theme_mode` 和 `color_scheme_preset` 两个键。
/// updatedAt 由 [SnapshotChangeTracker] 通过快照 hash 推断。
class AppSettingsSyncModule implements SyncableModule {
  AppSettingsSyncModule();

  static const _moduleKey = 'app_settings';
  static const _kThemeMode = 'theme_mode';
  static const _kColorScheme = 'color_scheme_preset';

  final SnapshotChangeTracker _tracker = SnapshotChangeTracker(_moduleKey);

  @override
  String get key => _moduleKey;

  @override
  String get displayName => '全局 - 主题与配色';

  Future<Map<String, dynamic>> _readSnapshot() async {
    final box = await HiveUtils.getSettingsBox();
    final theme = box.get(_kThemeMode) as String?;
    final color = box.get(_kColorScheme) as String?;
    return {
      _kThemeMode: ?theme,
      _kColorScheme: ?color,
    };
  }

  @override
  Future<DateTime?> getLocalUpdatedAt() async {
    final snap = await _readSnapshot();
    if (snap.isEmpty) return null;
    return _tracker.getUpdatedAt(snap);
  }

  @override
  Future<Map<String, dynamic>> exportData() async {
    final snap = await _readSnapshot();
    return {
      'version': 1,
      'settings': snap,
    };
  }

  @override
  Future<void> importData(Map<String, dynamic> data) async {
    final settings = (data['settings'] as Map?) ?? const {};
    final box = await HiveUtils.getSettingsBox();
    final theme = settings[_kThemeMode];
    final color = settings[_kColorScheme];
    if (theme is String) await box.put(_kThemeMode, theme);
    if (color is String) await box.put(_kColorScheme, color);

    // 让追踪器与刚导入的快照对齐，避免下次本地推送
    await _tracker.recordImported(
      await _readSnapshot(),
      DateTime.now(),
    );
  }
}
