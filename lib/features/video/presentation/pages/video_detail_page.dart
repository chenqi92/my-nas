import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/shared/mixins/tab_bar_visibility_mixin.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/nastool/presentation/providers/nastool_provider.dart';
import 'package:my_nas/features/pt_sites/presentation/pages/pt_site_detail_page.dart';
import 'package:my_nas/features/pt_sites/presentation/utils/pt_search_launcher.dart';
import 'package:my_nas/features/sources/domain/entities/source_category.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/video/data/services/opensubtitles_service.dart';
import 'package:my_nas/features/video/data/services/tmdb_service.dart';
import 'package:my_nas/features/video/data/services/video_database_service.dart';
import 'package:my_nas/features/video/data/services/video_favorites_service.dart';
import 'package:my_nas/features/video/domain/entities/video_item.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/features/video/domain/utils/video_localization.dart';
import 'package:my_nas/features/video/presentation/pages/manual_scraper_page.dart';
import 'package:my_nas/features/video/presentation/pages/season_scraper_page.dart';
import 'package:my_nas/features/video/presentation/pages/tmdb_preview_page.dart';
import 'package:my_nas/features/video/presentation/pages/video_player_page.dart';
import 'package:my_nas/features/video/presentation/providers/playlist_provider.dart';
import 'package:my_nas/features/video/presentation/providers/scraper_provider.dart'
    show ScrapingTaskState, backgroundScrapingProvider, enabledScraperCountProvider;
import 'package:my_nas/features/video/presentation/providers/video_detail_provider.dart';
import 'package:my_nas/features/video/presentation/providers/video_favorites_provider.dart';
import 'package:my_nas/features/video/presentation/providers/video_history_provider.dart';
import 'package:my_nas/features/video/presentation/widgets/cast_section.dart';
import 'package:my_nas/features/video/presentation/widgets/detail_hero_section.dart';
import 'package:my_nas/features/video/presentation/widgets/recommendations_section.dart';
import 'package:my_nas/features/video/presentation/widgets/subtitle_download_dialog.dart';
import 'package:my_nas/features/video/presentation/widgets/unified_episode_selector.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/shared/providers/ui_style_provider.dart';
import 'package:my_nas/shared/widgets/adaptive_glass_app_bar.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';

/// 视频详情页面
class VideoDetailPage extends ConsumerStatefulWidget {
  const VideoDetailPage({
    required this.metadata,
    required this.sourceId,
    super.key,
  });

  final VideoMetadata metadata;
  final String sourceId;

  @override
  ConsumerState<VideoDetailPage> createState() => _VideoDetailPageState();
}

