import 'dart:io';

import 'package:flutter/material.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/platform/spotlight/spotlight_hook.dart';
import 'package:my_nas/core/platform/spotlight/spotlight_item.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/features/video/domain/utils/genre_country_mapping.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// 视频排序选项
enum VideoSortOption {
  /// 评分从高到低
  ratingDesc,

  /// 评分从低到高
  ratingAsc,

  /// 年份从新到旧
  yearDesc,

  /// 年份从旧到新
  yearAsc,

  /// 名称 A-Z
  titleAsc,

  /// 名称 Z-A
  titleDesc,

  /// 添加时间从新到旧
  addedDesc,

  /// 添加时间从旧到新
  addedAsc,
}

/// 排序选项显示名称
extension VideoSortOptionExtension on VideoSortOption {
  String get displayName {
    switch (this) {
      case VideoSortOption.ratingDesc:
        return appL10n.videoSortRatingDesc;
      case VideoSortOption.ratingAsc:
        return appL10n.videoSortRatingAsc;
      case VideoSortOption.yearDesc:
        return appL10n.videoSortYearDesc;
      case VideoSortOption.yearAsc:
        return appL10n.videoSortYearAsc;
      case VideoSortOption.titleAsc:
        return appL10n.videoSortTitleAsc;
      case VideoSortOption.titleDesc:
        return appL10n.videoSortTitleDesc;
      case VideoSortOption.addedDesc:
        return appL10n.videoSortAddedDesc;
      case VideoSortOption.addedAsc:
        return appL10n.videoSortAddedAsc;
    }
  }

  IconData get icon {
    switch (this) {
      case VideoSortOption.ratingDesc:
      case VideoSortOption.ratingAsc:
        return Icons.star_rounded;
      case VideoSortOption.yearDesc:
      case VideoSortOption.yearAsc:
        return Icons.calendar_today_rounded;
      case VideoSortOption.titleAsc:
      case VideoSortOption.titleDesc:
        return Icons.sort_by_alpha_rounded;
      case VideoSortOption.addedDesc:
      case VideoSortOption.addedAsc:
        return Icons.access_time_rounded;
    }
  }
}

/// 视频数据库服务 - 使用 SQLite 支持大规模数据和索引查询
class VideoDatabaseService {
  factory VideoDatabaseService() => _instance ??= VideoDatabaseService._();
  VideoDatabaseService._();

  static VideoDatabaseService? _instance;

  Database? _db;
  bool _initialized = false;

  /// 获取数据库实例（供其他服务使用，如媒体服务器缓存）
  /// 调用前请确保已调用 init()
  Database? get database => _db;

  // 表名和列名常量
  static const String _tableMetadata = 'video_metadata';
  static const String _tableMediaServerCache = 'media_server_cache';
  static const String _tablePlaybackSyncQueue = 'playback_sync_queue';
  static const String _colId = 'id';
  static const String _colSourceId = 'source_id';
  static const String _colFilePath = 'file_path';
  static const String _colFileName = 'file_name';
  static const String _colCategory = 'category';
  static const String _colScrapeStatus = 'scrape_status';
  static const String _colTmdbId = 'tmdb_id';
  static const String _colTitle = 'title';
  static const String _colOriginalTitle = 'original_title';
  static const String _colYear = 'year';
  static const String _colOverview = 'overview';
  static const String _colPosterUrl = 'poster_url';
  static const String _colBackdropUrl = 'backdrop_url';
  static const String _colRating = 'rating';
  static const String _colRuntime = 'runtime';
  static const String _colGenres = 'genres';
  static const String _colCountries = 'countries';
  static const String _colDirector = 'director';
  static const String _colCast = 'cast_members';
  static const String _colSeasonNumber = 'season_number';
  static const String _colEpisodeNumber = 'episode_number';
  static const String _colEpisodeTitle = 'episode_title';
  static const String _colLastUpdated = 'last_updated';
  static const String _colThumbnailUrl = 'thumbnail_url';
  static const String _colGeneratedThumbnailUrl = 'generated_thumbnail_url';
  static const String _colLocalPosterUrl = 'local_poster_url';
  static const String _colLocalBackdropUrl = 'local_backdrop_url';
  static const String _colFileSize = 'file_size';
  static const String _colFileModifiedTime = 'file_modified_time';
  static const String _colCollectionId = 'collection_id';
  static const String _colCollectionName = 'collection_name';
  static const String _colCollectionPosterUrl =
      'collection_poster_url'; // 系列海报 URL
  static const String _colCollectionBackdropUrl =
      'collection_backdrop_url'; // 系列背景图 URL
  static const String _colHasNfo = 'has_nfo'; // 是否检测到 NFO 文件
  static const String _colScrapePriority = 'scrape_priority'; // 刮削优先级
  static const String _colShowDirectory = 'show_directory'; // TV 剧集所属剧目录
  static const String _colMovieDirectory = 'movie_directory'; // 电影所在目录
  static const String _colResolution =
      'resolution'; // 视频分辨率 (4K, 1080p, 720p 等)
  static const String _colLocalizedTitles = 'localized_titles'; // 多语言标题 JSON
  static const String _colLocalizedOverviews =
      'localized_overviews'; // 多语言简介 JSON
  // 扩展视频信息
  static const String _colVideoSource = 'video_source'; // 视频来源（BluRay, WEB-DL）
  static const String _colVideoCodec = 'video_codec'; // 视频编码（HEVC, x265）
  static const String _colHdrFormat =
      'hdr_format'; // HDR 格式（HDR10, Dolby Vision）
  static const String _colAudioFormat =
      'audio_format'; // 音频格式（Atmos, DTS-HD MA）
  static const String _colIs3D = 'is_3d'; // 是否 3D 内容
  static const String _colIsRemux = 'is_remux'; // 是否 Remux 版本
  // 扩展评分
  static const String _colImdbId = 'imdb_id'; // IMDb ID
  static const String _colImdbRating = 'imdb_rating'; // IMDb 评分
  static const String _colMetacriticRating =
      'metacritic_rating'; // Metacritic 评分
  static const String _colTraktRating = 'trakt_rating'; // Trakt 评分
  // 内容分级
  static const String _colCertification = 'certification'; // 内容分级（PG, R 等）

  // 媒体服务器相关字段
  static const String _colServerType =
      'server_type'; // 服务器类型 (jellyfin, emby, plex)
  static const String _colServerItemId = 'server_item_id'; // 服务器中的项目 ID
  static const String _colScrapeSource =
      'scrape_source'; // 元数据来源 (tmdb, server, nfo, filename)
  static const String _colIsWatched = 'is_watched'; // 是否已观看
  static const String _colPlaybackPositionTicks =
      'playback_position_ticks'; // 播放位置（时间刻度）
  static const String _colLastPlayedAt = 'last_played_at'; // 最后播放时间

  // 字幕表
  static const String _tableSubtitles = 'video_subtitles';
  static const String _subColId = 'id';
  static const String _subColSourceId = 'source_id';
  static const String _subColVideoPath = 'video_path'; // 关联的视频文件路径
  static const String _subColSubtitlePath = 'subtitle_path'; // 字幕文件路径
  static const String _subColFileName = 'file_name'; // 字幕文件名
  static const String _subColFormat = 'format'; // 字幕格式 (srt, ass, vtt)
  static const String _subColLanguage = 'language'; // 语言

  // TV 剧集分组表（预计算聚合数据，避免 GROUP BY）
  static const String _tableTvShowGroups = 'tv_show_groups';
  static const String _tvgColId = 'id';
  static const String _tvgColGroupKey = 'group_key'; // 'tmdb_123' 或 'title_xxx'
  static const String _tvgColTmdbId = 'tmdb_id';
  static const String _tvgColTitle = 'title';
  static const String _tvgColNormalizedTitle = 'normalized_title';
  static const String _tvgColOriginalTitle = 'original_title';
  static const String _tvgColYear = 'year';
  static const String _tvgColOverview = 'overview';
  static const String _tvgColPosterUrl = 'poster_url';
  static const String _tvgColBackdropUrl = 'backdrop_url';
  static const String _tvgColRating = 'rating';
  static const String _tvgColGenres = 'genres';
  static const String _tvgColSeasonCount = 'season_count';
  static const String _tvgColEpisodeCount = 'episode_count';
  static const String _tvgColRepresentativeRowid = 'representative_rowid';
  static const String _tvgColLastSynced = 'last_synced';
  static const String _tvgColLocalPosterUrl =
      'local_poster_url'; // 本地海报路径（NAS 路径或 file:// 路径）

  // 电影系列分组表
  static const String _tableMovieCollectionGroups = 'movie_collection_groups';
  static const String _mcgColId = 'id';
  static const String _mcgColTmdbCollectionId = 'tmdb_collection_id';
  static const String _mcgColName = 'name';
  static const String _mcgColPosterUrl = 'poster_url';
  static const String _mcgColBackdropUrl = 'backdrop_url';
  static const String _mcgColOverview = 'overview';
  static const String _mcgColMovieCount = 'movie_count';
  static const String _mcgColLastSynced = 'last_synced';
  static const String _mcgColLocalPosterUrl = 'local_poster_url'; // 本地海报路径

  // 目录扫描状态表（用于增量扫描和断点续扫）
  static const String _tableScanProgress = 'scan_progress';
  static const String _scanColId = 'id';
  static const String _scanColSourceId = 'source_id';
  static const String _scanColPath = 'path'; // 目录路径
  static const String _scanColRootPath = 'root_path'; // 根目录路径（媒体库配置的路径）
  static const String _scanColStatus =
      'status'; // 0=pending, 1=scanning, 2=completed
  static const String _scanColVideoCount = 'video_count'; // 该目录发现的视频数
  static const String _scanColLastScanned = 'last_scanned'; // 最后扫描时间
  static const String _scanColDirModifiedTime =
      'dir_modified_time'; // 目录的修改时间（用于增量同步）

  /// 扫描状态常量
  static const int scanStatusPending = 0;
  static const int scanStatusScanning = 1;
  static const int scanStatusCompleted = 2;

