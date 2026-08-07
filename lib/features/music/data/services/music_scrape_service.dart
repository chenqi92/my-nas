import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/network/dio_client.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/core/utils/nas_path.dart';
import 'package:my_nas/features/music/data/services/music_cover_cache_service.dart';
import 'package:my_nas/features/music/data/services/music_database_service.dart';
import 'package:my_nas/features/music/data/services/music_scraper_manager_service.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_result.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

/// 音乐刮削进度事件
class MusicScrapeProgress {
  const MusicScrapeProgress({
    required this.sourceId,
    required this.pathPrefix,
    required this.phase,
    this.currentTrack,
    this.processedCount = 0,
    this.totalCount = 0,
    this.successCount = 0,
    this.skipCount = 0,
    this.failCount = 0,
  });

  /// 源ID
  final String sourceId;

  /// 目录路径前缀
  final String pathPrefix;

  /// 刮削阶段
  final MusicScrapePhase phase;

  /// 当前处理的曲目名称
  final String? currentTrack;

  /// 已处理数量
  final int processedCount;

  /// 总数量
  final int totalCount;

  /// 成功数量
  final int successCount;

  /// 跳过数量
  final int skipCount;

  /// 失败数量
  final int failCount;

  /// 计算进度百分比
  double get progress {
    if (totalCount == 0) return 0;
    return processedCount / totalCount;
  }

  /// 进度描述
  String get description {
    switch (phase) {
      case MusicScrapePhase.preparing:
        return appL10n.musicScrapeProgressPreparing;
      case MusicScrapePhase.scraping:
        if (currentTrack != null) {
          return appL10n.musicScrapeProgressScraping(currentTrack!);
        }
        return appL10n.musicScrapeProgressScrapingCount(
          processedCount,
          totalCount,
        );
      case MusicScrapePhase.completed:
        return appL10n.musicScrapeProgressCompleted(
          successCount,
          skipCount,
          failCount,
        );
      case MusicScrapePhase.cancelled:
        return appL10n.musicScrapeProgressCancelled;
      case MusicScrapePhase.error:
        return appL10n.musicScrapeProgressError;
    }
  }
}

/// 刮削阶段
enum MusicScrapePhase {
  /// 准备中
  preparing,

  /// 刮削中
  scraping,

  /// 完成
  completed,

  /// 已取消
  cancelled,

  /// 错误
  error,
}

/// 音乐刮削统计
class MusicScrapeStats {
  const MusicScrapeStats({
    this.total = 0,
    this.processed = 0,
    this.success = 0,
    this.skip = 0,
    this.fail = 0,
  });

  final int total;
  final int processed;
  final int success;
  final int skip;
  final int fail;

  double get progress => total == 0 ? 0 : processed / total;
}

/// 音乐刮削服务
///
/// 后台执行音乐元数据、封面、歌词的刮削
/// 不阻塞用户操作，进度通过 Stream 实时更新
///
/// 生命周期特性：
/// - 全局单例，不随页面生命周期销毁
/// - 页面切换不影响刮削进度
class MusicScrapeService {
  factory MusicScrapeService() => _instance ??= MusicScrapeService._();

  MusicScrapeService._();

  static MusicScrapeService? _instance;

  final _db = MusicDatabaseService();
  final _coverCache = MusicCoverCacheService();
  MusicScraperManagerService? _scraperManager;

  bool _isScraping = false;
  bool get isScraping => _isScraping;

  bool _shouldStop = false;

  // 当前刮削的目录信息
  String? _currentSourceId;
  String? _currentPathPrefix;

  String? get currentSourceId => _currentSourceId;
  String? get currentPathPrefix => _currentPathPrefix;

  /// 刮削进度流
  final _progressController = StreamController<MusicScrapeProgress>.broadcast();
  Stream<MusicScrapeProgress> get progressStream => _progressController.stream;

  /// 刮削统计流
  final _statsController = StreamController<MusicScrapeStats>.broadcast();
  Stream<MusicScrapeStats> get statsStream => _statsController.stream;

  /// 检查指定目录是否正在刮削
  bool isScrapingPath(String sourceId, String pathPrefix) =>
      _isScraping &&
      _currentSourceId == sourceId &&
      _currentPathPrefix == pathPrefix;