class _VideoDetailPageState extends ConsumerState<VideoDetailPage>
    with ConsumerTabBarVisibilityMixin {
  bool _isPlaying = false;
  /// 当前选中的视频版本（用于质量切换）
  late VideoMetadata _selectedMetadata;

  @override
  void initState() {
    super.initState();
    hideTabBar();
    _selectedMetadata = widget.metadata;
  }

  bool get _isTvShow => _selectedMetadata.category == MediaCategory.tvShow;
  bool get _hasTmdbId => _selectedMetadata.tmdbId != null && _selectedMetadata.tmdbId! > 0;
  bool get _hasDoubanId => _selectedMetadata.doubanId != null && _selectedMetadata.doubanId!.isNotEmpty;
  /// 是否有任何刮削数据（TMDB 或豆瓣）
  bool get _hasMetadata => _hasTmdbId || _hasDoubanId;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    final isWide = size.width > 800;

    // 获取播放进度
    final progressAsync = ref.watch(videoProgressProvider(_selectedMetadata.filePath));
    final watchProgress = progressAsync.whenOrNull(data: (p) => p?.progressPercent);

    // 获取收藏状态
    final isFavoriteAsync = ref.watch(isFavoriteProvider(_selectedMetadata.filePath));
    final isFavorite = isFavoriteAsync.valueOrNull ?? false;

    // 获取已观看状态
    final isWatchedAsync = ref.watch(isWatchedProvider(_selectedMetadata.filePath));
    final isWatched = isWatchedAsync.valueOrNull ?? false;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : Colors.grey[100],
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // Hero 区域
              SliverToBoxAdapter(
                child: _buildHeroSection(
                  isDark,
                  watchProgress: watchProgress,
                  isFavorite: isFavorite,
                  isWatched: isWatched,
                ),
              ),

              // 内容区域
              SliverToBoxAdapter(
                child: _buildMainContent(context, isDark, isWide),
              ),
            ],
          ),

          // 返回按钮
          _buildBackButton(context, isDark),
          // PT 搜索按钮（右上角浮动）
          _buildPtSearchFab(context, isDark),
        ],
      ),
    );
  }

  /// 右上角悬浮的 "在 PT 站搜索本片" 按钮
  ///
  /// 用户在浏览自己已有的视频时，可以一键去 PT 站搜素更高画质/补全缺失剧集等。
  /// 仅在用户已添加任何 PT 站时显示，避免对未配置的用户产生干扰。
  Widget _buildPtSearchFab(BuildContext context, bool isDark) {
    final allSources = ref.watch(sourcesProvider).valueOrNull ?? const <SourceEntity>[];
    final hasPtSite = allSources
        .any((s) => s.type.category == SourceCategory.ptSites && s.type.isSupported);
    if (!hasPtSite) return const SizedBox.shrink();

    final safeTop = MediaQuery.of(context).padding.top;
    final titleGetter = ref.watch(videoTitleGetterProvider);
    final localized = titleGetter(_selectedMetadata).trim();
    final rawTitle = (_selectedMetadata.title ?? '').trim();
    final rawOriginal = (_selectedMetadata.originalTitle ?? '').trim();
    final searchTitle = localized.isNotEmpty
        ? localized
        : (rawTitle.isNotEmpty ? rawTitle : rawOriginal);

    if (searchTitle.isEmpty) return const SizedBox.shrink();

    final yearStr = _selectedMetadata.year?.toString();
    final query = (yearStr != null && yearStr.isNotEmpty)
        ? '$searchTitle $yearStr'
        : searchTitle;

    return Positioned(
      top: safeTop + 8,
      right: 12,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          shape: BoxShape.circle,
        ),
        child: IconButton(
          icon: const Icon(Icons.cloud_download_outlined, color: Colors.white),
          tooltip: '在 PT 站搜索本片',
          onPressed: () => launchPtSearchForMedia(context, ref, query: query),
        ),
      ),
    );
  }

  Widget _buildHeroSection(
    bool isDark, {
    double? watchProgress,
    bool isFavorite = false,
    bool isWatched = false,
  }) {
    // 获取 TMDB 详情以获取 tagline、评分等
    String? tagline;
    String? overview;
    double? tmdbRating;
    int? voteCount;
    var backdropUrl = widget.metadata.backdropUrl;

    if (_hasTmdbId) {
      if (_isTvShow) {
        final _ = ref.watch(tvDetailProvider(widget.metadata.tmdbId!))
        ..whenData((detail) {
          if (detail != null) {
            tagline = detail.tagline;
            overview = detail.overview;
            tmdbRating = detail.voteAverage;
            voteCount = detail.voteCount;
            backdropUrl ??= detail.backdropUrl;
          }
        });
      } else {
        final _ = ref.watch(movieDetailProvider(widget.metadata.tmdbId!))
        ..whenData((detail) {
          if (detail != null) {
            tagline = detail.tagline;
            overview = detail.overview;
            tmdbRating = detail.voteAverage;
            voteCount = detail.voteCount;
            backdropUrl ??= detail.backdropUrl;
          }
        });
      }
    }

    // 使用 metadata 的简介作为后备
    overview ??= widget.metadata.overview;

    // 获取本地化标题
    final titleGetter = ref.watch(videoTitleGetterProvider);
    final localizedTitle = titleGetter(_selectedMetadata);

    // 获取本地化简介（如果没有从 TMDB 获取到的话）
    if (overview == null || overview!.isEmpty) {
      final overviewGetter = ref.watch(videoOverviewGetterProvider);
      overview = overviewGetter(_selectedMetadata);
    }

    // 如果只有豆瓣数据，使用 metadata 中的评分作为豆瓣评分
    final doubanRating = _hasDoubanId && !_hasTmdbId ? _selectedMetadata.rating : null;

    // 只有在有启用的刮削源时才显示刮削按钮
    final hasEnabledScrapers = ref.watch(enabledScraperCountProvider) > 0;

    // 获取当前 showDirectory 的刮削状态
    var showDirectory = _selectedMetadata.showDirectory;
    if ((showDirectory == null || showDirectory.isEmpty) && _isTvShow) {
      showDirectory = VideoDatabaseService.extractShowDirectory(_selectedMetadata.filePath);
    }
    final scrapingTask = showDirectory != null && showDirectory.isNotEmpty
        ? ref.watch(backgroundScrapingProvider)[showDirectory]
        : null;

    return DetailHeroSection(
      metadata: _selectedMetadata,
      onPlay: _isPlaying ? () {} : _playVideo,
      onFavorite: _toggleFavorite,
      onToggleWatched: _toggleWatched,
      onScrape: hasEnabledScrapers ? _openManualScraper : null,
      isFavorite: isFavorite,
      isWatched: isWatched,
      watchProgress: watchProgress,
      backdropUrl: backdropUrl,
      tagline: tagline,
      displayTitle: localizedTitle,
      overview: overview,
      tmdbRating: tmdbRating,
      doubanRating: doubanRating,
      imdbRating: _selectedMetadata.imdbRating,
      traktRating: _selectedMetadata.traktRating,
      voteCount: voteCount,
      sourceId: widget.sourceId,
      // 电视剧详情页隐藏季集信息，因为这是剧的总览页，不是单集页
      // 只要有刮削数据（TMDB 或豆瓣）或 showDirectory，都隐藏单集标签
      hideEpisodeInfo: _isTvShow && (_hasMetadata || _selectedMetadata.showDirectory != null),
      scrapingTask: scrapingTask,
      onScrapingDismiss: scrapingTask != null && showDirectory != null
          ? () => _onScrapingDismiss(showDirectory!, scrapingTask)
          : null,
    );
  }

  /// 刮削完成后关闭进度指示器
  void _onScrapingDismiss(String showDirectory, ScrapingTaskState task) {
    ref.read(backgroundScrapingProvider.notifier).removeTask(showDirectory);
    // 刷新剧集列表
    if (task.tmdbId > 0) {
      ref
        ..invalidate(localEpisodeFilesProvider(task.tmdbId))
        ..invalidate(tvDetailProvider(task.tmdbId));
    }
    ref.invalidate(localEpisodesByShowDirProvider(showDirectory));
  }

  Widget _buildMainContent(BuildContext context, bool isDark, bool isWide) {
    // 调试日志
    logger..i('VideoDetailPage: _buildMainContent called')
    ..i('VideoDetailPage:   title=${_selectedMetadata.displayTitle}')
    ..i('VideoDetailPage:   category=${_selectedMetadata.category}')
    ..i('VideoDetailPage:   isTvShow=$_isTvShow, hasTmdbId=$_hasTmdbId, hasDoubanId=$_hasDoubanId')
    ..i('VideoDetailPage:   tmdbId=${_selectedMetadata.tmdbId}, doubanId=${_selectedMetadata.doubanId}')
    ..i('VideoDetailPage:   showDirectory=${_selectedMetadata.showDirectory}')
    ..i('VideoDetailPage:   seasonNumber=${_selectedMetadata.seasonNumber}')
    ..i('VideoDetailPage:   episodeNumber=${_selectedMetadata.episodeNumber}')
    ..i('VideoDetailPage:   filePath=${_selectedMetadata.filePath}');

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isWide ? 24 : 0,
        vertical: 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 剧集选择器 (电视剧) - 使用统一选择器
          if (_isTvShow) ...[
            _buildUnifiedEpisodeSection(),
            const SizedBox(height: 24),
          ],

          // 注意：简介已移至 Banner 区域，不再单独显示

          // 演员阵容
          // - 有 TMDB ID：从 TMDB 获取详细信息（带照片）
          // - 只有豆瓣 ID：显示 metadata 中的演员列表（无照片）
          if (_hasTmdbId) ...[
            _buildCastSection(),
          ] else if (_hasDoubanId && _selectedMetadata.cast != null) ...[
            _buildSimpleCastSection(isDark),
          ],

          // 电影系列 (仅电影且有 TMDB ID)
          if (!_isTvShow && _hasTmdbId) ...[
            const SizedBox(height: 24),
            _buildMovieCollectionSection(isDark),
          ],

          // 注意：详细信息已移至 Banner 区域的元数据标签中

          // 推荐内容 (需要 TMDB ID)
          if (_hasTmdbId) ...[
            const SizedBox(height: 24),
            _buildRecommendationsSection(),
          ],

          // 文件信息
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildFileInfoSection(isDark),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  /// 构建统一剧集选择器
  Widget _buildUnifiedEpisodeSection() {
    final allProgressAsync = ref.watch(allVideoProgressProvider);
    final allProgress = allProgressAsync.valueOrNull ?? {};

    // 将进度转换为 Map<filePath, double>
    final episodeProgress = <String, double>{};
    for (final entry in allProgress.entries) {
      episodeProgress[entry.key] = entry.value.progressPercent;
    }

    // 获取本地剧集数据
    if (_hasTmdbId) {
      // 有 TMDB ID：同时获取 TMDB 和本地数据
      final tmdbId = _selectedMetadata.tmdbId!;
      final tvDetailAsync = ref.watch(tvDetailProvider(tmdbId));
      final localEpisodesAsync = ref.watch(localEpisodeFilesProvider(tmdbId));

      final localEpisodes = localEpisodesAsync.valueOrNull ?? {};

      return tvDetailAsync.when(
        loading: () => const SizedBox(
          height: 200,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (_, _) => UnifiedEpisodeSelector(
          localEpisodes: localEpisodes,
          initialSeason: _selectedMetadata.seasonNumber,
          episodeProgress: episodeProgress,
          onEpisodePlay: _playUnifiedEpisode,
          showName: _selectedMetadata.title,
          year: _selectedMetadata.year?.toString(),
        ),
        data: (tvDetail) => UnifiedEpisodeSelector(
          tmdbId: tmdbId,
          tmdbSeasons: tvDetail?.seasons,
          localEpisodes: localEpisodes,
          initialSeason: _selectedMetadata.seasonNumber,
          episodeProgress: episodeProgress,
          onEpisodePlay: _playUnifiedEpisode,
          showName: tvDetail?.name ?? _selectedMetadata.title,
          year: tvDetail?.year?.toString() ?? _selectedMetadata.year?.toString(),
        ),
      );
    } else {
      // 无 TMDB ID：使用 showDirectory 获取本地剧集
      var showDirectory = _selectedMetadata.showDirectory;
      if (showDirectory == null || showDirectory.isEmpty) {
        showDirectory = VideoDatabaseService.extractShowDirectory(_selectedMetadata.filePath);
      }

      if (showDirectory == null || showDirectory.isEmpty) {
        return const SizedBox.shrink();
      }

      final localEpisodesAsync = ref.watch(localEpisodesByShowDirProvider(showDirectory));

      return localEpisodesAsync.when(
        loading: () => const SizedBox(
          height: 200,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (_, _) => const SizedBox.shrink(),
        data: (episodes) => UnifiedEpisodeSelector(
          localEpisodes: episodes,
          initialSeason: _selectedMetadata.seasonNumber,
          episodeProgress: episodeProgress,
          onEpisodePlay: _playUnifiedEpisode,
          showName: _selectedMetadata.title,
          year: _selectedMetadata.year?.toString(),
        ),
      );
    }
  }

  /// 统一的剧集播放方法
  Future<void> _playUnifiedEpisode(VideoMetadata localFile, {TmdbEpisode? tmdbEpisode}) async {
    setState(() => _isPlaying = true);

    try {
      final videoInfo = await _getVideoInfo(localFile.filePath);
      if (videoInfo == null) return;

      if (!mounted) return;

      // 优先使用 TMDB 剧集名，其次使用本地元数据
      final episodeName = tmdbEpisode?.name ?? localFile.episodeTitle ?? localFile.displayTitle;

      final videoItem = VideoItem(
        name: episodeName,
        path: localFile.filePath,
        url: videoInfo.url,
        sourceId: widget.sourceId,
        size: videoInfo.size,
        thumbnailUrl: tmdbEpisode?.stillUrl ?? localFile.displayPosterUrl,
      );

      // 构建当前季的剧集播放列表（不阻塞导航）
      final seasonNumber = localFile.seasonNumber ?? 1;
      _buildEpisodePlaylist(seasonNumber, localFile.episodeNumber ?? 1);

      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (context) => VideoPlayerPage(video: videoItem),
        ),
      );

      // 刷新播放历史
      ref..invalidate(continueWatchingProvider)
      ..invalidate(allVideoProgressProvider);
    } finally {
      if (mounted) {
        setState(() => _isPlaying = false);
      }
    }
  }

  /// 构建当前季的播放列表（同步方法，不阻塞播放）
  void _buildEpisodePlaylist(int seasonNumber, int currentEpisodeNumber) {
    // 获取本地剧集数据
    var localEpisodes = <int, Map<int, VideoMetadata>>{};

    if (_hasTmdbId) {
      final data = ref.read(localEpisodeFilesProvider(_selectedMetadata.tmdbId!));
      localEpisodes = data.valueOrNull ?? {};
    } else {
      var showDirectory = _selectedMetadata.showDirectory;
      if (showDirectory == null || showDirectory.isEmpty) {
        showDirectory = VideoDatabaseService.extractShowDirectory(_selectedMetadata.filePath);
      }
      if (showDirectory != null && showDirectory.isNotEmpty) {
        final data = ref.read(localEpisodesByShowDirProvider(showDirectory));
        localEpisodes = data.valueOrNull ?? {};
      }
    }

    // 获取当前季的剧集
    final seasonEpisodes = localEpisodes[seasonNumber] ?? {};
    if (seasonEpisodes.isEmpty) {
      logger.d('VideoDetailPage: 无法构建播放列表，当前季无剧集');
      return;
    }

    // 按集号排序并构建 VideoItem 列表
    final episodeNumbers = seasonEpisodes.keys.toList()..sort();
    final playlistItems = <VideoItem>[];
    var startIndex = 0;

    for (var i = 0; i < episodeNumbers.length; i++) {
      final epNum = episodeNumbers[i];
      final episode = seasonEpisodes[epNum]!;

      // 使用空 URL 构建 VideoItem（播放时会自动解析）
      playlistItems.add(VideoItem(
        name: episode.episodeTitle ?? episode.displayTitle,
        path: episode.filePath,
        // URL 留空，播放时会自动获取
        sourceId: widget.sourceId,
        size: episode.fileSize ?? 0,
        thumbnailUrl: episode.displayPosterUrl,
      ));

      // 记录当前播放集的索引
      if (epNum == currentEpisodeNumber) {
        startIndex = i;
      }
    }

    // 设置播放列表
    if (playlistItems.isNotEmpty) {
      ref.read(playlistProvider.notifier).setPlaylist(playlistItems, startIndex: startIndex);
      logger.i('VideoDetailPage: 播放列表已设置，共 ${playlistItems.length} 集，从第 ${startIndex + 1} 集开始');
    }
  }

  Widget _buildCastSection() {
    if (_isTvShow) {
      final tvDetailAsync = ref.watch(tvDetailProvider(widget.metadata.tmdbId!));
      return tvDetailAsync.when(
        loading: () => const SizedBox.shrink(),
        error: (_, _) => const SizedBox.shrink(),
        data: (tvDetail) {
          if (tvDetail == null || tvDetail.cast.isEmpty) {
            return const SizedBox.shrink();
          }
          return CastAndCrewSection(
            cast: tvDetail.cast,
            crew: tvDetail.crew,
          );
        },
      );
    } else {
      final movieDetailAsync = ref.watch(movieDetailProvider(widget.metadata.tmdbId!));
      return movieDetailAsync.when(
        loading: () => const SizedBox.shrink(),
        error: (_, _) => const SizedBox.shrink(),
        data: (movieDetail) {
          if (movieDetail == null || movieDetail.cast.isEmpty) {
            return const SizedBox.shrink();
          }
          return CastAndCrewSection(
            cast: movieDetail.cast,
            crew: movieDetail.crew,
          );
        },
      );
    }
  }

  /// 简单演员列表（用于豆瓣等没有详细演员信息的数据源）
  Widget _buildSimpleCastSection(bool isDark) {
    final castList = _selectedMetadata.castList;
    if (castList.isEmpty) return const SizedBox.shrink();

    final director = _selectedMetadata.director;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '演职人员',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
            ),
          ),
          const SizedBox(height: 12),
          // 导演
          if (director != null && director.isNotEmpty) ...[
            _buildSimpleCastItem('导演', director, isDark),
            const SizedBox(height: 8),
          ],
          // 演员
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: castList.take(10).map((name) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurfaceVariant : Colors.grey[100],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? AppColors.darkOutline : Colors.grey[300]!,
                ),
              ),
              child: Text(
                name,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                ),
              ),
            )).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleCastItem(String role, String name, bool isDark) => Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            role,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.primary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          name,
          style: TextStyle(
            fontSize: 14,
            color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
          ),
        ),
      ],
    );

  /// 电影系列/合集区域
  Widget _buildMovieCollectionSection(bool isDark) {
    final movieDetailAsync = ref.watch(movieDetailProvider(widget.metadata.tmdbId!));

    return movieDetailAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (movieDetail) {
        if (movieDetail == null || movieDetail.belongsToCollection == null) {
          return const SizedBox.shrink();
        }

        final collectionInfo = movieDetail.belongsToCollection!;
        final collectionAsync = ref.watch(movieCollectionProvider(collectionInfo.id));

        return collectionAsync.when(
          loading: () => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  collectionInfo.name,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                  ),
                ),
                const SizedBox(height: 12),
                const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
          error: (_, _) => const SizedBox.shrink(),
          data: (collection) {
            if (collection == null || collection.parts.isEmpty) {
              return const SizedBox.shrink();
            }

            final sortedParts = collection.sortedParts;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题行：系列名称 + 查看全部
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              collection.name,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '共 ${sortedParts.length} 部电影',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark
                                    ? AppColors.darkOnSurfaceVariant
                                    : AppColors.lightOnSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 查看全部按钮
                      TextButton.icon(
                        onPressed: () => _openMovieCollectionPage(
                          collection,
                          widget.metadata.tmdbId!,
                          isDark,
                        ),
                        icon: Icon(
                          Icons.grid_view_rounded,
                          size: 16,
                          color: AppColors.primary,
                        ),
                        label: Text(
                          '查看全部',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 200,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: sortedParts.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final part = sortedParts[index];
                        final isCurrentMovie = part.id == widget.metadata.tmdbId;

                        return _buildCollectionMovieCard(
                          part,
                          isDark,
                          isCurrentMovie: isCurrentMovie,
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCollectionMovieCard(
    TmdbCollectionPart part,
    bool isDark, {
    bool isCurrentMovie = false,
  }) => GestureDetector(
      onTap: isCurrentMovie ? null : () => _onCollectionMovieTap(part),
      child: Container(
        width: 120,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: isCurrentMovie
              ? Border.all(color: AppColors.primary, width: 2)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 海报
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (part.posterUrl.isNotEmpty) Image.network(
                            part.posterUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _buildPosterPlaceholder(isDark),
                          ) else _buildPosterPlaceholder(isDark),
                    // 当前电影标识
                    if (isCurrentMovie)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '当前',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    // 评分
                    if (part.voteAverage > 0)
                      Positioned(
                        bottom: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
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
                                size: 12,
                                color: Colors.amber,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                part.ratingText,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.white,
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
            ),
            const SizedBox(height: 6),
            // 标题
            Text(
              part.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
              ),
            ),
            // 年份
            if (part.year != null)
              Text(
                '${part.year}',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark
                      ? AppColors.darkOnSurfaceVariant
                      : AppColors.lightOnSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );

  Widget _buildPosterPlaceholder(bool isDark) => Container(
      color: isDark ? AppColors.darkSurfaceVariant : Colors.grey[300],
      child: Center(
        child: Icon(
          Icons.movie_rounded,
          size: 40,
          color: isDark ? Colors.grey[600] : Colors.grey[500],
        ),
      ),
    );

  Future<void> _onCollectionMovieTap(TmdbCollectionPart part) async {
    // 检查本地是否有该电影
    final metadataService = ref.read(videoMetadataServiceProvider);
    await metadataService.init();
    final localVideo = await metadataService.getFirstByTmdbId(part.id);

    if (!mounted) return;

    if (localVideo != null) {
      // 本地有该电影，跳转到详情页
      // 使用 pushReplacement 避免详情页嵌套过深
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (context) => VideoDetailPage(
            metadata: localVideo,
            sourceId: localVideo.sourceId,
          ),
        ),
      );
    } else {
      // 本地没有该电影，跳转到 TMDB 预览页面
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => TmdbPreviewPage(
            tmdbId: part.id,
            isMovie: true, // 电影系列中的都是电影
            title: part.title,
            posterUrl: part.posterUrl,
            backdropUrl: part.backdropUrl,
          ),
        ),
      );
    }
  }

  /// 打开电影系列完整列表页面
  void _openMovieCollectionPage(
    TmdbCollection collection,
    int currentMovieId,
    bool isDark,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => MovieCollectionListPage(
          collection: collection,
          currentMovieId: currentMovieId,
          sourceId: widget.sourceId,
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, bool isDark) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: isDark
                    ? AppColors.darkOnSurfaceVariant
                    : AppColors.lightOnSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
              ),
            ),
          ),
        ],
      ),
    );

  Widget _buildRecommendationsSection() => CombinedRecommendationsSection(
      tmdbId: widget.metadata.tmdbId!,
      isMovie: !_isTvShow,
      onItemTap: _onRecommendationTap,
    );

  Widget _buildFileInfoSection(bool isDark) {
    // 电视剧：显示剧集统计信息
    if (_isTvShow && _hasTmdbId) {
      return _buildTvShowFileInfo(isDark);
    }

    // 电视剧（无 TMDB）：显示基于 showDirectory 的剧集统计
    // _buildLocalTvShowFileInfo 内部会尝试从文件路径提取 showDirectory
    if (_isTvShow) {
      return _buildLocalTvShowFileInfo(isDark);
    }

    // 电影：显示单个文件信息 + 质量选择器
    final hasSubtitleConfig = ref.watch(hasOpenSubtitlesConfigProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceVariant : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.darkOutline : Colors.grey[300]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '文件信息',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                ),
              ),
              const Spacer(),
              // 字幕下载按钮
              if (hasSubtitleConfig)
                IconButton(
                  onPressed: () => _showSubtitleDownloadDialog(
                    seasonNumber: null,
                    episodeNumber: null,
                    savePath: _getVideoDirectory(_selectedMetadata.filePath),
                  ),
                  icon: const Icon(Icons.subtitles, size: 20),
                  tooltip: '下载字幕',
                  visualDensity: VisualDensity.compact,
                ),
              // 质量选择器（仅电影）
              _buildQualitySelector(isDark),
            ],
          ),
          const SizedBox(height: 12),
          _buildInfoRow('文件名', _selectedMetadata.fileName, isDark),
          _buildInfoRow('路径', _selectedMetadata.filePath, isDark),
          _buildInfoRow('来源', widget.sourceId, isDark),
          if (_selectedMetadata.resolution != null)
            _buildInfoRow('分辨率', _selectedMetadata.resolution!, isDark),
          if (_selectedMetadata.fileSizeText.isNotEmpty)
            _buildInfoRow('文件大小', _selectedMetadata.fileSizeText, isDark),
        ],
      ),
    );
  }

  /// 电视剧文件信息统计
  Widget _buildTvShowFileInfo(bool isDark) {
    final episodesAsync = ref.watch(relatedLocalVideosProvider(_selectedMetadata.tmdbId!));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceVariant : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.darkOutline : Colors.grey[300]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '本地剧集',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
            ),
          ),
          const SizedBox(height: 12),
          episodesAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            error: (_, _) => Text(
              '加载失败',
              style: TextStyle(
                color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
              ),
            ),
            data: (episodes) {
              if (episodes.isEmpty) {
                return Text(
                  '无本地剧集',
                  style: TextStyle(
                    color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                  ),
                );
              }

              // 统计信息
              final totalSize = episodes.fold<int>(0, (sum, e) => sum + (e.fileSize ?? 0));
              final totalSizeText = _formatFileSize(totalSize);
              final seasonNumbers = episodes
                  .where((e) => e.seasonNumber != null)
                  .map((e) => e.seasonNumber!)
                  .toSet()
                  .toList()
                ..sort();
              final showDirectory = episodes.first.showDirectory ?? '';

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoRow('剧集数量', '${episodes.length} 集', isDark),
                  if (seasonNumbers.isNotEmpty)
                    _buildInfoRow(
                      '季数',
                      seasonNumbers.length == 1
                          ? '第 ${seasonNumbers.first} 季'
                          : '${seasonNumbers.length} 季 (${seasonNumbers.first}-${seasonNumbers.last})',
                      isDark,
                    ),
                  _buildInfoRow('总大小', totalSizeText, isDark),
                  if (showDirectory.isNotEmpty)
                    _buildInfoRow('目录', showDirectory, isDark),
                  _buildInfoRow('来源', widget.sourceId, isDark),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// 本地电视剧文件信息统计（无 TMDB 数据时使用）
  Widget _buildLocalTvShowFileInfo(bool isDark) {
    // 尝试获取 showDirectory，如果没有设置，从文件路径提取
    var showDirectory = _selectedMetadata.showDirectory;
    if (showDirectory == null || showDirectory.isEmpty) {
      showDirectory = VideoDatabaseService.extractShowDirectory(_selectedMetadata.filePath);
    }

    if (showDirectory == null || showDirectory.isEmpty) {
      return const SizedBox.shrink();
    }

    final episodesAsync = ref.watch(localEpisodesByShowDirProvider(showDirectory));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceVariant : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.darkOutline : Colors.grey[300]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '本地剧集',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
            ),
          ),
          const SizedBox(height: 12),
          episodesAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            error: (_, _) => Text(
              '加载失败',
              style: TextStyle(
                color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
              ),
            ),
            data: (episodeMap) {
              // 统计信息
              var totalEpisodes = 0;
              var totalSize = 0;
              for (final seasonEpisodes in episodeMap.values) {
                for (final episode in seasonEpisodes.values) {
                  totalEpisodes++;
                  totalSize += episode.fileSize ?? 0;
                }
              }

              if (totalEpisodes == 0) {
                return Text(
                  '无本地剧集',
                  style: TextStyle(
                    color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                  ),
                );
              }

              final totalSizeText = _formatFileSize(totalSize);
              final seasonNumbers = episodeMap.keys.toList()..sort();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoRow('剧集数量', '$totalEpisodes 集', isDark),
                  if (seasonNumbers.isNotEmpty)
                    _buildInfoRow(
                      '季数',
                      seasonNumbers.length == 1
                          ? '第 ${seasonNumbers.first} 季'
                          : '${seasonNumbers.length} 季 (${seasonNumbers.first}-${seasonNumbers.last})',
                      isDark,
                    ),
                  _buildInfoRow('总大小', totalSizeText, isDark),
                  _buildInfoRow('目录', showDirectory!, isDark),
                  _buildInfoRow('来源', widget.sourceId, isDark),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String _formatFileSize(int bytes) {
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;
    if (bytes >= gb) {
      return '${(bytes / gb).toStringAsFixed(2)} GB';
    } else if (bytes >= mb) {
      return '${(bytes / mb).toStringAsFixed(1)} MB';
    } else if (bytes >= kb) {
      return '${(bytes / kb).toStringAsFixed(0)} KB';
    }
    return '$bytes B';
  }

  Widget _buildBackButton(BuildContext context, bool isDark) {
    final uiStyle = ref.watch(uiStyleProvider);
    final safeTop = MediaQuery.of(context).padding.top;

    // iOS 26 玻璃模式：使用悬浮玻璃返回按钮
    if (uiStyle.isGlass) {
      return Positioned(
        top: safeTop + 8,
        left: 16,
        child: GestureDetector(
          onLongPress: () {
            // 长按：返回到视频库主页
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
          onSecondaryTap: () {
            // 右键：返回到视频库主页
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
          child: const GlassFloatingBackButton(),
        ),
      );
    }

    // 经典模式：半透明圆形按钮
    return Positioned(
      top: safeTop + 8,
      left: 8,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          shape: BoxShape.circle,
        ),
        child: GestureDetector(
          onLongPress: () {
            // 长按：返回到视频库主页
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
          onSecondaryTap: () {
            // 右键：返回到视频库主页
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
          child: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: '返回（长按/右键返回主页）',
          ),
        ),
      ),
    );
  }

  /// 构建质量选择器
  ///
  /// 如果同一电影有多个质量版本，显示下拉选择器
  Widget _buildQualitySelector(bool isDark) {
    // 仅对电影显示质量选择器（剧集使用剧集选择器）
    if (_isTvShow) {
      return const SizedBox.shrink();
    }

    // 使用 movieVersionsProvider 获取所有版本（支持有/无 TMDB ID）
    final variantsAsync = ref.watch(movieVersionsProvider(_selectedMetadata));

    return variantsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (variants) {
        // 只有一个版本，不显示选择器
        if (variants.length <= 1) {
          return const SizedBox.shrink();
        }

        // 按分辨率排序（4K > 2160p > 1080p > 720p > 480p > 无）
        final sortedVariants = _sortByResolution(variants);

        return PopupMenuButton<VideoMetadata>(
          onSelected: (selected) {
            setState(() => _selectedMetadata = selected);
          },
          offset: const Offset(0, 40),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.hd_rounded,
                  size: 16,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  _selectedMetadata.resolution ?? '原始',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.arrow_drop_down_rounded,
                  size: 18,
                  color: AppColors.primary,
                ),
              ],
            ),
          ),
          itemBuilder: (context) => sortedVariants.map((v) {
            final isSelected = v.filePath == _selectedMetadata.filePath;
            return PopupMenuItem<VideoMetadata>(
              value: v,
              child: Row(
                children: [
                  if (isSelected)
                    Icon(Icons.check_rounded, size: 18, color: AppColors.primary)
                  else
                    const SizedBox(width: 18),
                  const SizedBox(width: 8),
                  Text(
                    v.resolution ?? '原始',
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    v.fileSizeText,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? AppColors.darkOnSurfaceVariant
                          : AppColors.lightOnSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  /// 按分辨率排序（高到低）
  List<VideoMetadata> _sortByResolution(List<VideoMetadata> variants) {
    const resolutionOrder = <String, int>{
      '4K': 0,
      '2160P': 1,
      '2160p': 1,
      '1080P': 2,
      '1080p': 2,
      '720P': 3,
      '720p': 3,
      '480P': 4,
      '480p': 4,
    };

    final sorted = List<VideoMetadata>.from(variants)
    ..sort((a, b) {
      final orderA = resolutionOrder[a.resolution] ?? 99;
      final orderB = resolutionOrder[b.resolution] ?? 99;
      return orderA.compareTo(orderB);
    });
    return sorted;
  }

  Future<void> _toggleFavorite() async {
    final favoritesNotifier = ref.read(favoritesProvider.notifier);
    final item = VideoFavoriteItem(
      videoPath: _selectedMetadata.filePath,
      videoName: _selectedMetadata.displayTitle,
      videoUrl: '', // URL 将在播放时获取
      thumbnailUrl: _selectedMetadata.displayPosterUrl,
      addedAt: DateTime.now(),
    );
    await favoritesNotifier.toggleFavorite(item);
  }

  Future<void> _toggleWatched() async {
    await toggleWatchedStatus(ref, widget.metadata.filePath);
  }

  /// 打开刮削页面
  /// 电视剧使用整剧刮削页面，电影使用单个刮削页面
  Future<void> _openManualScraper() async {
    final connections = ref.read(activeConnectionsProvider);
    final connection = connections[widget.sourceId];
    final fileSystem = connection?.status == SourceStatus.connected
        ? connection!.adapter.fileSystem
        : null;

    bool? result;

    // 尝试获取 showDirectory
    var showDirectory = _selectedMetadata.showDirectory;
    if ((showDirectory == null || showDirectory.isEmpty) && _isTvShow) {
      // 如果 showDirectory 为空但是电视剧，尝试从文件路径提取
      showDirectory = VideoDatabaseService.extractShowDirectory(_selectedMetadata.filePath);
    }

    if (_isTvShow && showDirectory != null && showDirectory.isNotEmpty) {
      // 电视剧：使用整剧刮削页面
      result = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => SeasonScraperPage(
            showDirectory: showDirectory!,
            sourceId: widget.sourceId,
            tmdbId: _selectedMetadata.tmdbId,
            fileSystem: fileSystem,
            initialSeasonNumber: _selectedMetadata.seasonNumber,
          ),
        ),
      );
    } else {
      // 电影或无法确定 showDirectory 的视频：使用单个刮削页面
      result = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => ManualScraperPage(
            metadata: _selectedMetadata,
            fileSystem: fileSystem,
          ),
        ),
      );
    }

    // 刮削成功后刷新详情页
    if ((result ?? false) && mounted) {
      // 重新加载元数据
      final metadataService = ref.read(videoMetadataServiceProvider);
      await metadataService.init();
      final updatedMetadata = await metadataService.getCachedAsync(
        widget.sourceId,
        _selectedMetadata.filePath,
      );
      if (updatedMetadata != null && mounted) {
        // 刷新剧集列表 Provider（刮削前的 ID 和刮削后的 ID 都需要刷新）
        final oldTmdbId = _selectedMetadata.tmdbId;
        final newTmdbId = updatedMetadata.tmdbId;

        setState(() {
          _selectedMetadata = updatedMetadata;
        });

        // 刷新相关 Provider
        if (oldTmdbId != null) {
          ref
            ..invalidate(movieDetailProvider(oldTmdbId))
            ..invalidate(tvDetailProvider(oldTmdbId))
            ..invalidate(localEpisodeFilesProvider(oldTmdbId));
        }
        if (newTmdbId != null && newTmdbId != oldTmdbId) {
          ref
            ..invalidate(movieDetailProvider(newTmdbId))
            ..invalidate(tvDetailProvider(newTmdbId))
            ..invalidate(localEpisodeFilesProvider(newTmdbId));
        }

        // 刷新 showDirectory 相关的 Provider
        if (showDirectory != null && showDirectory.isNotEmpty) {
          ref.invalidate(localEpisodesByShowDirProvider(showDirectory));
        }
      }
    }
  }

  Future<void> _playVideo() async {
    setState(() => _isPlaying = true);

    try {
      final videoInfo = await _getVideoInfo(widget.metadata.filePath);
      if (videoInfo == null) return;

      if (!mounted) return;

      final videoItem = VideoItem(
        name: _selectedMetadata.displayTitle,
        path: _selectedMetadata.filePath,
        url: videoInfo.url,
        sourceId: widget.sourceId,
        size: videoInfo.size,
        thumbnailUrl: _selectedMetadata.displayPosterUrl,
      );

      await Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (context) => VideoPlayerPage(video: videoItem),
        ),
      );

      // 刷新播放历史
      ref..invalidate(continueWatchingProvider)
      ..invalidate(videoProgressProvider(_selectedMetadata.filePath));
    } finally {
      if (mounted) {
        setState(() => _isPlaying = false);
      }
    }
  }

  /// 获取视频信息（URL 和文件大小）
  Future<_VideoPlayInfo?> _getVideoInfo(String filePath) async {
    final connections = ref.read(activeConnectionsProvider);
    final connection = connections[widget.sourceId];

    if (connection == null || connection.status != SourceStatus.connected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.cloud_off_rounded, color: Colors.white),
                SizedBox(width: 12),
                Text('未连接到 NAS，请先在设置中连接'),
              ],
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return null;
    }

    try {
      final fileSystem = connection.adapter.fileSystem;

      // 获取文件信息以获得大小
      final fileInfo = await fileSystem.getFileInfo(filePath);
      final url = await fileSystem.getFileUrl(filePath);

      return _VideoPlayInfo(url: url, size: fileInfo.size);
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('获取视频信息失败: $e')),
              ],
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return null;
    }
  }

  Future<void> _onRecommendationTap(TmdbMediaItem item) async {
    // 检查本地是否有该影片
    final metadataService = ref.read(videoMetadataServiceProvider);
    await metadataService.init();
    final localVideo = await metadataService.getFirstByTmdbId(item.id);

    if (!mounted) return;

    if (localVideo != null) {
      // 本地有该影片，跳转到详情页
      // 使用 pushReplacement 避免详情页嵌套过深
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (context) => VideoDetailPage(
            metadata: localVideo,
            sourceId: localVideo.sourceId,
          ),
        ),
      );
    } else {
      // 本地没有该影片，跳转到 TMDB 预览页面
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => TmdbPreviewPage(
            tmdbId: item.id,
            isMovie: item.isMovie,
            title: item.title,
            posterUrl: item.posterUrl,
            backdropUrl: item.backdropUrl,
          ),
        ),
      );
    }
  }

  /// 获取视频文件所在目录
  String _getVideoDirectory(String filePath) {
    final lastSlash = filePath.lastIndexOf('/');
    if (lastSlash > 0) {
      return filePath.substring(0, lastSlash);
    }
    return filePath;
  }

  /// 显示字幕下载对话框
  Future<void> _showSubtitleDownloadDialog({
    int? seasonNumber,
    int? episodeNumber,
    required String savePath,
  }) async {
    // 获取本地化标题
    final titleGetter = ref.read(videoTitleGetterProvider);
    final displayTitle = titleGetter(_selectedMetadata);

    await SubtitleDownloadDialog.show(
      context: context,
      tmdbId: _selectedMetadata.tmdbId,
      title: displayTitle,
      seasonNumber: seasonNumber ?? _selectedMetadata.seasonNumber,
      episodeNumber: episodeNumber ?? _selectedMetadata.episodeNumber,
      isMovie: !_isTvShow,
      savePath: savePath,
      onDownloaded: (path) {
        logger.i('字幕已下载到: $path');
        // 刷新字幕缓存
        // 如果用户返回播放页面，将会重新扫描字幕
      },
    );
  }
}

