import 'dart:io';

import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/music/data/services/music_cover_cache_service.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// 音乐曲目实体（用于 SQLite 存储）
class MusicTrackEntity {
  const MusicTrackEntity({
    required this.sourceId,
    required this.filePath,
    required this.fileName,
    this.title,
    this.artist,
    this.album,
    this.duration,
    this.trackNumber,
    this.year,
    this.genre,
    this.coverPath,
    this.size,
    this.modifiedTime,
    this.lastUpdated,
  });

  final String sourceId;
  final String filePath;
  final String fileName;
  final String? title;
  final String? artist;
  final String? album;
  final int? duration; // 毫秒
  final int? trackNumber;
  final int? year;
  final String? genre;
  final String? coverPath; // 封面文件路径（磁盘缓存）
  final int? size;
  final DateTime? modifiedTime;
  final DateTime? lastUpdated;

  String get uniqueKey => '${sourceId}_$filePath';

  /// 显示的标题（优先使用元数据标题）
  String get displayTitle {
    if (title != null && title!.isNotEmpty) return title!;
    final nameWithoutExt = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
    final match = RegExp(r'^.+?\s*[-–—]\s*(.+)$').firstMatch(nameWithoutExt);
    return match?.group(1)?.trim() ?? nameWithoutExt;
  }

  /// 显示的艺术家
  String get displayArtist {
    if (artist != null && artist!.isNotEmpty) return artist!;
    final nameWithoutExt = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
    final match = RegExp(r'^(.+?)\s*[-–—]\s*.+$').firstMatch(nameWithoutExt);
    return match?.group(1)?.trim() ?? appL10n.musicUnknownArtist;
  }

  /// 显示的专辑
  String get displayAlbum => album?.isNotEmpty ?? false ? album! : appL10n.musicUnknownAlbum;

