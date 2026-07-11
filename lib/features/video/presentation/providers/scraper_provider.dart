import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/video/data/services/scraper_factory.dart';
import 'package:my_nas/features/video/data/services/scraper_manager_service.dart';
import 'package:my_nas/features/video/data/services/tmdb_service.dart';
import 'package:my_nas/features/video/data/services/video_database_service.dart';
import 'package:my_nas/features/video/data/services/video_metadata_service.dart';
import 'package:my_nas/features/video/data/services/video_scanner_service.dart';
import 'package:my_nas/features/video/domain/entities/scraper_result.dart';
import 'package:my_nas/features/video/domain/entities/scraper_source.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

/// 刮削源管理服务 Provider
final scraperManagerProvider = Provider<ScraperManagerService>((ref) => ScraperManagerService());

/// 刮削源列表 Provider
final scraperSourcesProvider =
    StateNotifierProvider<ScraperSourcesNotifier, AsyncValue<List<ScraperSourceEntity>>>(
        ScraperSourcesNotifier.new);

/// 已启用的刮削源数量 Provider
final enabledScraperCountProvider = Provider<int>((ref) {
  final sources = ref.watch(scraperSourcesProvider).valueOrNull ?? [];
  return sources.where((s) => s.isEnabled).length;
});

/// 总刮削源数量 Provider
final totalScraperCountProvider = Provider<int>((ref) {
  final sources = ref.watch(scraperSourcesProvider).valueOrNull ?? [];
  return sources.length;
});

/// 刮削源列表管理
class ScraperSourcesNotifier extends StateNotifier<AsyncValue<List<ScraperSourceEntity>>> {
  ScraperSourcesNotifier(this._ref) : super(const AsyncValue.loading()) {
    _load();
  }

  final Ref _ref;

  Future<void> _load() async {
    try {
      final manager = _ref.read(scraperManagerProvider);
      await manager.init();

      // 尝试从旧配置迁移
      await manager.migrateFromLegacyConfig();

      final sources = await manager.getSources();
      state = AsyncValue.data(sources);
    } on Exception catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// 刷新列表
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    await _load();
  }

  /// 添加刮削源
  Future<void> addSource(ScraperSourceEntity source) async {
    final manager = _ref.read(scraperManagerProvider);
    await manager.addSource(source);
    await _load();
  }

  /// 更新刮削源
  Future<void> updateSource(ScraperSourceEntity source) async {
    final manager = _ref.read(scraperManagerProvider);
    await manager.updateSource(source);
    await _load();
  }

  /// 删除刮削源
  Future<void> removeSource(String sourceId) async {
    final manager = _ref.read(scraperManagerProvider);
    await manager.removeSource(sourceId);
    await _load();
  }

  /// 重新排序刮削源
  Future<void> reorderSources(int oldIndex, int newIndex) async {
    final sources = state.valueOrNull;
    if (sources == null) return;

    // 创建可变副本
    final mutableSources = List<ScraperSourceEntity>.from(sources);

    // 移动元素
    final item = mutableSources.removeAt(oldIndex);
    mutableSources.insert(newIndex, item);

    // 更新排序顺序
    final updatedSources = <ScraperSourceEntity>[];
    for (var i = 0; i < mutableSources.length; i++) {
      updatedSources.add(mutableSources[i].copyWith(priority: i));
    }

    // 保存到存储
    final manager = _ref.read(scraperManagerProvider);
    for (final source in updatedSources) {
      await manager.updateSource(source);
    }

    // 立即更新状态
    state = AsyncValue.data(updatedSources);
  }

  /// 启用/禁用刮削源
  Future<void> toggleSource(String sourceId, {required bool enabled}) async {
    final manager = _ref.read(scraperManagerProvider);
    await manager.toggleSource(sourceId, enabled: enabled);

    // 立即更新状态（不需要完整 reload）
    final sources = state.valueOrNull;
    if (sources != null) {
      final updatedSources = sources.map((s) {
        if (s.id == sourceId) {
          return s.copyWith(isEnabled: enabled);
        }
        return s;
      }).toList();
      state = AsyncValue.data(updatedSources);
    }
  }

