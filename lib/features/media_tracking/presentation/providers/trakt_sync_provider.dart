import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/media_tracking/presentation/providers/trakt_provider.dart';
import 'package:my_nas/features/video/data/services/video_database_service.dart';
import 'package:my_nas/features/video/data/services/video_history_service.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/features/video/presentation/providers/video_history_provider.dart';
import 'package:my_nas/service_adapters/trakt/api/trakt_api.dart';
import 'package:my_nas/shared/providers/language_preference_provider.dart';

/// Trakt 同步状态
class TraktSyncState {
  const TraktSyncState({
    this.playbackProgress = const [],
    this.isLoading = false,
    this.lastSyncTime,
    this.errorMessage,
  });

  final List<TraktPlaybackItem> playbackProgress;
  final bool isLoading;
  final DateTime? lastSyncTime;
  final String? errorMessage;

  TraktSyncState copyWith({
    List<TraktPlaybackItem>? playbackProgress,
    bool? isLoading,
    DateTime? lastSyncTime,
    String? errorMessage,
    bool clearError = false,
  }) =>
      TraktSyncState(
        playbackProgress: playbackProgress ?? this.playbackProgress,
        isLoading: isLoading ?? this.isLoading,
        lastSyncTime: lastSyncTime ?? this.lastSyncTime,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      );
}

/// Trakt 同步 Provider
final traktSyncProvider =
    StateNotifierProvider<TraktSyncNotifier, TraktSyncState>(
  TraktSyncNotifier.new,
);

class TraktSyncNotifier extends StateNotifier<TraktSyncState> {
  TraktSyncNotifier(this._ref) : super(const TraktSyncState());

  final Ref _ref;

  /// 获取 Trakt API 实例
  TraktApi? get _api => _ref.read(traktConnectionProvider.notifier).api;

  /// 是否已连接 Trakt
  bool get isConnected =>
      _ref.read(traktConnectionProvider).status == TraktConnectionStatus.connected;

  /// 刷新播放进度列表
  Future<void> refreshPlaybackProgress() async {
    if (!isConnected || _api == null) return;

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final progress = await _api!.getPlaybackProgress();
      state = state.copyWith(
        playbackProgress: progress,
        isLoading: false,
        lastSyncTime: DateTime.now(),
      );
      logger.i('TraktSync: 获取播放进度成功，共 ${progress.length} 项');
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'TraktSync.refreshPlaybackProgress');
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// 根据 TMDB ID 查找播放进度
  TraktPlaybackItem? findProgressByTmdbId(int tmdbId, {int? season, int? episode}) {
    for (final item in state.playbackProgress) {
      if (item.tmdbId == tmdbId) {
        // 如果是剧集，还需要匹配季和集
        if (item.type == 'episode' && season != null && episode != null) {
          final epInfo = item.episodeInfo;
          if (epInfo != null && epInfo.$1 == season && epInfo.$2 == episode) {
            return item;
          }
        } else if (item.type == 'movie') {
          return item;
        }
      }
    }
    return null;
  }

  /// 根据 IMDB ID 查找播放进度
  TraktPlaybackItem? findProgressByImdbId(String imdbId, {int? season, int? episode}) {
    for (final item in state.playbackProgress) {
      if (item.imdbId == imdbId) {
        // 如果是剧集，还需要匹配季和集
        if (item.type == 'episode' && season != null && episode != null) {
          final epInfo = item.episodeInfo;
          if (epInfo != null && epInfo.$1 == season && epInfo.$2 == episode) {
            return item;
          }
        } else if (item.type == 'movie') {
          return item;
        }
      }
    }
    return null;
  }

  /// 删除播放进度
  Future<void> deleteProgress(int playbackId) async {
    if (!isConnected || _api == null) return;

    try {
      await _api!.deletePlaybackProgress(playbackId);
      // 从本地列表中移除
      state = state.copyWith(
        playbackProgress: state.playbackProgress
            .where((item) => item.id != playbackId)
            .toList(),
      );
      logger.i('TraktSync: 删除播放进度成功 id=$playbackId');
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'TraktSync.deleteProgress');
    }
  }

  /// 获取本地视频对应的 Trakt 进度
  ///
  /// 根据视频元数据中的 TMDB/IMDB ID 匹配 Trakt 进度
  Future<TraktPlaybackItem?> getProgressForVideo(
    String videoPath,
    String sourceId,
  ) async {
    if (state.playbackProgress.isEmpty) {
      await refreshPlaybackProgress();
    }

    try {
      final dbService = VideoDatabaseService();
      await dbService.init();
      final metadata = await dbService.get(sourceId, videoPath);

      if (metadata == null) return null;

      // 尝试通过 TMDB ID 匹配
      if (metadata.tmdbId != null) {
        final progress = findProgressByTmdbId(
          metadata.tmdbId!,
          season: metadata.seasonNumber,
          episode: metadata.episodeNumber,
        );
        if (progress != null) return progress;
      }

      // 尝试通过 IMDB ID 匹配
      if (metadata.imdbId != null) {
        return findProgressByImdbId(
          metadata.imdbId!,
          season: metadata.seasonNumber,
          episode: metadata.episodeNumber,
        );
      }

      return null;
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '获取视频 Trakt 进度失败');
      return null;
    }
  }

  /// 将 Trakt 进度转换为播放位置
  ///
  /// [progress] Trakt 进度 (0.0 - 100.0)
  /// [duration] 视频总时长
  Duration progressToDuration(double progress, Duration duration) =>
      Duration(
        milliseconds: (duration.inMilliseconds * progress / 100).round(),
      );
}