  /// 格式化时长
  String get durationText {
    if (duration == null || duration! <= 0) return '--:--';
    // 过滤异常值：超过 24 小时的时长视为无效
    // 86400000 毫秒 = 24 小时
    if (duration! > 86400000) return '--:--';
    final totalSeconds = duration! ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// 格式化文件大小
  String get displaySize {
    final s = size ?? 0;
    if (s < 1024) return '$s B';
    if (s < 1024 * 1024) return '${(s / 1024).toStringAsFixed(1)} KB';
    return '${(s / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// 获取文件夹名称
  String get folderName {
    final parts = filePath.split('/');
    if (parts.length > 1) {
      return parts[parts.length - 2];
    }
    return appL10n.musicRootFolder;
  }

  /// 显示封面路径
  /// 优先使用数据库中的 coverPath，如果无效则动态计算
  /// 仿照影视模块的 displayPosterUrl 实现
  String? get displayCoverPath {
    // 1. 如果有存储的路径且文件存在，直接使用
    if (coverPath != null && coverPath!.isNotEmpty) {
      if (File(coverPath!).existsSync()) {
        return coverPath;
      }
    }
    // 2. 动态尝试从缓存服务获取
    return MusicCoverCacheService().getCachedCoverPathSync(uniqueKey);
  }

  MusicTrackEntity copyWith({
    String? sourceId,
    String? filePath,
    String? fileName,
    String? title,
    String? artist,
    String? album,
    int? duration,
    int? trackNumber,
    int? year,
    String? genre,
    Object? coverPath = _sentinel,
    int? size,
    DateTime? modifiedTime,
    DateTime? lastUpdated,
  }) =>
      MusicTrackEntity(
        sourceId: sourceId ?? this.sourceId,
        filePath: filePath ?? this.filePath,
        fileName: fileName ?? this.fileName,
        title: title ?? this.title,
        artist: artist ?? this.artist,
        album: album ?? this.album,
        duration: duration ?? this.duration,
        trackNumber: trackNumber ?? this.trackNumber,
        year: year ?? this.year,
        genre: genre ?? this.genre,
        coverPath: coverPath == _sentinel ? this.coverPath : coverPath as String?,
        size: size ?? this.size,
        modifiedTime: modifiedTime ?? this.modifiedTime,
        lastUpdated: lastUpdated ?? this.lastUpdated,
      );
}

/// 用于 copyWith 方法中区分 null 和未提供参数的哨兵值
const _sentinel = Object();

/// 音乐数据库服务 - 使用 SQLite 支持大规模数据和索引查询
class MusicDatabaseService {
  factory MusicDatabaseService() => _instance ??= MusicDatabaseService._();
  MusicDatabaseService._();

  static MusicDatabaseService? _instance;

  Database? _db;
  bool _initialized = false;

  // 表名和列名常量
  static const String _tableMetadata = 'music_metadata';
  static const String _colId = 'id';
  static const String _colSourceId = 'source_id';
  static const String _colFilePath = 'file_path';
  static const String _colFileName = 'file_name';
  static const String _colTitle = 'title';
  static const String _colArtist = 'artist';
  static const String _colAlbum = 'album';
  static const String _colDuration = 'duration';
  static const String _colTrackNumber = 'track_number';
  static const String _colYear = 'year';
  static const String _colGenre = 'genre';
  static const String _colCoverPath = 'cover_path';
  static const String _colSize = 'size';
  static const String _colModifiedTime = 'modified_time';
  static const String _colLastUpdated = 'last_updated';

  /// 初始化数据库
  Future<void> init() async {
    if (_initialized) return;

    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      final dbPath = join(documentsDir.path, 'music_metadata.db');

      _db = await openDatabase(
        dbPath,
        version: 1,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        onConfigure: _onConfigure,
      );

      _initialized = true;
      logger.i('MusicDatabaseService: 数据库初始化完成');
    } catch (e, st) {
      AppError.handle(e, st, 'MusicDatabaseService.init');
      rethrow;
    }
  }

  /// 数据库配置 - 启用 WAL 模式和安全设置
  Future<void> _onConfigure(Database db) async {
    // 使用 rawQuery 获取 PRAGMA 结果，避免 iOS 上 "not an error" 异常
    await db.rawQuery('PRAGMA journal_mode=WAL');
    await db.rawQuery('PRAGMA synchronous=NORMAL');
    await db.rawQuery('PRAGMA busy_timeout=5000');
    await db.rawQuery('PRAGMA foreign_keys=ON');
    logger.d('MusicDatabaseService: 数据库配置完成 (WAL模式)');
  }

  /// 创建表和索引
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_tableMetadata (
        $_colId INTEGER PRIMARY KEY AUTOINCREMENT,
        $_colSourceId TEXT NOT NULL,
        $_colFilePath TEXT NOT NULL,
        $_colFileName TEXT NOT NULL,
        $_colTitle TEXT,
        $_colArtist TEXT,
        $_colAlbum TEXT,
        $_colDuration INTEGER,
        $_colTrackNumber INTEGER,
        $_colYear INTEGER,
        $_colGenre TEXT,
        $_colCoverPath TEXT,
        $_colSize INTEGER,
        $_colModifiedTime INTEGER,
        $_colLastUpdated INTEGER,
        UNIQUE($_colSourceId, $_colFilePath)
      )
    ''');

    // 创建索引 - 用于快速查询
    await db.execute(
        'CREATE INDEX idx_artist ON $_tableMetadata($_colArtist)');
    await db.execute(
        'CREATE INDEX idx_album ON $_tableMetadata($_colAlbum)');
    await db.execute(
        'CREATE INDEX idx_year ON $_tableMetadata($_colYear)');
    await db.execute(
        'CREATE INDEX idx_genre ON $_tableMetadata($_colGenre)');
    await db.execute(
        'CREATE INDEX idx_source_id ON $_tableMetadata($_colSourceId)');
    await db.execute(
        'CREATE INDEX idx_last_updated ON $_tableMetadata($_colLastUpdated DESC)');
    await db.execute(
        'CREATE INDEX idx_modified_time ON $_tableMetadata($_colModifiedTime DESC)');
    // 复合索引 - 用于艺术家+专辑查询
    await db.execute(
        'CREATE INDEX idx_artist_album ON $_tableMetadata($_colArtist, $_colAlbum)');

    logger.i('MusicDatabaseService: 表和索引创建完成');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    logger.i('MusicDatabaseService: 数据库升级 $oldVersion -> $newVersion');
  }

  /// 插入或更新元数据
  Future<void> upsert(MusicTrackEntity metadata) async {
    if (!_initialized) await init();

    await _db!.insert(
      _tableMetadata,
      _toRow(metadata),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 批量插入或更新
  ///
  /// 使用事务保护确保原子性
  Future<void> upsertBatch(List<MusicTrackEntity> metadataList) async {
    if (!_initialized) await init();
    if (metadataList.isEmpty) return;

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
    logger.d('MusicDatabaseService: 批量插入 ${metadataList.length} 条');
  }

  /// 根据 sourceId 和 filePath 获取元数据
  Future<MusicTrackEntity?> get(String sourceId, String filePath) async {
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
  Future<Map<String, MusicTrackEntity>> getBatch(
      List<({String sourceId, String filePath})> keys) async {
    if (!_initialized) await init();
    if (keys.isEmpty) return {};

    final result = <String, MusicTrackEntity>{};
    const batchSize = 100;

    for (var i = 0; i < keys.length; i += batchSize) {
      final batchKeys = keys.skip(i).take(batchSize).toList();
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

  /// 根据艺术家获取曲目（分页）
  Future<List<MusicTrackEntity>> getByArtist(
    String artist, {
    int limit = 50,
    int offset = 0,
  }) async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tableMetadata,
      where: '$_colArtist = ?',
      whereArgs: [artist],
      orderBy: '$_colAlbum, $_colTrackNumber',
      limit: limit,
      offset: offset,
    );

    return results.map(_fromRow).toList();
  }

  /// 根据专辑获取曲目（分页）
  Future<List<MusicTrackEntity>> getByAlbum(
    String album, {
    int limit = 50,
    int offset = 0,
  }) async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tableMetadata,
      where: '$_colAlbum = ?',
      whereArgs: [album],
      orderBy: '$_colTrackNumber, $_colFileName',
      limit: limit,
      offset: offset,
    );

    return results.map(_fromRow).toList();
  }

  /// 根据年份获取曲目（分页）
  Future<List<MusicTrackEntity>> getByYear(
    int year, {
    int limit = 50,
    int offset = 0,
  }) async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tableMetadata,
      where: '$_colYear = ?',
      whereArgs: [year],
      orderBy: '$_colArtist, $_colAlbum',
      limit: limit,
      offset: offset,
    );

    return results.map(_fromRow).toList();
  }

  /// 根据流派获取曲目（分页）
  Future<List<MusicTrackEntity>> getByGenre(
    String genre, {
    int limit = 50,
    int offset = 0,
  }) async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tableMetadata,
      where: '$_colGenre LIKE ?',
      whereArgs: ['%$genre%'],
      orderBy: '$_colArtist, $_colAlbum',
      limit: limit,
      offset: offset,
    );

    return results.map(_fromRow).toList();
  }

  /// 根据文件夹路径获取曲目
  Future<List<MusicTrackEntity>> getByFolder(
    String folderPath, {
    int limit = 50,
    int offset = 0,
  }) async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tableMetadata,
      where: '$_colFilePath LIKE ?',
      whereArgs: ['$folderPath/%'],
      orderBy: _colFileName,
      limit: limit,
      offset: offset,
    );

    return results.map(_fromRow).toList();
  }

  /// 获取最近添加的曲目（分页）
  ///
  /// [enabledPaths] 启用的路径列表，如果提供则只返回这些路径下的音乐
  Future<List<MusicTrackEntity>> getRecentlyAdded({
    int limit = 50,
    int offset = 0,
    List<({String sourceId, String path})>? enabledPaths,
  }) async {
    if (!_initialized) await init();

    final pathFilter = _buildPathFilter(enabledPaths);

    if (pathFilter.where.isEmpty) {
      final results = await _db!.query(
        _tableMetadata,
        orderBy: '$_colModifiedTime DESC',
        limit: limit,
        offset: offset,
      );
      return results.map(_fromRow).toList();
    }

    final sql = '''
      SELECT * FROM $_tableMetadata${pathFilter.where}
      ORDER BY $_colModifiedTime DESC
      LIMIT ? OFFSET ?
    ''';
    final results = await _db!.rawQuery(sql, [...pathFilter.args, limit, offset]);
    return results.map(_fromRow).toList();
  }

  /// 分页获取所有曲目
  ///
  /// [enabledPaths] 启用的路径列表，如果提供则只返回这些路径下的音乐
  Future<List<MusicTrackEntity>> getPage({
    int limit = 50,
    int offset = 0,
    String? orderBy,
    List<({String sourceId, String path})>? enabledPaths,
  }) async {
    if (!_initialized) await init();

    final pathFilter = _buildPathFilter(enabledPaths);
    final orderClause = orderBy ?? '$_colArtist, $_colAlbum, $_colTrackNumber';

    if (pathFilter.where.isEmpty) {
      final results = await _db!.query(
        _tableMetadata,
        orderBy: orderClause,
        limit: limit,
        offset: offset,
      );
      return results.map(_fromRow).toList();
    }

    final sql = '''
      SELECT * FROM $_tableMetadata${pathFilter.where}
      ORDER BY $orderClause
      LIMIT ? OFFSET ?
    ''';
    final results = await _db!.rawQuery(sql, [...pathFilter.args, limit, offset]);
    return results.map(_fromRow).toList();
  }

  /// 搜索曲目
  ///
  /// [enabledPaths] 启用的路径列表，如果提供则只在这些路径下搜索
  Future<List<MusicTrackEntity>> search(
    String query, {
    int limit = 50,
    int offset = 0,
    List<({String sourceId, String path})>? enabledPaths,
  }) async {
    if (!_initialized) await init();
    if (query.isEmpty) return [];

    final searchPattern = '%$query%';
    final pathFilter = _buildPathFilter(enabledPaths);

    final searchCondition = '($_colTitle LIKE ? OR $_colArtist LIKE ? OR $_colAlbum LIKE ? OR $_colFileName LIKE ?)';
    final searchArgs = [searchPattern, searchPattern, searchPattern, searchPattern];

    if (pathFilter.where.isEmpty) {
      final results = await _db!.query(
        _tableMetadata,
        where: searchCondition,
        whereArgs: searchArgs,
        orderBy: '$_colArtist, $_colAlbum',
        limit: limit,
        offset: offset,
      );
      return results.map(_fromRow).toList();
    }

    final sql = '''
      SELECT * FROM $_tableMetadata
      WHERE $searchCondition${pathFilter.andWhere}
      ORDER BY $_colArtist, $_colAlbum
      LIMIT ? OFFSET ?
    ''';
    final results = await _db!.rawQuery(sql, [...searchArgs, ...pathFilter.args, limit, offset]);
    return results.map(_fromRow).toList();
  }

  /// 获取所有唯一艺术家（带曲目数量）
  ///
  /// [enabledPaths] 启用的路径列表，如果提供则只统计这些路径下的音乐
  Future<List<({String artist, int count})>> getArtists({
    List<({String sourceId, String path})>? enabledPaths,
  }) async {
    if (!_initialized) await init();

    final pathFilter = _buildPathFilter(enabledPaths);

    final sql = '''
      SELECT $_colArtist as artist, COUNT(*) as count
      FROM $_tableMetadata
      WHERE $_colArtist IS NOT NULL AND $_colArtist != ''${pathFilter.andWhere}
      GROUP BY $_colArtist
      ORDER BY $_colArtist
    ''';
    final results = await _db!.rawQuery(sql, pathFilter.args);

    return results
        .map((r) => (artist: r['artist']! as String, count: r['count']! as int))
        .toList();
  }

  /// 获取所有唯一专辑（带艺术家和曲目数量）
  ///
  /// [enabledPaths] 启用的路径列表，如果提供则只统计这些路径下的音乐
  Future<List<({String album, String? artist, int count, String? coverPath})>> getAlbums({
    List<({String sourceId, String path})>? enabledPaths,
  }) async {
    if (!_initialized) await init();

    final pathFilter = _buildPathFilter(enabledPaths);

    final sql = '''
      SELECT $_colAlbum as album, $_colArtist as artist, COUNT(*) as count,
             (SELECT $_colCoverPath FROM $_tableMetadata m2
              WHERE m2.$_colAlbum = $_tableMetadata.$_colAlbum
              AND m2.$_colCoverPath IS NOT NULL LIMIT 1) as cover_path
      FROM $_tableMetadata
      WHERE $_colAlbum IS NOT NULL AND $_colAlbum != ''${pathFilter.andWhere}
      GROUP BY $_colAlbum
      ORDER BY $_colAlbum
    ''';
    final results = await _db!.rawQuery(sql, pathFilter.args);

    return results
        .map((r) => (
              album: r['album']! as String,
              artist: r['artist'] as String?,
              count: r['count']! as int,
              coverPath: r['cover_path'] as String?,
            ))
        .toList();
  }

  /// 获取所有唯一年份（带曲目数量）
  ///
  /// [enabledPaths] 启用的路径列表，如果提供则只统计这些路径下的音乐
  Future<List<({int year, int count})>> getYears({
    List<({String sourceId, String path})>? enabledPaths,
  }) async {
    if (!_initialized) await init();

    final pathFilter = _buildPathFilter(enabledPaths);

    final sql = '''
      SELECT $_colYear as year, COUNT(*) as count
      FROM $_tableMetadata
      WHERE $_colYear IS NOT NULL AND $_colYear > 1900${pathFilter.andWhere}
      GROUP BY $_colYear
      ORDER BY $_colYear DESC
    ''';
    final results = await _db!.rawQuery(sql, pathFilter.args);

    return results
        .map((r) => (year: r['year']! as int, count: r['count']! as int))
        .toList();
  }

  /// 获取所有唯一流派（带曲目数量）
  ///
  /// [enabledPaths] 启用的路径列表，如果提供则只统计这些路径下的音乐
  Future<List<({String genre, int count})>> getGenres({
    List<({String sourceId, String path})>? enabledPaths,
  }) async {
    if (!_initialized) await init();

    final pathFilter = _buildPathFilter(enabledPaths);

    final sql = '''
      SELECT $_colGenre as genre, COUNT(*) as count
      FROM $_tableMetadata
      WHERE $_colGenre IS NOT NULL AND $_colGenre != ''${pathFilter.andWhere}
      GROUP BY $_colGenre
      ORDER BY count DESC
    ''';
    final results = await _db!.rawQuery(sql, pathFilter.args);

    return results
        .map((r) => (genre: r['genre']! as String, count: r['count']! as int))
        .toList();
  }

  /// 获取所有唯一文件夹
  ///
  /// [enabledPaths] 启用的路径列表，如果提供则只统计这些路径下的音乐
  Future<List<({String folder, int count})>> getFolders({
    List<({String sourceId, String path})>? enabledPaths,
  }) async {
    if (!_initialized) await init();

    final pathFilter = _buildPathFilter(enabledPaths);

    // 使用 SQLite 的字符串函数提取文件夹路径
    final sql = '''
      SELECT
        SUBSTR($_colFilePath, 1, LENGTH($_colFilePath) - LENGTH($_colFileName) - 1) as folder,
        COUNT(*) as count
      FROM $_tableMetadata${pathFilter.where}
      GROUP BY folder
      ORDER BY folder
    ''';
    final results = await _db!.rawQuery(sql, pathFilter.args);

    return results
        .where((r) => r['folder'] != null && (r['folder']! as String).isNotEmpty)
        .map((r) => (folder: r['folder']! as String, count: r['count']! as int))
        .toList();
  }

  /// 获取统计信息
  ///
  /// [enabledPaths] 启用的路径列表，如果提供则只统计这些路径下的音乐
  Future<Map<String, dynamic>> getStats({
    List<({String sourceId, String path})>? enabledPaths,
  }) async {
    if (!_initialized) await init();

    final pathFilter = _buildPathFilter(enabledPaths);

    final totalCount = Sqflite.firstIntValue(await _db!.rawQuery(
        'SELECT COUNT(*) FROM $_tableMetadata${pathFilter.where}',
        pathFilter.args));

    final artistCount = Sqflite.firstIntValue(await _db!.rawQuery(
        'SELECT COUNT(DISTINCT $_colArtist) FROM $_tableMetadata WHERE $_colArtist IS NOT NULL${pathFilter.andWhere}',
        pathFilter.args));

    final albumCount = Sqflite.firstIntValue(await _db!.rawQuery(
        'SELECT COUNT(DISTINCT $_colAlbum) FROM $_tableMetadata WHERE $_colAlbum IS NOT NULL${pathFilter.andWhere}',
        pathFilter.args));

    final genreCount = Sqflite.firstIntValue(await _db!.rawQuery(
        'SELECT COUNT(DISTINCT $_colGenre) FROM $_tableMetadata WHERE $_colGenre IS NOT NULL${pathFilter.andWhere}',
        pathFilter.args));

    final yearCount = Sqflite.firstIntValue(await _db!.rawQuery(
        'SELECT COUNT(DISTINCT $_colYear) FROM $_tableMetadata WHERE $_colYear IS NOT NULL${pathFilter.andWhere}',
        pathFilter.args));

    // 计算文件夹数量
    final folderCount = Sqflite.firstIntValue(await _db!.rawQuery('''
      SELECT COUNT(DISTINCT SUBSTR($_colFilePath, 1, LENGTH($_colFilePath) - LENGTH($_colFileName) - 1))
      FROM $_tableMetadata${pathFilter.where}
    ''', pathFilter.args));

    final totalDuration = Sqflite.firstIntValue(await _db!.rawQuery(
            'SELECT SUM($_colDuration) FROM $_tableMetadata${pathFilter.where}',
            pathFilter.args)) ??
        0;

    return {
      'total': totalCount ?? 0,
      'artists': artistCount ?? 0,
      'albums': albumCount ?? 0,
      'genres': genreCount ?? 0,
      'years': yearCount ?? 0,
      'folders': folderCount ?? 0,
      'totalDuration': totalDuration,
    };
  }

  /// 获取总数量
  ///
  /// [sourceId] 可选，按源ID筛选
  /// [pathPrefix] 可选，按路径前缀筛选（需要同时提供 sourceId）
  Future<int> getCount({
    String? sourceId,
    String? pathPrefix,
  }) async {
    if (!_initialized) await init();

    // 构建路径过滤条件
    var whereClause = '';
    final args = <Object>[];

    if (sourceId != null && pathPrefix != null) {
      whereClause = ' WHERE $_colSourceId = ? AND $_colFilePath LIKE ?';
      args.addAll([sourceId, '$pathPrefix%']);
    } else if (sourceId != null) {
      whereClause = ' WHERE $_colSourceId = ?';
      args.add(sourceId);
    }

    return Sqflite.firstIntValue(
            await _db!.rawQuery('SELECT COUNT(*) FROM $_tableMetadata$whereClause', args)) ??
        0;
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

    final count = await _db!.delete(
      _tableMetadata,
      where: '$_colSourceId = ?',
      whereArgs: [sourceId],
    );
    logger.i('MusicDatabaseService: 已删除 $count 首音乐 (sourceId: $sourceId)');
    return count;
  }

  /// 根据 sourceId 和路径前缀删除（用于移除文件夹）
  Future<int> deleteByPath(String sourceId, String pathPrefix) async {
    if (!_initialized) await init();

    final count = await _db!.delete(
      _tableMetadata,
      where: '$_colSourceId = ? AND $_colFilePath LIKE ?',
      whereArgs: [sourceId, '$pathPrefix%'],
    );
    logger.i('MusicDatabaseService: 已删除 $count 首音乐 (sourceId: $sourceId, path: $pathPrefix)');
    return count;
  }

  /// 清空所有数据
  Future<void> clearAll() async {
    if (!_initialized) await init();
    await _db!.delete(_tableMetadata);
    logger.i('MusicDatabaseService: 已清空所有数据');
  }

  /// 安全关闭数据库
  ///
  /// 执行 WAL checkpoint 确保数据安全持久化
  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      try {
        await _db!.execute('PRAGMA wal_checkpoint(TRUNCATE)');
        logger.d('MusicDatabaseService: WAL checkpoint 完成');
      } on Exception catch (e, st) {
        AppError.ignore(e, st, 'WAL checkpoint 失败，不影响关闭流程');
      }
      await _db!.close();
      _db = null;
      _initialized = false;
      logger.i('MusicDatabaseService: 数据库已安全关闭');
    }
  }

  /// 构建路径过滤条件
  ///
  /// 返回 WHERE 子句和 AND 子句，用于 SQL 查询
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

  Map<String, dynamic> _toRow(MusicTrackEntity m) => {
        _colSourceId: m.sourceId,
        _colFilePath: m.filePath,
        _colFileName: m.fileName,
        _colTitle: m.title,
        _colArtist: m.artist,
        _colAlbum: m.album,
        _colDuration: m.duration,
        _colTrackNumber: m.trackNumber,
        _colYear: m.year,
        _colGenre: m.genre,
        _colCoverPath: m.coverPath,
        _colSize: m.size,
        _colModifiedTime: m.modifiedTime?.millisecondsSinceEpoch,
        _colLastUpdated: m.lastUpdated?.millisecondsSinceEpoch,
      };

  MusicTrackEntity _fromRow(Map<String, dynamic> row) => MusicTrackEntity(
        sourceId: row[_colSourceId] as String,
        filePath: row[_colFilePath] as String,
        fileName: row[_colFileName] as String,
        title: row[_colTitle] as String?,
        artist: row[_colArtist] as String?,
        album: row[_colAlbum] as String?,
        duration: row[_colDuration] as int?,
        trackNumber: row[_colTrackNumber] as int?,
        year: row[_colYear] as int?,
        genre: row[_colGenre] as String?,
        coverPath: row[_colCoverPath] as String?,
        size: row[_colSize] as int?,
        modifiedTime: row[_colModifiedTime] != null
            ? DateTime.fromMillisecondsSinceEpoch(row[_colModifiedTime] as int)
            : null,
        lastUpdated: row[_colLastUpdated] != null
            ? DateTime.fromMillisecondsSinceEpoch(row[_colLastUpdated] as int)
            : null,
      );
}