  /// 测试刮削源连接
  Future<bool> testConnection(ScraperSourceEntity source) async {
    final manager = _ref.read(scraperManagerProvider);
    final scraper = await manager.getScraper(source.id);
    if (scraper == null) return false;
    return scraper.testConnection();
  }

  /// 使用临时凭证测试连接（用于新建或编辑时）
  Future<bool> testConnectionWithCredential(
    ScraperType type,
    ScraperCredential credential, {
    String? apiUrl,
    int requestInterval = 0,
  }) async {
    final scraper = ScraperFactory.createFromCredential(
      type,
      credential,
      apiUrl: apiUrl,
      requestInterval: requestInterval,
    );

    try {
      return await scraper.testConnection();
    } finally {
      scraper.dispose();
    }
  }
}

/// 搜索电影结果 Provider（带参数）
final searchMoviesProvider = FutureProvider.family
    .autoDispose<ScraperSearchResult, MovieSearchParams>((ref, params) async {
  final manager = ref.read(scraperManagerProvider);
  await manager.init();
  return manager.searchMovies(
    params.query,
    page: params.page,
    language: params.language,
    year: params.year,
  );
});

/// 搜索电视剧结果 Provider（带参数）
final searchTvShowsProvider = FutureProvider.family
    .autoDispose<ScraperSearchResult, TvSearchParams>((ref, params) async {
  final manager = ref.read(scraperManagerProvider);
  await manager.init();
  return manager.searchTvShows(
    params.query,
    page: params.page,
    language: params.language,
    year: params.year,
  );
});

/// 电影详情 Provider
final movieDetailProvider = FutureProvider.family
    .autoDispose<ScraperMovieDetail?, MovieDetailParams>((ref, params) async {
  final manager = ref.read(scraperManagerProvider);
  await manager.init();
  return manager.getMovieDetail(
    query: params.query,
    externalId: params.externalId,
    source: params.source,
    language: params.language,
    year: params.year,
  );
});

/// 电视剧详情 Provider
final tvDetailProvider = FutureProvider.family
    .autoDispose<ScraperTvDetail?, TvDetailParams>((ref, params) async {
  final manager = ref.read(scraperManagerProvider);
  await manager.init();
  return manager.getTvDetail(
    query: params.query,
    externalId: params.externalId,
    source: params.source,
    language: params.language,
    year: params.year,
  );
});

/// 电影搜索参数
class MovieSearchParams {
  const MovieSearchParams({
    required this.query,
    this.page = 1,
    this.language,
    this.year,
  });

  final String query;
  final int page;
  final String? language;
  final int? year;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MovieSearchParams &&
          runtimeType == other.runtimeType &&
          query == other.query &&
          page == other.page &&
          language == other.language &&
          year == other.year;

  @override
  int get hashCode => Object.hash(query, page, language, year);
}

/// 电视剧搜索参数
class TvSearchParams {
  const TvSearchParams({
    required this.query,
    this.page = 1,
    this.language,
    this.year,
  });

  final String query;
  final int page;
  final String? language;
  final int? year;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TvSearchParams &&
          runtimeType == other.runtimeType &&
          query == other.query &&
          page == other.page &&
          language == other.language &&
          year == other.year;

  @override
  int get hashCode => Object.hash(query, page, language, year);
}

/// 电影详情参数
class MovieDetailParams {
  const MovieDetailParams({
    this.query,
    this.externalId,
    this.source,
    this.language,
    this.year,
  });

  final String? query;
  final String? externalId;
  final ScraperType? source;
  final String? language;
  final int? year;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MovieDetailParams &&
          runtimeType == other.runtimeType &&
          query == other.query &&
          externalId == other.externalId &&
          source == other.source &&
          language == other.language &&
          year == other.year;

  @override
  int get hashCode => Object.hash(query, externalId, source, language, year);
}

/// 电视剧详情参数
class TvDetailParams {
  const TvDetailParams({
    this.query,
    this.externalId,
    this.source,
    this.language,
    this.year,
  });

  final String? query;
  final String? externalId;
  final ScraperType? source;
  final String? language;
  final int? year;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TvDetailParams &&
          runtimeType == other.runtimeType &&
          query == other.query &&
          externalId == other.externalId &&
          source == other.source &&
          language == other.language &&
          year == other.year;

