import 'dart:async';

import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/background_task_pool.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/data/services/nfo_scraper_service.dart';
import 'package:my_nas/features/video/data/services/nfo_writer_service.dart';
import 'package:my_nas/features/video/data/services/remote_poster_service.dart';
import 'package:my_nas/features/video/data/services/scraper_manager_service.dart';
import 'package:my_nas/features/video/data/services/tmdb_service.dart';
import 'package:my_nas/features/video/data/services/video_database_service.dart';
import 'package:my_nas/features/video/data/services/video_history_service.dart';
import 'package:my_nas/features/video/data/services/video_poster_cache_service.dart';
import 'package:my_nas/features/video/data/services/video_thumbnail_service.dart';
import 'package:my_nas/features/video/domain/entities/scraper_result.dart';
import 'package:my_nas/features/video/domain/entities/scraper_source.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

/// 视频元数据服务 - 使用 SQLite 后端，支持大规模数据
class VideoMetadataService {
  factory VideoMetadataService() => _instance ??= VideoMetadataService._();
  VideoMetadataService._();

  static VideoMetadataService? _instance;

  final VideoDatabaseService _db = VideoDatabaseService();
  final ScraperManagerService _scraperManager = ScraperManagerService();
  final TmdbService _tmdbService = TmdbService(); // 仅用于 TMDB 特定功能（NFO、翻译）
  final NfoScraperService _nfoService = NfoScraperService();
  final NfoWriterService _nfoWriterService = NfoWriterService();
  final RemotePosterService _remotePosterService = RemotePosterService();
  final VideoThumbnailService _thumbnailService = VideoThumbnailService();
  final VideoHistoryService _historyService = VideoHistoryService();
  final VideoPosterCacheService _posterCacheService = VideoPosterCacheService();

  bool _initialized = false;

  /// 初始化
  Future<void> init() async {
    if (_initialized) return;

    try {
      // 并行初始化 SQLite、ThumbnailService、PosterCacheService 和 ScraperManager
      await Future.wait([
        _db.init(),
        _thumbnailService.init(),
        _posterCacheService.init(),
        _scraperManager.init(),
      ]);

      _initialized = true;

      final stats = await _db.getStats();
      logger.i('VideoMetadataService: 初始化完成，SQLite 条目: ${stats['total']}');
    } catch (e, st) {
      AppError.handle(e, st, 'VideoMetadataService.init');
      rethrow;
    }
  }

  /// 获取缓存的元数据（异步，使用 SQLite）
  Future<VideoMetadata?> getCachedAsync(String sourceId, String filePath) async {
    if (!_initialized) await init();
    return _db.get(sourceId, filePath);
  }

  /// 批量获取缓存的元数据（异步）
  Future<Map<String, VideoMetadata>> getCachedBatch(
      List<({String sourceId, String filePath})> keys) async {
    if (!_initialized) await init();
    return _db.getBatch(keys);
  }

  /// 保存元数据
  Future<void> save(VideoMetadata metadata) async {
    if (!_initialized) await init();
    await _db.upsert(metadata);
  }

  /// 批量保存元数据
  Future<void> saveBatch(List<VideoMetadata> metadataList) async {
    if (!_initialized) await init();
    await _db.upsertBatch(metadataList);
  }

  /// 删除元数据
  Future<void> delete(String sourceId, String filePath) async {
    if (!_initialized) await init();
    // 清理海报缓存
    await _posterCacheService.deleteCachedPoster(sourceId, filePath);
    await _db.delete(sourceId, filePath);
  }

  /// 清除所有缓存
  Future<void> clearAll() async {
    if (!_initialized) await init();
    await _db.clearAll();
  }

  // ============ 索引查询方法（使用 SQLite 索引）============

  /// 根据 TMDB ID 获取所有匹配的元数据
  Future<List<VideoMetadata>> getByTmdbId(int tmdbId) async {
    if (!_initialized) await init();
    return _db.getByTmdbId(tmdbId);
  }

  /// 获取同一电影的所有版本（不同清晰度）
  ///
  /// 按分辨率降序排序（4K > 1080p > 720p），相同分辨率按文件大小降序
  /// 用于电影详情页显示版本选择
  Future<List<VideoMetadata>> getMovieVersions(VideoMetadata metadata) async {
    if (!_initialized) await init();
    return _db.getMovieVersions(metadata);
  }

  /// 获取同一电影的版本数量
  Future<int> getMovieVersionCount(VideoMetadata metadata) async {
    if (!_initialized) await init();
    return _db.getMovieVersionCount(metadata);
  }

  /// 根据 TMDB ID 获取剧集映射
  Future<Map<int, Map<int, VideoMetadata>>> getEpisodesByTmdbId(int tmdbId) async {
    if (!_initialized) await init();
    return _db.getEpisodesByTmdbId(tmdbId);
  }

  /// 根据 showDirectory 获取剧集映射（用于无 TMDB 的剧集）
  Future<Map<int, Map<int, VideoMetadata>>> getEpisodesByShowDirectory(String showDirectory) async {
    if (!_initialized) await init();
    return _db.getEpisodesByShowDirectory(showDirectory);
  }

  /// 获取所有 TMDB ID 集合
  Future<Set<int>> getAllTmdbIds() async {
    if (!_initialized) await init();
    return _db.getAllTmdbIds();
  }

  /// 根据 TMDB ID 获取第一个匹配的元数据
  Future<VideoMetadata?> getFirstByTmdbId(int tmdbId) async {
    if (!_initialized) await init();
    return _db.getFirstByTmdbId(tmdbId);
  }

  /// 根据分类获取元数据（分页）
  Future<List<VideoMetadata>> getByCategory(
    MediaCategory category, {
    int limit = 50,
    int offset = 0,
  }) async {
    if (!_initialized) await init();
    return _db.getByCategory(category, limit: limit, offset: offset);
  }

  /// 根据年份获取元数据（分页）
  Future<List<VideoMetadata>> getByYear(int year, {int limit = 50, int offset = 0}) async {
    if (!_initialized) await init();
    return _db.getByYear(year, limit: limit, offset: offset);
  }

