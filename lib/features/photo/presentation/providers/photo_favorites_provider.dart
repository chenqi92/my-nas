import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/features/photo/data/services/photo_favorites_service.dart';
import 'package:my_nas/features/photo/domain/entities/photo_item.dart';

/// 照片收藏状态：当前所有收藏照片的唯一键集合（`$sourceId:$photoPath`，
/// 与 [PhotoFavoritesService] 内部键一致）。用 Set 作为 state，收藏变更后
/// 替换为新 Set 触发依赖该 provider 的 widget 重建，角标即时更新。
final photoFavoritesProvider =
    StateNotifierProvider<PhotoFavoritesNotifier, Set<String>>(
  (ref) => PhotoFavoritesNotifier(),
);

/// 根据 sourceId + 照片路径生成收藏唯一键，必须与
/// [PhotoFavoritesService] 内部使用的键格式一致。
String photoFavoriteKey(String sourceId, String photoPath) =>
    '$sourceId:$photoPath';

class PhotoFavoritesNotifier extends StateNotifier<Set<String>> {
  PhotoFavoritesNotifier({PhotoFavoritesService? service})
      : _service = service ?? PhotoFavoritesService(),
        super(const {}) {
    _load();
  }

  final PhotoFavoritesService _service;

  Future<void> _load() async {
    try {
      final all = await _service.getAllFavorites();
      state = {for (final f in all) f.uniqueKey};
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '加载照片收藏列表失败，使用空集合');
    }
  }

  /// 同步查询某张照片是否已收藏（基于已载入的内存集合）。
  bool isFavorite(String key) => state.contains(key);

  /// 切换收藏状态：先更新内存集合让角标即时响应，再持久化。
  Future<void> toggle(PhotoItem item) async {
    final key = photoFavoriteKey(item.sourceId, item.path);
    final next = Set<String>.of(state);
    final willFavorite = !next.contains(key);
    if (willFavorite) {
      next.add(key);
    } else {
      next.remove(key);
    }
    state = next;

    try {
      if (willFavorite) {
        await _service.addToFavorites(item);
      } else {
        await _service.removeFromFavorites(item.path, item.sourceId);
      }
    } on Exception catch (e, st) {
      // 持久化失败则回滚内存状态，保持与磁盘一致。
      final rollback = Set<String>.of(state);
      if (willFavorite) {
        rollback.remove(key);
      } else {
        rollback.add(key);
      }
      state = rollback;
      AppError.ignore(e, st, '切换照片收藏状态失败');
    }
  }
}