  @override
  int get hashCode => Object.hash(query, externalId, source, language, year);
}

// ============ 后台刮削状态管理 ============

/// 单个刮削任务的状态
class ScrapingTaskState {
  const ScrapingTaskState({
    required this.showDirectory,
    required this.tmdbId,
    required this.tvDetail,
    this.status = ScrapingStatus.pending,
    this.progress = 0,
    this.total = 0,
    this.currentSeason = 0,
    this.currentEpisode = '',
    this.successCount = 0,
    this.failCount = 0,
    this.errorMessage,
  });

  /// 刮削目标的目录
  final String showDirectory;

  /// TMDB ID
  final int tmdbId;

  /// 电视剧详情
  final ScraperTvDetail tvDetail;

  /// 刮削状态
  final ScrapingStatus status;

  /// 当前进度（已刮削数量）
  final int progress;

  /// 总数量
  final int total;

  /// 当前正在刮削的季
  final int currentSeason;

  /// 当前正在刮削的剧集名称
  final String currentEpisode;

  /// 成功数量
  final int successCount;

  /// 失败数量
  final int failCount;

  /// 错误消息
  final String? errorMessage;

  /// 进度百分比 (0.0 - 1.0)
  double get progressPercent => total > 0 ? progress / total : 0.0;

  /// 是否正在刮削
  bool get isScraping => status == ScrapingStatus.scraping;

  /// 是否已完成（成功或失败）
  bool get isCompleted =>
      status == ScrapingStatus.completed || status == ScrapingStatus.failed;

  ScrapingTaskState copyWith({
    String? showDirectory,
    int? tmdbId,
    ScraperTvDetail? tvDetail,
    ScrapingStatus? status,
    int? progress,
    int? total,
    int? currentSeason,
    String? currentEpisode,
    int? successCount,
    int? failCount,
    String? errorMessage,
  }) => ScrapingTaskState(
      showDirectory: showDirectory ?? this.showDirectory,
      tmdbId: tmdbId ?? this.tmdbId,
      tvDetail: tvDetail ?? this.tvDetail,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      total: total ?? this.total,
      currentSeason: currentSeason ?? this.currentSeason,
      currentEpisode: currentEpisode ?? this.currentEpisode,
      successCount: successCount ?? this.successCount,
      failCount: failCount ?? this.failCount,
      errorMessage: errorMessage ?? this.errorMessage,
    );
}

/// 刮削状态
enum ScrapingStatus {
  /// 等待中
  pending,

  /// 正在刮削
  scraping,

  /// 已完成
  completed,

  /// 失败
  failed,
}

/// 后台刮削任务管理器
class BackgroundScrapingNotifier extends StateNotifier<Map<String, ScrapingTaskState>> {
  BackgroundScrapingNotifier(this._ref) : super({});

  // ignore: unused_field
  final Ref _ref;
  final VideoMetadataService _metadataService = VideoMetadataService();

  /// 获取指定目录的刮削状态
  ScrapingTaskState? getTaskState(String showDirectory) => state[showDirectory];

  /// 检查是否有任何正在进行的刮削
  bool get hasActiveTasks => state.values.any((t) => t.isScraping);

