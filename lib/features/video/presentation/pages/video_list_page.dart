// ignore_for_file: unused_element

import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/shared/mixins/tab_bar_visibility_mixin.dart';
import 'package:my_nas/shared/providers/media_favorites_provider.dart';
import 'package:my_nas/shared/providers/ui_style_provider.dart';
import 'package:my_nas/shared/widgets/media_info_sheet.dart';
import 'package:my_nas/shared/widgets/adaptive_glass_app_bar.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/utils/grid_helper.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/pages/media_library_page.dart';
import 'package:my_nas/features/sources/presentation/pages/sources_page.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/video/data/services/tmdb_service.dart';
import 'package:my_nas/features/video/data/services/video_database_service.dart';
import 'package:my_nas/features/video/data/services/video_history_service.dart';
import 'package:my_nas/features/video/data/services/video_library_cache_service.dart';
import 'package:my_nas/features/video/data/services/video_metadata_service.dart';
import 'package:my_nas/features/video/data/services/video_scanner_service.dart';
import 'package:my_nas/features/video/data/services/video_thumbnail_service.dart';
import 'package:my_nas/features/video/domain/entities/tv_show_group.dart';
import 'package:my_nas/features/video/domain/entities/video_category_config.dart';
import 'package:my_nas/features/video/domain/entities/video_item.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/features/video/presentation/pages/video_detail_page.dart';
import 'package:my_nas/features/video/presentation/pages/video_duplicates_page.dart';
import 'package:my_nas/features/video/presentation/pages/video_player_page.dart';
import 'package:my_nas/features/video/presentation/providers/playlist_provider.dart';
import 'package:my_nas/features/video/presentation/providers/video_category_settings_provider.dart';
import 'package:my_nas/features/video/presentation/providers/video_detail_provider.dart';
import 'package:my_nas/features/video/presentation/providers/video_history_provider.dart';
import 'package:my_nas/features/media_tracking/presentation/providers/trakt_sync_provider.dart';
import 'package:my_nas/features/video/presentation/widgets/category_browse_cards.dart';
import 'package:my_nas/features/video/presentation/widgets/hero_banner.dart';
import 'package:my_nas/features/video/presentation/widgets/live_stream_section.dart';
import 'package:my_nas/features/video/presentation/widgets/video_category_settings_sheet.dart';
import 'package:my_nas/features/video/presentation/widgets/video_poster.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/shared/widgets/adaptive_image.dart';
import 'package:my_nas/shared/widgets/app_bottom_sheet.dart';
import 'package:my_nas/shared/widgets/context_menu_region.dart';
import 'package:my_nas/shared/widgets/error_widget.dart';

/// 视频文件及其来源
class VideoFileWithSource {
  VideoFileWithSource({required this.file, required this.sourceId});

  final FileItem file;
  final String sourceId;

  String get name => file.name;
  String get path => file.path;
  int get size => file.size;
  DateTime? get modifiedTime => file.modifiedTime;
  String? get thumbnailUrl => file.thumbnailUrl;
  String get displaySize => file.displaySize;

  VideoLibraryCacheEntry toCacheEntry() => VideoLibraryCacheEntry(
    sourceId: sourceId,
    filePath: path,
    fileName: name,
    thumbnailUrl: thumbnailUrl,
    size: size,
    modifiedTime: modifiedTime,
  );
}

/// 视频列表状态
final videoListProvider =
    StateNotifierProvider<VideoListNotifier, VideoListState>(
      VideoListNotifier.new,
    );

/// 视频分类标签
enum VideoTab { all, movies, tvShows, other, recent }

/// 渐进式加载阶段
enum VideoLoadingPhase {
  /// 初始阶段：仅有统计数据
  stats,

  /// 第一批次完成：有每日推荐、最近添加、电影数据
  batch1,

  /// 全部完成：包含剧集、电影系列、其他视频
  complete,
}

sealed class VideoListState {}

class VideoListLoading extends VideoListState {
  VideoListLoading({
    this.progress = 0,
    this.currentFolder,
    this.fromCache = false,
    this.partialVideos = const [],
    this.scannedCount = 0,
  });
  final double progress;
  final String? currentFolder;
  final bool fromCache;
  final List<VideoFileWithSource> partialVideos;
  final int scannedCount;
}

/// 优化后的视频列表状态 - 使用分类数据而非全量内存加载
class VideoListLoaded extends VideoListState {
  VideoListLoaded({
    required this.totalCount,
    this.databaseTotalCount = 0,
    this.movieCount = 0,
    this.tvShowCount = 0,
    this.tvShowGroupCount = 0,
    this.otherCount = 0,
    this.currentTab = VideoTab.all,
    this.searchQuery = '',
    this.isLoadingMetadata = false,
    this.fromCache = false,
    // 渐进式加载阶段
    this.loadingPhase = VideoLoadingPhase.complete,
    // 分类数据 - 从 SQLite 分页加载
    this.topRatedMovies = const [],
    this.recentVideos = const [],
    this.movies = const [],
    this.tvShowGroups = const {},
    this.others = const [],
    // 电影系列数据
    this.movieCollections = const [],
    // 搜索结果
    this.searchResults = const [],
    // 用于快速查找的 Map（O(1) 查找）
    this.videoByKey = const {},
  });

  final int totalCount;

  /// 数据库中的总数量（不经过路径过滤）
  /// 用于判断是否有数据但被路径过滤掉了
  final int databaseTotalCount;
  final int movieCount;

  /// 剧集集数（单集数量）
  final int tvShowCount;

  /// 剧集分组数量（不同电视剧数量）
  final int tvShowGroupCount;

  /// 其他视频数量（未识别为电影或剧集的视频）
  final int otherCount;
  final VideoTab currentTab;
  final String searchQuery;
  final bool isLoadingMetadata;
  final bool fromCache;

  /// 渐进式加载阶段
  final VideoLoadingPhase loadingPhase;

  /// 是否还在加载中（用于显示骨架屏）
  bool get isStillLoading => loadingPhase != VideoLoadingPhase.complete;

  // 分类数据 - 已从 SQLite 按评分排序
  final List<VideoMetadata> topRatedMovies;
  final List<VideoMetadata> recentVideos;
  final List<VideoMetadata> movies;

  /// 剧集分组（使用 TvShowGroup 按季组织）
  final Map<String, TvShowGroup> tvShowGroups;

  /// 其他视频（未识别为电影或剧集）
  final List<VideoMetadata> others;

  /// 电影系列
  final List<MovieCollection> movieCollections;

  // 搜索结果
  final List<VideoMetadata> searchResults;

  // 用于 O(1) 查找的 Map
  final Map<String, VideoMetadata> videoByKey;

  /// 根据当前分类获取过滤后的数据
  List<VideoMetadata> get filteredMetadata {
    if (searchQuery.isNotEmpty) return searchResults;

    switch (currentTab) {
      case VideoTab.all:
        // 返回所有视频（合并电影、剧集代表和其他）
        final allVideos = <VideoMetadata>[...movies, ...others];
        for (final group in tvShowGroups.values) {
          allVideos.add(group.representative);
        }
        // 按上映年份降序排序（晚上映的排在前面）
        allVideos.sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
        return allVideos;
      case VideoTab.movies:
        return movies;
      case VideoTab.tvShows:
        // 返回每个剧集的代表（第一季第一集）
        return tvShowGroups.values.map((g) => g.representative).toList();
      case VideoTab.other:
        return others;
      case VideoTab.recent:
        return recentVideos;
    }
  }

  /// 获取剧集分组列表（用于展示剧集卡片）
  List<TvShowGroup> get tvShowGroupList => tvShowGroups.values.toList();

  VideoListLoaded copyWith({
    int? totalCount,
    int? databaseTotalCount,
    int? movieCount,
    int? tvShowCount,
    int? tvShowGroupCount,
    int? otherCount,
    VideoTab? currentTab,
    String? searchQuery,
    bool? isLoadingMetadata,
    bool? fromCache,
    VideoLoadingPhase? loadingPhase,
    List<VideoMetadata>? topRatedMovies,
    List<VideoMetadata>? recentVideos,
    List<VideoMetadata>? movies,
    Map<String, TvShowGroup>? tvShowGroups,
    List<VideoMetadata>? others,
    List<MovieCollection>? movieCollections,
    List<VideoMetadata>? searchResults,
    Map<String, VideoMetadata>? videoByKey,
  }) => VideoListLoaded(
    totalCount: totalCount ?? this.totalCount,
    databaseTotalCount: databaseTotalCount ?? this.databaseTotalCount,
    movieCount: movieCount ?? this.movieCount,
    tvShowCount: tvShowCount ?? this.tvShowCount,
    tvShowGroupCount: tvShowGroupCount ?? this.tvShowGroupCount,
    otherCount: otherCount ?? this.otherCount,
    currentTab: currentTab ?? this.currentTab,
    searchQuery: searchQuery ?? this.searchQuery,
    isLoadingMetadata: isLoadingMetadata ?? this.isLoadingMetadata,
    fromCache: fromCache ?? this.fromCache,
    loadingPhase: loadingPhase ?? this.loadingPhase,
    topRatedMovies: topRatedMovies ?? this.topRatedMovies,
    recentVideos: recentVideos ?? this.recentVideos,
    movies: movies ?? this.movies,
    tvShowGroups: tvShowGroups ?? this.tvShowGroups,
    others: others ?? this.others,
    movieCollections: movieCollections ?? this.movieCollections,
    searchResults: searchResults ?? this.searchResults,
    videoByKey: videoByKey ?? this.videoByKey,
  );
}

class VideoListError extends VideoListState {
  VideoListError(this.message);
  final String message;
}