/// 获取继续观看列表（结合本地历史和 Trakt 进度）
///
/// 此 Provider 合并本地播放历史和 Trakt 进度，提供统一的继续观看列表
/// 特性：
/// - 合并本地历史和 Trakt 进度
/// - 去重：同一视频优先使用 Trakt 进度
/// - 本地化标题：使用本地数据库中的标题
/// - 匹配本地影视库：只显示本地有对应文件的视频
final combinedContinueWatchingProvider =
    FutureProvider<List<ContinueWatchingItem>>((ref) async {
  final traktSync = ref.watch(traktSyncProvider);
  final traktConnection = ref.watch(traktConnectionProvider);
  final localHistoryAsync = ref.watch(continueWatchingProvider);
  final langPref = ref.watch(languagePreferenceProvider);

  // 用于去重的 Map: key 为 "tmdb_{id}" 或 "path_{videoPath}"
  final itemMap = <String, ContinueWatchingItem>{};

  // 初始化数据库服务
  final dbService = VideoDatabaseService();
  await dbService.init();

  // 获取首选语言列表
  final preferredLangs = langPref.metadataLanguages.isNotEmpty
      ? langPref.metadataLanguages.map((l) => l.code).toList()
      : ['zh-CN', 'en'];

  // 1. 处理 Trakt 进度
  if (traktConnection.isConnected) {
    for (final progress in traktSync.playbackProgress) {
      final tmdbId = progress.tmdbId;
      VideoMetadata? matchedMetadata;
      String? localizedTitle;

      // 尝试从本地数据库查找匹配的元数据
      if (tmdbId != null) {
        final localMatches = await dbService.getByTmdbId(tmdbId);
        if (localMatches.isNotEmpty) {
          // 如果是剧集，尝试匹配季和集
          if (progress.type == 'episode') {
            final epInfo = progress.episodeInfo;
            if (epInfo != null) {
              matchedMetadata = localMatches.where((m) =>
                  m.seasonNumber == epInfo.$1 && m.episodeNumber == epInfo.$2).firstOrNull;
            }
          }
          // 电影或未找到精确匹配的剧集，使用第一个匹配
          matchedMetadata ??= localMatches.first;

          // 获取本地化标题
          localizedTitle = matchedMetadata.getLocalizedTitle(preferredLangs);
        }
      }

      final key = tmdbId != null ? 'tmdb_$tmdbId' : 'trakt_${progress.id}';
      itemMap[key] = ContinueWatchingItem(
        source: ContinueWatchingSource.trakt,
        traktProgress: progress,
        progress: progress.progress,
        updatedAt: progress.pausedAt,
        metadata: matchedMetadata,
        localizedTitle: localizedTitle,
        videoPath: matchedMetadata?.filePath,
        sourceId: matchedMetadata?.sourceId,
      );
    }
  }

  // 2. 处理本地历史
  final localHistory = localHistoryAsync.valueOrNull ?? [];
  for (final item in localHistory) {
    // 尝试获取视频元数据
    VideoMetadata? metadata;
    String? localizedTitle;
    int? tmdbId;

    if (item.sourceId != null) {
      metadata = await dbService.get(item.sourceId!, item.videoPath);
      if (metadata != null) {
        tmdbId = metadata.tmdbId;
        localizedTitle = metadata.getLocalizedTitle(preferredLangs);
      }
    }

    // 去重：如果已有 Trakt 进度，跳过
    final key = tmdbId != null ? 'tmdb_$tmdbId' : 'path_${item.videoPath}';
    if (itemMap.containsKey(key)) continue;

    itemMap[key] = ContinueWatchingItem(
      source: ContinueWatchingSource.local,
      progress: item.progressPercent * 100, // 转换为 0-100
      updatedAt: item.watchedAt,
      videoPath: item.videoPath,
      sourceId: item.sourceId,
      metadata: metadata,
      localizedTitle: localizedTitle,
      localHistoryItem: item,
    );
  }

  // 按更新时间排序
  final items = itemMap.values.toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  logger.d('CombinedContinueWatching: 共 ${items.length} 项 '
      '(Trakt: ${items.where((i) => i.source == ContinueWatchingSource.trakt).length}, '
      'Local: ${items.where((i) => i.source == ContinueWatchingSource.local).length})');

  return items;
});