  /// 开始批量刮削
  ///
  /// [sourceId] 源ID
  /// [pathPrefix] 目录路径前缀
  /// [connection] 源连接（用于访问文件系统写入歌词）
  Future<void> startScraping({
    required String sourceId,
    required String pathPrefix,
    required SourceConnection connection,
  }) async {
    if (_isScraping) {
      logger.w('MusicScrapeService: 刮削正在进行中，跳过');
      return;
    }

    _isScraping = true;
    _shouldStop = false;
    _currentSourceId = sourceId;
    _currentPathPrefix = pathPrefix;

    final fileSystem = connection.adapter.fileSystem;

    try {
      // 初始化服务
      await _db.init();
      await _coverCache.init();
      _scraperManager ??= MusicScraperManagerService();
      await _scraperManager!.init();

      // 发送准备中进度
      _emitProgress(
        MusicScrapeProgress(
          sourceId: sourceId,
          pathPrefix: pathPrefix,
          phase: MusicScrapePhase.preparing,
        ),
      );

      // 获取该路径下的所有音乐数量
      final totalCount = await _db.getCount(
        sourceId: sourceId,
        pathPrefix: pathPrefix,
      );

      if (totalCount == 0) {
        _emitProgress(
          MusicScrapeProgress(
            sourceId: sourceId,
            pathPrefix: pathPrefix,
            phase: MusicScrapePhase.completed,
            totalCount: 0,
          ),
        );
        return;
      }

      // 开始刮削
      await _doScraping(
        sourceId: sourceId,
        pathPrefix: pathPrefix,
        totalCount: totalCount,
        fileSystem: fileSystem,
      );
    } catch (e, st) {
      // 部分 NAS SDK（目前 smb_connect 即属此类）会直接 throw String，
      // 而不是实现 Exception。批量任务是异步入口，必须在这里兜住所有
      // Object，避免单个远端文件错误逃逸到 PlatformDispatcher 并中断整批。
      AppError.handle(e, st, 'musicBatchScrape');
      _emitProgress(
        MusicScrapeProgress(
          sourceId: sourceId,
          pathPrefix: pathPrefix,
          phase: MusicScrapePhase.error,
        ),
      );
    } finally {
      _isScraping = false;
      _currentSourceId = null;
      _currentPathPrefix = null;
    }
  }

