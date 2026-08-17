import 'dart:async';
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/services/background_task_service.dart';
import 'package:my_nas/core/utils/background_task_pool.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/video/data/services/subtitle_service.dart';
import 'package:my_nas/features/video/data/services/video_database_service.dart';
import 'package:my_nas/features/video/data/services/video_library_cache_service.dart';
import 'package:my_nas/features/video/data/services/video_metadata_service.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/nas_adapters/smb/smb_file_system.dart';

/// 视频扫描进度
class VideoScanProgress {
  const VideoScanProgress({
    required this.phase,
    this.sourceId,
    this.pathPrefix,
    this.currentPath,
    this.scannedCount = 0,
    this.totalCount = 0,
    this.currentFile,
  });

  /// 扫描阶段
  final VideoScanPhase phase;

  /// 源ID（用于区分不同目录的进度）
  final String? sourceId;

  /// 目录路径前缀（用于区分不同目录的进度）
  final String? pathPrefix;

  /// 当前扫描的路径
  final String? currentPath;

  /// 已扫描数量
  final int scannedCount;

  /// 总数量（元数据阶段使用）
  final int totalCount;

  /// 当前处理的文件名
  final String? currentFile;

  /// 计算进度百分比
  double get progress {
    if (totalCount == 0) return 0;
    return scannedCount / totalCount;
  }

  /// 进度描述
  String get description {
    switch (phase) {
      case VideoScanPhase.scanning:
        return currentPath ?? appL10n.videoScanProgressDefault;
      case VideoScanPhase.savingToDb:
        return appL10n.videoScanProgressSavingToDb(scannedCount, totalCount);
      case VideoScanPhase.scraping:
        if (currentFile != null) {
          return appL10n.videoScanProgressScrapingFile(
            currentFile ?? '',
            scannedCount,
            totalCount,
          );
        }
        return appL10n.videoScanProgressScrapingMetadata(
          scannedCount,
          totalCount,
        );
      case VideoScanPhase.completed:
        return appL10n.videoScanCompletedCount(scannedCount);
      case VideoScanPhase.error:
        return appL10n.videoScanProgressFailed;
    }
  }
}

/// 扫描阶段
enum VideoScanPhase {
  /// 扫描文件系统
  scanning,

  /// 保存到数据库
  savingToDb,

  /// 刮削元数据（NFO/TMDB/缩略图）
  scraping,

  /// 完成
  completed,

  /// 错误
  error,
}

/// 视频扫描服务
///
/// 负责：
/// 1. 扫描配置的视频目录（快速，创建基础记录）
/// 2. 后台刮削信息（NFO > TMDB > 生成缩略图）
/// 3. 保存到 SQLite 数据库
///
/// 生命周期特性：
/// - 全局单例，不随页面生命周期销毁
/// - 支持应用重启后自动恢复未完成的刮削
/// - 页面切换不影响刮削进度
class VideoScannerService {
  factory VideoScannerService() => _instance ??= VideoScannerService._();

  VideoScannerService._() {
    // 监听来自后台任务的命令
    _setupBackgroundTaskListener();
  }

  static VideoScannerService? _instance;

  final VideoLibraryCacheService _cacheService = VideoLibraryCacheService();
  final VideoMetadataService _metadataService = VideoMetadataService();
  final VideoDatabaseService _dbService = VideoDatabaseService();
  final BackgroundTaskService _backgroundTaskService = BackgroundTaskService();

  bool _isScanning = false;

  bool get isScanning => _isScanning;

  bool _isScraping = false;

  bool get isScraping => _isScraping;

  bool _shouldStopScraping = false;

  // 用于恢复刮削的 connections 缓存（预留用于源断开重连场景）
  // ignore: unused_field
  Map<String, SourceConnection>? _cachedConnections;

  /// 设置后台任务监听器
  void _setupBackgroundTaskListener() {
    // 仅在移动平台设置监听
    if (!Platform.isAndroid && !Platform.isIOS) return;

    FlutterForegroundTask.addTaskDataCallback(_onBackgroundTaskData);
  }

  /// 处理来自后台任务的数据
  void _onBackgroundTaskData(Object data) {
    if (data is Map<String, dynamic>) {
      final command = data['command'] as String?;
      if (command == 'stop') {
        logger.i('VideoScannerService: 收到停止命令');
        stopScraping();
      }
    }
  }

  /// 扫描进度流
  final _progressController = StreamController<VideoScanProgress>.broadcast();

  Stream<VideoScanProgress> get progressStream => _progressController.stream;

  /// 刮削统计信息流
  final _scrapeStatsController = StreamController<ScrapeStats>.broadcast();

  Stream<ScrapeStats> get scrapeStatsStream => _scrapeStatsController.stream;

  /// 边扫边显示：部分扫描结果流（Infuse 风格）
  ///
  /// 每扫描一批文件就推送一次，UI 可以逐步显示内容
  /// 用户不需要等待扫描完成就能看到视频列表
  final _partialResultsController =
      StreamController<List<VideoMetadata>>.broadcast();

  Stream<List<VideoMetadata>> get partialResultsStream =>
      _partialResultsController.stream;

  /// 单视频更新流（Infuse 风格）
  ///
  /// 刮削完成单个视频后推送，UI 只需更新该视频的卡片
  /// 替代整体 scrapeStatsStream 刷新，实现精准更新
  final _videoUpdatedController = StreamController<VideoMetadata>.broadcast();

  Stream<VideoMetadata> get videoUpdatedStream =>
      _videoUpdatedController.stream;

  /// 检查并恢复未完成的刮削任务
  ///
  /// 在应用启动时调用，检查是否有待刮削的视频
  /// 如果有，自动开始刮削
  Future<void> checkAndResumeScraping(
    Map<String, SourceConnection> connections,
  ) async {
    if (_isScraping) {
      logger.d('VideoScannerService: 刮削已在进行中，跳过恢复检查');
      return;
    }

    try {
      await _dbService.init();
      final stats = await _dbService.getScrapeStats();

      if (stats.pending > 0) {
        logger.i('''
        VideoScannerService: 发现 ${stats.pending} 个待刮削视频，
          自动恢复刮削
          ''');
        // 缓存 connections 并开始刮削
        _cachedConnections = connections;
        AppError.fireAndForget(
          scrapeMetadata(connections: connections),
          action: 'checkAndResumeScraping.scrapeMetadata',
        );
      } else {
        // 没有待刮削视频时，检查并补充缺失的元数据
        // 延迟执行，避免影响启动性能
        Future.delayed(const Duration(seconds: 3), () {
          _metadataService.supplementMissingCountriesAndGenres().then((count) {
            if (count > 0) {
              logger.i('VideoScannerService: 启动时补充了 $count 个视频的地区/类型信息');
            }
          }).ignore();
        });
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '检查恢复刮削失败，非关键操作');
    }
  }

  /// 更新 connections 缓存（用于源重连后恢复刮削）
  void updateConnections(Map<String, SourceConnection> connections) {
    _cachedConnections = connections;
  }

