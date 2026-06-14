import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/video/data/services/video_database_service.dart';
import 'package:my_nas/media_server_adapters/base/media_server_adapter.dart';
import 'package:my_nas/media_server_adapters/base/media_server_cache_service.dart';
import 'package:my_nas/media_server_adapters/base/media_server_entities.dart';
import 'package:my_nas/media_server_adapters/base/metadata_priority_service.dart';

/// 同步状态
enum MediaServerSyncStatus {
  idle,
  syncing,
  completed,
  failed,
}

/// 同步进度
class SyncProgress {
  const SyncProgress({
    this.status = MediaServerSyncStatus.idle,
    this.currentLibrary,
    this.totalLibraries = 0,
    this.processedLibraries = 0,
    this.totalItems = 0,
    this.processedItems = 0,
    this.newItems = 0,
    this.updatedItems = 0,
    this.errorMessage,
  });

  final MediaServerSyncStatus status;
  final String? currentLibrary;
  final int totalLibraries;
  final int processedLibraries;
  final int totalItems;
  final int processedItems;
  final int newItems;
  final int updatedItems;
  final String? errorMessage;

  double get progress {
    if (totalItems == 0) return 0;
    return processedItems / totalItems;
  }

  SyncProgress copyWith({
    MediaServerSyncStatus? status,
    String? currentLibrary,
    int? totalLibraries,
    int? processedLibraries,
    int? totalItems,
    int? processedItems,
    int? newItems,
    int? updatedItems,
    String? errorMessage,
  }) =>
      SyncProgress(
        status: status ?? this.status,
        currentLibrary: currentLibrary ?? this.currentLibrary,
        totalLibraries: totalLibraries ?? this.totalLibraries,
        processedLibraries: processedLibraries ?? this.processedLibraries,
        totalItems: totalItems ?? this.totalItems,
        processedItems: processedItems ?? this.processedItems,
        newItems: newItems ?? this.newItems,
        updatedItems: updatedItems ?? this.updatedItems,
        errorMessage: errorMessage ?? this.errorMessage,
      );
}

/// 媒体服务器同步服务
///
/// 实现增量同步，定期从服务器拉取更新的内容
class MediaServerSyncService {
  MediaServerSyncService(this._ref);

  final Ref _ref;
  final _progressController = StreamController<SyncProgress>.broadcast();

  Timer? _autoSyncTimer;
  bool _isSyncing = false;

  /// 同步进度流
  Stream<SyncProgress> get progressStream => _progressController.stream;

  /// 当前同步状态
  SyncProgress _currentProgress = const SyncProgress();
  SyncProgress get currentProgress => _currentProgress;

  /// 启动自动同步定时器
  void startAutoSync({Duration interval = const Duration(minutes: 30)}) {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(interval, (_) => syncAll());
  }

