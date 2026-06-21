import 'package:hive_ce/hive.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/sync/syncable_module.dart';
import 'package:my_nas/features/music/data/services/music_favorites_service.dart';

/// 同步音乐收藏。最简策略：
/// - exportData = 全部 favorites 当前快照
/// - importData = union（按 musicPath 主键），冲突 last-addedAt-wins
/// - localUpdatedAt = max(addedAt)
///
/// 已知局限：纯删除（用户取消收藏）跨设备不能立即传播；下次本机收藏列表为
/// 空且远端有数据时，本地会被远端覆盖恢复。考虑到收藏量级小，先按这个简化处理。
class FavoritesSyncModule implements SyncableModule {
  FavoritesSyncModule();

  final MusicFavoritesService _service = MusicFavoritesService();

  @override
  String get key => 'music_favorites';

  @override
  String get displayName => appL10n.syncModuleMusicFavorites;

  @override
  Future<DateTime?> getLocalUpdatedAt() async {
    await _service.init();
    final list = await _service.getAllFavorites();
    if (list.isEmpty) return null;
    var maxAt = list.first.addedAt;
    for (final f in list) {
      if (f.addedAt.isAfter(maxAt)) maxAt = f.addedAt;
    }
    return maxAt;
  }

  @override
  Future<Map<String, dynamic>> exportData() async {
    await _service.init();
    final list = await _service.getAllFavorites();
    return {
      'version': 1,
      'favorites': list.map((f) => f.toMap()).toList(),
    };
  }

  @override
  Future<void> importData(Map<String, dynamic> data) async {
    await _service.init();
    final list = (data['favorites'] as List?) ?? const [];
    final box = await Hive.openBox<Map<dynamic, dynamic>>('music_favorites');
    for (final raw in list.cast<Map<dynamic, dynamic>>()) {
      try {
        final item = MusicFavoriteItem.fromMap(raw);
        final existing = box.get(item.musicPath);
        // 已存在 + 已存的 addedAt 更晚 → 跳过；否则覆盖
        if (existing is Map) {
          final existingAt = existing['addedAt'] as int? ?? 0;
          if (existingAt >= item.addedAt.millisecondsSinceEpoch) continue;
        }
        await box.put(item.musicPath, item.toMap());
      } on Exception catch (_) {
        continue;
      }
    }
  }
}
