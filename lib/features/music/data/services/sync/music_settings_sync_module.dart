import 'package:hive_ce/hive.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/sync/snapshot_change_tracker.dart';
import 'package:my_nas/core/sync/syncable_module.dart';

/// 同步音乐播放设置（音量 / 播放模式 / 歌词字号 / 翻译 等）。
///
/// 数据存放在 `music_settings` Hive box（key = 'settings'），形如
/// MusicSettings.toMap()。这里直接以 box 为 source of truth，不绕道
/// MusicSettingsNotifier，避免构造 Riverpod 依赖。
class MusicSettingsSyncModule implements SyncableModule {
  MusicSettingsSyncModule();

  static const _moduleKey = 'music_settings';
  static const _boxName = 'music_settings';
  static const _settingsKey = 'settings';

  final SnapshotChangeTracker _tracker = SnapshotChangeTracker(_moduleKey);

  @override
  String get key => _moduleKey;

  @override
  String get displayName => appL10n.syncModuleMusicSettings;

  @override
  SyncMergePolicy get mergePolicy => SyncMergePolicy.lastWriteWins;

  Future<Box<Map<dynamic, dynamic>>> _open() async {
    if (Hive.isBoxOpen(_boxName)) {
      return Hive.box<Map<dynamic, dynamic>>(_boxName);
    }
    return Hive.openBox<Map<dynamic, dynamic>>(_boxName);
  }

  Future<Map<String, dynamic>?> _readSnapshot() async {
    final box = await _open();
    final raw = box.get(_settingsKey);
    if (raw == null) return null;
    return Map<String, dynamic>.from(raw);
  }

  @override
  Future<DateTime?> getLocalUpdatedAt() async {
    final snap = await _readSnapshot();
    return _tracker.getUpdatedAt(snap);
  }

  @override
  Future<Map<String, dynamic>> exportData() async {
    final snap = await _readSnapshot() ?? const <String, dynamic>{};
    return {'version': 1, 'settings': snap};
  }

  @override
  Future<void> importData(
    Map<String, dynamic> data, {
    DateTime? remoteUpdatedAt,
  }) async {
    final raw = data['settings'];
    if (raw is! Map) return;
    final box = await _open();
    final merged = Map<dynamic, dynamic>.from(raw);
    await box.put(_settingsKey, merged);

    final snap = Map<String, dynamic>.from(merged);
    await _tracker.recordImported(snap, remoteUpdatedAt ?? DateTime.now());
  }
}