  /// 开始刮削电视剧
  ///
  /// 返回是否成功启动刮削
  Future<bool> startTvShowScraping({
    required String showDirectory,
    required ScraperTvDetail tvDetail,
    required Set<int> selectedSeasons,
    required Map<int, Map<int, VideoMetadata>> localEpisodes,
    required Map<int, ScraperSeasonDetail> seasonDetails,
    NasFileSystem? fileSystem,
    ScrapeOptions options = const ScrapeOptions(),
  }) async {
    // 如果已经在刮削，不重复启动
    if (state[showDirectory]?.isScraping ?? false) {
      logger.w('BackgroundScrapingNotifier: 已经在刮削 $showDirectory');
      return false;
    }

    // 计算总数
    var totalEpisodes = 0;
    for (final season in selectedSeasons) {
      totalEpisodes += localEpisodes[season]?.length ?? 0;
    }

    if (totalEpisodes == 0) {
      logger.w('BackgroundScrapingNotifier: 没有本地剧集可刮削');
      return false;
    }

    // 获取 TMDB ID
    final tmdbId = int.tryParse(tvDetail.externalId);
    if (tmdbId == null) {
      logger.e('BackgroundScrapingNotifier: 无效的 TMDB ID ${tvDetail.externalId}');
      return false;
    }

    // 创建任务状态
    final taskState = ScrapingTaskState(
      showDirectory: showDirectory,
      tmdbId: tmdbId,
      tvDetail: tvDetail,
      status: ScrapingStatus.scraping,
      total: totalEpisodes,
    );

    // 更新状态
    final newState = Map<String, ScrapingTaskState>.from(state);
    newState[showDirectory] = taskState;
    state = newState;

    // 启动后台刮削任务
    AppError.fireAndForget(
      _runScrapingTask(
        showDirectory: showDirectory,
        tvDetail: tvDetail,
        selectedSeasons: selectedSeasons,
        localEpisodes: localEpisodes,
        seasonDetails: seasonDetails,
        fileSystem: fileSystem,
        options: options,
      ),
      action: 'BackgroundScrapingNotifier.startTvShowScraping',
    );

    return true;
  }

  /// 执行刮削任务
  Future<void> _runScrapingTask({
    required String showDirectory,
    required ScraperTvDetail tvDetail,
    required Set<int> selectedSeasons,
    required Map<int, Map<int, VideoMetadata>> localEpisodes,
    required Map<int, ScraperSeasonDetail> seasonDetails,
    NasFileSystem? fileSystem,
    ScrapeOptions options = const ScrapeOptions(),
  }) async {
    await _metadataService.init();

    var successCount = 0;
    var failCount = 0;
    var progress = 0;

    // 按季号排序刮削
    final sortedSeasons = selectedSeasons.toList()..sort();

    try {
      for (final seasonNumber in sortedSeasons) {
        final localSeasonEpisodes = localEpisodes[seasonNumber] ?? {};
        if (localSeasonEpisodes.isEmpty) continue;

        final seasonDetail = seasonDetails[seasonNumber];

        // 更新当前季
        _updateTaskState(
          showDirectory,
          (task) => task.copyWith(currentSeason: seasonNumber),
        );

        for (final entry in localSeasonEpisodes.entries) {
          final episodeNumber = entry.key;
          final metadata = entry.value;

          // 获取对应的刮削剧集
          final scraperEpisode = seasonDetail?.getEpisode(episodeNumber);

          // 更新当前剧集
          _updateTaskState(
            showDirectory,
            (task) => task.copyWith(
              currentEpisode: '${metadata.displayTitle} (S${seasonNumber}E$episodeNumber)',
            ),
          );

          try {
            await _metadataService.scrapeAndSave(
              metadata: metadata,
              tvDetail: tvDetail,
              seasonNumber: seasonNumber,
              episodeNumber: episodeNumber,
              episodeTitle: scraperEpisode?.name,
              fileSystem: fileSystem,
              options: options,
            );
            successCount++;
          } on Exception catch (e, st) {
            AppError.handle(e, st, 'BackgroundScrapingNotifier._runScrapingTask');
            failCount++;
          }

          progress++;
          _updateTaskState(
            showDirectory,
            (task) => task.copyWith(
              progress: progress,
              successCount: successCount,
              failCount: failCount,
            ),
          );
        }
      }

      // 刮削完成
      _updateTaskState(
        showDirectory,
        (task) => task.copyWith(
          status: ScrapingStatus.completed,
          currentEpisode: '',
          currentSeason: 0,
        ),
      );

      logger.i('BackgroundScrapingNotifier: 刮削完成 $showDirectory, '
          '成功: $successCount, 失败: $failCount');
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'BackgroundScrapingNotifier._runScrapingTask');
      _updateTaskState(
        showDirectory,
        (task) => task.copyWith(
          status: ScrapingStatus.failed,
          errorMessage: e.toString(),
        ),
      );
    }
  }

  /// 更新任务状态
  void _updateTaskState(
    String showDirectory,
    ScrapingTaskState Function(ScrapingTaskState) updater,
  ) {
    final currentTask = state[showDirectory];
    if (currentTask != null) {
      final newState = Map<String, ScrapingTaskState>.from(state);
      newState[showDirectory] = updater(currentTask);
      state = newState;
    }
  }

  /// 移除已完成的任务
  void removeTask(String showDirectory) {
    final newState = Map<String, ScrapingTaskState>.from(state)
    ..remove(showDirectory);
    state = newState;
  }

  /// 清除所有已完成的任务
  void clearCompletedTasks() {
    state = Map.fromEntries(
      state.entries.where((e) => e.value.isScraping),
    );
  }
}

