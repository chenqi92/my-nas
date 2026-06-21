import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/book/data/services/book_file_cache_service.dart';
import 'package:my_nas/features/music/data/services/music_audio_cache_service.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/transfer/data/services/cache_config_service.dart';
import 'package:my_nas/features/transfer/data/services/media_cache_service.dart';
import 'package:my_nas/features/transfer/data/services/transfer_service.dart';
import 'package:my_nas/features/transfer/data/services/uploaded_mark_service.dart';
import 'package:my_nas/features/transfer/domain/entities/transfer_task.dart';

/// 缓存配置服务 Provider
final cacheConfigServiceProvider = Provider<CacheConfigService>((ref) => CacheConfigService());

/// 缓存配置 Provider（用于 UI 显示和设置）
final cacheConfigProvider = FutureProvider<Map<MediaType, int>>((ref) async {
  final configService = ref.watch(cacheConfigServiceProvider);
  await configService.init();
  return configService.getAllCacheSizeLimits();
});

/// 传输服务 Provider
final transferServiceProvider = Provider<TransferService>((ref) {
  final service = TransferService();

  // 监听连接变化，更新传输服务的连接映射
  ref.listen(activeConnectionsProvider, (previous, next) {
    service.setConnections(next);
  });

  // 初始化时设置当前连接
  final connections = ref.read(activeConnectionsProvider);
  service.setConnections(connections);

  return service;
});

/// 上传标记服务 Provider
final uploadedMarkServiceProvider = Provider<UploadedMarkService>((ref) => UploadedMarkService());

/// 媒体缓存服务 Provider
final mediaCacheServiceProvider = Provider<MediaCacheService>((ref) => MediaCacheService());

/// 音乐音频缓存服务 Provider
final musicAudioCacheServiceProvider = Provider<MusicAudioCacheService>((ref) => MusicAudioCacheService());

/// 图书文件缓存服务 Provider
final bookFileCacheServiceProvider = Provider<BookFileCacheService>((ref) => BookFileCacheService());

/// 传输任务列表 Provider
final transferTasksProvider =
    StateNotifierProvider<TransferTasksNotifier, TransferTasksState>(
        TransferTasksNotifier.new);

/// 上传任务列表
final uploadTasksProvider = Provider<List<TransferTask>>((ref) {
  final state = ref.watch(transferTasksProvider);
  return state.tasks.where((t) => t.type == TransferType.upload).toList();
});

/// 下载任务列表
final downloadTasksProvider = Provider<List<TransferTask>>((ref) {
  final state = ref.watch(transferTasksProvider);
  return state.tasks.where((t) => t.type == TransferType.download).toList();
});

/// 缓存任务列表（包含正在缓存和已完成的）
final cacheTasksProvider = Provider<List<TransferTask>>((ref) {
  final state = ref.watch(transferTasksProvider);
  return state.tasks.where((t) => t.type == TransferType.cache).toList();
});

/// 正在传输的任务数
final activeTransferCountProvider = Provider<int>((ref) {
  final state = ref.watch(transferTasksProvider);
  return state.tasks
      .where((t) =>
          t.status == TransferStatus.transferring ||
          t.status == TransferStatus.queued)
      .length;
});

/// 正在上传的任务数
final uploadingCountProvider = Provider<int>((ref) {
  final tasks = ref.watch(uploadTasksProvider);
  return tasks
      .where((t) =>
          t.status == TransferStatus.transferring ||
          t.status == TransferStatus.queued)
      .length;
});

/// 正在下载的任务数
final downloadingCountProvider = Provider<int>((ref) {
  final tasks = ref.watch(downloadTasksProvider);
  return tasks
      .where((t) =>
          t.status == TransferStatus.transferring ||
          t.status == TransferStatus.queued)
      .length;
});

/// 正在缓存的任务数
final cachingCountProvider = Provider<int>((ref) {
  final tasks = ref.watch(cacheTasksProvider);
  return tasks
      .where((t) =>
          t.status == TransferStatus.transferring ||
          t.status == TransferStatus.queued)
      .length;
});

/// 已缓存的项目列表
final cachedItemsProvider =
    FutureProvider.family<List<CachedMediaItem>, MediaType?>((ref, mediaType) async {
  final cacheService = ref.watch(mediaCacheServiceProvider);
  await cacheService.init();
  return cacheService.getCachedItems(mediaType: mediaType);
});