/// 视频播放信息
class _VideoPlayInfo {
  const _VideoPlayInfo({
    required this.url,
    required this.size,
  });

  final String url;
  final int size;
}

/// 电影系列完整列表页面
class MovieCollectionListPage extends ConsumerWidget {
  const MovieCollectionListPage({
    required this.collection,
    required this.currentMovieId,
    required this.sourceId,
    super.key,
  });

  final TmdbCollection collection;
  final int currentMovieId;
  final String sourceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final uiStyle = ref.watch(uiStyleProvider);
    final sortedParts = collection.sortedParts;
    final safeTop = MediaQuery.of(context).padding.top;

    // iOS 26 玻璃模式：Stack 布局 + 悬浮玻璃返回按钮
    if (uiStyle.isGlass) {
      return Scaffold(
        backgroundColor: isDark ? AppColors.darkBackground : Colors.grey[50],
        body: Stack(
          children: [
            // 主内容
            CustomScrollView(
              slivers: [
                // Hero 背景图区域
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 220,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (collection.backdropUrl.isNotEmpty)
                          Image.network(
                            collection.backdropUrl,
                            fit: BoxFit.cover,
                          )
                        else
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.darkSurfaceVariant : Colors.grey[300],
                            ),
                          ),
                        // 渐变遮罩
                        DecoratedBox(
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
                        // 底部标题
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 16,
                          child: Text(
                            collection.name,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              shadows: [
                                Shadow(
                                  offset: Offset(0, 1),
                                  blurRadius: 4,
                                  color: Colors.black54,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 系列简介
                if (collection.overview.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        collection.overview,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),

                // 电影数量
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      '共 ${sortedParts.length} 部电影',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                      ),
                    ),
                  ),
                ),

                // 电影网格
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 160,
                      childAspectRatio: 0.55,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 16,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final part = sortedParts[index];
                        final isCurrentMovie = part.id == currentMovieId;

                        return _CollectionMovieGridItem(
                          part: part,
                          isCurrentMovie: isCurrentMovie,
                          sourceId: sourceId,
                          isDark: isDark,
                        );
                      },
                      childCount: sortedParts.length,
                    ),
                  ),
                ),