/// 后台刮削任务管理器 Provider
final backgroundScrapingProvider =
    StateNotifierProvider<BackgroundScrapingNotifier, Map<String, ScrapingTaskState>>(
        BackgroundScrapingNotifier.new);

/// 获取指定目录的刮削状态 Provider
final scrapingTaskProvider = Provider.family<ScrapingTaskState?, String>(
  (ref, showDirectory) => ref.watch(backgroundScrapingProvider)[showDirectory],
);

// ============ 元数据增强服务 ============

/// 元数据增强状态
class MetadataEnrichmentState {
  const MetadataEnrichmentState({
    this.isRunning = false,
    this.progress = 0,
    this.total = 0,
    this.currentItem = '',
    this.successCount = 0,
    this.failCount = 0,
    this.lastError,
  });

  final bool isRunning;
  final int progress;
  final int total;
  final String currentItem;
  final int successCount;
  final int failCount;
  final String? lastError;

  double get progressPercent => total > 0 ? progress / total : 0.0;

  MetadataEnrichmentState copyWith({
    bool? isRunning,
    int? progress,
    int? total,
    String? currentItem,
    int? successCount,
    int? failCount,
    String? lastError,
  }) => MetadataEnrichmentState(
      isRunning: isRunning ?? this.isRunning,
      progress: progress ?? this.progress,
      total: total ?? this.total,
      currentItem: currentItem ?? this.currentItem,
      successCount: successCount ?? this.successCount,
      failCount: failCount ?? this.failCount,
      lastError: lastError ?? this.lastError,
    );
}

/// 元数据增强服务 Notifier
///
/// 当添加新的刮削源时，自动检测并更新缺失的元数据：
/// - 电影系列信息（collectionId, collectionName, collectionPosterUrl, collectionBackdropUrl）
/// - 地区和类型信息
/// - 其他可能缺失的 TMDB 元数据
class MetadataEnrichmentNotifier extends StateNotifier<MetadataEnrichmentState> {
  MetadataEnrichmentNotifier(this._ref) : super(const MetadataEnrichmentState()) {
    _init();
  }

  final Ref _ref;
  final _dbService = VideoDatabaseService();
  StreamSubscription<ScraperSourceEvent>? _subscription;

  void _init() {
    // 监听刮削源变更事件
    final manager = _ref.read(scraperManagerProvider);
    _subscription = manager.onSourceChanged.listen(_onSourceChanged);
  }

  void _onSourceChanged(ScraperSourceEvent event) {
    // 当添加任何刮削源时，检查是否有待刮削的视频
    if (event.type == ScraperSourceEventType.added) {
      logger.i('检测到新增刮削源: ${event.source.name}');
      AppError.fireAndForget(
        _scrapePendingVideosIfNeeded(),
        action: 'MetadataEnrichmentNotifier._scrapePendingVideosIfNeeded',
      );

      // 仅当添加 TMDB 源时触发元数据增强（补充电影系列信息等）
      if (event.source.type == ScraperType.tmdb) {
        logger.i('检测到新增 TMDB 刮削源，开始元数据增强');
        AppError.fireAndForget(
          enrichAllMetadata(),
          action: 'MetadataEnrichmentNotifier.enrichAllMetadata',
        );
      }
    }
  }

