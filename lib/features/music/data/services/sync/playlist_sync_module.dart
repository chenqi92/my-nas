import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/sync/syncable_module.dart';
import 'package:my_nas/features/music/data/services/playlist_service.dart';

/// 把 [PlaylistService] 暴露给 [CloudSyncService] 同步：
/// - key: `music_playlists`
/// - exportData: 全量序列化所有 playlist（含已软删除，便于跨设备同步回收站状态）
/// - importData: 整体覆盖本地 box 的所有 playlist
/// - localUpdatedAt: 取所有 playlist 最大 updatedAt
class PlaylistSyncModule implements SyncableModule {
  PlaylistSyncModule();

  final PlaylistService _service = PlaylistService();

  @override
  String get key => 'music_playlists';

  @override
  String get displayName => appL10n.syncModuleMusicPlaylists;

  @override
  Future<DateTime?> getLocalUpdatedAt() async {
    final all = await _service.getAllPlaylists(includeDeleted: true);
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
    return {
      'version': 1,
      'playlists': all.map((p) => p.toMap()).toList(),
    };
  }

  @override
  Future<void> importData(Map<String, dynamic> data) async {
    final list = (data['playlists'] as List?) ?? const [];
    // 拉取远端时按 last-write-wins 合并：远端 entry 比本地新才覆盖
    for (final raw in list.cast<Map<dynamic, dynamic>>()) {
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
        if (remote.updatedAt.isAfter(local.updatedAt)) {
          await _service.upsertFromSync(remote);
        }
        // remote 标记了删除而 local 没有 → 应用软删除
        if (remote.deletedAt != null && local.deletedAt == null) {
          await _service.upsertFromSync(remote);
        }
      } on Exception catch (_) {
        continue;
      }
    }
  }
}