                // 底部留白
                const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
              ],
            ),

            // 悬浮返回按钮
            Positioned(
              top: safeTop + 8,
              left: 16,
              child: const GlassFloatingBackButton(),
            ),
          ],
        ),
      );
    }

    // 经典模式：使用 SliverAppBar
    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : Colors.grey[50],
      body: CustomScrollView(
        slivers: [
          // 顶部 AppBar 带背景图
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                collection.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(
                      offset: Offset(0, 1),
                      blurRadius: 4,
                      color: Colors.black54,
                    ),
                  ],
                ),
              ),
              background: collection.backdropUrl.isNotEmpty
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          collection.backdropUrl,
                          fit: BoxFit.cover,
                        ),
                        // 渐变遮罩
                        DecoratedBox(
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
                      ],
                    )
                  : DecoratedBox(
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkSurfaceVariant : Colors.grey[300],
                      ),
                    ),
            ),
          ),

          // 系列简介
          if (collection.overview.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  collection.overview,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ),
            ),

          // 电影数量
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                '共 ${sortedParts.length} 部电影',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                ),
              ),
            ),
          ),

          // 电影网格
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 160,
                childAspectRatio: 0.55,
                crossAxisSpacing: 12,
                mainAxisSpacing: 16,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final part = sortedParts[index];
                  final isCurrentMovie = part.id == currentMovieId;

                  return _CollectionMovieGridItem(
                    part: part,
                    isCurrentMovie: isCurrentMovie,
                    sourceId: sourceId,
                    isDark: isDark,
                  );
                },
                childCount: sortedParts.length,
              ),
            ),
          ),

          // 底部留白
          const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
        ],
      ),
    );
  }
}