  /// 检查并刮削 pending 状态的视频
  ///
  /// 当配置完刮削源后，自动刮削之前扫描但未刮削的视频
  Future<void> _scrapePendingVideosIfNeeded() async {
    try {
      await _dbService.init();

      // 获取 pending 状态的视频数量
      final stats = await _dbService.getScrapeStats();
      if (stats.pending == 0) {
        logger.i('没有待刮削的视频，跳过');
        return;
      }

      logger.i('发现 ${stats.pending} 个待刮削视频，准备自动刮削');

      // 获取活跃连接
      final connections = _ref.read(activeConnectionsProvider);
      final hasConnected = connections.values
          .any((c) => c.status == SourceStatus.connected);

      if (!hasConnected) {
        logger.w('没有可用连接，跳过自动刮削');
        return;
      }

      // 检查是否已经在刮削中
      final scanner = VideoScannerService();
      if (scanner.isScraping) {
        logger.i('刮削任务正在进行中，跳过');
        return;
      }

      // 触发刮削
      logger.i('开始自动刮削 ${stats.pending} 个视频');
      await scanner.scrapeMetadata(connections: connections);
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'MetadataEnrichmentNotifier._scrapePendingVideosIfNeeded');
    }
  }

  /// 增强所有元数据
  ///
  /// 包括：电影系列信息、地区、类型、演员、导演等
  /// 同时处理电影和剧集
  Future<void> enrichAllMetadata() async {
    if (state.isRunning) {
      logger.w('元数据增强正在进行中，跳过');
      return;
    }

    try {
      await _dbService.init();

      // 获取需要增强的电影列表（有 TMDB ID 但缺少系列信息或其他元数据）
      final moviesWithoutCollection = await _dbService.getMoviesWithoutCollection();
      final moviesWithoutMetadata = await _dbService.getMoviesWithIncompleteMetadata();

      // 合并去重电影
      final movieSet = <int>{};
      final movies = <VideoMetadata>[];
      for (final movie in [...moviesWithoutCollection, ...moviesWithoutMetadata]) {
        if (movie.tmdbId != null && !movieSet.contains(movie.tmdbId)) {
          movieSet.add(movie.tmdbId!);
          movies.add(movie);
        }
      }

      // 获取需要增强的剧集列表（有 TMDB ID 但缺少地区或类型信息）
      final tvShowsWithoutMetadata = await _dbService.getTvShowsWithIncompleteMetadata();

      // 合并去重剧集
      final tvShowSet = <int>{};
      final tvShows = <VideoMetadata>[];
      for (final tvShow in tvShowsWithoutMetadata) {
        if (tvShow.tmdbId != null && !tvShowSet.contains(tvShow.tmdbId)) {
          tvShowSet.add(tvShow.tmdbId!);
          tvShows.add(tvShow);
        }
      }

      final totalItems = movies.length + tvShows.length;
      if (totalItems == 0) {
        logger.i('没有需要增强元数据的电影或剧集');
        return;
      }

      state = MetadataEnrichmentState(
        isRunning: true,
        total: totalItems,
        currentItem: appL10n.scraperCheckingMetadata,
      );

      final tmdbService = TmdbService();
      if (!tmdbService.hasApiKey) {
        logger.w('TMDB API Key 未配置，无法增强元数据');
        state = state.copyWith(
          isRunning: false,
          lastError: appL10n.scraperTmdbKeyMissing,
        );
        return;
      }

      var successCount = 0;
      var failCount = 0;
      var progress = 0;

      // 处理电影
      for (final movie in movies) {
        if (movie.tmdbId == null) continue;

        state = state.copyWith(
          progress: progress,
          currentItem: appL10n.scraperMovieItem(movie.displayTitle),
        );

        try {
          // 获取电影详情
          final detail = await tmdbService.getMovieDetail(movie.tmdbId!);
          if (detail != null) {
            // 检查需要更新哪些字段
            var needsUpdate = false;
            var updatedMovie = movie;

            // 更新系列信息
            if (detail.collectionId != null && movie.collectionId == null) {
              updatedMovie = updatedMovie.copyWith(
                collectionId: detail.collectionId,
                collectionName: detail.collectionName,
                collectionPosterUrl: detail.collectionPosterUrl,
                collectionBackdropUrl: detail.collectionBackdropUrl,
              );
              needsUpdate = true;
              logger.d('更新电影系列信息: ${movie.displayTitle} -> ${detail.collectionName}');
            }

            // 更新地区信息
            final countriesList = detail.countriesList;
            if ((movie.countries == null || movie.countries!.isEmpty) &&
                countriesList != null &&
                countriesList.isNotEmpty) {
              updatedMovie = updatedMovie.copyWith(countries: countriesList.join(', '));
              needsUpdate = true;
              logger.d('更新电影地区: ${movie.displayTitle} -> $countriesList');
            }

            // 更新类型信息
            final genresList = detail.genresList;
            if ((movie.genres == null || movie.genres!.isEmpty) &&
                genresList != null &&
                genresList.isNotEmpty) {
              updatedMovie = updatedMovie.copyWith(genres: genresList.join(' / '));
              needsUpdate = true;
              logger.d('更新电影类型: ${movie.displayTitle} -> $genresList');
            }

            // 更新导演信息
            if ((movie.director == null || movie.director!.isEmpty) &&
                detail.directorName != null) {
              updatedMovie = updatedMovie.copyWith(director: detail.directorName);
              needsUpdate = true;
            }

            // 更新演员信息
            final castNames = detail.castNames;
            if ((movie.cast == null || movie.cast!.isEmpty) &&
                castNames != null &&
                castNames.isNotEmpty) {
              updatedMovie = updatedMovie.copyWith(cast: castNames.join(', '));
              needsUpdate = true;
            }

            if (needsUpdate) {
              await _dbService.upsert(updatedMovie);
            }
            successCount++;
          } else {
            // 无法获取详情
            failCount++;
          }
        } on Exception catch (e, st) {
          AppError.handle(e, st, 'MetadataEnrichmentNotifier.enrichMovieMetadata');
          failCount++;
        }

        progress++;

        // 添加延迟避免 API 限流
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }

      // 处理剧集
      for (final tvShow in tvShows) {
        if (tvShow.tmdbId == null) continue;

        state = state.copyWith(
          progress: progress,
          currentItem: appL10n.scraperTvItem(tvShow.displayTitle),
        );

        try {
          // 获取剧集详情
          final detail = await tmdbService.getTvDetail(tvShow.tmdbId!);
          if (detail != null) {
            // 获取需要更新的字段
            final countriesText = detail.countriesText;
            final genresText = detail.genresText;
            final castNames = detail.cast.take(5).map((c) => c.name).join(', ');

            // 检查是否需要更新
            final needsCountries = (tvShow.countries == null || tvShow.countries!.isEmpty) &&
                countriesText.isNotEmpty;
            final needsGenres = (tvShow.genres == null || tvShow.genres!.isEmpty) &&
                genresText.isNotEmpty;
            final needsCast = (tvShow.cast == null || tvShow.cast!.isEmpty) &&
                castNames.isNotEmpty;

            if (needsCountries || needsGenres || needsCast) {
              // 批量更新同一剧集的所有集（使用 TMDB ID 匹配）
              await _dbService.updateTvShowMetadata(
                showDirectory: tvShow.showDirectory,
                tmdbId: tvShow.tmdbId!,
                countries: needsCountries ? countriesText : null,
                genres: needsGenres ? genresText : null,
                cast: needsCast ? castNames : null,
              );
              logger.d('更新剧集元数据: ${tvShow.displayTitle} -> 地区=$countriesText, 类型=$genresText');
            }
            successCount++;
          } else {
            failCount++;
          }
        } on Exception catch (e, st) {
          AppError.handle(e, st, 'MetadataEnrichmentNotifier.enrichTvShowMetadata');
          failCount++;
        }

        progress++;

        // 添加延迟避免 API 限流
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }

      state = MetadataEnrichmentState(
        isRunning: false,
        progress: progress,
        total: totalItems,
        successCount: successCount,
        failCount: failCount,
      );

      logger.i('元数据增强完成: 电影=${movies.length}, 剧集=${tvShows.length}, '
          '成功=$successCount, 失败=$failCount');

      // 刷新首页数据
      // 通过 invalidate video list provider 来触发刷新
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'MetadataEnrichmentNotifier.enrichAllMetadata');
      state = state.copyWith(
        isRunning: false,
        lastError: e.toString(),
      );
    }
  }

  /// 手动触发增强
  Future<void> startEnrichment() async {
    await enrichAllMetadata();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

/// 元数据增强服务 Provider
final metadataEnrichmentProvider =
    StateNotifierProvider<MetadataEnrichmentNotifier, MetadataEnrichmentState>(
        MetadataEnrichmentNotifier.new);