  /// 停止自动同步
  void stopAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
  }

  /// 同步所有已连接的媒体服务器
  Future<void> syncAll() async {
    if (_isSyncing) return;

    final connections = _ref.read(activeMediaServerConnectionsProvider);
    for (final connection in connections.values) {
      if (connection.status == SourceStatus.connected) {
        await syncSource(connection.source.id, connection.adapter);
      }
    }
  }

  /// 同步指定源
  Future<void> syncSource(String sourceId, MediaServerAdapter adapter) async {
    if (_isSyncing) {
      logger.w('MediaServerSyncService: 同步已在进行中');
      return;
    }

    _isSyncing = true;
    _updateProgress(const SyncProgress(status: MediaServerSyncStatus.syncing));

    try {
      // 获取媒体库列表
      final libraries = await adapter.getLibraries();
      _updateProgress(_currentProgress.copyWith(
        totalLibraries: libraries.length,
      ));

      var totalNewItems = 0;
      var totalUpdatedItems = 0;

      for (var i = 0; i < libraries.length; i++) {
        final library = libraries[i];

        // 只同步视频相关库
        if (!_isSupportedLibraryType(library.type)) continue;

        _updateProgress(_currentProgress.copyWith(
          currentLibrary: library.name,
          processedLibraries: i,
        ));

        final result = await _syncLibrary(sourceId, library.id, adapter);
        totalNewItems += result.newItems;
        totalUpdatedItems += result.updatedItems;
      }

      _updateProgress(SyncProgress(
        status: MediaServerSyncStatus.completed,
        totalLibraries: libraries.length,
        processedLibraries: libraries.length,
        newItems: totalNewItems,
        updatedItems: totalUpdatedItems,
      ));

      logger.i(
        'MediaServerSyncService: 同步完成，新增 $totalNewItems，更新 $totalUpdatedItems',
      );
    } on Exception catch (e) {
      _updateProgress(SyncProgress(
        status: MediaServerSyncStatus.failed,
        errorMessage: e.toString(),
      ));
      logger.e('MediaServerSyncService: 同步失败', e);
    } finally {
      _isSyncing = false;
    }
  }

  /// 同步单个媒体库
  Future<_SyncResult> _syncLibrary(
    String sourceId,
    String libraryId,
    MediaServerAdapter adapter,
  ) async {
    var newItems = 0;
    var updatedItems = 0;
    var startIndex = 0;
    const pageSize = 100;

    final cacheService = _ref.read(mediaServerCacheServiceProvider);
    final priorityService = _ref.read(metadataPriorityServiceProvider);
    final dbService = VideoDatabaseService();

    while (true) {
      // 分页获取项目
      final result = await adapter.getItems(
        libraryId: libraryId,
        startIndex: startIndex,
        limit: pageSize,
      );

      if (result.items.isEmpty) break;

      _updateProgress(_currentProgress.copyWith(
        totalItems: result.totalRecordCount,
        processedItems: startIndex + result.items.length,
      ));

      // 处理每个项目
      for (final item in result.items) {
        // 跳过非可播放项目
        if (!item.type.isPlayable) continue;

        // 检查本地缓存
        final cached = await cacheService.get(sourceId, item.id);
        final isNew = cached == null;

        // 创建/更新缓存条目
        final entry = cacheService.createEntry(
          sourceId: sourceId,
          item: item,
          parentId: item.parentId,
        );
        await cacheService.upsert(entry);

        // 更新本地元数据库
        await _updateLocalMetadata(
          sourceId: sourceId,
          item: item,
          priorityService: priorityService,
          dbService: dbService,
        );

        if (isNew) {
          newItems++;
        } else {
          updatedItems++;
        }
      }

      startIndex += result.items.length;
      if (!result.hasMore) break;
    }

    return _SyncResult(newItems: newItems, updatedItems: updatedItems);
  }

  /// 更新本地元数据
  Future<void> _updateLocalMetadata({
    required String sourceId,
    required MediaItem item,
    required MetadataPriorityService priorityService,
    required VideoDatabaseService dbService,
  }) async {
    // 构建虚拟文件路径（用于标识）
    final filePath = '/${item.seriesName ?? ''}/${item.seasonName ?? ''}/${item.name}';

    // 获取现有元数据
    final existing = await dbService.get(sourceId, filePath);

    if (existing != null) {
      // 更新现有元数据（服务器数据优先级最高）
      final updated = priorityService.updateFromMediaItem(
        existing,
        item,
        serverType: 'jellyfin',
      );
      await dbService.upsert(updated);
    } else {
      // 创建新元数据
      final metadata = priorityService.fromMediaItem(
        item: item,
        filePath: filePath,
        sourceId: sourceId,
        fileName: item.name,
        serverType: 'jellyfin',
      );
      await dbService.upsert(metadata);
    }
  }

  bool _isSupportedLibraryType(MediaLibraryType type) => switch (type) {
        MediaLibraryType.movies ||
        MediaLibraryType.tvShows ||
        MediaLibraryType.homeVideos =>
          true,
        _ => false,
      };

  void _updateProgress(SyncProgress progress) {
    _currentProgress = progress;
    _progressController.add(progress);
  }

  /// 增量同步 - 只同步最近更新的内容
  Future<void> incrementalSync(
    String sourceId,
    MediaServerAdapter adapter, {
    Duration since = const Duration(hours: 24),
  }) async {
    if (_isSyncing) return;

    _isSyncing = true;
    _updateProgress(const SyncProgress(status: MediaServerSyncStatus.syncing));

    try {
      // 获取最近添加/更新的项目
      final recentItems = await adapter.getRecentlyAdded(limit: 100);

      _updateProgress(_currentProgress.copyWith(
        totalItems: recentItems.items.length,
      ));

      final cacheService = _ref.read(mediaServerCacheServiceProvider);
      final priorityService = _ref.read(metadataPriorityServiceProvider);
      final dbService = VideoDatabaseService();

      var processed = 0;
      var newItems = 0;

      for (final item in recentItems.items) {
        if (!item.type.isPlayable) continue;

        final cached = await cacheService.get(sourceId, item.id);
        if (cached == null) {
          newItems++;

          // 缓存新项目
          final entry = cacheService.createEntry(
            sourceId: sourceId,
            item: item,
            parentId: item.parentId,
          );
          await cacheService.upsert(entry);

          // 更新本地元数据
          await _updateLocalMetadata(
            sourceId: sourceId,
            item: item,
            priorityService: priorityService,
            dbService: dbService,
          );
        }

        processed++;
        _updateProgress(_currentProgress.copyWith(
          processedItems: processed,
        ));
      }

      _updateProgress(SyncProgress(
        status: MediaServerSyncStatus.completed,
        newItems: newItems,
        processedItems: processed,
        totalItems: recentItems.items.length,
      ));

      logger.i('MediaServerSyncService: 增量同步完成，新增 $newItems 项');
    } on Exception catch (e) {
      _updateProgress(SyncProgress(
        status: MediaServerSyncStatus.failed,
        errorMessage: e.toString(),
      ));
      logger.e('MediaServerSyncService: 增量同步失败', e);
    } finally {
      _isSyncing = false;
    }
  }

  /// 清理指定源的同步数据
  Future<void> clearSyncData(String sourceId) async {
    final cacheService = _ref.read(mediaServerCacheServiceProvider);
    await cacheService.deleteBySource(sourceId);
    logger.i('MediaServerSyncService: 已清理源 $sourceId 的同步数据');
  }

  void dispose() {
    stopAutoSync();
    _progressController.close();
  }
}

class _SyncResult {
  const _SyncResult({this.newItems = 0, this.updatedItems = 0});

  final int newItems;
  final int updatedItems;
}

/// 媒体服务器同步服务 Provider
final mediaServerSyncServiceProvider = Provider<MediaServerSyncService>((ref) {
  final service = MediaServerSyncService(ref);
  ref.onDispose(service.dispose);
  return service;
});

/// 同步进度 Provider
final syncProgressProvider = StreamProvider<SyncProgress>((ref) {
  final service = ref.watch(mediaServerSyncServiceProvider);
  return service.progressStream;
});