/// 电影系列网格项
class _CollectionMovieGridItem extends ConsumerWidget {
  const _CollectionMovieGridItem({
    required this.part,
    required this.isCurrentMovie,
    required this.sourceId,
    required this.isDark,
  });

  final TmdbCollectionPart part;
  final bool isCurrentMovie;
  final String sourceId;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 检查本地是否有该电影
    final localVideoAsync = ref.watch(localVideoByTmdbIdProvider(part.id));
    final localVideo = localVideoAsync.valueOrNull;
    final hasLocal = localVideo != null;

    return GestureDetector(
      onTap: () => _onTap(context, ref, localVideo),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: isCurrentMovie
              ? Border.all(color: AppColors.primary, width: 2)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 海报
            Flexible(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // 海报图片
                    if (part.posterUrl.isNotEmpty)
                      Image.network(
                        part.posterUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _buildPlaceholder(),
                      )
                    else
                      _buildPlaceholder(),

                    // 当前电影标识
                    if (isCurrentMovie)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            '当前',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),

                    // 本地可用标识
                    if (hasLocal && !isCurrentMovie)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppColors.success,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            size: 12,
                            color: Colors.white,
                          ),
                        ),
                      ),

                    // 评分
                    if (part.voteAverage > 0)
                      Positioned(
                        bottom: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                size: 12,
                                color: Colors.amber,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                part.ratingText,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.white,
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
            ),

            // 标题
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                part.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                ),
              ),
            ),

            // 年份
            if (part.year != null)
              Text(
                '${part.year}',
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
    );
  }

  Widget _buildPlaceholder() => Container(
        color: isDark ? AppColors.darkSurfaceVariant : Colors.grey[300],
        child: Center(
          child: Icon(
            Icons.movie_rounded,
            size: 40,
            color: isDark ? Colors.grey[600] : Colors.grey[500],
          ),
        ),
      );

  void _onTap(BuildContext context, WidgetRef ref, VideoMetadata? localVideo) {
    if (isCurrentMovie) {
      Navigator.of(context).pop(); // 返回当前详情页
      return;
    }

    if (localVideo != null) {
      // 本地有该电影，跳转到详情页
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (context) => VideoDetailPage(
            metadata: localVideo,
            sourceId: localVideo.sourceId,
          ),
        ),
      );
    } else {
      // 本地没有该电影，显示操作选项
      _showMissingMovieActions(context, ref);
    }
  }

  /// 显示缺失电影的操作选项
  void _showMissingMovieActions(BuildContext context, WidgetRef ref) {
    final ptSites = ref.read(ptSitesSourcesProvider);
    final nastoolSources = ref.read(nastoolSourcesProvider);
    final hasPtSites = ptSites.isNotEmpty;
    final hasNastool = nastoolSources.isNotEmpty;

    // 如果没有配置任何服务，跳转到 TmdbPreviewPage
    if (!hasPtSites && !hasNastool) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => TmdbPreviewPage(
            tmdbId: part.id,
            isMovie: true,
            title: part.title,
            posterUrl: part.posterUrl,
          ),
        ),
      );
      return;
    }

    showAdaptiveModalSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _MissingMovieActionSheet(
        title: part.title,
        tmdbId: part.id,
        year: part.year?.toString(),
        posterUrl: part.posterUrl,
        ptSites: ptSites,
        nastoolSources: nastoolSources,
      ),
    );
  }
}