/// 所有缓存项列表（聚合所有缓存服务）
final allCachedItemsProvider = FutureProvider<List<CachedMediaItem>>((ref) async {
  final mediaCacheService = ref.watch(mediaCacheServiceProvider);
  final musicAudioCacheService = ref.watch(musicAudioCacheServiceProvider);
  final bookFileCacheService = ref.watch(bookFileCacheServiceProvider);

  // 初始化所有缓存服务
  await Future.wait([
    mediaCacheService.init(),
    musicAudioCacheService.init(),
    bookFileCacheService.init(),
  ]);

  // 获取所有缓存项
  final results = await Future.wait([
    mediaCacheService.getCachedItems(),
    musicAudioCacheService.getCachedItems(),
    bookFileCacheService.getCachedItems(),
  ]);

  // 合并所有缓存项
  final allItems = <CachedMediaItem>[
    ...results[0],
    ...results[1],
    ...results[2],
  ]

  // 按媒体类型和时间排序
  ..sort((a, b) {
    // 先按媒体类型分组
    if (a.mediaType != b.mediaType) {
      return a.mediaType.index.compareTo(b.mediaType.index);
    }
    // 同类型按时间倒序
    final timeA = a.lastAccessed ?? a.cachedAt;
    final timeB = b.lastAccessed ?? b.cachedAt;
    return timeB.compareTo(timeA);
  });

  return allItems;
});

/// 缓存统计信息（聚合所有缓存服务）
/// 使用实际缓存列表计算统计数据，确保与列表数量一致
final cacheStatsProvider =
    FutureProvider<Map<MediaType, ({int count, int size})>>((ref) async {
  final mediaCacheService = ref.watch(mediaCacheServiceProvider);
  final musicAudioCacheService = ref.watch(musicAudioCacheServiceProvider);
  final bookFileCacheService = ref.watch(bookFileCacheServiceProvider);

  // 初始化所有缓存服务
  await Future.wait([
    mediaCacheService.init(),
    musicAudioCacheService.init(),
    bookFileCacheService.init(),
  ]);

  // 获取 MediaCacheService 的统计（已验证文件存在性）
  final stats = await mediaCacheService.getCacheStats();

  // 添加 MusicAudioCacheService 的统计（使用实际缓存列表）
  final musicCachedItems = await musicAudioCacheService.getCachedItems();
  if (musicCachedItems.isNotEmpty) {
    final musicTotalSize =
        musicCachedItems.fold<int>(0, (sum, item) => sum + item.fileSize);
    final existing = stats[MediaType.music] ?? (count: 0, size: 0);
    stats[MediaType.music] = (
      count: existing.count + musicCachedItems.length,
      size: existing.size + musicTotalSize,
    );
  }

  // 添加 BookFileCacheService 的统计（使用实际缓存列表）
  final bookCachedItems = await bookFileCacheService.getCachedItems();
  if (bookCachedItems.isNotEmpty) {
    final bookTotalSize =
        bookCachedItems.fold<int>(0, (sum, item) => sum + item.fileSize);
    final existing = stats[MediaType.book] ?? (count: 0, size: 0);
    stats[MediaType.book] = (
      count: existing.count + bookCachedItems.length,
      size: existing.size + bookTotalSize,
    );
  }

  return stats;
});

/// 检查文件是否已上传
final isUploadedProvider =
    FutureProvider.family<bool, ({String localPath, String targetSourceId})>(
        (ref, params) async {
  final markService = ref.watch(uploadedMarkServiceProvider);
  await markService.init();
  return markService.isUploaded(params.localPath, params.targetSourceId);
});

/// 检查文件是否已缓存
final isCachedProvider =
    FutureProvider.family<bool, ({String sourceId, String sourcePath})>(
        (ref, params) async {
  final cacheService = ref.watch(mediaCacheServiceProvider);
  await cacheService.init();
  return cacheService.isCached(params.sourceId, params.sourcePath);
});

/// 获取缓存文件路径（用于离线播放）
final cachedPathProvider =
    FutureProvider.family<String?, ({String sourceId, String sourcePath})>(
        (ref, params) async {
  final cacheService = ref.watch(mediaCacheServiceProvider);
  await cacheService.init();
  return cacheService.getCachedPath(params.sourceId, params.sourcePath);
});

/// 传输任务状态
class TransferTasksState {
  const TransferTasksState({
    this.tasks = const [],
    this.isLoading = false,
    this.error,
  });

  final List<TransferTask> tasks;
  final bool isLoading;
  final String? error;