class VideoListNotifier extends StateNotifier<VideoListState> {
  VideoListNotifier(this._ref) : super(VideoListLoading()) {
    // 使用 addPostFrameCallback 推迟初始化，确保导航动画不被阻塞
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _init();
    });

    final scanner = VideoScannerService();

    // 监听扫描进度变化，实现扫描过程中的实时更新
    _scanProgressSubscription = scanner.progressStream.listen(
      _onScanProgressChanged,
    );

    // 边扫边显示（Infuse 风格）：监听部分扫描结果
    // 每扫描一批文件就推送，用户不需要等待扫描完成
    _partialResultsSubscription = scanner.partialResultsStream.listen(
      _onPartialResults,
    );

    // 单视频更新（Infuse 风格）：监听单个视频元数据更新
    // 替代整体 scrapeStatsStream 刷新，实现精准卡片更新
    _videoUpdatedSubscription = scanner.videoUpdatedStream.listen(
      _onVideoUpdated,
    );

    // 监听刮削统计变化（保留用于总数变化和全部完成检测）
    _scrapeStatsSubscription = scanner.scrapeStatsStream.listen(
      _onScrapeStatsChanged,
    );

    // 监听连接状态变化，当有新连接时检查恢复刮削
    _connectionsSubscription = _ref.listen<Map<String, SourceConnection>>(
      activeConnectionsProvider,
      _onConnectionsChanged,
      fireImmediately: false,
    );

    // 监听媒体库配置变化（启用/停用/移除路径）
    _configSubscription = _ref.listen<AsyncValue<MediaLibraryConfig>>(
      mediaLibraryConfigProvider,
      (previous, next) {
        final prevPaths =
            previous?.valueOrNull?.getEnabledPathsForType(MediaType.video) ??
                [];
        final nextPaths =
            next.valueOrNull?.getEnabledPathsForType(MediaType.video) ?? [];

        // 比较路径是否变化（包括 sourceId 和 path）
        final prevKeys = prevPaths.map((p) => '${p.sourceId}|${p.path}').toSet();
        final nextKeys = nextPaths.map((p) => '${p.sourceId}|${p.path}').toSet();

        if (prevKeys.length != nextKeys.length ||
            !prevKeys.containsAll(nextKeys)) {
          logger.i('VideoListNotifier: 媒体库配置变化，刷新视频列表');
          _scheduleRefresh();
        }
      },
      fireImmediately: false,
    );
  }

  final Ref _ref;
  final VideoMetadataService _metadataService = VideoMetadataService();
  final VideoLibraryCacheService _cacheService = VideoLibraryCacheService();
  final VideoDatabaseService _db = VideoDatabaseService();

  StreamSubscription<VideoScanProgress>? _scanProgressSubscription;
  StreamSubscription<List<VideoMetadata>>? _partialResultsSubscription;
  StreamSubscription<VideoMetadata>? _videoUpdatedSubscription;
  StreamSubscription<ScrapeStats>? _scrapeStatsSubscription;
  ProviderSubscription<Map<String, SourceConnection>>? _connectionsSubscription;
  ProviderSubscription<AsyncValue<MediaLibraryConfig>>? _configSubscription;
  int _lastCompletedCount = 0;
  int _lastTotalCount = 0; // 跟踪总数变化，用于扫描完成时刷新
  bool _hasCheckedResume = false;
  Timer? _debounceTimer;

  /// 增量同步计时器（刮削期间每3秒同步一次聚合表）
  Timer? _incrementalSyncTimer;

  /// 增量同步间隔（秒）
  static const int _incrementalSyncIntervalSeconds = 3;

  /// 上次同步时的完成数（用于检测是否有新数据）
  int _lastSyncedCompletedCount = 0;

  /// 防抖间隔（毫秒）- 避免频繁刷新导致UI卡顿
  static const int _debounceMs = 500;

  /// 获取启用的路径列表（用于 SQLite 过滤）
  ///
  /// 返回 null 表示不进行路径过滤（显示所有数据）
  /// 返回空列表也会被转换为 null（不过滤）
  List<({String sourceId, String path})>? _getEnabledPaths() {
    final configState = _ref.read(mediaLibraryConfigProvider);

    // 配置还在加载中，不进行路径过滤
    if (configState.isLoading) {
      logger.d('VideoListNotifier: 媒体库配置加载中，跳过路径过滤');
      return null;
    }

    // 配置加载失败，不进行路径过滤
    if (configState.hasError) {
      logger.w('VideoListNotifier: 媒体库配置加载失败，跳过路径过滤');
      return null;
    }

    final config = configState.valueOrNull;
    if (config == null) {
      logger.d('VideoListNotifier: 媒体库配置为空，跳过路径过滤');
      return null;
    }

    final enabledPaths = config.getEnabledPathsForType(MediaType.video);
    if (enabledPaths.isEmpty) {
      logger.d('VideoListNotifier: 视频路径列表为空，跳过路径过滤');
      return null;
    }

    // 详细记录路径配置，帮助诊断路径匹配问题
    final result = enabledPaths
        .map((p) => (sourceId: p.sourceId, path: p.path))
        .toList();

    logger.d(
      'VideoListNotifier: 启用的视频路径: ${result.map((p) => '${p.sourceId}:${p.path}').join(', ')}',
    );

    return result;
  }

  @override
  void dispose() {
    _scanProgressSubscription?.cancel();
    _partialResultsSubscription?.cancel();
    _videoUpdatedSubscription?.cancel();
    _scrapeStatsSubscription?.cancel();
    _connectionsSubscription?.close();
    _configSubscription?.close();
    _debounceTimer?.cancel();
    _incrementalSyncTimer?.cancel();
    super.dispose();
  }

  /// 预缓存首页封面图片
  ///
  /// 在数据加载完成后立即触发图片预加载，避免用户看到空白封面
  /// 只预缓存前几个分类的图片，避免过度消耗内存和带宽
  void _precacheHomeImages(VideoListLoaded loadedState) {
    // 收集需要预缓存的网络图片 URL
    final urlsToPrecache = <String>{};

    // 1. 每日推荐/Hero Banner（最重要，优先加载）
    for (final video in loadedState.topRatedMovies.take(6)) {
      final posterUrl = video.displayPosterUrl;
      if (posterUrl != null && VideoPoster.isNetworkUrl(posterUrl)) {
        urlsToPrecache.add(posterUrl);
      }
      // 也预缓存背景图（用于 Hero Banner）
      final backdropUrl = video.backdropUrl;
      if (backdropUrl != null && VideoPoster.isNetworkUrl(backdropUrl)) {
        urlsToPrecache.add(backdropUrl);
      }
    }

    // 2. 最近添加（第二重要）
    for (final video in loadedState.recentVideos.take(8)) {
      final posterUrl = video.displayPosterUrl;
      if (posterUrl != null && VideoPoster.isNetworkUrl(posterUrl)) {
        urlsToPrecache.add(posterUrl);
      }
    }

    // 3. 电影列表前几个
    for (final video in loadedState.movies.take(6)) {
      final posterUrl = video.displayPosterUrl;
      if (posterUrl != null && VideoPoster.isNetworkUrl(posterUrl)) {
        urlsToPrecache.add(posterUrl);
      }
    }

    // 4. 剧集列表前几个
    for (final group in loadedState.tvShowGroups.values.take(6)) {
      final posterUrl = group.displayPosterUrl;
      if (posterUrl != null && VideoPoster.isNetworkUrl(posterUrl)) {
        urlsToPrecache.add(posterUrl);
      }
    }

    // 5. 电影系列前几个
    for (final collection in loadedState.movieCollections.take(4)) {
      final posterUrl = collection.posterUrl;
      if (posterUrl != null && VideoPoster.isNetworkUrl(posterUrl)) {
        urlsToPrecache.add(posterUrl);
      }
    }

    if (urlsToPrecache.isEmpty) return;

    logger.d('VideoListNotifier: 开始预缓存 ${urlsToPrecache.length} 张首页封面图片');

    // 异步预缓存，不阻塞主线程
    // 使用 SchedulerBinding 确保在帧回调后执行，避免影响 UI 渲染
    SchedulerBinding.instance.addPostFrameCallback((_) {
      AppError.fireAndForget(
        Future(() async {
          for (final url in urlsToPrecache) {
            try {
              // 使用 CachedNetworkImageProvider 预缓存
              final provider = CachedNetworkImageProvider(url);
              final completer = Completer<void>();
              final stream = provider.resolve(ImageConfiguration.empty);

              late ImageStreamListener listener;
              listener = ImageStreamListener(
                (imageInfo, synchronousCall) {
                  if (!completer.isCompleted) {
                    completer.complete();
                    stream.removeListener(listener);
                  }
                },
                onError: (error, stackTrace) {
                  if (!completer.isCompleted) {
                    completer.complete(); // 错误时也完成，继续下一张
                    stream.removeListener(listener);
                  }
                },
              );
              stream.addListener(listener);
              await completer.future;
            } on Exception catch (_) {
              // 单张图片加载失败不影响其他图片
            }
          }
          logger.d('VideoListNotifier: 首页封面图片预缓存完成');
        }),
        action: 'precacheHomeImages',
      );
    });
  }

  /// 扫描进度变化时的处理
  ///
  /// 当扫描完成（savingToDb 或 completed 阶段）时刷新数据，
  /// 确保用户在扫描完成后立即看到视频列表
  void _onScanProgressChanged(VideoScanProgress progress) {
    switch (progress.phase) {
      case VideoScanPhase.completed:
        // 扫描完成，立即刷新数据
        logger.d('VideoListNotifier: 扫描完成，刷新视频列表');
        _debounceTimer?.cancel();
        _loadCategorizedData(silent: true);
      case VideoScanPhase.savingToDb:
        // 正在保存到数据库，实时触发刷新（依赖 500ms 防抖控制频率）
        if (progress.scannedCount > 0) {
          _scheduleRefresh();
        }
      case VideoScanPhase.scanning:
      case VideoScanPhase.scraping:
      case VideoScanPhase.error:
        // 其他阶段不需要特殊处理
        break;
    }
  }

  /// 连接状态变化时检查是否需要恢复刮削
  void _onConnectionsChanged(
    Map<String, SourceConnection>? previous,
    Map<String, SourceConnection> next,
  ) {
    // 只在首次有连接成功时检查恢复刮削
    if (_hasCheckedResume) return;

    final hasConnected = next.values.any(
      (c) => c.status == SourceStatus.connected,
    );
    if (hasConnected) {
      _hasCheckedResume = true;
      logger.d('VideoListNotifier: 检测到连接成功，检查是否有待恢复的刮削任务');
      VideoScannerService().checkAndResumeScraping(next);
    }
  }

  /// 刮削统计变化时刷新数据
  ///
  /// 使用防抖机制实现实时更新：
  /// - 每次刮削完成触发防抖计时器
  /// - 在防抖间隔内如果有新的完成，重置计时器
  /// - 防抖时间到期后执行一次刷新
  /// - 刮削全部完成时立即刷新
  /// - 当总数变化时也触发刷新（说明扫描完成有新视频加入）
  void _onScrapeStatsChanged(ScrapeStats stats) {
    logger.d(
      'VideoListNotifier: 收到统计更新 - total: ${stats.total}, completed: ${stats.completed}, '
      'pending: ${stats.pending}, isAllDone: ${stats.isAllDone}, '
      'lastTotal: $_lastTotalCount, lastCompleted: $_lastCompletedCount',
    );

    // 检查当前 UI 状态 - 如果数据库有数据但 UI 显示为空，强制刷新
    final currentState = state;
    if (currentState is VideoListLoaded) {
      logger.d(
        'VideoListNotifier: 当前 UI 状态 - totalCount: ${currentState.totalCount}, '
        'databaseTotalCount: ${currentState.databaseTotalCount}',
      );
    }
    if (currentState is VideoListLoaded &&
        currentState.totalCount == 0 &&
        stats.total > 0) {
      logger.d('VideoListNotifier: UI 为空但数据库有 ${stats.total} 个视频，强制刷新');
      _debounceTimer?.cancel();
      _lastCompletedCount = stats.completed;
      _lastTotalCount = stats.total;
      _loadCategorizedData(silent: true);
      return;
    }

    // 当刮削全部完成时，做一次完整分类刷新（重新排序高分推荐等）
    if (stats.isAllDone && stats.total > 0) {
      logger.d('VideoListNotifier: 刮削全部完成，执行完整分类刷新');
      _stopIncrementalSyncTimer(); // 停止增量同步
      _debounceTimer?.cancel();
      _lastCompletedCount = stats.completed;
      _lastTotalCount = stats.total;
      _loadCategorizedData(silent: true, forceSync: true);
      return;
    }

    // 刮削进行中：启动增量同步计时器
    if (stats.pending > 0 && stats.completed > _lastSyncedCompletedCount) {
      _startIncrementalSyncTimer();
    }

    // 当总数变化时（新扫描完成），立即刷新
    if (stats.total != _lastTotalCount) {
      logger.d('VideoListNotifier: 视频总数变化 $_lastTotalCount -> ${stats.total}');
      _lastTotalCount = stats.total;
      _lastCompletedCount = stats.completed;
      // 不需要立即刷新，partialResultsStream 会处理
      return;
    }

    // 更新完成计数（用于进度显示）
    _lastCompletedCount = stats.completed;
    // 注意：刮削进行中的更新现在由 videoUpdatedStream 处理，这里不再触发刷新
  }

  /// 启动增量同步计时器
  ///
  /// 刮削期间每隔 [_incrementalSyncIntervalSeconds] 秒同步一次聚合表
  /// 确保剧集分组和电影系列的海报能及时更新
  void _startIncrementalSyncTimer() {
    if (_incrementalSyncTimer?.isActive ?? false) return;

    logger.d('VideoListNotifier: 启动增量同步计时器');
    _incrementalSyncTimer = Timer.periodic(
      Duration(seconds: _incrementalSyncIntervalSeconds),
      (_) => _performIncrementalSync(),
    );
  }

  /// 停止增量同步计时器
  void _stopIncrementalSyncTimer() {
    if (_incrementalSyncTimer?.isActive ?? false) {
      logger.d('VideoListNotifier: 停止增量同步计时器');
      _incrementalSyncTimer?.cancel();
      _incrementalSyncTimer = null;
    }
  }

  /// 执行增量同步（只同步聚合表，不重建整个 UI）
  ///
  /// 性能优化策略：
  /// 1. 至少有 [_minCompletionsBeforeSync] 个新完成才执行同步
  /// 2. 使用 fire-and-forget 模式执行 UI 刷新，不阻塞计时器
  Future<void> _performIncrementalSync() async {
    // 检查是否有足够的新完成数据（至少10个）
    const minCompletionsBeforeSync = 10;
    final newCompletions = _lastCompletedCount - _lastSyncedCompletedCount;
    if (newCompletions < minCompletionsBeforeSync) {
      return;
    }

    logger.d('VideoListNotifier: 执行增量同步 (新增完成数: $newCompletions)');
    _lastSyncedCompletedCount = _lastCompletedCount;

    // 在后台执行，不阻塞主线程
    // 使用 AppError.fireAndForget 确保异常被捕获
    AppError.fireAndForget(
      Future(() async {
        // 同步聚合表
        await Future.wait([
          _db.syncTvShowGroups(),
          _db.syncMovieCollectionGroups(),
        ]);

        // 静默刷新数据（用户无感知）
        await _loadCategorizedData(silent: true);
      }),
      action: 'incrementalSync',
    );
  }

  /// 边扫边显示（Infuse 风格）：处理部分扫描结果
  ///
  /// 每收到一批扫描结果就追加到列表中
  /// 用户可以在扫描过程中就看到视频
  void _onPartialResults(List<VideoMetadata> newVideos) {
    if (newVideos.isEmpty) return;

    final currentState = state;
    if (currentState is! VideoListLoaded) {
      // 如果还没有初始化完成，创建新状态
      final videoByKey = <String, VideoMetadata>{};
      for (final v in newVideos) {
        videoByKey[v.uniqueKey] = v;
      }
      state = VideoListLoaded(
        totalCount: newVideos.length,
        databaseTotalCount: newVideos.length,
        videoByKey: videoByKey,
        recentVideos: newVideos.take(20).toList(),
        movies: newVideos
            .where((v) => v.category == MediaCategory.movie)
            .take(30)
            .toList(),
        others: newVideos
            .where((v) => v.category == MediaCategory.unknown)
            .take(30)
            .toList(),
        fromCache: true,
      );
      logger.d('VideoListNotifier: 边扫边显示 - 初始化 ${newVideos.length} 个视频');
      return;
    }

    // 追加到现有状态
    final newVideoByKey = Map<String, VideoMetadata>.from(
      currentState.videoByKey,
    );
    for (final v in newVideos) {
      newVideoByKey[v.uniqueKey] = v;
    }

    // 追加到各分类列表
    final newMovies = List<VideoMetadata>.from(currentState.movies);
    final newOthers = List<VideoMetadata>.from(currentState.others);
    final newRecent = List<VideoMetadata>.from(currentState.recentVideos);

    for (final v in newVideos) {
      if (v.category == MediaCategory.movie && newMovies.length < 50) {
        newMovies.add(v);
      } else if (v.category == MediaCategory.unknown && newOthers.length < 50) {
        newOthers.add(v);
      }
      if (newRecent.length < 30) {
        newRecent.add(v);
      }
    }

    state = currentState.copyWith(
      totalCount: newVideoByKey.length,
      databaseTotalCount: newVideoByKey.length,
      videoByKey: newVideoByKey,
      recentVideos: newRecent,
      movies: newMovies,
      others: newOthers,
      movieCount: newMovies.length,
      otherCount: newOthers.length,
    );

    logger.d(
      'VideoListNotifier: 边扫边显示 - 追加 ${newVideos.length} 个视频，总计 ${newVideoByKey.length}',
    );
  }

  /// 单视频更新（Infuse 风格）：处理单个视频元数据更新
  ///
  /// 只更新这一个视频的数据，不刷新整个列表
  /// 这是精准更新的核心，避免 ListView 重建
  void _onVideoUpdated(VideoMetadata updated) {
    final currentState = state;
    if (currentState is! VideoListLoaded) return;

    final key = updated.uniqueKey;
    final existing = currentState.videoByKey[key];

    // 如果视频不在当前显示列表中，忽略
    if (existing == null) return;

    // 检查是否有实际变化
    if (!_hasMetadataChanged(existing, updated)) return;

    // 更新 videoByKey
    final newVideoByKey = Map<String, VideoMetadata>.from(
      currentState.videoByKey,
    );
    newVideoByKey[key] = updated;

    // 更新各分类列表中的视频
    final newMovies = _updateSingleInList(currentState.movies, key, updated);
    final newOthers = _updateSingleInList(currentState.others, key, updated);
    final newRecent = _updateSingleInList(
      currentState.recentVideos,
      key,
      updated,
    );
    final newTopRated = _updateSingleInList(
      currentState.topRatedMovies,
      key,
      updated,
    );

    state = currentState.copyWith(
      videoByKey: newVideoByKey,
      movies: newMovies,
      others: newOthers,
      recentVideos: newRecent,
      topRatedMovies: newTopRated,
    );

    logger.d('VideoListNotifier: 单视频更新 - ${updated.title ?? updated.fileName}');
  }

  /// 更新列表中的单个视频
  List<VideoMetadata> _updateSingleInList(
    List<VideoMetadata> list,
    String key,
    VideoMetadata updated,
  ) {
    final index = list.indexWhere((v) => v.uniqueKey == key);
    if (index == -1) return list;

    final newList = List<VideoMetadata>.from(list);
    newList[index] = updated;
    return newList;
  }

  /// 使用防抖机制调度刷新（完整刷新）
  void _scheduleRefresh() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(
      const Duration(milliseconds: _debounceMs),
      () => _loadCategorizedData(silent: true),
    );
  }

  /// 检查元数据是否有变化
  bool _hasMetadataChanged(VideoMetadata old, VideoMetadata updated) =>
      old.title != updated.title ||
      old.posterUrl != updated.posterUrl ||
      old.localPosterUrl != updated.localPosterUrl ||
      old.generatedThumbnailUrl != updated.generatedThumbnailUrl ||
      old.rating != updated.rating ||
      old.tmdbId != updated.tmdbId ||
      old.year != updated.year;

  void _init() {
    logger.d('VideoListNotifier: 开始初始化...');

    // 关键优化：立即显示空状态UI，让用户立即看到界面
    // 用户不会看到黑屏或loading状态
    state = VideoListLoaded(totalCount: 0);

    // Infuse 风格的两阶段加载：
    // 阶段1：快速加载所有视频（毫秒级）
    // 阶段2：后台加载分类数据（可以较慢）
    AppError.fireAndForget(
      _initAndLoadInBackground().then((_) {
        logger.i('VideoListNotifier: 后台初始化完成');
      }),
      action: 'videoList.initAndLoadInBackground',
    );
  }

  /// Infuse 风格的两阶段加载
  ///
  /// 阶段1：快速加载 - 立即显示所有视频（<50ms）
  /// 阶段2：分类加载 - 后台加载分类数据（高分推荐、最近添加等）
  Future<void> _initAndLoadInBackground() async {
    try {
      // 快速初始化服务（SQLite和Hive都是本地操作，应该很快）
      await Future.wait([
        _metadataService.init(),
        _cacheService.init(),
        _db.init(),
      ]).timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          logger.w('VideoListNotifier: 服务初始化超时');
          return <void>[];
        },
      );

      logger.d('VideoListNotifier: 服务初始化完成');

      // ========== 阶段1：快速加载（Infuse 风格）==========
      // 使用简单查询立即获取所有视频，不做复杂分类
      // 同时并行查询统计数量，确保显示真实数量而非临时列表长度
      final enabledPaths = _getEnabledPaths();
      final stopwatch = Stopwatch()..start();

      // 并行执行：获取视频列表 + 查询统计数量
      final phase1Results = await Future.wait([
        _db.getAllVideosQuick(enabledPaths: enabledPaths),
        _db.getStats(enabledPaths: enabledPaths),
        _db.getTvShowGroupCount(enabledPaths: enabledPaths),
      ]);

      final allVideos = phase1Results[0] as List<VideoMetadata>;
      final stats = phase1Results[1] as Map<String, dynamic>;
      final tvShowGroupCount = phase1Results[2] as int;

      stopwatch.stop();
      logger.i(
        'VideoListNotifier: 阶段1完成 - 快速加载 ${allVideos.length} 个视频，耗时 ${stopwatch.elapsedMilliseconds}ms',
      );

      // 同步统计值
      try {
        final scrapeStats = await _db.getScrapeStats();
        _lastTotalCount = scrapeStats.total;
        _lastCompletedCount = scrapeStats.completed;
      } on Exception catch (e) {
        logger.w('VideoListNotifier: 同步统计值失败', e);
      }

      if (allVideos.isEmpty) {
        // 没有数据，保持空状态
        state = VideoListLoaded(totalCount: 0);
        return;
      }

      // 快速构建临时数据结构，立即显示
      final videoByKey = <String, VideoMetadata>{};
      for (final v in allVideos) {
        videoByKey[v.uniqueKey] = v;
      }

      // 立即更新 UI（阶段1完成）
      // 临时分类：简单过滤，后续会被完整分类数据替换
      final tempMovies = allVideos
          .where((v) => v.category == MediaCategory.movie)
          .take(30)
          .toList();
      final tempTvShows = allVideos
          .where((v) => v.category == MediaCategory.tvShow)
          .toList();
      final tempOthers = allVideos
          .where((v) => v.category == MediaCategory.unknown)
          .take(30)
          .toList();

      // 快速构建临时剧集分组（遍历所有剧集，按分组去重后取前30个分组）
      final tempTvShowGroups = <String, TvShowGroup>{};
      for (final ep in tempTvShows) {
        // 达到30个分组后停止
        if (tempTvShowGroups.length >= 30) break;

        final groupKey = ep.tmdbId != null
            ? 'tmdb_${ep.tmdbId}'
            : (ep.showDirectory != null
                  ? 'dir_${ep.showDirectory}'
                  : 'title_${ep.title?.toLowerCase() ?? ep.fileName.toLowerCase()}');
        if (!tempTvShowGroups.containsKey(groupKey)) {
          tempTvShowGroups[groupKey] = TvShowGroup(
            groupKey: groupKey,
            title: ep.title ?? ep.fileName,
            tmdbId: ep.tmdbId,
            posterUrl: ep.posterUrl,
            backdropUrl: ep.backdropUrl,
            rating: ep.rating,
            overview: ep.overview,
            year: ep.year,
            genres: ep.genres,
            seasonEpisodes: {
              ep.seasonNumber ?? 1: [ep],
            },
          );
        }
      }

      // 构建最近添加列表（应用剧集分组去重）
      final tempRecent = _buildRecentWithGroups(
        allVideos,
        tempTvShowGroups,
        limit: 20,
      );

      // 使用真实统计数量，而非临时列表长度
      state = VideoListLoaded(
        totalCount: allVideos.length,
        databaseTotalCount: allVideos.length,
        movieCount: stats['movies'] as int? ?? tempMovies.length,
        tvShowCount: stats['tvShows'] as int? ?? tempTvShows.length,
        tvShowGroupCount: tvShowGroupCount,
        otherCount: stats['others'] as int? ?? tempOthers.length,
        videoByKey: videoByKey,
        recentVideos: tempRecent,
        movies: tempMovies,
        tvShowGroups: tempTvShowGroups,
        others: tempOthers,
        fromCache: true,
      );

      // ========== 阶段2：分类加载（后台）==========
      // 延迟执行，不阻塞阶段1的显示
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await _loadCategorizedData(silent: true);
    } on Exception catch (e) {
      logger.e('VideoListNotifier: 后台初始化失败', e);
      // 保持空列表状态，让用户可以正常使用界面
    }
  }

  /// 从 SQLite 加载分类数据（高性能，渐进式 UI 渲染）
  ///
  /// [silent] 为 true 时不显示加载状态，避免页面闪烁（用于刮削进度更新）
  /// [forceSync] 为 true 时强制同步聚合表（用于刮削完成后更新海报等数据）
  Future<void> _loadCategorizedData({
    bool silent = false,
    bool forceSync = false,
  }) async {
    // 非静默模式才显示加载状态
    if (!silent) {
      state = VideoListLoading(fromCache: true);
    }

    // 确保数据库已初始化
    try {
      await _db.init();

      // 检查聚合表是否需要同步（首次运行、数据库升级后、或刮削完成后）
      final tvGroupCount = await _db.getTvShowGroupListCount();
      if (tvGroupCount == 0 || forceSync) {
        logger.i(
          'VideoListNotifier: 触发聚合表同步 (tvGroupCount=$tvGroupCount, forceSync=$forceSync)',
        );
        // 使用 fireAndForget 确保同步在后台进行，不阻塞 UI
        await Future.wait([
          _db.syncTvShowGroups(),
          _db.syncMovieCollectionGroups(),
        ]);
        logger.i('VideoListNotifier: 聚合表初始同步完成');
      }
    } on Exception catch (e) {
      logger.e('VideoListNotifier: 数据库初始化失败', e);
      return;
    }

    // 获取启用的路径（用于过滤停用文件夹的视频）
    final enabledPaths = _getEnabledPaths();
    if (enabledPaths != null) {
      logger.d('VideoListNotifier: enabledPaths 数量=${enabledPaths.length}');
      for (final p in enabledPaths) {
        logger.d('  - sourceId="${p.sourceId}", path="${p.path}"');
      }
    } else {
      logger.d('VideoListNotifier: enabledPaths = null (不进行路径过滤)');
    }

    // ============ 第一阶段：统计信息（快速响应） ============
    List<Object?> phase1Results;
    try {
      phase1Results =
          await Future.wait([
            _db.getStats(enabledPaths: enabledPaths),
            _db.getTvShowGroupCount(enabledPaths: enabledPaths),
            _db.getCount(), // 总数用于判断路径过滤
          ]).timeout(
            const Duration(seconds: 3),
            onTimeout: () {
              logger.w('VideoListNotifier: 统计查询超时（3秒）');
              return [
                <String, dynamic>{
                  'total': 0,
                  'movies': 0,
                  'tvShows': 0,
                  'others': 0,
                },
                0,
                0,
              ];
            },
          );
    } on Exception catch (e) {
      logger.e('VideoListNotifier: 统计查询失败', e);
      return;
    }

    final stats =
        (phase1Results[0] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final tvShowGroupCount = (phase1Results[1] as int?) ?? 0;
    final databaseTotalCount = (phase1Results[2] as int?) ?? 0;

    // 检查路径过滤是否需要回退
    final filteredTotal = stats['total'] as int? ?? 0;
    final needFallback =
        filteredTotal == 0 && databaseTotalCount > 0 && enabledPaths != null;
    final effectiveEnabledPaths = needFallback ? null : enabledPaths;

    if (needFallback) {
      logger.w('VideoListNotifier: 路径过滤后无数据，回退到显示所有数据');
      try {
        final fallbackStats = await _db.getStats();
        stats
          ..['total'] = fallbackStats['total']
          ..['movies'] = fallbackStats['movies']
          ..['tvShows'] = fallbackStats['tvShows']
          ..['others'] = fallbackStats['others'];
      } on Exception catch (e) {
        logger.w('VideoListNotifier: 回退统计查询失败', e);
      }
    }

    final newTotalCount = stats['total'] as int? ?? 0;

    // 🚀 渐进式更新：Phase 1 完成，立即显示统计数据和骨架屏
    if (!silent) {
      state = VideoListLoaded(
        totalCount: newTotalCount,
        databaseTotalCount: databaseTotalCount,
        movieCount: stats['movies'] as int? ?? 0,
        tvShowCount: stats['tvShows'] as int? ?? 0,
        tvShowGroupCount: tvShowGroupCount,
        otherCount: stats['others'] as int? ?? 0,
        loadingPhase: VideoLoadingPhase.stats,
        fromCache: true,
      );
      logger.d('VideoListNotifier: Phase 1 完成，显示统计数据');
    }

    // ============ 第二阶段：批次1 - 首屏核心内容 ============
    var topRatedRaw = <VideoMetadata>[];
    var recentRaw = <VideoMetadata>[];
    var moviesList = <VideoMetadata>[];

    try {
      final batch1Stopwatch = Stopwatch()..start();
      // 每日推荐使用基于日期的随机种子，每天推荐不同内容
      final today = DateTime.now();
      final dateSeed = today.year * 10000 + today.month * 100 + today.day;

      final batch1 =
          await Future.wait([
            // 每日推荐使用随机排序，从所有已刮削视频中随机选择
            _db.getTopRated(
              limit: 100,
              enabledPaths: effectiveEnabledPaths,
              includeUnrated: true,
              randomSort: true,
              randomSeed: dateSeed,
            ),
            _db.getRecentlyUpdated(
              limit: 20,
              enabledPaths: effectiveEnabledPaths,
            ),
            _db.getByCategory(
              MediaCategory.movie,
              limit: 30,
              enabledPaths: effectiveEnabledPaths,
            ),
          ]).timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              logger.w('VideoListNotifier: 批次1查询超时（5秒）');
              return [<VideoMetadata>[], <VideoMetadata>[], <VideoMetadata>[]];
            },
          );
      batch1Stopwatch.stop();
      logger.d(
        'VideoListNotifier: 批次1完成，耗时 ${batch1Stopwatch.elapsedMilliseconds}ms',
      );

      topRatedRaw = (batch1[0] as List<VideoMetadata>?) ?? [];
      recentRaw = (batch1[1] as List<VideoMetadata>?) ?? [];
      moviesList = (batch1[2] as List<VideoMetadata>?) ?? [];
    } on Exception catch (e) {
      logger.e('VideoListNotifier: 批次1查询失败', e);
    }

    // 构建电影的快速查找 Map
    final videoByKey = <String, VideoMetadata>{};
    for (final m in moviesList) {
      videoByKey[m.uniqueKey] = m;
    }

    // 临时的每日推荐（仅基于电影，剧集稍后补充）
    final tempDailyRecommendation = _buildDailyRecommendation(
      topRatedRaw,
      {},
      limit: 50,
    );
    // 临时的最近添加（仅基于原始数据，剧集去重稍后补充）
    final tempRecent = _buildRecentWithGroups(recentRaw, {}, limit: 20);

    // 🚀 渐进式更新：Batch 1 完成，显示每日推荐、最近添加、电影
    if (!silent) {
      final batch1State = VideoListLoaded(
        totalCount: newTotalCount,
        databaseTotalCount: databaseTotalCount,
        movieCount: stats['movies'] as int? ?? 0,
        tvShowCount: stats['tvShows'] as int? ?? 0,
        tvShowGroupCount: tvShowGroupCount,
        otherCount: stats['others'] as int? ?? 0,
        loadingPhase: VideoLoadingPhase.batch1,
        topRatedMovies: tempDailyRecommendation,
        recentVideos: tempRecent,
        movies: moviesList,
        videoByKey: videoByKey,
        fromCache: true,
      );
      state = batch1State;
      // 首屏数据就绪，开始预缓存封面图片
      _precacheHomeImages(batch1State);
      logger.d('VideoListNotifier: Batch 1 完成，显示每日推荐/最近添加/电影');
    }

    // ============ 第三阶段：批次2 - 剧集、系列、其他 ============
    var tvShowRepresentatives = <VideoMetadata>[];
    var movieCollections = <MovieCollection>[];
    var othersList = <VideoMetadata>[];

    try {
      final batch2Stopwatch = Stopwatch()..start();
      final batch2 =
          await Future.wait([
            _db.getTvShowGroupRepresentatives(
              limit: 30,
              enabledPaths: effectiveEnabledPaths,
            ),
            _db.getMovieCollections(minCount: 2),
            _db.getByCategory(
              MediaCategory.unknown,
              limit: 30,
              enabledPaths: effectiveEnabledPaths,
            ),
          ]).timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              logger.w('VideoListNotifier: 批次2查询超时（5秒）');
              return [
                <VideoMetadata>[],
                <MovieCollection>[],
                <VideoMetadata>[],
              ];
            },
          );
      batch2Stopwatch.stop();
      logger.d(
        'VideoListNotifier: 批次2完成，耗时 ${batch2Stopwatch.elapsedMilliseconds}ms, '
        'tvShows=${(batch2[0] as List).length}, collections=${(batch2[1] as List).length}, '
        'others=${(batch2[2] as List).length}',
      );

      tvShowRepresentatives = (batch2[0] as List<VideoMetadata>?) ?? [];
      movieCollections = (batch2[1] as List<MovieCollection>?) ?? [];
      othersList = (batch2[2] as List<VideoMetadata>?) ?? [];
    } on Exception catch (e) {
      logger.e('VideoListNotifier: 批次2查询失败', e);
    }

    // 记录查询结果统计
    logger.d(
      'VideoListNotifier: 查询结果 - stats=$stats, '
      'topRated=${topRatedRaw.length}, recent=${recentRaw.length}, '
      'movies=${moviesList.length}, tvShows=${tvShowRepresentatives.length}, '
      'others=${othersList.length}, databaseTotal=$databaseTotalCount',
    );

    // 构建剧集分组
    final tmdbIds = tvShowRepresentatives
        .where((r) => r.tmdbId != null)
        .map((r) => r.tmdbId!)
        .toList();
    final showDirectories = tvShowRepresentatives
        .where((r) => r.tmdbId == null && r.showDirectory != null)
        .map((r) => r.showDirectory!)
        .toList();
    final titles = tvShowRepresentatives
        .where(
          (r) => r.tmdbId == null && r.showDirectory == null && r.title != null,
        )
        .map((r) => r.title!)
        .toList();

    // 批量获取季集统计
    final groupStats = await _db.getTvShowGroupStats(
      tmdbIds: tmdbIds.isNotEmpty ? tmdbIds : null,
      showDirectories: showDirectories.isNotEmpty ? showDirectories : null,
      titles: titles.isNotEmpty ? titles : null,
    );

    final tvShowGroups = <String, TvShowGroup>{};
    for (final rep in tvShowRepresentatives) {
      final groupKey = rep.tmdbId != null
          ? 'tmdb_${rep.tmdbId}'
          : (rep.showDirectory != null
                ? 'dir_${rep.showDirectory}'
                : 'title_${rep.title?.toLowerCase()}');
      final groupStat = groupStats[groupKey];
      tvShowGroups[groupKey] = TvShowGroup(
        groupKey: groupKey,
        title: rep.title ?? rep.fileName,
        tmdbId: rep.tmdbId,
        posterUrl: rep.posterUrl,
        backdropUrl: rep.backdropUrl,
        rating: rep.rating,
        overview: rep.overview,
        year: rep.year,
        genres: rep.genres,
        seasonEpisodes: {
          rep.seasonNumber ?? 1: [rep],
        },
        precomputedSeasonCount: groupStat?.seasonCount ?? 1,
        precomputedEpisodeCount: groupStat?.episodeCount ?? 1,
      );
    }

    // 现在有了完整的剧集分组，重新计算每日推荐和最近添加（包含剧集去重）
    final dailyRecommendation = _buildDailyRecommendation(
      topRatedRaw,
      tvShowGroups,
      limit: 50,
    );
    final recent = _buildRecentWithGroups(recentRaw, tvShowGroups, limit: 20);

    // 更新快速查找 Map
    for (final m in tvShowRepresentatives) {
      videoByKey[m.uniqueKey] = m;
    }
    for (final m in othersList) {
      videoByKey[m.uniqueKey] = m;
    }

    // 同步刮削统计跟踪值
    _lastTotalCount = databaseTotalCount;

    // 保护：在 silent 模式下，如果新查询结果为空但当前状态有数据，保留当前状态
    if (silent) {
      final currentState = state;
      if (currentState is VideoListLoaded &&
          currentState.totalCount > 0 &&
          newTotalCount == 0) {
        logger.w(
          'VideoListNotifier: silent 模式下查询结果为空，但当前状态有 ${currentState.totalCount} 个视频，保留当前状态',
        );
        return;
      }
    }

    // 🚀 渐进式更新：全部完成，显示完整内容
    final completeState = VideoListLoaded(
      totalCount: newTotalCount,
      databaseTotalCount: databaseTotalCount,
      movieCount: stats['movies'] as int? ?? 0,
      tvShowCount: stats['tvShows'] as int? ?? 0,
      tvShowGroupCount: tvShowGroupCount,
      otherCount: stats['others'] as int? ?? 0,
      loadingPhase: VideoLoadingPhase.complete,
      topRatedMovies: dailyRecommendation,
      recentVideos: recent,
      movies: moviesList,
      tvShowGroups: tvShowGroups,
      others: othersList,
      movieCollections: movieCollections,
      videoByKey: videoByKey,
      fromCache: true,
    );
    state = completeState;
    // 完整数据就绪，预缓存剧集和系列封面
    _precacheHomeImages(completeState);

    logger.i('''
      VideoListNotifier: 数据加载完成（渐进式），
      总计 ${stats['total']} 个视频（数据库总数: $databaseTotalCount），
      电影 ${stats['movies']} 个（首页加载 ${moviesList.length}），
      剧集 $tvShowGroupCount 部（首页加载 ${tvShowRepresentatives.length} 部），
      其他 ${stats['others']} 个（首页加载 ${othersList.length}），
      电影系列 ${movieCollections.length} 个，
      每日推荐 ${dailyRecommendation.length} 个，
      最近添加 ${recent.length} 个'
      ''');
  }

  /// 重新加载数据（扫描完成后调用）
  Future<void> reloadFromCache() async {
    await _loadCategorizedData();
  }

  void setTab(VideoTab tab) {
    final current = state;
    if (current is VideoListLoaded) {
      state = current.copyWith(currentTab: tab);
    }
  }

  void setSearchQuery(String query) {
    final current = state;
    if (current is VideoListLoaded) {
      if (query.isEmpty) {
        state = current.copyWith(searchQuery: '', searchResults: []);
      } else {
        // 使用 SQLite 搜索（带索引）
        _performSearch(query, current);
      }
    }
  }

  /// 执行搜索（使用 SQLite LIKE 查询）
  Future<void> _performSearch(String query, VideoListLoaded current) async {
    state = current.copyWith(searchQuery: query, isLoadingMetadata: true);

    final results = await _db.search(query, limit: 100);

    final newState = state;
    if (newState is VideoListLoaded && newState.searchQuery == query) {
      state = newState.copyWith(
        searchResults: results,
        isLoadingMetadata: false,
      );
    }
  }

  /// 构建每日推荐列表
  ///
  /// 特点：
  /// - 基于当天日期的随机种子，每天推荐不同内容
  /// - 剧集使用 TvShowGroup 的完整信息（避免展示多集）
  /// - 电影和剧集都会进行去重
  /// - 同一电影的多个版本会合并，选择最高清晰度版本
  List<VideoMetadata> _buildDailyRecommendation(
    List<VideoMetadata> videos,
    Map<String, TvShowGroup> tvShowGroups, {
    int limit = 20,
  }) {
    final seenTvShows = <String>{};
    // 电影按 key 存储最佳版本（最高清晰度）
    final movieBestVersions = <String, VideoMetadata>{};
    final tvShowResults = <VideoMetadata>[];

    for (final video in videos) {
      // 电影：选择最高清晰度版本
      if (video.category == MediaCategory.movie) {
        final movieKey = video.tmdbId != null
            ? 'tmdb_${video.tmdbId}'
            : video.uniqueKey;

        final existing = movieBestVersions[movieKey];
        if (existing == null || _compareResolution(video, existing) > 0) {
          movieBestVersions[movieKey] = video;
        }
        continue;
      }

      // 剧集需要去重并使用分组信息
      final groupKey = _getTvShowGroupKey(video);
      if (seenTvShows.contains(groupKey)) {
        continue;
      }
      seenTvShows.add(groupKey);

      // 使用 TvShowGroup 的信息构建代表元数据
      final group = tvShowGroups[groupKey];
      if (group != null) {
        tvShowResults.add(_buildGroupRepresentative(group));
      } else {
        tvShowResults.add(video);
      }
    }

    // 合并电影和剧集
    final allResults = <VideoMetadata>[
      ...movieBestVersions.values,
      ...tvShowResults,
    ];

    // 使用基于日期的随机种子进行打乱
    // 这样每天推荐的内容不同，但同一天内保持一致
    final today = DateTime.now();
    final dateSeed = today.year * 10000 + today.month * 100 + today.day;
    final random = Random(dateSeed);
    allResults.shuffle(random);

    return allResults.take(limit).toList();
  }

  /// 构建最近添加列表，剧集使用 TvShowGroup 的完整信息
  /// 电影和剧集都会进行去重，避免重复显示
  /// 同一电影的多个版本会合并，选择最高清晰度版本
  /// 剧集保留最新添加那集的时间信息用于排序
  List<VideoMetadata> _buildRecentWithGroups(
    List<VideoMetadata> videos,
    Map<String, TvShowGroup> tvShowGroups, {
    int limit = 20,
  }) {
    // 电影按 key 存储最佳版本（最高清晰度）
    final movieBestVersions = <String, VideoMetadata>{};
    // 剧集按 groupKey 存储：TvShowGroup 信息 + 最新添加那集的时间
    final tvShowBestVersions = <String, VideoMetadata>{};

    for (final video in videos) {
      // 电影：选择最高清晰度版本
      if (video.category == MediaCategory.movie) {
        final movieKey = video.tmdbId != null
            ? 'tmdb_${video.tmdbId}'
            : video.uniqueKey;

        final existing = movieBestVersions[movieKey];
        if (existing == null || _compareResolution(video, existing) > 0) {
          movieBestVersions[movieKey] = video;
        }
        continue;
      }

      // 剧集：去重，但保留最新添加那集的时间用于排序
      final groupKey = _getTvShowGroupKey(video);
      final existing = tvShowBestVersions[groupKey];

      // 如果还没有记录，或者当前这集更新，则更新记录
      if (existing == null) {
        // 使用 TvShowGroup 的信息，但保留当前 video 的 fileModifiedTime
        final group = tvShowGroups[groupKey];
        if (group != null) {
          tvShowBestVersions[groupKey] = _buildGroupRepresentativeWithTime(
            group,
            video.fileModifiedTime,
          );
        } else {
          tvShowBestVersions[groupKey] = video;
        }
      } else {
        // 比较文件修改时间，保留更新的
        final existingTime = existing.fileModifiedTime ?? DateTime(1970);
        final currentTime = video.fileModifiedTime ?? DateTime(1970);
        if (currentTime.isAfter(existingTime)) {
          final group = tvShowGroups[groupKey];
          if (group != null) {
            tvShowBestVersions[groupKey] = _buildGroupRepresentativeWithTime(
              group,
              video.fileModifiedTime,
            );
          } else {
            tvShowBestVersions[groupKey] = video;
          }
        }
      }
    }

    // 合并电影和剧集，按文件修改时间排序（最近添加）
    final allResults =
        <VideoMetadata>[
          ...movieBestVersions.values,
          ...tvShowBestVersions.values,
        ]..sort((a, b) {
          final timeA = a.fileModifiedTime ?? DateTime(1970);
          final timeB = b.fileModifiedTime ?? DateTime(1970);
          return timeB.compareTo(timeA);
        });

    return allResults.take(limit).toList();
  }

  /// 比较两个视频的分辨率
  ///
  /// 返回正数表示 a 的分辨率更高，负数表示 b 更高，0 表示相同
  int _compareResolution(VideoMetadata a, VideoMetadata b) {
    const resolutionOrder = <String, int>{
      '4K': 100,
      '2160P': 100,
      '2160p': 100,
      '1080P': 80,
      '1080p': 80,
      '720P': 60,
      '720p': 60,
      '480P': 40,
      '480p': 40,
    };

    final orderA = resolutionOrder[a.resolution] ?? 0;
    final orderB = resolutionOrder[b.resolution] ?? 0;

    if (orderA != orderB) {
      return orderA - orderB;
    }

    // 分辨率相同时，选择文件更大的（通常码率更高）
    final sizeA = a.fileSize ?? 0;
    final sizeB = b.fileSize ?? 0;
    return sizeA.compareTo(sizeB);
  }

  /// 从 TvShowGroup 构建代表性的 VideoMetadata
  /// 使用分组的标题、海报、评分等信息
  VideoMetadata _buildGroupRepresentative(TvShowGroup group) {
    final rep = group.representative;
    return VideoMetadata(
      sourceId: rep.sourceId,
      filePath: rep.filePath,
      fileName: rep.fileName,
      category: MediaCategory.tvShow,
      scrapeStatus: rep.scrapeStatus,
      tmdbId: group.tmdbId ?? rep.tmdbId,
      title: group.title, // 使用分组标题
      originalTitle: rep.originalTitle,
      year: group.year ?? rep.year,
      overview: group.overview ?? rep.overview, // 使用分组简介
      posterUrl: group.displayPosterUrl, // 使用分组海报
      backdropUrl: group.backdropUrl ?? rep.backdropUrl,
      rating: group.rating ?? rep.rating, // 使用分组评分
      runtime: rep.runtime,
      genres: group.genres ?? rep.genres,
      director: rep.director,
      cast: rep.cast,
      seasonNumber: rep.seasonNumber,
      episodeNumber: rep.episodeNumber,
      episodeTitle: rep.episodeTitle,
      lastUpdated: rep.lastUpdated,
      thumbnailUrl: rep.thumbnailUrl,
      generatedThumbnailUrl: rep.generatedThumbnailUrl,
      fileSize: rep.fileSize,
      fileModifiedTime: rep.fileModifiedTime,
    );
  }

  /// 从 TvShowGroup 构建代表性的 VideoMetadata，但使用指定的 fileModifiedTime
  /// 用于最近添加列表，保留最新添加那集的时间用于排序
  VideoMetadata _buildGroupRepresentativeWithTime(
    TvShowGroup group,
    DateTime? fileModifiedTime,
  ) {
    final rep = group.representative;
    return VideoMetadata(
      sourceId: rep.sourceId,
      filePath: rep.filePath,
      fileName: rep.fileName,
      category: MediaCategory.tvShow,
      scrapeStatus: rep.scrapeStatus,
      tmdbId: group.tmdbId ?? rep.tmdbId,
      title: group.title,
      originalTitle: rep.originalTitle,
      year: group.year ?? rep.year,
      overview: group.overview ?? rep.overview,
      posterUrl: group.displayPosterUrl,
      backdropUrl: group.backdropUrl ?? rep.backdropUrl,
      rating: group.rating ?? rep.rating,
      runtime: rep.runtime,
      genres: group.genres ?? rep.genres,
      director: rep.director,
      cast: rep.cast,
      seasonNumber: rep.seasonNumber,
      episodeNumber: rep.episodeNumber,
      episodeTitle: rep.episodeTitle,
      lastUpdated: rep.lastUpdated,
      thumbnailUrl: rep.thumbnailUrl,
      generatedThumbnailUrl: rep.generatedThumbnailUrl,
      fileSize: rep.fileSize,
      fileModifiedTime: fileModifiedTime ?? rep.fileModifiedTime, // 使用传入的时间
    );
  }

  /// 获取剧集的分组键
  /// 与 tvShowGroups 的键生成逻辑保持一致
  String _getTvShowGroupKey(VideoMetadata video) {
    // 优先使用 tmdbId
    if (video.tmdbId != null) {
      return 'tmdb_${video.tmdbId}';
    }
    // 其次使用 showDirectory
    if (video.showDirectory != null) {
      return 'dir_${video.showDirectory}';
    }
    // 最后使用标题
    return 'title_${video.title?.toLowerCase() ?? video.fileName.toLowerCase()}';
  }

  /// 从媒体库移除视频（只删除数据库记录，不删除源文件）
  Future<bool> removeFromLibrary(VideoMetadata video) async {
    try {
      await _db.delete(video.sourceId, video.filePath);
      await _loadCategorizedData(silent: true);
      logger.i('VideoListNotifier: 已从媒体库移除 ${video.displayTitle}');
      return true;
    } on Exception catch (e) {
      logger.e('VideoListNotifier: 移除视频失败', e);
      return false;
    }
  }

  /// 删除视频源文件（同时删除数据库记录和源文件）
  Future<bool> deleteFromSource(VideoMetadata video) async {
    try {
      // 获取连接
      final connections = _ref.read(activeConnectionsProvider);
      final connection = connections[video.sourceId];
      if (connection == null || connection.status != SourceStatus.connected) {
        logger.w('VideoListNotifier: 无法删除，源未连接');
        return false;
      }

      // 删除源文件
      await connection.adapter.fileSystem.delete(video.filePath);

      // 删除数据库记录
      await _db.delete(video.sourceId, video.filePath);

      // 刷新列表
      await _loadCategorizedData(silent: true);

      logger.i('VideoListNotifier: 已删除源文件 ${video.displayTitle}');
      return true;
    } on Exception catch (e) {
      logger.e('VideoListNotifier: 删除视频源文件失败', e);
      return false;
    }
  }
}