  /// 执行刮削
  Future<void> _doScraping({
    required String sourceId,
    required String pathPrefix,
    required int totalCount,
    NasFileSystem? fileSystem,
  }) async {
    var processedCount = 0;
    var successCount = 0;
    var skipCount = 0;
    var failCount = 0;

    // 发送刮削开始进度
    _emitProgress(
      MusicScrapeProgress(
        sourceId: sourceId,
        pathPrefix: pathPrefix,
        phase: MusicScrapePhase.scraping,
        totalCount: totalCount,
      ),
    );

    // 分批获取音乐（避免一次性加载太多）
    const batchSize = 50;
    var offset = 0;

    while (!_shouldStop) {
      final tracks = await _db.getPage(
        limit: batchSize,
        offset: offset,
        enabledPaths: [(sourceId: sourceId, path: pathPrefix)],
      );

      if (tracks.isEmpty) break;

      for (final track in tracks) {
        if (_shouldStop) break;

        // 发送当前处理的曲目
        _emitProgress(
          MusicScrapeProgress(
            sourceId: sourceId,
            pathPrefix: pathPrefix,
            phase: MusicScrapePhase.scraping,
            currentTrack: track.displayTitle,
            processedCount: processedCount,
            totalCount: totalCount,
            successCount: successCount,
            skipCount: skipCount,
            failCount: failCount,
          ),
        );

        // 处理单个曲目
        final result = await _processTrack(track, fileSystem);
        processedCount++;

        switch (result) {
          case _TrackResult.success:
            successCount++;
          case _TrackResult.skip:
            skipCount++;
          case _TrackResult.fail:
            failCount++;
        }

        // 发送进度更新
        _emitProgress(
          MusicScrapeProgress(
            sourceId: sourceId,
            pathPrefix: pathPrefix,
            phase: MusicScrapePhase.scraping,
            processedCount: processedCount,
            totalCount: totalCount,
            successCount: successCount,
            skipCount: skipCount,
            failCount: failCount,
          ),
        );

        // 广播统计
        _statsController.add(
          MusicScrapeStats(
            total: totalCount,
            processed: processedCount,
            success: successCount,
            skip: skipCount,
            fail: failCount,
          ),
        );

        // 稍微延迟，避免请求过快
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      offset += batchSize;
    }

    // 发送完成进度
    _emitProgress(
      MusicScrapeProgress(
        sourceId: sourceId,
        pathPrefix: pathPrefix,
        phase: _shouldStop
            ? MusicScrapePhase.cancelled
            : MusicScrapePhase.completed,
        processedCount: processedCount,
        totalCount: totalCount,
        successCount: successCount,
        skipCount: skipCount,
        failCount: failCount,
      ),
    );
  }

  /// 处理单个曲目
  Future<_TrackResult> _processTrack(
    MusicTrackEntity track,
    NasFileSystem? fileSystem,
  ) async {
    try {
      // 检查各项是否已有
      var hasCover = track.coverPath != null && track.coverPath!.isNotEmpty;
      final hasTitle = track.title != null && track.title!.isNotEmpty;
      final hasArtist = track.artist != null && track.artist!.isNotEmpty;
      final hasAlbum = track.album != null && track.album!.isNotEmpty;
      final hasYear = track.year != null && track.year! > 0;
      final hasGenre = track.genre != null && track.genre!.isNotEmpty;

      // 缺封面时先尝试 NAS sidecar 文件（<basename>-cover.jpg 等）
      var workingTrack = track;
      if (!hasCover) {
        final sidecarCache = await _trySidecarCover(track, fileSystem);
        if (sidecarCache != null) {
          workingTrack = workingTrack.copyWith(coverPath: sidecarCache);
          hasCover = true;
        }
      }

      // 检查是否已有歌词文件
      final hasLyrics = await _checkLyricsExists(track.filePath, fileSystem);

      // 如果全部都有，直接跳过
      if (hasCover && hasTitle && hasArtist && hasAlbum && hasLyrics) {
        // 若 sidecar 命中后 coverPath 与原 track 不同，需要持久化
        if (workingTrack != track) {
          await _db.upsert(workingTrack);
        }
        return _TrackResult.skip;
      }

      // 确定需要获取什么
      final needCover = !hasCover;
      final needLyrics = !hasLyrics;
      // 缺少任何元数据字段都需要尝试获取
      final needAnyMetadata =
          !hasTitle || !hasArtist || !hasAlbum || !hasYear || !hasGenre;

      // 搜索元数据（使用现有数据或从文件名解析）
      final searchTitle = hasTitle ? track.title! : track.displayTitle;
      // 标签缺失时仍可从常见的「歌手 - 标题.ext」文件名推出歌手。
      // 自动刮削把它作为约束，避免同名歌曲直接采用搜索接口第一项。
      final inferredArtist = track.displayArtist;
      final searchArtist =
          inferredArtist == appL10n.musicUnknownArtist ? null : inferredArtist;

      final result = await _scraperManager!.scrape(
        title: searchTitle,
        artist: searchArtist,
        album: hasAlbum ? track.album : null,
        durationMs: track.duration,
        getCover: needCover,
        getLyrics: needLyrics,
      );

      // 检查是否有任何有用的结果
      final hasUsefulResult = (needAnyMetadata && result.detail != null) ||
          (needCover && result.cover != null) ||
          (needLyrics && result.lyrics != null && result.lyrics!.hasLyrics);

      if (!hasUsefulResult) {
        return _TrackResult.fail;
      }

      // 应用结果（只补充缺失的内容）
      await _applyResult(
        workingTrack,
        result,
        fileSystem: fileSystem,
        needCover: needCover,
        needLyrics: needLyrics,
        hasTitle: hasTitle,
        hasArtist: hasArtist,
        hasAlbum: hasAlbum,
        hasYear: hasYear,
        hasGenre: hasGenre,
      );

      return _TrackResult.success;
    } catch (e, st) {
      logger.w('MusicScrapeService: 处理失败 ${track.displayTitle}: $e');
      AppError.ignore(e, st, '音乐单曲刮削失败: ${track.displayTitle}');
      return _TrackResult.fail;
    }
  }

  /// 检查歌词文件是否存在
  Future<bool> _checkLyricsExists(
    String musicPath,
    NasFileSystem? fileSystem,
  ) async {
    if (fileSystem == null) return false;

    try {
      final musicDir = nasPathDirname(musicPath);
      final baseName = nasPathBasenameWithoutExtension(musicPath);
      final lrcPath = nasPathJoin(musicDir, '$baseName.lrc');

      // 尝试获取文件信息，如果成功则文件存在
      await fileSystem.getFileInfo(lrcPath);
      return true;
    } catch (_) {
      // NAS 适配器可能抛出非 Exception 对象（例如 smb_connect 的 String）。
      // 文件不存在或获取失败
      return false;
    }
  }

  /// 尝试从 NAS sidecar 文件加载封面（`<basename>-cover.{jpg,png,webp}`）
  /// 命中后写入本地缓存，返回缓存路径；未命中返回 null。
  Future<String?> _trySidecarCover(
    MusicTrackEntity track,
    NasFileSystem? fileSystem,
  ) async {
    if (fileSystem == null) return null;
    final musicDir = nasPathDirname(track.filePath);
    final baseName = nasPathBasenameWithoutExtension(track.filePath);
    const exts = ['jpg', 'jpeg', 'png', 'webp'];
    for (final ext in exts) {
      final coverPath = nasPathJoin(musicDir, '$baseName-cover.$ext');
      try {
        await fileSystem.getFileInfo(coverPath);
      } catch (_) {
        continue;
      }
      try {
        final stream = await fileSystem.getFileStream(coverPath);
        final bytes = await stream.fold<List<int>>(
          [],
          (prev, chunk) => prev..addAll(chunk),
        );
        if (bytes.isEmpty) continue;
        final uniqueKey = '${track.sourceId}_${track.filePath}';
        return _coverCache.saveCover(uniqueKey, Uint8List.fromList(bytes));
      } catch (e, st) {
        logger.w('MusicScrapeService: 读取 sidecar 封面失败 $coverPath: $e');
        AppError.ignore(e, st, '读取音乐 sidecar 封面失败: $coverPath');
      }
    }
    return null;
  }

  /// 应用刮削结果
  Future<void> _applyResult(
    MusicTrackEntity track,
    MusicScrapeResult result, {
    NasFileSystem? fileSystem,
    required bool needCover,
    required bool needLyrics,
    required bool hasTitle,
    required bool hasArtist,
    required bool hasAlbum,
    required bool hasYear,
    required bool hasGenre,
  }) async {
    var updatedTrack = track;

    // 下载封面（仅当缺少封面时）
    if (needCover && result.cover != null) {
      try {
        final dio = DioClient.createTlsAware();
        final response = await dio.get<List<int>>(
          result.cover!.coverUrl,
          options: Options(responseType: ResponseType.bytes),
        );
        if (response.data != null) {
          final coverData = Uint8List.fromList(response.data!);

          // 保存封面到本地缓存
          final uniqueKey = '${track.sourceId}_${track.filePath}';
          final localCoverPath = await _coverCache.saveCover(
            uniqueKey,
            coverData,
          );

          if (localCoverPath != null) {
            updatedTrack = updatedTrack.copyWith(coverPath: localCoverPath);
          }

          // Sidecar 回写：把封面同步保存到曲目目录 <basename>-cover.jpg
          // 让其它播放器（VLC、PotPlayer、Jellyfin 等）也能识别封面
          if (fileSystem != null) {
            try {
              final musicDir = nasPathDirname(track.filePath);
              final baseName = nasPathBasenameWithoutExtension(track.filePath);
              final coverPath = nasPathJoin(musicDir, '$baseName-cover.jpg');
              await fileSystem.writeFile(coverPath, coverData);
            } catch (e, st) {
              logger.w('MusicScrapeService: 回写 sidecar 封面失败: $e');
              AppError.ignore(e, st, '回写音乐 sidecar 封面失败');
            }
          }
        }
      } catch (e, st) {
        logger.w('MusicScrapeService: 下载封面失败: $e');
        AppError.ignore(e, st, '下载音乐封面失败');
      }
    }

    // 下载歌词到 NAS（仅当缺少歌词时）
    if (needLyrics &&
        result.lyrics != null &&
        result.lyrics!.hasLyrics &&
        fileSystem != null) {
      try {
        final lrcContent =
            result.lyrics!.lrcContent ?? result.lyrics!.plainText ?? '';
        if (lrcContent.isNotEmpty) {
          final musicDir = nasPathDirname(track.filePath);
          final baseName = nasPathBasenameWithoutExtension(track.filePath);
          final lrcPath = nasPathJoin(musicDir, '$baseName.lrc');
          final utf8Bytes = const Utf8Encoder().convert(lrcContent);
          await fileSystem.writeFile(lrcPath, Uint8List.fromList(utf8Bytes));
        }
      } catch (e, st) {
        logger.w('MusicScrapeService: 下载歌词失败: $e');
        AppError.ignore(e, st, '下载并回写音乐歌词失败');
      }
    }

    // 补充缺失的元数据字段（不覆盖已有数据）
    if (result.detail != null) {
      final detail = result.detail!;
      updatedTrack = updatedTrack.copyWith(
        // 只补充缺失的字段
        title: hasTitle ? track.title : detail.title,
        artist: hasArtist ? track.artist : detail.artist,
        album: hasAlbum ? track.album : detail.album,
        year: hasYear ? track.year : detail.year,
        trackNumber: track.trackNumber ?? detail.trackNumber,
        genre: hasGenre ? track.genre : detail.genres?.join(', '),
      );
    }

    // 保存更新
    if (updatedTrack != track) {
      await _db.upsert(updatedTrack);
    }
  }

  /// 停止刮削
  void stopScraping() {
    _shouldStop = true;
  }

  /// 发送进度事件
  void _emitProgress(MusicScrapeProgress progress) {
    _progressController.add(progress);
  }

  /// 获取指定目录的刮削统计
  Future<MusicScrapeStats> getStats({
    required String sourceId,
    required String pathPrefix,
  }) async {
    await _db.init();
    final total = await _db.getCount(
      sourceId: sourceId,
      pathPrefix: pathPrefix,
    );
    return MusicScrapeStats(total: total);
  }

  /// 释放资源
  void dispose() {
    _progressController.close();
    _statsController.close();
  }
}

/// 曲目处理结果
enum _TrackResult { success, skip, fail }
