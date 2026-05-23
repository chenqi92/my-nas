import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/video/data/services/video_database_service.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/features/video/presentation/providers/video_history_provider.dart';
import 'package:my_nas/media_server_adapters/base/playback_sync_queue_service.dart';

/// 观看状态同步服务
///
/// 处理本地和媒体服务器的观看状态同步
class WatchedStatusService {
  WatchedStatusService(this._ref);

  final Ref _ref;

  /// 标记为已观看
  ///
  /// 同时更新本地状态和同步到媒体服务器
  Future<void> markWatched({
    required String sourceId,
    required String filePath,
    String? serverItemId,
  }) async {
    // 1. 更新本地历史记录
    final historyService = _ref.read(videoHistoryServiceProvider);
    await historyService.markAsWatched(filePath);

    // 2. 更新本地元数据
    await _updateLocalMetadata(sourceId, filePath, isWatched: true);

    // 3. 同步到媒体服务器
    await _syncToServer(
      sourceId: sourceId,
      serverItemId: serverItemId,
      isWatched: true,
    );

    // 4. 刷新相关 Provider
    _invalidateProviders(filePath);

    logger.i('WatchedStatusService: 已标记 $filePath 为已观看');
  }

  /// 标记为未观看
  Future<void> markUnwatched({
    required String sourceId,
    required String filePath,
    String? serverItemId,
  }) async {
    // 1. 更新本地历史记录
    final historyService = _ref.read(videoHistoryServiceProvider);
    await historyService.markAsUnwatched(filePath);

    // 2. 更新本地元数据
    await _updateLocalMetadata(sourceId, filePath, isWatched: false);

    // 3. 同步到媒体服务器
    await _syncToServer(
      sourceId: sourceId,
      serverItemId: serverItemId,
      isWatched: false,
    );

    // 4. 刷新相关 Provider
    _invalidateProviders(filePath);

    logger.i('WatchedStatusService: 已标记 $filePath 为未观看');
  }

  /// 切换观看状态
  Future<bool> toggle({
    required String sourceId,
    required String filePath,
    String? serverItemId,
  }) async {
    final historyService = _ref.read(videoHistoryServiceProvider);
    final isCurrentlyWatched = await historyService.isVideoWatched(filePath);

    if (isCurrentlyWatched) {
      await markUnwatched(
        sourceId: sourceId,
        filePath: filePath,
        serverItemId: serverItemId,
      );
      return false;
    } else {
      await markWatched(
        sourceId: sourceId,
        filePath: filePath,
        serverItemId: serverItemId,
      );
      return true;
    }
  }

  /// 批量标记为已观看
  Future<void> markAllWatched({
    required String sourceId,
    required List<VideoMetadata> items,
  }) async {
    for (final item in items) {
      await markWatched(
        sourceId: sourceId,
        filePath: item.filePath,
        serverItemId: item.serverItemId,
      );
    }
  }

  /// 批量标记为未观看
  Future<void> markAllUnwatched({
    required String sourceId,
    required List<VideoMetadata> items,
  }) async {
    for (final item in items) {
      await markUnwatched(
        sourceId: sourceId,
        filePath: item.filePath,
        serverItemId: item.serverItemId,
      );
    }
  }

  /// 更新本地元数据
  Future<void> _updateLocalMetadata(
    String sourceId,
    String filePath, {
    required bool isWatched,
  }) async {
    final dbService = VideoDatabaseService();
    final metadata = await dbService.get(sourceId, filePath);

    if (metadata != null) {
      final updated = metadata.copyWith(
        isWatched: isWatched,
        lastUpdated: DateTime.now(),
      );
      await dbService.upsert(updated);
    }
  }

  /// 同步到媒体服务器
  Future<void> _syncToServer({
    required String sourceId,
    required String? serverItemId,
    required bool isWatched,
  }) async {
    if (serverItemId == null) return;

    // 检查是否有活动的媒体服务器连接
    final connections = _ref.read(activeMediaServerConnectionsProvider);
    final connection = connections[sourceId];

    if (connection == null || connection.status != SourceStatus.connected) {
      // 离线时加入同步队列
      final syncQueue = _ref.read(playbackSyncQueueServiceProvider);
      await syncQueue.enqueue(
        sourceId: sourceId,
        itemId: serverItemId,
        positionTicks: 0,
        isWatched: isWatched,
        eventType: isWatched
            ? SyncEventType.markWatched
            : SyncEventType.markUnwatched,
      );
      logger.d('WatchedStatusService: 已加入同步队列');
      return;
    }

    // 在线时直接同步
    try {
      final adapter = connection.adapter;
      if (isWatched) {
        await adapter.markWatched(serverItemId);
      } else {
        await adapter.markUnwatched(serverItemId);
      }
      logger.d('WatchedStatusService: 已同步到服务器');
    } on Exception catch (e) {
      logger.w('WatchedStatusService: 同步失败，加入队列', e);
      // 失败时加入同步队列
      final syncQueue = _ref.read(playbackSyncQueueServiceProvider);
      await syncQueue.enqueue(
        sourceId: sourceId,
        itemId: serverItemId,
        positionTicks: 0,
        isWatched: isWatched,
        eventType: isWatched
            ? SyncEventType.markWatched
            : SyncEventType.markUnwatched,
      );
    }
  }

  void _invalidateProviders(String filePath) {
    _ref
      ..invalidate(isWatchedProvider(filePath))
      ..invalidate(allWatchedPathsProvider)
      ..invalidate(videoHistoryProvider)
      ..invalidate(continueWatchingProvider);
  }
}

/// 观看状态同步服务 Provider
final watchedStatusServiceProvider = Provider<WatchedStatusService>(WatchedStatusService.new);

/// 带媒体服务器同步的观看状态切换
///
/// 替代 video_history_provider 中的 toggleWatchedStatus 使用
Future<bool> toggleWatchedWithServerSync(
  WidgetRef ref, {
  required String sourceId,
  required String filePath,
  String? serverItemId,
}) async {
  final service = ref.read(watchedStatusServiceProvider);
  return service.toggle(
    sourceId: sourceId,
    filePath: filePath,
    serverItemId: serverItemId,
  );
}
