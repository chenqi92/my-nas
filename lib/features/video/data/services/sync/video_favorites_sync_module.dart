import 'package:hive_ce/hive.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/sync/syncable_module.dart';
import 'package:my_nas/features/video/data/services/video_favorites_service.dart';

/// 同步视频收藏。策略与音乐收藏同：union by videoPath，addedAt 决定胜负。
class VideoFavoritesSyncModule implements SyncableModule {
  VideoFavoritesSyncModule();

  final VideoFavoritesService _service = VideoFavoritesService();

  @override
  String get key => 'video_favorites';

  @override
  String get displayName => appL10n.syncModuleVideoFavorites;

  @override
  SyncMergePolicy get mergePolicy => SyncMergePolicy.recordMerge;

  @override
  Future<DateTime?> getLocalUpdatedAt() async {
    await _service.init();
    final list = (await _service.getAllFavorites()).toList()
      ..sort((a, b) => a.videoPath.compareTo(b.videoPath));
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
    return {'version': 1, 'favorites': list.map((f) => f.toMap()).toList()};
  }

  @override
  Future<void> importData(
    Map<String, dynamic> data, {
    DateTime? remoteUpdatedAt,
  }) async {
    await _service.init();
    final list = data['favorites'];
    if (list is! List) {
      throw const FormatException('video_favorites.favorites 必须是数组');
    }
    final box = await Hive.openBox<Map<dynamic, dynamic>>('video_favorites');
    for (final raw in list) {
      if (raw is! Map) continue;
      try {
        final item = VideoFavoriteItem.fromMap(raw);
        final existing = box.get(item.videoPath);
        if (existing is Map) {
          final existingAt = existing['addedAt'] as int? ?? 0;
          if (existingAt >= item.addedAt.millisecondsSinceEpoch) continue;
        }
        await box.put(item.videoPath, item.toMap());
      } on Object catch (e, st) {
        AppError.ignore(e, st, '远端 video_favorites 单条记录解析失败，跳过该条');
        continue;
      }
    }
  }
}