class VideoListPage extends ConsumerStatefulWidget {
  const VideoListPage({super.key});

  @override
  ConsumerState<VideoListPage> createState() => _VideoListPageState();
}

class _VideoListPageState extends ConsumerState<VideoListPage> {
  final _searchController = TextEditingController();
  bool _showSearch = false;

  // 刮削进度状态
  StreamSubscription<ScrapeStats>? _scrapeSubscription;
  ScrapeStats? _scrapeStats;
  bool _showScrapeDetails = false;

  // 精选推荐随机 seed（每次打开 app 随机变化）
  late final int _heroBannerSeed;

  @override
  void initState() {
    super.initState();
    _heroBannerSeed = DateTime.now().millisecondsSinceEpoch;
    _initScrapeListener();
  }

  /// 随机选择精选推荐项目（优先选择有背景图的）
  List<VideoMetadata> _selectRandomHeroItems(
    List<VideoMetadata> candidates,
    int count,
  ) {
    if (candidates.isEmpty) return [];
    if (candidates.length <= count) return candidates;

    // 优先选择有背景图的视频
    final withBackdrop = candidates
        .where((v) => v.backdropUrl != null && v.backdropUrl!.isNotEmpty)
        .toList();
    final withoutBackdrop = candidates
        .where((v) => v.backdropUrl == null || v.backdropUrl!.isEmpty)
        .toList();

    // 使用固定 seed 的随机数生成器，确保同一会话内一致
    final random = Random(_heroBannerSeed);

    final result = <VideoMetadata>[];

    // 先从有背景图的中随机选择
    if (withBackdrop.isNotEmpty) {
      final shuffled = List<VideoMetadata>.from(withBackdrop)..shuffle(random);
      result.addAll(shuffled.take(count));
    }

    // 如果不够，从没有背景图的中补充
    if (result.length < count && withoutBackdrop.isNotEmpty) {
      final shuffled = List<VideoMetadata>.from(withoutBackdrop)
        ..shuffle(random);
      result.addAll(shuffled.take(count - result.length));
    }

    return result;
  }

  void _initScrapeListener() {
    _scrapeSubscription = VideoScannerService().scrapeStatsStream.listen((
      stats,
    ) {
      if (mounted) {
        setState(() => _scrapeStats = stats);
      }
    });

    // 初始检查刮削状态
    _checkInitialScrapeState();
  }

  Future<void> _checkInitialScrapeState() async {
    if (VideoScannerService().isScraping) {
      final stats = await VideoScannerService().getScrapeStats();
      if (mounted) {
        setState(() => _scrapeStats = stats);
      }
    }
  }