  /// 广播当前刮削统计到 Stream
  ///
  /// 用于应用从后台恢复时强制刷新 UI 进度
  /// 这确保 UI 显示的进度与实际后台执行的进度同步
  Future<void> broadcastCurrentStats() async {
    try {
      await _dbService.init();
      final stats = await _dbService.getScrapeStats();
      _scrapeStatsController.add(stats);
      logger.d(
        'VideoScannerService: 已广播当前统计 - completed: ${stats.completed}, pending: ${stats.pending}',
      );
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '广播统计失败，非关键操作');
    }
  }

  /// 仅扫描文件（快速，不刮削元数据）
  ///
  /// 扫描完成后立即返回，视频可以在影院页面展示
  /// 刮削会在后台自动进行
  ///
  /// 注意：无深度限制，会递归扫描所有子目录
  Future<int> scanFilesOnly({
    required List<MediaLibraryPath> paths,
    required Map<String, SourceConnection> connections,
  }) async {
    if (_isScanning) {
      logger.w('VideoScannerService: 扫描正在进行中，跳过');
      return 0;
    }

    _isScanning = true;
    final allVideos = <_ScannedVideo>[];
    final allSubtitles = <_ScannedSubtitle>[];
    final sourceIds = <String>{};

    // 启动后台服务（移动平台）
    await _backgroundTaskService.init();
    await _backgroundTaskService.startService(
      taskType: BackgroundTaskType.videoScan,
      initialMessage: appL10n.videoScanBackgroundScanningLibrary,
    );

    try {
      // 初始化服务
      await _cacheService.init();
      await _dbService.init();

      // 阶段1：扫描文件系统
      // 记录每个目录的扫描结果，用于后续发送各目录的进度
      final pathVideoCounts =
          <(String sourceId, String pathPrefix, int count)>[];
      final completedSnapshots =
          <
            ({
              String sourceId,
              String pathPrefix,
              Set<String> encounteredPaths,
              bool canPrune,
            })
          >[];

      for (final path in paths) {
        if (!path.isEnabled) continue;

        final conn = connections[path.sourceId];
        if (conn == null || conn.status != SourceStatus.connected) {
          logger.w('VideoScannerService: 源 ${path.sourceId} 未连接，跳过');
          continue;
        }

        sourceIds.add(path.sourceId);
        final fileSystem = conn.adapter.fileSystem;

        // 断点续扫只会返回本次剩余目录中的文件，因此不能据此清理旧快照。
        // 全新扫描也不预删数据，等完整成功并写入新快照后再做差集清理。
        final hasUnfinished = await _dbService.hasUnfinishedScan(
          path.sourceId,
          path.path,
        );
        if (hasUnfinished) {
          logger.i(
            'VideoScannerService: 发现未完成扫描，保留已有数据继续扫描 ${path.sourceId}:${path.path}',
          );
        }

        // 为每个目录单独发送扫描开始事件（包含目录标识）
        _emitProgress(
          VideoScanProgress(
            phase: VideoScanPhase.scanning,
            sourceId: path.sourceId,
            pathPrefix: path.path,
          ),
        );

        // 创建当前目录的视频和字幕列表（用于计算单目录进度）
        final pathVideos = <_ScannedVideo>[];
        final pathSubtitles = <_ScannedSubtitle>[];

        // 使用增量扫描（支持断点续扫和并行处理）
        await _scanDirectoriesIncremental(
          fileSystem: fileSystem,
          sourceId: path.sourceId,
          rootPath: path.path,
          videos: pathVideos,
          subtitles: pathSubtitles,
          resumeExisting: hasUnfinished,
        );

        allVideos.addAll(pathVideos);
        allSubtitles.addAll(pathSubtitles);

        // 记录该目录的扫描数量
        pathVideoCounts.add((path.sourceId, path.path, pathVideos.length));
        completedSnapshots.add((
          sourceId: path.sourceId,
          pathPrefix: path.path,
          encounteredPaths: pathVideos.map((video) => video.file.path).toSet(),
          canPrune: !hasUnfinished,
        ));
      }

      logger.i('VideoScannerService: 文件扫描完成，共 ${allVideos.length} 个视频');

      // 阶段2：保存基础记录到 SQLite
      // 为每个目录发送 savingToDb 阶段进度
      for (final (sourceId, pathPrefix, count) in pathVideoCounts) {
        _emitProgress(
          VideoScanProgress(
            phase: VideoScanPhase.savingToDb,
            sourceId: sourceId,
            pathPrefix: pathPrefix,
            totalCount: count,
          ),
        );
      }

      await _saveBasicMetadataToDb(allVideos);

      // 保存字幕索引到数据库
      if (allSubtitles.isNotEmpty) {
        await _saveSubtitlesToDb(allSubtitles);
        logger.i('VideoScannerService: 字幕索引完成，共 ${allSubtitles.length} 条');
      }

      // 只有全新扫描的整个目录树成功后，才删除本次未再次出现的旧记录。
      // 断点续扫保留旧记录，下一次完整扫描再进行精确清理。
      for (final snapshot in completedSnapshots.where((s) => s.canPrune)) {
        final existing = await _dbService.getVideoFilesMap(
          snapshot.sourceId,
          pathPrefix: snapshot.pathPrefix,
        );
        final missing = existing.keys
            .where((filePath) => !snapshot.encounteredPaths.contains(filePath))
            .toList();
        if (missing.isNotEmpty) {
          final deleted = await _dbService.deleteVideosBatch(
            snapshot.sourceId,
            missing,
          );
          logger.i(
            'VideoScannerService: 完整扫描后清理 $deleted 个已删除视频 '
            '(${snapshot.sourceId}:${snapshot.pathPrefix})',
          );
        }
      }

      // 从最终数据库快照重建启动缓存，避免断点续扫只把“剩余目录”写进缓存。
      final enabledPaths = paths
          .where((path) => path.isEnabled)
          .map((path) => (sourceId: path.sourceId, path: path.path))
          .toList();
      final cachedVideos = await _dbService.getAllVideosQuick(
        enabledPaths: enabledPaths,
      );
      await _cacheService.saveCache(
        VideoLibraryCache(
          videos: cachedVideos
              .map(
                (video) => VideoLibraryCacheEntry(
                  sourceId: video.sourceId,
                  filePath: video.filePath,
                  fileName: video.fileName,
                  thumbnailUrl: video.thumbnailUrl,
                  size: video.fileSize ?? 0,
                  modifiedTime: video.fileModifiedTime,
                ),
              )
              .toList(),
          lastUpdated: DateTime.now(),
          sourceIds: sourceIds.toList(),
        ),
      );

      // 完成文件扫描 - 为每个目录发送 completed 阶段进度
      for (final (sourceId, pathPrefix, count) in pathVideoCounts) {
        _emitProgress(
          VideoScanProgress(
            phase: VideoScanPhase.completed,
            sourceId: sourceId,
            pathPrefix: pathPrefix,
            scannedCount: count,
          ),
        );
      }

      // 执行 WAL checkpoint，将写入日志合并到主数据库
      // 这样用户看到的缓存大小会更准确稳定
      await _dbService.checkpoint();

      // 扫描完成后立即广播刮削统计，确保影视页面能及时刷新
      // 这一步非常关键：VideoListNotifier 监听 scrapeStatsStream
      // 当 total 变化时会触发页面刷新
      try {
        final stats = await _dbService.getScrapeStats();
        _scrapeStatsController.add(stats);
        logger.i(
          'VideoScannerService: 扫描完成，广播统计 - total: ${stats.total}, pending: ${stats.pending}',
        );
      } on Exception catch (e, st) {
        AppError.ignore(e, st, '广播扫描完成统计失败，非关键操作');
      }

      // 更新后台服务为完成状态
      await _backgroundTaskService.updateProgress(
        BackgroundTaskProgress(
          taskType: BackgroundTaskType.videoScan,
          state: BackgroundTaskState.completed,
          current: allVideos.length,
          total: allVideos.length,
          message: appL10n.videoScanCompletedCount(allVideos.length),
        ),
      );

      return allVideos.length;
    } catch (e, st) {
      AppError.handle(e, st, 'VideoScannerService.scanFilesOnly');

      // 为所有正在扫描的路径发送错误进度
      for (final path in paths) {
        if (!path.isEnabled) continue;
        _emitProgress(
          VideoScanProgress(
            phase: VideoScanPhase.error,
            sourceId: path.sourceId,
            pathPrefix: path.path,
          ),
        );
      }

      // 更新后台服务为错误状态
      await _backgroundTaskService.updateProgress(
        BackgroundTaskProgress(
          taskType: BackgroundTaskType.videoScan,
          state: BackgroundTaskState.error,
          message: appL10n.videoScanFailedError(e),
        ),
      );
      rethrow;
    } finally {
      _isScanning = false;
      // 扫描完成后停止后台服务（刮削会重新启动）
      await _backgroundTaskService.stopService();
    }
  }

  /// 保存基础元数据到数据库（不刮削）
  ///
  /// 优化：如果扫描阶段已解析 NFO 基础信息，会一并保存
  /// 这样用户在扫描完成后就能看到有标题和海报的内容
  Future<void> _saveBasicMetadataToDb(List<_ScannedVideo> videos) async {
    const batchSize = 50;

    for (var i = 0; i < videos.length; i += batchSize) {
      final batch = videos.skip(i).take(batchSize).toList();
      final metadataList = <VideoMetadata>[];
      final nfoFlags = <({String sourceId, String filePath, bool hasNfo})>[];

      for (final video in batch) {
        // 检查是否已存在
        final existing = await _dbService.get(video.sourceId, video.file.path);
        if (existing != null) {
          // 已存在，但仍需更新 NFO 标志（可能目录内容有变化）
          if (video.hasNfoInDirectory) {
            nfoFlags.add((
              sourceId: video.sourceId,
              filePath: video.file.path,
              hasNfo: true,
            ));
          }
          continue;
        }

        // 创建基础元数据（包含 NFO 基础信息，如果有的话）
        final nfoInfo = video.nfoBasicInfo;
        // 解析文件名获取分辨率和剧集信息
        final fileInfo = VideoFileNameParser.parse(video.file.name);

        // 先分析目录结构（用于辅助分类判断）
        final showDirectory = VideoDatabaseService.extractShowDirectory(
          video.file.path,
        );
        final isInSeasonDir = _isInSeasonDirectory(video.file.path);

        // 蓝光原盘强制识别为电影，其他使用推断分类
        final MediaCategory category;
        if (video.isBdmv) {
          category = MediaCategory.movie;
        } else {
          category = _inferCategory(
            nfoInfo,
            fileName: video.file.name,
            filePath: video.file.path,
            isInSeasonDir: isInSeasonDir,
          );
        }

        // 蓝光原盘使用目录名作为标题（如果 NFO 没有提供）
        final effectiveTitle = nfoInfo?.title ?? video.bdmvTitle;

        // 蓝光原盘的电影目录应该是 BDMV 上一级（电影名目录）
        String? movieDirectory;
        if (category == MediaCategory.movie) {
          if (video.isBdmv) {
            // BDMV: 使用 MovieName 目录（BDMV 的父目录）
            movieDirectory = _extractBdmvMovieDirectory(video.file.path);
          } else {
            movieDirectory = VideoDatabaseService.extractMovieDirectory(
              video.file.path,
            );
          }
        }

        final metadata = VideoMetadata(
          sourceId: video.sourceId,
          filePath: video.file.path,
          fileName: video.file.name,
          thumbnailUrl: video.file.thumbnailUrl,
          fileSize: video.file.size,
          fileModifiedTime: video.file.modifiedTime,
          // NFO 基础信息，蓝光原盘优先使用目录名
          title: effectiveTitle,
          originalTitle: nfoInfo?.originalTitle,
          year: nfoInfo?.year,
          rating: nfoInfo?.rating,
          tmdbId: nfoInfo?.tmdbId,
          genres: nfoInfo?.genres,
          seasonNumber: nfoInfo?.seasonNumber ?? fileInfo.season,
          episodeNumber: nfoInfo?.episodeNumber ?? fileInfo.episode,
          // 分类
          category: category,
          // 本地海报路径（NAS 路径，用于 StreamImage 流式加载）
          localPosterUrl: nfoInfo?.posterPath,
          // TV 剧集的剧目录（用于分组）- 剧集和 unknown 都尝试设置
          showDirectory: category != MediaCategory.movie ? showDirectory : null,
          // 电影所在目录（用于目录系列识别）
          movieDirectory: movieDirectory,
          // 视频分辨率（用于质量分组）
          resolution: fileInfo.resolution,
        );
        metadataList.add(metadata);

        // 记录 NFO 标志（新视频）
        if (video.hasNfoInDirectory) {
          nfoFlags.add((
            sourceId: video.sourceId,
            filePath: video.file.path,
            hasNfo: true,
          ));
        }
      }

      if (metadataList.isNotEmpty) {
        await _dbService.upsertBatch(metadataList);

        // 边扫边显示（Infuse 风格）：每保存一批就推送到 UI
        // 用户不需要等待扫描完成就能看到视频列表
        _partialResultsController.add(metadataList);
        logger.d('VideoScannerService: 推送部分结果 ${metadataList.length} 个视频');
      }

      // 批量更新 NFO 标志
      if (nfoFlags.isNotEmpty) {
        await _dbService.updateNfoFlagBatch(nfoFlags);
      }
    }
  }

  /// 根据 NFO 信息、文件名和目录结构推断媒体分类
  ///
  /// 优先顺序：
  /// 1. NFO 信息中的季集号（最可靠）
  /// 2. 目录结构（位于 Season X 等季目录中 → tvShow）
  /// 3. 文件名模式（如 S01E01、1x01、第X集、EP01）
  /// 4. NFO 有数据但无季集信息 → 电影
  /// 5. 文件名有年份且不是剧集 → 电影
  /// 6. 都没有 → unknown
  MediaCategory _inferCategory(
    NfoBasicInfo? nfoInfo, {
    String? fileName,
    String? filePath,
    bool isInSeasonDir = false,
  }) {
    // 1. 优先使用 NFO 信息中的季集号
    if (nfoInfo != null) {
      if (nfoInfo.seasonNumber != null || nfoInfo.episodeNumber != null) {
        return MediaCategory.tvShow;
      }
    }

    // 2. 目录结构判断：如果在季目录中，强制识别为剧集
    // 这比文件名更可靠，即使文件名不规范也能正确分类
    if (isInSeasonDir) {
      return MediaCategory.tvShow;
    }

    // 3. 尝试从文件名推断
    if (fileName != null && fileName.isNotEmpty) {
      // 使用 VideoFileNameParser 检测剧集模式
      final info = VideoFileNameParser.parse(fileName);
      if (info.isTvShow) {
        return MediaCategory.tvShow;
      }
    }

    // 4. NFO 有数据但无季集信息，认为是电影
    if (nfoInfo != null && nfoInfo.hasData) {
      return MediaCategory.movie;
    }

    // 5. 如果文件名有年份且不是剧集，可能是电影
    if (fileName != null && fileName.isNotEmpty) {
      final info = VideoFileNameParser.parse(fileName);
      if (info.year != null) {
        return MediaCategory.movie;
      }
    }

    return MediaCategory.unknown;
  }

  /// 检查文件是否位于季目录中
  ///
  /// 季目录模式：Season X, S01, 第X季, Specials 等
  bool _isInSeasonDirectory(String filePath) {
    if (filePath.isEmpty) return false;

    // 标准化路径分隔符
    final normalizedPath = filePath.replaceAll(r'\', '/');
    final parts = normalizedPath.split('/').where((p) => p.isNotEmpty).toList();

    if (parts.length < 2) return false;

    // 检查父目录是否是季目录
    final parentDir = parts[parts.length - 2];
    return VideoDatabaseService.isSeasonDirectory(parentDir);
  }

  /// 完整扫描（扫描文件 + 刮削元数据）
  ///
  /// [paths] 要扫描的路径列表
  /// [connections] 源连接映射
  ///
  /// 注意：无深度限制，会递归扫描所有子目录
  Future<List<VideoMetadata>> scan({
    required List<MediaLibraryPath> paths,
    required Map<String, SourceConnection> connections,
  }) async {
    // 先扫描文件
    final count = await scanFilesOnly(paths: paths, connections: connections);

    if (count == 0) return [];

    // 然后刮削元数据
    await scrapeMetadata(connections: connections);

    // 返回所有元数据
    return _dbService.getPage(limit: count);
  }

  /// 后台刮削元数据
  ///
  /// 可以随时调用，会自动处理待刮削的视频
  /// 在移动平台会自动启动前台服务以支持后台运行
  Future<void> scrapeMetadata({
    required Map<String, SourceConnection> connections,
    int batchSize = 20,
  }) async {
    if (_isScraping) {
      logger.w('VideoScannerService: 刮削正在进行中，跳过');
      return;
    }

    _isScraping = true;
    _shouldStopScraping = false;

    // 启动后台服务（移动平台）
    await _backgroundTaskService.init();
    await _backgroundTaskService.startService(
      taskType: BackgroundTaskType.videoScrape,
      initialMessage: appL10n.videoScanBackgroundPreparingScrape,
    );

    try {
      await _metadataService.init();
      await _dbService.init();

      // 重置可能中断的刮削状态
      await _dbService.resetScrapingToPending();

      // 立即广播初始统计，确保 UI 能及时更新刮削状态
      final initialStats = await _dbService.getScrapeStats();
      _scrapeStatsController.add(initialStats);

      // 用于跟踪本批次完成的视频数
      var batchCompletedCount = 0;

      while (!_shouldStopScraping) {
        // 获取待刮削的视频
        final pendingVideos = await _dbService.getPendingScrape(
          limit: batchSize,
        );

        if (pendingVideos.isEmpty) {
          logger.i('VideoScannerService: 所有视频刮削完成');
          break;
        }

        // 每批次开始时获取一次统计（减少数据库查询）
        final batchStats = await _dbService.getScrapeStats();
        _scrapeStatsController.add(batchStats);

        // 发送批次开始进度
        _emitProgress(
          VideoScanProgress(
            phase: VideoScanPhase.scraping,
            scannedCount: batchStats.processed,
            totalCount: batchStats.total,
            currentFile: appL10n.videoScanProgressProcessingVideos(
              pendingVideos.length,
            ),
          ),
        );

        // 更新后台服务进度（批次级别）
        await _backgroundTaskService.updateProgress(
          BackgroundTaskProgress(
            taskType: BackgroundTaskType.videoScrape,
            state: BackgroundTaskState.running,
            current: batchStats.processed,
            total: batchStats.total,
            message: appL10n.videoScrapingCount(pendingVideos.length),
          ),
        );

        // 使用任务池并行刮削（限制并发数，防止过载）
        // 移动端 2 并发，桌面端 4 并发
        final futures = <Future<void>>[];
        for (final video in pendingVideos) {
          if (_shouldStopScraping) break;

          final future = BackgroundTaskPool.scrape.add(() async {
            await _scrapeOneVideo(video, connections);
            batchCompletedCount++;

            // 实时发送进度（UI 端做节流处理）
            _emitProgress(
              VideoScanProgress(
                phase: VideoScanPhase.scraping,
                scannedCount: batchStats.processed + batchCompletedCount,
                totalCount: batchStats.total,
                currentFile: video.fileName,
              ),
            );
          }, taskName: 'scrape:${video.fileName}');
          futures.add(future);
        }

        // 等待本批次所有刮削任务完成
        await Future.wait(futures);

        // 批次完成后更新统计（只查询一次数据库）
        final updatedStats = await _dbService.getScrapeStats();
        _scrapeStatsController.add(updatedStats);
        batchCompletedCount = 0;

        // 批次间短暂延迟，避免 API 限流
        if (!_shouldStopScraping) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }

      // 执行 WAL checkpoint，将写入日志合并到主数据库
      // 这样用户看到的缓存大小会更准确稳定
      await _dbService.checkpoint();

      // 补充缺失的电影系列信息（用于后配置刮削源的情况）
      // 后台执行，不阻塞主流程
      _metadataService.supplementMissingCollections().then((count) {
        if (count > 0) {
          logger.i('VideoScannerService: 补充了 $count 部电影的系列信息');
        }
      }).ignore();

      // 补充缺失的地区/类型信息（用于刮削失败或 NFO 不完整的情况）
      // 后台执行，不阻塞主流程
      _metadataService.supplementMissingCountriesAndGenres().then((count) {
        if (count > 0) {
          logger.i('VideoScannerService: 补充了 $count 个视频的地区/类型信息');
        }
      }).ignore();

      // 刮削完成，广播最终统计
      final finalStats = await _dbService.getScrapeStats();
      _scrapeStatsController.add(finalStats);

      _emitProgress(
        VideoScanProgress(
          phase: VideoScanPhase.completed,
          scannedCount: finalStats.total,
        ),
      );

      // 更新后台服务为完成状态
      await _backgroundTaskService.updateProgress(
        BackgroundTaskProgress(
          taskType: BackgroundTaskType.videoScrape,
          state: BackgroundTaskState.completed,
          message: appL10n.videoScrapeCompleted,
        ),
      );
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'VideoScannerService.scrapeMetadata');
      _emitProgress(const VideoScanProgress(phase: VideoScanPhase.error));

      // 广播统计以更新 UI
      try {
        final errorStats = await _dbService.getScrapeStats();
        _scrapeStatsController.add(errorStats);
      } on Exception {
        // 忽略获取统计时的错误
      }

      // 更新后台服务为错误状态
      await _backgroundTaskService.updateProgress(
        BackgroundTaskProgress(
          taskType: BackgroundTaskType.videoScrape,
          state: BackgroundTaskState.error,
          message: appL10n.videoScrapeFailedError(e),
        ),
      );
    } finally {
      _isScraping = false;
      // 广播最终统计以确保 UI 更新 _isScraping 状态
      try {
        final endStats = await _dbService.getScrapeStats();
        _scrapeStatsController.add(endStats);
      } on Exception {
        // 忽略错误
      }
      // 停止后台服务
      await _backgroundTaskService.stopService();
    }
  }

  /// 刮削单个视频（带重试机制）
  ///
  /// 网络错误时自动重试，最多重试 [maxRetries] 次
  Future<void> _scrapeOneVideo(
    VideoMetadata video,
    Map<String, SourceConnection> connections, {
    int maxRetries = 3,
  }) async {
    var retryCount = 0;
    Exception? lastError;

    while (retryCount <= maxRetries) {
      try {
        // 标记为刮削中
        await _dbService.updateScrapeStatus(
          video.sourceId,
          video.filePath,
          ScrapeStatus.scraping,
        );

        final conn = connections[video.sourceId];
        String? videoUrl;
        NasFileSystem? fileSystem;

        if (conn != null && conn.status == SourceStatus.connected) {
          fileSystem = conn.adapter.fileSystem;
          try {
            videoUrl = await fileSystem.getFileUrl(video.filePath);
          } on Exception catch (e) {
            logger.w(
              'VideoScannerService: 获取视频URL失败 ${video.filePath}，错误原因 $e',
            );
          }
        }

        // 获取元数据（跳过缩略图生成以加速刮削，缩略图会在后台异步生成）
        final metadata = await _metadataService.getOrFetch(
          sourceId: video.sourceId,
          filePath: video.filePath,
          fileName: video.fileName,
          fileSystem: fileSystem,
          videoUrl: videoUrl,
          skipThumbnail: true, // 刮削时跳过缩略图，后续单独处理
        );

        // 根据结果更新刮削状态
        if (metadata.hasMetadata) {
          metadata.scrapeStatus = ScrapeStatus.completed;
        } else {
          metadata.scrapeStatus = ScrapeStatus.failed;
        }

        // 保留文件信息
        metadata
          ..fileSize = video.fileSize
          ..fileModifiedTime = video.fileModifiedTime;

        await _metadataService.save(metadata);

        // 单视频更新推送（Infuse 风格）：只通知这一个视频更新
        // UI 端只需更新对应的卡片，无需刷新整个列表
        _videoUpdatedController.add(metadata);

        // 成功，退出重试循环
        return;
      } on Exception catch (e) {
        lastError = e;
        retryCount++;

        // 判断是否是可重试的网络错误
        if (_isRetryableError(e) && retryCount <= maxRetries) {
          final delay = Duration(seconds: retryCount * 2); // 指数退避
          logger.w(
            'VideoScannerService: 刮削失败 ${video.fileName}，'
            '$delay 后重试 ($retryCount/$maxRetries)',
            e,
          );
          await Future<void>.delayed(delay);
          continue;
        }

        // 不可重试的错误或重试次数用尽
        break;
      }
    }

    // 所有重试都失败
    logger.w('''
      VideoScannerService: 刮削最终失败 ${video.fileName}，
      重试 $retryCount 次后放弃,
      ''', lastError);

    // 标记为失败
    await _dbService.updateScrapeStatus(
      video.sourceId,
      video.filePath,
      ScrapeStatus.failed,
    );
  }

  /// 判断是否是可重试的错误
  bool _isRetryableError(Exception e) {
    final errorStr = e.toString().toLowerCase();
    // 网络相关错误
    if (errorStr.contains('socket') ||
        errorStr.contains('timeout') ||
        errorStr.contains('connection') ||
        errorStr.contains('network') ||
        errorStr.contains('handshake') ||
        errorStr.contains('http') ||
        errorStr.contains('failed host lookup')) {
      return true;
    }
    // TMDB API 限流
    if (errorStr.contains('429') || errorStr.contains('rate limit')) {
      return true;
    }
    return false;
  }

  /// 停止刮削
  void stopScraping() {
    _shouldStopScraping = true;
  }

  /// 获取刮削统计
  ///
  /// [sourceId] 可选，按源ID筛选
  /// [pathPrefix] 可选，按路径前缀筛选（需要同时提供 sourceId）
  Future<ScrapeStats> getScrapeStats({
    String? sourceId,
    String? pathPrefix,
  }) async {
    await _dbService.init();
    return _dbService.getScrapeStats(
      sourceId: sourceId,
      pathPrefix: pathPrefix,
    );
  }

  /// 获取需要重试的视频数量
  ///
  /// 包括刮削失败的和刮削完成但没有 TMDB 数据的
  /// [sourceId] 可选，按源ID筛选
  /// [pathPrefix] 可选，按路径前缀筛选（需要同时提供 sourceId）
  Future<int> getRetryableCount({String? sourceId, String? pathPrefix}) async {
    await _dbService.init();
    return _dbService.getRetryableCount(
      sourceId: sourceId,
      pathPrefix: pathPrefix,
    );
  }

  /// 重试刮削失败和无 TMDB 数据的视频
  ///
  /// 只会刮削失败的和完成但无 TMDB ID 的视频，
  /// 不会重新刮削已成功获取 TMDB 数据的视频
  Future<void> retryScrapeFailedVideos({
    required Map<String, SourceConnection> connections,
  }) async {
    if (_isScraping) {
      logger.w('VideoScannerService: 刮削正在进行中，跳过重试');
      return;
    }

    try {
      await _dbService.init();

      // 获取需要重试的数量
      final retryableCount = await _dbService.getRetryableCount();
      if (retryableCount == 0) {
        logger.i('VideoScannerService: 没有需要重试的视频');
        return;
      }

      logger.i('VideoScannerService: 开始重试刮削 $retryableCount 个视频');

      // 重置需要重试的视频状态为 pending
      await _dbService.resetRetryableVideos();

      // 开始刮削
      await scrapeMetadata(connections: connections);
    } on Exception catch (e, st) {
      logger.e('VideoScannerService: 重试刮削失败', e, st);
    }
  }

  /// 快速增量同步媒体库
  ///
  /// 采用高效的分层检测策略，只扫描发生变化的目录分支。
  /// 适合在 app 启动时调用，资源消耗极小。
  ///
  /// 工作流程：
  /// 1. 快速检测根目录修改时间，无变化则直接跳过
  /// 2. 分层向下检测，只遍历有变化的目录分支
  /// 3. 对变化目录进行文件级别对比
  /// 4. 支持中断和超时保护
  ///
  /// 返回 [IncrementalSyncResult] 包含同步统计信息
  Future<IncrementalSyncResult?> incrementalSync({
    required List<MediaLibraryPath> paths,
    required Map<String, SourceConnection> connections,
    void Function(String message)? onProgress,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    if (_isScanning) {
      logger.w('VideoScannerService: 扫描正在进行中，跳过增量同步');
      return null;
    }

    _isScanning = true;
    _shouldStopScraping = false;
    final startTime = DateTime.now();

    try {
      await _dbService.init();

      var addedFiles = 0;
      var deletedFiles = 0;
      var changedFiles = 0;
      var unchangedDirectories = 0;
      var changedDirectories = 0;
      var newDirectories = 0;
      var deletedDirectories = 0;

      for (final path in paths) {
        // 中断检查
        if (_shouldStopScraping) {
          logger.i('VideoScannerService: 增量同步被中断');
          break;
        }

        // 超时检查
        if (DateTime.now().difference(startTime) > timeout) {
          logger.w('VideoScannerService: 增量同步超时，已运行 ${timeout.inMinutes} 分钟');
          break;
        }

        if (!path.isEnabled) continue;

        final conn = connections[path.sourceId];
        if (conn == null || conn.status != SourceStatus.connected) {
          logger.w('VideoScannerService: 源 ${path.sourceId} 未连接，跳过增量同步');
          continue;
        }

        final fileSystem = conn.adapter.fileSystem;

        // 步骤1：快速检测根目录是否有变化
        onProgress?.call('检查 ${path.path}...');

        final rootDirRecord = await _dbService.getScanProgressItem(
          path.sourceId,
          path.path,
        );

        // 如果没有历史记录，跳过增量同步（需要全量扫描）
        if (rootDirRecord == null) {
          logger.i('VideoScannerService: ${path.path} 无历史记录，跳过增量同步');
          continue;
        }

        // 获取根目录当前修改时间
        DateTime? currentRootMtime;
        try {
          final rootInfo = await fileSystem.getFileInfo(path.path);
          currentRootMtime = rootInfo.modifiedTime;
        } on Exception catch (e) {
          logger.w('VideoScannerService: 获取根目录信息失败 ${path.path}', e);
          continue;
        }

        // 快速判断：如果根目录修改时间没变，整个目录树都没变化
        if (rootDirRecord.dirModifiedTime != null &&
            currentRootMtime != null &&
            !currentRootMtime.isAfter(rootDirRecord.dirModifiedTime!)) {
          logger.i('VideoScannerService: ${path.path} 根目录未变化，跳过');
          unchangedDirectories++;
          continue;
        }

        // 步骤2：分层检测变化的目录
        onProgress?.call('检测变化...');

        final syncResult = await _incrementalSyncDirectory(
          fileSystem: fileSystem,
          sourceId: path.sourceId,
          rootPath: path.path,
          onProgress: onProgress,
          startTime: startTime,
          timeout: timeout,
        );

        if (syncResult == null) continue;

        addedFiles += syncResult.addedFiles;
        deletedFiles += syncResult.deletedFiles;
        changedFiles += syncResult.changedFiles;
        unchangedDirectories += syncResult.unchangedDirectories;
        changedDirectories += syncResult.changedDirectories;
        newDirectories += syncResult.newDirectories;
        deletedDirectories += syncResult.deletedDirectories;
      }

      final result = IncrementalSyncResult(
        addedFiles: addedFiles,
        deletedFiles: deletedFiles,
        changedFiles: changedFiles,
        unchangedDirectories: unchangedDirectories,
        changedDirectories: changedDirectories,
        newDirectories: newDirectories,
        deletedDirectories: deletedDirectories,
      );

      if (result.hasChanges) {
        logger.i('''
VideoScannerService: 增量同步完成
  - 新增文件: $addedFiles
  - 删除文件: $deletedFiles
  - 变化文件: $changedFiles
  - 新增目录: $newDirectories
  - 删除目录: $deletedDirectories
''');

        // 如果有新增文件，触发刮削
        if (addedFiles > 0 || changedFiles > 0) {
          AppError.fireAndForget(
            scrapeMetadata(connections: connections),
            action: 'incrementalSync.scrapeMetadata',
          );
        }
      } else {
        logger.i('VideoScannerService: 增量同步完成，无变化');
      }

      return result;
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'VideoScannerService.incrementalSync');
      return null;
    } finally {
      _isScanning = false;
    }
  }

  /// 分层增量同步单个目录树
  ///
  /// 从根目录开始，只遍历修改时间变化的目录分支
  Future<IncrementalSyncResult?> _incrementalSyncDirectory({
    required NasFileSystem fileSystem,
    required String sourceId,
    required String rootPath,
    void Function(String message)? onProgress,
    required DateTime startTime,
    required Duration timeout,
  }) async {
    var addedFiles = 0;
    var deletedFiles = 0;
    var changedFiles = 0;
    var unchangedDirectories = 0;
    var changedDirectories = 0;
    var newDirectories = 0;
    // 增量扫描沿着变更分支下行，不做全量比对，因此不统计目录删除。
    const deletedDirectories = 0;

    // 使用队列进行广度优先遍历（只遍历有变化的分支）
    final dirsToCheck = <String>[rootPath];
    final dirsToScan = <String>{}; // 需要扫描文件的目录
    var checkedCount = 0;
    const maxDirsToCheck = 1000; // 单次最多检查目录数，避免过载

    while (dirsToCheck.isNotEmpty && checkedCount < maxDirsToCheck) {
      // 中断检查
      if (_shouldStopScraping) break;

      // 超时检查
      if (DateTime.now().difference(startTime) > timeout) break;

      final currentDir = dirsToCheck.removeAt(0);
      checkedCount++;

      // 获取数据库中该目录的记录
      final dbRecord = await _dbService.getScanProgressItem(
        sourceId,
        currentDir,
      );

      // 获取当前目录修改时间
      DateTime? currentMtime;
      try {
        final dirInfo = await fileSystem.getFileInfo(currentDir);
        currentMtime = dirInfo.modifiedTime;
      } on Exception catch (e) {
        // getFileInfo 失败无法证明目录已删除；超时、权限和会话过期都会走到这里。
        // 保留数据库快照，等待下一次同步或一次成功的父目录列表来确认删除。
        logger.w('VideoScannerService: 获取目录信息失败，保留旧数据 $currentDir', e);
        continue;
      }

      // 检查目录是否有变化
      final hasChanged =
          dbRecord == null || // 新目录
          dbRecord.dirModifiedTime == null || // 没有记录修改时间
          (currentMtime != null &&
              currentMtime.isAfter(dbRecord.dirModifiedTime!));

      if (!hasChanged) {
        unchangedDirectories++;
        continue;
      }

      if (dbRecord == null) {
        newDirectories++;
      } else {
        changedDirectories++;
      }

      // 标记需要扫描文件
      dirsToScan.add(currentDir);

      // 获取子目录并加入检查队列
      try {
        final items = await fileSystem.listDirectory(currentDir);
        final subDirs = items
            .where(
              (f) =>
                  f.isDirectory && !f.isHidden && !_shouldSkipDirectory(f.name),
            )
            .map((f) => f.path)
            .toList();
        dirsToCheck.addAll(subDirs);
      } on Exception catch (e) {
        logger.w('VideoScannerService: 列出目录失败 $currentDir', e);
      }
    }

    // 步骤3：扫描需要更新的目录
    if (dirsToScan.isEmpty) {
      return IncrementalSyncResult(
        addedFiles: 0,
        deletedFiles: deletedFiles,
        changedFiles: 0,
        unchangedDirectories: unchangedDirectories,
        changedDirectories: changedDirectories,
        newDirectories: newDirectories,
        deletedDirectories: deletedDirectories,
      );
    }

    onProgress?.call('扫描 ${dirsToScan.length} 个变化目录...');

    // 分批扫描，避免一次性处理过多
    const batchSize = 20;
    final dirsList = dirsToScan.toList();

    for (var i = 0; i < dirsList.length; i += batchSize) {
      if (_shouldStopScraping) break;
      if (DateTime.now().difference(startTime) > timeout) break;

      final batch = dirsList.skip(i).take(batchSize).toList();

      for (final dir in batch) {
        final result = await _scanDirectoryForChanges(
          fileSystem: fileSystem,
          sourceId: sourceId,
          dirPath: dir,
          rootPath: rootPath,
        );

        addedFiles += result.addedFiles;
        deletedFiles += result.deletedFiles;
        changedFiles += result.changedFiles;
      }
    }

    return IncrementalSyncResult(
      addedFiles: addedFiles,
      deletedFiles: deletedFiles,
      changedFiles: changedFiles,
      unchangedDirectories: unchangedDirectories,
      changedDirectories: changedDirectories,
      newDirectories: newDirectories,
      deletedDirectories: deletedDirectories,
    );
  }

  /// 扫描单个目录的文件变化
  Future<({int addedFiles, int deletedFiles, int changedFiles})>
  _scanDirectoryForChanges({
    required NasFileSystem fileSystem,
    required String sourceId,
    required String dirPath,
    required String rootPath,
  }) async {
    var addedFiles = 0;
    var deletedFiles = 0;
    var changedFiles = 0;

    try {
      // 获取数据库中该目录的文件
      final dbFiles = await _dbService.getVideoFilesInDirectory(
        sourceId,
        dirPath,
      );

      // 扫描当前目录
      final items = await fileSystem.listDirectory(dirPath);
      final videoItems = items
          .where((f) => !f.isDirectory && f.type == FileType.video)
          .toList();

      // 获取目录修改时间用于保存
      DateTime? dirMtime;
      try {
        final dirInfo = await fileSystem.getFileInfo(dirPath);
        dirMtime = dirInfo.modifiedTime;
      } on Exception {
        // 忽略
      }

      final currentFilePaths = <String>{};

      for (final videoItem in videoItems) {
        currentFilePaths.add(videoItem.path);
        final dbFile = dbFiles[videoItem.path];

        if (dbFile == null) {
          // 新文件
          final video = _ScannedVideo(
            sourceId: sourceId,
            file: videoItem,
            hasNfoInDirectory: items.any(
              (f) => !f.isDirectory && f.name.toLowerCase().endsWith('.nfo'),
            ),
          );
          await _saveBasicMetadataToDb([video]);
          addedFiles++;
        } else {
          // 检查文件是否变化
          final sizeChanged = dbFile.fileSize != videoItem.size;
          final timeChanged =
              dbFile.fileModifiedTime != null &&
              videoItem.modifiedTime != null &&
              videoItem.modifiedTime!.isAfter(dbFile.fileModifiedTime!);

          if (sizeChanged || timeChanged) {
            // 文件已变化，更新记录
            final video = _ScannedVideo(
              sourceId: sourceId,
              file: videoItem,
              hasNfoInDirectory: items.any(
                (f) => !f.isDirectory && f.name.toLowerCase().endsWith('.nfo'),
              ),
            );
            await _saveBasicMetadataToDb([video]);
            changedFiles++;
          }
        }
      }

      // 检测删除的文件
      for (final dbFilePath in dbFiles.keys) {
        if (!currentFilePaths.contains(dbFilePath)) {
          await _dbService.deleteVideosBatch(sourceId, [dbFilePath]);
          deletedFiles++;
        }
      }

      // 更新目录扫描记录
      await _dbService.upsertScanProgressItem(
        sourceId: sourceId,
        path: dirPath,
        rootPath: rootPath,
        videoCount: videoItems.length,
        dirModifiedTime: dirMtime,
      );
    } on Exception catch (e) {
      logger.w('VideoScannerService: 扫描目录变化失败 $dirPath', e);
    }

    return (
      addedFiles: addedFiles,
      deletedFiles: deletedFiles,
      changedFiles: changedFiles,
    );
  }

  /// 检查是否是字幕文件
  bool _isSubtitleFile(String fileName) {
    final ext = _getExtension(fileName);
    return subtitleExtensions.contains(ext);
  }

  /// 获取文件扩展名（小写，包含点号）
  String _getExtension(String fileName) {
    final lastDot = fileName.lastIndexOf('.');
    if (lastDot == -1) return '';
    return fileName.substring(lastDot).toLowerCase();
  }

  /// 从字幕文件名解析语言
  String? _parseSubtitleLanguage(String subtitleName, String videoBaseName) {
    // 常见的语言标记
    const languagePatterns = {
      'chs': '简体中文',
      'cht': '繁体中文',
      'sc': '简体中文',
      'tc': '繁体中文',
      'zh': '中文',
      'zh-cn': '简体中文',
      'zh-tw': '繁体中文',
      'chinese': '中文',
      '简体': '简体中文',
      '繁体': '繁体中文',
      '简中': '简体中文',
      '繁中': '繁体中文',
      'en': 'English',
      'eng': 'English',
      'english': 'English',
      'ja': '日本語',
      'jp': '日本語',
      'jpn': '日本語',
      'ko': '한국어',
      'kor': '한국어',
    };

    final subtitleBaseName = _getBaseName(subtitleName).toLowerCase();
    var remaining = subtitleBaseName;

    if (subtitleBaseName.startsWith(videoBaseName)) {
      remaining = subtitleBaseName.substring(videoBaseName.length);
    }

    remaining = remaining.replaceAll(RegExp(r'^[._\-\s]+'), '');

    for (final entry in languagePatterns.entries) {
      if (remaining.contains(entry.key)) {
        return entry.value;
      }
    }

    return remaining.isNotEmpty ? remaining : null;
  }

  /// 获取文件基础名（不含扩展名）
  String _getBaseName(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex > 0) {
      return fileName.substring(0, dotIndex);
    }
    return fileName;
  }

  /// 判断是否应该跳过该目录
  bool _shouldSkipDirectory(String name) =>
      name.startsWith('.') ||
      name.startsWith('@') ||
      name.startsWith('#recycle') ||
      name == 'eaDir' ||
      name == '@eaDir';

  // ============ 增量扫描方法 ============

  /// 增量扫描目录（支持断点续扫和并行处理）
  ///
  /// 两阶段扫描策略：
  /// 1. 阶段1：快速发现所有目录，保存到数据库
  /// 2. 阶段2：逐目录扫描视频文件，已完成的目录会跳过
  ///
  /// 优势：
  /// - 中断后可从上次位置继续
  /// - SMB 连接池并行列目录，速度提升数倍
  /// - 进度可视化（已扫描 X/Y 个目录）
  Future<void> _scanDirectoriesIncremental({
    required NasFileSystem fileSystem,
    required String sourceId,
    required String rootPath,
    required List<_ScannedVideo> videos,
    required List<_ScannedSubtitle> subtitles,
    required bool resumeExisting,
  }) async {
    if (resumeExisting) {
      logger.i('VideoScannerService: 发现未完成的扫描，继续上次进度');
      // 重置中断的扫描状态
      await _dbService.resetInterruptedScans(sourceId, rootPath);
    } else {
      // 新扫描：先清除旧进度，然后发现所有目录
      await _dbService.clearScanProgress(sourceId, rootPath);

      // 阶段1：发现所有目录
      _emitProgress(
        VideoScanProgress(
          phase: VideoScanPhase.scanning,
          sourceId: sourceId,
          pathPrefix: rootPath,
          currentPath: appL10n.videoScanProgressDiscoveringDirectories,
        ),
      );

      final directories = await _discoverDirectories(
        fileSystem: fileSystem,
        sourceId: sourceId,
        rootPath: rootPath,
      );

      logger.i('VideoScannerService: 发现 ${directories.length} 个目录');

      // 保存到数据库
      await _dbService.addPendingDirectories(sourceId, rootPath, directories);
    }

    // 阶段2：逐目录扫描文件
    await _scanPendingDirectories(
      fileSystem: fileSystem,
      sourceId: sourceId,
      rootPath: rootPath,
      videos: videos,
      subtitles: subtitles,
    );
  }

  /// 发现所有子目录（利用 SMB 并行能力）
  Future<List<String>> _discoverDirectories({
    required NasFileSystem fileSystem,
    required String sourceId,
    required String rootPath,
  }) async {
    // 如果是 SMB 文件系统，使用并行发现
    if (fileSystem is SmbFileSystem) {
      return fileSystem.discoverAllDirectories(
        rootPath,
        onProgress: (count) {
          _emitProgress(
            VideoScanProgress(
              phase: VideoScanPhase.scanning,
              sourceId: sourceId,
              pathPrefix: rootPath,
              currentPath: appL10n.videoScanProgressDiscoveringCount(count),
            ),
          );
        },
      );
    }

    // 其他文件系统使用递归发现
    final directories = <String>[rootPath];
    final pending = <String>[rootPath];

    while (pending.isNotEmpty) {
      final current = pending.removeAt(0);

      try {
        final items = await fileSystem.listDirectory(current);
        final subDirs = items
            .where(
              (f) =>
                  f.isDirectory && !f.isHidden && !_shouldSkipDirectory(f.name),
            )
            .map((f) => f.path)
            .toList();

        directories.addAll(subDirs);
        pending.addAll(subDirs);

        if (directories.length % 50 == 0) {
          _emitProgress(
            VideoScanProgress(
              phase: VideoScanPhase.scanning,
              sourceId: sourceId,
              pathPrefix: rootPath,
              currentPath: appL10n.videoScanProgressDiscoveringCount(
                directories.length,
              ),
            ),
          );
        }
      } on Exception catch (e, st) {
        logger.w('VideoScannerService: 发现目录失败 $current', e);
        Error.throwWithStackTrace(e, st);
      }
    }

    return directories;
  }

  /// 扫描待处理的目录
  Future<void> _scanPendingDirectories({
    required NasFileSystem fileSystem,
    required String sourceId,
    required String rootPath,
    required List<_ScannedVideo> videos,
    required List<_ScannedSubtitle> subtitles,
  }) async {
    // 获取总进度
    final stats = await _dbService.getScanProgressStats(sourceId, rootPath);

    while (true) {
      // 获取一批待扫描目录
      final pending = await _dbService.getPendingDirectories(
        sourceId,
        rootPath,
        limit: 20,
      );

      if (pending.isEmpty) {
        logger.i('VideoScannerService: 所有目录扫描完成');
        break;
      }

      // SMB 支持并行列目录
      if (fileSystem is SmbFileSystem && pending.length > 1) {
        await _scanDirectoriesBatchParallel(
          fileSystem: fileSystem,
          sourceId: sourceId,
          rootPath: rootPath,
          directories: pending,
          videos: videos,
          subtitles: subtitles,
          totalDirectories: stats.totalDirectories,
        );
      } else {
        // 串行扫描
        for (final dir in pending) {
          await _scanSingleDirectory(
            fileSystem: fileSystem,
            sourceId: sourceId,
            rootPath: rootPath,
            dirPath: dir.path,
            videos: videos,
            subtitles: subtitles,
            totalDirectories: stats.totalDirectories,
          );
        }
      }
    }
  }

  /// 并行扫描一批目录（SMB 优化）
  Future<void> _scanDirectoriesBatchParallel({
    required SmbFileSystem fileSystem,
    required String sourceId,
    required String rootPath,
    required List<ScanProgressItem> directories,
    required List<_ScannedVideo> videos,
    required List<_ScannedSubtitle> subtitles,
    required int totalDirectories,
  }) async {
    // 标记开始扫描
    for (final dir in directories) {
      await _dbService.markDirectoryScanning(sourceId, dir.path);
    }

    // 并行列出所有目录内容
    final paths = directories.map((d) => d.path).toList();
    final results = await fileSystem.listDirectoriesParallel(paths);

    // 获取目录修改时间（用于增量同步）
    final dirMtimes = await fileSystem.getDirectoriesModifiedTime(paths);

    // 处理每个目录的结果
    final completedDirs =
        <
          ({
            String sourceId,
            String path,
            int videoCount,
            DateTime? dirModifiedTime,
          })
        >[];
    final batchVideos = <_ScannedVideo>[];
    final batchSubtitles = <_ScannedSubtitle>[];
    final failedDirectories = <String>[];

    for (final dir in directories) {
      final items = results[dir.path];
      if (items == null) {
        failedDirectories.add(dir.path);
        continue;
      }

      // 收集该目录的视频和字幕
      final dirVideos = <_ScannedVideo>[];
      final dirSubtitles = <_ScannedSubtitle>[];

      // 处理目录内容
      final videoCount = await _processDirectoryItems(
        sourceId: sourceId,
        dirPath: dir.path,
        items: items,
        videos: dirVideos,
        subtitles: dirSubtitles,
      );

      batchVideos.addAll(dirVideos);
      batchSubtitles.addAll(dirSubtitles);

      completedDirs.add((
        sourceId: sourceId,
        path: dir.path,
        videoCount: videoCount,
        dirModifiedTime: dirMtimes[dir.path],
      ));
    }

    // 先保存视频和字幕到数据库（确保目录状态和数据一致）
    if (batchVideos.isNotEmpty) {
      await _saveBasicMetadataToDb(batchVideos);
    }
    if (batchSubtitles.isNotEmpty) {
      await _saveSubtitlesToDb(batchSubtitles);
    }

    // 将视频和字幕添加到总列表（用于缓存和进度统计）
    videos.addAll(batchVideos);
    subtitles.addAll(batchSubtitles);

    // 批量标记完成（在数据保存之后）
    await _dbService.markDirectoriesCompletedBatch(completedDirs);

    if (failedDirectories.isNotEmpty) {
      throw StateError(
        'Failed to list ${failedDirectories.length} directories: '
        '${failedDirectories.take(3).join(', ')}',
      );
    }

    // 更新进度
    final currentStats = await _dbService.getScanProgressStats(
      sourceId,
      rootPath,
    );
    _emitProgress(
      VideoScanProgress(
        phase: VideoScanPhase.scanning,
        sourceId: sourceId,
        pathPrefix: rootPath,
        currentPath: appL10n.videoScanProgressDirectoriesScanned(
          currentStats.completedDirectories,
          totalDirectories,
        ),
        scannedCount: videos.length,
      ),
    );
  }

  /// 扫描单个目录
  Future<void> _scanSingleDirectory({
    required NasFileSystem fileSystem,
    required String sourceId,
    required String rootPath,
    required String dirPath,
    required List<_ScannedVideo> videos,
    required List<_ScannedSubtitle> subtitles,
    required int totalDirectories,
  }) async {
    // 标记开始扫描
    await _dbService.markDirectoryScanning(sourceId, dirPath);

    try {
      final items = await fileSystem.listDirectory(dirPath);

      // 获取目录修改时间（用于增量同步）
      DateTime? dirMtime;
      try {
        final dirInfo = await fileSystem.getFileInfo(dirPath);
        dirMtime = dirInfo.modifiedTime;
      } catch (_) {
        // 忽略获取目录信息失败（包括 Error 子类如 StateError），不影响扫描流程
      }

      // 收集该目录的视频和字幕
      final dirVideos = <_ScannedVideo>[];
      final dirSubtitles = <_ScannedSubtitle>[];

      final videoCount = await _processDirectoryItems(
        sourceId: sourceId,
        dirPath: dirPath,
        items: items,
        videos: dirVideos,
        subtitles: dirSubtitles,
      );

      // 立即保存该目录的视频到数据库（确保目录状态和数据一致）
      // 这样即使扫描中断，已完成目录的数据也不会丢失
      if (dirVideos.isNotEmpty) {
        await _saveBasicMetadataToDb(dirVideos);
      }
      if (dirSubtitles.isNotEmpty) {
        await _saveSubtitlesToDb(dirSubtitles);
      }

      // 将视频和字幕添加到总列表（用于缓存和进度统计）
      videos.addAll(dirVideos);
      subtitles.addAll(dirSubtitles);

      // 标记完成（包含目录修改时间）
      await _dbService.markDirectoryCompleted(
        sourceId,
        dirPath,
        videoCount: videoCount,
        dirModifiedTime: dirMtime,
      );

      // 更新进度
      final currentStats = await _dbService.getScanProgressStats(
        sourceId,
        rootPath,
      );
      _emitProgress(
        VideoScanProgress(
          phase: VideoScanPhase.scanning,
          sourceId: sourceId,
          pathPrefix: rootPath,
          currentPath: appL10n.videoScanProgressDirectoriesProgress(
            currentStats.completedDirectories,
            totalDirectories,
          ),
          scannedCount: videos.length,
        ),
      );
    } on Exception catch (e, st) {
      logger.w('VideoScannerService: 扫描目录失败 $dirPath', e);
      // 保持 scanning 状态；下次断点续扫会重置为 pending。
      Error.throwWithStackTrace(e, st);
    }
  }

  /// 处理目录内容，提取视频和字幕
  ///
  /// 返回发现的视频数量
  Future<int> _processDirectoryItems({
    required String sourceId,
    required String dirPath,
    required List<FileItem> items,
    required List<_ScannedVideo> videos,
    required List<_ScannedSubtitle> subtitles,
  }) async {
    // 检测当前目录是否包含 NFO 文件
    final hasNfo = items.any(
      (item) =>
          !item.isDirectory &&
          (item.name.toLowerCase().endsWith('.nfo') ||
              item.name.toLowerCase() == 'movie.nfo' ||
              item.name.toLowerCase() == 'tvshow.nfo'),
    );

    // 收集视频和字幕
    final videoItems = items
        .where((f) => !f.isDirectory && f.type == FileType.video)
        .toList();
    final subtitleItems = items
        .where((f) => !f.isDirectory && _isSubtitleFile(f.name))
        .toList();

    // 检测是否是蓝光原盘 STREAM 目录
    final isBdmvStream = _isBdmvStreamDirectory(dirPath);

    if (isBdmvStream) {
      // 蓝光原盘目录：只选择最大的 m2ts 文件作为主视频
      final m2tsFiles = videoItems
          .where((f) => f.name.toLowerCase().endsWith('.m2ts'))
          .toList();

      final mainFile = _selectMainBdmvFile(m2tsFiles);
      if (mainFile != null) {
        final bdmvTitle = _extractBdmvMovieTitle(dirPath);

        videos.add(
          _ScannedVideo(
            sourceId: sourceId,
            file: mainFile,
            hasNfoInDirectory: hasNfo,
            nfoBasicInfo: null,
            isBdmv: true,
            bdmvTitle: bdmvTitle,
          ),
        );

        logger.i(
          'VideoScannerService: BDMV 检测 - 选择主文件 ${mainFile.name} (${mainFile.displaySize})，跳过 ${m2tsFiles.length - 1} 个其他文件，电影名: $bdmvTitle',
        );

        // 关联字幕（使用电影名或主文件名匹配）
        final videoBaseName = _getBaseName(mainFile.name).toLowerCase();
        final titleBaseName = bdmvTitle?.toLowerCase() ?? '';
        for (final subtitleItem in subtitleItems) {
          final subtitleBaseName = _getBaseName(
            subtitleItem.name,
          ).toLowerCase();
          if (subtitleBaseName == videoBaseName ||
              subtitleBaseName.startsWith(videoBaseName) ||
              (titleBaseName.isNotEmpty &&
                  subtitleBaseName.contains(titleBaseName))) {
            subtitles.add(
              _ScannedSubtitle(
                sourceId: sourceId,
                videoPath: mainFile.path,
                subtitleFile: subtitleItem,
                language: _parseSubtitleLanguage(
                  subtitleItem.name,
                  videoBaseName,
                ),
              ),
            );
          }
        }

        return 1; // 只返回 1 个视频（主文件）
      }

      // 没有找到 m2ts 文件，可能是其他格式，继续正常处理
    }

    // 普通目录：处理所有视频文件
    for (final videoItem in videoItems) {
      videos.add(
        _ScannedVideo(
          sourceId: sourceId,
          file: videoItem,
          hasNfoInDirectory: hasNfo,
          // 不在扫描阶段解析 NFO，加快扫描速度
          nfoBasicInfo: null,
        ),
      );

      // 关联字幕
      final videoBaseName = _getBaseName(videoItem.name).toLowerCase();
      for (final subtitleItem in subtitleItems) {
        final subtitleBaseName = _getBaseName(subtitleItem.name).toLowerCase();
        if (subtitleBaseName == videoBaseName ||
            subtitleBaseName.startsWith(videoBaseName)) {
          subtitles.add(
            _ScannedSubtitle(
              sourceId: sourceId,
              videoPath: videoItem.path,
              subtitleFile: subtitleItem,
              language: _parseSubtitleLanguage(
                subtitleItem.name,
                videoBaseName,
              ),
            ),
          );
        }
      }
    }

    return videoItems.length;
  }

  void _emitProgress(VideoScanProgress progress) {
    _progressController.add(progress);
  }

  /// 检测是否是蓝光原盘 STREAM 目录
  ///
  /// 标准蓝光目录结构：MovieName/BDMV/STREAM/*.m2ts
  /// STREAM 目录是 BDMV 的子目录，包含实际的视频流文件
  bool _isBdmvStreamDirectory(String dirPath) {
    if (dirPath.isEmpty) return false;

    final normalizedPath = dirPath.replaceAll(r'\', '/');
    final parts = normalizedPath.split('/').where((p) => p.isNotEmpty).toList();

    if (parts.length < 2) return false;

    // 检查当前目录是否是 STREAM，父目录是否是 BDMV
    final currentDir = parts.last.toUpperCase();
    final parentDir = parts[parts.length - 2].toUpperCase();

    return currentDir == 'STREAM' && parentDir == 'BDMV';
  }

  /// 从蓝光目录结构中提取电影名称
  ///
  /// 路径格式：.../MovieName/BDMV/STREAM/
  /// 返回 MovieName 作为电影标题
  String? _extractBdmvMovieTitle(String dirPath) {
    if (dirPath.isEmpty) return null;

    final normalizedPath = dirPath.replaceAll(r'\', '/');
    final parts = normalizedPath.split('/').where((p) => p.isNotEmpty).toList();

    // 需要至少 3 级目录：MovieName/BDMV/STREAM
    if (parts.length < 3) return null;

    // 获取 BDMV 上一级目录作为电影名
    // parts: [..., MovieName, BDMV, STREAM]
    return parts[parts.length - 3];
  }

  /// 从 m2ts 文件列表中选择主视频文件
  ///
  /// 选择标准：文件大小最大的 m2ts 文件通常是主电影
  /// 其他较小的文件通常是花絮、菜单动画等
  FileItem? _selectMainBdmvFile(List<FileItem> m2tsFiles) {
    if (m2tsFiles.isEmpty) return null;
    if (m2tsFiles.length == 1) return m2tsFiles.first;

    // 按文件大小降序排序，选择最大的
    final sorted = List<FileItem>.from(m2tsFiles)
      ..sort((a, b) => b.size.compareTo(a.size));

    return sorted.first;
  }

  /// 从蓝光文件路径提取电影目录路径
  ///
  /// 路径格式：.../MovieName/BDMV/STREAM/00001.m2ts
  /// 返回 .../MovieName 作为电影目录
  String? _extractBdmvMovieDirectory(String filePath) {
    if (filePath.isEmpty) return null;

    final normalizedPath = filePath.replaceAll(r'\', '/');
    final parts = normalizedPath.split('/').where((p) => p.isNotEmpty).toList();

    // 需要至少 4 级：MovieName/BDMV/STREAM/file.m2ts
    if (parts.length < 4) return null;

    // 找到 BDMV 目录的位置
    for (var i = parts.length - 3; i >= 0; i--) {
      if (parts[i].toUpperCase() == 'BDMV' &&
          i + 1 < parts.length &&
          parts[i + 1].toUpperCase() == 'STREAM') {
        // 返回 BDMV 前面的路径（包含 MovieName）
        if (i > 0) {
          return '/${parts.sublist(0, i).join('/')}';
        }
        return null;
      }
    }

    return null;
  }

  /// 保存字幕索引到数据库
  Future<void> _saveSubtitlesToDb(List<_ScannedSubtitle> subtitles) async {
    final subtitleIndexes = subtitles
        .map(
          (s) => SubtitleIndex(
            sourceId: s.sourceId,
            videoPath: s.videoPath,
            subtitlePath: s.subtitleFile.path,
            fileName: s.subtitleFile.name,
            format: _getExtension(s.subtitleFile.name).substring(1), // 去掉点号
            language: s.language,
          ),
        )
        .toList();

    await _dbService.upsertSubtitlesBatch(subtitleIndexes);
  }

  /// 释放资源
  void dispose() {
    _progressController.close();
    _scrapeStatsController.close();
    _partialResultsController.close();
    _videoUpdatedController.close();
  }
}

/// 扫描到的视频
class _ScannedVideo {
  const _ScannedVideo({
    required this.sourceId,
    required this.file,
    this.hasNfoInDirectory = false,
    this.nfoBasicInfo,
    this.isBdmv = false,
    this.bdmvTitle,
  });

  final String sourceId;
  final FileItem file;
  final bool hasNfoInDirectory; // 同目录下是否有 NFO 文件
  final NfoBasicInfo? nfoBasicInfo; // NFO 基础信息（扫描阶段快速解析）
  final bool isBdmv; // 是否是蓝光原盘主文件
  final String? bdmvTitle; // 蓝光原盘电影标题（从目录名提取）
}

/// NFO 基础信息（轻量级，用于扫描阶段）
class NfoBasicInfo {
  const NfoBasicInfo({
    this.title,
    this.originalTitle,
    this.year,
    this.rating,
    this.tmdbId,
    this.genres,
    this.seasonNumber,
    this.episodeNumber,
    this.posterPath,
  });

  final String? title;
  final String? originalTitle;
  final int? year;
  final double? rating;
  final int? tmdbId;
  final String? genres;
  final int? seasonNumber;
  final int? episodeNumber;
  final String? posterPath;

  bool get hasData => title != null || tmdbId != null;
}

/// 扫描到的字幕
class _ScannedSubtitle {
  const _ScannedSubtitle({
    required this.sourceId,
    required this.videoPath,
    required this.subtitleFile,
    this.language,
  });

  final String sourceId;
  final String videoPath;
  final FileItem subtitleFile;
  final String? language;
}