  /// 根据类型获取元数据（分页）
  Future<List<VideoMetadata>> getByGenre(String genre, {int limit = 50, int offset = 0}) async {
    if (!_initialized) await init();
    return _db.getByGenre(genre, limit: limit, offset: offset);
  }

  /// 获取高评分内容（分页）
  Future<List<VideoMetadata>> getTopRated({
    double minRating = 7.0,
    MediaCategory? category,
    int limit = 50,
    int offset = 0,
  }) async {
    if (!_initialized) await init();
    return _db.getTopRated(
      minRating: minRating,
      category: category,
      limit: limit,
      offset: offset,
    );
  }

  /// 分页获取元数据
  Future<List<VideoMetadata>> getPage({
    int limit = 50,
    int offset = 0,
    MediaCategory? category,
  }) async {
    if (!_initialized) await init();
    return _db.getPage(limit: limit, offset: offset, category: category);
  }

  /// 搜索元数据
  Future<List<VideoMetadata>> search(String query, {int limit = 50, int offset = 0}) async {
    if (!_initialized) await init();
    return _db.search(query, limit: limit, offset: offset);
  }

  /// 获取统计信息
  Future<Map<String, dynamic>> getStats() async {
    if (!_initialized) await init();
    return _db.getStats();
  }

  /// 获取总数量
  Future<int> getCount({MediaCategory? category}) async {
    if (!_initialized) await init();
    return _db.getCount(category: category);
  }

  // ============ 元数据获取方法 ============

  /// 当播放进度更新时，刷新缩略图
  Future<void> refreshThumbnailOnProgressUpdate({
    required String sourceId,
    required String filePath,
    required String videoUrl,
    NasFileSystem? fileSystem,
  }) async {
    try {
      final metadata = await getCachedAsync(sourceId, filePath);
      if (metadata == null) return;

      if (metadata.posterUrl != null || metadata.thumbnailUrl != null) {
        logger.d('VideoMetadataService: 视频有刮削封面，跳过缩略图更新');
        return;
      }

      await _thumbnailService.deleteCached(filePath);
      await _tryGenerateThumbnail(metadata, videoUrl, fileSystem);
      await save(metadata);

      logger.i('VideoMetadataService: 已更新缩略图为当前播放位置 "${metadata.fileName}"');
    } on Exception catch (e) {
      logger.w('VideoMetadataService: 更新缩略图失败', e);
    }
  }

  /// 获取或刷新元数据
  ///
  /// [skipThumbnail] 为 true 时跳过缩略图生成（用于批量刮削时提高速度）
  Future<VideoMetadata> getOrFetch({
    required String sourceId,
    required String filePath,
    required String fileName,
    NasFileSystem? fileSystem,
    String? videoUrl,
    bool forceRefresh = false,
    bool skipThumbnail = false,
  }) async {
    if (!_initialized) await init();

    // 检查缓存
    var metadata = await getCachedAsync(sourceId, filePath);

    if (metadata != null && !forceRefresh) {
      final needsUpdate = metadata.lastUpdated == null ||
          DateTime.now().difference(metadata.lastUpdated!).inDays > 7;

      if (!needsUpdate && metadata.hasMetadata) {
        return metadata;
      }
    }

    // 创建新的元数据
    metadata ??= VideoMetadata(
      filePath: filePath,
      sourceId: sourceId,
      fileName: fileName,
    );

    // 优先尝试从 NFO 文件获取信息
    var hasNfoData = false;
    if (fileSystem != null) {
      hasNfoData = await _fetchFromNfo(metadata, fileSystem);
    }

    // 如果 NFO 没有数据或缺少关键信息，尝试从刮削源获取
    // 传入 fileSystem 以便将 NFO 和海报写入远程目录
    if (!hasNfoData || !metadata.hasMetadata) {
      await _fetchFromScrapers(metadata, fileSystem);
    } else if (hasNfoData &&
               metadata.category == MediaCategory.movie &&
               metadata.collectionId == null &&
               metadata.tmdbId != null) {
      // NFO 刮削成功但缺少系列信息：尝试从 TMDB 补充
      // 仅补充 collectionId/collectionName，不覆盖其他元数据
      await _supplementCollectionFromTmdb(metadata);
    }

    // 捕获非空引用供闭包使用（避免 Dart 类型分析器警告）
    final metadataRef = metadata;

    // 下载海报到本地缓存（支持离线显示）
    // 使用任务池限制并发，防止大量视频同时下载导致手机发热
    if (metadataRef.posterUrl != null && metadataRef.localPosterUrl == null) {
      BackgroundTaskPool.media.addFireAndForget(
        () => _downloadPosterAndSave(metadataRef, fileSystem),
        taskName: 'downloadPoster:${metadataRef.fileName}',
      );
    }

    // 如果没有封面图，尝试生成缩略图（可跳过以加速刮削）
    // 缩略图生成是 CPU 密集型操作，必须限制并发
    if (!skipThumbnail && metadataRef.displayPosterUrl == null && videoUrl != null) {
      BackgroundTaskPool.media.addFireAndForget(
        () => _tryGenerateThumbnailAndSave(metadataRef, videoUrl, fileSystem),
        taskName: 'generateThumbnail:${metadataRef.fileName}',
      );
    }

    // 保存到缓存
    await save(metadata);

    return metadata;
  }