  @override
  void dispose() {
    _scrapeSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// 获取问候语
  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 6) return '夜深了';
    if (hour < 12) return '早上好';
    if (hour < 14) return '中午好';
    if (hour < 18) return '下午好';
    return '晚上好';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(videoListProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final uiStyle = ref.watch(uiStyleProvider);
    final safeTop = MediaQuery.of(context).padding.top;
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    // iOS 26 Liquid Glass 风格：悬浮布局
    if (uiStyle.isGlass) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF0D0D0D) : Colors.grey[50],
        body: Stack(
          children: [
            // 主内容（包含大标题）
            switch (state) {
              VideoListLoading(
                :final progress,
                :final currentFolder,
                :final fromCache,
                :final partialVideos,
                :final scannedCount,
              ) =>
                _buildLoadingState(
                  context,
                  ref,
                  progress,
                  currentFolder,
                  fromCache,
                  partialVideos,
                  scannedCount,
                  isDark,
                ),
              VideoListError(:final message) => AppErrorWidget(
                message: message,
                onRetry: () =>
                    ref.read(videoListProvider.notifier).reloadFromCache(),
              ),
              final VideoListLoaded loaded =>
                loaded.totalCount == 0
                    ? _buildEmptyOrFilteredState(context, ref, loaded, isDark)
                    : _buildVideoContentWithLargeTitle(context, ref, loaded, isDark, safeTop),
            },
            if (_showSearch)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => setState(() => _showSearch = false),
                ),
              ),
            // 悬浮按钮组（右上角）
            AnimatedPositioned(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              top: _showSearch ? null : safeTop + 8,
              right: 16,
              bottom: _showSearch ? (keyboardInset > 0 ? keyboardInset + 16 : bottomPadding + 16) : null,
              child: _showSearch
                  ? _buildFloatingSearchBar(context, ref, isDark)
                  : _buildFloatingButtons(context, ref, isDark, state),
            ),
          ],
        ),
      );
    }

    // 经典模式：传统布局
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D0D0D) : Colors.grey[50],
      body: Column(
        children: [
          _buildHeader(context, ref, isDark, state),
          Expanded(
            child: switch (state) {
              VideoListLoading(
                :final progress,
                :final currentFolder,
                :final fromCache,
                :final partialVideos,
                :final scannedCount,
              ) =>
                _buildLoadingState(
                  context,
                  ref,
                  progress,
                  currentFolder,
                  fromCache,
                  partialVideos,
                  scannedCount,
                  isDark,
                ),
              VideoListError(:final message) => AppErrorWidget(
                message: message,
                onRetry: () =>
                    ref.read(videoListProvider.notifier).reloadFromCache(),
              ),
              final VideoListLoaded loaded =>
                loaded.totalCount == 0
                    ? _buildEmptyOrFilteredState(context, ref, loaded, isDark)
                    : _buildVideoContent(context, ref, loaded, isDark),
            },
          ),
        ],
      ),
    );
  }

  /// iOS 26 悬浮按钮组
  Widget _buildFloatingButtons(
    BuildContext context,
    WidgetRef ref,
    bool isDark,
    VideoListState state,
  ) {
    return GlassButtonGroup(
      children: [
        GlassGroupIconButton(
          icon: Icons.search_rounded,
          onPressed: () => setState(() => _showSearch = true),
          tooltip: '搜索',
        ),
        GlassGroupIconButton(
          icon: Icons.tune_rounded,
          onPressed: () => VideoCategorySettingsSheet.show(context),
          tooltip: '分类设置',
        ),
        GlassGroupPopupMenuButton<String>(
          icon: Icons.more_vert_rounded,
          tooltip: '更多',
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'library',
              child: Row(
                children: const [
                  Icon(Icons.settings_rounded, size: 20),
                  SizedBox(width: 12),
                  Text('媒体库设置'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'sources',
              child: Row(
                children: const [
                  Icon(Icons.cloud_rounded, size: 20),
                  SizedBox(width: 12),
                  Text('连接源管理'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'duplicates',
              child: Row(
                children: const [
                  Icon(Icons.content_copy_rounded, size: 20),
                  SizedBox(width: 12),
                  Text('查找重复'),
                ],
              ),
            ),
          ],
          onSelected: _handleMenuSelection,
        ),
      ],
    );
  }

  /// 处理菜单选择
  void _handleMenuSelection(String value) {
    if (!mounted) return;
    switch (value) {
      case 'library':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => const MediaLibraryPage(),
          ),
        );
      case 'sources':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => const SourcesPage(),
          ),
        );
      case 'duplicates':
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => const VideoDuplicatesPage(),
          ),
        );
    }
  }

  /// iOS 26 悬浮搜索栏
  Widget _buildFloatingSearchBar(
    BuildContext context,
    WidgetRef ref,
    bool isDark,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    // Reserve space for close button (~48px) and side padding/gap
    final available = screenWidth - 96; // padding + gap + close button
    final searchWidth = available.clamp(220.0, 480.0);

    return GlassFloatingSearchBar(
      controller: _searchController,
      hintText: '搜索视频...',
      width: searchWidth,
      onChanged: (query) {
        ref.read(videoListProvider.notifier).setSearchQuery(query);
      },
      onClose: () {
        setState(() => _showSearch = false);
      },
    );
  }

  /// iOS 26 带大标题的视频内容
  Widget _buildVideoContentWithLargeTitle(
    BuildContext context,
    WidgetRef ref,
    VideoListLoaded state,
    bool isDark,
    double safeTop,
  ) {
    // 如果有搜索，显示搜索结果
    if (state.searchQuery.isNotEmpty) {
      return _buildSearchResults(context, ref, state, isDark);
    }

    // 获取分类设置
    final categorySettings = ref.watch(videoCategorySettingsProvider);
    final visibleSections = categorySettings.visibleSections;

    // 判断设备类型
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 800;

    // 预加载数据
    final recentVideos = _getRecentVideos(state, limit: 10);
    final allRecentVideos = _getRecentVideos(state);
    final movies = state.movies;
    final tvShowGroups = state.tvShowGroupList;
    final movieCollections = state.movieCollections;
    final topRated = state.topRatedMovies;

    // 构建分类 slivers
    final slivers = _buildCategorySlivers(
      context: context,
      ref: ref,
      visibleSections: visibleSections,
      state: state,
      isDark: isDark,
      isDesktop: isDesktop,
      recentVideos: recentVideos,
      allRecentVideos: allRecentVideos,
      movies: movies,
      tvShowGroups: tvShowGroups,
      movieCollections: movieCollections,
      topRated: topRated,
      categorySettings: categorySettings,
    );

    return CustomScrollView(
      slivers: [
        // 顶部安全区域留白
        SliverPadding(padding: EdgeInsets.only(top: safeTop + 8)),
        // 大标题区域（iOS 26 风格）- 右侧留出浮动按钮空间
        _buildLargeTitleSliver(context, state, isDark, hasFloatingButtons: true),
        // 内容
        ...slivers,
        // 底部留白
        SliverPadding(padding: EdgeInsets.only(bottom: context.scrollBottomPadding)),
      ],
    );
  }

  /// iOS 26 大标题 Sliver
  Widget _buildLargeTitleSliver(
    BuildContext context,
    VideoListLoaded state,
    bool isDark, {
    bool hasFloatingButtons = false,
  }) {
    final movieCount = state.movieCount;
    final tvShowCount = state.tvShowGroupCount;
    final otherCount = state.otherCount;

    // 判断是否正在刮削
    final isScraping =
        _scrapeStats != null &&
        !_scrapeStats!.isAllDone &&
        _scrapeStats!.total > 0;

    // 右侧留出浮动按钮空间（按钮组宽度约 140px + 16px 右边距 + 一些额外空间）
    final rightPadding = hasFloatingButtons ? 170.0 : 20.0;

    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 8, rightPadding, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 大标题
            Text(
              _getGreeting(),
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            // 统计信息
            if (state.totalCount > 0 || isScraping)
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _buildStatChip(
                    icon: Icons.movie_filter_rounded,
                    label: '$movieCount 电影',
                    color: AppColors.primary,
                    isDark: isDark,
                  ),
                  _buildStatChip(
                    icon: Icons.tv_rounded,
                    label: '$tvShowCount 剧集',
                    color: AppColors.accent,
                    isDark: isDark,
                  ),
                  if (otherCount > 0)
                    _buildStatChip(
                      icon: Icons.folder_special_rounded,
                      label: '$otherCount 其他',
                      color: Colors.grey,
                      isDark: isDark,
                    ),
                  if (isScraping) _buildScrapeProgressChip(isDark),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// 构建顶部区域（类似音乐模块的设计）
  Widget _buildHeader(
    BuildContext context,
    WidgetRef ref,
    bool isDark,
    VideoListState state,
  ) {
    final uiStyle = ref.watch(uiStyleProvider);

    // 玻璃模式下的染色
    final tintColor = uiStyle.isGlass
        ? (isDark
            ? AppColors.primary.withValues(alpha: 0.15)
            : AppColors.primary.withValues(alpha: 0.08))
        : null;

    return AdaptiveGlassHeader(
      height: 72,
      backgroundColor: uiStyle.isGlass
          ? tintColor
          : (isDark
              ? const Color(0xFF1A1A2E) // 深蓝紫色调
              : AppColors.primary.withValues(alpha: 0.08)),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.appBarHorizontalPadding,
          AppSpacing.appBarVerticalPadding,
          AppSpacing.appBarHorizontalPadding,
          AppSpacing.lg,
        ),
        child: _showSearch
            ? _buildSearchBar(context, ref, isDark)
            : _buildGreetingHeader(context, ref, isDark, state),
      ),
    );
  }

  /// 问候语头部
  Widget _buildGreetingHeader(
    BuildContext context,
    WidgetRef ref,
    bool isDark,
    VideoListState state,
  ) {
    final videoCount = state is VideoListLoaded ? state.totalCount : 0;
    final movieCount = state is VideoListLoaded ? state.movieCount : 0;
    final tvShowCount = state is VideoListLoaded ? state.tvShowGroupCount : 0;
    final otherCount = state is VideoListLoaded ? state.otherCount : 0;

    // 判断是否正在刮削
    final isScraping =
        _scrapeStats != null &&
        !_scrapeStats!.isAllDone &&
        _scrapeStats!.total > 0;

    return Row(
      children: [
        Expanded(
          // 使用 Expanded 确保左侧内容填满可用空间，按钮自动靠右
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _getGreeting(),
                style: context.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              if (videoCount > 0 || isScraping)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildStatChip(
                        icon: Icons.movie_filter_rounded,
                        label: '$movieCount 电影',
                        color: AppColors.primary,
                        isDark: isDark,
                      ),
                      const SizedBox(width: 12),
                      _buildStatChip(
                        icon: Icons.tv_rounded,
                        label: '$tvShowCount 剧集',
                        color: AppColors.accent,
                        isDark: isDark,
                      ),
                      // 其他视频
                      if (otherCount > 0) ...[
                        const SizedBox(width: 12),
                        _buildStatChip(
                          icon: Icons.folder_special_rounded,
                          label: '$otherCount 其他',
                          color: Colors.grey,
                          isDark: isDark,
                        ),
                      ],
                      // 刮削进度指示器
                      if (isScraping) ...[
                        const SizedBox(width: 12),
                        _buildScrapeProgressChip(isDark),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
        // 操作按钮 - iOS 26 玻璃风格下使用浮动按钮组
        GlassButtonGroup(
          children: [
            GlassGroupIconButton(
              icon: Icons.search_rounded,
              onPressed: () => setState(() => _showSearch = true),
              tooltip: '搜索',
            ),
            GlassGroupIconButton(
              icon: Icons.tune_rounded,
              onPressed: () => VideoCategorySettingsSheet.show(context),
              tooltip: '分类设置',
            ),
            GlassGroupPopupMenuButton<String>(
              icon: Icons.more_vert_rounded,
              tooltip: '更多',
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'library',
                  child: Row(
                    children: const [
                      Icon(Icons.settings_rounded, size: 20),
                      SizedBox(width: 12),
                      Text('媒体库设置'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'sources',
                  child: Row(
                    children: const [
                      Icon(Icons.cloud_rounded, size: 20),
                      SizedBox(width: 12),
                      Text('连接源管理'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'duplicates',
                  child: Row(
                    children: const [
                      Icon(Icons.content_copy_rounded, size: 20),
                      SizedBox(width: 12),
                      Text('查找重复'),
                    ],
                  ),
                ),
              ],
              onSelected: _handleMenuSelection,
            ),
          ],
        ),
      ],
    );
  }

  /// 刮削进度标签
  Widget _buildScrapeProgressChip(bool isDark) {
    final stats = _scrapeStats!;
    final progress = stats.progress;
    final percentage = (progress * 100).toInt();

    return GestureDetector(
      onTap: () => setState(() => _showScrapeDetails = !_showScrapeDetails),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: _showScrapeDetails
            ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
            : EdgeInsets.zero,
        decoration: _showScrapeDetails
            ? BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              )
            : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 2,
                backgroundColor: isDark
                    ? AppColors.darkOutline
                    : AppColors.lightOutline,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AppColors.warning,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              _showScrapeDetails
                  ? '${stats.processed}/${stats.total}'
                  : '$percentage%',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.warning,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 搜索栏
  Widget _buildSearchBar(BuildContext context, WidgetRef ref, bool isDark) =>
      Row(
        children: [
          IconButton(
            onPressed: () {
              setState(() => _showSearch = false);
              _searchController.clear();
              ref.read(videoListProvider.notifier).setSearchQuery('');
            },
            icon: Icon(
              Icons.arrow_back,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          Expanded(
            child: TextField(
              controller: _searchController,
              autofocus: true,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                hintText: '搜索电影、剧集...',
                hintStyle: TextStyle(
                  color: isDark ? Colors.grey[500] : Colors.grey[400],
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onChanged: (v) =>
                  ref.read(videoListProvider.notifier).setSearchQuery(v),
            ),
          ),
          if (_searchController.text.isNotEmpty)
            IconButton(
              onPressed: () {
                _searchController.clear();
                ref.read(videoListProvider.notifier).setSearchQuery('');
              },
              icon: Icon(
                Icons.close,
                color: isDark
                    ? AppColors.darkOnSurfaceVariant
                    : AppColors.lightOnSurfaceVariant,
              ),
            ),
        ],
      );

  /// 统计标签
  Widget _buildStatChip({
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
  }) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 4),
      Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: isDark
              ? AppColors.darkOnSurfaceVariant
              : AppColors.lightOnSurfaceVariant,
        ),
      ),
    ],
  );

  Widget _buildLoadingState(
    BuildContext context,
    WidgetRef ref,
    double progress,
    String? currentFolder,
    bool fromCache,
    List<VideoFileWithSource> partialVideos,
    int scannedCount,
    bool isDark,
  ) {
    // 如果有部分结果，显示带进度条的网格视图
    if (partialVideos.isNotEmpty && !fromCache) {
      return Column(
        children: [
          // 扫描进度条
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkBackground : AppColors.lightSurface,
              border: Border(
                bottom: BorderSide(
                  color: isDark
                      ? AppColors.darkOutline
                      : AppColors.lightOutline,
                ),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: progress > 0 ? progress : null,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '正在扫描... 已找到 $scannedCount 个视频',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      if (currentFolder != null)
                        Text(
                          currentFolder,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.grey[500] : Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                if (progress > 0)
                  Text(
                    '${(progress * 100).toInt()}%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
              ],
            ),
          ),
          // 部分结果网格
          Expanded(
            child: _buildPartialResultsGrid(
              context,
              ref,
              partialVideos,
              isDark,
            ),
          ),
        ],
      );
    }

    // 没有部分结果时显示加载中心动画
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 60,
            height: 60,
            child: CircularProgressIndicator(
              value: progress > 0 ? progress : null,
              strokeWidth: 4,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            fromCache ? '加载缓存...' : '扫描视频中...',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white : null,
            ),
          ),
          if (currentFolder != null) ...[
            const SizedBox(height: 8),
            Text(
              currentFolder,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.grey[400] : Colors.grey,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPartialResultsGrid(
    BuildContext context,
    WidgetRef ref,
    List<VideoFileWithSource> videos,
    bool isDark,
  ) {
    final gridConfig = GridHelper.getVideoThumbnailGridConfig(context);

    return GridView.builder(
      padding: gridConfig.padding,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: gridConfig.crossAxisCount,
        childAspectRatio: gridConfig.childAspectRatio,
        mainAxisSpacing: gridConfig.mainAxisSpacing,
        crossAxisSpacing: gridConfig.crossAxisSpacing,
      ),
      itemCount: videos.length,
      itemBuilder: (context, index) {
        final video = videos[index];
        return _PartialVideoCard(video: video, isDark: isDark);
      },
    );
  }

  /// 根据数据库实际数据量决定显示空状态还是被过滤提示
  Widget _buildEmptyOrFilteredState(
    BuildContext context,
    WidgetRef ref,
    VideoListLoaded state,
    bool isDark,
  ) {
    // 如果数据库有数据但当前显示为空，说明数据被路径过滤了
    if (state.databaseTotalCount > 0) {
      return _buildFilteredEmptyState(context, ref, state, isDark);
    }
    return _buildEmptyState(context, ref, state, isDark);
  }

  /// 数据被路径过滤后的空状态（数据库有数据但当前媒体库配置没有匹配）
  Widget _buildFilteredEmptyState(
    BuildContext context,
    WidgetRef ref,
    VideoListLoaded state,
    bool isDark,
  ) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.filter_list_off_rounded,
              size: 50,
              color: AppColors.warning,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '媒体库路径未匹配',
            style: context.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : null,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '数据库中有 ${state.databaseTotalCount} 个影视，但当前媒体库配置的路径没有匹配到这些数据。',
            style: context.textTheme.bodyMedium?.copyWith(
              color: isDark ? Colors.grey[400] : Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            '请检查媒体库设置中的目录配置是否正确。',
            style: context.textTheme.bodySmall?.copyWith(
              color: isDark ? Colors.grey[500] : Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const MediaLibraryPage()),
            ),
            icon: const Icon(Icons.folder_open_rounded),
            label: const Text('媒体库设置'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildEmptyState(
    BuildContext context,
    WidgetRef ref,
    VideoListLoaded state,
    bool isDark,
  ) =>
      // 使用 FutureBuilder 异步获取数据库统计信息
      FutureBuilder<String>(
        future: VideoDatabaseService().getStatsInfo(),
        builder: (context, snapshot) {
          final cacheInfo = snapshot.data ?? '加载中...';
          return _buildEmptyStateContent(context, ref, isDark, cacheInfo);
        },
      );

  Widget _buildEmptyStateContent(
    BuildContext context,
    WidgetRef ref,
    bool isDark,
    String cacheInfo,
  ) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.video_library_rounded,
              size: 50,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '视频库为空',
            style: context.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : null,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '请在媒体库设置中配置视频目录并扫描',
            style: context.textTheme.bodyMedium?.copyWith(
              color: isDark ? Colors.grey[400] : Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          // 缓存信息
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkSurfaceVariant
                  : AppColors.lightSurfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.storage_rounded,
                  size: 14,
                  color: isDark
                      ? AppColors.darkOnSurfaceVariant
                      : AppColors.lightOnSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  cacheInfo,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? AppColors.darkOnSurfaceVariant
                        : AppColors.lightOnSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const MediaLibraryPage()),
            ),
            icon: const Icon(Icons.folder_open_rounded),
            label: const Text('媒体库设置'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            ),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const SourcesPage()),
            ),
            icon: const Icon(Icons.cloud_rounded),
            label: const Text('连接管理'),
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
          ),
        ],
      ),
    ),
  );

  Widget _buildVideoContent(
    BuildContext context,
    WidgetRef ref,
    VideoListLoaded state,
    bool isDark,
  ) {
    // 如果有搜索，显示搜索结果
    if (state.searchQuery.isNotEmpty) {
      return _buildSearchResults(context, ref, state, isDark);
    }

    // 获取分类设置
    final categorySettings = ref.watch(videoCategorySettingsProvider);
    final visibleSections = categorySettings.visibleSections;

    // 判断设备类型
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 800;

    // 预加载数据（首屏显示更多最近添加）
    final recentVideos = _getRecentVideos(state, limit: 10);
    final allRecentVideos = _getRecentVideos(state);
    final movies = state.movies;
    final tvShowGroups = state.tvShowGroupList;
    final movieCollections = state.movieCollections;
    final topRated = state.topRatedMovies;

    // 构建分类 slivers
    final slivers = _buildCategorySlivers(
      context: context,
      ref: ref,
      visibleSections: visibleSections,
      state: state,
      isDark: isDark,
      isDesktop: isDesktop,
      recentVideos: recentVideos,
      allRecentVideos: allRecentVideos,
      movies: movies,
      tvShowGroups: tvShowGroups,
      movieCollections: movieCollections,
      topRated: topRated,
      categorySettings: categorySettings,
    );

    return CustomScrollView(
      slivers: [
        ...slivers,
        // 底部留白 - 使用动态 padding 支持悬浮导航栏
        SliverPadding(padding: EdgeInsets.only(bottom: context.scrollBottomPadding)),
      ],
    );
  }

  /// 构建所有分类 Slivers
  /// - browse 分类：显示为卡片行，只包含用户选择的筛选条件
  /// - 动态分类：不显示为独立行（其筛选条件用于 browse 分类的卡片）
  List<Widget> _buildCategorySlivers({
    required BuildContext context,
    required WidgetRef ref,
    required List<VideoCategorySectionConfig> visibleSections,
    required VideoListLoaded state,
    required bool isDark,
    required bool isDesktop,
    required List<VideoMetadata> recentVideos,
    required List<VideoMetadata> allRecentVideos,
    required List<VideoMetadata> movies,
    required List<TvShowGroup> tvShowGroups,
    required List<MovieCollection> movieCollections,
    required List<VideoMetadata> topRated,
    required VideoCategorySettings categorySettings,
  }) {
    final slivers = <Widget>[];

    for (final section in visibleSections) {
      // 跳过动态分类（它们的筛选条件用于 browse 分类的卡片，不单独显示）
      if (section.category.isDynamic) {
        continue;
      }

      // 构建该分类的 sliver
      slivers.addAll(
        _buildCategorySliver(
          context: context,
          ref: ref,
          section: section,
          state: state,
          isDark: isDark,
          isDesktop: isDesktop,
          recentVideos: recentVideos,
          allRecentVideos: allRecentVideos,
          movies: movies,
          tvShowGroups: tvShowGroups,
          movieCollections: movieCollections,
          topRated: topRated,
          categorySettings: categorySettings,
        ),
      );
    }

    return slivers;
  }

  /// 根据分类配置构建对应的 Sliver
  List<Widget> _buildCategorySliver({
    required BuildContext context,
    required WidgetRef ref,
    required VideoCategorySectionConfig section,
    required VideoListLoaded state,
    required bool isDark,
    required bool isDesktop,
    required List<VideoMetadata> recentVideos,
    required List<VideoMetadata> allRecentVideos,
    required List<VideoMetadata> movies,
    required List<TvShowGroup> tvShowGroups,
    required List<MovieCollection> movieCollections,
    required List<VideoMetadata> topRated,
    required VideoCategorySettings categorySettings,
  }) {
    // 获取启用的路径列表（用于分类查询过滤）
    List<({String sourceId, String path})>? enabledPaths;
    final configState = ref.read(mediaLibraryConfigProvider);
    if (!configState.isLoading && !configState.hasError) {
      final config = configState.valueOrNull;
      if (config != null) {
        final paths = config.getEnabledPathsForType(MediaType.video);
        if (paths.isNotEmpty) {
          enabledPaths = paths
              .map((p) => (sourceId: p.sourceId, path: p.path))
              .toList();
        }
      }
    }

    // 渐进式加载：根据 loadingPhase 决定显示内容还是骨架屏
    final phase = state.loadingPhase;
    final isStatsPhase = phase == VideoLoadingPhase.stats;
    final needsBatch2 = phase != VideoLoadingPhase.complete;

    switch (section.category) {
      case VideoHomeCategory.heroBanner:
        // stats 阶段：显示骨架屏 hero banner
        if (isStatsPhase) {
          return [
            SliverToBoxAdapter(
              child: Container(
                height: isDesktop ? 450 : 200,
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkSurfaceVariant
                      : AppColors.lightSurfaceVariant,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.primary.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
            ),
          ];
        }
        if (topRated.isEmpty) return [];
        // 使用随机 seed 从评分 7-10 的内容中随机选择 4 部，每次打开 app 会变化
        final heroItems = _selectRandomHeroItems(topRated, 4);
        return [
          SliverToBoxAdapter(
            child: isDesktop
                ? HeroBanner(
                    items: heroItems,
                    height: 450,
                    onItemTap: (item) => _openVideoDetail(context, ref, item),
                    onPlayTap: (item) => _playVideo(context, ref, item),
                  )
                : CompactHeroBanner(
                    items: heroItems,
                    onItemTap: (item) => _openVideoDetail(context, ref, item),
                  ),
          ),
        ];

      case VideoHomeCategory.continueWatching:
        return [_ContinueWatchingSection(isDark: isDark)];

      case VideoHomeCategory.recentlyAdded:
        // stats 阶段：显示骨架屏
        if (isStatsPhase) {
          return [
            SliverToBoxAdapter(
              child: _SkeletonCategoryRow(
                title: '最近添加',
                isDark: isDark,
                icon: Icons.fiber_new_rounded,
                iconColor: Colors.blue,
              ),
            ),
          ];
        }
        if (recentVideos.isEmpty) return [];
        return [
          SliverToBoxAdapter(
            child: _CategoryRow(
              title: '最近添加',
              items: recentVideos,
              onItemTap: (m) => _openVideoDetail(context, ref, m),
              onItemContextMenu: (m) => _showVideoContextMenu(context, ref, m),
              isDark: isDark,
              icon: Icons.fiber_new_rounded,
              iconColor: Colors.blue,
              onViewAll: allRecentVideos.length > 20
                  ? () => _showCategoryPage(context, '最近添加', allRecentVideos)
                  : null,
            ),
          ),
        ];

      case VideoHomeCategory.movies:
        // stats 阶段：显示骨架屏
        if (isStatsPhase) {
          return [
            SliverToBoxAdapter(
              child: _SkeletonCategoryRow(
                title: '电影',
                isDark: isDark,
                icon: Icons.movie_filter_rounded,
                iconColor: AppColors.primary,
              ),
            ),
          ];
        }
        if (movies.isEmpty) return [];
        return [
          SliverToBoxAdapter(
            child: _CategoryRow(
              title: '电影',
              items: movies,
              onItemTap: (m) => _openVideoDetail(context, ref, m),
              onItemContextMenu: (m) => _showVideoContextMenu(context, ref, m),
              isDark: isDark,
              icon: Icons.movie_filter_rounded,
              iconColor: AppColors.primary,
              totalCount: state.movieCount,
              onViewAll: state.movieCount > 10
                  ? () => _showMoviesPage(context, ref, '电影')
                  : null,
            ),
          ),
        ];

      case VideoHomeCategory.tvShows:
        // 需要 batch2 数据，stats/batch1 阶段显示骨架屏
        if (needsBatch2) {
          return [
            SliverToBoxAdapter(
              child: _SkeletonCategoryRow(
                title: '剧集',
                isDark: isDark,
                icon: Icons.tv_rounded,
                iconColor: AppColors.accent,
              ),
            ),
          ];
        }
        if (tvShowGroups.isEmpty) return [];
        return [
          SliverToBoxAdapter(
            child: _TvShowRow(
              title: '剧集',
              groups: tvShowGroups,
              onGroupTap: (group) => _openTvShowDetail(context, ref, group),
              isDark: isDark,
              icon: Icons.tv_rounded,
              iconColor: AppColors.accent,
              totalCount: state.tvShowGroupCount,
              onViewAll: state.tvShowGroupCount > 10
                  ? () => _showTvShowsFullPage(context, ref, '剧集')
                  : null,
            ),
          ),
        ];

      case VideoHomeCategory.movieCollections:
        // 需要 batch2 数据，stats/batch1 阶段显示骨架屏
        if (needsBatch2) {
          return [
            SliverToBoxAdapter(
              child: _SkeletonCategoryRow(
                title: '电影系列',
                isDark: isDark,
                icon: Icons.video_library_rounded,
                iconColor: Colors.purple,
              ),
            ),
          ];
        }
        if (movieCollections.isEmpty) return [];
        return [
          SliverToBoxAdapter(
            child: _MovieCollectionRow(
              title: '电影系列',
              collections: movieCollections,
              onCollectionTap: (collection) =>
                  _showCollectionPage(context, ref, collection),
              onSeeAllTap: movieCollections.length > 10
                  ? () => _showMovieCollectionsFullPage(
                      context,
                      ref,
                      movieCollections,
                    )
                  : null,
              isDark: isDark,
              icon: Icons.video_library_rounded,
              iconColor: Colors.purple,
            ),
          ),
        ];

      case VideoHomeCategory.topRated:
        // stats 阶段：显示骨架屏
        if (isStatsPhase) {
          return [
            SliverToBoxAdapter(
              child: _SkeletonCategoryRow(
                title: '每日推荐',
                isDark: isDark,
                icon: Icons.auto_awesome_rounded,
                iconColor: Colors.amber,
              ),
            ),
          ];
        }
        // 跳过 heroBanner 使用的项目（最多 4 个）
        // HeroBanner 只在有足够数据时使用前 4 个，否则使用全部
        final heroBannerCount = topRated.length >= 4 ? 4 : 0;
        final remainingItems = topRated.skip(heroBannerCount).toList();
        if (remainingItems.isEmpty) return [];
        return [
          SliverToBoxAdapter(
            child: _CategoryRow(
              title: '每日推荐',
              items: remainingItems,
              onItemTap: (m) => _openVideoDetail(context, ref, m),
              onItemContextMenu: (m) => _showVideoContextMenu(context, ref, m),
              isDark: isDark,
              icon: Icons.auto_awesome_rounded,
              iconColor: Colors.amber,
              onViewAll: remainingItems.length > 10
                  ? () => _showCategoryPage(context, '每日推荐', remainingItems)
                  : null,
            ),
          ),
        ];

      case VideoHomeCategory.unwatched:
        // 未观看分类 - 需要异步加载，这里先返回占位符
        return [
          _UnwatchedSection(
            isDark: isDark,
            onItemTap: (m) => _openVideoDetail(context, ref, m),
            onItemContextMenu: (m) => _showVideoContextMenu(context, ref, m),
          ),
        ];

      case VideoHomeCategory.others:
        // 需要 batch2 数据，stats/batch1 阶段显示骨架屏
        if (needsBatch2) {
          return [
            SliverToBoxAdapter(
              child: _SkeletonCategoryRow(
                title: '其他',
                isDark: isDark,
                icon: Icons.folder_special_rounded,
                iconColor: Colors.grey,
              ),
            ),
          ];
        }
        if (state.others.isEmpty) return [];
        return [
          SliverToBoxAdapter(
            child: _CategoryRow(
              title: '其他',
              items: state.others,
              onItemTap: (m) => _openVideoDetail(context, ref, m),
              onItemContextMenu: (m) => _showVideoContextMenu(context, ref, m),
              isDark: isDark,
              icon: Icons.folder_special_rounded,
              iconColor: Colors.grey,
              totalCount: state.otherCount,
              onViewAll: state.otherCount > 10
                  ? () => _showOthersPage(context, ref, '其他')
                  : null,
            ),
          ),
        ];

      case VideoHomeCategory.byMovieGenre:
        // 电影类型分类
        if (section.filter == null) return [];
        return [
          _DynamicCategorySection(
            category: section.category,
            filter: section.filter!,
            isDark: isDark,
            onItemTap: (m) => _openVideoDetail(context, ref, m),
            onItemContextMenu: (m) => _showVideoContextMenu(context, ref, m),
            enabledPaths: enabledPaths,
          ),
        ];

      case VideoHomeCategory.byMovieRegion:
        // 电影地区分类
        if (section.filter == null) return [];
        return [
          _DynamicCategorySection(
            category: section.category,
            filter: section.filter!,
            isDark: isDark,
            onItemTap: (m) => _openVideoDetail(context, ref, m),
            onItemContextMenu: (m) => _showVideoContextMenu(context, ref, m),
            enabledPaths: enabledPaths,
          ),
        ];

      case VideoHomeCategory.byTvGenre:
        // 电视剧类型分类
        if (section.filter == null) return [];
        return [
          _DynamicCategorySection(
            category: section.category,
            filter: section.filter!,
            isDark: isDark,
            onItemTap: (m) => _openVideoDetail(context, ref, m),
            onItemContextMenu: (m) => _showVideoContextMenu(context, ref, m),
            enabledPaths: enabledPaths,
          ),
        ];

      case VideoHomeCategory.byTvRegion:
        // 电视剧地区分类
        if (section.filter == null) return [];
        return [
          _DynamicCategorySection(
            category: section.category,
            filter: section.filter!,
            isDark: isDark,
            onItemTap: (m) => _openVideoDetail(context, ref, m),
            onItemContextMenu: (m) => _showVideoContextMenu(context, ref, m),
            enabledPaths: enabledPaths,
          ),
        ];

      case VideoHomeCategory.browseMovieGenres:
        // 电影-类型（卡片式），只显示用户选择的类型
        final movieGenreFilters = categorySettings
            .getFiltersForCategory(VideoHomeCategory.byMovieGenre)
            .whereType<String>()
            .toList();
        if (movieGenreFilters.isEmpty) return [];
        return [
          SliverToBoxAdapter(
            child: CategoryBrowseCardsRow(
              category: section.category,
              isDark: isDark,
              selectedFilters: movieGenreFilters,
              enabledPaths: enabledPaths,
              onCategoryTap: (filter) => _showFilteredVideosPage(
                context,
                ref,
                VideoHomeCategory.byMovieGenre,
                filter,
                enabledPaths,
              ),
            ),
          ),
        ];

      case VideoHomeCategory.browseMovieRegions:
        // 电影-地区（卡片式），只显示用户选择的地区
        final movieRegionFilters = categorySettings
            .getFiltersForCategory(VideoHomeCategory.byMovieRegion)
            .whereType<String>()
            .toList();
        if (movieRegionFilters.isEmpty) return [];
        return [
          SliverToBoxAdapter(
            child: CategoryBrowseCardsRow(
              category: section.category,
              isDark: isDark,
              selectedFilters: movieRegionFilters,
              enabledPaths: enabledPaths,
              onCategoryTap: (filter) => _showFilteredVideosPage(
                context,
                ref,
                VideoHomeCategory.byMovieRegion,
                filter,
                enabledPaths,
              ),
            ),
          ),
        ];

      case VideoHomeCategory.browseTvGenres:
        // 剧集-类型（卡片式），只显示用户选择的类型
        final tvGenreFilters = categorySettings
            .getFiltersForCategory(VideoHomeCategory.byTvGenre)
            .whereType<String>()
            .toList();
        if (tvGenreFilters.isEmpty) return [];
        return [
          SliverToBoxAdapter(
            child: CategoryBrowseCardsRow(
              category: section.category,
              isDark: isDark,
              selectedFilters: tvGenreFilters,
              enabledPaths: enabledPaths,
              onCategoryTap: (filter) => _showFilteredVideosPage(
                context,
                ref,
                VideoHomeCategory.byTvGenre,
                filter,
                enabledPaths,
              ),
            ),
          ),
        ];

      case VideoHomeCategory.browseTvRegions:
        // 剧集-地区（卡片式），只显示用户选择的地区
        final tvRegionFilters = categorySettings
            .getFiltersForCategory(VideoHomeCategory.byTvRegion)
            .whereType<String>()
            .toList();
        if (tvRegionFilters.isEmpty) return [];
        return [
          SliverToBoxAdapter(
            child: CategoryBrowseCardsRow(
              category: section.category,
              isDark: isDark,
              selectedFilters: tvRegionFilters,
              enabledPaths: enabledPaths,
              onCategoryTap: (filter) => _showFilteredVideosPage(
                context,
                ref,
                VideoHomeCategory.byTvRegion,
                filter,
                enabledPaths,
              ),
            ),
          ),
        ];

      case VideoHomeCategory.liveStreaming:
        // 直播区块
        return [
          SliverToBoxAdapter(
            child: LiveStreamSection(isDark: isDark),
          ),
        ];
    }
  }

  /// 获取最近添加的视频（使用 SQLite 预加载的数据）
  List<VideoMetadata> _getRecentVideos(VideoListLoaded state, {int? limit}) {
    final recentVideos = state.recentVideos;
    return limit != null ? recentVideos.take(limit).toList() : recentVideos;
  }

  /// 显示分类页面（旧版，用于最近添加等）
  void _showCategoryPage(
    BuildContext context,
    String title,
    List<VideoMetadata> items,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _CategoryFullPage(title: title, items: items),
      ),
    );
  }

  /// 显示电影全部页面（支持分页懒加载）
  void _showMoviesPage(BuildContext context, WidgetRef ref, String title) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _MoviesPaginatedPage(title: title),
      ),
    );
  }

  /// 显示剧集全部页面（支持分页懒加载）
  void _showTvShowsFullPage(BuildContext context, WidgetRef ref, String title) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _TvShowsPaginatedPage(title: title),
      ),
    );
  }

  /// 显示其他视频全部页面（支持分页懒加载）
  void _showOthersPage(BuildContext context, WidgetRef ref, String title) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _OthersPaginatedPage(title: title),
      ),
    );
  }

  /// 显示筛选视频页面（用于动态分类卡片点击）
  void _showFilteredVideosPage(
    BuildContext context,
    WidgetRef ref,
    VideoHomeCategory category,
    String filter,
    List<({String sourceId, String path})>? enabledPaths,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _FilteredVideosPaginatedPage(
          category: category,
          enabledPaths: enabledPaths,
          filter: filter,
          onVideoTap: (video) => _openVideoDetail(context, ref, video),
        ),
      ),
    );
  }

  /// 显示电影系列详情页面
  void _showCollectionPage(
    BuildContext context,
    WidgetRef ref,
    MovieCollection collection,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _MovieCollectionPage(
          collection: collection,
          onMovieTap: (movie) => _openVideoDetail(context, ref, movie),
        ),
      ),
    );
  }

  /// 显示电影系列全部页面
  void _showMovieCollectionsFullPage(
    BuildContext context,
    WidgetRef ref,
    List<MovieCollection> collections,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _MovieCollectionsFullPage(
          collections: collections,
          onCollectionTap: (collection) =>
              _showCollectionPage(context, ref, collection),
        ),
      ),
    );
  }

  /// 搜索结果页面
  Widget _buildSearchResults(
    BuildContext context,
    WidgetRef ref,
    VideoListLoaded state,
    bool isDark,
  ) {
    final results = state.filteredMetadata;

    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 64,
              color: isDark ? Colors.grey[600] : Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              '未找到 "${state.searchQuery}" 的相关结果',
              style: TextStyle(
                fontSize: 16,
                color: isDark
                    ? AppColors.darkOnSurfaceVariant
                    : AppColors.lightOnSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        // 顶部安全区域留白（避免与状态栏重叠）
        SliverPadding(padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              '找到 ${results.length} 个结果',
              style: TextStyle(
                fontSize: 14,
                color: isDark
                    ? AppColors.darkOnSurfaceVariant
                    : AppColors.lightOnSurfaceVariant,
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: _CategoryRow(
            title: '搜索结果',
            items: results,
            onItemTap: (m) => _openVideoDetail(context, ref, m),
            isDark: isDark,
            icon: Icons.search_rounded,
            iconColor: AppColors.primary,
            maxCount: results.length, // 显示所有结果
          ),
        ),
        // 底部留白 - 使用动态 padding 支持悬浮导航栏
        SliverPadding(padding: EdgeInsets.only(bottom: context.scrollBottomPadding)),
      ],
    );
  }

  /// 直接播放视频
  Future<void> _playVideo(
    BuildContext context,
    WidgetRef ref,
    VideoMetadata metadata,
  ) async {
    // 获取连接
    final connections = ref.read(activeConnectionsProvider);
    final connection = connections[metadata.sourceId];
    if (connection == null) return;

    try {
      // 获取视频URL
      final url = await connection.adapter.fileSystem.getFileUrl(
        metadata.filePath,
      );

      if (!context.mounted) return;

      final videoItem = VideoItem(
        name: metadata.displayTitle,
        path: metadata.filePath,
        url: url,
        sourceId: metadata.sourceId,
        thumbnailUrl: metadata.displayPosterUrl,
      );

      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (context) => VideoPlayerPage(video: videoItem),
        ),
      );

      ref.invalidate(continueWatchingProvider);
    } on Exception catch (e) {
      logger.e('播放视频失败', e);
    }
  }

  Future<void> _openVideoDetail(
    BuildContext context,
    WidgetRef ref,
    VideoMetadata metadata,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) =>
            VideoDetailPage(metadata: metadata, sourceId: metadata.sourceId),
      ),
    );
    ref.invalidate(continueWatchingProvider);
  }

  /// 打开 TV 剧集合集详情页
  ///
  /// 使用 [VideoDetailPage] 展示代表集，其内置的剧集选择器可以展示和播放所有剧集
  Future<void> _openTvShowDetail(
    BuildContext context,
    WidgetRef ref,
    TvShowGroup group,
  ) async {
    // 使用 TvShowGroup 的代表集（通常是第一集或最近观看的一集）导航到 VideoDetailPage
    // VideoDetailPage 内置的 EpisodeSelector 会显示同一部剧的所有季和集
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => VideoDetailPage(
          metadata: group.representative,
          sourceId: group.representative.sourceId,
        ),
      ),
    );
    ref.invalidate(continueWatchingProvider);
  }

  /// 显示视频上下文菜单
  Future<void> _showVideoContextMenu(
    BuildContext context,
    WidgetRef ref,
    VideoMetadata metadata,
  ) async {
    final favService = ref.read(mediaFavoritesServiceProvider);
    await favService.init();
    final isFav = favService.isFavoriteSync(
      type: MediaType.video,
      sourceId: metadata.sourceId,
      path: metadata.filePath,
    );

    if (!context.mounted) return;
    final action = await showMediaFileContextMenu(
      context: context,
      fileName: metadata.displayTitle,
      showAddToFavorites: true,
      isFavorite: isFav,
      showViewDetails: true,
      // 视频文件大，菜单中暂不提供下载入口（保留 false）；
      // 用户若要离线观看，建议从详情页或专门的下载流程发起。
    );

    if (action == null || !context.mounted) return;

    switch (action) {
      case MediaFileAction.removeFromLibrary:
        final confirmed = await showDeleteConfirmDialog(
          context: context,
          title: '从媒体库移除',
          content:
              '确定要从媒体库移除「${metadata.displayTitle}」吗？\n\n这只会移除索引记录，源文件不会被删除。',
          confirmText: '移除',
          isDestructive: false,
        );
        if (confirmed && context.mounted) {
          final success = await ref
              .read(videoListProvider.notifier)
              .removeFromLibrary(metadata);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(success ? '已从媒体库移除' : '移除失败'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      case MediaFileAction.deleteFromSource:
        final confirmed = await showDeleteConfirmDialog(
          context: context,
          title: '删除源文件',
          content:
              '确定要删除「${metadata.displayTitle}」的源文件吗？\n\n⚠️ 此操作不可恢复！文件将从 NAS 中永久删除。',
        );
        if (confirmed && context.mounted) {
          final success = await ref
              .read(videoListProvider.notifier)
              .deleteFromSource(metadata);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(success ? '已删除源文件' : '删除失败，请检查连接状态'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      case MediaFileAction.addToFavorites:
      case MediaFileAction.removeFromFavorites:
        await ref.read(mediaFavoritesActionsProvider).toggle(
              type: MediaType.video,
              sourceId: metadata.sourceId,
              path: metadata.filePath,
              displayName: metadata.displayTitle,
            );
      case MediaFileAction.viewDetails:
        await MediaInfoSheet.show(
          context: context,
          title: metadata.displayTitle,
          subtitle: '视频',
          entries: [
            MediaInfoEntry(label: '文件大小', value: metadata.fileSizeText),
            MediaInfoEntry(label: '分辨率', value: metadata.resolution ?? ''),
            MediaInfoEntry(label: '编码', value: metadata.videoCodec ?? ''),
            MediaInfoEntry(
              label: '修改时间',
              value: metadata.fileModifiedTime?.toLocal().toString() ?? '',
            ),
            MediaInfoEntry(label: '来源 ID', value: metadata.sourceId, copyable: true),
            MediaInfoEntry(label: '路径', value: metadata.filePath, copyable: true),
          ],
        );
      case MediaFileAction.share:
      case MediaFileAction.download:
        // 视频不在菜单中提供分享/下载（文件过大）；showXxx 默认 false。
        debugPrint('[VideoList] MediaFileAction.${action.name} 尚未实现');
    }
  }
}

/// 继续观看区域
class _ContinueWatchingSection extends ConsumerWidget {
  const _ContinueWatchingSection({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 使用合并后的继续观看数据（包含本地历史和 Trakt 进度）
    final combinedAsync = ref.watch(combinedContinueWatchingProvider);

    return combinedAsync.when(
      data: (items) {
        // 过滤出可播放的项目（有本地文件或本地历史记录）
        final playableItems = items.where((item) => item.isPlayable).toList();

        if (playableItems.isEmpty) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }

        return SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.play_circle_rounded,
                        color: AppColors.error,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '继续观看',
                      style: context.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : null,
                      ),
                    ),
                    // 显示数据来源指示
                    if (items.any((i) => i.source == ContinueWatchingSource.trakt)) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFED1C24).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Trakt',
                          style: TextStyle(
                            color: Color(0xFFED1C24),
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(
                height: 140,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  // 预构建更多屏幕外的 item，让图片提前开始加载
                  cacheExtent: 500,
                  itemCount: playableItems.length,
                  itemBuilder: (context, index) =>
                      _CombinedContinueWatchingCard(item: playableItems[index], isDark: isDark),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
      error: (_, _) => const SliverToBoxAdapter(child: SizedBox.shrink()),
    );
  }
}

/// 合并版继续观看卡片（支持本地和 Trakt 数据源）
class _CombinedContinueWatchingCard extends ConsumerWidget {
  _CombinedContinueWatchingCard({required this.item, required this.isDark});

  final ContinueWatchingItem item;
  final bool isDark;
  final VideoThumbnailService _thumbnailService = VideoThumbnailService();

  /// 获取可用的海报 URL
  String? _getDisplayPosterUrl() {
    // 优先使用进度截图（停止帧）
    if (item.videoPath != null) {
      final progressThumbnail = _thumbnailService.getProgressThumbnailUrl(item.videoPath!);
      if (progressThumbnail != null) {
        return progressThumbnail;
      }
    }

    // 其次使用 ContinueWatchingItem 的海报 URL
    if (item.posterUrl != null && item.posterUrl!.isNotEmpty) {
      if (AdaptiveImage.isSupportedUrl(item.posterUrl!)) {
        return item.posterUrl;
      }
    }

    // 最后使用本地历史记录的缩略图
    if (item.localHistoryItem?.thumbnailUrl != null &&
        item.localHistoryItem!.thumbnailUrl!.isNotEmpty) {
      if (AdaptiveImage.isSupportedUrl(item.localHistoryItem!.thumbnailUrl!)) {
        return item.localHistoryItem!.thumbnailUrl;
      }
    }

    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posterUrl = _getDisplayPosterUrl();
    final progressPercent = (item.progress / 100).clamp(0.0, 1.0);

    return Container(
      width: 200,
      margin: const EdgeInsets.only(right: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _playVideo(context, ref),
          borderRadius: BorderRadius.circular(12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkBackground : AppColors.lightSurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 缩略图区域
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                        child: posterUrl != null
                            ? AdaptiveImage(
                                imageUrl: posterUrl,
                                placeholder: (_) => _buildThumbnailPlaceholder(),
                                errorWidget: (_, _) => _buildThumbnailPlaceholder(),
                              )
                            : _buildThumbnailPlaceholder(),
                      ),
                      // 进度条
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          height: 3,
                          color: Colors.black45,
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: progressPercent,
                            child: Container(color: AppColors.error),
                          ),
                        ),
                      ),
                      // 来源标识
                      if (item.source == ContinueWatchingSource.trakt)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFED1C24),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'T',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // 信息区域
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white : null,
                        ),
                      ),
                      Text(
                        '${item.progress.round()}%',
                        style: TextStyle(
                          fontSize: 10,
                          color: isDark
                              ? AppColors.darkOnSurfaceVariant
                              : AppColors.lightOnSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnailPlaceholder() => Container(
        color: isDark ? Colors.grey[800] : Colors.grey[200],
        child: const Center(
          child: Icon(Icons.play_circle_rounded, size: 40, color: Colors.white54),
        ),
      );

  Future<void> _playVideo(BuildContext context, WidgetRef ref) async {
    // 优先使用本地历史记录播放
    if (item.localHistoryItem != null) {
      final historyItem = item.localHistoryItem!;
      final videoItem = VideoItem(
        name: item.displayTitle,
        path: historyItem.videoPath,
        url: historyItem.videoUrl,
        sourceId: historyItem.sourceId,
        size: historyItem.size,
        thumbnailUrl: historyItem.thumbnailUrl,
        lastPosition: historyItem.lastPosition,
      );

      if (!context.mounted) return;

      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (context) => VideoPlayerPage(video: videoItem),
        ),
      );

      if (!context.mounted) return;
      ref
        ..invalidate(continueWatchingProvider)
        ..invalidate(combinedContinueWatchingProvider);
      return;
    }

    // 使用元数据播放
    if (item.metadata != null && item.videoPath != null) {
      final metadata = item.metadata!;
      final videoItem = VideoItem(
        name: item.displayTitle,
        path: item.videoPath!,
        url: '', // URL 需要通过文件系统获取
        sourceId: item.sourceId,
        thumbnailUrl: metadata.displayPosterUrl,
      );

      if (!context.mounted) return;

      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (context) => VideoPlayerPage(video: videoItem),
        ),
      );

      if (!context.mounted) return;
      ref
        ..invalidate(continueWatchingProvider)
        ..invalidate(combinedContinueWatchingProvider);
    }
  }
}

/// 继续观看卡片
class _ContinueWatchingCard extends ConsumerWidget {
  _ContinueWatchingCard({required this.item, required this.isDark});

  final VideoHistoryItem item;
  final bool isDark;
  final VideoThumbnailService _thumbnailService = VideoThumbnailService();

