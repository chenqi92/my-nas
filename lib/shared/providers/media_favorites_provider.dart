import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/shared/services/media_favorites_service.dart';

/// 通用媒体收藏服务 Provider
final mediaFavoritesServiceProvider =
    Provider<MediaFavoritesService>((ref) => MediaFavoritesService());

/// 通用媒体收藏列表（按类型）
///
/// 监听 [_mediaFavoritesVersionProvider]，每次 add/remove/toggle 后自增版本号
/// 来触发列表刷新。比 StreamProvider 简单，避免 Hive 自身没有变更通知的问题。
final mediaFavoritesProvider =
    FutureProvider.family<List<MediaFavoriteItem>, MediaType?>(
        (ref, type) async {
  ref.watch(_mediaFavoritesVersionProvider); // 监听版本号
  final service = ref.watch(mediaFavoritesServiceProvider);
  await service.init();
  return service.getAll(type: type);
});

/// 全量初始化标记（在 main 启动后 ref.read 触发一次即可）
final mediaFavoritesInitProvider = FutureProvider<void>((ref) async {
  final service = ref.watch(mediaFavoritesServiceProvider);
  await service.init();
});

/// 内部版本号——任何改动收藏的操作都应自增以触发依赖刷新
final _mediaFavoritesVersionProvider = StateProvider<int>((ref) => 0);

/// 收藏切换操作的统一入口
///
/// 调用方：`await ref.read(mediaFavoritesActionsProvider).toggle(...)`
class MediaFavoritesActions {
  MediaFavoritesActions(this._ref);

  final Ref _ref;

  Future<bool> toggle({
    required MediaType type,
    required String sourceId,
    required String path,
    required String displayName,
  }) async {
    final service = _ref.read(mediaFavoritesServiceProvider);
    final result = await service.toggle(
      type: type,
      sourceId: sourceId,
      path: path,
      displayName: displayName,
    );
    _bumpVersion();
    return result;
  }

  Future<void> add({
    required MediaType type,
    required String sourceId,
    required String path,
    required String displayName,
  }) async {
    await _ref.read(mediaFavoritesServiceProvider).add(
          type: type,
          sourceId: sourceId,
          path: path,
          displayName: displayName,
        );
    _bumpVersion();
  }

  Future<void> remove({
    required MediaType type,
    required String sourceId,
    required String path,
  }) async {
    await _ref.read(mediaFavoritesServiceProvider).remove(
          type: type,
          sourceId: sourceId,
          path: path,
        );
    _bumpVersion();
  }

  void _bumpVersion() {
    final notifier = _ref.read(_mediaFavoritesVersionProvider.notifier);
    notifier.state = notifier.state + 1;
  }
}

final mediaFavoritesActionsProvider =
    Provider<MediaFavoritesActions>(MediaFavoritesActions.new);
