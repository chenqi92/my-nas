import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/sync/syncable_module.dart';
import 'package:my_nas/features/music/data/services/playlist_service.dart';

/// 把 [PlaylistService] 暴露给 [CloudSyncService] 同步：
/// - key: `music_playlists`
/// - exportData: 全量序列化所有 playlist（含已软删除，便于跨设备同步回收站状态）
/// - importData: 按 playlist id 和更新时间逐条合并
/// - localUpdatedAt: 取所有 playlist 最大 updatedAt
class PlaylistSyncModule implements SyncableModule {
  PlaylistSyncModule();

  final PlaylistService _service = PlaylistService();

  @override
  String get key => 'music_playlists';

  @override
  String get displayName => appL10n.syncModuleMusicPlaylists;

  @override
  SyncMergePolicy get mergePolicy => SyncMergePolicy.recordMerge;

  @override
  Future<DateTime?> getLocalUpdatedAt() async {
    final all = (await _service.getAllPlaylists(includeDeleted: true)).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    if (all.isEmpty) return null;
    var maxAt = all.first.updatedAt;
    for (final p in all) {
      if (p.updatedAt.isAfter(maxAt)) maxAt = p.updatedAt;
      if (p.deletedAt != null && p.deletedAt!.isAfter(maxAt)) {
        maxAt = p.deletedAt!;
      }
    }
    return maxAt;
  }

  @override
  Future<Map<String, dynamic>> exportData() async {
    final all = await _service.getAllPlaylists(includeDeleted: true);
    return {'version': 1, 'playlists': all.map((p) => p.toMap()).toList()};
  }

  @override
  Future<void> importData(
    Map<String, dynamic> data, {
    DateTime? remoteUpdatedAt,
  }) async {
    final list = data['playlists'];
    if (list is! List) {
      throw const FormatException('music_playlists.playlists 必须是数组');
    }
    // 拉取远端时按 last-write-wins 合并：远端 entry 比本地新才覆盖
    for (final raw in list) {
      if (raw is! Map) continue;
      try {
        final remote = PlaylistEntry.fromMap(raw);
        final local = await _service.getPlaylist(
          remote.id,
          includeDeleted: true,
        );
        if (local == null) {
          await _service.upsertFromSync(remote);
          continue;
        }
        final remoteAt = _latestChangeAt(remote);
        final localAt = _latestChangeAt(local);
        if (remoteAt.isAfter(localAt)) {
          await _service.upsertFromSync(remote);
        }
      } on Object catch (e, st) {
        AppError.ignore(e, st, '远端 music_playlists 单条记录解析失败，跳过该条');
        continue;
      }
    }
  }

  DateTime _latestChangeAt(PlaylistEntry entry) {
    final deletedAt = entry.deletedAt;
    if (deletedAt != null && deletedAt.isAfter(entry.updatedAt)) {
      return deletedAt;
    }
    return entry.updatedAt;
  }
}