  /// 获取可用的海报 URL - 优先使用进度截图，其次是历史记录中的 thumbnailUrl
  String? _getDisplayPosterUrl() {
    // 优先使用进度截图（停止帧）
    final progressThumbnail = _thumbnailService.getProgressThumbnailUrl(
      item.videoPath,
    );
    if (progressThumbnail != null) {
      return progressThumbnail;
    }

    // 其次使用历史记录中的 thumbnailUrl
    if (item.thumbnailUrl != null && item.thumbnailUrl!.isNotEmpty) {
      if (AdaptiveImage.isSupportedUrl(item.thumbnailUrl!)) {
        return item.thumbnailUrl;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posterUrl = _getDisplayPosterUrl();

    return Container(
      width: 200,
      margin: const EdgeInsets.only(right: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _playVideo(context, ref),
          borderRadius: BorderRadius.circular(12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkBackground : AppColors.lightSurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 缩略图区域
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                        child: posterUrl != null
                            ? AdaptiveImage(
                                imageUrl: posterUrl,
                                placeholder: (_) =>
                                    _buildThumbnailPlaceholder(),
                                errorWidget: (_, _) =>
                                    _buildThumbnailPlaceholder(),
                              )
                            : _buildThumbnailPlaceholder(),
                      ),
                      // 进度条
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          height: 3,
                          color: Colors.black45,
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: item.progressPercent.clamp(0.0, 1.0),
                            child: Container(color: AppColors.error),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // 信息区域
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.videoName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white : null,
                        ),
                      ),
                      if (item.lastPosition != null && item.duration != null)
                        Text(
                          '${_formatDuration(item.lastPosition!)} / ${_formatDuration(item.duration!)}',
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark
                                ? AppColors.darkOnSurfaceVariant
                                : AppColors.lightOnSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnailPlaceholder() => Container(
    color: isDark ? Colors.grey[800] : Colors.grey[200],
    child: const Center(
      child: Icon(Icons.play_circle_rounded, size: 40, color: Colors.white54),
    ),
  );

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _playVideo(BuildContext context, WidgetRef ref) async {
    final videoItem = VideoItem(
      name: item.videoName,
      path: item.videoPath,
      url: item.videoUrl,
      sourceId: item.sourceId,
      size: item.size,
      thumbnailUrl: item.thumbnailUrl,
      lastPosition: item.lastPosition,
    );

    if (!context.mounted) return;

    // 尝试获取视频元数据，如果是剧集则设置播放列表
    await _trySetPlaylistForTvEpisode(ref);

    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (context) => VideoPlayerPage(video: videoItem),
      ),
    );

    // 检查 widget 是否仍然挂载
    if (!context.mounted) return;
    ref.invalidate(continueWatchingProvider);
  }

  /// 尝试为电视剧集设置播放列表
  ///
  /// 从 VideoMetadataService 获取视频元数据，如果是剧集则获取同季所有剧集并设置播放列表
  Future<void> _trySetPlaylistForTvEpisode(WidgetRef ref) async {
    try {
      // 获取视频元数据
      final metadataService = ref.read(videoMetadataServiceProvider);
      await metadataService.init();

      final sourceId = item.sourceId;
      if (sourceId == null) return;

      final metadata = await metadataService.getCachedAsync(
        sourceId,
        item.videoPath,
      );
      if (metadata == null) return;

      // 检查是否为电视剧集
      if (metadata.category != MediaCategory.tvShow) return;
      if (metadata.seasonNumber == null) return;

      // 获取同系列剧集
      var localEpisodes = <int, Map<int, VideoMetadata>>{};

      if (metadata.tmdbId != null) {
        // 使用 TMDB ID 查询
        localEpisodes = await metadataService.getEpisodesByTmdbId(
          metadata.tmdbId!,
        );
      } else {
        // 使用 showDirectory 查询
        var showDirectory = metadata.showDirectory;
        if (showDirectory == null || showDirectory.isEmpty) {
          showDirectory = VideoDatabaseService.extractShowDirectory(
            metadata.filePath,
          );
        }
        if (showDirectory != null && showDirectory.isNotEmpty) {
          localEpisodes = await metadataService.getEpisodesByShowDirectory(
            showDirectory,
          );
        }
      }

      // 获取当前季的剧集
      final seasonEpisodes = localEpisodes[metadata.seasonNumber] ?? {};
      if (seasonEpisodes.isEmpty) {
        logger.d('ContinueWatchingCard: 无法构建播放列表，当前季无其他剧集');
        return;
      }

      // 按集号排序并构建 VideoItem 列表
      final episodeNumbers = seasonEpisodes.keys.toList()..sort();
      final playlistItems = <VideoItem>[];
      var startIndex = 0;

      for (var i = 0; i < episodeNumbers.length; i++) {
        final epNum = episodeNumbers[i];
        final episode = seasonEpisodes[epNum]!;

        playlistItems.add(
          VideoItem(
            name: episode.episodeTitle ?? episode.displayTitle,
            path: episode.filePath,
            // URL 留空，播放时会自动获取
            sourceId: sourceId,
            size: episode.fileSize ?? 0,
            thumbnailUrl: episode.displayPosterUrl,
          ),
        );

        // 记录当前播放集的索引
        if (episode.filePath == item.videoPath) {
          startIndex = i;
        }
      }

      // 设置播放列表
      if (playlistItems.isNotEmpty) {
        ref
            .read(playlistProvider.notifier)
            .setPlaylist(playlistItems, startIndex: startIndex);
        logger.i(
          'ContinueWatchingCard: 播放列表已设置，共 ${playlistItems.length} 集，从第 ${startIndex + 1} 集开始',
        );
      }
    } catch (e, st) {
      // 设置播放列表失败不影响正常播放
      AppError.ignore(e, st, 'ContinueWatchingCard: 设置播放列表失败');
    }
  }
}

/// 扫描中的简化视频卡片（横向布局）
class _PartialVideoCard extends StatelessWidget {
  const _PartialVideoCard({required this.video, required this.isDark});

  final VideoFileWithSource video;
  final bool isDark;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      // 横向视频缩略图
      Flexible(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.darkSurfaceVariant
                : AppColors.lightSurfaceVariant,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 缩略图或占位符
                if (video.thumbnailUrl != null &&
                    AdaptiveImage.isSupportedUrl(video.thumbnailUrl!))
                  AdaptiveImage(
                    imageUrl: video.thumbnailUrl!,
                    placeholder: (_) => _buildPlaceholder(),
                    errorWidget: (_, _) => _buildPlaceholder(),
                  )
                else
                  _buildPlaceholder(),
                // 扫描中标记
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 8,
                          height: 8,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          '扫描中',
                          style: TextStyle(color: Colors.white, fontSize: 9),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          video.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white : null,
          ),
        ),
      ),
    ],
  );

  Widget _buildPlaceholder() => Center(
    child: Icon(
      Icons.movie_rounded,
      size: 32,
      color: isDark ? Colors.grey[600] : Colors.grey[400],
    ),
  );
}

/// 海报卡片（带播放进度）
class _PosterCard extends ConsumerStatefulWidget {
  const _PosterCard({
    required this.metadata,
    required this.onTap,
    required this.isDark,
    // ignore: unused_element_parameter
    this.width,
  });

  final VideoMetadata metadata;
  final VoidCallback onTap;
  final bool isDark;
  final double? width;

  @override
  ConsumerState<_PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends ConsumerState<_PosterCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final displayPoster = widget.metadata.displayPosterUrl;
    final hasPoster = displayPoster != null && displayPoster.isNotEmpty;

    // 获取播放进度
    final progressAsync = ref.watch(allVideoProgressProvider);
    final progress = progressAsync.valueOrNull?[widget.metadata.filePath];
    final hasProgress =
        progress != null &&
        progress.progressPercent > 0.02 &&
        progress.progressPercent < 0.98;

    return Container(
      width: widget.width,
      margin: widget.width != null ? const EdgeInsets.only(right: 12) : null,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            transform: Matrix4.identity()
              ..scaleByDouble(
                _isHovered ? 1.05 : 1.0,
                _isHovered ? 1.05 : 1.0,
                1,
                1,
              ),
            transformAlignment: Alignment.center,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 海报
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: _isHovered ? 0.4 : 0.25,
                          ),
                          blurRadius: _isHovered ? 20 : 10,
                          offset: Offset(0, _isHovered ? 10 : 5),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // 海报图片（使用 VideoPoster 支持 NAS 路径）
                          if (hasPoster)
                            VideoPoster(
                              posterUrl: displayPoster,
                              sourceId: widget.metadata.sourceId,
                              placeholder: _buildPlaceholder(),
                              errorWidget: _buildPlaceholder(),
                            )
                          else
                            _buildPlaceholder(),

                          // 渐变遮罩
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              height: 60,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withValues(alpha: 0.8),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          // 播放进度条
                          if (hasProgress)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: Container(
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  borderRadius: const BorderRadius.only(
                                    bottomLeft: Radius.circular(12),
                                    bottomRight: Radius.circular(12),
                                  ),
                                ),
                                child: FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: progress.progressPercent.clamp(
                                    0.0,
                                    1.0,
                                  ),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      borderRadius: BorderRadius.only(
                                        bottomLeft: const Radius.circular(12),
                                        bottomRight:
                                            progress.progressPercent > 0.95
                                            ? const Radius.circular(12)
                                            : Radius.zero,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                          // 评分徽章
                          if (widget.metadata.rating != null &&
                              widget.metadata.rating! > 0)
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _getRatingColor(),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.star_rounded,
                                      size: 12,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      widget.metadata.ratingText,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          // 剧集标记
                          if (widget.metadata.category == MediaCategory.tvShow)
                            Positioned(
                              top: 8,
                              left: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.accent,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  widget.metadata.seasonNumber != null
                                      ? 'S${widget.metadata.seasonNumber}'
                                      : '剧集',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),

                          // 刮削状态指示器
                          if (widget.metadata.isPendingScrape ||
                              widget.metadata.isScraping)
                            Positioned(
                              top: 8,
                              left:
                                  widget.metadata.category ==
                                      MediaCategory.tvShow
                                  ? 50
                                  : 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey[800]!.withValues(
                                    alpha: 0.9,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 8,
                                      height: 8,
                                      child: widget.metadata.isScraping
                                          ? const CircularProgressIndicator(
                                              strokeWidth: 1.5,
                                              color: Colors.white,
                                            )
                                          : Icon(
                                              Icons.hourglass_empty,
                                              size: 8,
                                              color: Colors.grey[400],
                                            ),
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      widget.metadata.isScraping
                                          ? '刮削中'
                                          : '待刮削',
                                      style: TextStyle(
                                        color: Colors.grey[300],
                                        fontSize: 8,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          // 继续观看标记
                          if (hasProgress)
                            Positioned(
                              bottom: 10,
                              left: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.7),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.play_arrow_rounded,
                                      size: 12,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      '${(progress.progressPercent * 100).toInt()}%',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          // 悬停边框
                          if (_isHovered)
                            Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: AppColors.primary,
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                // 标题
                const SizedBox(height: 8),
                Text(
                  widget.metadata.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: widget.isDark ? Colors.white : null,
                  ),
                ),
                // 年份
                if (widget.metadata.year != null)
                  Text(
                    '${widget.metadata.year}',
                    style: TextStyle(
                      fontSize: 10,
                      color: widget.isDark
                          ? Colors.grey[500]
                          : Colors.grey[600],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() => Container(
    color: widget.isDark
        ? AppColors.darkSurfaceVariant
        : AppColors.lightSurfaceVariant,
    child: Center(
      child: Icon(
        widget.metadata.category == MediaCategory.tvShow
            ? Icons.live_tv_rounded
            : Icons.movie_rounded,
        size: 40,
        color: widget.isDark ? Colors.grey[600] : Colors.grey[400],
      ),
    ),
  );

  Color _getRatingColor() => AppColors.ratingColor(widget.metadata.rating ?? 0);
}

/// 骨架屏分类行组件（渐进式加载时显示）
class _SkeletonCategoryRow extends StatelessWidget {
  const _SkeletonCategoryRow({
    required this.title,
    required this.isDark,
    this.icon,
    this.iconColor,
    // ignore: unused_element_parameter
    this.itemCount = 5,
  });

  final String title;
  final bool isDark;
  final IconData? icon;
  final Color? iconColor;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final effectiveIconColor = iconColor ?? AppColors.primary;
    const cardWidth = 130.0;
    const cardHeight = 195.0;
    final shimmerBaseColor = isDark
        ? AppColors.darkOutline
        : AppColors.lightOutline;
    final shimmerHighlightColor = isDark
        ? Colors.grey[700]!
        : Colors.grey[100]!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题栏
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Row(
            children: [
              if (icon != null) ...[
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: effectiveIconColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 18, color: effectiveIconColor),
                ),
                const SizedBox(width: 10),
              ],
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(width: 8),
              // 加载指示器
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    effectiveIconColor.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
          ),
        ),
        // 骨架卡片列表
        SizedBox(
          height: cardHeight + 45,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            physics: const NeverScrollableScrollPhysics(),
            itemCount: itemCount,
            itemBuilder: (context, index) => Container(
              width: cardWidth,
              margin: const EdgeInsets.only(right: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 海报骨架
                  _ShimmerBox(
                    width: cardWidth,
                    height: cardHeight,
                    borderRadius: 8,
                    baseColor: shimmerBaseColor,
                    highlightColor: shimmerHighlightColor,
                  ),
                  const SizedBox(height: 8),
                  // 标题骨架
                  _ShimmerBox(
                    width: cardWidth * 0.8,
                    height: 14,
                    borderRadius: 4,
                    baseColor: shimmerBaseColor,
                    highlightColor: shimmerHighlightColor,
                  ),
                  const SizedBox(height: 4),
                  // 副标题骨架
                  _ShimmerBox(
                    width: cardWidth * 0.5,
                    height: 12,
                    borderRadius: 4,
                    baseColor: shimmerBaseColor,
                    highlightColor: shimmerHighlightColor,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 闪烁动画骨架盒子
class _ShimmerBox extends StatefulWidget {
  const _ShimmerBox({
    required this.width,
    required this.height,
    required this.borderRadius,
    required this.baseColor,
    required this.highlightColor,
  });

  final double width;
  final double height;
  final double borderRadius;
  final Color baseColor;
  final Color highlightColor;

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
    _animation = Tween<double>(begin: -1, end: 2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _animation,
    builder: (context, child) => Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [widget.baseColor, widget.highlightColor, widget.baseColor],
          stops: [
            (_animation.value - 0.3).clamp(0.0, 1.0),
            _animation.value.clamp(0.0, 1.0),
            (_animation.value + 0.3).clamp(0.0, 1.0),
          ],
        ),
      ),
    ),
  );
}

/// 分类行组件（Netflix 风格，带查看更多）
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.title,
    required this.items,
    required this.onItemTap,
    required this.isDark,
    this.icon,
    this.iconColor,
    this.maxCount = 10,
    this.onViewAll,
    // ignore: unused_element_parameter
    this.useVerticalPosters = true,
    this.totalCount,
    this.onItemContextMenu,
  });

  final String title;
  final List<VideoMetadata> items;
  final void Function(VideoMetadata) onItemTap;
  final bool isDark;
  final IconData? icon;
  final Color? iconColor;
  final int maxCount;
  final VoidCallback? onViewAll;
  final bool useVerticalPosters;

  /// 实际总数量（用于显示在"查看全部"按钮上，如果不传则使用 items.length）
  final int? totalCount;

  /// 长按/右键点击时的上下文菜单回调
  final void Function(VideoMetadata)? onItemContextMenu;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    final displayItems = items.take(maxCount).toList();
    // 始终显示"查看更多"卡片（只要有 onViewAll 回调）
    final showViewMore = onViewAll != null;
    // 使用真实总数（如果提供），否则使用 items.length
    final actualTotalCount = totalCount ?? items.length;
    final remainingCount = actualTotalCount > maxCount
        ? actualTotalCount - maxCount
        : 0;
    final effectiveIconColor = iconColor ?? AppColors.primary;

    // 根据海报类型计算高度
    // 纵向海报: 宽130 * 1.5 = 195 高度 + 标题区域约 40
    // 横向视频卡: 高度约 160
    final rowHeight = useVerticalPosters ? 240.0 : 160.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题栏
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Row(
            children: [
              if (icon != null) ...[
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: effectiveIconColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 18, color: effectiveIconColor),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              // 标题栏的"查看全部"按钮
              if (showViewMore)
                TextButton(
                  onPressed: onViewAll,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '查看全部 ($actualTotalCount)',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 12,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        // 内容滚动区域
        SizedBox(
          height: rowHeight,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            // 预构建更多屏幕外的 item，让图片提前开始加载
            cacheExtent: 500,
            itemCount: displayItems.length + (showViewMore ? 1 : 0),
            itemBuilder: (context, index) {
              // 最后一个是"查看更多"卡片
              if (showViewMore && index == displayItems.length) {
                return _ViewMoreCard(
                  onTap: onViewAll,
                  isDark: isDark,
                  useVerticalStyle: useVerticalPosters,
                  remainingCount: remainingCount,
                  totalCount: items.length,
                );
              }

              final metadata = displayItems[index];
              if (useVerticalPosters) {
                return _VerticalPosterCard(
                  metadata: metadata,
                  onTap: () => onItemTap(metadata),
                  isDark: isDark,
                  onContextMenu: onItemContextMenu,
                );
              } else {
                return _HorizontalVideoCard(
                  metadata: metadata,
                  onTap: () => onItemTap(metadata),
                  isDark: isDark,
                  onContextMenu: onItemContextMenu,
                );
              }
            },
          ),
        ),
      ],
    );
  }
}

/// 查看更多卡片
class _ViewMoreCard extends StatefulWidget {
  const _ViewMoreCard({
    required this.onTap,
    required this.isDark,
    this.useVerticalStyle = true,
    this.remainingCount = 0,
    this.totalCount = 0,
  });

  final VoidCallback? onTap;
  final bool isDark;
  final bool useVerticalStyle;
  final int remainingCount;
  final int totalCount;

  @override
  State<_ViewMoreCard> createState() => _ViewMoreCardState();
}

class _ViewMoreCardState extends State<_ViewMoreCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    // 与 _VerticalPosterCard 保持一致的尺寸
    // 纵向: 宽130, 海报高195 (2:3比例), 横向: 220x124
    const verticalWidth = 130.0;
    const verticalPosterHeight = 195.0; // 130 * 1.5
    const horizontalWidth = 220.0;
    const horizontalHeight = 124.0;

    final width = widget.useVerticalStyle ? verticalWidth : horizontalWidth;
    final posterHeight = widget.useVerticalStyle
        ? verticalPosterHeight
        : horizontalHeight;