/// 继续观看来源
enum ContinueWatchingSource {
  local,
  trakt,
  mediaServer,
}

/// 继续观看项
class ContinueWatchingItem {
  const ContinueWatchingItem({
    required this.source,
    required this.progress,
    required this.updatedAt,
    this.videoPath,
    this.sourceId,
    this.traktProgress,
    this.metadata,
    this.localizedTitle,
    this.localHistoryItem,
  });

  final ContinueWatchingSource source;
  final double progress; // 0.0 - 100.0
  final DateTime updatedAt;
  final String? videoPath;
  final String? sourceId;
  final TraktPlaybackItem? traktProgress;
  final VideoMetadata? metadata;
  final String? localizedTitle;
  final VideoHistoryItem? localHistoryItem;

  /// 获取显示标题（优先本地化标题）
  String get displayTitle {
    // 优先使用本地化标题
    if (localizedTitle != null && localizedTitle!.isNotEmpty) {
      return _formatTitleWithEpisode(localizedTitle!);
    }

    // 其次使用本地元数据标题
    if (metadata != null) {
      return _formatTitleWithEpisode(metadata!.displayTitle);
    }

    // 最后使用 Trakt 原始标题
    if (traktProgress != null) {
      if (traktProgress!.type == 'movie') {
        return traktProgress!.movie?.title ?? appL10n.traktSyncUnknownMovie;
      } else {
        final show = traktProgress!.show?.title ?? appL10n.traktSyncUnknownShow;
        final ep = traktProgress!.episode;
        if (ep != null) {
          return '$show S${ep.season.toString().padLeft(2, '0')}E${ep.number.toString().padLeft(2, '0')}';
        }
        return show;
      }
    }

    // 本地历史记录
    if (localHistoryItem != null) {
      return localHistoryItem!.videoName;
    }

    return videoPath ?? appL10n.traktSyncUnknownVideo;
  }

  /// 格式化标题（添加剧集信息）
  String _formatTitleWithEpisode(String title) {
    // 如果是剧集，添加季集信息
    if (traktProgress?.type == 'episode') {
      final ep = traktProgress!.episode;
      if (ep != null) {
        return '$title S${ep.season.toString().padLeft(2, '0')}E${ep.number.toString().padLeft(2, '0')}';
      }
    } else if (metadata?.category == MediaCategory.tvShow &&
        metadata?.seasonNumber != null &&
        metadata?.episodeNumber != null) {
      return '$title S${metadata!.seasonNumber.toString().padLeft(2, '0')}E${metadata!.episodeNumber.toString().padLeft(2, '0')}';
    }
    return title;
  }

  /// 获取海报 URL
  String? get posterUrl {
    // 优先使用本地元数据海报
    if (metadata?.displayPosterUrl != null) {
      return metadata!.displayPosterUrl;
    }
    // 本地历史记录的缩略图
    if (localHistoryItem?.thumbnailUrl != null) {
      return localHistoryItem!.thumbnailUrl;
    }
    return null;
  }

  /// 获取 TMDB ID
  int? get tmdbId {
    if (metadata?.tmdbId != null) return metadata!.tmdbId;
    if (traktProgress != null) return traktProgress!.tmdbId;
    return null;
  }

  /// 是否有本地文件
  bool get hasLocalFile => videoPath != null && videoPath!.isNotEmpty;

  /// 是否可播放（有本地文件或本地历史记录）
  bool get isPlayable => hasLocalFile || localHistoryItem != null;
}

/// Trakt 观看历史 Provider
final traktWatchHistoryProvider =
    FutureProvider.autoDispose<List<TraktHistoryItem>>((ref) async {
  final traktConnection = ref.watch(traktConnectionProvider);
  if (!traktConnection.isConnected) return [];

  final api = ref.read(traktConnectionProvider.notifier).api;
  if (api == null) return [];

  try {
    return await api.getWatchedHistory(limit: 50);
  } on Exception catch (e, st) {
    AppError.handle(e, st, 'TraktWatchHistory.fetch');
    return [];
  }
});

/// Trakt 待看列表 Provider
final traktWatchlistProvider =
    FutureProvider.autoDispose<List<TraktWatchlistItem>>((ref) async {
  final traktConnection = ref.watch(traktConnectionProvider);
  if (!traktConnection.isConnected) return [];

  final api = ref.read(traktConnectionProvider.notifier).api;
  if (api == null) return [];

  try {
    return await api.getWatchlist(limit: 50);
  } on Exception catch (e, st) {
    AppError.handle(e, st, 'TraktWatchlist.fetch');
    return [];
  }
});