  TransferTasksState copyWith({
    List<TransferTask>? tasks,
    bool? isLoading,
    String? error,
  }) =>
      TransferTasksState(
        tasks: tasks ?? this.tasks,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

/// 传输任务状态管理器
class TransferTasksNotifier extends StateNotifier<TransferTasksState> {
  TransferTasksNotifier(this._ref) : super(const TransferTasksState()) {
    _init();
  }

  final Ref _ref;
  StreamSubscription<List<TransferTask>>? _subscription;

  Future<void> _init() async {
    state = state.copyWith(isLoading: true);

    try {
      final service = _ref.read(transferServiceProvider);
      await service.init();

      // 初始任务列表
      state = state.copyWith(
        tasks: service.allTasks,
        isLoading: false,
      );

      // 监听任务变化
      _subscription = service.tasksStream.listen((tasks) {
        state = state.copyWith(tasks: tasks);
      });

      logger.i('TransferTasksNotifier: 初始化完成');
    } catch (e, st) {
      AppError.handle(e, st, 'TransferTasksNotifier._init');
      state = state.copyWith(
        isLoading: false,
        error: appL10n.transferInitFailedError,
      );
    }
  }

  /// 添加上传任务
  Future<TransferTask?> addUploadTask({
    required String localPath,
    required String targetSourceId,
    required String targetPath,
    required MediaType mediaType,
    required int fileSize,
    String? assetId,
    int? songId,
    String? thumbnailPath,
  }) async {
    try {
      final service = _ref.read(transferServiceProvider);
      return await service.addUploadTask(
        localPath: localPath,
        targetSourceId: targetSourceId,
        targetPath: targetPath,
        mediaType: mediaType,
        fileSize: fileSize,
        assetId: assetId,
        songId: songId,
        thumbnailPath: thumbnailPath,
      );
    } catch (e, st) {
      AppError.handle(e, st, 'TransferTasksNotifier.addUploadTask');
      return null;
    }
  }

  /// 批量添加上传任务
  Future<List<TransferTask>> addUploadTasks({
    required List<({
      String localPath,
      int fileSize,
      String? assetId,
      int? songId,
      String? thumbnailPath,
    })> items,
    required String targetSourceId,
    required String targetPath,
    required MediaType mediaType,
  }) async {
    final tasks = <TransferTask>[];

    for (final item in items) {
      final task = await addUploadTask(
        localPath: item.localPath,
        targetSourceId: targetSourceId,
        targetPath: targetPath,
        mediaType: mediaType,
        fileSize: item.fileSize,
        assetId: item.assetId,
        songId: item.songId,
        thumbnailPath: item.thumbnailPath,
      );
      if (task != null) {
        tasks.add(task);
      }
    }

    return tasks;
  }

  /// 添加下载任务
  Future<TransferTask?> addDownloadTask({
    required String sourceId,
    required String sourcePath,
    required String targetPath,
    required MediaType mediaType,
    required int fileSize,
    String? thumbnailPath,
  }) async {
    try {
      final service = _ref.read(transferServiceProvider);
      return await service.addDownloadTask(
        sourceId: sourceId,
        sourcePath: sourcePath,
        targetPath: targetPath,
        mediaType: mediaType,
        fileSize: fileSize,
        thumbnailPath: thumbnailPath,
      );
    } catch (e, st) {
      AppError.handle(e, st, 'TransferTasksNotifier.addDownloadTask');
      return null;
    }
  }

  /// 添加缓存任务
  Future<TransferTask?> addCacheTask({
    required String sourceId,
    required String sourcePath,
    required MediaType mediaType,
    required int fileSize,
    String? thumbnailPath,
  }) async {
    try {
      final service = _ref.read(transferServiceProvider);
      return await service.addCacheTask(
        sourceId: sourceId,
        sourcePath: sourcePath,
        mediaType: mediaType,
        fileSize: fileSize,
        thumbnailPath: thumbnailPath,
      );
    } catch (e, st) {
      AppError.handle(e, st, 'TransferTasksNotifier.addCacheTask');
      return null;
    }
  }

  /// 暂停任务
  Future<void> pauseTask(String taskId) async {
    try {
      final service = _ref.read(transferServiceProvider);
      await service.pauseTask(taskId);
    } catch (e, st) {
      AppError.handle(e, st, 'TransferTasksNotifier.pauseTask');
    }
  }

  /// 继续任务
  Future<void> resumeTask(String taskId) async {
    try {
      final service = _ref.read(transferServiceProvider);
      await service.resumeTask(taskId);
    } catch (e, st) {
      AppError.handle(e, st, 'TransferTasksNotifier.resumeTask');
    }
  }

  /// 取消任务
  Future<void> cancelTask(String taskId) async {
    try {
      final service = _ref.read(transferServiceProvider);
      await service.cancelTask(taskId);
    } catch (e, st) {
      AppError.handle(e, st, 'TransferTasksNotifier.cancelTask');
    }
  }

  /// 重试任务
  Future<void> retryTask(String taskId) async {
    try {
      final service = _ref.read(transferServiceProvider);
      await service.retryTask(taskId);
    } catch (e, st) {
      AppError.handle(e, st, 'TransferTasksNotifier.retryTask');
    }
  }

  /// 删除任务
  Future<void> deleteTask(String taskId) async {
    try {
      final service = _ref.read(transferServiceProvider);
      await service.deleteTask(taskId);
    } catch (e, st) {
      AppError.handle(e, st, 'TransferTasksNotifier.deleteTask');
    }
  }

  /// 清除已完成的下载任务
  Future<void> clearCompletedDownloads() async {
    try {
      final service = _ref.read(transferServiceProvider);
      await service.clearCompletedTasks(type: TransferType.download);
    } catch (e, st) {
      AppError.handle(e, st, 'TransferTasksNotifier.clearCompletedDownloads');
    }
  }

  /// 清除已完成的上传任务
  Future<void> clearCompletedUploads() async {
    try {
      final service = _ref.read(transferServiceProvider);
      await service.clearCompletedTasks(type: TransferType.upload);
    } catch (e, st) {
      AppError.handle(e, st, 'TransferTasksNotifier.clearCompletedUploads');
    }
  }

  /// 删除缓存（兼容 TransferTask 和 CachedMediaItem）
  Future<void> deleteCache(String sourceId, String sourcePath) async {
    try {
      // 根据 sourceId 判断缓存来源
      if (sourceId == 'music_audio_cache') {
        // 音乐音频缓存 - sourcePath 就是 cachePath
        final musicCacheService = _ref.read(musicAudioCacheServiceProvider);
        await musicCacheService.deleteCacheByPath(sourcePath);
      } else if (sourceId == 'book_file_cache') {
        // 图书文件缓存 - sourcePath 就是 cachePath
        final bookCacheService = _ref.read(bookFileCacheServiceProvider);
        await bookCacheService.deleteCacheByPath(sourcePath);
      } else {
        // MediaCacheService 缓存
        final cacheService = _ref.read(mediaCacheServiceProvider);
        await cacheService.deleteCache(sourceId, sourcePath);

        // 同时删除对应的缓存任务记录（如果存在）
        try {
          final task = state.tasks.firstWhere(
            (t) =>
                t.type == TransferType.cache &&
                t.sourceId == sourceId &&
                t.sourcePath == sourcePath,
          );
          await deleteTask(task.id);
        } catch (_) {
          // 任务不存在，忽略
        }
      }

      // 刷新缓存项列表
      _ref
        ..invalidate(cachedItemsProvider)
        ..invalidate(allCachedItemsProvider)
        ..invalidate(cacheStatsProvider);
    } catch (e, st) {
      AppError.ignore(e, st, '删除缓存失败');
    }
  }

  /// 清空所有缓存
  Future<void> clearAllCache({MediaType? mediaType}) async {
    try {
      final cacheService = _ref.read(mediaCacheServiceProvider);
      final musicAudioCacheService = _ref.read(musicAudioCacheServiceProvider);
      final bookFileCacheService = _ref.read(bookFileCacheServiceProvider);

      // 清空 MediaCacheService
      await cacheService.clearCache(mediaType: mediaType);

      // 如果清空音乐缓存，同时清空 MusicAudioCacheService
      if (mediaType == null || mediaType == MediaType.music) {
        await musicAudioCacheService.clearAll();
      }

      // 如果清空图书缓存，同时清空 BookFileCacheService
      if (mediaType == null || mediaType == MediaType.book) {
        await bookFileCacheService.clearAll();
      }

      // 清除对应的缓存任务记录
      final service = _ref.read(transferServiceProvider);
      final cacheTasks = state.tasks.where((t) {
        if (t.type != TransferType.cache) return false;
        if (mediaType != null && t.mediaType != mediaType) return false;
        return true;
      }).toList();

      for (final task in cacheTasks) {
        await service.deleteTask(task.id);
      }

      // 刷新缓存项列表
      _ref
        ..invalidate(cachedItemsProvider)
        ..invalidate(allCachedItemsProvider)
        ..invalidate(cacheStatsProvider);
    } catch (e, st) {
      AppError.handle(e, st, 'TransferTasksNotifier.clearAllCache');
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