/// 缺失电影的操作选项底部弹窗
class _MissingMovieActionSheet extends ConsumerWidget {
  const _MissingMovieActionSheet({
    required this.title,
    required this.tmdbId,
    required this.year,
    required this.posterUrl,
    required this.ptSites,
    required this.nastoolSources,
  });

  final String title;
  final int tmdbId;
  final String? year;
  final String posterUrl;
  final List<SourceEntity> ptSites;
  final List<SourceEntity> nastoolSources;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 拖动指示器
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[600] : Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // 标题
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.cloud_off_rounded,
                      color: AppColors.warning,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '本地不可用',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 操作选项
            if (ptSites.isNotEmpty)
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.search,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                ),
                title: const Text(
                  '在 PT 站搜索',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  '搜索 "$title"',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(context);
                  _onPtSearch(context, ref);
                },
              ),
            if (nastoolSources.isNotEmpty)
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF673AB7).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.add_alert,
                    color: Color(0xFF673AB7),
                    size: 20,
                  ),
                ),
                title: const Text(
                  '添加 NASTool 订阅',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  '订阅 "$title"',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(context);
                  _onNastoolSubscribe(context, ref);
                },
              ),
            // 查看详情
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.info_outline,
                  color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                  size: 20,
                ),
              ),
              title: const Text(
                '查看详情',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: Text(
                '查看 TMDB 信息',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => TmdbPreviewPage(
                      tmdbId: tmdbId,
                      isMovie: true,
                      title: title,
                      posterUrl: posterUrl,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _onPtSearch(BuildContext context, WidgetRef ref) {
    if (ptSites.length == 1) {
      // 只有一个 PT 站，直接跳转
      _navigateToPtSite(context, ref, ptSites.first);
    } else {
      // 多个 PT 站，显示选择弹窗
      _showPtSiteSelection(context, ref);
    }
  }

  void _navigateToPtSite(BuildContext context, WidgetRef ref, SourceEntity source) {
    // 拼接年份能显著提高 PT 站搜索命中率（同名作品多年份重制版常见）
    final query = (year != null && year!.isNotEmpty) ? '$title $year' : title;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => PTSiteDetailPage(
          source: source,
          initialQuery: query,
        ),
      ),
    );
  }

  void _showPtSiteSelection(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showAdaptiveModalSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[600] : Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.search,
                        color: Theme.of(context).colorScheme.primary,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '选择 PT 站',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '搜索: $title',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ...ptSites.map((site) => ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: site.type.themeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    site.type.icon,
                    color: site.type.themeColor,
                    size: 20,
                  ),
                ),
                title: Text(
                  site.name.isEmpty ? site.type.displayName : site.name,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  site.host,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(context);
                  _navigateToPtSite(context, ref, site);
                },
              )),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _onNastoolSubscribe(BuildContext context, WidgetRef ref) {
    if (nastoolSources.length == 1) {
      _addNastoolSubscribe(context, ref, nastoolSources.first);
    } else {
      _showNastoolSelection(context, ref);
    }
  }

  Future<void> _addNastoolSubscribe(BuildContext context, WidgetRef ref, SourceEntity source) async {
    try {
      final connection = ref.read(nastoolConnectionProvider(source.id));
      if (connection == null || connection.status != NasToolConnectionStatus.connected) {
        context.showWarningToast('${source.name} 未连接');
        return;
      }

      await ref.read(nastoolActionsProvider(source.id)).addSubscribe(
        name: title,
        type: 'MOV',
        year: year,
        mediaId: 'tmdb:$tmdbId',
      );

      if (context.mounted) {
        context.showSuccessToast('已添加订阅: $title');
      }
    } catch (e, st) {
      AppError.handle(e, st, 'addNastoolSubscribeFromCollection');
      if (context.mounted) {
        context.showErrorToast('添加订阅失败: $e');
      }
    }
  }

  void _showNastoolSelection(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showAdaptiveModalSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[600] : Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFF673AB7).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.add_alert,
                        color: Color(0xFF673AB7),
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '选择 NASTool',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '订阅: $title',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ...nastoolSources.map((source) => ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: source.type.themeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    source.type.icon,
                    color: source.type.themeColor,
                    size: 20,
                  ),
                ),
                title: Text(
                  source.name.isEmpty ? source.type.displayName : source.name,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  source.host,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(context);
                  _addNastoolSubscribe(context, ref, source);
                },
              )),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