  /// 初始化数据库
  Future<void> init() async {
    if (_initialized) return;

    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      final dbPath = join(documentsDir.path, 'video_metadata.db');

      _db = await openDatabase(
        dbPath,
        version: 20, // 添加 NFO 本地背景图字段
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        onConfigure: _onConfigure,
      );

      _initialized = true;
      logger.i('VideoDatabaseService: 数据库初始化完成');
    } catch (e, st) {
      AppError.handle(e, st, 'VideoDatabaseService.init');
      rethrow;
    }
  }

  /// 数据库配置 - 启用 WAL 模式和安全设置
  ///
  /// WAL (Write-Ahead Logging) 模式的优势：
  /// - 更好的并发性能：读写可以同时进行
  /// - 更安全的写入：写入中断时自动回滚到一致状态
  /// - 更快的恢复：应用崩溃后恢复更快
  Future<void> _onConfigure(Database db) async {
    // 使用 rawQuery 获取 PRAGMA 结果，避免 iOS 上 "not an error" 异常
    // 启用 WAL 模式
    await db.rawQuery('PRAGMA journal_mode=WAL');
    // 设置同步模式为 NORMAL（平衡安全性和性能）
    // FULL 更安全但性能较低，NORMAL 在大多数情况下足够安全
    await db.rawQuery('PRAGMA synchronous=NORMAL');
    // 设置忙等待超时（5秒），避免锁冲突时立即失败
    await db.rawQuery('PRAGMA busy_timeout=5000');
    // 启用外键约束
    await db.rawQuery('PRAGMA foreign_keys=ON');
    logger.d('VideoDatabaseService: 数据库配置完成 (WAL模式)');
  }

  /// 创建表和索引
  Future<void> _onCreate(Database db, int version) async {
    // 创建主表
    await db.execute('''
      CREATE TABLE $_tableMetadata (
        $_colId INTEGER PRIMARY KEY AUTOINCREMENT,
        $_colSourceId TEXT NOT NULL,
        $_colFilePath TEXT NOT NULL,
        $_colFileName TEXT NOT NULL,
        $_colCategory INTEGER DEFAULT 2,
        $_colScrapeStatus INTEGER DEFAULT 0,
        $_colTmdbId INTEGER,
        $_colTitle TEXT,
        $_colOriginalTitle TEXT,
        $_colYear INTEGER,
        $_colOverview TEXT,
        $_colPosterUrl TEXT,
        $_colBackdropUrl TEXT,
        $_colRating REAL,
        $_colRuntime INTEGER,
        $_colGenres TEXT,
        $_colCountries TEXT,
        $_colDirector TEXT,
        $_colCast TEXT,
        $_colSeasonNumber INTEGER,
        $_colEpisodeNumber INTEGER,
        $_colEpisodeTitle TEXT,
        $_colLastUpdated INTEGER,
        $_colThumbnailUrl TEXT,
        $_colGeneratedThumbnailUrl TEXT,
        $_colLocalPosterUrl TEXT,
        $_colLocalBackdropUrl TEXT,
        $_colFileSize INTEGER,
        $_colFileModifiedTime INTEGER,
        $_colCollectionId INTEGER,
        $_colCollectionName TEXT,
        $_colCollectionPosterUrl TEXT,
        $_colCollectionBackdropUrl TEXT,
        $_colHasNfo INTEGER DEFAULT 0,
        $_colScrapePriority INTEGER DEFAULT 2,
        $_colShowDirectory TEXT,
        $_colMovieDirectory TEXT,
        $_colResolution TEXT,
        $_colLocalizedTitles TEXT,
        $_colLocalizedOverviews TEXT,
        $_colVideoSource TEXT,
        $_colVideoCodec TEXT,
        $_colHdrFormat TEXT,
        $_colAudioFormat TEXT,
        $_colIs3D INTEGER DEFAULT 0,
        $_colIsRemux INTEGER DEFAULT 0,
        $_colImdbId TEXT,
        $_colImdbRating REAL,
        $_colMetacriticRating INTEGER,
        $_colTraktRating REAL,
        $_colCertification TEXT,
        $_colServerType TEXT,
        $_colServerItemId TEXT,
        $_colScrapeSource TEXT,
        $_colIsWatched INTEGER DEFAULT 0,
        $_colPlaybackPositionTicks INTEGER,
        $_colLastPlayedAt INTEGER,
        UNIQUE($_colSourceId, $_colFilePath)
      )
    ''');

    // 创建索引 - 用于快速查询
    await db.execute(
      'CREATE INDEX idx_tmdb_id ON $_tableMetadata($_colTmdbId)',
    );
    await db.execute(
      'CREATE INDEX idx_category ON $_tableMetadata($_colCategory)',
    );
    await db.execute(
      'CREATE INDEX idx_scrape_status ON $_tableMetadata($_colScrapeStatus)',
    );
    await db.execute('CREATE INDEX idx_year ON $_tableMetadata($_colYear)');
    await db.execute(
      'CREATE INDEX idx_rating ON $_tableMetadata($_colRating DESC)',
    );
    await db.execute(
      'CREATE INDEX idx_source_id ON $_tableMetadata($_colSourceId)',
    );
    await db.execute(
      'CREATE INDEX idx_last_updated ON $_tableMetadata($_colLastUpdated DESC)',
    );
    // 复合索引 - 用于剧集查询
    await db.execute(
      'CREATE INDEX idx_tmdb_season_episode ON $_tableMetadata($_colTmdbId, $_colSeasonNumber, $_colEpisodeNumber)',
    );
    // 电影系列索引
    await db.execute(
      'CREATE INDEX idx_collection_id ON $_tableMetadata($_colCollectionId)',
    );
    // 刮削优先级索引（用于智能排序）
    await db.execute(
      'CREATE INDEX idx_scrape_priority ON $_tableMetadata($_colScrapePriority, $_colScrapeStatus)',
    );
    // 媒体服务器索引（用于快速查找服务器项目）
    await db.execute(
      'CREATE INDEX idx_server_item ON $_tableMetadata($_colSourceId, $_colServerItemId)',
    );
    // 观看状态索引
    await db.execute(
      'CREATE INDEX idx_watched ON $_tableMetadata($_colIsWatched)',
    );

    // 创建字幕索引表
    await _createSubtitleTable(db);

    // 创建扫描进度表
    await _createScanProgressTable(db);

    // 创建聚合表
    await _createTvShowGroupsTable(db);
    await _createMovieCollectionGroupsTable(db);

    // 创建媒体服务器相关表
    await _createMediaServerCacheTable(db);
    await _createPlaybackSyncQueueTable(db);

    logger.i('VideoDatabaseService: 表和索引创建完成');
  }

  /// 创建媒体服务器缓存表
  Future<void> _createMediaServerCacheTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableMediaServerCache (
        id TEXT PRIMARY KEY,
        source_id TEXT NOT NULL,
        item_id TEXT NOT NULL,
        parent_id TEXT,
        item_type TEXT NOT NULL,
        name TEXT NOT NULL,
        metadata_json TEXT NOT NULL,
        image_urls_json TEXT,
        last_updated INTEGER NOT NULL,
        UNIQUE(source_id, item_id)
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_msc_source_parent
      ON $_tableMediaServerCache(source_id, parent_id)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_msc_type
      ON $_tableMediaServerCache(source_id, item_type)
    ''');
    logger.i('VideoDatabaseService: 媒体服务器缓存表创建完成');
  }

  /// 创建播放同步队列表
  Future<void> _createPlaybackSyncQueueTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tablePlaybackSyncQueue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source_id TEXT NOT NULL,
        item_id TEXT NOT NULL,
        position_ticks INTEGER NOT NULL,
        is_watched INTEGER NOT NULL DEFAULT 0,
        event_type TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        retry_count INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        synced_at INTEGER,
        error_message TEXT
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_psq_status
      ON $_tablePlaybackSyncQueue(sync_status, created_at)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_psq_source
      ON $_tablePlaybackSyncQueue(source_id, item_id)
    ''');
    logger.i('VideoDatabaseService: 播放同步队列表创建完成');
  }

  /// 创建字幕索引表
  Future<void> _createSubtitleTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableSubtitles (
        $_subColId INTEGER PRIMARY KEY AUTOINCREMENT,
        $_subColSourceId TEXT NOT NULL,
        $_subColVideoPath TEXT NOT NULL,
        $_subColSubtitlePath TEXT NOT NULL,
        $_subColFileName TEXT NOT NULL,
        $_subColFormat TEXT NOT NULL,
        $_subColLanguage TEXT,
        UNIQUE($_subColSourceId, $_subColSubtitlePath)
      )
    ''');

    // 创建索引 - 用于快速查询视频对应的字幕
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_subtitle_video ON $_tableSubtitles($_subColSourceId, $_subColVideoPath)',
    );

    logger.i('VideoDatabaseService: 字幕索引表创建完成');
  }

  /// 创建扫描进度表
  ///
  /// 用于跟踪目录扫描状态，支持增量扫描和断点续扫
  Future<void> _createScanProgressTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableScanProgress (
        $_scanColId INTEGER PRIMARY KEY AUTOINCREMENT,
        $_scanColSourceId TEXT NOT NULL,
        $_scanColPath TEXT NOT NULL,
        $_scanColRootPath TEXT NOT NULL,
        $_scanColStatus INTEGER DEFAULT 0,
        $_scanColVideoCount INTEGER DEFAULT 0,
        $_scanColLastScanned INTEGER,
        $_scanColDirModifiedTime INTEGER,
        UNIQUE($_scanColSourceId, $_scanColPath)
      )
    ''');

    // 创建索引 - 用于快速查询待扫描目录
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_scan_source_status ON $_tableScanProgress($_scanColSourceId, $_scanColStatus)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_scan_root ON $_tableScanProgress($_scanColSourceId, $_scanColRootPath)',
    );

    logger.i('VideoDatabaseService: 扫描进度表创建完成');
  }

  /// 创建 TV 剧集分组表
  ///
  /// 预计算的聚合表，每部剧一行，避免 GROUP BY 查询
  Future<void> _createTvShowGroupsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableTvShowGroups (
        $_tvgColId INTEGER PRIMARY KEY AUTOINCREMENT,
        $_tvgColGroupKey TEXT UNIQUE NOT NULL,
        $_tvgColTmdbId INTEGER,
        $_tvgColTitle TEXT NOT NULL,
        $_tvgColNormalizedTitle TEXT NOT NULL,
        $_tvgColOriginalTitle TEXT,
        $_tvgColYear INTEGER,
        $_tvgColOverview TEXT,
        $_tvgColPosterUrl TEXT,
        $_tvgColBackdropUrl TEXT,
        $_tvgColRating REAL,
        $_tvgColGenres TEXT,
        $_tvgColSeasonCount INTEGER DEFAULT 0,
        $_tvgColEpisodeCount INTEGER DEFAULT 0,
        $_tvgColRepresentativeRowid INTEGER,
        $_tvgColLastSynced INTEGER,
        $_tvgColLocalPosterUrl TEXT
      )
    ''');

    // 创建索引
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_tvg_tmdb_id ON $_tableTvShowGroups($_tvgColTmdbId)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_tvg_rating ON $_tableTvShowGroups($_tvgColRating DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_tvg_normalized_title ON $_tableTvShowGroups($_tvgColNormalizedTitle)',
    );

    logger.i('VideoDatabaseService: TV剧集分组表创建完成');
  }

  /// 创建电影系列分组表
  Future<void> _createMovieCollectionGroupsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tableMovieCollectionGroups (
        $_mcgColId INTEGER PRIMARY KEY AUTOINCREMENT,
        $_mcgColTmdbCollectionId INTEGER UNIQUE,
        $_mcgColName TEXT NOT NULL,
        $_mcgColPosterUrl TEXT,
        $_mcgColBackdropUrl TEXT,
        $_mcgColOverview TEXT,
        $_mcgColMovieCount INTEGER DEFAULT 0,
        $_mcgColLastSynced INTEGER,
        $_mcgColLocalPosterUrl TEXT
      )
    ''');

    // 创建索引
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_mcg_tmdb_id ON $_tableMovieCollectionGroups($_mcgColTmdbCollectionId)',
    );

    logger.i('VideoDatabaseService: 电影系列分组表创建完成');
  }

  /// 迁移 TV 剧集的 show_directory 字段
  ///
  /// 从现有 TV 剧集记录的 file_path 解析出 show_directory
  /// 这是一次性迁移，在数据库升级到版本 9 时执行
  Future<void> _migrateShowDirectories(Database db) async {
    // 获取所有 TV 剧集记录
    final tvShows = await db.query(
      _tableMetadata,
      columns: [_colId, _colFilePath],
      where: '$_colCategory = ?',
      whereArgs: [MediaCategory.tvShow.index],
    );

    if (tvShows.isEmpty) {
      logger.d('VideoDatabaseService: 无 TV 剧集需要迁移 show_directory');
      return;
    }

    logger.i(
      'VideoDatabaseService: 开始迁移 ${tvShows.length} 条 TV 剧集的 show_directory',
    );

    // 批量更新
    final batch = db.batch();
    for (final row in tvShows) {
      final id = row[_colId] as int?;
      final filePath = row[_colFilePath] as String?;
      if (id == null || filePath == null) continue;
      final showDir = extractShowDirectory(filePath);

      if (showDir != null) {
        batch.update(
          _tableMetadata,
          {_colShowDirectory: showDir},
          where: '$_colId = ?',
          whereArgs: [id],
        );
      }
    }

    await batch.commit(noResult: true);
    logger.i('VideoDatabaseService: show_directory 迁移完成');
  }

  /// 从文件路径提取剧目录
  ///
  /// 识别常见的电视剧目录结构：
  /// - `/TV/Breaking Bad/Season 1/S01E01.mkv` → `/TV/Breaking Bad`
  /// - `/TV/剧名.S01/S01E01.mkv` → `/TV/剧名.S01`
  /// - `/TV/剧名/S01E01.mkv` → `/TV/剧名`
  ///
  /// 规则：
  /// 1. 如果父目录名匹配季目录模式（Season X, S01 等），取祖父目录
  /// 2. 否则取父目录
  static String? extractShowDirectory(String filePath) {
    if (filePath.isEmpty) return null;

    // 标准化路径分隔符
    final normalizedPath = filePath.replaceAll(r'\', '/');
    final parts = normalizedPath.split('/').where((p) => p.isNotEmpty).toList();

    if (parts.length < 2) return null;

    // 文件名是最后一个部分
    // parts.removeLast(); // 移除文件名

    // 检查父目录是否是季目录
    final parentDir = parts.length >= 2 ? parts[parts.length - 2] : null;

    if (parentDir != null && _isSeasonDirectory(parentDir)) {
      // 父目录是季目录，取祖父目录作为剧目录
      if (parts.length >= 3) {
        // 返回从根到祖父目录的完整路径
        return '/${parts.sublist(0, parts.length - 2).join('/')}';
      }
      return null;
    }

    // 父目录不是季目录，父目录本身就是剧目录
    if (parts.length >= 2) {
      return '/${parts.sublist(0, parts.length - 1).join('/')}';
    }

    return null;
  }

  /// 检查目录名是否是季目录
  ///
  /// 季目录模式包括：
  /// - Season X, Season 01, Season1
  /// - S01, S1
  /// - 第X季, 第一季
  /// - Specials, 特典, SP
  static bool isSeasonDirectory(String dirName) {
    final name = dirName.toLowerCase().trim();

    // 常见季目录模式
    // Season 1, Season 01, Season1
    if (RegExp(r'^season\s*\d+$', caseSensitive: false).hasMatch(name)) {
      return true;
    }

    // S01, S1
    if (RegExp(r'^s\d{1,2}$', caseSensitive: false).hasMatch(name)) {
      return true;
    }

    // 第1季, 第一季
    if (RegExp(r'^第[\d一二三四五六七八九十]+季$').hasMatch(name)) {
      return true;
    }

    // Specials, 特典
    if (name == 'specials' || name == '特典' || name == 'sp') {
      return true;
    }

    return false;
  }

  // 保留私有别名以保持内部兼容性
  static bool _isSeasonDirectory(String dirName) => isSeasonDirectory(dirName);

  /// 迁移电影的 movie_directory 字段
  ///
  /// 从现有电影记录的 file_path 解析出 movie_directory
  /// 这是一次性迁移，在数据库升级到版本 10 时执行
  Future<void> _migrateMovieDirectories(Database db) async {
    // 获取所有电影记录
    final movies = await db.query(
      _tableMetadata,
      columns: [_colId, _colFilePath],
      where: '$_colCategory = ?',
      whereArgs: [MediaCategory.movie.index],
    );

    if (movies.isEmpty) {
      logger.d('VideoDatabaseService: 无电影需要迁移 movie_directory');
      return;
    }

    logger.i(
      'VideoDatabaseService: 开始迁移 ${movies.length} 条电影的 movie_directory',
    );

    // 批量更新
    final batch = db.batch();
    for (final row in movies) {
      final id = row[_colId] as int?;
      final filePath = row[_colFilePath] as String?;
      if (id == null || filePath == null) continue;
      final movieDir = extractMovieDirectory(filePath);

      if (movieDir != null) {
        batch.update(
          _tableMetadata,
          {_colMovieDirectory: movieDir},
          where: '$_colId = ?',
          whereArgs: [id],
        );
      }
    }

    await batch.commit(noResult: true);
    logger.i('VideoDatabaseService: movie_directory 迁移完成');
  }

  /// 从文件路径提取电影所在目录
  ///
  /// 电影目录结构比 TV 剧集简单，直接取父目录
  /// 例如：
  /// - `/Movies/漫威电影宇宙/钢铁侠.mkv` → `/Movies/漫威电影宇宙`
  /// - `/Movies/2023/Oppenheimer.mkv` → `/Movies/2023`
  static String? extractMovieDirectory(String filePath) {
    if (filePath.isEmpty) return null;

    // 标准化路径分隔符
    final normalizedPath = filePath.replaceAll(r'\', '/');
    final parts = normalizedPath.split('/').where((p) => p.isNotEmpty).toList();

    if (parts.length < 2) return null;

    // 直接返回父目录路径
    return '/${parts.sublist(0, parts.length - 1).join('/')}';
  }

  /// 迁移视频的 resolution 字段
  ///
  /// 从现有视频记录的 file_name 解析出分辨率
  /// 这是一次性迁移，在数据库升级到版本 11 时执行
  Future<void> _migrateResolutions(Database db) async {
    // 获取所有没有 resolution 的记录
    final videos = await db.query(
      _tableMetadata,
      columns: [_colId, _colFileName],
      where: '$_colResolution IS NULL',
    );

    if (videos.isEmpty) {
      logger.d('VideoDatabaseService: 无视频需要迁移 resolution');
      return;
    }

    logger.i('VideoDatabaseService: 开始迁移 ${videos.length} 条视频的 resolution');

    // 批量更新
    final batch = db.batch();
    for (final row in videos) {
      final id = row[_colId] as int?;
      final fileName = row[_colFileName] as String?;
      if (id == null || fileName == null) continue;

      final fileInfo = VideoFileNameParser.parse(fileName);
      if (fileInfo.resolution != null) {
        batch.update(
          _tableMetadata,
          {_colResolution: fileInfo.resolution},
          where: '$_colId = ?',
          whereArgs: [id],
        );
      }
    }

    await batch.commit(noResult: true);
    logger.i('VideoDatabaseService: resolution 迁移完成');
  }

  /// 迁移扩展视频信息（从文件名解析 HDR、音频格式等）
  Future<void> _migrateExtendedVideoInfo(Database db) async {
    // 获取所有没有扩展视频信息的记录
    final videos = await db.query(
      _tableMetadata,
      columns: [_colId, _colFileName],
      where: '$_colVideoSource IS NULL AND $_colHdrFormat IS NULL',
    );

    if (videos.isEmpty) {
      logger.d('VideoDatabaseService: 无视频需要迁移扩展视频信息');
      return;
    }

    logger.i('VideoDatabaseService: 开始迁移 ${videos.length} 条视频的扩展视频信息');

    // 批量更新
    final batch = db.batch();
    for (final row in videos) {
      final id = row[_colId] as int?;
      final fileName = row[_colFileName] as String?;
      if (id == null || fileName == null) continue;

      final fileInfo = VideoFileNameParser.parse(fileName);

      // 只有当解析出有效信息时才更新
      final updates = <String, dynamic>{};
      if (fileInfo.source != null) updates[_colVideoSource] = fileInfo.source;
      if (fileInfo.codec != null) updates[_colVideoCodec] = fileInfo.codec;
      if (fileInfo.hdrFormat != null) {
        updates[_colHdrFormat] = fileInfo.hdrFormat;
      }
      if (fileInfo.audioFormat != null) {
        updates[_colAudioFormat] = fileInfo.audioFormat;
      }
      if (fileInfo.is3D) updates[_colIs3D] = 1;
      if (fileInfo.isRemux) updates[_colIsRemux] = 1;

      if (updates.isNotEmpty) {
        batch.update(
          _tableMetadata,
          updates,
          where: '$_colId = ?',
          whereArgs: [id],
        );
      }
    }

    await batch.commit(noResult: true);
    logger.i('VideoDatabaseService: 扩展视频信息迁移完成');
  }

  /// 数据库升级
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    logger.i('VideoDatabaseService: 数据库升级 $oldVersion -> $newVersion');

    // 从版本1升级到版本2
    if (oldVersion < 2) {
      // 添加刮削状态字段
      await db.execute(
        'ALTER TABLE $_tableMetadata ADD COLUMN $_colScrapeStatus INTEGER DEFAULT 0',
      );
      // 添加文件大小字段
      await db.execute(
        'ALTER TABLE $_tableMetadata ADD COLUMN $_colFileSize INTEGER',
      );
      // 添加文件修改时间字段
      await db.execute(
        'ALTER TABLE $_tableMetadata ADD COLUMN $_colFileModifiedTime INTEGER',
      );
      // 创建刮削状态索引
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_scrape_status ON $_tableMetadata($_colScrapeStatus)',
      );

      // 将现有已有TMDB数据的记录标记为已刮削完成
      await db.execute('''
        UPDATE $_tableMetadata
        SET $_colScrapeStatus = 2
        WHERE $_colTmdbId IS NOT NULL
      ''');

      logger.i('VideoDatabaseService: 版本1->2 升级完成');
    }

    // 从版本2升级到版本3
    if (oldVersion < 3) {
      // 添加电影系列字段
      await db.execute(
        'ALTER TABLE $_tableMetadata ADD COLUMN $_colCollectionId INTEGER',
      );
      await db.execute(
        'ALTER TABLE $_tableMetadata ADD COLUMN $_colCollectionName TEXT',
      );
      // 创建电影系列索引
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_collection_id ON $_tableMetadata($_colCollectionId)',
      );

      logger.i('VideoDatabaseService: 版本2->3 升级完成');
    }

    // 从版本3升级到版本4
    if (oldVersion < 4) {
      // 添加 NFO 检测标志
      await db.execute(
        'ALTER TABLE $_tableMetadata ADD COLUMN $_colHasNfo INTEGER DEFAULT 0',
      );
      // 添加刮削优先级字段
      await db.execute(
        'ALTER TABLE $_tableMetadata ADD COLUMN $_colScrapePriority INTEGER DEFAULT 2',
      );
      // 创建刮削优先级索引
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_scrape_priority ON $_tableMetadata($_colScrapePriority, $_colScrapeStatus)',
      );

      logger.i('VideoDatabaseService: 版本3->4 升级完成');
    }

    // 从版本4升级到版本5
    if (oldVersion < 5) {
      // 添加本地海报缓存路径字段
      await db.execute(
        'ALTER TABLE $_tableMetadata ADD COLUMN $_colLocalPosterUrl TEXT',
      );

      logger.i('VideoDatabaseService: 版本4->5 升级完成');
    }

    // 从版本5升级到版本6
    if (oldVersion < 6) {
      // 添加字幕索引表
      await _createSubtitleTable(db);

      logger.i('VideoDatabaseService: 版本5->6 升级完成（添加字幕索引表）');
    }

    // 从版本6升级到版本7
    if (oldVersion < 7) {
      // 添加扫描进度表
      await _createScanProgressTable(db);

      logger.i('VideoDatabaseService: 版本6->7 升级完成（添加扫描进度表）');
    }

    // 从版本7升级到版本8
    if (oldVersion < 8) {
      // 添加 TV 剧集分组表
      await _createTvShowGroupsTable(db);
      // 添加电影系列分组表
      await _createMovieCollectionGroupsTable(db);

      logger.i('VideoDatabaseService: 版本7->8 升级完成（添加聚合表）');
    }

    // 从版本8升级到版本9
    if (oldVersion < 9) {
      // 添加 show_directory 字段（TV 剧集所属剧目录，用于分组）
      await db.execute(
        'ALTER TABLE $_tableMetadata ADD COLUMN $_colShowDirectory TEXT',
      );
      // 创建索引
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_show_directory ON $_tableMetadata($_colShowDirectory)',
      );

      // 迁移现有 TV 剧集数据：从 file_path 解析 show_directory
      // 使用 _extractShowDirectory 逻辑在 Dart 层处理
      await _migrateShowDirectories(db);

      logger.i('VideoDatabaseService: 版本8->9 升级完成（添加 show_directory 字段）');
    }

    // 从版本9升级到版本10
    if (oldVersion < 10) {
      // 添加 movie_directory 字段（电影所在目录，用于目录系列识别）
      await db.execute(
        'ALTER TABLE $_tableMetadata ADD COLUMN $_colMovieDirectory TEXT',
      );
      // 创建索引
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_movie_directory ON $_tableMetadata($_colMovieDirectory)',
      );

      // 迁移现有电影数据：从 file_path 解析 movie_directory
      await _migrateMovieDirectories(db);

      logger.i('VideoDatabaseService: 版本9->10 升级完成（添加 movie_directory 字段）');
    }

    // 从版本10升级到版本11
    if (oldVersion < 11) {
      // 添加 resolution 字段（视频分辨率，用于质量分组）
      await db.execute(
        'ALTER TABLE $_tableMetadata ADD COLUMN $_colResolution TEXT',
      );

      // 迁移现有数据：从文件名解析 resolution
      await _migrateResolutions(db);

      logger.i('VideoDatabaseService: 版本10->11 升级完成（添加 resolution 字段）');
    }

    // 从版本11升级到版本12
    if (oldVersion < 12) {
      // 添加 local_poster_url 列到聚合表（使用 _safeAddColumn 避免重复添加）
      await _safeAddColumn(
        db,
        _tableTvShowGroups,
        _tvgColLocalPosterUrl,
        'TEXT',
      );
      await _safeAddColumn(
        db,
        _tableMovieCollectionGroups,
        _mcgColLocalPosterUrl,
        'TEXT',
      );

      // 从 video_metadata 同步 local_poster_url 到 tv_show_groups
      await db.execute('''
        UPDATE $_tableTvShowGroups
        SET $_tvgColLocalPosterUrl = (
          SELECT vm.$_colLocalPosterUrl
          FROM $_tableMetadata vm
          WHERE vm.rowid = $_tableTvShowGroups.$_tvgColRepresentativeRowid
        )
      ''');

      logger.i(
        'VideoDatabaseService: 版本11->12 升级完成（添加聚合表 local_poster_url 字段）',
      );
    }

    // 从版本12升级到版本13
    if (oldVersion < 13) {
      // 添加多语言元数据字段
      await db.execute(
        'ALTER TABLE $_tableMetadata ADD COLUMN $_colLocalizedTitles TEXT',
      );
      await db.execute(
        'ALTER TABLE $_tableMetadata ADD COLUMN $_colLocalizedOverviews TEXT',
      );

      logger.i('VideoDatabaseService: 版本12->13 升级完成（添加多语言元数据字段）');
    }

    // 从版本13升级到版本14
    if (oldVersion < 14) {
      // 添加国家/地区字段
      await db.execute(
        'ALTER TABLE $_tableMetadata ADD COLUMN $_colCountries TEXT',
      );

      logger.i('VideoDatabaseService: 版本13->14 升级完成（添加国家/地区字段）');
    }

    // 从版本14升级到版本15
    if (oldVersion < 15) {
      // 添加电影系列海报字段（存储 TMDB 系列专属海报）
      await db.execute(
        'ALTER TABLE $_tableMetadata ADD COLUMN $_colCollectionPosterUrl TEXT',
      );
      await db.execute(
        'ALTER TABLE $_tableMetadata ADD COLUMN $_colCollectionBackdropUrl TEXT',
      );

      logger.i('VideoDatabaseService: 版本14->15 升级完成（添加系列海报字段）');
    }

    // 从版本15升级到版本16
    // 修复：版本15的迁移可能在某些情况下没有成功执行，导致列缺失
    if (oldVersion < 16) {
      // 安全地检查并添加缺失的列
      await _safeAddColumn(db, _tableMetadata, _colCollectionPosterUrl, 'TEXT');
      await _safeAddColumn(
        db,
        _tableMetadata,
        _colCollectionBackdropUrl,
        'TEXT',
      );

      logger.i('VideoDatabaseService: 版本15->16 升级完成（修复系列海报字段）');
    }

    // 从版本16升级到版本17
    if (oldVersion < 17) {
      // 添加扩展视频信息字段
      await _safeAddColumn(db, _tableMetadata, _colVideoSource, 'TEXT');
      await _safeAddColumn(db, _tableMetadata, _colVideoCodec, 'TEXT');
      await _safeAddColumn(db, _tableMetadata, _colHdrFormat, 'TEXT');
      await _safeAddColumn(db, _tableMetadata, _colAudioFormat, 'TEXT');
      await _safeAddColumn(db, _tableMetadata, _colIs3D, 'INTEGER DEFAULT 0');
      await _safeAddColumn(
        db,
        _tableMetadata,
        _colIsRemux,
        'INTEGER DEFAULT 0',
      );
      // 添加扩展评分字段
      await _safeAddColumn(db, _tableMetadata, _colImdbId, 'TEXT');
      await _safeAddColumn(db, _tableMetadata, _colImdbRating, 'REAL');
      await _safeAddColumn(db, _tableMetadata, _colMetacriticRating, 'INTEGER');
      await _safeAddColumn(db, _tableMetadata, _colTraktRating, 'REAL');
      // 添加内容分级字段
      await _safeAddColumn(db, _tableMetadata, _colCertification, 'TEXT');

      // 迁移现有数据：从文件名解析扩展视频信息
      await _migrateExtendedVideoInfo(db);

      logger.i('VideoDatabaseService: 版本16->17 升级完成（添加扩展视频信息、评分和内容分级字段）');
    }

    // 从版本17升级到版本18
    if (oldVersion < 18) {
      // 添加目录修改时间字段（用于增量同步）
      await _safeAddColumn(
        db,
        _tableScanProgress,
        _scanColDirModifiedTime,
        'INTEGER',
      );

      logger.i('VideoDatabaseService: 版本17->18 升级完成（添加增量同步支持）');
    }

    // 从版本18升级到版本19
    if (oldVersion < 19) {
      // 添加媒体服务器支持字段
      await _safeAddColumn(db, _tableMetadata, _colServerType, 'TEXT');
      await _safeAddColumn(db, _tableMetadata, _colServerItemId, 'TEXT');
      await _safeAddColumn(db, _tableMetadata, _colScrapeSource, 'TEXT');
      await _safeAddColumn(
        db,
        _tableMetadata,
        _colIsWatched,
        'INTEGER DEFAULT 0',
      );
      await _safeAddColumn(
        db,
        _tableMetadata,
        _colPlaybackPositionTicks,
        'INTEGER',
      );
      await _safeAddColumn(db, _tableMetadata, _colLastPlayedAt, 'INTEGER');

      // 创建索引
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_server_item ON $_tableMetadata($_colSourceId, $_colServerItemId)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_watched ON $_tableMetadata($_colIsWatched)',
      );

      // 回填 scrape_source：有 tmdb_id 的记录设为 'tmdb'
      await db.execute('''
        UPDATE $_tableMetadata
        SET $_colScrapeSource = 'tmdb'
        WHERE $_colTmdbId IS NOT NULL AND $_colScrapeSource IS NULL
      ''');

      // 创建媒体服务器缓存表
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $_tableMediaServerCache (
          id TEXT PRIMARY KEY,
          source_id TEXT NOT NULL,
          item_id TEXT NOT NULL,
          parent_id TEXT,
          item_type TEXT NOT NULL,
          name TEXT NOT NULL,
          metadata_json TEXT NOT NULL,
          image_urls_json TEXT,
          last_updated INTEGER NOT NULL,
          UNIQUE(source_id, item_id)
        )
      ''');
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_msc_source_parent
        ON $_tableMediaServerCache(source_id, parent_id)
      ''');
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_msc_type
        ON $_tableMediaServerCache(source_id, item_type)
      ''');

      // 创建播放同步队列表
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $_tablePlaybackSyncQueue (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          source_id TEXT NOT NULL,
          item_id TEXT NOT NULL,
          position_ticks INTEGER NOT NULL,
          is_watched INTEGER NOT NULL DEFAULT 0,
          event_type TEXT NOT NULL,
          sync_status TEXT NOT NULL DEFAULT 'pending',
          retry_count INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          synced_at INTEGER,
          error_message TEXT
        )
      ''');
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_psq_status
        ON $_tablePlaybackSyncQueue(sync_status, created_at)
      ''');
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_psq_source
        ON $_tablePlaybackSyncQueue(source_id, item_id)
      ''');

      logger.i('VideoDatabaseService: 版本18->19 升级完成（添加媒体服务器支持）');
    }

    // 从版本19升级到版本20
    if (oldVersion < 20) {
      // 添加 NFO 本地背景图字段（独立于 backdrop_url，存本地 fanart 路径）
      await _safeAddColumn(db, _tableMetadata, _colLocalBackdropUrl, 'TEXT');

      logger.i('VideoDatabaseService: 版本19->20 升级完成（添加本地背景图字段）');
    }
  }

  /// 安全地添加列（如果列不存在则添加，存在则忽略）
  Future<void> _safeAddColumn(
    Database db,
    String table,
    String column,
    String type,
  ) async {
    // 检查列是否已存在
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final columnExists = columns.any((col) => col['name'] == column);

    if (!columnExists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
      logger.d('VideoDatabaseService: 添加列 $table.$column');
    }
  }

  /// 插入或更新元数据
  Future<void> upsert(VideoMetadata metadata) async {
    if (!_initialized) await init();

    await _db!.insert(
      _tableMetadata,
      _toRow(metadata),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 批量插入或更新
  ///
  /// 使用事务保护确保原子性：要么全部成功，要么全部回滚
  /// 这样即使应用在写入过程中被终止，数据库也不会处于不一致状态
  Future<void> upsertBatch(List<VideoMetadata> metadataList) async {
    if (!_initialized) await init();
    if (metadataList.isEmpty) return;

    // 在事务中执行批量操作，确保原子性
    await _db!.transaction((txn) async {
      final batch = txn.batch();
      for (final metadata in metadataList) {
        batch.insert(
          _tableMetadata,
          _toRow(metadata),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
    logger.d('VideoDatabaseService: 批量插入 ${metadataList.length} 条');
  }

  /// 根据 sourceId 和 filePath 获取元数据
  Future<VideoMetadata?> get(String sourceId, String filePath) async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tableMetadata,
      where: '$_colSourceId = ? AND $_colFilePath = ?',
      whereArgs: [sourceId, filePath],
      limit: 1,
    );

    if (results.isEmpty) return null;
    return _fromRow(results.first);
  }

  /// 批量获取元数据
  Future<Map<String, VideoMetadata>> getBatch(
    List<({String sourceId, String filePath})> keys,
  ) async {
    if (!_initialized) await init();
    if (keys.isEmpty) return {};

    final result = <String, VideoMetadata>{};

    // 分批查询，避免 SQL 语句过长
    const batchSize = 100;
    for (var i = 0; i < keys.length; i += batchSize) {
      final batchKeys = keys.skip(i).take(batchSize).toList();

      // 构建 OR 条件
      final conditions = batchKeys
          .map((_) => '($_colSourceId = ? AND $_colFilePath = ?)')
          .join(' OR ');
      final args = batchKeys.expand((k) => [k.sourceId, k.filePath]).toList();

      final results = await _db!.query(
        _tableMetadata,
        where: conditions,
        whereArgs: args,
      );

      for (final row in results) {
        final metadata = _fromRow(row);
        result[metadata.uniqueKey] = metadata;
      }
    }

    return result;
  }

  /// 根据 TMDB ID 获取所有匹配的元数据（使用索引）
  Future<List<VideoMetadata>> getByTmdbId(int tmdbId) async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tableMetadata,
      where: '$_colTmdbId = ?',
      whereArgs: [tmdbId],
    );

    return results.map(_fromRow).toList();
  }

  /// 获取同一电影的所有版本（不同清晰度）
  ///
  /// 按分辨率降序排序（4K > 1080p > 720p），相同分辨率按文件大小降序
  /// 用于电影详情页显示版本选择
  ///
  /// [metadata] 电影元数据（用于匹配同一电影）
  /// 返回所有匹配的版本列表，如果只有一个版本则返回单元素列表
  Future<List<VideoMetadata>> getMovieVersions(VideoMetadata metadata) async {
    if (!_initialized) await init();

    // 分辨率优先级排序
    const resolutionOrder =
        '''
      CASE
        WHEN $_colResolution IN ('4K', '2160p', 'UHD') THEN 4
        WHEN $_colResolution = '1080p' THEN 3
        WHEN $_colResolution = '720p' THEN 2
        WHEN $_colResolution = '480p' THEN 1
        ELSE 0
      END
    ''';

    List<Map<String, Object?>> results;

    if (metadata.tmdbId != null) {
      // 如果有 TMDB ID，按 TMDB ID 匹配
      results = await _db!.rawQuery(
        '''
        SELECT * FROM $_tableMetadata
        WHERE $_colCategory = 0 AND $_colTmdbId = ?
        ORDER BY $resolutionOrder DESC,
                 COALESCE($_colFileSize, 0) DESC
      ''',
        [metadata.tmdbId],
      );
    } else if (metadata.title != null) {
      // 如果没有 TMDB ID，按标题+年份匹配
      results = await _db!.rawQuery(
        '''
        SELECT * FROM $_tableMetadata
        WHERE $_colCategory = 0
          AND $_colTmdbId IS NULL
          AND LOWER(COALESCE($_colTitle, '')) = LOWER(?)
          AND COALESCE($_colYear, 0) = ?
        ORDER BY $resolutionOrder DESC,
                 COALESCE($_colFileSize, 0) DESC
      ''',
        [metadata.title, metadata.year ?? 0],
      );
    } else {
      // 没有匹配条件，返回单个元素
      return [metadata];
    }

    if (results.isEmpty) {
      return [metadata];
    }

    return results.map(_fromRow).toList();
  }

  /// 获取同一电影的版本数量
  ///
  /// 用于在列表页面显示版本标记
  Future<int> getMovieVersionCount(VideoMetadata metadata) async {
    if (!_initialized) await init();

    int? count;

    if (metadata.tmdbId != null) {
      count = Sqflite.firstIntValue(
        await _db!.rawQuery(
          '''
        SELECT COUNT(*) FROM $_tableMetadata
        WHERE $_colCategory = 0 AND $_colTmdbId = ?
      ''',
          [metadata.tmdbId],
        ),
      );
    } else if (metadata.title != null) {
      count = Sqflite.firstIntValue(
        await _db!.rawQuery(
          '''
        SELECT COUNT(*) FROM $_tableMetadata
        WHERE $_colCategory = 0
          AND $_colTmdbId IS NULL
          AND LOWER(COALESCE($_colTitle, '')) = LOWER(?)
          AND COALESCE($_colYear, 0) = ?
      ''',
          [metadata.title, metadata.year ?? 0],
        ),
      );
    }

    return count ?? 1;
  }

  /// 根据 TMDB ID 获取剧集映射（使用索引）
  Future<Map<int, Map<int, VideoMetadata>>> getEpisodesByTmdbId(
    int tmdbId,
  ) async {
    if (!_initialized) await init();

    logger.d(
      'VideoDatabaseService: getEpisodesByTmdbId called, tmdbId=$tmdbId',
    );

    final results = await _db!.query(
      _tableMetadata,
      where:
          '$_colTmdbId = ? AND $_colSeasonNumber IS NOT NULL AND $_colEpisodeNumber IS NOT NULL',
      whereArgs: [tmdbId],
      orderBy: '$_colSeasonNumber, $_colEpisodeNumber',
    );

    logger.d(
      'VideoDatabaseService: query returned ${results.length} rows for tmdbId=$tmdbId',
    );

    final episodeMap = <int, Map<int, VideoMetadata>>{};
    for (final row in results) {
      final metadata = _fromRow(row);
      if (metadata.seasonNumber != null && metadata.episodeNumber != null) {
        episodeMap.putIfAbsent(
          metadata.seasonNumber!,
          () => {},
        )[metadata.episodeNumber!] = metadata;
      }
    }

    logger.d(
      'VideoDatabaseService: returning episodeMap with ${episodeMap.length} seasons for tmdbId=$tmdbId',
    );
    return episodeMap;
  }

  /// 根据 showDirectory 获取剧集映射（用于无 TMDB 的剧集）
  ///
  /// 返回 `Map<seasonNumber, Map<episodeNumber, VideoMetadata>>`
  /// - 对于有 seasonNumber/episodeNumber 的剧集，使用原有值
  /// - 对于没有 seasonNumber/episodeNumber 的剧集，默认分配到第 1 季，按文件名排序生成集号
  Future<Map<int, Map<int, VideoMetadata>>> getEpisodesByShowDirectory(
    String showDirectory,
  ) async {
    if (!_initialized) await init();

    logger.d(
      'VideoDatabaseService: getEpisodesByShowDirectory called, showDirectory=$showDirectory',
    );

    // 获取该目录下所有视频（包括有和没有季集号的）
    final results = await _db!.query(
      _tableMetadata,
      where: '$_colShowDirectory = ?',
      whereArgs: [showDirectory],
      orderBy: '$_colSeasonNumber, $_colEpisodeNumber, $_colFileName',
    );

    logger.d('VideoDatabaseService: query returned ${results.length} rows');

    final episodeMap = <int, Map<int, VideoMetadata>>{};

    // 先处理有季集号的剧集
    final withSeasonEpisode = <VideoMetadata>[];
    final withoutSeasonEpisode = <VideoMetadata>[];

    for (final row in results) {
      final metadata = _fromRow(row);
      if (metadata.seasonNumber != null && metadata.episodeNumber != null) {
        withSeasonEpisode.add(metadata);
      } else {
        withoutSeasonEpisode.add(metadata);
      }
    }

    logger.d(
      'VideoDatabaseService: withSeasonEpisode=${withSeasonEpisode.length}, withoutSeasonEpisode=${withoutSeasonEpisode.length}',
    );

    // 添加有季集号的剧集
    for (final metadata in withSeasonEpisode) {
      episodeMap.putIfAbsent(
        metadata.seasonNumber!,
        () => {},
      )[metadata.episodeNumber!] = metadata;
    }

    // 如果有无季集号的剧集，将它们添加到第 1 季（或找一个不冲突的季号）
    if (withoutSeasonEpisode.isNotEmpty) {
      // 按文件名排序
      withoutSeasonEpisode.sort((a, b) => a.fileName.compareTo(b.fileName));

      // 找一个不会冲突的起始集号
      final season1Episodes = episodeMap[1] ?? {};
      var nextEpisodeNumber = season1Episodes.isEmpty
          ? 1
          : (season1Episodes.keys.reduce((a, b) => a > b ? a : b) + 1);

      // 如果第 1 季已经有剧集，为没有季集号的剧集创建一个特殊季（-1 表示"未分类"）
      // 但为了 UI 兼容性，还是使用正数季号
      final targetSeason = season1Episodes.isEmpty ? 1 : 1;

      for (final metadata in withoutSeasonEpisode) {
        // 创建一个带有默认季集号的副本
        final updatedMetadata = metadata.copyWith(
          seasonNumber: targetSeason,
          episodeNumber: nextEpisodeNumber,
        );
        episodeMap.putIfAbsent(targetSeason, () => {})[nextEpisodeNumber] =
            updatedMetadata;
        nextEpisodeNumber++;
      }
    }

    logger.d(
      'VideoDatabaseService: returning episodeMap with ${episodeMap.length} seasons',
    );
    return episodeMap;
  }

  /// 获取所有 TMDB ID 集合（使用索引）
  Future<Set<int>> getAllTmdbIds() async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tableMetadata,
      columns: [_colTmdbId],
      where: '$_colTmdbId IS NOT NULL',
      distinct: true,
    );

    return results.map((r) => r[_colTmdbId]! as int).toSet();
  }

  /// 根据 TMDB ID 获取第一个匹配的元数据
  Future<VideoMetadata?> getFirstByTmdbId(int tmdbId) async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tableMetadata,
      where: '$_colTmdbId = ?',
      whereArgs: [tmdbId],
      limit: 1,
    );

    if (results.isEmpty) return null;
    return _fromRow(results.first);
  }

  /// 根据分类获取元数据（分页）
  ///
  /// [enabledPaths] 启用的路径列表，如果提供则只返回这些路径下的视频
  /// 注意：对于电影类别，会自动去重（同一电影不同清晰度只返回最高清版本）
  Future<List<VideoMetadata>> getByCategory(
    MediaCategory category, {
    int limit = 50,
    int offset = 0,
    List<({String sourceId, String path})>? enabledPaths,
  }) async {
    if (!_initialized) await init();

    final pathFilter = _buildPathFilter(enabledPaths);
    final orderBy = '$_colYear DESC NULLS LAST, $_colTitle';

    // 电影类别使用去重逻辑（同一电影不同清晰度只返回最高清版本）
    if (category == MediaCategory.movie) {
      final sql = _buildMovieDeduplicationQuery(
        baseWhere: '$_colCategory = ${category.index}',
        pathFilter: pathFilter,
        orderBy: orderBy,
        limit: limit,
        offset: offset,
      );
      // 路径过滤参数需要出现两次（外层和子查询各一次）
      final args = [...pathFilter.args, ...pathFilter.args];
      final results = await _db!.rawQuery(sql, args);
      return results.map(_fromRow).toList();
    }

    // 其他类别使用普通查询
    var where = '$_colCategory = ?';
    final whereArgs = <Object>[category.index];

    if (pathFilter.andWhere.isNotEmpty) {
      where += pathFilter.andWhere;
      whereArgs.addAll(pathFilter.args);
    }

    final results = await _db!.query(
      _tableMetadata,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );

    return results.map(_fromRow).toList();
  }

  /// 根据年份获取元数据（分页）
  Future<List<VideoMetadata>> getByYear(
    int year, {
    int limit = 50,
    int offset = 0,
  }) async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tableMetadata,
      where: '$_colYear = ?',
      whereArgs: [year],
      // 同年份内按标题排序
      orderBy: _colTitle,
      limit: limit,
      offset: offset,
    );

    return results.map(_fromRow).toList();
  }

  /// 根据类型获取元数据（分页，使用 LIKE 搜索）
  Future<List<VideoMetadata>> getByGenre(
    String genre, {
    int limit = 50,
    int offset = 0,
  }) async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tableMetadata,
      where: '$_colGenres LIKE ?',
      whereArgs: ['%$genre%'],
      // 按上映年份降序排序
      orderBy: '$_colYear DESC NULLS LAST, $_colTitle',
      limit: limit,
      offset: offset,
    );

    return results.map(_fromRow).toList();
  }

  /// 获取最近添加的视频（分页）
  ///
  /// 按文件修改时间排序，越新的文件排在越前面
  /// 只返回电影和剧集，不包含未识别的视频
  ///
  /// [enabledPaths] 启用的路径列表，如果提供则只返回这些路径下的视频
  Future<List<VideoMetadata>> getRecentlyUpdated({
    int limit = 50,
    int offset = 0,
    List<({String sourceId, String path})>? enabledPaths,
  }) async {
    if (!_initialized) await init();

    final pathFilter = _buildPathFilter(enabledPaths);

    // 只获取电影(0)和剧集(1)，按文件修改时间降序排序
    const categoryFilter = '$_colCategory IN (0, 1)';
    final orderBy = '$_colFileModifiedTime DESC NULLS LAST';

    if (pathFilter.where.isEmpty) {
      final results = await _db!.rawQuery(
        'SELECT * FROM $_tableMetadata WHERE $categoryFilter ORDER BY $orderBy LIMIT ? OFFSET ?',
        [limit, offset],
      );
      return results.map(_fromRow).toList();
    }

    // 路径过滤已包含 WHERE，需要用 AND 连接
    final results = await _db!.rawQuery(
      'SELECT * FROM $_tableMetadata${pathFilter.where} AND $categoryFilter ORDER BY $orderBy LIMIT ? OFFSET ?',
      [...pathFilter.args, limit, offset],
    );

    return results.map(_fromRow).toList();
  }

  /// 获取高评分内容（分页）
  ///
  /// [enabledPaths] 启用的路径列表，如果提供则只返回这些路径下的视频
  /// [includeUnrated] 是否包含无评分的已刮削视频（用于每日推荐等场景，扩大推荐池）
  /// [randomSort] 是否使用随机排序（用于每日推荐，实现真正的随机推荐）
  /// [randomSeed] 随机种子（配合 randomSort 使用，相同种子返回相同顺序）
  Future<List<VideoMetadata>> getTopRated({
    double minRating = 0.0, // 降低默认阈值，确保有数据返回
    MediaCategory? category,
    int limit = 50,
    int offset = 0,
    List<({String sourceId, String path})>? enabledPaths,
    bool includeUnrated = false,
    bool randomSort = false,
    int? randomSeed,
  }) async {
    if (!_initialized) await init();

    final pathFilter = _buildPathFilter(enabledPaths);

    String where;
    final whereArgs = <Object>[];

    if (includeUnrated) {
      // 包含所有已刮削的视频（有海报的优先，无评分的排在后面）
      where = '$_colScrapeStatus = ?';
      whereArgs.add(ScrapeStatus.completed.index);
    } else {
      // 只筛选有评分的视频（rating > 0），不设最低分数门槛
      where = '$_colRating > ?';
      whereArgs.add(minRating);
    }

    if (category != null) {
      where += ' AND $_colCategory = ?';
      whereArgs.add(category.index);
    }

    if (pathFilter.andWhere.isNotEmpty) {
      where += pathFilter.andWhere;
      whereArgs.addAll(pathFilter.args);
    }

    // 确定排序方式
    String orderByClause;
    if (randomSort) {
      // 使用随机排序：基于 randomSeed 生成伪随机但可重复的顺序
      // SQLite 的 RANDOM() 每次调用都不同，无法直接使用种子
      // 我们使用 (id * seed) % large_prime 来生成可重复的伪随机顺序
      if (randomSeed != null) {
        // 使用大质数和种子生成可重复的伪随机排序
        // 这样相同的 seed 会返回相同的顺序
        orderByClause = '(($_colId * $randomSeed) % 2147483647)';
      } else {
        // 无种子时使用 SQLite 的真随机
        orderByClause = 'RANDOM()';
      }
    } else {
      // 按评分降序，无评分的排在最后
      orderByClause = '$_colRating DESC NULLS LAST, $_colTitle';
    }

    final results = await _db!.query(
      _tableMetadata,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderByClause,
      limit: limit,
      offset: offset,
    );

    return results.map(_fromRow).toList();
  }

  /// 分页获取所有元数据
  Future<List<VideoMetadata>> getPage({
    int limit = 50,
    int offset = 0,
    String? orderBy,
    MediaCategory? category,
  }) async {
    if (!_initialized) await init();

    String? where;
    List<Object>? whereArgs;

    if (category != null) {
      where = '$_colCategory = ?';
      whereArgs = [category.index];
    }

    final results = await _db!.query(
      _tableMetadata,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy ?? '$_colRating DESC, $_colTitle',
      limit: limit,
      offset: offset,
    );

    return results.map(_fromRow).toList();
  }

  /// 搜索元数据
  Future<List<VideoMetadata>> search(
    String query, {
    int limit = 50,
    int offset = 0,
  }) async {
    if (!_initialized) await init();
    if (query.isEmpty) return [];

    final searchPattern = '%$query%';
    final results = await _db!.query(
      _tableMetadata,
      where:
          '$_colTitle LIKE ? OR $_colOriginalTitle LIKE ? OR $_colFileName LIKE ?',
      whereArgs: [searchPattern, searchPattern, searchPattern],
      orderBy: '$_colRating DESC',
      limit: limit,
      offset: offset,
    );

    return results.map(_fromRow).toList();
  }

  /// 快速获取所有视频（Infuse 风格的即时加载）
  ///
  /// 这是最快的加载方式，用于首页初始化：
  /// - 单次简单查询，无复杂 JOIN 或分组
  /// - 按文件修改时间倒序，最新内容优先
  /// - 返回所有必要字段，供 UI 立即展示
  ///
  /// 适用场景：
  /// - 应用启动时的首次加载
  /// - 需要即时响应的场景（<50ms）
  ///
  /// [enabledPaths] 启用的路径列表，如果提供则只返回这些路径下的视频
  /// [limit] 返回数量限制，0 表示不限制
  Future<List<VideoMetadata>> getAllVideosQuick({
    List<({String sourceId, String path})>? enabledPaths,
    int limit = 0,
  }) async {
    if (!_initialized) await init();

    final pathFilter = _buildPathFilter(enabledPaths);

    String sql;
    List<Object> args;

    if (pathFilter.where.isEmpty) {
      sql = 'SELECT * FROM $_tableMetadata ORDER BY $_colFileModifiedTime DESC';
      args = [];
    } else {
      sql =
          'SELECT * FROM $_tableMetadata${pathFilter.where} ORDER BY $_colFileModifiedTime DESC';
      args = pathFilter.args;
    }

    if (limit > 0) {
      sql += ' LIMIT ?';
      args.add(limit);
    }

    final results = await _db!.rawQuery(sql, args);
    return results.map(_fromRow).toList();
  }

  /// 批量获取视频元数据（用于增量更新）
  ///
  /// 根据 uniqueKey 列表批量获取视频，避免多次数据库查询
  /// [keys] uniqueKey 列表，格式为 "sourceId_filePath"（与 VideoMetadata.uniqueKey 一致）
  Future<Map<String, VideoMetadata>> getByKeys(List<String> keys) async {
    if (!_initialized) await init();
    if (keys.isEmpty) return {};

    final result = <String, VideoMetadata>{};

    // SQLite 的 IN 子句有参数限制（通常是 999），分批查询
    const batchSize = 500;
    for (var i = 0; i < keys.length; i += batchSize) {
      final batch = keys.skip(i).take(batchSize).toList();
      final placeholders = List.filled(batch.length, '?').join(', ');

      // uniqueKey = sourceId || '_' || filePath（与 VideoMetadata.uniqueKey 一致）
      final sql =
          '''
        SELECT * FROM $_tableMetadata
        WHERE ($_colSourceId || '_' || $_colFilePath) IN ($placeholders)
      ''';

      final rows = await _db!.rawQuery(sql, batch);
      for (final row in rows) {
        final metadata = _fromRow(row);
        result[metadata.uniqueKey] = metadata;
      }
    }

    return result;
  }

  /// 获取统计信息
  ///
  /// [enabledPaths] 启用的路径列表，如果提供则只统计这些路径下的视频
  Future<Map<String, dynamic>> getStats({
    List<({String sourceId, String path})>? enabledPaths,
  }) async {
    if (!_initialized) await init();

    final pathFilter = _buildPathFilter(enabledPaths);

    final totalCount = Sqflite.firstIntValue(
      await _db!.rawQuery(
        'SELECT COUNT(*) FROM $_tableMetadata${pathFilter.where}',
        pathFilter.args,
      ),
    );

    // 电影使用去重计数（同一电影不同清晰度只计数一次）
    final movieBaseWhere = '$_colCategory = 0${pathFilter.andWhere}';
    final movieCountSql = _buildMovieDeduplicationCountQuery(
      baseWhere: movieBaseWhere,
    );
    // 参数需要出现两次（外层和子查询各一次）
    final movieCountArgs = [...pathFilter.args, ...pathFilter.args];
    final movieCount = Sqflite.firstIntValue(
      await _db!.rawQuery(movieCountSql, movieCountArgs),
    );

    final tvShowCount = Sqflite.firstIntValue(
      await _db!.rawQuery(
        'SELECT COUNT(*) FROM $_tableMetadata WHERE $_colCategory = 1${pathFilter.andWhere}',
        pathFilter.args,
      ),
    );

    // 其他视频（未识别为电影或剧集，category = 2 即 MediaCategory.unknown）
    final othersCount = Sqflite.firstIntValue(
      await _db!.rawQuery(
        'SELECT COUNT(*) FROM $_tableMetadata WHERE $_colCategory = 2${pathFilter.andWhere}',
        pathFilter.args,
      ),
    );

    final withMetadataCount = Sqflite.firstIntValue(
      await _db!.rawQuery(
        'SELECT COUNT(*) FROM $_tableMetadata WHERE $_colTmdbId IS NOT NULL${pathFilter.andWhere}',
        pathFilter.args,
      ),
    );

    return {
      'total': totalCount ?? 0,
      'movies': movieCount ?? 0,
      'tvShows': tvShowCount ?? 0,
      'others': othersCount ?? 0,
      'withMetadata': withMetadataCount ?? 0,
    };
  }

  /// 构建路径过滤条件
  ({String where, String andWhere, List<Object> args}) _buildPathFilter(
    List<({String sourceId, String path})>? enabledPaths,
  ) {
    if (enabledPaths == null || enabledPaths.isEmpty) {
      return (where: '', andWhere: '', args: []);
    }

    // 构建 (source_id = ? AND file_path LIKE ?) OR ... 条件
    final conditions = enabledPaths
        .map((_) => '($_colSourceId = ? AND $_colFilePath LIKE ?)')
        .join(' OR ');
    final args = enabledPaths
        .expand((p) => [p.sourceId, '${p.path}%'])
        .toList();

    return (
      where: ' WHERE ($conditions)',
      andWhere: ' AND ($conditions)',
      args: args,
    );
  }

  /// 构建电影去重子查询
  ///
  /// 对于同一部电影的多个版本（不同清晰度），只返回最高清晰度版本
  /// 分组依据：TMDB ID（如果存在）或 标题+年份
  /// 排序优先级：分辨率（4K > 1080p > 720p）> 文件大小 > 评分
  ///
  /// [baseWhere] 基础过滤条件，如 'category = 0'
  /// [pathFilter] 路径过滤条件
  /// [orderBy] 最终结果排序
  String _buildMovieDeduplicationQuery({
    required String baseWhere,
    required ({String where, String andWhere, List<Object> args}) pathFilter,
    required String orderBy,
    required int limit,
    required int offset,
  }) {
    // 分辨率优先级排序：数字越大优先级越高
    // 4K/2160p = 4, 1080p = 3, 720p = 2, 480p = 1, 其他 = 0
    const resolutionOrder =
        '''
      CASE
        WHEN $_colResolution IN ('4K', '2160p', 'UHD') THEN 4
        WHEN $_colResolution = '1080p' THEN 3
        WHEN $_colResolution = '720p' THEN 2
        WHEN $_colResolution = '480p' THEN 1
        ELSE 0
      END
    ''';

    return '''
      SELECT * FROM $_tableMetadata m1
      WHERE $baseWhere${pathFilter.andWhere}
        AND m1.rowid = (
          SELECT m2.rowid FROM $_tableMetadata m2
          WHERE $baseWhere${pathFilter.andWhere}
            AND (
              (m1.$_colTmdbId IS NOT NULL AND m2.$_colTmdbId = m1.$_colTmdbId)
              OR (m1.$_colTmdbId IS NULL AND m2.$_colTmdbId IS NULL
                  AND LOWER(COALESCE(m2.$_colTitle, '')) = LOWER(COALESCE(m1.$_colTitle, ''))
                  AND COALESCE(m2.$_colYear, 0) = COALESCE(m1.$_colYear, 0))
            )
          ORDER BY $resolutionOrder DESC,
                   COALESCE(m2.$_colFileSize, 0) DESC,
                   m2.$_colRating DESC NULLS LAST
          LIMIT 1
        )
      ORDER BY $orderBy
      LIMIT $limit OFFSET $offset
    ''';
  }

  /// 构建电影去重查询（带筛选条件，用于 getFiltered）
  ///
  /// 与 _buildMovieDeduplicationQuery 类似，但使用简单的 where 字符串而非 pathFilter
  String _buildMovieDeduplicationQueryWithFilters({
    required String baseWhere,
    required String orderBy,
    required int limit,
    required int offset,
  }) {
    // 分辨率优先级排序：数字越大优先级越高
    // 4K/2160p = 4, 1080p = 3, 720p = 2, 480p = 1, 其他 = 0
    const resolutionOrder =
        '''
      CASE
        WHEN $_colResolution IN ('4K', '2160p', 'UHD') THEN 4
        WHEN $_colResolution = '1080p' THEN 3
        WHEN $_colResolution = '720p' THEN 2
        WHEN $_colResolution = '480p' THEN 1
        ELSE 0
      END
    ''';

    return '''
      SELECT * FROM $_tableMetadata m1
      WHERE $baseWhere
        AND m1.rowid = (
          SELECT m2.rowid FROM $_tableMetadata m2
          WHERE $baseWhere
            AND (
              (m1.$_colTmdbId IS NOT NULL AND m2.$_colTmdbId = m1.$_colTmdbId)
              OR (m1.$_colTmdbId IS NULL AND m2.$_colTmdbId IS NULL
                  AND LOWER(COALESCE(m2.$_colTitle, '')) = LOWER(COALESCE(m1.$_colTitle, ''))
                  AND COALESCE(m2.$_colYear, 0) = COALESCE(m1.$_colYear, 0))
            )
          ORDER BY $resolutionOrder DESC,
                   COALESCE(m2.$_colFileSize, 0) DESC,
                   m2.$_colRating DESC NULLS LAST
          LIMIT 1
        )
      ORDER BY $orderBy
      LIMIT $limit OFFSET $offset
    ''';
  }

  /// 构建电影去重计数查询
  String _buildMovieDeduplicationCountQuery({required String baseWhere}) {
    // 分辨率优先级排序
    const resolutionOrder =
        '''
      CASE
        WHEN $_colResolution IN ('4K', '2160p', 'UHD') THEN 4
        WHEN $_colResolution = '1080p' THEN 3
        WHEN $_colResolution = '720p' THEN 2
        WHEN $_colResolution = '480p' THEN 1
        ELSE 0
      END
    ''';

    return '''
      SELECT COUNT(*) FROM $_tableMetadata m1
      WHERE $baseWhere
        AND m1.rowid = (
          SELECT m2.rowid FROM $_tableMetadata m2
          WHERE $baseWhere
            AND (
              (m1.$_colTmdbId IS NOT NULL AND m2.$_colTmdbId = m1.$_colTmdbId)
              OR (m1.$_colTmdbId IS NULL AND m2.$_colTmdbId IS NULL
                  AND LOWER(COALESCE(m2.$_colTitle, '')) = LOWER(COALESCE(m1.$_colTitle, ''))
                  AND COALESCE(m2.$_colYear, 0) = COALESCE(m1.$_colYear, 0))
            )
          ORDER BY $resolutionOrder DESC,
                   COALESCE(m2.$_colFileSize, 0) DESC,
                   m2.$_colRating DESC NULLS LAST
          LIMIT 1
        )
    ''';
  }

  /// 获取统计信息文本（用于空状态显示）
  ///
  /// 返回格式如: "123 个影视 · 2.5 MB 缓存"
  Future<String> getStatsInfo() async {
    if (!_initialized) await init();

    final totalCount =
        Sqflite.firstIntValue(
          await _db!.rawQuery('SELECT COUNT(*) FROM $_tableMetadata'),
        ) ??
        0;

    if (totalCount == 0) {
      return appL10n.videoCacheEmpty;
    }

    // 获取数据库文件大小（稳定值，不包括 WAL 波动）
    final dbSize = await _getDatabaseSize();
    final sizeText = _formatSize(dbSize);

    return appL10n.videoCacheStatsSummary(totalCount, sizeText);
  }

  /// 获取数据库文件大小（字节）
  ///
  /// 只返回主数据库文件大小，不包括 WAL 和 SHM 临时文件
  /// 这样可以避免因 WAL checkpoint 机制导致的大小波动
  Future<int> _getDatabaseSize() async {
    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      final dbPath = join(documentsDir.path, 'video_metadata.db');
      final dbFile = File(dbPath);
      if (await dbFile.exists()) {
        // 只返回主数据库大小，WAL/SHM 是临时文件，大小会波动
        // WAL 文件会在 checkpoint 时合并到主数据库
        return await dbFile.length();
      }
    } on Exception catch (e) {
      logger.w('VideoDatabaseService: 获取数据库大小失败', e);
    }
    return 0;
  }

  /// 执行 WAL checkpoint，将 WAL 日志合并到主数据库
  ///
  /// 建议在以下时机调用：
  /// - 应用进入后台时
  /// - 大量写操作完成后（如扫描完成）
  Future<void> checkpoint() async {
    if (!_initialized) return;
    try {
      await _db!.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      logger.d('VideoDatabaseService: WAL checkpoint 完成');
    } on Exception catch (e) {
      logger.w('VideoDatabaseService: WAL checkpoint 失败', e);
    }
  }

  /// 格式化文件大小
  String _formatSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
  }

  /// 获取第一个视频的路径信息（用于诊断路径不匹配问题）
  Future<({String sourceId, String filePath})?> getFirstVideoPath() async {
    if (!_initialized) await init();

    final result = await _db!.rawQuery(
      'SELECT $_colSourceId, $_colFilePath FROM $_tableMetadata LIMIT 1',
    );

    if (result.isEmpty) return null;

    final row = result.first;
    final sourceId = row[_colSourceId];
    final filePath = row[_colFilePath];

    if (sourceId is! String || filePath is! String) return null;

    return (sourceId: sourceId, filePath: filePath);
  }

  /// 获取总数量
  Future<int> getCount({MediaCategory? category}) async {
    if (!_initialized) await init();

    var sql = 'SELECT COUNT(*) FROM $_tableMetadata';
    List<Object>? args;

    if (category != null) {
      sql += ' WHERE $_colCategory = ?';
      args = [category.index];
    }

    return Sqflite.firstIntValue(await _db!.rawQuery(sql, args)) ?? 0;
  }

  /// 获取剧集分组数量
  ///
  /// 直接查询聚合表 tv_show_groups，确保与列表显示数量一致
  ///
  /// [enabledPaths] 启用的路径列表，如果提供则只统计代表视频命中这些路径的分组
  Future<int> getTvShowGroupCount({
    List<({String sourceId, String path})>? enabledPaths,
  }) async {
    if (!_initialized) await init();

    // 未指定路径过滤时，直接查询聚合表的数量，确保与列表一致
    if (enabledPaths == null || enabledPaths.isEmpty) {
      final count =
          Sqflite.firstIntValue(
            await _db!.rawQuery('''
        SELECT COUNT(*) FROM $_tableTvShowGroups
        WHERE $_tvgColRepresentativeRowid IS NOT NULL
        '''),
          ) ??
          0;

      return count;
    }

    // 指定了启用路径：通过代表视频的 rowid 关联到 video_metadata，
    // 仅统计其 (source_id, file_path) 命中启用路径的分组。
    // INNER JOIN 天然排除了 representative_rowid 为 NULL 的分组。
    final pathFilter = _buildPathFilter(enabledPaths);
    final count =
        Sqflite.firstIntValue(
          await _db!.rawQuery('''
      SELECT COUNT(*) FROM $_tableTvShowGroups g
      INNER JOIN $_tableMetadata vm
        ON g.$_tvgColRepresentativeRowid = vm.rowid${pathFilter.andWhere}
      ''', pathFilter.args),
        ) ??
        0;

    return count;
  }

  /// 批量获取剧集分组的季集统计（用于懒加载）
  ///
  /// 返回每个分组的季数和集数，无需加载完整剧集列表
  /// 键为分组键（tmdb_XXX 或 title_xxx），值为 (seasonCount, episodeCount)
  Future<Map<String, ({int seasonCount, int episodeCount})>>
  getTvShowGroupStats({
    List<int>? tmdbIds,
    List<String>? showDirectories,
    List<String>? titles,
  }) async {
    if (!_initialized) await init();

    final result = <String, ({int seasonCount, int episodeCount})>{};

    // 有 TMDB ID 的分组统计
    if (tmdbIds != null && tmdbIds.isNotEmpty) {
      final placeholders = List.filled(tmdbIds.length, '?').join(', ');
      final statsResult = await _db!.rawQuery('''
        SELECT
          $_colTmdbId,
          COUNT(DISTINCT CASE WHEN $_colSeasonNumber > 0 THEN $_colSeasonNumber ELSE NULL END) as season_count,
          COUNT(*) as episode_count
        FROM $_tableMetadata
        WHERE $_colTmdbId IN ($placeholders) AND $_colCategory = 1
        GROUP BY $_colTmdbId
      ''', tmdbIds);

      for (final row in statsResult) {
        final tmdbId = row[_colTmdbId] as int?;
        if (tmdbId != null) {
          final seasonCount = (row['season_count'] as int?) ?? 1;
          final episodeCount = (row['episode_count'] as int?) ?? 1;
          result['tmdb_$tmdbId'] = (
            seasonCount: seasonCount,
            episodeCount: episodeCount,
          );
        }
      }
    }

    // 按 showDirectory 分组的统计（优先于 title）
    if (showDirectories != null && showDirectories.isNotEmpty) {
      final placeholders = List.filled(showDirectories.length, '?').join(', ');
      final statsResult = await _db!.rawQuery('''
        SELECT
          $_colShowDirectory,
          COUNT(DISTINCT CASE WHEN $_colSeasonNumber > 0 THEN $_colSeasonNumber ELSE NULL END) as season_count,
          COUNT(*) as episode_count
        FROM $_tableMetadata
        WHERE $_colShowDirectory IN ($placeholders) AND $_colCategory = 1 AND $_colTmdbId IS NULL
        GROUP BY $_colShowDirectory
      ''', showDirectories);

      for (final row in statsResult) {
        final showDirectory = row[_colShowDirectory] as String?;
        if (showDirectory != null) {
          final seasonCount = (row['season_count'] as int?) ?? 1;
          final episodeCount = (row['episode_count'] as int?) ?? 1;
          result['dir_$showDirectory'] = (
            seasonCount: seasonCount,
            episodeCount: episodeCount,
          );
        }
      }
    }

    // 按标题分组的统计（仅用于无 tmdbId 且无 showDirectory 的剧集）
    if (titles != null && titles.isNotEmpty) {
      final placeholders = List.filled(titles.length, '?').join(', ');
      final statsResult = await _db!.rawQuery('''
        SELECT
          LOWER($_colTitle) as lower_title,
          COUNT(DISTINCT CASE WHEN $_colSeasonNumber > 0 THEN $_colSeasonNumber ELSE NULL END) as season_count,
          COUNT(*) as episode_count
        FROM $_tableMetadata
        WHERE LOWER($_colTitle) IN ($placeholders) AND $_colCategory = 1 AND $_colTmdbId IS NULL AND $_colShowDirectory IS NULL
        GROUP BY LOWER($_colTitle)
      ''', titles.map((t) => t.toLowerCase()).toList());

      for (final row in statsResult) {
        final lowerTitle = row['lower_title'] as String?;
        if (lowerTitle != null) {
          final seasonCount = (row['season_count'] as int?) ?? 1;
          final episodeCount = (row['episode_count'] as int?) ?? 1;
          result['title_$lowerTitle'] = (
            seasonCount: seasonCount,
            episodeCount: episodeCount,
          );
        }
      }
    }

    return result;
  }

  /// 获取剧集分组的代表性元数据（用于分页显示剧集列表）
  ///
  /// 返回每个剧集分组的一条代表性记录（按 tmdbId 或 title 分组，取评分最高的）
  /// [enabledPaths] 启用的路径列表
  ///
  /// 性能优化说明：
  /// 使用两阶段查询策略，避免 O(n²) 的关联子查询：
  /// - 阶段1：使用 GROUP BY 获取唯一分组，复杂度 O(n)
  /// - 阶段2：使用 IN 子句获取完整记录，复杂度 O(m)（m为分组数）
  Future<List<VideoMetadata>> getTvShowGroupRepresentatives({
    int limit = 50,
    int offset = 0,
    List<({String sourceId, String path})>? enabledPaths,
  }) async {
    if (!_initialized) await init();

    final pathFilter = _buildPathFilter(enabledPaths);

    // 阶段1：使用 GROUP BY 获取每个分组的代表性 rowid
    // 按 tmdbId 分组（有值的），按 LOWER(title) 分组（tmdbId 为空的）
    // 使用 MAX(rating) 和 MIN(season_number) 等条件选择最佳代表
    //
    // 策略：分两部分查询，合并结果
    // 1a: 有 tmdb_id 的剧集 - 按 tmdb_id 分组
    // 1b: 无 tmdb_id 的剧集 - 按 title 分组

    final representativeRowIds = <int>[];

    // 1a: 有 tmdb_id 的剧集 - 使用 JOIN + GROUP BY 策略

    // 更高效的方法：使用简单分组，每个 tmdb_id 取 MAX(rating) 对应的记录
    // SQLite 的 `GROUP BY` 会返回任意一行，我们用子查询确保取评分最高的
    // 注意：使用 AS rid 显式别名，因为 SQLite 返回的列名可能是 't1.rowid' 而不是 'rowid'
    final withTmdbSqlOptimized =
        '''
      SELECT t1.rowid AS rid
      FROM $_tableMetadata t1
      INNER JOIN (
        SELECT $_colTmdbId, MAX($_colRating) as max_rating
        FROM $_tableMetadata
        WHERE $_colCategory = 1 AND $_colTmdbId IS NOT NULL${pathFilter.andWhere}
        GROUP BY $_colTmdbId
      ) t2 ON t1.$_colTmdbId = t2.$_colTmdbId AND (t1.$_colRating = t2.max_rating OR (t1.$_colRating IS NULL AND t2.max_rating IS NULL))
      WHERE t1.$_colCategory = 1 AND t1.$_colTmdbId IS NOT NULL${pathFilter.andWhere}
      GROUP BY t1.$_colTmdbId
    ''';

    final withTmdbResult = await _db!.rawQuery(withTmdbSqlOptimized, [
      ...pathFilter.args,
      ...pathFilter.args,
    ]);
    representativeRowIds.addAll(
      withTmdbResult.map((r) => r['rid'] as int?).whereType<int>(),
    );

    // 1b: 无 tmdb_id 的剧集 - 优先按 show_directory 分组，其次按 LOWER(title) 分组
    // 使用 COALESCE 确保有 show_directory 的优先使用目录分组，没有的回退到标题分组
    // 同样使用 AS rid 显式别名
    final withoutTmdbSql =
        '''
      SELECT t1.rowid AS rid
      FROM $_tableMetadata t1
      INNER JOIN (
        SELECT COALESCE($_colShowDirectory, LOWER($_colTitle)) as group_key, MAX($_colRating) as max_rating
        FROM $_tableMetadata
        WHERE $_colCategory = 1 AND $_colTmdbId IS NULL AND ($_colShowDirectory IS NOT NULL OR $_colTitle IS NOT NULL)${pathFilter.andWhere}
        GROUP BY COALESCE($_colShowDirectory, LOWER($_colTitle))
      ) t2 ON COALESCE(t1.$_colShowDirectory, LOWER(t1.$_colTitle)) = t2.group_key AND (t1.$_colRating = t2.max_rating OR (t1.$_colRating IS NULL AND t2.max_rating IS NULL))
      WHERE t1.$_colCategory = 1 AND t1.$_colTmdbId IS NULL AND (t1.$_colShowDirectory IS NOT NULL OR t1.$_colTitle IS NOT NULL)${pathFilter.andWhere}
      GROUP BY COALESCE(t1.$_colShowDirectory, LOWER(t1.$_colTitle))
    ''';

    final withoutTmdbResult = await _db!.rawQuery(withoutTmdbSql, [
      ...pathFilter.args,
      ...pathFilter.args,
    ]);
    representativeRowIds.addAll(
      withoutTmdbResult.map((r) => r['rid'] as int?).whereType<int>(),
    );

    if (representativeRowIds.isEmpty) {
      return [];
    }

    // 阶段2：根据 rowid 列表获取完整记录，应用排序和分页
    // 注意：需要在获取完整数据后再排序
    // 按上映年份降序排序（最近上映的排在前面）
    final placeholders = List.filled(
      representativeRowIds.length,
      '?',
    ).join(', ');
    final fullDataSql =
        '''
      SELECT * FROM $_tableMetadata
      WHERE rowid IN ($placeholders)
      ORDER BY $_colYear DESC NULLS LAST, $_colTitle
      LIMIT ? OFFSET ?
    ''';

    final results = await _db!.rawQuery(fullDataSql, [
      ...representativeRowIds,
      limit,
      offset,
    ]);
    return results.map(_fromRow).toList();
  }

  /// 获取未观看的视频（去重：电影按 TMDB ID/标题+年份，剧集按剧目录/TMDB ID）
  ///
  /// 排除已在观看历史中的视频（通过传入已观看路径列表）
  /// [watchedPaths] 已观看的视频路径列表（从 VideoHistoryService.getAllWatchedPaths 获取）
  /// [enabledPaths] 启用的路径列表
  Future<List<VideoMetadata>> getUnwatched({
    required Set<String> watchedPaths,
    int limit = 50,
    int offset = 0,
    List<({String sourceId, String path})>? enabledPaths,
  }) async {
    if (!_initialized) await init();

    final pathFilter = _buildPathFilter(enabledPaths);

    // 分辨率优先级排序（用于电影去重）
    const resolutionOrder =
        '''
      CASE
        WHEN $_colResolution IN ('4K', '2160p', 'UHD') THEN 4
        WHEN $_colResolution = '1080p' THEN 3
        WHEN $_colResolution = '720p' THEN 2
        WHEN $_colResolution = '480p' THEN 1
        ELSE 0
      END
    ''';

    // 查询去重后的电影
    final movieSql =
        '''
      SELECT * FROM $_tableMetadata m1
      WHERE $_colCategory = 0${pathFilter.andWhere}
        AND m1.rowid = (
          SELECT m2.rowid FROM $_tableMetadata m2
          WHERE m2.$_colCategory = 0${pathFilter.andWhere}
            AND (
              (m1.$_colTmdbId IS NOT NULL AND m2.$_colTmdbId = m1.$_colTmdbId)
              OR (m1.$_colTmdbId IS NULL AND m2.$_colTmdbId IS NULL
                  AND LOWER(COALESCE(m2.$_colTitle, '')) = LOWER(COALESCE(m1.$_colTitle, ''))
                  AND COALESCE(m2.$_colYear, 0) = COALESCE(m1.$_colYear, 0))
            )
          ORDER BY $resolutionOrder DESC,
                   COALESCE(m2.$_colFileSize, 0) DESC,
                   m2.$_colRating DESC NULLS LAST
          LIMIT 1
        )
      ORDER BY $_colFileModifiedTime DESC NULLS LAST
    ''';

    // 查询去重后的剧集（每部剧只返回一条记录）
    final tvShowSql =
        '''
      SELECT * FROM $_tableMetadata m1
      WHERE $_colCategory = 1${pathFilter.andWhere}
        AND m1.rowid = (
          SELECT m2.rowid FROM $_tableMetadata m2
          WHERE m2.$_colCategory = 1${pathFilter.andWhere}
            AND (
              (m1.$_colTmdbId IS NOT NULL AND m2.$_colTmdbId = m1.$_colTmdbId)
              OR (m1.$_colTmdbId IS NULL AND m2.$_colTmdbId IS NULL
                  AND m1.$_colShowDirectory IS NOT NULL AND m2.$_colShowDirectory = m1.$_colShowDirectory)
              OR (m1.$_colTmdbId IS NULL AND m2.$_colTmdbId IS NULL
                  AND m1.$_colShowDirectory IS NULL AND m2.$_colShowDirectory IS NULL
                  AND LOWER(COALESCE(m2.$_colTitle, '')) = LOWER(COALESCE(m1.$_colTitle, '')))
            )
          ORDER BY m2.$_colRating DESC NULLS LAST,
                   m2.$_colSeasonNumber ASC NULLS LAST,
                   m2.$_colEpisodeNumber ASC NULLS LAST
          LIMIT 1
        )
      ORDER BY $_colFileModifiedTime DESC NULLS LAST
    ''';

    final movieArgs = [...pathFilter.args, ...pathFilter.args];
    final tvShowArgs = [...pathFilter.args, ...pathFilter.args];

    // 并行查询电影和剧集
    final results = await Future.wait([
      _db!.rawQuery(movieSql, movieArgs),
      _db!.rawQuery(tvShowSql, tvShowArgs),
    ]);

    final movies = results[0].map(_fromRow).toList();
    final tvShows = results[1].map(_fromRow).toList();

    // 合并并按文件修改时间排序
    final allVideos = [...movies, ...tvShows]
      ..sort((a, b) {
        final aTime = a.fileModifiedTime ?? DateTime(1970);
        final bTime = b.fileModifiedTime ?? DateTime(1970);
        return bTime.compareTo(aTime);
      });

    // 如果没有观看历史，直接返回
    if (watchedPaths.isEmpty) {
      return allVideos.skip(offset).take(limit).toList();
    }

    // 过滤掉已观看的视频
    // 对于剧集，检查是否有任何一集被观看过（通过 TMDB ID 或 showDirectory 匹配）
    final unwatched = <VideoMetadata>[];
    for (final video in allVideos) {
      // 先收满 offset+limit 条，再按 offset 分页返回
      if (unwatched.length >= offset + limit) break;

      if (video.category == MediaCategory.tvShow) {
        // 对于剧集，检查是否整部剧都没看过
        // 需要检查所有同剧的集数是否都没被观看
        final isWatched = await _isTvShowWatched(
          video,
          watchedPaths,
          pathFilter,
        );
        if (!isWatched) {
          unwatched.add(video);
        }
      } else {
        // 对于电影，检查所有版本是否都没被观看
        final isWatched = await _isMovieWatched(
          video,
          watchedPaths,
          pathFilter,
        );
        if (!isWatched) {
          unwatched.add(video);
        }
      }
    }

    return unwatched.skip(offset).take(limit).toList();
  }

  /// 检查电影是否已观看（检查所有版本）
  Future<bool> _isMovieWatched(
    VideoMetadata movie,
    Set<String> watchedPaths,
    ({String where, String andWhere, List<Object> args}) pathFilter,
  ) async {
    // 先检查当前版本
    if (watchedPaths.contains(movie.filePath)) {
      return true;
    }

    // 获取同一电影的所有版本路径
    List<Map<String, Object?>> results;
    if (movie.tmdbId != null) {
      results = await _db!.rawQuery(
        '''
        SELECT $_colFilePath FROM $_tableMetadata
        WHERE $_colCategory = 0 AND $_colTmdbId = ?${pathFilter.andWhere}
      ''',
        [movie.tmdbId, ...pathFilter.args],
      );
    } else if (movie.title != null) {
      results = await _db!.rawQuery(
        '''
        SELECT $_colFilePath FROM $_tableMetadata
        WHERE $_colCategory = 0
          AND $_colTmdbId IS NULL
          AND LOWER(COALESCE($_colTitle, '')) = LOWER(?)
          AND COALESCE($_colYear, 0) = ?${pathFilter.andWhere}
      ''',
        [movie.title, movie.year ?? 0, ...pathFilter.args],
      );
    } else {
      return watchedPaths.contains(movie.filePath);
    }

    // 检查任意版本是否被观看
    for (final row in results) {
      final path = row[_colFilePath] as String?;
      if (path != null && watchedPaths.contains(path)) {
        return true;
      }
    }

    return false;
  }

  /// 检查剧集是否已观看（检查任意一集）
  Future<bool> _isTvShowWatched(
    VideoMetadata tvShow,
    Set<String> watchedPaths,
    ({String where, String andWhere, List<Object> args}) pathFilter,
  ) async {
    // 先检查当前集
    if (watchedPaths.contains(tvShow.filePath)) {
      return true;
    }

    // 获取同一剧集的所有集数路径
    List<Map<String, Object?>> results;
    if (tvShow.tmdbId != null) {
      results = await _db!.rawQuery(
        '''
        SELECT $_colFilePath FROM $_tableMetadata
        WHERE $_colCategory = 1 AND $_colTmdbId = ?${pathFilter.andWhere}
      ''',
        [tvShow.tmdbId, ...pathFilter.args],
      );
    } else if (tvShow.showDirectory != null) {
      results = await _db!.rawQuery(
        '''
        SELECT $_colFilePath FROM $_tableMetadata
        WHERE $_colCategory = 1
          AND $_colTmdbId IS NULL
          AND $_colShowDirectory = ?${pathFilter.andWhere}
      ''',
        [tvShow.showDirectory, ...pathFilter.args],
      );
    } else if (tvShow.title != null) {
      results = await _db!.rawQuery(
        '''
        SELECT $_colFilePath FROM $_tableMetadata
        WHERE $_colCategory = 1
          AND $_colTmdbId IS NULL
          AND $_colShowDirectory IS NULL
          AND LOWER(COALESCE($_colTitle, '')) = LOWER(?)${pathFilter.andWhere}
      ''',
        [tvShow.title, ...pathFilter.args],
      );
    } else {
      return watchedPaths.contains(tvShow.filePath);
    }

    // 检查任意一集是否被观看
    for (final row in results) {
      final path = row[_colFilePath] as String?;
      if (path != null && watchedPaths.contains(path)) {
        return true;
      }
    }

    return false;
  }

  /// 获取所有存在的影片类型（去重）
  ///
  /// 返回数据库中所有视频的类型标签列表
  Future<List<String>> getAllGenres() async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tableMetadata,
      columns: [_colGenres],
      where: '$_colGenres IS NOT NULL AND $_colGenres != ?',
      whereArgs: [''],
      distinct: true,
    );

    // 收集所有类型并去重
    // 注意：genres 使用 ' / ' 分隔（来自 TMDB 和 NFO），支持多种分隔符格式
    final genreSet = <String>{};
    for (final row in results) {
      final genresStr = row[_colGenres] as String?;
      if (genresStr != null && genresStr.isNotEmpty) {
        final genres = genresStr
            .split(RegExp(r'\s*[/,]\s*'))
            .map((g) => g.trim());
        genreSet.addAll(genres.where((g) => g.isNotEmpty));
      }
    }

    // 按出现频率排序（可选：先统计每个类型的数量）
    final sortedGenres = genreSet.toList()..sort();
    return sortedGenres;
  }

  /// 获取所有存在的国家/地区（去重）
  ///
  /// 返回数据库中所有视频的国家/地区列表
  Future<List<String>> getAllCountries() async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tableMetadata,
      columns: [_colCountries],
      where: '$_colCountries IS NOT NULL AND $_colCountries != ?',
      whereArgs: [''],
      distinct: true,
    );

    // 收集所有国家并去重
    final countrySet = <String>{};
    for (final row in results) {
      final countriesStr = row[_colCountries] as String?;
      if (countriesStr != null && countriesStr.isNotEmpty) {
        final countries = countriesStr.split(',').map((c) => c.trim());
        countrySet.addAll(countries.where((c) => c.isNotEmpty));
      }
    }

    // 按字母排序
    final sortedCountries = countrySet.toList()..sort();
    return sortedCountries;
  }

  /// 获取可用的国家/地区列表（按分类筛选）
  ///
  /// [category] 可选的媒体分类过滤
  /// [preferChinese] 是否优先返回中文名称，默认 true
  /// 返回合并后的国家/地区列表（自动去除多语言重复项）
  Future<List<String>> getAvailableCountries({
    MediaCategory? category,
    bool preferChinese = true,
  }) async {
    if (!_initialized) await init();

    var sql =
        '''
      SELECT DISTINCT $_colCountries FROM $_tableMetadata
      WHERE $_colCountries IS NOT NULL AND $_colCountries != ''
    ''';
    final args = <Object>[];

    if (category != null) {
      sql += ' AND $_colCategory = ?';
      args.add(category.index);
    }

    final results = await _db!.rawQuery(sql, args);

    // 解析所有国家
    final rawCountries = <String>[];
    for (final row in results) {
      final countries = row[_colCountries] as String?;
      if (countries != null && countries.isNotEmpty) {
        rawCountries.addAll(countries.split(',').map((c) => c.trim()));
      }
    }

    // 使用映射工具合并多语言变体
    return GenreCountryMapping.mergeCountries(
      rawCountries,
      preferChinese: preferChinese,
    );
  }

  /// 根据国家/地区获取电影（去重，同一电影不同清晰度只返回最高清版本）
  Future<List<VideoMetadata>> getMoviesByCountry(
    String country, {
    int limit = 30,
    int offset = 0,
    VideoSortOption sortOption = VideoSortOption.ratingDesc,
    List<({String sourceId, String path})>? enabledPaths,
  }) async {
    if (!_initialized) await init();

    final pathFilter = _buildPathFilter(enabledPaths);
    final orderBy = _buildOrderBy(sortOption);

    // 分辨率优先级排序
    const resolutionOrder =
        '''
      CASE
        WHEN $_colResolution IN ('4K', '2160p', 'UHD') THEN 4
        WHEN $_colResolution = '1080p' THEN 3
        WHEN $_colResolution = '720p' THEN 2
        WHEN $_colResolution = '480p' THEN 1
        ELSE 0
      END
    ''';

    // 使用子查询去重：同一电影不同清晰度只返回最高清版本
    final sql =
        '''
      SELECT * FROM $_tableMetadata m1
      WHERE $_colCategory = 0 AND $_colCountries LIKE ?${pathFilter.andWhere}
        AND m1.rowid = (
          SELECT m2.rowid FROM $_tableMetadata m2
          WHERE m2.$_colCategory = 0 AND m2.$_colCountries LIKE ?${pathFilter.andWhere}
            AND (
              (m1.$_colTmdbId IS NOT NULL AND m2.$_colTmdbId = m1.$_colTmdbId)
              OR (m1.$_colTmdbId IS NULL AND m2.$_colTmdbId IS NULL
                  AND LOWER(COALESCE(m2.$_colTitle, '')) = LOWER(COALESCE(m1.$_colTitle, ''))
                  AND COALESCE(m2.$_colYear, 0) = COALESCE(m1.$_colYear, 0))
            )
          ORDER BY $resolutionOrder DESC,
                   COALESCE(m2.$_colFileSize, 0) DESC,
                   m2.$_colRating DESC NULLS LAST
          LIMIT 1
        )
      ORDER BY $orderBy
      LIMIT $limit OFFSET $offset
    ''';

    final args = [
      '%$country%',
      ...pathFilter.args,
      '%$country%',
      ...pathFilter.args,
    ];
    final results = await _db!.rawQuery(sql, args);

    return results.map(_fromRow).toList();
  }

  /// 根据国家/地区获取电视剧（每部剧只返回一条记录）
  Future<List<VideoMetadata>> getTvShowsByCountry(
    String country, {
    int limit = 30,
    int offset = 0,
    VideoSortOption sortOption = VideoSortOption.ratingDesc,
    List<({String sourceId, String path})>? enabledPaths,
  }) async {
    if (!_initialized) await init();

    final pathFilter = _buildPathFilter(enabledPaths);
    final orderBy = _buildOrderBy(sortOption);

    // 使用子查询获取每个剧集的代表性记录
    final sql =
        '''
      SELECT * FROM $_tableMetadata m1
      WHERE $_colCategory = 1 AND $_colCountries LIKE ?${pathFilter.andWhere}
        AND m1.rowid = (
          SELECT m2.rowid FROM $_tableMetadata m2
          WHERE m2.$_colCategory = 1 AND m2.$_colCountries LIKE ?${pathFilter.andWhere}
            AND (
              (m1.$_colTmdbId IS NOT NULL AND m2.$_colTmdbId = m1.$_colTmdbId)
              OR (m1.$_colTmdbId IS NULL AND m2.$_colTmdbId IS NULL AND LOWER(m2.$_colTitle) = LOWER(m1.$_colTitle))
            )
          ORDER BY m2.$_colRating DESC NULLS LAST, m2.$_colSeasonNumber ASC, m2.$_colEpisodeNumber ASC
          LIMIT 1
        )
      ORDER BY $orderBy
      LIMIT $limit OFFSET $offset
    ''';

    final args = [
      '%$country%',
      ...pathFilter.args,
      '%$country%',
      ...pathFilter.args,
    ];
    final results = await _db!.rawQuery(sql, args);

    return results.map(_fromRow).toList();
  }

  /// 根据国家/地区获取所有视频（电影+剧集）
  Future<List<VideoMetadata>> getByCountryCombined(
    String country, {
    int limit = 30,
    List<({String sourceId, String path})>? enabledPaths,
  }) async {
    final futures = await Future.wait([
      getMoviesByCountry(
        country,
        limit: limit ~/ 2 + 5,
        enabledPaths: enabledPaths,
      ),
      getTvShowsByCountry(
        country,
        limit: limit ~/ 2 + 5,
        enabledPaths: enabledPaths,
      ),
    ]);

    final movies = futures[0];
    final tvShows = futures[1];

    // 合并并按上映年份降序排序
    final combined = [...movies, ...tvShows]
      ..sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));

    return combined.take(limit).toList();
  }

  /// 根据类型获取电影（去重，同一电影不同清晰度只返回最高清版本）
  ///
  /// [genre] 类型名称（如：动作、科幻、喜剧）
  /// [enabledPaths] 启用的路径列表
  Future<List<VideoMetadata>> getMoviesByGenre(
    String genre, {
    int limit = 30,
    int offset = 0,
    VideoSortOption sortOption = VideoSortOption.ratingDesc,
    List<({String sourceId, String path})>? enabledPaths,
  }) async {
    if (!_initialized) await init();

    final pathFilter = _buildPathFilter(enabledPaths);
    final orderBy = _buildOrderBy(sortOption);

    // 分辨率优先级排序
    const resolutionOrder =
        '''
      CASE
        WHEN $_colResolution IN ('4K', '2160p', 'UHD') THEN 4
        WHEN $_colResolution = '1080p' THEN 3
        WHEN $_colResolution = '720p' THEN 2
        WHEN $_colResolution = '480p' THEN 1
        ELSE 0
      END
    ''';

    // 使用子查询去重：同一电影不同清晰度只返回最高清版本
    final sql =
        '''
      SELECT * FROM $_tableMetadata m1
      WHERE $_colCategory = 0 AND $_colGenres LIKE ?${pathFilter.andWhere}
        AND m1.rowid = (
          SELECT m2.rowid FROM $_tableMetadata m2
          WHERE m2.$_colCategory = 0 AND m2.$_colGenres LIKE ?${pathFilter.andWhere}
            AND (
              (m1.$_colTmdbId IS NOT NULL AND m2.$_colTmdbId = m1.$_colTmdbId)
              OR (m1.$_colTmdbId IS NULL AND m2.$_colTmdbId IS NULL
                  AND LOWER(COALESCE(m2.$_colTitle, '')) = LOWER(COALESCE(m1.$_colTitle, ''))
                  AND COALESCE(m2.$_colYear, 0) = COALESCE(m1.$_colYear, 0))
            )
          ORDER BY $resolutionOrder DESC,
                   COALESCE(m2.$_colFileSize, 0) DESC,
                   m2.$_colRating DESC NULLS LAST
          LIMIT 1
        )
      ORDER BY $orderBy
      LIMIT $limit OFFSET $offset
    ''';

    final args = [
      '%$genre%',
      ...pathFilter.args,
      '%$genre%',
      ...pathFilter.args,
    ];
    final results = await _db!.rawQuery(sql, args);

    return results.map(_fromRow).toList();
  }

  /// 根据类型获取剧集（去重，每个剧只返回一条代表记录）
  ///
  /// [genre] 类型名称
  /// [enabledPaths] 启用的路径列表
  Future<List<VideoMetadata>> getTvShowsByGenre(
    String genre, {
    int limit = 30,
    int offset = 0,
    VideoSortOption sortOption = VideoSortOption.ratingDesc,
    List<({String sourceId, String path})>? enabledPaths,
  }) async {
    if (!_initialized) await init();

    final pathFilter = _buildPathFilter(enabledPaths);
    final orderBy = _buildOrderBy(sortOption);

    // 使用子查询获取每个剧集的代表性记录
    // 注意：子查询也需要应用路径过滤，否则可能返回其他源的记录导致 rowid 不匹配
    final sql =
        '''
      SELECT * FROM $_tableMetadata m1
      WHERE $_colCategory = 1 AND $_colGenres LIKE ?${pathFilter.andWhere}
        AND m1.rowid = (
          SELECT m2.rowid FROM $_tableMetadata m2
          WHERE m2.$_colCategory = 1 AND m2.$_colGenres LIKE ?${pathFilter.andWhere}
            AND (
              (m1.$_colTmdbId IS NOT NULL AND m2.$_colTmdbId = m1.$_colTmdbId)
              OR (m1.$_colTmdbId IS NULL AND m2.$_colTmdbId IS NULL AND LOWER(m2.$_colTitle) = LOWER(m1.$_colTitle))
            )
          ORDER BY m2.$_colRating DESC NULLS LAST, m2.$_colSeasonNumber ASC, m2.$_colEpisodeNumber ASC
          LIMIT 1
        )
      ORDER BY $orderBy
      LIMIT ? OFFSET ?
    ''';

    final results = await _db!.rawQuery(sql, [
      '%$genre%',
      ...pathFilter.args,
      '%$genre%',
      ...pathFilter.args,
      limit,
      offset,
    ]);
    return results.map(_fromRow).toList();
  }

  /// 根据类型获取所有视频（电影+剧集）
  ///
  /// 用于类型分类显示，合并电影和剧集
  Future<List<VideoMetadata>> getByGenreCombined(
    String genre, {
    int limit = 30,
    List<({String sourceId, String path})>? enabledPaths,
  }) async {
    // 获取电影
    final movies = await getMoviesByGenre(
      genre,
      limit: limit ~/ 2,
      enabledPaths: enabledPaths,
    );

    // 获取剧集
    final tvShows = await getTvShowsByGenre(
      genre,
      limit: limit ~/ 2,
      enabledPaths: enabledPaths,
    );

    // 合并并按上映年份降序排序
    final combined = [...movies, ...tvShows]
      ..sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));

    return combined.take(limit).toList();
  }

  /// 删除元数据
  Future<void> delete(String sourceId, String filePath) async {
    if (!_initialized) await init();

    await _db!.delete(
      _tableMetadata,
      where: '$_colSourceId = ? AND $_colFilePath = ?',
      whereArgs: [sourceId, filePath],
    );
  }

  /// 根据 sourceId 删除所有
  Future<int> deleteBySourceId(String sourceId) async {
    if (!_initialized) await init();

    return _db!.delete(
      _tableMetadata,
      where: '$_colSourceId = ?',
      whereArgs: [sourceId],
    );
  }

  /// 根据 sourceId 和路径前缀删除（用于移除文件夹）
  Future<int> deleteByPath(String sourceId, String pathPrefix) async {
    if (!_initialized) await init();

    // 使用 LIKE 匹配路径前缀
    final count = await _db!.delete(
      _tableMetadata,
      where: '$_colSourceId = ? AND $_colFilePath LIKE ?',
      whereArgs: [sourceId, '$pathPrefix%'],
    );

    logger.i(
      'VideoDatabaseService: 已删除 $count 个视频 (sourceId: $sourceId, path: $pathPrefix)',
    );
    return count;
  }

  /// 清空所有数据（包括所有聚合表）
  Future<void> clearAll() async {
    if (!_initialized) await init();

    // 清空所有视频相关表
    await _db!.delete(_tableMetadata);
    await _db!.delete(_tableTvShowGroups);
    await _db!.delete(_tableMovieCollectionGroups);
    await _db!.delete(_tableScanProgress);

    logger.i('VideoDatabaseService: 已清空所有数据（包括聚合表和扫描进度）');
  }

  /// 安全关闭数据库
  ///
  /// 在应用终止前调用，确保所有写入操作完成
  /// WAL 模式下会执行 checkpoint，确保数据安全持久化
  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      // WAL checkpoint - 确保所有写入都持久化到主数据库文件
      try {
        await _db!.execute('PRAGMA wal_checkpoint(TRUNCATE)');
        logger.d('VideoDatabaseService: WAL checkpoint 完成');
      } on Exception catch (e) {
        logger.w('VideoDatabaseService: WAL checkpoint 失败', e);
      }
      await _db!.close();
      _db = null;
      _initialized = false;
      logger.i('VideoDatabaseService: 数据库已安全关闭');
    }
  }

  /// 转换为数据库行
  Map<String, dynamic> _toRow(VideoMetadata m) => {
    _colSourceId: m.sourceId,
    _colFilePath: m.filePath,
    _colFileName: m.fileName,
    _colCategory: m.category.index,
    _colScrapeStatus: m.scrapeStatus.index,
    _colTmdbId: m.tmdbId,
    _colTitle: m.title,
    _colOriginalTitle: m.originalTitle,
    _colYear: m.year,
    _colOverview: m.overview,
    _colPosterUrl: m.posterUrl,
    _colBackdropUrl: m.backdropUrl,
    _colRating: m.rating,
    _colRuntime: m.runtime,
    _colGenres: m.genres,
    _colCountries: m.countries,
    _colDirector: m.director,
    _colCast: m.cast,
    _colSeasonNumber: m.seasonNumber,
    _colEpisodeNumber: m.episodeNumber,
    _colEpisodeTitle: m.episodeTitle,
    _colLastUpdated: m.lastUpdated?.millisecondsSinceEpoch,
    _colThumbnailUrl: m.thumbnailUrl,
    _colGeneratedThumbnailUrl: m.generatedThumbnailUrl,
    _colLocalPosterUrl: m.localPosterUrl,
    _colLocalBackdropUrl: m.localBackdropUrl,
    _colFileSize: m.fileSize,
    _colFileModifiedTime: m.fileModifiedTime?.millisecondsSinceEpoch,
    _colCollectionId: m.collectionId,
    _colCollectionName: m.collectionName,
    _colCollectionPosterUrl: m.collectionPosterUrl,
    _colCollectionBackdropUrl: m.collectionBackdropUrl,
    _colShowDirectory: m.showDirectory,
    _colMovieDirectory: m.movieDirectory,
    _colResolution: m.resolution,
    _colLocalizedTitles: m.localizedTitles != null
        ? _encodeLocalizedMap(m.localizedTitles!)
        : null,
    _colLocalizedOverviews: m.localizedOverviews != null
        ? _encodeLocalizedMap(m.localizedOverviews!)
        : null,
    // 扩展视频信息
    _colVideoSource: m.videoSource,
    _colVideoCodec: m.videoCodec,
    _colHdrFormat: m.hdrFormat,
    _colAudioFormat: m.audioFormat,
    _colIs3D: m.is3D ? 1 : 0,
    _colIsRemux: m.isRemux ? 1 : 0,
    // 扩展评分
    _colImdbId: m.imdbId,
    _colImdbRating: m.imdbRating,
    _colMetacriticRating: m.metacriticRating,
    _colTraktRating: m.traktRating,
    // 内容分级
    _colCertification: m.certification,
    // 媒体服务器相关
    _colServerType: m.serverType,
    _colServerItemId: m.serverItemId,
    _colScrapeSource: m.scrapeSource,
    _colIsWatched: m.isWatched ? 1 : 0,
    _colPlaybackPositionTicks: m.playbackPositionTicks,
    _colLastPlayedAt: m.lastPlayedAt?.millisecondsSinceEpoch,
  };

  /// 编码多语言 Map 为 JSON 字符串
  String _encodeLocalizedMap(Map<String, String> map) {
    // 简单的 JSON 编码（不依赖 dart:convert）
    final pairs = map.entries.map(
      (e) => '"${_escapeJson(e.key)}":"${_escapeJson(e.value)}"',
    );
    return '{${pairs.join(',')}}';
  }

  /// 转义 JSON 字符串中的特殊字符
  String _escapeJson(String s) => s
      .replaceAll(r'\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r')
      .replaceAll('\t', r'\t');

  /// 从数据库行转换
  VideoMetadata _fromRow(Map<String, dynamic> row) => VideoMetadata(
    sourceId: row[_colSourceId] as String,
    filePath: row[_colFilePath] as String,
    fileName: row[_colFileName] as String,
    category: row[_colCategory] != null
        ? MediaCategory.values[row[_colCategory] as int]
        : MediaCategory.unknown,
    scrapeStatus: row[_colScrapeStatus] != null
        ? ScrapeStatus.values[row[_colScrapeStatus] as int]
        : ScrapeStatus.pending,
    tmdbId: row[_colTmdbId] as int?,
    title: row[_colTitle] as String?,
    originalTitle: row[_colOriginalTitle] as String?,
    year: row[_colYear] as int?,
    overview: row[_colOverview] as String?,
    posterUrl: row[_colPosterUrl] as String?,
    backdropUrl: row[_colBackdropUrl] as String?,
    rating: row[_colRating] as double?,
    runtime: row[_colRuntime] as int?,
    genres: row[_colGenres] as String?,
    countries: row[_colCountries] as String?,
    director: row[_colDirector] as String?,
    cast: row[_colCast] as String?,
    seasonNumber: row[_colSeasonNumber] as int?,
    episodeNumber: row[_colEpisodeNumber] as int?,
    episodeTitle: row[_colEpisodeTitle] as String?,
    lastUpdated: row[_colLastUpdated] != null
        ? DateTime.fromMillisecondsSinceEpoch(row[_colLastUpdated] as int)
        : null,
    thumbnailUrl: row[_colThumbnailUrl] as String?,
    generatedThumbnailUrl: row[_colGeneratedThumbnailUrl] as String?,
    localPosterUrl: row[_colLocalPosterUrl] as String?,
    localBackdropUrl: row[_colLocalBackdropUrl] as String?,
    fileSize: row[_colFileSize] as int?,
    fileModifiedTime: row[_colFileModifiedTime] != null
        ? DateTime.fromMillisecondsSinceEpoch(row[_colFileModifiedTime] as int)
        : null,
    collectionId: row[_colCollectionId] as int?,
    collectionName: row[_colCollectionName] as String?,
    collectionPosterUrl: row[_colCollectionPosterUrl] as String?,
    collectionBackdropUrl: row[_colCollectionBackdropUrl] as String?,
    showDirectory: row[_colShowDirectory] as String?,
    movieDirectory: row[_colMovieDirectory] as String?,
    resolution: row[_colResolution] as String?,
    localizedTitles: _parseLocalizedJson(row[_colLocalizedTitles] as String?),
    localizedOverviews: _parseLocalizedJson(
      row[_colLocalizedOverviews] as String?,
    ),
    // 扩展视频信息
    videoSource: row[_colVideoSource] as String?,
    videoCodec: row[_colVideoCodec] as String?,
    hdrFormat: row[_colHdrFormat] as String?,
    audioFormat: row[_colAudioFormat] as String?,
    is3D: row[_colIs3D] == 1,
    isRemux: row[_colIsRemux] == 1,
    // 扩展评分
    imdbId: row[_colImdbId] as String?,
    imdbRating: (row[_colImdbRating] as num?)?.toDouble(),
    metacriticRating: row[_colMetacriticRating] as int?,
    traktRating: (row[_colTraktRating] as num?)?.toDouble(),
    // 内容分级
    certification: row[_colCertification] as String?,
    // 媒体服务器相关
    serverType: row[_colServerType] as String?,
    serverItemId: row[_colServerItemId] as String?,
    scrapeSource: row[_colScrapeSource] as String?,
    isWatched: row[_colIsWatched] == 1,
    playbackPositionTicks: row[_colPlaybackPositionTicks] as int?,
    lastPlayedAt: row[_colLastPlayedAt] != null
        ? DateTime.fromMillisecondsSinceEpoch(row[_colLastPlayedAt] as int)
        : null,
  );

  /// 解析 JSON 字符串为多语言 Map
  Map<String, String>? _parseLocalizedJson(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      // 简单的 JSON 解析
      final content = json.trim();
      if (!content.startsWith('{') || !content.endsWith('}')) return null;

      final inner = content.substring(1, content.length - 1).trim();
      if (inner.isEmpty) return null;

      final result = <String, String>{};

      // 匹配 "key":"value" 对
      final regex = RegExp(
        r'"([^"\\]*(?:\\.[^"\\]*)*)"\s*:\s*"([^"\\]*(?:\\.[^"\\]*)*)"',
      );
      for (final match in regex.allMatches(inner)) {
        final key = _unescapeJson(match.group(1)!);
        final value = _unescapeJson(match.group(2)!);
        result[key] = value;
      }

      return result.isNotEmpty ? result : null;
    } on Exception {
      return null;
    }
  }

  /// 反转义 JSON 字符串
  String _unescapeJson(String s) => s
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\r', '\r')
      .replaceAll(r'\t', '\t')
      .replaceAll(r'\"', '"')
      .replaceAll(r'\\', r'\');

  /// 获取刮削统计信息
  ///
  /// [sourceId] 可选，按源ID筛选
  /// [pathPrefix] 可选，按路径前缀筛选（需要同时提供 sourceId）
  Future<ScrapeStats> getScrapeStats({
    String? sourceId,
    String? pathPrefix,
  }) async {
    if (!_initialized) await init();

    // 构建路径过滤条件
    var whereClause = '';
    var andWhereClause = '';
    final args = <Object>[];

    if (sourceId != null && pathPrefix != null) {
      whereClause = ' WHERE $_colSourceId = ? AND $_colFilePath LIKE ?';
      andWhereClause = ' AND $_colSourceId = ? AND $_colFilePath LIKE ?';
      args.addAll([sourceId, '$pathPrefix%']);
    } else if (sourceId != null) {
      whereClause = ' WHERE $_colSourceId = ?';
      andWhereClause = ' AND $_colSourceId = ?';
      args.add(sourceId);
    }

    final total =
        Sqflite.firstIntValue(
          await _db!.rawQuery(
            'SELECT COUNT(*) FROM $_tableMetadata$whereClause',
            args,
          ),
        ) ??
        0;

    final pending =
        Sqflite.firstIntValue(
          await _db!.rawQuery(
            'SELECT COUNT(*) FROM $_tableMetadata WHERE $_colScrapeStatus = 0$andWhereClause',
            args,
          ),
        ) ??
        0;

    final scraping =
        Sqflite.firstIntValue(
          await _db!.rawQuery(
            'SELECT COUNT(*) FROM $_tableMetadata WHERE $_colScrapeStatus = 1$andWhereClause',
            args,
          ),
        ) ??
        0;

    final completed =
        Sqflite.firstIntValue(
          await _db!.rawQuery(
            'SELECT COUNT(*) FROM $_tableMetadata WHERE $_colScrapeStatus = 2$andWhereClause',
            args,
          ),
        ) ??
        0;

    final failed =
        Sqflite.firstIntValue(
          await _db!.rawQuery(
            'SELECT COUNT(*) FROM $_tableMetadata WHERE $_colScrapeStatus = 3$andWhereClause',
            args,
          ),
        ) ??
        0;

    final skipped =
        Sqflite.firstIntValue(
          await _db!.rawQuery(
            'SELECT COUNT(*) FROM $_tableMetadata WHERE $_colScrapeStatus = 4$andWhereClause',
            args,
          ),
        ) ??
        0;

    final movies =
        Sqflite.firstIntValue(
          await _db!.rawQuery(
            'SELECT COUNT(*) FROM $_tableMetadata WHERE $_colCategory = 0$andWhereClause',
            args,
          ),
        ) ??
        0;

    final tvShows =
        Sqflite.firstIntValue(
          await _db!.rawQuery(
            'SELECT COUNT(*) FROM $_tableMetadata WHERE $_colCategory = 1$andWhereClause',
            args,
          ),
        ) ??
        0;

    return ScrapeStats(
      total: total,
      pending: pending,
      scraping: scraping,
      completed: completed,
      failed: failed,
      skipped: skipped,
      movies: movies,
      tvShows: tvShows,
    );
  }

  /// 获取待刮削的视频列表（智能优先级排序）
  ///
  /// 优先级策略（通过 scrape_priority 字段和 SQL CASE 表达式实现）：
  /// 0. 已检测到 NFO 文件的视频 - 几乎瞬间完成
  /// 1. 文件名格式规范的视频（包含年份、剧集信息如 S01E01）- 最容易匹配 TMDB
  /// 2. 普通视频文件 - 需要解析文件名匹配 TMDB
  /// 3. 特殊字符较多的文件名 - 可能难以匹配，需要抽帧
  ///
  /// 这样可以让容易刮削的视频优先完成，用户能更快看到有元数据的内容
  Future<List<VideoMetadata>> getPendingScrape({int limit = 50}) async {
    if (!_initialized) await init();

    // 优先使用预设的 scrape_priority 字段（在扫描时设置）
    // 如果没有预设，使用 SQL CASE 表达式动态计算
    // 分数越小优先级越高
    final sql =
        '''
      SELECT *,
        CASE
          -- 优先级 0：已检测到 NFO 文件（扫描时标记）
          WHEN $_colHasNfo = 1 THEN 0

          -- 优先级 1：文件名包含年份（如 Movie.2023）或剧集信息（如 S01E01）
          -- 这类文件名格式规范，TMDB 匹配成功率高
          WHEN $_colFileName GLOB '*[12][09][0-9][0-9]*'
               OR $_colFileName GLOB '*[Ss][0-9][0-9][Ee][0-9][0-9]*'
               OR $_colFileName GLOB '*[0-9]x[0-9][0-9]*'
          THEN 1

          -- 优先级 2：普通文件名（没有太多特殊字符）
          WHEN LENGTH($_colFileName) - LENGTH(REPLACE(REPLACE(REPLACE($_colFileName, '[', ''), ']', ''), '.', '')) < 5
          THEN 2

          -- 优先级 3：其他文件（特殊字符较多，可能需要更复杂的解析）
          ELSE 3
        END AS priority
      FROM $_tableMetadata
      WHERE $_colScrapeStatus = ?
      ORDER BY priority ASC, $_colId ASC
      LIMIT ?
    ''';

    final results = await _db!.rawQuery(sql, [
      ScrapeStatus.pending.index,
      limit,
    ]);
    return results.map(_fromRow).toList();
  }

  /// 更新视频的 NFO 检测标志和刮削优先级
  Future<void> updateNfoFlag(
    String sourceId,
    String filePath, {
    required bool hasNfo,
  }) async {
    if (!_initialized) await init();

    await _db!.update(
      _tableMetadata,
      {
        _colHasNfo: hasNfo ? 1 : 0,
        _colScrapePriority: hasNfo ? 0 : 2, // 有 NFO 的优先级最高
      },
      where: '$_colSourceId = ? AND $_colFilePath = ?',
      whereArgs: [sourceId, filePath],
    );
  }

  /// 批量更新 NFO 检测标志
  Future<void> updateNfoFlagBatch(
    List<({String sourceId, String filePath, bool hasNfo})> items,
  ) async {
    if (!_initialized) await init();
    if (items.isEmpty) return;

    // 在事务中执行批量操作，确保原子性
    await _db!.transaction((txn) async {
      final batch = txn.batch();
      for (final item in items) {
        batch.update(
          _tableMetadata,
          {
            _colHasNfo: item.hasNfo ? 1 : 0,
            _colScrapePriority: item.hasNfo ? 0 : 2,
          },
          where: '$_colSourceId = ? AND $_colFilePath = ?',
          whereArgs: [item.sourceId, item.filePath],
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// 获取需要重试的视频列表
  ///
  /// 包括：
  /// - 刮削失败的 (failed)
  /// - 刮削完成但没有 TMDB 数据的（只有封面或连封面都没有）
  Future<List<VideoMetadata>> getRetryableVideos({int limit = 50}) async {
    if (!_initialized) await init();

    // 获取失败的和完成但无 TMDB ID 的视频
    final results = await _db!.query(
      _tableMetadata,
      where:
          '''
        $_colScrapeStatus = ?
        OR ($_colScrapeStatus = ? AND $_colTmdbId IS NULL)
      ''',
      whereArgs: [ScrapeStatus.failed.index, ScrapeStatus.completed.index],
      orderBy: _colId,
      limit: limit,
    );

    return results.map(_fromRow).toList();
  }

  /// 获取需要重试的视频数量
  ///
  /// [sourceId] 可选，按源ID筛选
  /// [pathPrefix] 可选，按路径前缀筛选（需要同时提供 sourceId）
  Future<int> getRetryableCount({String? sourceId, String? pathPrefix}) async {
    if (!_initialized) await init();

    // 构建路径过滤条件
    var pathFilter = '';
    final args = <Object>[
      ScrapeStatus.failed.index,
      ScrapeStatus.completed.index,
    ];

    if (sourceId != null && pathPrefix != null) {
      pathFilter = ' AND $_colSourceId = ? AND $_colFilePath LIKE ?';
      args.addAll([sourceId, '$pathPrefix%']);
    } else if (sourceId != null) {
      pathFilter = ' AND $_colSourceId = ?';
      args.add(sourceId);
    }

    final count = Sqflite.firstIntValue(
      await _db!.rawQuery('''
      SELECT COUNT(*) FROM $_tableMetadata
      WHERE ($_colScrapeStatus = ?
        OR ($_colScrapeStatus = ? AND $_colTmdbId IS NULL))$pathFilter
    ''', args),
    );

    return count ?? 0;
  }

  /// 重置失败和无TMDB数据的视频状态为待刮削
  Future<int> resetRetryableVideos() async {
    if (!_initialized) await init();

    final count = await _db!.rawUpdate(
      '''
      UPDATE $_tableMetadata
      SET $_colScrapeStatus = ?
      WHERE $_colScrapeStatus = ?
        OR ($_colScrapeStatus = ? AND $_colTmdbId IS NULL)
    ''',
      [
        ScrapeStatus.pending.index,
        ScrapeStatus.failed.index,
        ScrapeStatus.completed.index,
      ],
    );

    logger.i('VideoDatabaseService: 重置 $count 个视频为待刮削状态');
    return count;
  }

  /// 更新刮削状态
  Future<void> updateScrapeStatus(
    String sourceId,
    String filePath,
    ScrapeStatus status,
  ) async {
    if (!_initialized) await init();

    await _db!.update(
      _tableMetadata,
      {_colScrapeStatus: status.index},
      where: '$_colSourceId = ? AND $_colFilePath = ?',
      whereArgs: [sourceId, filePath],
    );
  }

  /// 批量更新刮削状态
  Future<void> updateScrapeStatusBatch(
    List<({String sourceId, String filePath})> items,
    ScrapeStatus status,
  ) async {
    if (!_initialized) await init();
    if (items.isEmpty) return;

    // 在事务中执行批量操作，确保原子性
    await _db!.transaction((txn) async {
      final batch = txn.batch();
      for (final item in items) {
        batch.update(
          _tableMetadata,
          {_colScrapeStatus: status.index},
          where: '$_colSourceId = ? AND $_colFilePath = ?',
          whereArgs: [item.sourceId, item.filePath],
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// 重置所有刮削中状态为待刮削（用于应用重启后恢复）
  Future<void> resetScrapingToPending() async {
    if (!_initialized) await init();

    await _db!.update(
      _tableMetadata,
      {_colScrapeStatus: ScrapeStatus.pending.index},
      where: '$_colScrapeStatus = ?',
      whereArgs: [ScrapeStatus.scraping.index],
    );
  }

  /// 获取所有电影系列（按系列分组，返回每个系列的电影列表）
  ///
  /// 优化版本：使用单次批量查询代替循环查询
  /// 复杂度从 O(n) 降为 O(1)
  ///
  /// [minCount] 系列中至少需要的不同电影数量，默认为 2（真正的系列至少有2部电影）
  Future<List<MovieCollection>> getMovieCollections({int minCount = 2}) async {
    if (!_initialized) await init();

    final stopwatch = Stopwatch()..start();

    // 步骤1：获取所有符合条件的系列 ID 和名称
    final results = await _db!.rawQuery(
      '''
      SELECT $_colCollectionId, $_colCollectionName, COUNT(*) as count
      FROM $_tableMetadata
      WHERE $_colCollectionId IS NOT NULL
        AND $_colCategory = 0
      GROUP BY $_colCollectionId
      HAVING COUNT(*) >= ?
      ORDER BY count DESC
    ''',
      [minCount],
    );

    if (results.isEmpty) {
      stopwatch.stop();
      logger.d(
        'VideoDB: getMovieCollections - 无电影系列，耗时 ${stopwatch.elapsedMilliseconds}ms',
      );
      return [];
    }

    // 步骤2：收集所有系列 ID
    final collectionIds = <int>[];
    final collectionNames = <int, String>{};
    for (final row in results) {
      final id = row[_colCollectionId]! as int;
      collectionIds.add(id);
      collectionNames[id] =
          row[_colCollectionName] as String? ??
          appL10n.videoCollectionNameUnknown;
    }

    // 步骤3：单次批量查询获取所有系列的电影
    final placeholders = List.filled(collectionIds.length, '?').join(', ');
    final allMoviesResult = await _db!.rawQuery('''
      SELECT * FROM $_tableMetadata
      WHERE $_colCollectionId IN ($placeholders)
        AND $_colCategory = 0
      ORDER BY $_colCollectionId, $_colYear ASC
    ''', collectionIds);

    // 步骤4：在内存中按系列分组
    final moviesByCollection = <int, List<VideoMetadata>>{};
    for (final row in allMoviesResult) {
      final collectionId = row[_colCollectionId]! as int;
      moviesByCollection.putIfAbsent(collectionId, () => []).add(_fromRow(row));
    }

    // 步骤5：对每个系列中的电影进行去重
    // 只合并"完全相同"的电影（同一部电影的不同清晰度版本）
    // 使用更严格的匹配条件避免将系列中不同电影错误合并
    final deduplicatedCollections = <int, List<VideoMetadata>>{};
    for (final entry in moviesByCollection.entries) {
      final collectionId = entry.key;
      final movies = entry.value;

      // 按 TMDB ID + 年份 分组（更精确的匹配）
      // - 有 TMDB ID：使用 tmdbId + year 作为键（同一部电影的不同版本）
      // - 无 TMDB ID 但有年份：使用 title + year 作为键
      // - 无年份信息：使用 uniqueKey，不进行去重（避免错误合并）
      final movieGroups = <String, List<VideoMetadata>>{};
      for (final movie in movies) {
        String key;
        if (movie.tmdbId != null && movie.year != null) {
          // 有 TMDB ID 和年份：精确匹配
          key = 'tmdb_${movie.tmdbId}_${movie.year}';
        } else if (movie.tmdbId != null) {
          // 只有 TMDB ID：可能是同一部电影的不同版本
          key = 'tmdb_${movie.tmdbId}';
        } else if (movie.title != null && movie.year != null) {
          // 无 TMDB ID 但有标题和年份
          key = '${movie.title}_${movie.year}';
        } else {
          // 信息不足，不进行去重
          key = movie.uniqueKey;
        }
        movieGroups.putIfAbsent(key, () => []).add(movie);
      }

      // 每组只保留一部电影（优先选择评分最高的，其次选择清晰度最高的）
      final uniqueMovies = <VideoMetadata>[];
      for (final group in movieGroups.values) {
        if (group.length == 1) {
          uniqueMovies.add(group.first);
        } else {
          // 按评分降序，再按清晰度（文件大小）降序
          group.sort((a, b) {
            final ratingCmp = (b.rating ?? 0).compareTo(a.rating ?? 0);
            if (ratingCmp != 0) return ratingCmp;
            return (b.fileSize ?? 0).compareTo(a.fileSize ?? 0);
          });
          uniqueMovies.add(group.first);
        }
      }

      // 按年份排序
      uniqueMovies.sort((a, b) => (a.year ?? 0).compareTo(b.year ?? 0));
      deduplicatedCollections[collectionId] = uniqueMovies;
    }

    // 步骤6：构建结果列表（保持原有顺序，只保留有多部不同电影的系列）
    final collections = <MovieCollection>[];
    for (final id in collectionIds) {
      final movies = deduplicatedCollections[id] ?? [];
      // 只有系列中有多部不同电影时才包含
      if (movies.length >= minCount) {
        collections.add(
          MovieCollection(
            id: id,
            name: collectionNames[id] ?? appL10n.videoCollectionNameUnknown,
            movies: movies,
          ),
        );
      }
    }

    stopwatch.stop();
    logger.d(
      'VideoDB: getMovieCollections - 系列=${collections.length}, '
      '总电影=${allMoviesResult.length}, 耗时 ${stopwatch.elapsedMilliseconds}ms',
    );

    return collections;
  }

  /// 根据 collectionId 获取同系列的电影
  Future<List<VideoMetadata>> getByCollectionId(int collectionId) async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tableMetadata,
      where: '$_colCollectionId = ?',
      whereArgs: [collectionId],
      orderBy: '$_colYear ASC',
    );

    return results.map(_fromRow).toList();
  }

  /// 获取有 TMDB ID 但没有系列信息的电影
  ///
  /// 用于批量更新系列信息
  Future<List<VideoMetadata>> getMoviesWithoutCollection() async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tableMetadata,
      where:
          '$_colCategory = ? AND $_colTmdbId IS NOT NULL AND $_colCollectionId IS NULL',
      whereArgs: [MediaCategory.movie.index],
    );

    return results.map(_fromRow).toList();
  }

  /// 获取有 TMDB ID 但缺少地区、类型等元数据的电影
  ///
  /// 用于批量更新元数据
  Future<List<VideoMetadata>> getMoviesWithIncompleteMetadata() async {
    if (!_initialized) await init();

    // 查找有 TMDB ID 但缺少地区或类型信息的电影
    final results = await _db!.query(
      _tableMetadata,
      where:
          '''
        $_colCategory = ?
        AND $_colTmdbId IS NOT NULL
        AND (
          $_colCountries IS NULL OR $_colCountries = ''
          OR $_colGenres IS NULL OR $_colGenres = ''
        )
      ''',
      whereArgs: [MediaCategory.movie.index],
    );

    return results.map(_fromRow).toList();
  }

  /// 获取有 TMDB ID 但缺少地区、类型等元数据的剧集（去重，每个剧集只返回一集）
  ///
  /// 用于批量更新元数据
  Future<List<VideoMetadata>> getTvShowsWithIncompleteMetadata() async {
    if (!_initialized) await init();

    // 使用子查询获取每个剧集组的代表记录（按 showDirectory 或 title 分组）
    // 只返回缺少地区或类型信息的剧集
    final results = await _db!.rawQuery(
      '''
      SELECT * FROM $_tableMetadata m
      WHERE m.$_colCategory = ?
        AND m.$_colTmdbId IS NOT NULL
        AND (
          m.$_colCountries IS NULL OR m.$_colCountries = ''
          OR m.$_colGenres IS NULL OR m.$_colGenres = ''
        )
        AND m.$_colId = (
          SELECT MIN(m2.$_colId) FROM $_tableMetadata m2
          WHERE m2.$_colCategory = ?
            AND COALESCE(m2.$_colShowDirectory, m2.$_colTitle) = COALESCE(m.$_colShowDirectory, m.$_colTitle)
        )
    ''',
      [MediaCategory.tvShow.index, MediaCategory.tvShow.index],
    );

    return results.map(_fromRow).toList();
  }

  /// 批量更新同一剧集所有集的元数据
  ///
  /// 用于更新地区、类型、演员等信息到同一剧集的所有集
  /// [showDirectory] 剧集目录（用于分组匹配）
  /// [tmdbId] TMDB ID（用于精确匹配）
  /// [countries] 地区信息（可选，为 null 则不更新）
  /// [genres] 类型信息（可选，为 null 则不更新）
  /// [cast] 演员信息（可选，为 null 则不更新）
  Future<int> updateTvShowMetadata({
    String? showDirectory,
    required int tmdbId,
    String? countries,
    String? genres,
    String? cast,
  }) async {
    if (!_initialized) await init();

    // 构建更新字段
    final updates = <String, Object?>{};
    if (countries != null) updates[_colCountries] = countries;
    if (genres != null) updates[_colGenres] = genres;
    if (cast != null) updates[_colCast] = cast;

    if (updates.isEmpty) return 0;

    // 更新所有匹配的剧集记录（使用 TMDB ID 匹配）
    final count = await _db!.update(
      _tableMetadata,
      updates,
      where: '$_colCategory = ? AND $_colTmdbId = ?',
      whereArgs: [MediaCategory.tvShow.index, tmdbId],
    );

    logger.d('VideoDatabaseService: 更新剧集 TMDB ID=$tmdbId 的 $count 条记录');
    return count;
  }

  /// 获取所有可用的年份列表（按分类筛选）
  Future<List<int>> getAvailableYears({MediaCategory? category}) async {
    if (!_initialized) await init();

    var sql =
        '''
      SELECT DISTINCT $_colYear FROM $_tableMetadata
      WHERE $_colYear IS NOT NULL
    ''';
    final args = <Object>[];

    if (category != null) {
      sql += ' AND $_colCategory = ?';
      args.add(category.index);
    }

    sql += ' ORDER BY $_colYear DESC';

    final results = await _db!.rawQuery(sql, args);
    return results.map((r) => r[_colYear]! as int).toList();
  }

  /// 获取所有可用的类型列表（按分类筛选）
  ///
  /// [category] 可选的媒体分类过滤
  /// [preferChinese] 是否优先返回中文名称，默认 true
  /// 返回合并后的类型列表（自动去除多语言重复项）
  Future<List<String>> getAvailableGenres({
    MediaCategory? category,
    bool preferChinese = true,
  }) async {
    if (!_initialized) await init();

    var sql =
        '''
      SELECT DISTINCT $_colGenres FROM $_tableMetadata
      WHERE $_colGenres IS NOT NULL AND $_colGenres != ''
    ''';
    final args = <Object>[];

    if (category != null) {
      sql += ' AND $_colCategory = ?';
      args.add(category.index);
    }

    final results = await _db!.rawQuery(sql, args);

    // 解析所有类型
    // 注意：genres 可能使用 ' / '（Scraper）或 ', '（NFO）分隔
    final rawGenres = <String>[];
    for (final row in results) {
      final genres = row[_colGenres] as String?;
      if (genres != null && genres.isNotEmpty) {
        // 支持 ' / '、'/'、', '、',' 四种分隔符格式
        rawGenres.addAll(
          genres
              .split(RegExp(r'\s*[/,]\s*'))
              .map((g) => g.trim())
              .where((g) => g.isNotEmpty),
        );
      }
    }

    // 使用映射工具合并多语言变体
    return GenreCountryMapping.mergeGenres(
      rawGenres,
      preferChinese: preferChinese,
    );
  }

  /// 根据分类、类型、年份筛选获取元数据（支持组合筛选和排序）
  Future<List<VideoMetadata>> getFiltered({
    MediaCategory? category,
    String? genre,
    int? year,
    VideoSortOption sortOption = VideoSortOption.ratingDesc,
    int limit = 50,
    int offset = 0,
  }) async {
    if (!_initialized) await init();

    var where = '1 = 1';
    final whereArgs = <Object>[];

    if (category != null) {
      where += ' AND $_colCategory = ?';
      whereArgs.add(category.index);
    }

    if (genre != null && genre.isNotEmpty) {
      where += ' AND $_colGenres LIKE ?';
      whereArgs.add('%$genre%');
    }

    if (year != null) {
      where += ' AND $_colYear = ?';
      whereArgs.add(year);
    }

    final orderBy = _buildOrderBy(sortOption);

    // 电影类别使用去重逻辑（同一电影不同清晰度只返回最高清版本）
    if (category == MediaCategory.movie) {
      final sql = _buildMovieDeduplicationQueryWithFilters(
        baseWhere: where,
        orderBy: orderBy,
        limit: limit,
        offset: offset,
      );
      // 参数需要出现两次（外层和子查询各一次）
      final args = [...whereArgs, ...whereArgs];
      final results = await _db!.rawQuery(sql, args);
      return results.map(_fromRow).toList();
    }

    // 其他类别使用普通查询
    final results = await _db!.query(
      _tableMetadata,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );

    return results.map(_fromRow).toList();
  }

  /// 构建排序 SQL
  String _buildOrderBy(VideoSortOption sortOption) {
    switch (sortOption) {
      case VideoSortOption.ratingDesc:
        return '$_colRating DESC NULLS LAST, $_colTitle';
      case VideoSortOption.ratingAsc:
        return '$_colRating ASC NULLS LAST, $_colTitle';
      case VideoSortOption.yearDesc:
        return '$_colYear DESC NULLS LAST, $_colTitle';
      case VideoSortOption.yearAsc:
        return '$_colYear ASC NULLS LAST, $_colTitle';
      case VideoSortOption.titleAsc:
        return '$_colTitle ASC';
      case VideoSortOption.titleDesc:
        return '$_colTitle DESC';
      case VideoSortOption.addedDesc:
        return '$_colLastUpdated DESC NULLS LAST, $_colTitle';
      case VideoSortOption.addedAsc:
        return '$_colLastUpdated ASC NULLS LAST, $_colTitle';
    }
  }

  /// 获取筛选后的数量
  Future<int> getFilteredCount({
    MediaCategory? category,
    String? genre,
    int? year,
  }) async {
    if (!_initialized) await init();

    var where = '1 = 1';
    final whereArgs = <Object>[];

    if (category != null) {
      where += ' AND $_colCategory = ?';
      whereArgs.add(category.index);
    }

    if (genre != null && genre.isNotEmpty) {
      where += ' AND $_colGenres LIKE ?';
      whereArgs.add('%$genre%');
    }

    if (year != null) {
      where += ' AND $_colYear = ?';
      whereArgs.add(year);
    }

    // 电影类别使用去重计数（同一电影不同清晰度只计数一次）
    if (category == MediaCategory.movie) {
      final sql = _buildMovieDeduplicationCountQuery(baseWhere: where);
      // 参数需要出现两次（外层和子查询各一次）
      final args = [...whereArgs, ...whereArgs];
      final result = await _db!.rawQuery(sql, args);
      return Sqflite.firstIntValue(result) ?? 0;
    }

    // 其他类别使用普通计数
    final result = await _db!.rawQuery(
      'SELECT COUNT(*) FROM $_tableMetadata WHERE $where',
      whereArgs,
    );

    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// 获取剧集分组的代表性元数据（带筛选条件和排序）
  ///
  /// 优化版本：使用 tv_show_groups 聚合表避免 O(n²) 相关子查询
  Future<List<VideoMetadata>> getTvShowGroupRepresentativesFiltered({
    String? genre,
    int? year,
    VideoSortOption sortOption = VideoSortOption.ratingDesc,
    int limit = 50,
    int offset = 0,
  }) async {
    if (!_initialized) await init();

    // 构建筛选条件（基于聚合表）
    var filterWhere = '';
    final filterArgs = <Object>[];

    if (genre != null && genre.isNotEmpty) {
      filterWhere += ' AND g.$_tvgColGenres LIKE ?';
      filterArgs.add('%$genre%');
    }

    if (year != null) {
      filterWhere += ' AND g.$_tvgColYear = ?';
      filterArgs.add(year);
    }

    // 基于聚合表字段的排序
    final orderBy = _buildOrderByForAggTable(sortOption);

    // 优化查询：使用聚合表的 representative_rowid 进行 JOIN
    // 复杂度从 O(n²) 降为 O(n)
    final sql =
        '''
      SELECT m.* FROM $_tableTvShowGroups g
      INNER JOIN $_tableMetadata m ON g.$_tvgColRepresentativeRowid = m.rowid
      WHERE g.$_tvgColRepresentativeRowid IS NOT NULL$filterWhere
      ORDER BY $orderBy
      LIMIT ? OFFSET ?
    ''';

    final results = await _db!.rawQuery(sql, [...filterArgs, limit, offset]);
    return results.map(_fromRow).toList();
  }

  /// 为聚合表构建排序条件
  String _buildOrderByForAggTable(VideoSortOption sortOption) {
    switch (sortOption) {
      case VideoSortOption.ratingDesc:
        return 'g.$_tvgColRating DESC NULLS LAST, g.$_tvgColTitle';
      case VideoSortOption.ratingAsc:
        return 'g.$_tvgColRating ASC NULLS LAST, g.$_tvgColTitle';
      case VideoSortOption.yearDesc:
        return 'g.$_tvgColYear DESC NULLS LAST, g.$_tvgColTitle';
      case VideoSortOption.yearAsc:
        return 'g.$_tvgColYear ASC NULLS LAST, g.$_tvgColTitle';
      case VideoSortOption.titleAsc:
        return 'g.$_tvgColTitle ASC';
      case VideoSortOption.titleDesc:
        return 'g.$_tvgColTitle DESC';
      case VideoSortOption.addedDesc:
      case VideoSortOption.addedAsc:
        // 聚合表没有添加时间，使用评分代替
        return 'g.$_tvgColRating DESC NULLS LAST, g.$_tvgColTitle';
    }
  }

  /// 获取筛选后的剧集分组数量
  ///
  /// 直接查询聚合表 tv_show_groups，确保与列表显示数量一致
  Future<int> getTvShowGroupCountFiltered({String? genre, int? year}) async {
    if (!_initialized) await init();

    var filterWhere = '';
    final filterArgs = <Object>[];

    if (genre != null && genre.isNotEmpty) {
      filterWhere += ' AND $_tvgColGenres LIKE ?';
      filterArgs.add('%$genre%');
    }

    if (year != null) {
      filterWhere += ' AND $_tvgColYear = ?';
      filterArgs.add(year);
    }

    // 直接查询聚合表的数量，确保与列表一致
    final count =
        Sqflite.firstIntValue(
          await _db!.rawQuery('''
      SELECT COUNT(*) FROM $_tableTvShowGroups
      WHERE $_tvgColRepresentativeRowid IS NOT NULL$filterWhere
      ''', filterArgs),
        ) ??
        0;

    return count;
  }

  /// 修复现有视频的分类（基于文件名模式）
  ///
  /// 用于修复已扫描但分类不正确的视频。会检测文件名中的剧集模式
  /// （如 S01E01、1x01、第X集）并更新 category 字段。
  ///
  /// 返回修复的视频数量。
  Future<int> repairCategoriesFromFilenames() async {
    if (!_initialized) await init();

    var fixedCount = 0;

    // 获取所有分类为 unknown（2）的视频
    final unknownVideos = await _db!.query(
      _tableMetadata,
      columns: [_colSourceId, _colFilePath, _colFileName],
      where: '$_colCategory = ?',
      whereArgs: [MediaCategory.unknown.index],
    );

    logger.i('VideoDatabaseService: 发现 ${unknownVideos.length} 个未分类视频，开始修复');

    // 批量更新
    final tvShowUpdates = <({String sourceId, String filePath})>[];
    final movieUpdates = <({String sourceId, String filePath})>[];

    for (final row in unknownVideos) {
      final sourceId = row[_colSourceId] as String?;
      final filePath = row[_colFilePath] as String?;
      final fileName = row[_colFileName] as String?;
      if (sourceId == null || filePath == null || fileName == null) continue;

      // 使用正则表达式检测剧集模式（与 VideoFileNameParser 相同的逻辑）
      final tvShowPattern = RegExp(
        r'[Ss](\d{1,2})[Ee](\d{1,2})|(\d{1,2})x(\d{1,2})|第(\d+)季.*?第(\d+)集|第(\d+)集',
        caseSensitive: false,
      );

      if (tvShowPattern.hasMatch(fileName)) {
        tvShowUpdates.add((sourceId: sourceId, filePath: filePath));
      } else {
        // 检测年份模式判断是否为电影
        final yearPattern = RegExp(r'[\[\(]?((?:19|20)\d{2})[\]\)]?');
        if (yearPattern.hasMatch(fileName)) {
          movieUpdates.add((sourceId: sourceId, filePath: filePath));
        }
      }
    }

    // 批量更新为 tvShow
    if (tvShowUpdates.isNotEmpty) {
      await _db!.transaction((txn) async {
        final batch = txn.batch();
        for (final item in tvShowUpdates) {
          batch.update(
            _tableMetadata,
            {_colCategory: MediaCategory.tvShow.index},
            where: '$_colSourceId = ? AND $_colFilePath = ?',
            whereArgs: [item.sourceId, item.filePath],
          );
        }
        await batch.commit(noResult: true);
      });
      fixedCount += tvShowUpdates.length;
      logger.i('VideoDatabaseService: 已将 ${tvShowUpdates.length} 个视频修复为剧集');
    }

    // 批量更新为 movie
    if (movieUpdates.isNotEmpty) {
      await _db!.transaction((txn) async {
        final batch = txn.batch();
        for (final item in movieUpdates) {
          batch.update(
            _tableMetadata,
            {_colCategory: MediaCategory.movie.index},
            where: '$_colSourceId = ? AND $_colFilePath = ?',
            whereArgs: [item.sourceId, item.filePath],
          );
        }
        await batch.commit(noResult: true);
      });
      fixedCount += movieUpdates.length;
      logger.i('VideoDatabaseService: 已将 ${movieUpdates.length} 个视频修复为电影');
    }

    logger.i('VideoDatabaseService: 分类修复完成，共修复 $fixedCount 个视频');
    return fixedCount;
  }

  // ============ 字幕索引方法 ============

  /// 批量保存字幕索引
  ///
  /// 在视频扫描时调用，将发现的字幕文件索引到数据库
  Future<void> upsertSubtitlesBatch(List<SubtitleIndex> subtitles) async {
    if (!_initialized) await init();
    if (subtitles.isEmpty) return;

    await _db!.transaction((txn) async {
      final batch = txn.batch();
      for (final subtitle in subtitles) {
        batch.insert(_tableSubtitles, {
          _subColSourceId: subtitle.sourceId,
          _subColVideoPath: subtitle.videoPath,
          _subColSubtitlePath: subtitle.subtitlePath,
          _subColFileName: subtitle.fileName,
          _subColFormat: subtitle.format,
          _subColLanguage: subtitle.language,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });

    logger.d('VideoDatabaseService: 批量保存 ${subtitles.length} 条字幕索引');
  }

  /// 获取视频对应的字幕列表（毫秒级响应）
  ///
  /// 从本地数据库查询，不需要访问文件系统
  Future<List<SubtitleIndex>> getSubtitlesForVideo(
    String sourceId,
    String videoPath,
  ) async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tableSubtitles,
      where: '$_subColSourceId = ? AND $_subColVideoPath = ?',
      whereArgs: [sourceId, videoPath],
    );

    return results.map(_subtitleFromRow).toList();
  }

  /// 删除视频对应的所有字幕索引
  Future<void> deleteSubtitlesForVideo(
    String sourceId,
    String videoPath,
  ) async {
    if (!_initialized) await init();

    await _db!.delete(
      _tableSubtitles,
      where: '$_subColSourceId = ? AND $_subColVideoPath = ?',
      whereArgs: [sourceId, videoPath],
    );
  }

  /// 根据 sourceId 删除所有字幕索引
  Future<int> deleteSubtitlesBySourceId(String sourceId) async {
    if (!_initialized) await init();

    return _db!.delete(
      _tableSubtitles,
      where: '$_subColSourceId = ?',
      whereArgs: [sourceId],
    );
  }

  /// 根据 sourceId 和路径前缀删除字幕索引
  Future<int> deleteSubtitlesByPath(String sourceId, String pathPrefix) async {
    if (!_initialized) await init();

    return _db!.delete(
      _tableSubtitles,
      where: '$_subColSourceId = ? AND $_subColVideoPath LIKE ?',
      whereArgs: [sourceId, '$pathPrefix%'],
    );
  }

  /// 从数据库行转换为 SubtitleIndex
  SubtitleIndex _subtitleFromRow(Map<String, dynamic> row) => SubtitleIndex(
    sourceId: row[_subColSourceId] as String,
    videoPath: row[_subColVideoPath] as String,
    subtitlePath: row[_subColSubtitlePath] as String,
    fileName: row[_subColFileName] as String,
    format: row[_subColFormat] as String,
    language: row[_subColLanguage] as String?,
  );

  // ============ 扫描进度方法 ============

  /// 批量保存待扫描目录
  ///
  /// 在扫描开始时，将发现的所有子目录添加到待扫描队列
  Future<void> addPendingDirectories(
    String sourceId,
    String rootPath,
    List<String> directories,
  ) async {
    if (!_initialized) await init();
    if (directories.isEmpty) return;

    await _db!.transaction((txn) async {
      final batch = txn.batch();
      for (final dir in directories) {
        batch.insert(
          _tableScanProgress,
          {
            _scanColSourceId: sourceId,
            _scanColPath: dir,
            _scanColRootPath: rootPath,
            _scanColStatus: scanStatusPending,
            _scanColVideoCount: 0,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore, // 已存在则跳过
        );
      }
      await batch.commit(noResult: true);
    });

    logger.d('VideoDatabaseService: 添加 ${directories.length} 个待扫描目录');
  }

  /// 获取待扫描的目录列表
  ///
  /// 返回状态为 pending 或 scanning 的目录（scanning 表示上次中断）
  Future<List<ScanProgressItem>> getPendingDirectories(
    String sourceId,
    String rootPath, {
    int limit = 100,
  }) async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tableScanProgress,
      where:
          '$_scanColSourceId = ? AND $_scanColRootPath = ? AND $_scanColStatus < ?',
      whereArgs: [sourceId, rootPath, scanStatusCompleted],
      orderBy: _scanColId,
      limit: limit,
    );

    return results.map(_scanProgressFromRow).toList();
  }

  /// 标记目录开始扫描
  Future<void> markDirectoryScanning(String sourceId, String path) async {
    if (!_initialized) await init();

    await _db!.update(
      _tableScanProgress,
      {_scanColStatus: scanStatusScanning},
      where: '$_scanColSourceId = ? AND $_scanColPath = ?',
      whereArgs: [sourceId, path],
    );
  }

  /// 标记目录扫描完成
  ///
  /// [videoCount] 该目录发现的视频数量
  /// [dirModifiedTime] 目录的修改时间（用于下次增量同步检测变化）
  Future<void> markDirectoryCompleted(
    String sourceId,
    String path, {
    int videoCount = 0,
    DateTime? dirModifiedTime,
  }) async {
    if (!_initialized) await init();

    await _db!.update(
      _tableScanProgress,
      {
        _scanColStatus: scanStatusCompleted,
        _scanColVideoCount: videoCount,
        _scanColLastScanned: DateTime.now().millisecondsSinceEpoch,
        if (dirModifiedTime != null)
          _scanColDirModifiedTime: dirModifiedTime.millisecondsSinceEpoch,
      },
      where: '$_scanColSourceId = ? AND $_scanColPath = ?',
      whereArgs: [sourceId, path],
    );
  }

  /// 批量标记目录扫描完成
  Future<void> markDirectoriesCompletedBatch(
    List<
      ({
        String sourceId,
        String path,
        int videoCount,
        DateTime? dirModifiedTime,
      })
    >
    items,
  ) async {
    if (!_initialized) await init();
    if (items.isEmpty) return;

    final now = DateTime.now().millisecondsSinceEpoch;

    await _db!.transaction((txn) async {
      final batch = txn.batch();
      for (final item in items) {
        batch.update(
          _tableScanProgress,
          {
            _scanColStatus: scanStatusCompleted,
            _scanColVideoCount: item.videoCount,
            _scanColLastScanned: now,
            if (item.dirModifiedTime != null)
              _scanColDirModifiedTime:
                  item.dirModifiedTime!.millisecondsSinceEpoch,
          },
          where: '$_scanColSourceId = ? AND $_scanColPath = ?',
          whereArgs: [item.sourceId, item.path],
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// 获取扫描进度统计
  Future<ScanProgressStats> getScanProgressStats(
    String sourceId,
    String rootPath,
  ) async {
    if (!_initialized) await init();

    final total =
        Sqflite.firstIntValue(
          await _db!.rawQuery(
            'SELECT COUNT(*) FROM $_tableScanProgress WHERE $_scanColSourceId = ? AND $_scanColRootPath = ?',
            [sourceId, rootPath],
          ),
        ) ??
        0;

    final completed =
        Sqflite.firstIntValue(
          await _db!.rawQuery(
            'SELECT COUNT(*) FROM $_tableScanProgress WHERE $_scanColSourceId = ? AND $_scanColRootPath = ? AND $_scanColStatus = ?',
            [sourceId, rootPath, scanStatusCompleted],
          ),
        ) ??
        0;

    final scanning =
        Sqflite.firstIntValue(
          await _db!.rawQuery(
            'SELECT COUNT(*) FROM $_tableScanProgress WHERE $_scanColSourceId = ? AND $_scanColRootPath = ? AND $_scanColStatus = ?',
            [sourceId, rootPath, scanStatusScanning],
          ),
        ) ??
        0;

    final totalVideos =
        Sqflite.firstIntValue(
          await _db!.rawQuery(
            'SELECT SUM($_scanColVideoCount) FROM $_tableScanProgress WHERE $_scanColSourceId = ? AND $_scanColRootPath = ?',
            [sourceId, rootPath],
          ),
        ) ??
        0;

    return ScanProgressStats(
      totalDirectories: total,
      completedDirectories: completed,
      scanningDirectories: scanning,
      totalVideosFound: totalVideos,
    );
  }

  /// 清除扫描进度（用于重新扫描）
  Future<void> clearScanProgress(String sourceId, String rootPath) async {
    if (!_initialized) await init();

    await _db!.delete(
      _tableScanProgress,
      where: '$_scanColSourceId = ? AND $_scanColRootPath = ?',
      whereArgs: [sourceId, rootPath],
    );

    logger.i(
      'VideoDatabaseService: 已清除扫描进度 (sourceId: $sourceId, rootPath: $rootPath)',
    );
  }

  /// 清除源的所有扫描进度
  Future<void> clearScanProgressBySourceId(String sourceId) async {
    if (!_initialized) await init();

    await _db!.delete(
      _tableScanProgress,
      where: '$_scanColSourceId = ?',
      whereArgs: [sourceId],
    );
  }

  /// 重置中断的扫描（将 scanning 状态重置为 pending）
  Future<int> resetInterruptedScans(String sourceId, String rootPath) async {
    if (!_initialized) await init();

    return _db!.update(
      _tableScanProgress,
      {_scanColStatus: scanStatusPending},
      where:
          '$_scanColSourceId = ? AND $_scanColRootPath = ? AND $_scanColStatus = ?',
      whereArgs: [sourceId, rootPath, scanStatusScanning],
    );
  }

  /// 检查是否有未完成的扫描
  Future<bool> hasUnfinishedScan(String sourceId, String rootPath) async {
    if (!_initialized) await init();

    final count = Sqflite.firstIntValue(
      await _db!.rawQuery(
        'SELECT COUNT(*) FROM $_tableScanProgress WHERE $_scanColSourceId = ? AND $_scanColRootPath = ? AND $_scanColStatus < ?',
        [sourceId, rootPath, scanStatusCompleted],
      ),
    );

    return (count ?? 0) > 0;
  }

  /// 获取已完成目录的路径集合（用于增量扫描时跳过）
  Future<Set<String>> getCompletedDirectoryPaths(
    String sourceId,
    String rootPath,
  ) async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tableScanProgress,
      columns: [_scanColPath],
      where:
          '$_scanColSourceId = ? AND $_scanColRootPath = ? AND $_scanColStatus = ?',
      whereArgs: [sourceId, rootPath, scanStatusCompleted],
    );

    return results.map((r) => r[_scanColPath]! as String).toSet();
  }

  /// 从数据库行转换为 ScanProgressItem
  ScanProgressItem _scanProgressFromRow(Map<String, dynamic> row) =>
      ScanProgressItem(
        sourceId: row[_scanColSourceId] as String,
        path: row[_scanColPath] as String,
        rootPath: row[_scanColRootPath] as String,
        status: row[_scanColStatus] as int,
        videoCount: row[_scanColVideoCount] as int? ?? 0,
        lastScanned: row[_scanColLastScanned] != null
            ? DateTime.fromMillisecondsSinceEpoch(
                row[_scanColLastScanned] as int,
              )
            : null,
        dirModifiedTime: row[_scanColDirModifiedTime] != null
            ? DateTime.fromMillisecondsSinceEpoch(
                row[_scanColDirModifiedTime] as int,
              )
            : null,
      );

  // ============================================
  // 增量同步方法
  // ============================================

  /// 获取单个目录的扫描进度记录
  Future<ScanProgressItem?> getScanProgressItem(
    String sourceId,
    String path,
  ) async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tableScanProgress,
      where: '$_scanColSourceId = ? AND $_scanColPath = ?',
      whereArgs: [sourceId, path],
      limit: 1,
    );

    if (results.isEmpty) return null;
    return _scanProgressFromRow(results.first);
  }

  /// 删除单个目录的扫描进度记录
  Future<void> deleteScanProgressItem(String sourceId, String path) async {
    if (!_initialized) await init();

    await _db!.delete(
      _tableScanProgress,
      where: '$_scanColSourceId = ? AND $_scanColPath = ?',
      whereArgs: [sourceId, path],
    );
  }

  /// 插入或更新扫描进度记录
  Future<void> upsertScanProgressItem({
    required String sourceId,
    required String path,
    required String rootPath,
    int videoCount = 0,
    DateTime? dirModifiedTime,
  }) async {
    if (!_initialized) await init();

    await _db!.insert(_tableScanProgress, {
      _scanColSourceId: sourceId,
      _scanColPath: path,
      _scanColRootPath: rootPath,
      _scanColStatus: scanStatusCompleted,
      _scanColVideoCount: videoCount,
      _scanColLastScanned: DateTime.now().millisecondsSinceEpoch,
      if (dirModifiedTime != null)
        _scanColDirModifiedTime: dirModifiedTime.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 获取指定目录下的视频文件（用于增量同步）
  ///
  /// 只返回直接位于该目录下的文件（不递归）
  Future<Map<String, ({int fileSize, DateTime? fileModifiedTime})>>
  getVideoFilesInDirectory(String sourceId, String dirPath) async {
    if (!_initialized) await init();

    // 使用 LIKE 匹配直接子文件（不包含更深层目录）
    // 例如：/movies/avatar/ 下的文件，但不包括 /movies/avatar/subs/ 下的文件
    final normalizedPath = dirPath.endsWith('/') ? dirPath : '$dirPath/';

    final results = await _db!.rawQuery(
      '''
      SELECT $_colFilePath, $_colFileSize, $_colFileModifiedTime
      FROM $_tableMetadata
      WHERE $_colSourceId = ?
        AND $_colFilePath LIKE ?
        AND $_colFilePath NOT LIKE ?
      ''',
      [sourceId, '$normalizedPath%', '$normalizedPath%/%'],
    );

    return {
      for (final row in results)
        row[_colFilePath]! as String: (
          fileSize: row[_colFileSize] as int? ?? 0,
          fileModifiedTime: row[_colFileModifiedTime] != null
              ? DateTime.fromMillisecondsSinceEpoch(
                  row[_colFileModifiedTime]! as int,
                )
              : null,
        ),
    };
  }

  /// 获取所有已完成扫描的目录及其修改时间
  ///
  /// 用于增量同步时与当前文件系统对比
  Future<Map<String, ScanProgressItem>> getCompletedDirectoriesMap(
    String sourceId,
    String rootPath,
  ) async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tableScanProgress,
      where:
          '$_scanColSourceId = ? AND $_scanColRootPath = ? AND $_scanColStatus = ?',
      whereArgs: [sourceId, rootPath, scanStatusCompleted],
    );

    return {
      for (final row in results)
        row[_scanColPath]! as String: _scanProgressFromRow(row),
    };
  }

  /// 获取指定源下所有视频文件路径（用于检测已删除文件）
  ///
  /// 返回 `Map<filePath, (fileSize, fileModifiedTime)>`
  Future<Map<String, ({int fileSize, DateTime? fileModifiedTime})>>
  getVideoFilesMap(String sourceId, {String? pathPrefix}) async {
    if (!_initialized) await init();

    final directoryPrefix = pathPrefix == null
        ? null
        : pathPrefix.endsWith('/')
        ? pathPrefix
        : '$pathPrefix/';
    final escapedPrefix = directoryPrefix
        ?.replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    final where = pathPrefix != null
        ? '$_colSourceId = ? AND '
              "($_colFilePath = ? OR $_colFilePath LIKE ? ESCAPE '\\')"
        : '$_colSourceId = ?';
    final whereArgs = pathPrefix != null
        ? [sourceId, pathPrefix, '$escapedPrefix%']
        : [sourceId];

    final results = await _db!.query(
      _tableMetadata,
      columns: [_colFilePath, _colFileSize, _colFileModifiedTime],
      where: where,
      whereArgs: whereArgs,
    );

    return {
      for (final row in results)
        row[_colFilePath]! as String: (
          fileSize: row[_colFileSize] as int? ?? 0,
          fileModifiedTime: row[_colFileModifiedTime] != null
              ? DateTime.fromMillisecondsSinceEpoch(
                  row[_colFileModifiedTime]! as int,
                )
              : null,
        ),
    };
  }

  /// 批量删除视频记录（用于清理已删除的文件）
  Future<int> deleteVideosBatch(String sourceId, List<String> filePaths) async {
    if (!_initialized) await init();
    if (filePaths.isEmpty) return 0;

    var totalDeleted = 0;

    // 分批处理，避免 SQL 参数过多
    const batchSize = 100;
    for (var i = 0; i < filePaths.length; i += batchSize) {
      final batch = filePaths.skip(i).take(batchSize).toList();
      final placeholders = batch.map((_) => '?').join(', ');

      final deleted = await _db!.delete(
        _tableMetadata,
        where: '$_colSourceId = ? AND $_colFilePath IN ($placeholders)',
        whereArgs: [sourceId, ...batch],
      );
      totalDeleted += deleted;
    }

    // 同步移除 Spotlight 索引（macOS 启用时）
    SpotlightHook.afterDelete(
      SpotlightItemKind.video,
      filePaths.map((p) => '$sourceId|$p'),
    );

    return totalDeleted;
  }

  /// 标记目录为需要重新扫描（用于增量同步检测到变化时）
  Future<void> markDirectoriesForRescan(
    String sourceId,
    List<String> dirPaths,
  ) async {
    if (!_initialized) await init();
    if (dirPaths.isEmpty) return;

    // 分批处理
    const batchSize = 100;
    for (var i = 0; i < dirPaths.length; i += batchSize) {
      final batch = dirPaths.skip(i).take(batchSize).toList();
      final placeholders = batch.map((_) => '?').join(', ');

      await _db!.update(
        _tableScanProgress,
        {_scanColStatus: scanStatusPending},
        where: '$_scanColSourceId = ? AND $_scanColPath IN ($placeholders)',
        whereArgs: [sourceId, ...batch],
      );
    }
  }

  /// 获取增量同步统计
  Future<IncrementalSyncStats> getIncrementalSyncStats(
    String sourceId,
    String rootPath,
  ) async {
    if (!_initialized) await init();

    // 获取有修改时间记录的目录数
    final withMtime =
        Sqflite.firstIntValue(
          await _db!.rawQuery(
            '''
      SELECT COUNT(*) FROM $_tableScanProgress
      WHERE $_scanColSourceId = ? AND $_scanColRootPath = ?
        AND $_scanColDirModifiedTime IS NOT NULL
      ''',
            [sourceId, rootPath],
          ),
        ) ??
        0;

    // 获取总目录数
    final total =
        Sqflite.firstIntValue(
          await _db!.rawQuery(
            'SELECT COUNT(*) FROM $_tableScanProgress WHERE $_scanColSourceId = ? AND $_scanColRootPath = ?',
            [sourceId, rootPath],
          ),
        ) ??
        0;

    // 获取视频总数（按源和路径前缀过滤）
    final videos =
        Sqflite.firstIntValue(
          await _db!.rawQuery(
            'SELECT COUNT(*) FROM $_tableMetadata WHERE $_colSourceId = ? AND $_colFilePath LIKE ?',
            [sourceId, '$rootPath%'],
          ),
        ) ??
        0;

    return IncrementalSyncStats(
      totalDirectories: total,
      directoriesWithMtime: withMtime,
      totalVideos: videos,
      supportsIncrementalSync: withMtime > 0,
    );
  }

  // ============================================
  // 聚合表同步方法
  // ============================================

  /// 同步 TV 剧集分组表
  ///
  /// 新分组策略（基于 show_directory）：
  /// 1. 优先按 show_directory 分组（最可靠，基于目录结构）
  /// 2. 在同目录组内，选择众数 tmdbId（处理部分集刮削成功的情况）
  /// 3. 合并相同 tmdbId 的不同目录（处理跨路径的同一部剧）
  ///
  /// 分组键优先级：
  /// 1. tmdb_{id} - 有 tmdbId 时使用
  /// 2. dir_{show_directory_hash} - 无 tmdbId 但有目录结构
  Future<int> syncTvShowGroups() async {
    if (!_initialized) await init();

    final stopwatch = Stopwatch()..start();

    // 步骤 1: 清空旧数据
    await _db!.delete(_tableTvShowGroups);

    // 步骤 2: 按 show_directory 聚合，找出每个目录的众数 tmdbId
    // 这样可以处理同一目录下部分集有 tmdbId、部分没有的情况
    final directoryGroups = await _db!.rawQuery('''
      SELECT 
        $_colShowDirectory as show_directory,
        $_colTmdbId as tmdb_id,
        COUNT(*) as count
      FROM $_tableMetadata
      WHERE $_colCategory = 1 AND $_colShowDirectory IS NOT NULL
      GROUP BY $_colShowDirectory, $_colTmdbId
      ORDER BY $_colShowDirectory, count DESC
    ''');

    // 构建目录到最佳 tmdbId 的映射（取众数）
    final directoryTmdbMap = <String, int?>{};
    String? lastDir;
    for (final row in directoryGroups) {
      final dir = row['show_directory'] as String?;
      if (dir == null) continue;

      // 每个目录只取第一个（count 最大的）
      if (dir != lastDir) {
        lastDir = dir;
        final tmdbId = row['tmdb_id'] as int?;
        directoryTmdbMap[dir] = tmdbId;
      }
    }

    // 步骤 3: 收集需要合并的目录（相同 tmdbId）
    final tmdbDirectories = <int, List<String>>{};
    final orphanDirectories = <String>[]; // 没有 tmdbId 的目录

    for (final entry in directoryTmdbMap.entries) {
      if (entry.value != null) {
        tmdbDirectories.putIfAbsent(entry.value!, () => []).add(entry.key);
      } else {
        orphanDirectories.add(entry.key);
      }
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    var insertedCount = 0;

    // 步骤 4: 为每个有 tmdbId 的分组创建记录
    for (final entry in tmdbDirectories.entries) {
      final tmdbId = entry.key;
      final directories = entry.value;

      // 构建 WHERE 子句来匹配所有相关目录
      final placeholders = directories.map((_) => '?').join(', ');

      final aggregated = await _db!.rawQuery('''
        SELECT 
          MAX($_colTitle) as title,
          LOWER(MAX($_colTitle)) as normalized_title,
          MAX($_colOriginalTitle) as original_title,
          MAX($_colYear) as year,
          MAX($_colOverview) as overview,
          MAX($_colPosterUrl) as poster_url,
          MAX($_colBackdropUrl) as backdrop_url,
          MAX($_colRating) as rating,
          MAX($_colGenres) as genres,
          COUNT(DISTINCT CASE WHEN $_colSeasonNumber > 0 THEN $_colSeasonNumber END) as season_count,
          COUNT(*) as episode_count,
          MAX(rowid) as representative_rowid,
          MAX($_colLocalPosterUrl) as local_poster_url
        FROM $_tableMetadata
        WHERE $_colCategory = 1 AND $_colShowDirectory IN ($placeholders)
      ''', directories);

      if (aggregated.isEmpty) continue;

      final row = aggregated.first;
      final title = row['title'] as String?;
      if (title == null) continue;

      final groupKey = 'tmdb_$tmdbId';

      await _db!.rawInsert(
        '''
        INSERT OR REPLACE INTO $_tableTvShowGroups (
          $_tvgColGroupKey,
          $_tvgColTmdbId,
          $_tvgColTitle,
          $_tvgColNormalizedTitle,
          $_tvgColOriginalTitle,
          $_tvgColYear,
          $_tvgColOverview,
          $_tvgColPosterUrl,
          $_tvgColBackdropUrl,
          $_tvgColRating,
          $_tvgColGenres,
          $_tvgColSeasonCount,
          $_tvgColEpisodeCount,
          $_tvgColRepresentativeRowid,
          $_tvgColLastSynced,
          $_tvgColLocalPosterUrl
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
        [
          groupKey,
          tmdbId,
          title,
          row['normalized_title'] as String? ?? title.toLowerCase(),
          row['original_title'] as String?,
          row['year'] as int?,
          row['overview'] as String?,
          row['poster_url'] as String?,
          row['backdrop_url'] as String?,
          row['rating'] as double?,
          row['genres'] as String?,
          row['season_count'] as int? ?? 1,
          row['episode_count'] as int? ?? 1,
          row['representative_rowid'] as int?,
          now,
          row['local_poster_url'] as String?,
        ],
      );

      insertedCount++;
    }

    // 步骤 5: 为没有 tmdbId 的目录单独创建分组
    for (final directory in orphanDirectories) {
      final aggregated = await _db!.rawQuery(
        '''
        SELECT 
          MAX($_colTitle) as title,
          LOWER(MAX($_colTitle)) as normalized_title,
          MAX($_colOriginalTitle) as original_title,
          MAX($_colYear) as year,
          MAX($_colOverview) as overview,
          MAX($_colPosterUrl) as poster_url,
          MAX($_colBackdropUrl) as backdrop_url,
          MAX($_colRating) as rating,
          MAX($_colGenres) as genres,
          COUNT(DISTINCT CASE WHEN $_colSeasonNumber > 0 THEN $_colSeasonNumber END) as season_count,
          COUNT(*) as episode_count,
          MAX(rowid) as representative_rowid,
          MAX($_colLocalPosterUrl) as local_poster_url
        FROM $_tableMetadata
        WHERE $_colCategory = 1 AND $_colShowDirectory = ?
      ''',
        [directory],
      );

      if (aggregated.isEmpty) continue;

      final row = aggregated.first;
      final title = row['title'] as String?;
      if (title == null) continue;

      // 使用目录路径的哈希作为 group_key
      final groupKey = 'dir_${directory.hashCode.abs()}';

      await _db!.rawInsert(
        '''
        INSERT OR REPLACE INTO $_tableTvShowGroups (
          $_tvgColGroupKey,
          $_tvgColTmdbId,
          $_tvgColTitle,
          $_tvgColNormalizedTitle,
          $_tvgColOriginalTitle,
          $_tvgColYear,
          $_tvgColOverview,
          $_tvgColPosterUrl,
          $_tvgColBackdropUrl,
          $_tvgColRating,
          $_tvgColGenres,
          $_tvgColSeasonCount,
          $_tvgColEpisodeCount,
          $_tvgColRepresentativeRowid,
          $_tvgColLastSynced,
          $_tvgColLocalPosterUrl
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
        [
          groupKey,
          null, // no tmdbId
          title,
          row['normalized_title'] as String? ?? title.toLowerCase(),
          row['original_title'] as String?,
          row['year'] as int?,
          row['overview'] as String?,
          row['poster_url'] as String?,
          row['backdrop_url'] as String?,
          row['rating'] as double?,
          row['genres'] as String?,
          row['season_count'] as int? ?? 1,
          row['episode_count'] as int? ?? 1,
          row['representative_rowid'] as int?,
          now,
          row['local_poster_url'] as String?,
        ],
      );

      insertedCount++;
    }

    // 步骤 6: 处理没有 show_directory 的剧集（兼容旧数据）
    final noDirectoryCount =
        Sqflite.firstIntValue(
          await _db!.rawQuery('''
      SELECT COUNT(DISTINCT COALESCE($_colTmdbId, $_colTitle))
      FROM $_tableMetadata
      WHERE $_colCategory = 1 AND $_colShowDirectory IS NULL
    '''),
        ) ??
        0;

    if (noDirectoryCount > 0) {
      // 按 tmdbId 或 title 分组（旧逻辑兜底）
      final fallbackResult = await _db!.rawQuery('''
        SELECT 
          $_colTmdbId as tmdb_id,
          MAX($_colTitle) as title,
          LOWER(MAX($_colTitle)) as normalized_title,
          MAX($_colOriginalTitle) as original_title,
          MAX($_colYear) as year,
          MAX($_colOverview) as overview,
          MAX($_colPosterUrl) as poster_url,
          MAX($_colBackdropUrl) as backdrop_url,
          MAX($_colRating) as rating,
          MAX($_colGenres) as genres,
          COUNT(DISTINCT CASE WHEN $_colSeasonNumber > 0 THEN $_colSeasonNumber END) as season_count,
          COUNT(*) as episode_count,
          MAX(rowid) as representative_rowid
        FROM $_tableMetadata
        WHERE $_colCategory = 1 AND $_colShowDirectory IS NULL
        GROUP BY COALESCE($_colTmdbId, LOWER($_colTitle))
      ''');

      for (final row in fallbackResult) {
        final tmdbId = row['tmdb_id'] as int?;
        final title = row['title'] as String?;
        if (title == null) continue;

        final groupKey = tmdbId != null
            ? 'tmdb_$tmdbId'
            : 'title_${(row['normalized_title'] as String? ?? title.toLowerCase()).hashCode.abs()}';

        await _db!.rawInsert(
          '''
          INSERT OR IGNORE INTO $_tableTvShowGroups (
            $_tvgColGroupKey,
            $_tvgColTmdbId,
            $_tvgColTitle,
            $_tvgColNormalizedTitle,
            $_tvgColOriginalTitle,
            $_tvgColYear,
            $_tvgColOverview,
            $_tvgColPosterUrl,
            $_tvgColBackdropUrl,
            $_tvgColRating,
            $_tvgColGenres,
            $_tvgColSeasonCount,
            $_tvgColEpisodeCount,
            $_tvgColRepresentativeRowid,
            $_tvgColLastSynced
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
          [
            groupKey,
            tmdbId,
            title,
            row['normalized_title'] as String? ?? title.toLowerCase(),
            row['original_title'] as String?,
            row['year'] as int?,
            row['overview'] as String?,
            row['poster_url'] as String?,
            row['backdrop_url'] as String?,
            row['rating'] as double?,
            row['genres'] as String?,
            row['season_count'] as int? ?? 1,
            row['episode_count'] as int? ?? 1,
            row['representative_rowid'] as int?,
            now,
          ],
        );

        insertedCount++;
      }
    }

    stopwatch.stop();
    logger.i(
      'VideoDatabaseService: TV剧集分组同步完成, '
      '插入/更新 $insertedCount 条, 耗时 ${stopwatch.elapsedMilliseconds}ms',
    );

    return insertedCount;
  }

  /// 同步电影系列分组表
  ///
  /// 仅聚合 TMDB collection_id 系列（官方系列）
  /// 目录系列已禁用，避免将同目录不相关电影误识别为系列
  Future<int> syncMovieCollectionGroups() async {
    if (!_initialized) await init();

    final stopwatch = Stopwatch()..start();

    // 清空旧数据
    await _db!.delete(_tableMovieCollectionGroups);

    final now = DateTime.now().millisecondsSinceEpoch;
    var insertedCount = 0;

    // 聚合有 collection_id 的电影（TMDB 官方系列）
    // 优先使用系列专属海报，否则使用第一部电影的海报
    final tmdbCollections = await _db!.rawQuery('''
      SELECT
        $_colCollectionId,
        MAX($_colCollectionName) as name,
        COALESCE(MAX($_colCollectionPosterUrl), MAX($_colPosterUrl)) as poster_url,
        COALESCE(MAX($_colCollectionBackdropUrl), MAX($_colBackdropUrl)) as backdrop_url,
        MAX($_colOverview) as overview,
        COUNT(*) as movie_count
      FROM $_tableMetadata
      WHERE $_colCategory = 0 AND $_colCollectionId IS NOT NULL
      GROUP BY $_colCollectionId
    ''');

    for (final row in tmdbCollections) {
      final collectionId = row[_colCollectionId] as int?;
      if (collectionId == null) continue;

      await _db!.rawInsert(
        '''
        INSERT OR REPLACE INTO $_tableMovieCollectionGroups (
          $_mcgColTmdbCollectionId,
          $_mcgColName,
          $_mcgColPosterUrl,
          $_mcgColBackdropUrl,
          $_mcgColOverview,
          $_mcgColMovieCount,
          $_mcgColLastSynced
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ''',
        [
          collectionId,
          row['name'] as String? ?? appL10n.videoCollectionNameFallback,
          row['poster_url'] as String?,
          row['backdrop_url'] as String?,
          row['overview'] as String?,
          row['movie_count'] as int? ?? 1,
          now,
        ],
      );

      insertedCount++;
    }

    stopwatch.stop();
    logger.i(
      'VideoDatabaseService: 电影系列分组同步完成, '
      'TMDB: ${tmdbCollections.length}, '
      '总计 $insertedCount 条, 耗时 ${stopwatch.elapsedMilliseconds}ms',
    );

    return insertedCount;
  }

  /// 获取 TV 剧集分组列表（从聚合表读取）
  ///
  /// 这是首页使用的高性能查询，无需 GROUP BY
  Future<List<TvShowGroupRow>> getTvShowGroupList({
    int limit = 50,
    int offset = 0,
    String orderBy = 'rating DESC',
  }) async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tableTvShowGroups,
      orderBy: '$_tvgColRating DESC NULLS LAST, $_tvgColTitle',
      limit: limit,
      offset: offset,
    );

    return results
        .map(
          (row) => TvShowGroupRow(
            id: row[_tvgColId]! as int,
            groupKey: row[_tvgColGroupKey]! as String,
            tmdbId: row[_tvgColTmdbId] as int?,
            title: row[_tvgColTitle]! as String,
            normalizedTitle: row[_tvgColNormalizedTitle]! as String,
            originalTitle: row[_tvgColOriginalTitle] as String?,
            year: row[_tvgColYear] as int?,
            overview: row[_tvgColOverview] as String?,
            posterUrl: row[_tvgColPosterUrl] as String?,
            backdropUrl: row[_tvgColBackdropUrl] as String?,
            rating: row[_tvgColRating] as double?,
            genres: row[_tvgColGenres] as String?,
            seasonCount: row[_tvgColSeasonCount] as int? ?? 0,
            episodeCount: row[_tvgColEpisodeCount] as int? ?? 0,
            representativeRowid: row[_tvgColRepresentativeRowid] as int?,
            localPosterUrl: row[_tvgColLocalPosterUrl] as String?,
          ),
        )
        .toList();
  }

  /// 获取 TV 剧集分组总数（从聚合表读取）
  Future<int> getTvShowGroupListCount() async {
    if (!_initialized) await init();

    return Sqflite.firstIntValue(
          await _db!.rawQuery('SELECT COUNT(*) FROM $_tableTvShowGroups'),
        ) ??
        0;
  }

  /// 获取电影系列分组列表（从聚合表读取）
  Future<List<MovieCollectionGroupRow>> getMovieCollectionGroupList({
    int limit = 50,
    int offset = 0,
  }) async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tableMovieCollectionGroups,
      orderBy: '$_mcgColMovieCount DESC',
      limit: limit,
      offset: offset,
    );

    return results
        .map(
          (row) => MovieCollectionGroupRow(
            id: row[_mcgColId]! as int,
            tmdbCollectionId: row[_mcgColTmdbCollectionId] as int?,
            name: row[_mcgColName]! as String,
            posterUrl: row[_mcgColPosterUrl] as String?,
            backdropUrl: row[_mcgColBackdropUrl] as String?,
            overview: row[_mcgColOverview] as String?,
            movieCount: row[_mcgColMovieCount] as int? ?? 0,
          ),
        )
        .toList();
  }

  /// 获取电影系列分组总数（从聚合表读取）
  Future<int> getMovieCollectionGroupListCount() async {
    if (!_initialized) await init();

    return Sqflite.firstIntValue(
          await _db!.rawQuery(
            'SELECT COUNT(*) FROM $_tableMovieCollectionGroups',
          ),
        ) ??
        0;
  }

  // ============================================================
  // 重复视频检测方法
  // ============================================================

  /// 获取 TMDB ID 重复的视频组
  ///
  /// 返回所有具有相同 TMDB ID 的视频，按 TMDB ID 分组
  /// 只返回有 2 个或以上视频的组
  Future<Map<int, List<VideoMetadata>>> getDuplicatesByTmdbId() async {
    if (!_initialized) await init();

    // 先找出有重复的 TMDB ID
    final duplicateIds = await _db!.rawQuery('''
      SELECT $_colTmdbId, COUNT(*) as cnt
      FROM $_tableMetadata
      WHERE $_colTmdbId IS NOT NULL
      GROUP BY $_colTmdbId
      HAVING cnt > 1
    ''');

    if (duplicateIds.isEmpty) return {};

    final result = <int, List<VideoMetadata>>{};

    for (final row in duplicateIds) {
      final tmdbId = row[_colTmdbId]! as int;
      final videos = await _db!.query(
        _tableMetadata,
        where: '$_colTmdbId = ?',
        whereArgs: [tmdbId],
        orderBy: '$_colFileSize DESC', // 按文件大小降序，最大的在前
      );
      result[tmdbId] = videos.map(_fromRow).toList();
    }

    return result;
  }

  /// 获取标题+年份重复的视频组（针对无 TMDB ID 的视频）
  ///
  /// 返回所有具有相同标题和年份的视频，按 "title|year" 分组
  /// 只返回有 2 个或以上视频且没有 TMDB ID 的组
  Future<Map<String, List<VideoMetadata>>> getDuplicatesByTitleYear() async {
    if (!_initialized) await init();

    // 找出标题+年份重复且没有 TMDB ID 的视频
    final duplicates = await _db!.rawQuery('''
      SELECT $_colTitle, $_colYear, COUNT(*) as cnt
      FROM $_tableMetadata
      WHERE $_colTmdbId IS NULL
        AND $_colTitle IS NOT NULL
        AND $_colTitle != ''
        AND $_colYear IS NOT NULL
      GROUP BY $_colTitle, $_colYear
      HAVING cnt > 1
    ''');

    if (duplicates.isEmpty) return {};

    final result = <String, List<VideoMetadata>>{};

    for (final row in duplicates) {
      final title = row[_colTitle]! as String;
      final year = row[_colYear]! as int;
      final key = '$title|$year';

      final videos = await _db!.query(
        _tableMetadata,
        where: '$_colTmdbId IS NULL AND $_colTitle = ? AND $_colYear = ?',
        whereArgs: [title, year],
        orderBy: '$_colFileSize DESC',
      );
      result[key] = videos.map(_fromRow).toList();
    }

    return result;
  }

  /// 获取重复视频统计
  ///
  /// 返回各类重复的组数和涉及的文件总数
  Future<VideoDuplicateStats> getDuplicateStats() async {
    if (!_initialized) await init();

    // TMDB ID 重复统计
    final tmdbResult = await _db!.rawQuery('''
      SELECT COUNT(*) as group_count, SUM(cnt) as file_count
      FROM (
        SELECT $_colTmdbId, COUNT(*) as cnt
        FROM $_tableMetadata
        WHERE $_colTmdbId IS NOT NULL
        GROUP BY $_colTmdbId
        HAVING cnt > 1
      )
    ''');

    final tmdbGroups = (tmdbResult.first['group_count'] as int?) ?? 0;
    final tmdbFiles = (tmdbResult.first['file_count'] as int?) ?? 0;

    // 标题+年份重复统计（无 TMDB ID）
    final titleYearResult = await _db!.rawQuery('''
      SELECT COUNT(*) as group_count, SUM(cnt) as file_count
      FROM (
        SELECT $_colTitle, $_colYear, COUNT(*) as cnt
        FROM $_tableMetadata
        WHERE $_colTmdbId IS NULL
          AND $_colTitle IS NOT NULL
          AND $_colTitle != ''
          AND $_colYear IS NOT NULL
        GROUP BY $_colTitle, $_colYear
        HAVING cnt > 1
      )
    ''');

    final titleYearGroups = (titleYearResult.first['group_count'] as int?) ?? 0;
    final titleYearFiles = (titleYearResult.first['file_count'] as int?) ?? 0;

    return VideoDuplicateStats(
      tmdbIdGroups: tmdbGroups,
      tmdbIdFiles: tmdbFiles,
      titleYearGroups: titleYearGroups,
      titleYearFiles: titleYearFiles,
    );
  }

  /// 批量删除视频记录
  ///
  /// [keys] 要删除的视频唯一键列表，格式为 "sourceId_filePath"
  Future<int> deleteByKeys(List<String> keys) async {
    if (!_initialized) await init();
    if (keys.isEmpty) return 0;

    var deleted = 0;
    for (final key in keys) {
      final parts = key.split('_');
      if (parts.length >= 2) {
        final sourceId = parts.first;
        final filePath = parts.skip(1).join('_');
        deleted += await _db!.delete(
          _tableMetadata,
          where: '$_colSourceId = ? AND $_colFilePath = ?',
          whereArgs: [sourceId, filePath],
        );
      }
    }

    return deleted;
  }
}

/// 重复视频统计数据
class VideoDuplicateStats {
  const VideoDuplicateStats({
    required this.tmdbIdGroups,
    required this.tmdbIdFiles,
    required this.titleYearGroups,
    required this.titleYearFiles,
  });

  /// TMDB ID 重复的组数
  final int tmdbIdGroups;

  /// TMDB ID 重复涉及的文件数
  final int tmdbIdFiles;

  /// 标题+年份重复的组数（无 TMDB ID）
  final int titleYearGroups;

  /// 标题+年份重复涉及的文件数
  final int titleYearFiles;

  /// 总重复组数
  int get totalGroups => tmdbIdGroups + titleYearGroups;

  /// 总重复文件数
  int get totalFiles => tmdbIdFiles + titleYearFiles;

  /// 是否有重复
  bool get hasDuplicates => totalGroups > 0;
}

/// 字幕索引实体
class SubtitleIndex {
  const SubtitleIndex({
    required this.sourceId,
    required this.videoPath,
    required this.subtitlePath,
    required this.fileName,
    required this.format,
    this.language,
  });

  /// 源ID
  final String sourceId;

  /// 关联的视频文件路径
  final String videoPath;

  /// 字幕文件路径
  final String subtitlePath;

  /// 字幕文件名
  final String fileName;

  /// 字幕格式 (srt, ass, vtt 等)
  final String format;

  /// 语言
  final String? language;
}

/// 电影系列
class MovieCollection {
  const MovieCollection({
    required this.id,
    required this.name,
    required this.movies,
  });

  final int id;
  final String name;
  final List<VideoMetadata> movies;

  /// 系列中电影数量
  int get movieCount => movies.length;

  /// 代表电影（第一部）
  VideoMetadata? get representative => movies.isNotEmpty ? movies.first : null;

  /// 系列海报（优先使用 TMDB 系列专属海报，否则使用第一部电影的海报）
  String? get posterUrl {
    // 优先使用系列专属海报
    for (final movie in movies) {
      if (movie.collectionPosterUrl != null &&
          movie.collectionPosterUrl!.isNotEmpty) {
        return movie.collectionPosterUrl;
      }
    }
    // 否则使用代表电影的海报
    return representative?.posterUrl;
  }

  /// 系列背景图（优先使用系列专属背景图，否则使用评分最高的电影的背景图）
  String? get backdropUrl {
    if (movies.isEmpty) return null;
    // 优先使用系列专属背景图
    for (final movie in movies) {
      if (movie.collectionBackdropUrl != null &&
          movie.collectionBackdropUrl!.isNotEmpty) {
        return movie.collectionBackdropUrl;
      }
    }
    // 否则使用评分最高的电影的背景图
    final sortedByRating = List<VideoMetadata>.from(movies)
      ..sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));
    return sortedByRating.first.backdropUrl;
  }
}

/// TV 剧集分组行数据（从聚合表读取）
class TvShowGroupRow {
  const TvShowGroupRow({
    required this.id,
    required this.groupKey,
    this.tmdbId,
    required this.title,
    required this.normalizedTitle,
    this.originalTitle,
    this.year,
    this.overview,
    this.posterUrl,
    this.backdropUrl,
    this.rating,
    this.genres,
    required this.seasonCount,
    required this.episodeCount,
    this.representativeRowid,
    this.localPosterUrl,
  });

  final int id;
  final String groupKey;
  final int? tmdbId;
  final String title;
  final String normalizedTitle;
  final String? originalTitle;
  final int? year;
  final String? overview;
  final String? posterUrl;
  final String? backdropUrl;
  final double? rating;
  final String? genres;
  final int seasonCount;
  final int episodeCount;
  final int? representativeRowid;
  final String? localPosterUrl; // 本地海报路径（NAS 路径或 file://）

  /// 获取类型列表
  List<String> get genreList =>
      genres?.split(',').map((e) => e.trim()).toList() ?? [];

  /// 显示用的海报 URL（优先本地缓存）
  String? get displayPosterUrl => localPosterUrl ?? posterUrl;

  /// 显示用的背景 URL
  String? get displayBackdropUrl => backdropUrl;
}

/// 电影系列分组行数据（从聚合表读取）
class MovieCollectionGroupRow {
  const MovieCollectionGroupRow({
    required this.id,
    this.tmdbCollectionId,
    required this.name,
    this.posterUrl,
    this.backdropUrl,
    this.overview,
    required this.movieCount,
  });

  final int id;
  final int? tmdbCollectionId;
  final String name;
  final String? posterUrl;
  final String? backdropUrl;
  final String? overview;
  final int movieCount;
}

/// 刮削统计信息
class ScrapeStats {
  const ScrapeStats({
    required this.total,
    required this.pending,
    required this.scraping,
    required this.completed,
    required this.failed,
    required this.skipped,
    required this.movies,
    required this.tvShows,
  });

  final int total;
  final int pending;
  final int scraping;
  final int completed;
  final int failed;
  final int skipped;
  final int movies;
  final int tvShows;

  /// 已处理的数量（完成+失败+跳过）
  int get processed => completed + failed + skipped;

  /// 进度百分比 (0-1)
  double get progress => total > 0 ? processed / total : 0;

  /// 是否全部完成
  bool get isAllDone => pending == 0 && scraping == 0;
}

/// 扫描进度项
class ScanProgressItem {
  const ScanProgressItem({
    required this.sourceId,
    required this.path,
    required this.rootPath,
    required this.status,
    this.videoCount = 0,
    this.lastScanned,
    this.dirModifiedTime,
  });

  /// 源ID
  final String sourceId;

  /// 目录路径
  final String path;

  /// 根目录路径
  final String rootPath;

  /// 扫描状态: 0=pending, 1=scanning, 2=completed
  final int status;

  /// 该目录发现的视频数量
  final int videoCount;

  /// 最后扫描时间
  final DateTime? lastScanned;

  /// 目录的修改时间（用于增量同步检测变化）
  final DateTime? dirModifiedTime;

  /// 是否待扫描
  bool get isPending => status == VideoDatabaseService.scanStatusPending;

  /// 是否正在扫描
  bool get isScanning => status == VideoDatabaseService.scanStatusScanning;

  /// 是否已完成
  bool get isCompleted => status == VideoDatabaseService.scanStatusCompleted;
}

/// 扫描进度统计
class ScanProgressStats {
  const ScanProgressStats({
    required this.totalDirectories,
    required this.completedDirectories,
    required this.scanningDirectories,
    required this.totalVideosFound,
  });

  /// 总目录数
  final int totalDirectories;

  /// 已完成目录数
  final int completedDirectories;

  /// 正在扫描的目录数
  final int scanningDirectories;

  /// 已发现的视频总数
  final int totalVideosFound;

  /// 待扫描目录数
  int get pendingDirectories =>
      totalDirectories - completedDirectories - scanningDirectories;

  /// 进度百分比 (0-1)
  double get progress =>
      totalDirectories > 0 ? completedDirectories / totalDirectories : 0;

  /// 是否全部完成
  bool get isAllDone =>
      totalDirectories > 0 && completedDirectories == totalDirectories;

  /// 是否有未完成的扫描
  bool get hasUnfinished => pendingDirectories > 0 || scanningDirectories > 0;
}

/// 增量同步统计
class IncrementalSyncStats {
  const IncrementalSyncStats({
    required this.totalDirectories,
    required this.directoriesWithMtime,
    required this.totalVideos,
    required this.supportsIncrementalSync,
  });

  /// 总目录数
  final int totalDirectories;

  /// 有修改时间记录的目录数
  final int directoriesWithMtime;

  /// 视频总数
  final int totalVideos;

  /// 是否支持增量同步（需要有修改时间记录）
  final bool supportsIncrementalSync;
}

/// 增量同步结果
class IncrementalSyncResult {
  const IncrementalSyncResult({
    required this.addedFiles,
    required this.deletedFiles,
    required this.changedFiles,
    required this.unchangedDirectories,
    required this.changedDirectories,
    required this.newDirectories,
    required this.deletedDirectories,
  });

  /// 新增的文件数
  final int addedFiles;

  /// 删除的文件数
  final int deletedFiles;

  /// 变化的文件数（内容可能更新）
  final int changedFiles;

  /// 未变化的目录数
  final int unchangedDirectories;

  /// 有变化的目录数
  final int changedDirectories;

  /// 新增的目录数
  final int newDirectories;

  /// 删除的目录数
  final int deletedDirectories;

  /// 是否有任何变化
  bool get hasChanges =>
      addedFiles > 0 ||
      deletedFiles > 0 ||
      changedFiles > 0 ||
      newDirectories > 0 ||
      deletedDirectories > 0;

  /// 总的变化文件数
  int get totalChangedFiles => addedFiles + deletedFiles + changedFiles;
}