  /// 异步下载海报并保存（后台执行，不阻塞）
  Future<void> _downloadPosterAndSave(
    VideoMetadata metadata,
    NasFileSystem? fileSystem,
  ) async {
    try {
      final localUrl = await _posterCacheService.downloadAndCachePoster(
        sourceId: metadata.sourceId,
        filePath: metadata.filePath,
        posterUrl: metadata.posterUrl!,
        fileSystem: fileSystem,
      );

      if (localUrl != null) {
        metadata.localPosterUrl = localUrl;
        await save(metadata);
        logger.d('VideoMetadataService: 海报已缓存到本地 "${metadata.fileName}"');

        // 异步写入远程目录（不阻塞，不更新 localPosterUrl）
        // 仅当海报来自 TMDB（网络 URL）时才写入远程
        if (fileSystem != null && metadata.posterUrl!.startsWith('http')) {
          BackgroundTaskPool.media.addFireAndForget(
            () => _uploadPosterToRemote(metadata, fileSystem),
            taskName: 'uploadPosterRemote:${metadata.fileName}',
          );
        }
      }
    } on Exception catch (e) {
      logger.w('VideoMetadataService: 下载海报失败 "${metadata.fileName}"', e);
    }
  }

  /// 异步上传海报到远程目录（后台任务，仅作为备份/Kodi兼容）
  Future<void> _uploadPosterToRemote(
    VideoMetadata metadata,
    NasFileSystem fileSystem,
  ) async {
    try {
      final videoDir = _getParentPath(metadata.filePath);
      await _remotePosterService.downloadAndSavePoster(
        fileSystem: fileSystem,
        videoDir: videoDir,
        posterUrl: metadata.posterUrl!,
        type: PosterType.poster,
        videoFileName: metadata.fileName,
      );
      logger.d('VideoMetadataService: 海报已上传到远程目录 "$videoDir"');
    } on Exception catch (e) {
      logger.w('VideoMetadataService: 上传海报到远程目录失败 "${metadata.fileName}"', e);
    }
  }

  /// 异步生成缩略图并保存（后台执行，不阻塞）
  Future<void> _tryGenerateThumbnailAndSave(
    VideoMetadata metadata,
    String videoUrl,
    NasFileSystem? fileSystem,
  ) async {
    try {
      await _tryGenerateThumbnail(metadata, videoUrl, fileSystem);
      // 如果成功生成了缩略图，更新数据库
      if (metadata.generatedThumbnailUrl != null) {
        await save(metadata);
        logger.d('VideoMetadataService: 后台缩略图生成完成 "${metadata.fileName}"');
      }
    } on Exception catch (e) {
      logger.w('VideoMetadataService: 后台缩略图生成失败 "${metadata.fileName}"', e);
    }
  }

  /// 尝试为视频生成缩略图
  Future<void> _tryGenerateThumbnail(
    VideoMetadata metadata,
    String videoUrl,
    NasFileSystem? fileSystem,
  ) async {
    try {
      final cachedUrl = _thumbnailService.getCachedThumbnailUrl(metadata.filePath);
      if (cachedUrl != null) {
        metadata.generatedThumbnailUrl = cachedUrl;
        return;
      }

      var timeMs = 5000;
      final progress = await _historyService.getProgress(metadata.filePath);
      if (progress != null && progress.position.inMilliseconds > 0) {
        timeMs = progress.position.inMilliseconds;
        logger.d('VideoMetadataService: 使用播放历史位置生成缩略图 "${metadata.fileName}" @ ${progress.position.inSeconds}s');
      } else {
        logger.d('VideoMetadataService: 尝试为 "${metadata.fileName}" 生成缩略图 @ 5s');
      }

      final thumbnailPath = await _thumbnailService.generateThumbnail(
        videoUrl: videoUrl,
        videoPath: metadata.filePath,
        timeMs: timeMs,
        fileSystem: fileSystem,
      );

      if (thumbnailPath != null) {
        metadata.generatedThumbnailUrl = _thumbnailService.getCachedThumbnailUrl(metadata.filePath);
        logger.i('VideoMetadataService: 缩略图生成成功 "${metadata.fileName}"');
      }
    } on Exception catch (e) {
      logger.w('VideoMetadataService: 生成缩略图失败 "${metadata.fileName}"', e);
    }
  }

  /// 从 NFO 文件获取元数据
  Future<bool> _fetchFromNfo(VideoMetadata metadata, NasFileSystem fileSystem) async {
    try {
      final nfoData = await _nfoService.scrapeFromDirectory(
        fileSystem: fileSystem,
        videoPath: metadata.filePath,
        videoFileName: metadata.fileName,
      );

      if (nfoData != null && nfoData.hasData) {
        metadata..category = nfoData.seasonNumber != null || nfoData.episodeNumber != null
            ? MediaCategory.tvShow
            : MediaCategory.movie
        ..tmdbId = nfoData.tmdbId
        ..title = nfoData.title
        ..originalTitle = nfoData.originalTitle
        ..year = nfoData.year
        ..overview = nfoData.plot
        ..rating = nfoData.rating
        ..runtime = nfoData.runtime
        ..genres = nfoData.genres?.join(' / ')
        ..countries = nfoData.countries?.join(', ')
        ..director = nfoData.director
        ..cast = nfoData.actors?.take(5).join(', ')
        ..seasonNumber = nfoData.seasonNumber
        ..episodeNumber = nfoData.episodeNumber
        ..episodeTitle = nfoData.episodeTitle
        ..lastUpdated = DateTime.now();

        // 如果 NFO 包含 <set> 标签，使用其作为电影系列信息
        if (nfoData.setName != null) {
          // 优先使用 TMDB 系列 ID（如果有），否则使用负数 ID
          if (nfoData.setTmdbId != null) {
            metadata
              ..collectionId = nfoData.setTmdbId
              ..collectionName = nfoData.setName;
            logger.d('VideoMetadataService: 从 NFO 获取到 TMDB 电影系列 '
                '"${nfoData.setName}" (ID: ${nfoData.setTmdbId})');
          } else {
            // 使用负数 ID 区分 NFO 系列和 TMDB 系列
            metadata
              ..collectionId = -1 * nfoData.setName.hashCode.abs()
              ..collectionName = nfoData.setName;
            logger.d('VideoMetadataService: 从 NFO 获取到电影系列 "${nfoData.setName}"');
          }
        }

        // 存储本地海报路径（用于 StreamImage 流式加载）
        if (nfoData.posterPath != null) {
          metadata.localPosterUrl = nfoData.posterPath;
        }

        // 存储本地背景图路径（用于 StreamImage 流式加载）
        if (nfoData.fanartPath != null) {
          // 背景图使用 localPosterUrl 以外的字段无法存储，暂时不处理
          // TODO: 考虑添加 localBackdropUrl 字段
          // 目前使用 backdropUrl 存储路径，显示时需要识别并使用流式加载
          metadata.backdropUrl = nfoData.fanartPath;
        }

        logger.d('VideoMetadataService: 从 NFO 获取到元数据 "${nfoData.title}"'
            '${nfoData.posterPath != null ? ", poster: ${nfoData.posterPath}" : ""}'
            '${nfoData.fanartPath != null ? ", fanart: ${nfoData.fanartPath}" : ""}');
        return true;
      }
    } on Exception catch (e) {
      logger.w('VideoMetadataService: 从 NFO 获取元数据失败', e);
    }
    return false;
  }