    if (widget.useVerticalStyle) {
      // 纵向样式：与 _VerticalPosterCard 结构完全一致
      return Container(
        width: width,
        margin: const EdgeInsets.only(right: 12),
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedScale(
              scale: _isHovered ? 1.05 : 1.0,
              duration: const Duration(milliseconds: 150),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 海报区域 - 与 _VerticalPosterCard 的海报容器保持一致
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: width,
                    height: posterHeight,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: _isHovered
                            ? [
                                AppColors.primary.withValues(alpha: 0.3),
                                AppColors.primary.withValues(alpha: 0.1),
                              ]
                            : [
                                if (widget.isDark)
                                  Colors.grey[850]!
                                else
                                  Colors.grey[200]!,
                                if (widget.isDark)
                                  Colors.grey[900]!
                                else
                                  Colors.grey[100]!,
                              ],
                      ),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _isHovered
                            ? AppColors.primary
                            : (widget.isDark
                                  ? Colors.grey[700]!
                                  : Colors.grey[300]!),
                        width: _isHovered ? 2 : 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: _isHovered ? 0.4 : 0.2,
                          ),
                          blurRadius: _isHovered ? 16 : 8,
                          offset: Offset(0, _isHovered ? 8 : 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // 图标
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: _isHovered
                                ? AppColors.primary.withValues(alpha: 0.2)
                                : (widget.isDark
                                      ? Colors.grey[800]
                                      : Colors.grey[300]),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.grid_view_rounded,
                            color: _isHovered
                                ? AppColors.primary
                                : (widget.isDark
                                      ? AppColors.darkOnSurfaceVariant
                                      : AppColors.lightOnSurfaceVariant),
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 12),
                        // 文字
                        Text(
                          '查看全部',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _isHovered
                                ? AppColors.primary
                                : (widget.isDark
                                      ? Colors.white
                                      : Colors.black87),
                          ),
                        ),
                        const SizedBox(height: 4),
                        // 数量
                        Text(
                          widget.remainingCount > 0
                              ? '还有 ${widget.remainingCount} 部'
                              : '共 ${widget.totalCount} 部',
                          style: TextStyle(
                            fontSize: 11,
                            color: widget.isDark
                                ? Colors.grey[500]
                                : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 标题区域 - 与 _VerticalPosterCard 保持一致的间距
                  const SizedBox(height: 8),
                  Text(
                    '更多内容',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: widget.isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  // 副标题 - 与 _VerticalPosterCard 的年份行对应
                  Text(
                    '共 ${widget.totalCount} 部',
                    style: TextStyle(
                      fontSize: 10,
                      color: widget.isDark
                          ? Colors.grey[500]
                          : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // 横向样式保持原有实现
    return Container(
      margin: const EdgeInsets.only(right: 12),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _isHovered ? 1.05 : 1.0,
            duration: const Duration(milliseconds: 150),
            child: Container(
              width: width,
              height: posterHeight,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: _isHovered
                      ? [
                          AppColors.primary.withValues(alpha: 0.3),
                          AppColors.primary.withValues(alpha: 0.1),
                        ]
                      : [
                          if (widget.isDark)
                            Colors.grey[850]!
                          else
                            Colors.grey[200]!,
                          if (widget.isDark)
                            Colors.grey[900]!
                          else
                            Colors.grey[100]!,
                        ],
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _isHovered
                      ? AppColors.primary
                      : (widget.isDark ? Colors.grey[700]! : Colors.grey[300]!),
                  width: _isHovered ? 2 : 1,
                ),
                boxShadow: _isHovered
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 图标
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _isHovered
                          ? AppColors.primary.withValues(alpha: 0.2)
                          : (widget.isDark
                                ? Colors.grey[800]
                                : Colors.grey[300]),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.grid_view_rounded,
                      color: _isHovered
                          ? AppColors.primary
                          : (widget.isDark
                                ? AppColors.darkOnSurfaceVariant
                                : AppColors.lightOnSurfaceVariant),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 文字
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '查看全部',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _isHovered
                              ? AppColors.primary
                              : (widget.isDark ? Colors.white : Colors.black87),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.remainingCount > 0
                            ? '还有 ${widget.remainingCount} 部'
                            : '共 ${widget.totalCount} 部',
                        style: TextStyle(
                          fontSize: 11,
                          color: widget.isDark
                              ? Colors.grey[500]
                              : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 懒加载海报卡片包装器
///
/// 注意：不再使用 AutomaticKeepAliveClientMixin，让不在视野内的组件可以被回收。
/// StreamImage 有内存缓存，所以重新创建时可以快速从缓存获取图片数据。
class _LazyPosterCard extends ConsumerWidget {
  const _LazyPosterCard({
    required this.metadata,
    required this.onTap,
    required this.isDark,
    super.key,
    this.width = 130,
    this.showMargin = true,
  });

  final VideoMetadata metadata;
  final VoidCallback onTap;
  final bool isDark;
  final double width;
  final bool showMargin;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _VerticalPosterCard(
    metadata: metadata,
    onTap: onTap,
    isDark: isDark,
    width: width,
    showMargin: showMargin,
  );
}

/// 纵向海报卡片（2:3 比例，Netflix 风格）
class _VerticalPosterCard extends ConsumerStatefulWidget {
  const _VerticalPosterCard({
    required this.metadata,
    required this.onTap,
    required this.isDark,
    this.width = 130,
    this.onContextMenu,
    this.showMargin = true,
  });

  final VideoMetadata metadata;
  final VoidCallback onTap;
  final bool isDark;
  final double width;
  final void Function(VideoMetadata metadata)? onContextMenu;

  /// 是否显示右边距（用于水平滚动列表，GridView 不需要）
  final bool showMargin;

  @override
  ConsumerState<_VerticalPosterCard> createState() =>
      _VerticalPosterCardState();
}

class _VerticalPosterCardState extends ConsumerState<_VerticalPosterCard> {
  bool _isHovered = false;

  // 缓存图片 URL 避免重复计算
  late String? _posterUrl;
  late bool _hasPoster;

  @override
  void initState() {
    super.initState();
    _updatePosterUrl();
  }

  @override
  void didUpdateWidget(covariant _VerticalPosterCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当 metadata 变化时更新海报 URL
    if (oldWidget.metadata.displayPosterUrl !=
        widget.metadata.displayPosterUrl) {
      _updatePosterUrl();
    }
  }

  void _updatePosterUrl() {
    _posterUrl = widget.metadata.displayPosterUrl;
    _hasPoster = _posterUrl != null && _posterUrl!.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    // 获取播放进度
    final progressAsync = ref.watch(allVideoProgressProvider);
    final progress = progressAsync.valueOrNull?[widget.metadata.filePath];
    final hasProgress =
        progress != null &&
        progress.progressPercent > 0.02 &&
        progress.progressPercent < 0.98;

    // 2:3 海报比例
    final posterHeight = widget.width * 1.5;

    return Container(
      width: widget.width,
      margin: widget.showMargin ? const EdgeInsets.only(right: 12) : null,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          onLongPress: widget.onContextMenu != null
              ? () => widget.onContextMenu!(widget.metadata)
              : null,
          onSecondaryTap: widget.onContextMenu != null
              ? () => widget.onContextMenu!(widget.metadata)
              : null,
          child: AnimatedScale(
            scale: _isHovered ? 1.05 : 1.0,
            duration: const Duration(milliseconds: 150),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 海报图片容器
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: widget.width,
                  height: posterHeight,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: _isHovered ? 0.4 : 0.2,
                        ),
                        blurRadius: _isHovered ? 16 : 8,
                        offset: Offset(0, _isHovered ? 8 : 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // 海报图片 - 使用 VideoPoster 支持 NAS 路径
                        RepaintBoundary(
                          child: _hasPoster
                              ? VideoPoster(
                                  key: ValueKey(_posterUrl),
                                  posterUrl: _posterUrl,
                                  sourceId: widget.metadata.sourceId,
                                  placeholder: _buildPlaceholder(),
                                  errorWidget: _buildPlaceholder(),
                                )
                              : _buildPlaceholder(),
                        ),

                        // 渐变遮罩（底部）- 静态，不需要重建
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: IgnorePointer(
                            child: Container(
                              height: 60,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withValues(alpha: 0.7),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                        // 播放进度条
                        if (hasProgress)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: IgnorePointer(
                              child: Container(
                                height: 3,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  borderRadius: const BorderRadius.only(
                                    bottomLeft: Radius.circular(8),
                                    bottomRight: Radius.circular(8),
                                  ),
                                ),
                                child: FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: progress.progressPercent.clamp(
                                    0.0,
                                    1.0,
                                  ),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      borderRadius: BorderRadius.only(
                                        bottomLeft: const Radius.circular(8),
                                        bottomRight:
                                            progress.progressPercent > 0.95
                                            ? const Radius.circular(8)
                                            : Radius.zero,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                        // 评分徽章
                        if (widget.metadata.rating != null &&
                            widget.metadata.rating! > 0)
                          Positioned(
                            top: 6,
                            right: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _getRatingColor(),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.star_rounded,
                                    size: 10,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    widget.metadata.ratingText,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                        // 剧集标记
                        if (widget.metadata.category == MediaCategory.tvShow)
                          Positioned(
                            top: 6,
                            left: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.accent.withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                widget.metadata.seasonNumber != null
                                    ? 'S${widget.metadata.seasonNumber}'
                                    : '剧集',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),

                        // 继续观看标记
                        if (hasProgress)
                          Positioned(
                            bottom: 8,
                            left: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.play_arrow_rounded,
                                    size: 10,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    '${(progress.progressPercent * 100).toInt()}%',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                        // 悬停边框 - 使用 AnimatedOpacity 避免重建
                        Positioned.fill(
                          child: IgnorePointer(
                            child: AnimatedOpacity(
                              opacity: _isHovered ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 150),
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: AppColors.primary,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // 标题
                const SizedBox(height: 8),
                Text(
                  widget.metadata.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: widget.isDark ? Colors.white : Colors.black87,
                  ),
                ),
                // 年份
                if (widget.metadata.year != null)
                  Text(
                    '${widget.metadata.year}',
                    style: TextStyle(
                      fontSize: 10,
                      color: widget.isDark
                          ? Colors.grey[500]
                          : Colors.grey[600],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() => Container(
    color: widget.isDark
        ? AppColors.darkSurfaceVariant
        : AppColors.lightSurfaceVariant,
    child: Center(
      child: Icon(
        widget.metadata.category == MediaCategory.tvShow
            ? Icons.live_tv_rounded
            : Icons.movie_rounded,
        size: 40,
        color: widget.isDark ? Colors.grey[600] : Colors.grey[400],
      ),
    ),
  );

  Color _getRatingColor() => AppColors.ratingColor(widget.metadata.rating ?? 0);
}

/// 横向视频卡片（适合视频缩略图 16:9）
class _HorizontalVideoCard extends ConsumerStatefulWidget {
  const _HorizontalVideoCard({
    required this.metadata,
    required this.onTap,
    required this.isDark,
    this.onContextMenu,
  });

  final VideoMetadata metadata;
  final VoidCallback onTap;
  final bool isDark;
  final void Function(VideoMetadata metadata)? onContextMenu;

  @override
  ConsumerState<_HorizontalVideoCard> createState() =>
      _HorizontalVideoCardState();
}

class _HorizontalVideoCardState extends ConsumerState<_HorizontalVideoCard> {
  bool _isHovered = false;

  // 缓存图片 URL 避免重复计算
  late String? _posterUrl;
  late bool _hasPoster;

  @override
  void initState() {
    super.initState();
    _updatePosterUrl();
  }

  @override
  void didUpdateWidget(covariant _HorizontalVideoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.metadata.displayPosterUrl !=
        widget.metadata.displayPosterUrl) {
      _updatePosterUrl();
    }
  }

  void _updatePosterUrl() {
    _posterUrl = widget.metadata.displayPosterUrl;
    _hasPoster = _posterUrl != null && _posterUrl!.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    // 获取播放进度
    final progressAsync = ref.watch(allVideoProgressProvider);
    final progress = progressAsync.valueOrNull?[widget.metadata.filePath];
    final hasProgress =
        progress != null &&
        progress.progressPercent > 0.02 &&
        progress.progressPercent < 0.98;

    return Container(
      width: 220,
      margin: const EdgeInsets.only(right: 12),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          onLongPress: widget.onContextMenu != null
              ? () => widget.onContextMenu!(widget.metadata)
              : null,
          onSecondaryTap: widget.onContextMenu != null
              ? () => widget.onContextMenu!(widget.metadata)
              : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            transform: Matrix4.identity()
              ..scaleByDouble(
                _isHovered ? 1.03 : 1.0,
                _isHovered ? 1.03 : 1.0,
                1,
                1,
              ),
            transformAlignment: Alignment.center,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 视频缩略图（16:9 比例）
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: _isHovered ? 0.35 : 0.2,
                          ),
                          blurRadius: _isHovered ? 12 : 6,
                          offset: Offset(0, _isHovered ? 6 : 3),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // 缩略图 - 使用 VideoPoster 支持 NAS 路径
                          RepaintBoundary(
                            child: _hasPoster
                                ? VideoPoster(
                                    key: ValueKey(_posterUrl),
                                    posterUrl: _posterUrl,
                                    sourceId: widget.metadata.sourceId,
                                    placeholder: _buildPlaceholder(),
                                    errorWidget: _buildPlaceholder(),
                                  )
                                : _buildPlaceholder(),
                          ),

                          // 渐变遮罩（底部）
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: IgnorePointer(
                              child: Container(
                                height: 40,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      Colors.black.withValues(alpha: 0.7),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // 播放进度条
                          if (hasProgress)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: Container(
                                height: 3,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  borderRadius: const BorderRadius.only(
                                    bottomLeft: Radius.circular(10),
                                    bottomRight: Radius.circular(10),
                                  ),
                                ),
                                child: FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: progress.progressPercent.clamp(
                                    0.0,
                                    1.0,
                                  ),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      borderRadius: BorderRadius.only(
                                        bottomLeft: const Radius.circular(10),
                                        bottomRight:
                                            progress.progressPercent > 0.95
                                            ? const Radius.circular(10)
                                            : Radius.zero,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                          // 时长或进度标签
                          Positioned(
                            bottom: 6,
                            right: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                hasProgress
                                    ? '${(progress.progressPercent * 100).toInt()}%'
                                    : (widget.metadata.runtime != null
                                          ? '${widget.metadata.runtime}分钟'
                                          : ''),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),

                          // 评分徽章
                          if (widget.metadata.rating != null &&
                              widget.metadata.rating! > 0)
                            Positioned(
                              top: 6,
                              left: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _getRatingColor(),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.star_rounded,
                                      size: 10,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      widget.metadata.ratingText,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          // 剧集标记
                          if (widget.metadata.category == MediaCategory.tvShow)
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.accent,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  widget.metadata.seasonNumber != null
                                      ? 'S${widget.metadata.seasonNumber}'
                                      : '剧集',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),

                          // 悬停边框 - 使用 AnimatedOpacity 避免重建
                          Positioned.fill(
                            child: IgnorePointer(
                              child: AnimatedOpacity(
                                opacity: _isHovered ? 1.0 : 0.0,
                                duration: const Duration(milliseconds: 150),
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: AppColors.primary,
                                      width: 2,
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // 标题和年份
                const SizedBox(height: 6),
                Text(
                  widget.metadata.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: widget.isDark ? Colors.white : null,
                  ),
                ),
                if (widget.metadata.year != null)
                  Text(
                    '${widget.metadata.year}',
                    style: TextStyle(
                      fontSize: 10,
                      color: widget.isDark
                          ? Colors.grey[500]
                          : Colors.grey[600],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() => Container(
    color: widget.isDark
        ? AppColors.darkSurfaceVariant
        : AppColors.lightSurfaceVariant,
    child: Center(
      child: Icon(
        widget.metadata.category == MediaCategory.tvShow
            ? Icons.live_tv_rounded
            : Icons.movie_rounded,
        size: 36,
        color: widget.isDark ? Colors.grey[600] : Colors.grey[400],
      ),
    ),
  );

  Color _getRatingColor() => AppColors.ratingColor(widget.metadata.rating ?? 0);
}

/// 排序方式枚举
enum _SortType {
  rating, // 按评分
  year, // 按年份
  name, // 按名称
  recent, // 按添加时间
}

/// 分类全部页面（带排序筛选）
class _CategoryFullPage extends ConsumerStatefulWidget {
  const _CategoryFullPage({required this.title, required this.items});

  final String title;
  final List<VideoMetadata> items;

  @override
  ConsumerState<_CategoryFullPage> createState() => _CategoryFullPageState();
}

class _CategoryFullPageState extends ConsumerState<_CategoryFullPage> {
  // 默认按年份降序排序（最近上映的排在前面）
  _SortType _sortType = _SortType.year;
  bool _sortDescending = true;
  String? _selectedGenre;
  List<String> _availableGenres = [];

  @override
  void initState() {
    super.initState();
    _extractGenres();
  }

  /// 提取所有可用的类型标签
  void _extractGenres() {
    final genreSet = <String>{};
    for (final item in widget.items) {
      if (item.genres != null && item.genres!.isNotEmpty) {
        // 分割类型字符串（可能是 "动作 / 科幻" 格式）
        final genres = item.genres!
            .split(RegExp('[/,、]'))
            .map((g) => g.trim())
            .where((g) => g.isNotEmpty);
        genreSet.addAll(genres);
      }
    }
    _availableGenres = genreSet.toList()..sort();
  }

  /// 获取排序和筛选后的列表
  List<VideoMetadata> get _sortedAndFilteredItems {
    var result = widget.items.toList();

    // 筛选
    if (_selectedGenre != null) {
      result = result.where((item) {
        if (item.genres == null) return false;
        return item.genres!.contains(_selectedGenre!);
      }).toList();
    }

    // 排序
    result.sort((a, b) {
      int comparison;
      switch (_sortType) {
        case _SortType.rating:
          comparison = (a.rating ?? 0).compareTo(b.rating ?? 0);
        case _SortType.year:
          comparison = (a.year ?? 0).compareTo(b.year ?? 0);
        case _SortType.name:
          comparison = a.displayTitle.compareTo(b.displayTitle);
        case _SortType.recent:
          // 默认顺序就是最近添加
          comparison = 0;
      }
      return _sortDescending ? -comparison : comparison;
    });

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 600;

    // 使用 GridHelper 计算网格配置
    final gridConfig = GridHelper.getPosterGridConfig(context);
    final filteredItems = _sortedAndFilteredItems;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D0D0D) : Colors.grey[50],
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1A1A2E) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_rounded,
            color: isDark ? Colors.white : Colors.black87,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        actions: [
          // 排序按钮
          IconButton(
            icon: Icon(
              Icons.swap_vert_rounded,
              color: isDark ? Colors.white : Colors.black87,
            ),
            onPressed: () => _showSortOptions(context, isDark),
            tooltip: '排序',
          ),
          // 筛选按钮（如果有类型可选）
          if (_availableGenres.isNotEmpty)
            IconButton(
              icon: Badge(
                isLabelVisible: _selectedGenre != null,
                child: Icon(
                  Icons.filter_alt_rounded,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              onPressed: () => _showFilterOptions(context, isDark),
              tooltip: '筛选',
            ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '${filteredItems.length} 部',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 排序和筛选状态栏
          _buildStatusBar(isDark, isWide),
          // 内容区域
          Expanded(
            child: filteredItems.isEmpty
                ? _buildEmptyState(isDark)
                : GridView.builder(
                    padding: gridConfig.padding,
                    // 限制预加载区域，减少内存占用和初始加载时间
                    cacheExtent: 200,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: gridConfig.crossAxisCount,
                      childAspectRatio: gridConfig.childAspectRatio,
                      mainAxisSpacing: gridConfig.mainAxisSpacing,
                      crossAxisSpacing: gridConfig.crossAxisSpacing,
                    ),
                    itemCount: filteredItems.length,
                    itemBuilder: (context, index) {
                      final metadata = filteredItems[index];
                      final itemWidth = GridHelper.calculateItemSize(context, gridConfig).width;
                      return _LazyPosterCard(
                        key: ValueKey(metadata.uniqueKey),
                        metadata: metadata,
                        onTap: () => _openVideoDetail(context, metadata),
                        isDark: isDark,
                        width: itemWidth,
                        showMargin: false,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// 构建状态栏（仅在有筛选条件时显示）
  Widget _buildStatusBar(bool isDark, bool isWide) {
    // 只有在有筛选条件时才显示状态栏
    if (_selectedGenre == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.black26 : Colors.grey[100],
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppColors.darkOutline : AppColors.lightOutline,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            '筛选: ',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
          // 筛选标签
          _buildChip(
            label: _selectedGenre!,
            icon: Icons.local_movies_rounded,
            isDark: isDark,
            isActive: true,
            onTap: () => setState(() => _selectedGenre = null),
            onClose: () => setState(() => _selectedGenre = null),
          ),
        ],
      ),
    );
  }

  /// 构建标签
  Widget _buildChip({
    required String label,
    required IconData icon,
    required bool isDark,
    bool isActive = false,
    VoidCallback? onTap,
    VoidCallback? onClose,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isActive
            ? AppColors.primary.withValues(alpha: 0.2)
            : (isDark ? Colors.grey[800] : Colors.white),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive
              ? AppColors.primary
              : (isDark ? Colors.grey[700]! : Colors.grey[300]!),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: isActive
                ? AppColors.primary
                : (isDark ? Colors.grey[400] : Colors.grey[600]),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isActive
                  ? AppColors.primary
                  : (isDark ? Colors.grey[300] : Colors.grey[700]),
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          if (onClose != null) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onClose,
              child: Icon(
                Icons.close_rounded,
                size: 14,
                color: AppColors.primary,
              ),
            ),
          ],
        ],
      ),
    ),
  );

  /// 空状态
  Widget _buildEmptyState(bool isDark) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.filter_list_off_rounded,
          size: 64,
          color: isDark ? Colors.grey[600] : Colors.grey[400],
        ),
        const SizedBox(height: 16),
        Text(
          '没有符合筛选条件的内容',
          style: TextStyle(
            fontSize: 16,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() => _selectedGenre = null),
          child: const Text('清除筛选'),
        ),
      ],
    ),
  );

  /// 显示排序选项
  void _showSortOptions(BuildContext context, bool isDark) async {
    // 检查是否为玻璃模式
    final container = ProviderScope.containerOf(context);
    final uiStyle = container.read(uiStyleProvider);

    if (uiStyle.isGlass) {
      // 玻璃模式使用原生 iOS sheet
      final items = [
        ListSheetItem<_SortType>(
          title: '按评分',
          icon: Icons.star_rounded,
          value: _SortType.rating,
          isSelected: _sortType == _SortType.rating,
        ),
        ListSheetItem<_SortType>(
          title: '按年份',
          icon: Icons.calendar_today_rounded,
          value: _SortType.year,
          isSelected: _sortType == _SortType.year,
        ),
        ListSheetItem<_SortType>(
          title: '按名称',
          icon: Icons.sort_by_alpha_rounded,
          value: _SortType.name,
          isSelected: _sortType == _SortType.name,
        ),
        ListSheetItem<_SortType>(
          title: '按添加时间',
          icon: Icons.schedule_rounded,
          value: _SortType.recent,
          isSelected: _sortType == _SortType.recent,
        ),
      ];

      final result = await showNativeListSheet<_SortType>(
        context: context,
        items: items,
        title: '排序方式',
      );

      if (result != null) {
        setState(() {
          if (_sortType == result) {
            _sortDescending = !_sortDescending;
          } else {
            _sortType = result;
            _sortDescending = true;
          }
        });
      }
      return;
    }

    // 经典模式使用 Flutter 底部弹框
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1A1A2E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 拖拽指示器
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[600] : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '排序方式',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
            // 排序选项
            _buildSortOption(
              context,
              icon: Icons.star_rounded,
              label: '按评分',
              type: _SortType.rating,
              isDark: isDark,
            ),
            _buildSortOption(
              context,
              icon: Icons.calendar_today_rounded,
              label: '按年份',
              type: _SortType.year,
              isDark: isDark,
            ),
            _buildSortOption(
              context,
              icon: Icons.sort_by_alpha_rounded,
              label: '按名称',
              type: _SortType.name,
              isDark: isDark,
            ),
            _buildSortOption(
              context,
              icon: Icons.schedule_rounded,
              label: '按添加时间',
              type: _SortType.recent,
              isDark: isDark,
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// 构建排序选项
  Widget _buildSortOption(
    BuildContext context, {
    required IconData icon,
    required String label,
    required _SortType type,
    required bool isDark,
  }) {
    final isSelected = _sortType == type;

    return ListTile(
      leading: Icon(
        icon,
        color: isSelected
            ? AppColors.primary
            : (isDark ? Colors.grey[400] : Colors.grey[600]),
      ),
      title: Text(
        label,
        style: TextStyle(
          color: isSelected
              ? AppColors.primary
              : (isDark ? Colors.white : Colors.black87),
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: isSelected
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 升序/降序切换
                IconButton(
                  icon: Icon(
                    _sortDescending
                        ? Icons.arrow_downward_rounded
                        : Icons.arrow_upward_rounded,
                    color: AppColors.primary,
                  ),
                  onPressed: () {
                    setState(() => _sortDescending = !_sortDescending);
                    Navigator.pop(context);
                  },
                ),
                Icon(Icons.check_rounded, color: AppColors.primary),
              ],
            )
          : null,
      onTap: () {
        setState(() {
          if (_sortType == type) {
            _sortDescending = !_sortDescending;
          } else {
            _sortType = type;
            _sortDescending = true;
          }
        });
        Navigator.pop(context);
      },
    );
  }

  /// 显示筛选选项
  void _showFilterOptions(BuildContext context, bool isDark) async {
    // 检查是否为玻璃模式
    final container = ProviderScope.containerOf(context);
    final uiStyle = container.read(uiStyleProvider);

    if (uiStyle.isGlass) {
      // 玻璃模式使用原生 iOS sheet
      final items = _availableGenres.map((genre) {
        final count = widget.items
            .where((item) => item.genres?.contains(genre) ?? false)
            .length;
        return ListSheetItem<String>(
          title: '$genre ($count)',
          icon: Icons.local_movies_rounded,
          value: genre,
          isSelected: _selectedGenre == genre,
        );
      }).toList();

      // 添加"清除筛选"选项
      if (_selectedGenre != null) {
        items.insert(
          0,
          ListSheetItem<String>(
            title: '清除筛选',
            icon: Icons.clear_all_rounded,
            value: '',
            isSelected: false,
          ),
        );
      }

      final result = await showNativeListSheet<String>(
        context: context,
        items: items,
        title: '按类型筛选',
      );

      if (result != null) {
        setState(() {
          _selectedGenre = result.isEmpty ? null : result;
        });
      }
      return;
    }

    // 经典模式使用 Flutter 底部弹框
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1A1A2E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (context, scrollController) => SafeArea(
          child: Column(
            children: [
              // 拖拽指示器
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[600] : Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Text(
                      '按类型筛选',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const Spacer(),
                    if (_selectedGenre != null)
                      TextButton(
                        onPressed: () {
                          setState(() => _selectedGenre = null);
                          Navigator.pop(context);
                        },
                        child: const Text('清除'),
                      ),
                  ],
                ),
              ),
              // 类型列表
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: _availableGenres.length,
                  itemBuilder: (context, index) {
                    final genre = _availableGenres[index];
                    final isSelected = _selectedGenre == genre;
                    final count = widget.items
                        .where((item) => item.genres?.contains(genre) ?? false)
                        .length;

                    return ListTile(
                      leading: Icon(
                        Icons.local_movies_rounded,
                        color: isSelected
                            ? AppColors.primary
                            : (isDark ? Colors.grey[400] : Colors.grey[600]),
                      ),
                      title: Text(
                        genre,
                        style: TextStyle(
                          color: isSelected
                              ? AppColors.primary
                              : (isDark ? Colors.white : Colors.black87),
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.grey[800]
                                  : Colors.grey[200],
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$count',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                              ),
                            ),
                          ),
                          if (isSelected) ...[
                            const SizedBox(width: 8),
                            Icon(Icons.check_rounded, color: AppColors.primary),
                          ],
                        ],
                      ),
                      onTap: () {
                        setState(() {
                          _selectedGenre = isSelected ? null : genre;
                        });
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openVideoDetail(
    BuildContext context,
    VideoMetadata metadata,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) =>
            VideoDetailPage(metadata: metadata, sourceId: metadata.sourceId),
      ),
    );
    ref.invalidate(continueWatchingProvider);
  }
}

/// 剧集行组件（显示季集统计）
class _TvShowRow extends StatelessWidget {
  const _TvShowRow({
    required this.title,
    required this.groups,
    required this.onGroupTap,
    required this.isDark,
    this.icon,
    this.iconColor,
    // ignore: unused_element_parameter
    this.maxCount = 10,
    this.onViewAll,
    this.totalCount,
  });

  final String title;
  final List<TvShowGroup> groups;
  final void Function(TvShowGroup) onGroupTap;
  final bool isDark;
  final IconData? icon;
  final Color? iconColor;
  final int maxCount;
  final VoidCallback? onViewAll;

  /// 实际总数量（用于显示在"查看全部"按钮上，如果不传则使用 groups.length）
  final int? totalCount;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) return const SizedBox.shrink();

    final displayGroups = groups.take(maxCount).toList();
    final showViewMore = onViewAll != null;
    // 使用真实总数（如果提供），否则使用 groups.length
    final actualTotalCount = totalCount ?? groups.length;
    final remainingCount = actualTotalCount > maxCount
        ? actualTotalCount - maxCount
        : 0;
    final effectiveIconColor = iconColor ?? AppColors.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题栏
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Row(
            children: [
              if (icon != null) ...[
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: effectiveIconColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 18, color: effectiveIconColor),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              if (showViewMore)
                TextButton(
                  onPressed: onViewAll,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '查看全部 ($actualTotalCount)',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 12,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        // 内容滚动区域
        SizedBox(
          height: 240,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            // 预构建更多屏幕外的 item，让图片提前开始加载
            cacheExtent: 500,
            itemCount: displayGroups.length + (showViewMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (showViewMore && index == displayGroups.length) {
                return _ViewMoreCard(
                  onTap: onViewAll,
                  isDark: isDark,
                  remainingCount: remainingCount,
                  totalCount: groups.length,
                );
              }

              final group = displayGroups[index];
              return _TvShowPosterCard(
                group: group,
                onTap: () => onGroupTap(group),
                isDark: isDark,
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 剧集海报卡片（显示季数和集数）
class _TvShowPosterCard extends StatefulWidget {
  const _TvShowPosterCard({
    required this.group,
    required this.onTap,
    required this.isDark,
    // ignore: unused_element_parameter
    this.width = 130,
    this.showMargin = true,
  });

  final TvShowGroup group;
  final VoidCallback onTap;
  final bool isDark;
  final double width;

  /// 是否显示右边距（用于水平滚动列表，GridView 不需要）
  final bool showMargin;

  @override
  State<_TvShowPosterCard> createState() => _TvShowPosterCardState();
}

class _TvShowPosterCardState extends State<_TvShowPosterCard> {
  bool _isHovered = false;

  late String? _posterUrl;
  late bool _hasPoster;

  @override
  void initState() {
    super.initState();
    _updatePosterUrl();
  }

  @override
  void didUpdateWidget(covariant _TvShowPosterCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.group.displayPosterUrl != widget.group.displayPosterUrl) {
      _updatePosterUrl();
    }
  }

  void _updatePosterUrl() {
    _posterUrl = widget.group.displayPosterUrl;
    _hasPoster = _posterUrl != null && _posterUrl!.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final posterHeight = widget.width * 1.5;

    return Container(
      width: widget.width,
      margin: widget.showMargin ? const EdgeInsets.only(right: 12) : null,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _isHovered ? 1.05 : 1.0,
            duration: const Duration(milliseconds: 150),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 海报图片容器
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: widget.width,
                  height: posterHeight,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: _isHovered ? 0.4 : 0.2,
                        ),
                        blurRadius: _isHovered ? 16 : 8,
                        offset: Offset(0, _isHovered ? 8 : 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // 海报图片（使用 VideoPoster 支持 NAS 路径）
                        RepaintBoundary(
                          child: _hasPoster
                              ? VideoPoster(
                                  key: ValueKey(_posterUrl),
                                  posterUrl: _posterUrl,
                                  sourceId:
                                      widget.group.representative.sourceId,
                                  placeholder: _buildPlaceholder(),
                                  errorWidget: _buildPlaceholder(),
                                )
                              : _buildPlaceholder(),
                        ),

                        // 渐变遮罩
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: IgnorePointer(
                            child: Container(
                              height: 60,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withValues(alpha: 0.7),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                        // 评分徽章
                        if (widget.group.rating != null &&
                            widget.group.rating! > 0)
                          Positioned(
                            top: 6,
                            right: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _getRatingColor(),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.star_rounded,
                                    size: 10,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    widget.group.rating!.toStringAsFixed(1),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                        // 季集统计徽章（左上角）
                        Positioned(
                          top: 6,
                          left: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _getSeasonEpisodeText(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),

                        // 悬停边框
                        Positioned.fill(
                          child: IgnorePointer(
                            child: AnimatedOpacity(
                              opacity: _isHovered ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 150),
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: AppColors.primary,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // 标题
                const SizedBox(height: 8),
                Text(
                  widget.group.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: widget.isDark ? Colors.white : Colors.black87,
                  ),
                ),
                // 年份和季集信息
                Text(
                  _getSubtitleText(),
                  style: TextStyle(
                    fontSize: 10,
                    color: widget.isDark ? Colors.grey[500] : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getSeasonEpisodeText() {
    final seasonCount = widget.group.seasonCount;
    final episodeCount = widget.group.episodeCount;

    if (seasonCount > 1) {
      return '$seasonCount季 $episodeCount集';
    } else if (seasonCount == 1) {
      return '$episodeCount集';
    } else {
      return '$episodeCount集';
    }
  }

  String _getSubtitleText() {
    final parts = <String>[];
    if (widget.group.year != null) {
      parts.add('${widget.group.year}');
    }

    final seasonCount = widget.group.seasonCount;
    final episodeCount = widget.group.episodeCount;
    if (seasonCount > 1) {
      parts.add('$seasonCount季');
    }
    parts.add('$episodeCount集');

    return parts.join(' · ');
  }

  Widget _buildPlaceholder() => Container(
    color: widget.isDark
        ? AppColors.darkSurfaceVariant
        : AppColors.lightSurfaceVariant,
    child: Center(
      child: Icon(
        Icons.live_tv_rounded,
        size: 40,
        color: widget.isDark ? Colors.grey[600] : Colors.grey[400],
      ),
    ),
  );

  Color _getRatingColor() => AppColors.ratingColor(widget.group.rating ?? 0);
}

/// 剧集列表全页面
class _TvShowsFullPage extends ConsumerStatefulWidget {
  const _TvShowsFullPage({required this.title, required this.groups});

  final String title;
  final List<TvShowGroup> groups;

  @override
  ConsumerState<_TvShowsFullPage> createState() => _TvShowsFullPageState();
}

class _TvShowsFullPageState extends ConsumerState<_TvShowsFullPage>
    with ConsumerTabBarVisibilityMixin {
  @override
  void initState() {
    super.initState();
    hideTabBar();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D0D0D) : Colors.grey[50],
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: isDark ? const Color(0xFF0D0D0D) : Colors.grey[50],
        elevation: 0,
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 150,
          childAspectRatio: 0.55,
          crossAxisSpacing: 12,
          mainAxisSpacing: 16,
        ),
        itemCount: widget.groups.length,
        itemBuilder: (context, index) {
          final group = widget.groups[index];
          return _TvShowPosterCard(
            group: group,
            onTap: () => _openVideoDetail(context, group.representative),
            isDark: isDark,
            showMargin: false,
          );
        },
      ),
    );
  }

  Future<void> _openVideoDetail(
    BuildContext context,
    VideoMetadata metadata,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) =>
            VideoDetailPage(metadata: metadata, sourceId: metadata.sourceId),
      ),
    );
  }
}

/// 电影分页页面（支持懒加载和筛选）
class _MoviesPaginatedPage extends ConsumerStatefulWidget {
  const _MoviesPaginatedPage({required this.title});

  final String title;

  @override
  ConsumerState<_MoviesPaginatedPage> createState() =>
      _MoviesPaginatedPageState();
}

class _MoviesPaginatedPageState extends ConsumerState<_MoviesPaginatedPage>
    with ConsumerTabBarVisibilityMixin {
  final List<VideoMetadata> _movies = [];
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  bool _hasMore = true;
  int _offset = 0;
  static const int _pageSize = 50;

  // 筛选相关
  List<String> _availableGenres = [];
  List<int> _availableYears = [];
  String? _selectedGenre;
  int? _selectedYear;
  int _filteredCount = 0;
  bool _isLoadingFilters = true;

  // 排序相关（默认按上映年份降序排序）
  VideoSortOption _sortOption = VideoSortOption.yearDesc;

  @override
  void initState() {
    super.initState();
    // 隐藏底部导航栏
    hideTabBar();
    _loadFilters();
    _loadMore();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    // 显示底部导航栏
    // Mixin 自动处理恢复
    super.dispose();
  }

  Future<void> _loadFilters() async {
    try {
      final db = VideoDatabaseService();
      final genres = await db.getAvailableGenres(category: MediaCategory.movie);
      final years = await db.getAvailableYears(category: MediaCategory.movie);
      final count = await db.getFilteredCount(category: MediaCategory.movie);

      if (mounted) {
        setState(() {
          _availableGenres = genres;
          _availableYears = years;
          _filteredCount = count;
          _isLoadingFilters = false;
        });
      }
    } on Exception catch (e) {
      logger.e('VideoListPage: 加载筛选失败', e);
      if (mounted) {
        setState(() => _isLoadingFilters = false);
      }
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || !_hasMore || !mounted) return;

    setState(() => _isLoading = true);

    try {
      final db = VideoDatabaseService();
      final newMovies = await db.getFiltered(
        category: MediaCategory.movie,
        genre: _selectedGenre,
        year: _selectedYear,
        sortOption: _sortOption,
        offset: _offset,
      );

      if (!mounted) return;

      setState(() {
        _movies.addAll(newMovies);
        _offset += newMovies.length;
        _hasMore = newMovies.length >= _pageSize;
        _isLoading = false;
      });
    } on Exception catch (e) {
      logger.e('VideoListPage: 加载更多失败', e);
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _resetAndReload() async {
    if (!mounted) return;
    setState(() {
      _movies.clear();
      _offset = 0;
      _hasMore = true;
    });

    // 更新筛选后的数量
    try {
      final db = VideoDatabaseService();
      final count = await db.getFilteredCount(
        category: MediaCategory.movie,
        genre: _selectedGenre,
        year: _selectedYear,
      );
      if (mounted) {
        setState(() => _filteredCount = count);
      }
    } on Exception catch (e) {
      logger.e('VideoListPage: 更新筛选后数量失败', e);
      // 忽略错误
    }

    await _loadMore();
  }

  void _showFilterSheet(BuildContext context, bool isDark) async {
    final uiStyle = ref.read(uiStyleProvider);

    // 玻璃模式使用原生筛选弹框
    if (uiStyle.isGlass) {
      // 构建筛选分区
      final sections = <FilterSection>[
        FilterSection(
          id: 'genre',
          title: '类型',
          items: _availableGenres
              .map((g) => FilterItem(value: g, title: g))
              .toList(),
        ),
        FilterSection(
          id: 'year',
          title: '年份',
          items: _availableYears
              .map((y) => FilterItem(value: y.toString(), title: y.toString()))
              .toList(),
        ),
      ];

      final initialValues = <String, String>{};
      if (_selectedGenre != null) initialValues['genre'] = _selectedGenre!;
      if (_selectedYear != null) initialValues['year'] = _selectedYear.toString();

      final result = await showNativeFilterSheet(
        context: context,
        sections: sections,
        title: '筛选',
        initialSelectedValues: initialValues,
      );

      if (result != null) {
        final genre = result.getSelected('genre');
        final yearStr = result.getSelected('year');
        final year = yearStr != null ? int.tryParse(yearStr) : null;

        if (genre != _selectedGenre || year != _selectedYear) {
          setState(() {
            _selectedGenre = genre;
            _selectedYear = year;
          });
          _resetAndReload();
        }
      }
      return;
    }

    // 经典模式使用 Flutter 底部弹框
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _FilterBottomSheet(
        isDark: isDark,
        availableGenres: _availableGenres,
        availableYears: _availableYears,
        selectedGenre: _selectedGenre,
        selectedYear: _selectedYear,
        onApply: (genre, year) {
          Navigator.of(context).pop();
          if (genre != _selectedGenre || year != _selectedYear) {
            setState(() {
              _selectedGenre = genre;
              _selectedYear = year;
            });
            _resetAndReload();
          }
        },
      ),
    );
  }

  bool get _hasFilters => _selectedGenre != null || _selectedYear != null;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final uiStyle = ref.watch(uiStyleProvider);
    final safeTop = MediaQuery.of(context).padding.top;

    // iOS 26 玻璃模式：使用悬浮头部
    if (uiStyle.isGlass) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF0D0D0D) : Colors.grey[50],
        body: Stack(
          children: [
            // 主内容区域
            _buildContent(context, isDark, safeTop + 60), // 留出头部空间
            // 悬浮按钮 - 左侧返回按钮
            Positioned(
              top: safeTop + 8,
              left: 16,
              child: const GlassFloatingBackButton(),
            ),
            // 悬浮按钮 - 右侧操作按钮
            Positioned(
              top: safeTop + 8,
              right: 16,
              child: GlassButtonGroup(
                children: [
                  GlassGroupIconButton(
                    icon: Icons.swap_vert_rounded,
                    tooltip: '排序',
                    onPressed: () => _showSortMenu(context, isDark),
                  ),
                  GlassGroupIconButton(
                    icon: Icons.filter_alt_rounded,
                    tooltip: '筛选',
                    onPressed: _isLoadingFilters
                        ? null
                        : () => _showFilterSheet(context, isDark),
                    // 显示筛选指示器
                    badge: _hasFilters,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // 经典模式：保留原有 AppBar
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D0D0D) : Colors.grey[50],
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1A1A2E) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_rounded,
            color: isDark ? Colors.white : Colors.black87,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          '${widget.title} ($_filteredCount)',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        actions: [
          // 排序按钮
          IconButton(
            icon: Icon(
              Icons.swap_vert_rounded,
              color: isDark ? Colors.white : Colors.black87,
            ),
            tooltip: '排序',
            onPressed: () => _showSortMenu(context, isDark),
          ),
          // 筛选按钮
          Stack(
            children: [
              IconButton(
                icon: Icon(
                  Icons.filter_alt_rounded,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                onPressed: _isLoadingFilters
                    ? null
                    : () => _showFilterSheet(context, isDark),
              ),
              if (_hasFilters)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: _buildContent(context, isDark, 0),
    );
  }

  /// 构建主内容区域 - 使用 CustomScrollView 让所有内容一起滚动
  Widget _buildContent(BuildContext context, bool isDark, double topPadding) {
    // 加载中状态
    if (_movies.isEmpty && _isLoading) {
      return Column(
        children: [
          if (topPadding > 0) SizedBox(height: topPadding),
          const Expanded(child: Center(child: CircularProgressIndicator())),
        ],
      );
    }

    // 空状态
    if (_movies.isEmpty) {
      return Column(
        children: [
          if (topPadding > 0) SizedBox(height: topPadding),
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.movie_filter_outlined,
                    size: 64,
                    color: isDark ? Colors.white30 : Colors.black26,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '没有找到匹配的电影',
                    style: TextStyle(
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // 有内容时：使用 CustomScrollView 让所有内容一起滚动
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final isMobile = screenWidth < 600;
        final maxExtent = isMobile ? 120.0 : 150.0;
        final aspectRatio = isMobile ? 0.48 : 0.52;
        final gridPadding = isMobile ? 12.0 : 16.0;

        return CustomScrollView(
          controller: _scrollController,
          slivers: [
            // 顶部留白（玻璃模式用于避开浮动头部）
            if (topPadding > 0)
              SliverToBoxAdapter(child: SizedBox(height: topPadding)),
            // 筛选标签
            if (_hasFilters)
              SliverToBoxAdapter(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (_selectedGenre != null)
                        _FilterChip(
                          label: _selectedGenre!,
                          onRemove: () {
                            setState(() => _selectedGenre = null);
                            _resetAndReload();
                          },
                          isDark: isDark,
                        ),
                      if (_selectedYear != null)
                        _FilterChip(
                          label: '$_selectedYear年',
                          onRemove: () {
                            setState(() => _selectedYear = null);
                            _resetAndReload();
                          },
                          isDark: isDark,
                        ),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedGenre = null;
                            _selectedYear = null;
                          });
                          _resetAndReload();
                        },
                        child: Text(
                          '清除全部',
                          style: TextStyle(fontSize: 12, color: Colors.blue),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // 排序标签
            if (_sortOption != VideoSortOption.yearDesc)
              SliverToBoxAdapter(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.swap_vert_rounded,
                        size: 14,
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '按${_sortOption.displayName}排序',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // 网格内容
            SliverPadding(
              padding: EdgeInsets.all(gridPadding),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: maxExtent,
                  childAspectRatio: aspectRatio,
                  crossAxisSpacing: isMobile ? 10 : 12,
                  mainAxisSpacing: isMobile ? 12 : 16,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index >= _movies.length) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    final movie = _movies[index];
                    return _VerticalPosterCard(
                      metadata: movie,
                      onTap: () => _openVideoDetail(context, movie),
                      isDark: isDark,
                      showMargin: false,
                    );
                  },
                  childCount: _movies.length + (_hasMore ? 1 : 0),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showSortMenu(BuildContext context, bool isDark) async {
    final uiStyle = ref.read(uiStyleProvider);
    
    // 玻璃模式使用原生 iOS sheet
    if (uiStyle.isGlass) {
      final items = VideoSortOption.values.map((option) {
        return ListSheetItem<VideoSortOption>(
          title: option.displayName,
          icon: option.icon,
          value: option,
          isSelected: option == _sortOption,
        );
      }).toList();

      final selected = await showNativeListSheet<VideoSortOption>(
        context: context,
        items: items,
        title: '排序方式',
        titleIcon: Icons.sort_rounded,
      );

      if (selected != null && selected != _sortOption) {
        setState(() => _sortOption = selected);
        _resetAndReload();
      }
      return;
    }

    // 经典模式使用 Flutter 底部弹框
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '排序方式',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
            const Divider(height: 1),
            ...VideoSortOption.values.map((option) {
              final isSelected = option == _sortOption;
              return ListTile(
                leading: Icon(
                  option.icon,
                  color: isSelected
                      ? Colors.blue
                      : (isDark ? Colors.white70 : Colors.black54),
                ),
                title: Text(
                  option.displayName,
                  style: TextStyle(
                    color: isSelected
                        ? Colors.blue
                        : (isDark ? Colors.white : Colors.black87),
                    fontWeight: isSelected ? FontWeight.bold : null,
                  ),
                ),
                trailing: isSelected
                    ? const Icon(Icons.check, color: Colors.blue)
                    : null,
                onTap: () {
                  Navigator.of(context).pop();
                  if (option != _sortOption) {
                    setState(() => _sortOption = option);
                    _resetAndReload();
                  }
                },
              );
            }),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
          ],
        ),
      ),
    );
  }

  Future<void> _openVideoDetail(
    BuildContext context,
    VideoMetadata metadata,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) =>
            VideoDetailPage(metadata: metadata, sourceId: metadata.sourceId),
      ),
    );
  }
}

/// 筛选标签
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.onRemove,
    required this.isDark,
  });

  final String label;
  final VoidCallback onRemove;
  final bool isDark;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: isDark
          ? Colors.white.withValues(alpha: 0.1)
          : Colors.black.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: isDark ? Colors.white24 : Colors.black12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: onRemove,
          child: Icon(
            Icons.close,
            size: 16,
            color: isDark ? Colors.white54 : Colors.black45,
          ),
        ),
      ],
    ),
  );
}

/// 筛选底部弹窗
class _FilterBottomSheet extends StatefulWidget {
  const _FilterBottomSheet({
    required this.isDark,
    required this.availableGenres,
    required this.availableYears,
    required this.selectedGenre,
    required this.selectedYear,
    required this.onApply,
  });

  final bool isDark;
  final List<String> availableGenres;
  final List<int> availableYears;
  final String? selectedGenre;
  final int? selectedYear;
  final void Function(String? genre, int? year) onApply;

  @override
  State<_FilterBottomSheet> createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends State<_FilterBottomSheet> {
  late String? _genre;
  late int? _year;

  @override
  void initState() {
    super.initState();
    _genre = widget.selectedGenre;
    _year = widget.selectedYear;
  }

  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.7,
    ),
    decoration: BoxDecoration(
      color: widget.isDark ? const Color(0xFF1A1A2E) : Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 拖动条
        Container(
          margin: const EdgeInsets.only(top: 12),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: widget.isDark ? Colors.white24 : Colors.black12,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        // 标题栏
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '筛选',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: widget.isDark ? Colors.white : Colors.black87,
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _genre = null;
                    _year = null;
                  });
                },
                child: const Text('重置'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // 筛选内容
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 类型筛选
                Text(
                  '类型',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: widget.isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: widget.availableGenres.map((genre) {
                    final isSelected = _genre == genre;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _genre = isSelected ? null : genre;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.blue
                              : widget.isDark
                              ? Colors.white.withValues(alpha: 0.1)
                              : Colors.black.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected
                                ? Colors.blue
                                : widget.isDark
                                ? Colors.white24
                                : Colors.black12,
                          ),
                        ),
                        child: Text(
                          genre,
                          style: TextStyle(
                            fontSize: 14,
                            color: isSelected
                                ? Colors.white
                                : widget.isDark
                                ? Colors.white
                                : Colors.black87,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
                // 年份筛选
                Text(
                  '年份',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: widget.isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: widget.availableYears.map((year) {
                    final isSelected = _year == year;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _year = isSelected ? null : year;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.blue
                              : widget.isDark
                              ? Colors.white.withValues(alpha: 0.1)
                              : Colors.black.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected
                                ? Colors.blue
                                : widget.isDark
                                ? Colors.white24
                                : Colors.black12,
                          ),
                        ),
                        child: Text(
                          '$year',
                          style: TextStyle(
                            fontSize: 14,
                            color: isSelected
                                ? Colors.white
                                : widget.isDark
                                ? Colors.white
                                : Colors.black87,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
        // 底部按钮
        Container(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.of(context).padding.bottom,
          ),
          decoration: BoxDecoration(
            color: widget.isDark ? const Color(0xFF1A1A2E) : Colors.white,
            border: Border(
              top: BorderSide(
                color: widget.isDark ? Colors.white12 : Colors.black12,
              ),
            ),
          ),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => widget.onApply(_genre, _year),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                '应用筛选',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// 剧集分页页面（支持懒加载和筛选）
class _TvShowsPaginatedPage extends ConsumerStatefulWidget {
  const _TvShowsPaginatedPage({required this.title});

  final String title;

  @override
  ConsumerState<_TvShowsPaginatedPage> createState() =>
      _TvShowsPaginatedPageState();
}

class _TvShowsPaginatedPageState extends ConsumerState<_TvShowsPaginatedPage>
    with ConsumerTabBarVisibilityMixin {
  final List<VideoMetadata> _tvShows = [];
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  bool _hasMore = true;
  int _offset = 0;
  static const int _pageSize = 50;

  // 筛选相关
  List<String> _availableGenres = [];
  List<int> _availableYears = [];
  String? _selectedGenre;
  int? _selectedYear;
  int _filteredCount = 0;
  bool _isLoadingFilters = true;

  // 排序相关（默认按上映年份降序排序）
  VideoSortOption _sortOption = VideoSortOption.yearDesc;

  @override
  void initState() {
    super.initState();
    // 隐藏底部导航栏
    hideTabBar();
    _loadFilters();
    _loadMore();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    // 显示底部导航栏
    // Mixin 自动处理恢复
    super.dispose();
  }

  Future<void> _loadFilters() async {
    try {
      final db = VideoDatabaseService();
      final genres = await db.getAvailableGenres(
        category: MediaCategory.tvShow,
      );
      final years = await db.getAvailableYears(category: MediaCategory.tvShow);
      final count = await db.getTvShowGroupCount();

      if (mounted) {
        setState(() {
          _availableGenres = genres;
          _availableYears = years;
          _filteredCount = count;
          _isLoadingFilters = false;
        });
      }
    } on Exception catch (e) {
      logger.e('TvShowsPaginatedPage: 加载筛选失败', e);
      if (mounted) {
        setState(() => _isLoadingFilters = false);
      }
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || !_hasMore || !mounted) return;

    setState(() => _isLoading = true);

    try {
      final db = VideoDatabaseService();
      final newTvShows = await db.getTvShowGroupRepresentativesFiltered(
        genre: _selectedGenre,
        year: _selectedYear,
        sortOption: _sortOption,
        offset: _offset,
      );

      if (!mounted) return;

      setState(() {
        _tvShows.addAll(newTvShows);
        _offset += newTvShows.length;
        _hasMore = newTvShows.length >= _pageSize;
        _isLoading = false;
      });
    } on Exception catch (e) {
      logger.e('TvShowsPaginatedPage: 加载更多失败', e);
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _resetAndReload() async {
    if (!mounted) return;
    setState(() {
      _tvShows.clear();
      _offset = 0;
      _hasMore = true;
    });

    // 更新筛选后的数量
    try {
      final db = VideoDatabaseService();
      final count = await db.getTvShowGroupCountFiltered(
        genre: _selectedGenre,
        year: _selectedYear,
      );
      if (mounted) {
        setState(() => _filteredCount = count);
      }
    } on Exception catch (e) {
      logger.w('TvShowsPaginatedPage: 更新筛选后数量失败', e);
      // 忽略错误
    }

    await _loadMore();
  }

  void _showFilterSheet(BuildContext context, bool isDark) async {
    final uiStyle = ref.read(uiStyleProvider);

    // 玻璃模式使用原生筛选弹框
    if (uiStyle.isGlass) {
      // 构建筛选分区
      final sections = <FilterSection>[
        FilterSection(
          id: 'genre',
          title: '类型',
          items: _availableGenres
              .map((g) => FilterItem(value: g, title: g))
              .toList(),
        ),
        FilterSection(
          id: 'year',
          title: '年份',
          items: _availableYears
              .map((y) => FilterItem(value: y.toString(), title: y.toString()))
              .toList(),
        ),
      ];

      final initialValues = <String, String>{};
      if (_selectedGenre != null) initialValues['genre'] = _selectedGenre!;
      if (_selectedYear != null) initialValues['year'] = _selectedYear.toString();

      final result = await showNativeFilterSheet(
        context: context,
        sections: sections,
        title: '筛选',
        initialSelectedValues: initialValues,
      );

      if (result != null) {
        final genre = result.getSelected('genre');
        final yearStr = result.getSelected('year');
        final year = yearStr != null ? int.tryParse(yearStr) : null;

        if (genre != _selectedGenre || year != _selectedYear) {
          setState(() {
            _selectedGenre = genre;
            _selectedYear = year;
          });
          _resetAndReload();
        }
      }
      return;
    }

    // 经典模式使用 Flutter 底部弹框
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _FilterBottomSheet(
        isDark: isDark,
        availableGenres: _availableGenres,
        availableYears: _availableYears,
        selectedGenre: _selectedGenre,
        selectedYear: _selectedYear,
        onApply: (genre, year) {
          Navigator.of(context).pop();
          if (genre != _selectedGenre || year != _selectedYear) {
            setState(() {
              _selectedGenre = genre;
              _selectedYear = year;
            });
            _resetAndReload();
          }
        },
      ),
    );
  }

  void _showSortMenu(BuildContext context, bool isDark) async {
    final uiStyle = ref.read(uiStyleProvider);
    
    // 玻璃模式使用原生 iOS sheet
    if (uiStyle.isGlass) {
      final items = VideoSortOption.values.map((option) {
        return ListSheetItem<VideoSortOption>(
          title: option.displayName,
          icon: option.icon,
          value: option,
          isSelected: option == _sortOption,
        );
      }).toList();

      final selected = await showNativeListSheet<VideoSortOption>(
        context: context,
        items: items,
        title: '排序方式',
        titleIcon: Icons.sort_rounded,
      );

      if (selected != null && selected != _sortOption) {
        setState(() => _sortOption = selected);
        _resetAndReload();
      }
      return;
    }

    // 经典模式使用 Flutter 底部弹框
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '排序方式',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
            const Divider(height: 1),
            ...VideoSortOption.values.map((option) {
              final isSelected = option == _sortOption;
              return ListTile(
                leading: Icon(
                  option.icon,
                  color: isSelected
                      ? Colors.blue
                      : (isDark ? Colors.white70 : Colors.black54),
                ),
                title: Text(
                  option.displayName,
                  style: TextStyle(
                    color: isSelected
                        ? Colors.blue
                        : (isDark ? Colors.white : Colors.black87),
                    fontWeight: isSelected ? FontWeight.bold : null,
                  ),
                ),
                trailing: isSelected
                    ? const Icon(Icons.check, color: Colors.blue)
                    : null,
                onTap: () {
                  Navigator.of(context).pop();
                  if (option != _sortOption) {
                    setState(() => _sortOption = option);
                    _resetAndReload();
                  }
                },
              );
            }),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
          ],
        ),
      ),
    );
  }

  bool get _hasFilters => _selectedGenre != null || _selectedYear != null;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final uiStyle = ref.watch(uiStyleProvider);
    final safeTop = MediaQuery.of(context).padding.top;

    // iOS 26 玻璃模式：使用悬浮头部
    if (uiStyle.isGlass) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF0D0D0D) : Colors.grey[50],
        body: Stack(
          children: [
            // 主内容区域
            _buildContent(context, isDark, safeTop + 60),
            // 悬浮按钮 - 左侧返回按钮
            Positioned(
              top: safeTop + 8,
              left: 16,
              child: const GlassFloatingBackButton(),
            ),
            // 悬浮按钮 - 右侧操作按钮
            Positioned(
              top: safeTop + 8,
              right: 16,
              child: GlassButtonGroup(
                children: [
                  GlassGroupIconButton(
                    icon: Icons.swap_vert_rounded,
                    tooltip: '排序',
                    onPressed: () => _showSortMenu(context, isDark),
                  ),
                  GlassGroupIconButton(
                    icon: Icons.filter_alt_rounded,
                    tooltip: '筛选',
                    onPressed: _isLoadingFilters
                        ? null
                        : () => _showFilterSheet(context, isDark),
                    badge: _hasFilters,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // 经典模式：保留 AppBar
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D0D0D) : Colors.grey[50],
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1A1A2E) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_rounded,
            color: isDark ? Colors.white : Colors.black87,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          '${widget.title} ($_filteredCount)',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.swap_vert_rounded,
              color: isDark ? Colors.white : Colors.black87,
            ),
            tooltip: '排序',
            onPressed: () => _showSortMenu(context, isDark),
          ),
          Stack(
            children: [
              IconButton(
                icon: Icon(
                  Icons.filter_alt_rounded,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                onPressed: _isLoadingFilters
                    ? null
                    : () => _showFilterSheet(context, isDark),
              ),
              if (_hasFilters)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: _buildContent(context, isDark, 0),
    );
  }

  /// 构建主内容区域 - 使用 CustomScrollView 让所有内容一起滚动
  Widget _buildContent(BuildContext context, bool isDark, double topPadding) {
    // 加载中状态
    if (_tvShows.isEmpty && _isLoading) {
      return Column(
        children: [
          if (topPadding > 0) SizedBox(height: topPadding),
          const Expanded(child: Center(child: CircularProgressIndicator())),
        ],
      );
    }

    // 空状态
    if (_tvShows.isEmpty) {
      return Column(
        children: [
          if (topPadding > 0) SizedBox(height: topPadding),
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.live_tv_outlined,
                    size: 64,
                    color: isDark ? Colors.white30 : Colors.black26,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '没有找到匹配的剧集',
                    style: TextStyle(
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // 有内容时：使用 CustomScrollView 让所有内容一起滚动
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final isMobile = screenWidth < 600;
        final maxExtent = isMobile ? 120.0 : 150.0;
        final aspectRatio = isMobile ? 0.48 : 0.52;
        final gridPadding = isMobile ? 12.0 : 16.0;

        return CustomScrollView(
          controller: _scrollController,
          slivers: [
            // 顶部留白
            if (topPadding > 0)
              SliverToBoxAdapter(child: SizedBox(height: topPadding)),
            // 筛选标签
            if (_hasFilters)
              SliverToBoxAdapter(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (_selectedGenre != null)
                        _FilterChip(
                          label: _selectedGenre!,
                          onRemove: () {
                            setState(() => _selectedGenre = null);
                            _resetAndReload();
                          },
                          isDark: isDark,
                        ),
                      if (_selectedYear != null)
                        _FilterChip(
                          label: '$_selectedYear年',
                          onRemove: () {
                            setState(() => _selectedYear = null);
                            _resetAndReload();
                          },
                          isDark: isDark,
                        ),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedGenre = null;
                            _selectedYear = null;
                          });
                          _resetAndReload();
                        },
                        child: Text(
                          '清除全部',
                          style: TextStyle(fontSize: 12, color: Colors.blue),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // 网格内容
            SliverPadding(
              padding: EdgeInsets.all(gridPadding),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: maxExtent,
                  childAspectRatio: aspectRatio,
                  crossAxisSpacing: isMobile ? 10 : 12,
                  mainAxisSpacing: isMobile ? 12 : 16,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index >= _tvShows.length) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    final tvShow = _tvShows[index];
                    return _VerticalPosterCard(
                      metadata: tvShow,
                      onTap: () => _openVideoDetail(context, tvShow),
                      isDark: isDark,
                      showMargin: false,
                    );
                  },
                  childCount: _tvShows.length + (_hasMore ? 1 : 0),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openVideoDetail(
    BuildContext context,
    VideoMetadata metadata,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) =>
            VideoDetailPage(metadata: metadata, sourceId: metadata.sourceId),
      ),
    );
  }
}

/// 其他视频分页页面（支持懒加载，无筛选）
class _OthersPaginatedPage extends ConsumerStatefulWidget {
  const _OthersPaginatedPage({required this.title});

  final String title;

  @override
  ConsumerState<_OthersPaginatedPage> createState() =>
      _OthersPaginatedPageState();
}

class _OthersPaginatedPageState extends ConsumerState<_OthersPaginatedPage>
    with ConsumerTabBarVisibilityMixin {
  final List<VideoMetadata> _videos = [];
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  bool _hasMore = true;
  int _offset = 0;
  int _totalCount = 0;
  static const int _pageSize = 50;

  // 排序相关
  VideoSortOption _sortOption = VideoSortOption.addedDesc;

  @override
  void initState() {
    super.initState();
    // 隐藏底部导航栏
    hideTabBar();
    _loadCount();
    _loadMore();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    // 显示底部导航栏
    // Mixin 自动处理恢复
    super.dispose();
  }

  Future<void> _loadCount() async {
    try {
      final db = VideoDatabaseService();
      final count = await db.getCount(category: MediaCategory.unknown);
      if (mounted) {
        setState(() => _totalCount = count);
      }
    } on Exception catch (e) {
      logger.e('VideoListPage: 加载其他视频数量失败', e);
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || !_hasMore || !mounted) return;

    setState(() => _isLoading = true);

    try {
      final db = VideoDatabaseService();
      final newVideos = await db.getFiltered(
        category: MediaCategory.unknown,
        sortOption: _sortOption,
        offset: _offset,
      );

      if (!mounted) return;

      setState(() {
        _videos.addAll(newVideos);
        _offset += newVideos.length;
        _hasMore = newVideos.length >= _pageSize;
        _isLoading = false;
      });
    } on Exception catch (e) {
      logger.e('VideoListPage: 加载更多其他视频失败', e);
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _resetAndReload() async {
    if (!mounted) return;
    setState(() {
      _videos.clear();
      _offset = 0;
      _hasMore = true;
    });
    await _loadMore();
  }

  void _showSortSheet(BuildContext context, bool isDark) async {
    final uiStyle = ref.read(uiStyleProvider);

    // 玻璃模式使用原生 iOS sheet
    if (uiStyle.isGlass) {
      final items = VideoSortOption.values.map((option) {
        return ListSheetItem<VideoSortOption>(
          title: option.displayName,
          icon: option.icon,
          value: option,
          isSelected: option == _sortOption,
        );
      }).toList();

      final result = await showNativeListSheet<VideoSortOption>(
        context: context,
        items: items,
        title: '排序方式',
      );

      if (result != null && result != _sortOption) {
        setState(() => _sortOption = result);
        _resetAndReload();
      }
      return;
    }

    // 经典模式使用 Flutter 底部弹框
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '排序方式',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
            ...VideoSortOption.values.map(
              (option) => ListTile(
                leading: Icon(
                  option.icon,
                  color: _sortOption == option
                      ? AppColors.primary
                      : (isDark ? Colors.grey[400] : Colors.grey[600]),
                ),
                title: Text(
                  option.displayName,
                  style: TextStyle(
                    color: _sortOption == option
                        ? AppColors.primary
                        : (isDark ? Colors.white : Colors.black87),
                    fontWeight: _sortOption == option
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                trailing: _sortOption == option
                    ? Icon(Icons.check, color: AppColors.primary)
                    : null,
                onTap: () {
                  Navigator.of(context).pop();
                  if (_sortOption != option) {
                    setState(() => _sortOption = option);
                    _resetAndReload();
                  }
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final uiStyle = ref.watch(uiStyleProvider);
    final safeTop = MediaQuery.of(context).padding.top;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final crossAxisCount = screenWidth > 1200
        ? 8
        : screenWidth > 800
        ? 6
        : screenWidth > 600
        ? 4
        : 3;
    final spacing = isMobile ? 10.0 : 16.0;
    final aspectRatio = isMobile ? 0.48 : 0.52;

    // iOS 26 玻璃模式
    if (uiStyle.isGlass) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF0D0D0D) : Colors.grey[50],
        body: Stack(
          children: [
            // 主内容 - 使用 CustomScrollView 让内容滚动到按钮下方
            _videos.isEmpty && _isLoading
                ? Center(
                    child: Padding(
                      padding: EdgeInsets.only(top: safeTop + 60),
                      child: const CircularProgressIndicator(),
                    ),
                  )
                : _videos.isEmpty
                    ? Center(
                        child: Padding(
                          padding: EdgeInsets.only(top: safeTop + 60),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.video_file_rounded,
                                size: 64,
                                color: isDark ? Colors.grey[600] : Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                '没有其他视频',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : GridView.builder(
                        controller: _scrollController,
                        padding: EdgeInsets.fromLTRB(
                          spacing,
                          safeTop + 60 + spacing,
                          spacing,
                          spacing,
                        ),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          childAspectRatio: aspectRatio,
                          crossAxisSpacing: spacing,
                          mainAxisSpacing: spacing,
                        ),
                        itemCount: _videos.length + (_hasMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index >= _videos.length) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          final video = _videos[index];
                          return _VerticalPosterCard(
                            metadata: video,
                            onTap: () => _openVideoDetail(context, video),
                            isDark: isDark,
                            showMargin: false,
                          );
                        },
                      ),
            // 悬浮按钮 - 左侧返回按钮
            Positioned(
              top: safeTop + 8,
              left: 16,
              child: const GlassFloatingBackButton(),
            ),
            // 悬浮按钮 - 右侧操作按钮
            Positioned(
              top: safeTop + 8,
              right: 16,
              child: GlassButtonGroup(
                children: [
                  GlassGroupIconButton(
                    icon: Icons.swap_vert_rounded,
                    tooltip: '排序',
                    onPressed: () => _showSortSheet(context, isDark),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // 经典模式
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D0D0D) : Colors.grey[50],
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1A1A2E) : Colors.white,
        title: Text(
          '$_totalCount 个${widget.title}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () => _showSortSheet(context, isDark),
            icon: Icon(
              Icons.swap_vert_rounded,
              color: isDark ? Colors.white : Colors.black87,
            ),
            tooltip: '排序',
          ),
        ],
      ),
      body: _videos.isEmpty && _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _videos.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.video_file_rounded,
                    size: 64,
                    color: isDark ? Colors.grey[600] : Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '没有其他视频',
                    style: TextStyle(
                      fontSize: 16,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            )
          : GridView.builder(
              controller: _scrollController,
              padding: EdgeInsets.all(spacing),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                childAspectRatio: aspectRatio,
                crossAxisSpacing: spacing,
                mainAxisSpacing: spacing,
              ),
              itemCount: _videos.length + (_hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= _videos.length) {
                  return const Center(child: CircularProgressIndicator());
                }
                final video = _videos[index];
                return _VerticalPosterCard(
                  metadata: video,
                  onTap: () => _openVideoDetail(context, video),
                  isDark: isDark,
                  showMargin: false,
                );
              },
            ),
    );
  }

  Future<void> _openVideoDetail(
    BuildContext context,
    VideoMetadata metadata,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) =>
            VideoDetailPage(metadata: metadata, sourceId: metadata.sourceId),
      ),
    );
  }
}

/// 电影系列行组件
class _MovieCollectionRow extends StatelessWidget {
  const _MovieCollectionRow({
    required this.title,
    required this.collections,
    required this.onCollectionTap,
    required this.isDark,
    this.onSeeAllTap,
    this.icon,
    this.iconColor,
    // ignore: unused_element_parameter
    this.maxCount = 10,
  });

  final String title;
  final List<MovieCollection> collections;
  final void Function(MovieCollection) onCollectionTap;
  final VoidCallback? onSeeAllTap;
  final bool isDark;
  final IconData? icon;
  final Color? iconColor;
  final int maxCount;

  @override
  Widget build(BuildContext context) {
    if (collections.isEmpty) return const SizedBox.shrink();

    final displayItems = collections.take(maxCount).toList();
    final effectiveIconColor = iconColor ?? AppColors.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题栏
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
          child: Row(
            children: [
              if (icon != null) ...[
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: effectiveIconColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 18, color: effectiveIconColor),
                ),
                const SizedBox(width: 10),
              ],
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[800] : Colors.grey[200],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${collections.length}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ),
              const Spacer(),
              // 查看全部按钮
              if (onSeeAllTap != null && collections.length > maxCount)
                TextButton(
                  onPressed: onSeeAllTap,
                  child: Text(
                    '查看全部 (${collections.length})',
                    style: TextStyle(color: AppColors.primary, fontSize: 13),
                  ),
                ),
            ],
          ),
        ),
        // 系列列表（竖向海报风格，和普通电影/剧集卡片大小一致）
        SizedBox(
          height: 235, // 130 * 1.5 + 标题区域约 40
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            // 预构建更多屏幕外的 item，让图片提前开始加载
            cacheExtent: 500,
            itemCount: displayItems.length,
            itemBuilder: (context, index) {
              final collection = displayItems[index];
              return _MovieCollectionCard(
                collection: collection,
                onTap: () => onCollectionTap(collection),
                isDark: isDark,
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 电影系列卡片（竖向海报风格，和普通电影/剧集卡片大小一致）
class _MovieCollectionCard extends StatefulWidget {
  const _MovieCollectionCard({
    required this.collection,
    required this.onTap,
    required this.isDark,
  });

  final MovieCollection collection;
  final VoidCallback onTap;
  final bool isDark;

  @override
  State<_MovieCollectionCard> createState() => _MovieCollectionCardState();
}

class _MovieCollectionCardState extends State<_MovieCollectionCard> {
  bool _isHovered = false;

  static const double _cardWidth = 130.0;
  static const double _posterHeight = _cardWidth * 1.5; // 2:3 比例

  @override
  Widget build(BuildContext context) {
    final collection = widget.collection;
    final posterUrl = collection.posterUrl;
    final hasPoster = posterUrl != null && posterUrl.isNotEmpty;

    return Container(
      width: _cardWidth,
      margin: const EdgeInsets.only(right: 12),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _isHovered ? 1.05 : 1.0,
            duration: const Duration(milliseconds: 150),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 海报区域
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: _cardWidth,
                  height: _posterHeight,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: _isHovered ? 0.4 : 0.2,
                        ),
                        blurRadius: _isHovered ? 16 : 8,
                        offset: Offset(0, _isHovered ? 8 : 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // 背景海报
                        if (hasPoster)
                          AdaptiveImage(
                            imageUrl: posterUrl,
                            placeholder: (_) => _buildPlaceholder(),
                            errorWidget: (_, _) => _buildPlaceholder(),
                          )
                        else
                          _buildPlaceholder(),
                        // 底部渐变遮罩
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            height: _posterHeight * 0.4,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.9),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // 电影数量徽章
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${collection.movieCount}部',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        // 悬停边框
                        if (_isHovered)
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: AppColors.primary,
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                // 标题
                const SizedBox(height: 8),
                Text(
                  collection.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: widget.isDark ? Colors.white : Colors.black87,
                  ),
                ),
                // 年份信息
                if (collection.movies.isNotEmpty)
                  Text(
                    _getYearRange(),
                    style: TextStyle(
                      fontSize: 10,
                      color: widget.isDark
                          ? Colors.grey[500]
                          : Colors.grey[600],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getYearRange() {
    final years = widget.collection.movies
        .where((m) => m.year != null)
        .map((m) => m.year!)
        .toList();
    if (years.isEmpty) return '';
    years.sort();
    if (years.length == 1) return '${years.first}';
    return '${years.first} - ${years.last}';
  }

  Widget _buildPlaceholder() => Container(
    color: widget.isDark
        ? AppColors.darkSurfaceVariant
        : AppColors.lightSurfaceVariant,
    child: Center(
      child: Icon(
        Icons.collections_bookmark_rounded,
        size: 40,
        color: widget.isDark ? Colors.grey[600] : Colors.grey[400],
      ),
    ),
  );
}

/// 电影系列全部页面
class _MovieCollectionsFullPage extends ConsumerWidget {
  const _MovieCollectionsFullPage({
    required this.collections,
    required this.onCollectionTap,
  });

  final List<MovieCollection> collections;
  final void Function(MovieCollection) onCollectionTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final uiStyle = ref.watch(uiStyleProvider);
    final safeTop = MediaQuery.of(context).padding.top;

    // iOS 26 玻璃模式
    if (uiStyle.isGlass) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF0D0D0D) : Colors.grey[50],
        body: Stack(
          children: [
            // 主内容
            GridView.builder(
              padding: EdgeInsets.fromLTRB(16, safeTop + 68, 16, 16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                childAspectRatio: 0.65,
                crossAxisSpacing: 12,
                mainAxisSpacing: 16,
              ),
              itemCount: collections.length,
              itemBuilder: (context, index) {
                final collection = collections[index];
                return _MovieCollectionGridCard(
                  collection: collection,
                  onTap: () => onCollectionTap(collection),
                  isDark: isDark,
                );
              },
            ),
            // 悬浮按钮 - 只有左侧返回按钮
            Positioned(
              top: safeTop + 8,
              left: 16,
              child: const GlassFloatingBackButton(),
            ),
          ],
        ),
      );
    }

    // 经典模式
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D0D0D) : Colors.grey[50],
      appBar: AppBar(
        title: Text('电影系列 (${collections.length})'),
        backgroundColor: isDark ? const Color(0xFF0D0D0D) : Colors.grey[50],
        elevation: 0,
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 180,
          childAspectRatio: 0.65,
          crossAxisSpacing: 12,
          mainAxisSpacing: 16,
        ),
        itemCount: collections.length,
        itemBuilder: (context, index) {
          final collection = collections[index];
          return _MovieCollectionGridCard(
            collection: collection,
            onTap: () => onCollectionTap(collection),
            isDark: isDark,
          );
        },
      ),
    );
  }
}

/// 电影系列网格卡片
class _MovieCollectionGridCard extends StatelessWidget {
  const _MovieCollectionGridCard({
    required this.collection,
    required this.onTap,
    required this.isDark,
  });

  final MovieCollection collection;
  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    // 获取系列封面（优先使用系列专属封面，与首页卡片保持一致）
    final posterUrl = collection.posterUrl;
    final hasPoster = posterUrl != null && posterUrl.isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 封面
          Flexible(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // 海报（使用 AdaptiveImage 支持网络和本地路径）
                    if (hasPoster)
                      AdaptiveImage(
                        imageUrl: posterUrl,
                        placeholder: (_) => _buildPlaceholder(),
                        errorWidget: (_, _) => _buildPlaceholder(),
                      )
                    else
                      _buildPlaceholder(),
                    // 电影数量徽章
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${collection.movies.length} 部',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 标题
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              collection.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder() => Container(
    color: isDark
        ? AppColors.darkSurfaceVariant
        : AppColors.lightSurfaceVariant,
    child: Center(
      child: Icon(
        Icons.collections_bookmark_rounded,
        size: 40,
        color: isDark ? Colors.grey[600] : Colors.grey[400],
      ),
    ),
  );
}

/// 电影系列详情页面
///
/// 支持显示本地电影和 TMDB 上的其他电影
class _MovieCollectionPage extends ConsumerWidget {
  const _MovieCollectionPage({
    required this.collection,
    required this.onMovieTap,
  });

  final MovieCollection collection;
  final void Function(VideoMetadata) onMovieTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final localMovies = collection.movies;
    final isTmdbCollection = collection.id > 0; // 正数 ID 是 TMDB 系列

    // 如果是 TMDB 系列，获取完整系列信息
    final tmdbCollectionAsync = isTmdbCollection
        ? ref.watch(movieCollectionProvider(collection.id))
        : const AsyncValue<TmdbCollection?>.data(null);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D0D1A) : Colors.grey[50],
      body: CustomScrollView(
        slivers: [
          // 顶部 AppBar 带背景图
          _buildAppBar(isDark, tmdbCollectionAsync),
          // 电影数量标签
          _buildMovieCountLabel(isDark, tmdbCollectionAsync),
          // 电影列表
          _buildMovieGrid(context, isDark, localMovies, tmdbCollectionAsync),
          // 底部留白 - 使用动态 padding 支持悬浮导航栏
          SliverPadding(padding: EdgeInsets.only(bottom: context.scrollBottomPadding)),
        ],
      ),
    );
  }

  Widget _buildAppBar(bool isDark, AsyncValue<TmdbCollection?> tmdbAsync) {
    // 优先使用 TMDB 的背景图，其次本地背景图，最后使用海报作为回退
    final backdropUrl =
        tmdbAsync.valueOrNull?.backdropUrl ??
        collection.backdropUrl ??
        collection.posterUrl;
    final hasBackground = backdropUrl != null && backdropUrl.isNotEmpty;

    return SliverAppBar(
      expandedHeight: hasBackground ? 200 : 120,
      pinned: true,
      backgroundColor: isDark ? const Color(0xFF0D0D1A) : Colors.white,
      flexibleSpace: FlexibleSpaceBar(
        title: Text(
          collection.name,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        background: hasBackground
            ? Stack(
                fit: StackFit.expand,
                children: [
                  AdaptiveImage(imageUrl: backdropUrl),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          (isDark ? const Color(0xFF0D0D1A) : Colors.white)
                              .withValues(alpha: 0.8),
                          if (isDark) const Color(0xFF0D0D1A) else Colors.white,
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.primary.withValues(alpha: 0.3),
                      if (isDark) const Color(0xFF0D0D1A) else Colors.white,
                    ],
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.collections_bookmark_rounded,
                    size: 48,
                    color: isDark ? Colors.grey[700] : Colors.grey[400],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildMovieCountLabel(
    bool isDark,
    AsyncValue<TmdbCollection?> tmdbAsync,
  ) {
    final localCount = collection.movies.length;
    final tmdbCollection = tmdbAsync.valueOrNull;
    final tmdbCount = tmdbCollection?.parts.length;

    String countText;
    if (tmdbCount != null && tmdbCount > localCount) {
      countText = '已收藏 $localCount / $tmdbCount 部';
    } else {
      countText = '$localCount 部电影';
    }

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Row(
          children: [
            Icon(
              Icons.movie_rounded,
              size: 20,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
            const SizedBox(width: 8),
            Text(
              countText,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
            // 加载中指示器
            if (tmdbAsync.isLoading) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation(
                    isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMovieGrid(
    BuildContext context,
    bool isDark,
    List<VideoMetadata> localMovies,
    AsyncValue<TmdbCollection?> tmdbAsync,
  ) {
    final tmdbCollection = tmdbAsync.valueOrNull;

    // 如果有 TMDB 数据，合并本地和 TMDB 电影列表
    if (tmdbCollection != null && tmdbCollection.parts.isNotEmpty) {
      // 按发布日期排序的 TMDB 电影
      final sortedParts = tmdbCollection.sortedParts;

      return SliverPadding(
        padding: const EdgeInsets.all(16),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 160,
            mainAxisSpacing: 16,
            crossAxisSpacing: 12,
            childAspectRatio: 0.55,
          ),
          delegate: SliverChildBuilderDelegate((context, index) {
            final part = sortedParts[index];
            final localMovie = localMovies.firstWhereOrNull(
              (m) => m.tmdbId == part.id,
            );
            final hasLocal = localMovie != null;

            return _CollectionMovieCard(
              part: part,
              localMovie: localMovie,
              hasLocal: hasLocal,
              onTap: hasLocal ? () => onMovieTap(localMovie) : null,
              isDark: isDark,
            );
          }, childCount: sortedParts.length),
        ),
      );
    }

    // 没有 TMDB 数据时，显示本地电影
    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 160,
          mainAxisSpacing: 16,
          crossAxisSpacing: 12,
          childAspectRatio: 0.55,
        ),
        delegate: SliverChildBuilderDelegate((context, index) {
          final movie = localMovies[index];
          return _VerticalPosterCard(
            metadata: movie,
            onTap: () => onMovieTap(movie),
            isDark: isDark,
            showMargin: false,
          );
        }, childCount: localMovies.length),
      ),
    );
  }
}

/// 系列电影卡片（支持显示本地/未收藏状态）
class _CollectionMovieCard extends StatelessWidget {
  const _CollectionMovieCard({
    required this.part,
    required this.localMovie,
    required this.hasLocal,
    required this.onTap,
    required this.isDark,
  });

  final TmdbCollectionPart part;
  final VideoMetadata? localMovie;
  final bool hasLocal;
  final VoidCallback? onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    // posterUrl 可能是空字符串，需要检查
    final posterUrl = part.posterUrl.isNotEmpty
        ? part.posterUrl
        : localMovie?.posterUrl;
    final year = part.releaseDate.isNotEmpty
        ? part.releaseDate.substring(0, 4)
        : localMovie?.year?.toString();

    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: hasLocal ? 1.0 : 0.5,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 海报
            Flexible(
              child: Stack(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: posterUrl != null
                          ? AdaptiveImage(imageUrl: posterUrl)
                          : Container(
                              color: isDark
                                  ? Colors.grey[800]
                                  : Colors.grey[300],
                              child: Center(
                                child: Icon(
                                  Icons.movie_rounded,
                                  size: 48,
                                  color: isDark
                                      ? Colors.grey[600]
                                      : Colors.grey[500],
                                ),
                              ),
                            ),
                    ),
                  ),
                  // 未收藏标签
                  if (!hasLocal)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '未收藏',
                          style: TextStyle(color: Colors.white70, fontSize: 10),
                        ),
                      ),
                    ),
                  // 评分
                  if (part.voteAverage > 0)
                    Positioned(
                      bottom: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              color: Colors.amber,
                              size: 12,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              part.voteAverage.toStringAsFixed(1),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // 标题
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                part.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: hasLocal
                      ? (isDark ? Colors.white : Colors.black87)
                      : (isDark ? Colors.grey[500] : Colors.grey[600]),
                ),
              ),
            ),
            // 年份
            if (year != null)
              Text(
                year,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey[500] : Colors.grey[600],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 未观看分类区块（异步加载）
class _UnwatchedSection extends StatefulWidget {
  const _UnwatchedSection({
    required this.isDark,
    required this.onItemTap,
    required this.onItemContextMenu,
  });

  final bool isDark;
  final void Function(VideoMetadata) onItemTap;
  final void Function(VideoMetadata) onItemContextMenu;

  @override
  State<_UnwatchedSection> createState() => _UnwatchedSectionState();
}

class _UnwatchedSectionState extends State<_UnwatchedSection> {
  List<VideoMetadata>? _unwatchedVideos;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUnwatched();
  }

  Future<void> _loadUnwatched() async {
    try {
      final historyService = VideoHistoryService();
      await historyService.init();
      final watchedPaths = await historyService.getAllWatchedPaths();

      final db = VideoDatabaseService();
      await db.init();
      final unwatched = await db.getUnwatched(
        watchedPaths: watchedPaths,
        limit: 20,
      );

      if (mounted) {
        setState(() {
          _unwatchedVideos = unwatched;
          _loading = false;
        });
      }
    } on Exception catch (e) {
      logger.w('_UnwatchedSection: 加载未观看视频失败', e);
      if (mounted) {
        setState(() {
          _unwatchedVideos = [];
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    if (_unwatchedVideos == null || _unwatchedVideos!.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverToBoxAdapter(
      child: _CategoryRow(
        title: '未观看',
        items: _unwatchedVideos!,
        onItemTap: widget.onItemTap,
        onItemContextMenu: widget.onItemContextMenu,
        isDark: widget.isDark,
        icon: Icons.visibility_off_rounded,
        iconColor: Colors.teal,
      ),
    );
  }
}

/// 动态分类区块（支持电影类型、电影地区、电视剧类型、电视剧地区）
class _DynamicCategorySection extends StatefulWidget {
  const _DynamicCategorySection({
    required this.category,
    required this.filter,
    required this.isDark,
    required this.onItemTap,
    required this.onItemContextMenu,
    this.enabledPaths,
  });

  final VideoHomeCategory category;
  final String filter;
  final bool isDark;
  final void Function(VideoMetadata) onItemTap;
  final void Function(VideoMetadata) onItemContextMenu;
  final List<({String sourceId, String path})>? enabledPaths;

  @override
  State<_DynamicCategorySection> createState() =>
      _DynamicCategorySectionState();
}

class _DynamicCategorySectionState extends State<_DynamicCategorySection> {
  List<VideoMetadata>? _videos;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadVideos();
  }

  @override
  void didUpdateWidget(covariant _DynamicCategorySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当 category 或 filter 改变时重新加载数据
    if (oldWidget.category != widget.category ||
        oldWidget.filter != widget.filter) {
      _loadVideos();
    }
  }

  Future<void> _loadVideos() async {
    try {
      final db = VideoDatabaseService();
      await db.init();

      List<VideoMetadata> videos;

      switch (widget.category) {
        case VideoHomeCategory.byMovieGenre:
          videos = await db.getMoviesByGenre(
            widget.filter,
            limit: 20,
            enabledPaths: widget.enabledPaths,
          );
        case VideoHomeCategory.byMovieRegion:
          videos = await db.getMoviesByCountry(
            widget.filter,
            limit: 20,
            enabledPaths: widget.enabledPaths,
          );
        case VideoHomeCategory.byTvGenre:
          videos = await db.getTvShowsByGenre(
            widget.filter,
            limit: 20,
            enabledPaths: widget.enabledPaths,
          );
        case VideoHomeCategory.byTvRegion:
          videos = await db.getTvShowsByCountry(
            widget.filter,
            limit: 20,
            enabledPaths: widget.enabledPaths,
          );
        default:
          videos = [];
      }

      if (mounted) {
        setState(() {
          _videos = videos;
          _loading = false;
        });
      }
    } on Exception catch (e) {
      logger.w(
        '_DynamicCategorySection: 加载${widget.category.displayName}视频失败',
        e,
      );
      if (mounted) {
        setState(() {
          _videos = [];
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    if (_videos == null || _videos!.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverToBoxAdapter(
      child: _CategoryRow(
        title: widget.filter,
        items: _videos!,
        onItemTap: widget.onItemTap,
        onItemContextMenu: widget.onItemContextMenu,
        isDark: widget.isDark,
        icon: _getIcon(),
        iconColor: _getIconColor(),
      ),
    );
  }

  IconData _getIcon() {
    switch (widget.category) {
      case VideoHomeCategory.byMovieGenre:
        return Icons.category_rounded;
      case VideoHomeCategory.byMovieRegion:
        return Icons.public_rounded;
      case VideoHomeCategory.byTvGenre:
        return Icons.category_rounded;
      case VideoHomeCategory.byTvRegion:
        return Icons.language_rounded;
      default:
        return Icons.category_rounded;
    }
  }

  Color _getIconColor() {
    switch (widget.category) {
      case VideoHomeCategory.byMovieGenre:
        return AppColors.downloadColor;
      case VideoHomeCategory.byMovieRegion:
        return AppColors.photoColor;
      case VideoHomeCategory.byTvGenre:
        return AppColors.warning;
      case VideoHomeCategory.byTvRegion:
        return AppColors.musicColor;
      default:
        return AppColors.aiColor;
    }
  }
}

/// 筛选视频分页页面（用于动态分类卡片点击后的全部视频展示）
class _FilteredVideosPaginatedPage extends ConsumerStatefulWidget {
  const _FilteredVideosPaginatedPage({
    required this.category,
    required this.filter,
    required this.onVideoTap,
    this.enabledPaths,
  });

  final VideoHomeCategory category;
  final String filter;
  final void Function(VideoMetadata) onVideoTap;
  final List<({String sourceId, String path})>? enabledPaths;

  @override
  ConsumerState<_FilteredVideosPaginatedPage> createState() =>
      _FilteredVideosPaginatedPageState();
}

class _FilteredVideosPaginatedPageState
    extends ConsumerState<_FilteredVideosPaginatedPage>
    with ConsumerTabBarVisibilityMixin {
  final List<VideoMetadata> _videos = [];
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  bool _hasMore = true;
  int _offset = 0;
  static const int _pageSize = 50;

  // 排序相关（默认按上映年份降序排序）
  VideoSortOption _sortOption = VideoSortOption.yearDesc;

  @override
  void initState() {
    super.initState();
    // 隐藏底部导航栏
    hideTabBar();
    _loadMore();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    // 显示底部导航栏
    // Mixin 自动处理恢复
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || !_hasMore || !mounted) return;

    setState(() => _isLoading = true);

    try {
      final db = VideoDatabaseService();
      await db.init();

      List<VideoMetadata> newVideos;

      switch (widget.category) {
        case VideoHomeCategory.byMovieGenre:
          newVideos = await db.getMoviesByGenre(
            widget.filter,
            limit: _pageSize,
            offset: _offset,
            sortOption: _sortOption,
            enabledPaths: widget.enabledPaths,
          );
        case VideoHomeCategory.byMovieRegion:
          newVideos = await db.getMoviesByCountry(
            widget.filter,
            limit: _pageSize,
            offset: _offset,
            sortOption: _sortOption,
            enabledPaths: widget.enabledPaths,
          );
        case VideoHomeCategory.byTvGenre:
          newVideos = await db.getTvShowsByGenre(
            widget.filter,
            limit: _pageSize,
            offset: _offset,
            sortOption: _sortOption,
            enabledPaths: widget.enabledPaths,
          );
        case VideoHomeCategory.byTvRegion:
          newVideos = await db.getTvShowsByCountry(
            widget.filter,
            limit: _pageSize,
            offset: _offset,
            sortOption: _sortOption,
            enabledPaths: widget.enabledPaths,
          );
        default:
          newVideos = [];
      }

      if (!mounted) return;

      setState(() {
        _videos.addAll(newVideos);
        _offset += newVideos.length;
        _hasMore = newVideos.length >= _pageSize;
        _isLoading = false;
      });
    } on Exception catch (e) {
      logger.e('_FilteredVideosPaginatedPage: 加载更多失败', e);
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _resetAndReload() async {
    if (!mounted) return;
    setState(() {
      _videos.clear();
      _offset = 0;
      _hasMore = true;
    });
    await _loadMore();
  }

  void _showSortMenu(BuildContext context, bool isDark) async {
    final uiStyle = ref.read(uiStyleProvider);
    
    // 玻璃模式使用原生 iOS sheet
    if (uiStyle.isGlass) {
      final items = VideoSortOption.values.map((option) {
        return ListSheetItem<VideoSortOption>(
          title: option.displayName,
          icon: option.icon,
          value: option,
          isSelected: option == _sortOption,
        );
      }).toList();

      final selected = await showNativeListSheet<VideoSortOption>(
        context: context,
        items: items,
        title: '排序方式',
        titleIcon: Icons.sort_rounded,
      );

      if (selected != null && selected != _sortOption) {
        setState(() => _sortOption = selected);
        _resetAndReload();
      }
      return;
    }

    // 经典模式使用 Flutter 底部弹框
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '排序方式',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
            const Divider(height: 1),
            ...VideoSortOption.values.map((option) {
              final isSelected = option == _sortOption;
              return ListTile(
                leading: Icon(
                  option.icon,
                  color: isSelected
                      ? Colors.blue
                      : (isDark ? Colors.white70 : Colors.black54),
                ),
                title: Text(
                  option.displayName,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                trailing: isSelected
                    ? const Icon(Icons.check_rounded, color: Colors.blue)
                    : null,
                onTap: () {
                  Navigator.of(context).pop();
                  if (option != _sortOption) {
                    setState(() => _sortOption = option);
                    _resetAndReload();
                  }
                },
              );
            }),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final uiStyle = ref.watch(uiStyleProvider);
    final safeTop = MediaQuery.of(context).padding.top;

    // iOS 26 玻璃模式：使用悬浮头部
    if (uiStyle.isGlass) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF0D0D0D) : Colors.grey[50],
        body: Stack(
          children: [
            // 主内容 - 使用滚动边距，无固定顶栏
            _buildGlassContent(context, isDark, safeTop + 60),
            // 悬浮按钮 - 左侧返回按钮
            Positioned(
              top: safeTop + 8,
              left: 16,
              child: const GlassFloatingBackButton(),
            ),
            // 悬浮按钮 - 右侧操作按钮
            Positioned(
              top: safeTop + 8,
              right: 16,
              child: GlassButtonGroup(
                children: [
                  GlassGroupIconButton(
                    icon: Icons.swap_vert_rounded,
                    tooltip: '排序',
                    onPressed: () => _showSortMenu(context, isDark),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // 经典模式：保留原有 AppBar
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.filter),
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          // 排序按钮
          IconButton(
            icon: Icon(
              _sortOption.icon,
              color: _sortOption != VideoSortOption.yearDesc
                  ? Colors.blue
                  : null,
            ),
            tooltip: '排序: ${_sortOption.displayName}',
            onPressed: () => _showSortMenu(context, isDark),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _buildContent(context, isDark),
    );
  }

  /// 玻璃模式内容 - 带顶部滚动边距
  Widget _buildGlassContent(BuildContext context, bool isDark, double topPadding) {
    if (_videos.isEmpty && _isLoading) {
      return Center(
        child: Padding(
          padding: EdgeInsets.only(top: topPadding),
          child: const CircularProgressIndicator(),
        ),
      );
    }

    if (_videos.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.only(top: topPadding),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.movie_outlined,
                size: 64,
                color: isDark ? Colors.grey[600] : Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                '暂无视频',
                style: TextStyle(
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final isMobile = screenWidth < 600;
        final maxExtent = isMobile ? 120.0 : 150.0;
        final aspectRatio = isMobile ? 0.48 : 0.52;
        final gridPadding = isMobile ? 10.0 : 12.0;

        return GridView.builder(
          controller: _scrollController,
          padding: EdgeInsets.fromLTRB(
            gridPadding,
            topPadding + gridPadding,
            gridPadding,
            gridPadding,
          ),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: maxExtent,
            childAspectRatio: aspectRatio,
            crossAxisSpacing: isMobile ? 8 : 10,
            mainAxisSpacing: isMobile ? 10 : 12,
          ),
          itemCount: _videos.length + (_hasMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= _videos.length) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }

            final video = _videos[index];
            return _VerticalPosterCard(
              metadata: video,
              isDark: isDark,
              onTap: () => widget.onVideoTap(video),
              showMargin: false,
            );
          },
        );
      },
    );
  }

  /// 经典模式内容
  Widget _buildContent(BuildContext context, bool isDark) {
    if (_videos.isEmpty && _isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_videos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.movie_outlined,
              size: 64,
              color: isDark ? Colors.grey[600] : Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              '暂无视频',
              style: TextStyle(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final isMobile = screenWidth < 600;
        final maxExtent = isMobile ? 120.0 : 150.0;
        final aspectRatio = isMobile ? 0.48 : 0.52;

        return GridView.builder(
          controller: _scrollController,
          padding: EdgeInsets.all(isMobile ? 10 : 12),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: maxExtent,
            childAspectRatio: aspectRatio,
            crossAxisSpacing: isMobile ? 8 : 10,
            mainAxisSpacing: isMobile ? 10 : 12,
          ),
          itemCount: _videos.length + (_hasMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= _videos.length) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }

            final video = _videos[index];
            return _VerticalPosterCard(
              metadata: video,
              isDark: isDark,
              onTap: () => widget.onVideoTap(video),
              showMargin: false,
            );
          },
        );
      },
    );
  }
}