  /// 从刮削源获取元数据（按优先级尝试所有已启用的刮削源）
  ///
  /// 如果 [fileSystem] 不为 null，会将 NFO 文件和海报图片写入到视频所在的远程目录，
  /// 使刮削数据可被 Kodi/Jellyfin/Plex 等软件使用。
  Future<void> _fetchFromScrapers(VideoMetadata metadata, NasFileSystem? fileSystem) async {
    // 检查是否有可用的刮削源
    final enabledScrapers = await _scraperManager.getEnabledScrapers();
    if (enabledScrapers.isEmpty) {
      logger.w('VideoMetadataService: 没有已启用的刮削源');
      return;
    }

    final info = VideoFileNameParser.parse(metadata.fileName);
    logger.d('VideoMetadataService: 解析文件名 "${metadata.fileName}" -> '
        'title: "${info.cleanTitle}", year: ${info.year}, '
        'S${info.season}E${info.episode}');

    if (info.cleanTitle.isEmpty) {
      return;
    }

    try {
      ScraperMovieDetail? movieDetail;
      ScraperTvDetail? tvDetail;

      if (info.isTvShow) {
        // 获取电视剧详情
        tvDetail = await _scraperManager.getTvDetail(
          query: info.cleanTitle,
          year: info.year,
        );

        if (tvDetail != null) {
          String? episodeTitle;

          // 如果来源是 TMDB，尝试获取具体的剧集标题
          if (tvDetail.source == ScraperType.tmdb &&
              info.season != null &&
              info.episode != null) {
            final seasonDetail = await _scraperManager.getSeasonDetail(
              tvId: tvDetail.externalId,
              seasonNumber: info.season!,
              source: ScraperType.tmdb,
            );
            if (seasonDetail != null) {
              final episode = seasonDetail.getEpisode(info.episode!);
              episodeTitle = episode?.name;
            }
          }

          // 使用通用的 applyTo 方法更新元数据
          tvDetail.applyTo(
            metadata,
            seasonNumber: info.season,
            episodeNumber: info.episode,
            episodeTitle: episodeTitle,
          );

          // 仅对 TMDB 源获取多语言翻译
          if (tvDetail.source == ScraperType.tmdb && metadata.tmdbId != null) {
            _fetchAndStoreTranslations(
              metadata: metadata,
              tmdbId: metadata.tmdbId!,
              isMovie: false,
            );
          }

          logger.i('VideoMetadataService: 使用 ${tvDetail.source.displayName} '
              '匹配到电视剧 "${tvDetail.title}"');
        }
      } else {
        // 获取电影详情
        movieDetail = await _scraperManager.getMovieDetail(
          query: info.cleanTitle,
          year: info.year,
        );

        if (movieDetail != null) {
          // 使用通用的 applyTo 方法更新元数据
          movieDetail.applyTo(metadata);

          // 仅对 TMDB 源获取多语言翻译
          if (movieDetail.source == ScraperType.tmdb && metadata.tmdbId != null) {
            _fetchAndStoreTranslations(
              metadata: metadata,
              tmdbId: metadata.tmdbId!,
              isMovie: true,
            );
          }

          logger.i('VideoMetadataService: 使用 ${movieDetail.source.displayName} '
              '匹配到电影 "${movieDetail.title}"');
        }
      }

      // ---------------- 远程写入 NFO 和海报（仅 TMDB 源）----------------
      // 如果有 fileSystem 且成功获取了 TMDB 数据，将刮削结果写入远程目录
      // 目前 NFO 格式仅支持 TMDB，豆瓣源不写入 NFO
      if (fileSystem != null && metadata.tmdbId != null) {
        final videoDir = _getParentPath(metadata.filePath);
        final videoFileName = metadata.fileName;

        // 后台异步写入 NFO 和海报，不阻塞主流程
        BackgroundTaskPool.media.addFireAndForget(
          () => _writeNfoAndPosterToRemoteForTmdb(
            metadata: metadata,
            isMovie: movieDetail != null,
            fileSystem: fileSystem,
            videoDir: videoDir,
            videoFileName: videoFileName,
          ),
          taskName: 'writeNfoAndPoster:${metadata.fileName}',
        );
      }
    } on Exception catch (e) {
      logger.e('VideoMetadataService: 获取元数据失败', e);
    }
  }

  /// 获取文件的父目录路径
  String _getParentPath(String filePath) {
    final lastSlash = filePath.lastIndexOf('/');
    if (lastSlash > 0) {
      return filePath.substring(0, lastSlash);
    }
    return '/';
  }

  /// 异步获取并存储多语言翻译
  ///
  /// 后台运行，不阻塞主刮削流程
  void _fetchAndStoreTranslations({
    required VideoMetadata metadata,
    required int tmdbId,
    required bool isMovie,
  }) {
    // 使用 fire-and-forget 模式，后台异步执行
    BackgroundTaskPool.media.addFireAndForget(
      () async {
        try {
          final translations = isMovie
              ? await _tmdbService.getMovieTranslations(tmdbId)
              : await _tmdbService.getTvTranslations(tmdbId);

          if (translations != null && translations.translations.isNotEmpty) {
            // 获取用户偏好的语言列表
            final preferredLangs = _tmdbService.getPreferredLanguageCodes();

            // 为每个偏好语言存储翻译（如果有的话）
            for (final langCode in preferredLangs) {
              final translation = translations.getTranslation(langCode);
              if (translation != null) {
                if (translation.title != null && translation.title!.isNotEmpty) {
                  metadata.addLocalizedTitle(langCode, translation.title!);
                }
                if (translation.overview != null && translation.overview!.isNotEmpty) {
                  metadata.addLocalizedOverview(langCode, translation.overview!);
                }
              }
            }

            // 也存储原语言数据（通常是英文）
            final enTranslation = translations.getTranslation('en');
            if (enTranslation != null) {
              if (enTranslation.title != null && enTranslation.title!.isNotEmpty) {
                metadata.addLocalizedTitle('en', enTranslation.title!);
              }
              if (enTranslation.overview != null && enTranslation.overview!.isNotEmpty) {
                metadata.addLocalizedOverview('en', enTranslation.overview!);
              }
            }

            // 保存更新后的元数据
            await save(metadata);
            logger.d('VideoMetadataService: 已保存多语言翻译 for ${metadata.title}');
          }
        } on Exception catch (e) {
          // 翻译获取失败不影响主流程，仅记录日志
          logger.w('VideoMetadataService: 获取翻译失败', e);
        }
      },
      taskName: 'fetchTranslations:${metadata.fileName}',
    );
  }

  /// 将 NFO 和海报写入远程目录（仅支持 TMDB 源）
  ///
  /// 使用 metadata 中的 tmdbId 重新从 TMDB 获取详情，生成 NFO 文件
  Future<void> _writeNfoAndPosterToRemoteForTmdb({
    required VideoMetadata metadata,
    required bool isMovie,
    required NasFileSystem fileSystem,
    required String videoDir,
    required String videoFileName,
  }) async {
    if (metadata.tmdbId == null || !_tmdbService.hasApiKey) {
      return;
    }

    try {
      // 1. 从 TMDB 获取详细信息用于生成 NFO
      String? nfoContent;
      NfoType nfoType;

      if (isMovie) {
        final movieDetail = await _tmdbService.getMovieDetail(metadata.tmdbId!);
        if (movieDetail != null) {
          nfoContent = _nfoWriterService.generateFromTmdbMovie(movieDetail);
          nfoType = NfoType.movie;
        } else {
          return;
        }
      } else {
        final tvDetail = await _tmdbService.getTvDetail(metadata.tmdbId!);
        if (tvDetail != null) {
          nfoContent = _nfoWriterService.generateFromTmdbTvShow(tvDetail);
          nfoType = NfoType.tvShow;
        } else {
          return;
        }
      }

      // 2. 写入 NFO 文件
      await _nfoWriterService.writeNfoFile(
        fileSystem: fileSystem,
        videoDir: videoDir,
        nfoContent: nfoContent,
        type: nfoType,
        videoFileName: videoFileName,
      );

      // 3. 下载背景图（fanart）到远程目录
      // 注意：海报已在 _downloadPosterAndSave 中异步处理，这里只需处理背景图
      if (metadata.backdropUrl != null &&
          metadata.backdropUrl!.isNotEmpty &&
          metadata.backdropUrl!.startsWith('http')) {
        await _remotePosterService.downloadAndSavePoster(
          fileSystem: fileSystem,
          videoDir: videoDir,
          posterUrl: metadata.backdropUrl!,
          type: PosterType.fanart,
          videoFileName: videoFileName,
        );
      }

      logger.i('VideoMetadataService: NFO 已写入远程目录 "$videoDir"');
    } on Exception catch (e, st) {
      // 写入失败不影响主流程，仅记录警告
      logger.w('VideoMetadataService: 写入 NFO/海报到远程目录失败', e, st);
    }
  }


  /// 从 TMDB 补充电影系列信息
  ///
  /// 用于刮削成功但缺少系列信息的情况
  /// 仅更新 collectionId、collectionName 和系列海报，不覆盖其他元数据
  ///
  /// [save] 是否保存到数据库，默认为 false（由调用者统一保存）
  Future<bool> _supplementCollectionFromTmdb(VideoMetadata metadata, {bool save = false}) async {
    if (!_tmdbService.hasApiKey || metadata.tmdbId == null) return false;

    try {
      final movieDetail = await _tmdbService.getMovieDetail(metadata.tmdbId!);
      if (movieDetail != null && movieDetail.belongsToCollection != null) {
        final collection = movieDetail.belongsToCollection!;
        metadata
          ..collectionId = collection.id
          ..collectionName = collection.name
          ..collectionPosterUrl = collection.posterUrl
          ..collectionBackdropUrl = collection.backdropUrl;
        logger.d('VideoMetadataService: 从 TMDB 补充系列信息 '
            '"${collection.name}" for "${metadata.title}"');

        if (save) {
          await this.save(metadata);
        }
        return true;
      }
    } on Exception catch (e) {
      logger.w('VideoMetadataService: 补充 TMDB 系列信息失败', e);
    }
    return false;
  }

  /// 批量为缺少系列信息的电影补充数据
  ///
  /// 查找所有有 TMDB ID 但缺少 collectionId 的电影，从 TMDB 获取系列信息
  /// 返回成功补充的电影数量
  ///
  /// [onProgress] 进度回调，参数为 (已处理数量, 总数量)
  Future<int> supplementMissingCollections({
    void Function(int processed, int total)? onProgress,
  }) async {
    if (!_tmdbService.hasApiKey) {
      logger.w('VideoMetadataService: 无法补充系列信息，TMDB API Key 未配置');
      return 0;
    }

    if (!_initialized) await init();

    // 获取所有有 TMDB ID 但缺少 collectionId 的电影
    final movies = await _db.getMoviesWithoutCollection();
    if (movies.isEmpty) {
      logger.d('VideoMetadataService: 没有需要补充系列信息的电影');
      return 0;
    }

    logger.i('VideoMetadataService: 开始为 ${movies.length} 部电影补充系列信息');

    var successCount = 0;
    for (var i = 0; i < movies.length; i++) {
      final movie = movies[i];
      final success = await _supplementCollectionFromTmdb(movie, save: true);
      if (success) {
        successCount++;
      }

      onProgress?.call(i + 1, movies.length);

      // 添加延迟避免 TMDB API 限流
      if (i < movies.length - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }

    logger.i('VideoMetadataService: 系列信息补充完成，成功 $successCount/${movies.length}');
    return successCount;
  }

  /// 批量为缺少地区/类型信息的视频补充数据
  ///
  /// 查找所有有 TMDB ID 但缺少地区或类型信息的电影和剧集，从 TMDB 获取并更新
  /// 返回成功补充的视频数量
  ///
  /// [onProgress] 进度回调，参数为 (已处理数量, 总数量)
  Future<int> supplementMissingCountriesAndGenres({
    void Function(int processed, int total)? onProgress,
  }) async {
    if (!_tmdbService.hasApiKey) {
      logger.w('VideoMetadataService: 无法补充元数据，TMDB API Key 未配置');
      return 0;
    }

    if (!_initialized) await init();

    // 获取所有有 TMDB ID 但缺少地区或类型信息的电影
    final movies = await _db.getMoviesWithIncompleteMetadata();
    // 获取所有有 TMDB ID 但缺少地区或类型信息的剧集（去重）
    final tvShows = await _db.getTvShowsWithIncompleteMetadata();

    final totalCount = movies.length + tvShows.length;
    if (totalCount == 0) {
      logger.d('VideoMetadataService: 没有需要补充地区/类型信息的视频');
      return 0;
    }

    logger.i('VideoMetadataService: 开始为 ${movies.length} 部电影和 ${tvShows.length} 个剧集补充元数据');

    var successCount = 0;
    var processedCount = 0;

    // 补充电影元数据
    for (final movie in movies) {
      if (movie.tmdbId == null) continue;

      try {
        final detail = await _tmdbService.getMovieDetail(movie.tmdbId!);
        if (detail != null) {
          var needsUpdate = false;
          var updatedMovie = movie;

          // 更新地区信息
          final countriesList = detail.countriesList;
          if ((movie.countries == null || movie.countries!.isEmpty) &&
              countriesList != null && countriesList.isNotEmpty) {
            updatedMovie = updatedMovie.copyWith(countries: countriesList.join(', '));
            needsUpdate = true;
          }

          // 更新类型信息
          final genresList = detail.genresList;
          if ((movie.genres == null || movie.genres!.isEmpty) &&
              genresList != null && genresList.isNotEmpty) {
            updatedMovie = updatedMovie.copyWith(genres: genresList.join(' / '));
            needsUpdate = true;
          }

          if (needsUpdate) {
            await _db.upsert(updatedMovie);
            successCount++;
            logger.d('VideoMetadataService: 补充电影元数据 "${movie.displayTitle}"');
          }
        }
      } on Exception catch (e) {
        logger.w('VideoMetadataService: 补充电影 "${movie.displayTitle}" 元数据失败', e);
      }

      processedCount++;
      onProgress?.call(processedCount, totalCount);

      // 添加延迟避免 TMDB API 限流
      if (processedCount < totalCount) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }

    // 补充剧集元数据
    for (final tvShow in tvShows) {
      if (tvShow.tmdbId == null) continue;

      try {
        final detail = await _tmdbService.getTvDetail(tvShow.tmdbId!);
        if (detail != null) {
          final countriesText = detail.countriesText;
          final genresText = detail.genresText;

          final needsCountries = (tvShow.countries == null || tvShow.countries!.isEmpty) &&
              countriesText.isNotEmpty;
          final needsGenres = (tvShow.genres == null || tvShow.genres!.isEmpty) &&
              genresText.isNotEmpty;

          if (needsCountries || needsGenres) {
            // 批量更新同一剧集的所有集
            await _db.updateTvShowMetadata(
              showDirectory: tvShow.showDirectory,
              tmdbId: tvShow.tmdbId!,
              countries: needsCountries ? countriesText : null,
              genres: needsGenres ? genresText : null,
            );
            successCount++;
            logger.d('VideoMetadataService: 补充剧集元数据 "${tvShow.displayTitle}"');
          }
        }
      } on Exception catch (e) {
        logger.w('VideoMetadataService: 补充剧集 "${tvShow.displayTitle}" 元数据失败', e);
      }

      processedCount++;
      onProgress?.call(processedCount, totalCount);

      // 添加延迟避免 TMDB API 限流
      if (processedCount < totalCount) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }

    logger.i('VideoMetadataService: 元数据补充完成，成功 $successCount/$totalCount');
    return successCount;
  }

  /// 手动搜索（从所有已启用的刮削源搜索）
  Future<List<ScraperMediaItem>> searchMedia(String query, {bool isMovie = true}) async {
    try {
      final result = isMovie
          ? await _scraperManager.searchMovies(query)
          : await _scraperManager.searchTvShows(query);
      return result.items;
    } on Exception catch (e) {
      logger.e('VideoMetadataService: 搜索失败', e);
      return [];
    }
  }

  /// 手动匹配电影
  ///
  /// [externalId] 外部 ID（TMDB ID 或豆瓣 ID）
  /// [source] 数据来源类型
  Future<void> matchMovie(
    VideoMetadata metadata,
    String externalId,
    ScraperType source,
  ) async {
    try {
      final movieDetail = await _scraperManager.getMovieDetail(
        externalId: externalId,
        source: source,
      );

      if (movieDetail != null) {
        movieDetail.applyTo(metadata);
        await save(metadata);
        logger.i('VideoMetadataService: 手动匹配电影 "${movieDetail.title}" '
            '(来源: ${source.displayName})');
      }
    } on Exception catch (e) {
      logger.e('VideoMetadataService: 手动匹配电影失败', e);
    }
  }

  /// 手动匹配电视剧
  ///
  /// [externalId] 外部 ID（TMDB ID 或豆瓣 ID）
  /// [source] 数据来源类型
  Future<void> matchTvShow(
    VideoMetadata metadata,
    String externalId,
    ScraperType source, {
    int? season,
    int? episode,
  }) async {
    try {
      final tvDetail = await _scraperManager.getTvDetail(
        externalId: externalId,
        source: source,
      );

      if (tvDetail != null) {
        String? episodeTitle;

        // 仅 TMDB 支持获取具体剧集标题
        if (source == ScraperType.tmdb && season != null && episode != null) {
          final seasonDetail = await _scraperManager.getSeasonDetail(
            tvId: externalId,
            seasonNumber: season,
            source: source,
          );
          if (seasonDetail != null) {
            final ep = seasonDetail.getEpisode(episode);
            episodeTitle = ep?.name;
          }
        }

        tvDetail.applyTo(
          metadata,
          seasonNumber: season,
          episodeNumber: episode,
          episodeTitle: episodeTitle,
        );
        await save(metadata);
        logger.i('VideoMetadataService: 手动匹配电视剧 "${tvDetail.title}" '
            '(来源: ${source.displayName})');
      }
    } on Exception catch (e) {
      logger.e('VideoMetadataService: 手动匹配电视剧失败', e);
    }
  }

  /// 手动刮削并保存（用于手动刮削页面）
  ///
  /// 将刮削结果应用到视频元数据，保存到数据库，并可选地写入 NFO 和海报到远程目录
  ///
  /// [metadata] 要刮削的视频元数据
  /// [movieDetail] 电影详情（与 tvDetail 二选一）
  /// [tvDetail] 电视剧详情（与 movieDetail 二选一）
  /// [seasonNumber] 季号（电视剧专用）
  /// [episodeNumber] 集号（电视剧专用）
  /// [episodeTitle] 剧集标题（电视剧专用）
  /// [fileSystem] 远程文件系统（用于写入 NFO 和海报）
  /// [options] 刮削选项
  Future<void> scrapeAndSave({
    required VideoMetadata metadata,
    ScraperMovieDetail? movieDetail,
    ScraperTvDetail? tvDetail,
    int? seasonNumber,
    int? episodeNumber,
    String? episodeTitle,
    NasFileSystem? fileSystem,
    ScrapeOptions options = const ScrapeOptions(),
  }) async {
    if (movieDetail == null && tvDetail == null) {
      throw ArgumentError(appL10n.videoMetadataScrapeErrorBothDetailsRequired);
    }

    try {
      // 1. 应用刮削数据到元数据
      if (movieDetail != null) {
        movieDetail.applyTo(metadata);
        metadata.scrapeStatus = ScrapeStatus.completed;
      } else if (tvDetail != null) {
        tvDetail.applyTo(
          metadata,
          seasonNumber: seasonNumber,
          episodeNumber: episodeNumber,
          episodeTitle: episodeTitle,
        );
        metadata.scrapeStatus = ScrapeStatus.completed;
      }

      // 2. 保存到数据库
      if (options.updateMetadata) {
        await save(metadata);
      }

      // 3. 写入 NFO 和海报到远程目录
      if (fileSystem != null && (options.generateNfo || options.downloadPoster || options.downloadFanart)) {
        final videoDir = _getVideoDirectory(metadata.filePath);
        final videoFileName = metadata.fileName;

        // 生成并写入 NFO
        if (options.generateNfo) {
          String? nfoContent;
          NfoType nfoType;

          if (movieDetail != null) {
            nfoContent = _nfoWriterService.generateMovieNfo(
              title: movieDetail.title,
              originalTitle: movieDetail.originalTitle,
              year: movieDetail.year,
              rating: movieDetail.rating,
              plot: movieDetail.overview,
              tmdbId: movieDetail.source == ScraperType.tmdb
                  ? int.tryParse(movieDetail.externalId)
                  : null,
              imdbId: movieDetail.imdbId,
              genres: movieDetail.genres,
              runtime: movieDetail.runtime,
              director: movieDetail.director,
              tagline: movieDetail.tagline,
              collectionId: movieDetail.collectionId != null
                  ? int.tryParse(movieDetail.collectionId!)
                  : null,
              collectionName: movieDetail.collectionName,
            );
            nfoType = NfoType.movie;
          } else {
            nfoContent = _nfoWriterService.generateTvShowNfo(
              title: tvDetail!.title,
              originalTitle: tvDetail.originalTitle,
              year: tvDetail.year,
              rating: tvDetail.rating,
              plot: tvDetail.overview,
              tmdbId: tvDetail.source == ScraperType.tmdb
                  ? int.tryParse(tvDetail.externalId)
                  : null,
              imdbId: tvDetail.imdbId,
              genres: tvDetail.genres,
              runtime: tvDetail.episodeRuntime,
              status: tvDetail.status,
            );
            nfoType = NfoType.tvShow;
          }

          await _nfoWriterService.writeNfoFile(
            fileSystem: fileSystem,
            videoDir: videoDir,
            nfoContent: nfoContent,
            type: nfoType,
            videoFileName: videoFileName,
          );
        }

        // 下载海报到远程目录
        if (options.downloadPoster) {
          final posterUrl = movieDetail?.posterUrl ?? tvDetail?.posterUrl;
          if (posterUrl != null && posterUrl.isNotEmpty && posterUrl.startsWith('http')) {
            await _remotePosterService.downloadAndSavePoster(
              fileSystem: fileSystem,
              videoDir: videoDir,
              posterUrl: posterUrl,
              type: PosterType.poster,
              videoFileName: videoFileName,
            );
          }
        }

        // 下载背景图到远程目录
        if (options.downloadFanart) {
          final fanartUrl = movieDetail?.backdropUrl ?? tvDetail?.backdropUrl;
          if (fanartUrl != null && fanartUrl.isNotEmpty && fanartUrl.startsWith('http')) {
            await _remotePosterService.downloadAndSavePoster(
              fileSystem: fileSystem,
              videoDir: videoDir,
              posterUrl: fanartUrl,
              type: PosterType.fanart,
              videoFileName: videoFileName,
            );
          }
        }

        logger.i('VideoMetadataService: 手动刮削完成 "${metadata.title}" '
            '(来源: ${movieDetail?.source.displayName ?? tvDetail?.source.displayName})');
      }
    } on Exception catch (e, st) {
      logger.e('VideoMetadataService: 手动刮削失败', e, st);
      rethrow;
    }
  }

  /// 获取视频所在目录
  String _getVideoDirectory(String filePath) {
    final lastSlash = filePath.lastIndexOf('/');
    if (lastSlash > 0) {
      return filePath.substring(0, lastSlash);
    }
    // Windows 路径
    final lastBackSlash = filePath.lastIndexOf(r'\');
    if (lastBackSlash > 0) {
      return filePath.substring(0, lastBackSlash);
    }
    return filePath;
  }

  /// 批量获取元数据
  Future<List<VideoMetadata>> batchFetch(
    List<({String sourceId, String filePath, String fileName})> videos, {
    NasFileSystem? fileSystem,
    void Function(int current, int total)? onProgress,
  }) async {
    final results = <VideoMetadata>[];
    final total = videos.length;

    for (var i = 0; i < videos.length; i++) {
      final video = videos[i];
      onProgress?.call(i + 1, total);

      final metadata = await getOrFetch(
        sourceId: video.sourceId,
        filePath: video.filePath,
        fileName: video.fileName,
        fileSystem: fileSystem,
      );
      results.add(metadata);

      if (i < videos.length - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }

    return results;
  }

  /// 为没有封面的视频生成缩略图
  Future<String?> generateThumbnailForVideo({
    required String videoUrl,
    required String videoPath,
  }) async {
    try {
      final thumbnailPath = await _thumbnailService.generateThumbnail(
        videoUrl: videoUrl,
        videoPath: videoPath,
      );

      if (thumbnailPath != null) {
        return _thumbnailService.getCachedThumbnailUrl(videoPath);
      }
    } on Exception catch (e) {
      logger.w('VideoMetadataService: 生成视频缩略图失败', e);
    }
    return null;
  }

  /// 获取视频的显示封面 URL
  Future<String?> getDisplayPosterUrl({
    required VideoMetadata metadata,
    String? videoUrl,
  }) async {
    if (metadata.posterUrl != null && metadata.posterUrl!.isNotEmpty) {
      return metadata.posterUrl;
    }

    if (metadata.thumbnailUrl != null && metadata.thumbnailUrl!.isNotEmpty) {
      return metadata.thumbnailUrl;
    }

    final cachedUrl = _thumbnailService.getCachedThumbnailUrl(metadata.filePath);
    if (cachedUrl != null) {
      return cachedUrl;
    }

    if (videoUrl != null && videoUrl.isNotEmpty) {
      return generateThumbnailForVideo(
        videoUrl: videoUrl,
        videoPath: metadata.filePath,
      );
    }

    return null;
  }

  /// 批量更新电影系列信息
  ///
  /// 用于先扫描后设置刮削源的情况
  /// 查找所有有 TMDB ID 但没有系列信息的电影，从 TMDB 获取系列信息并更新
  ///
  /// [onProgress] 进度回调 (current, total, movieTitle)
  /// 返回更新的电影数量
  Future<int> batchUpdateCollectionInfo({
    void Function(int current, int total, String? title)? onProgress,
  }) async {
    if (!_tmdbService.hasApiKey) {
      logger.w('VideoMetadataService: 无法更新系列信息，未设置 TMDB API Key');
      return 0;
    }

    // 查找所有有 TMDB ID 但没有系列信息的电影
    final movies = await _db.getMoviesWithoutCollection();
    if (movies.isEmpty) {
      logger.i('VideoMetadataService: 没有需要更新系列信息的电影');
      return 0;
    }

    logger.i('VideoMetadataService: 开始批量更新系列信息，共 ${movies.length} 部电影');

    var updatedCount = 0;
    for (var i = 0; i < movies.length; i++) {
      final movie = movies[i];
      onProgress?.call(i + 1, movies.length, movie.title);

      if (movie.tmdbId == null) continue;

      try {
        final movieDetail = await _tmdbService.getMovieDetail(movie.tmdbId!);
        if (movieDetail != null && movieDetail.belongsToCollection != null) {
          final collection = movieDetail.belongsToCollection!;
          movie
            ..collectionId = collection.id
            ..collectionName = collection.name
            ..collectionPosterUrl = collection.posterUrl
            ..collectionBackdropUrl = collection.backdropUrl;
          await _db.upsert(movie);
          updatedCount++;
          logger.d('VideoMetadataService: 更新系列信息 "${movie.title}" -> '
              '"${collection.name}"');
        }
      } on Exception catch (e) {
        logger.w('VideoMetadataService: 获取 "${movie.title}" 系列信息失败', e);
      }

      // 添加延迟避免 API 限流
      if (i < movies.length - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }

    logger.i('VideoMetadataService: 批量更新系列信息完成，更新了 $updatedCount 部电影');
    return updatedCount;
  }

  /// 清除缩略图缓存
  Future<void> clearThumbnailCache() async {
    await _thumbnailService.clearAllCache();
  }

  /// 获取缩略图缓存大小
  Future<int> getThumbnailCacheSize() async => _thumbnailService.getCacheSize();
}

/// 刮削选项
class ScrapeOptions {
  const ScrapeOptions({
    this.updateMetadata = true,
    this.downloadPoster = true,
    this.downloadFanart = true,
    this.generateNfo = true,
  });

  /// 更新元数据（保存到数据库）
  final bool updateMetadata;

  /// 下载海报到视频目录
  final bool downloadPoster;

  /// 下载背景图到视频目录
  final bool downloadFanart;

  /// 生成 NFO 文件
  final bool generateNfo;
}
