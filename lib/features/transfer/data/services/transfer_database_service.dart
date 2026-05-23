import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/transfer/domain/entities/transfer_task.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// 传输任务数据库服务
class TransferDatabaseService {
  factory TransferDatabaseService() => _instance ??= TransferDatabaseService._();
  TransferDatabaseService._();

  static TransferDatabaseService? _instance;

  Database? _db;
  bool _initialized = false;

  static const String _tableTasks = 'transfer_tasks';
  static const String _tableUploadedMarks = 'uploaded_marks';
  static const String _tableCachedMedia = 'cached_media';

  /// 初始化数据库
  Future<void> init() async {
    if (_initialized) return;

    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      final dbPath = p.join(documentsDir.path, 'transfer.db');

      _db = await openDatabase(
        dbPath,
        version: 1,
        onCreate: _onCreate,
      );

      _initialized = true;
      logger.i('TransferDatabaseService: 数据库初始化完成');
    } catch (e, st) {
      AppError.handle(e, st, 'TransferDatabaseService.init');
      rethrow;
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    // 传输任务表
    await db.execute('''
      CREATE TABLE $_tableTasks (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        media_type TEXT NOT NULL,
        source_id TEXT NOT NULL,
        source_path TEXT NOT NULL,
        file_name TEXT NOT NULL,
        file_size INTEGER NOT NULL,
        target_source_id TEXT,
        target_path TEXT NOT NULL,
        status TEXT NOT NULL,
        transferred_bytes INTEGER DEFAULT 0,
        error TEXT,
        created_at INTEGER NOT NULL,
        completed_at INTEGER,
        asset_id TEXT,
        song_id INTEGER,
        thumbnail_path TEXT
      )
    ''');

    // 已上传标记表
    await db.execute('''
      CREATE TABLE $_tableUploadedMarks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        local_path TEXT NOT NULL,
        target_source_id TEXT NOT NULL,
        target_path TEXT NOT NULL,
        uploaded_at INTEGER NOT NULL,
        UNIQUE(local_path, target_source_id)
      )
    ''');

    // 缓存媒体表
    await db.execute('''
      CREATE TABLE $_tableCachedMedia (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source_id TEXT NOT NULL,
        source_path TEXT NOT NULL,
        media_type TEXT NOT NULL,
        file_name TEXT NOT NULL,
        file_size INTEGER NOT NULL,
        cache_path TEXT NOT NULL,
        cached_at INTEGER NOT NULL,
        last_accessed INTEGER,
        title TEXT,
        artist TEXT,
        album TEXT,
        thumbnail_path TEXT,
        UNIQUE(source_id, source_path)
      )
    ''');

    // 创建索引
    await db.execute(
      'CREATE INDEX idx_tasks_status ON $_tableTasks (status)',
    );
    await db.execute(
      'CREATE INDEX idx_tasks_type ON $_tableTasks (type)',
    );
    await db.execute(
      'CREATE INDEX idx_uploaded_marks_local_path ON $_tableUploadedMarks (local_path)',
    );
    await db.execute(
      'CREATE INDEX idx_cached_media_source ON $_tableCachedMedia (source_id, source_path)',
    );
  }

  // ============ 传输任务操作 ============

  /// 插入任务
  Future<void> insertTask(TransferTask task) async {
    if (!_initialized) await init();
    await _db!.insert(_tableTasks, task.toMap());
  }

  /// 更新任务
  Future<void> updateTask(TransferTask task) async {
    if (!_initialized) await init();
    await _db!.update(
      _tableTasks,
      task.toMap(),
      where: 'id = ?',
      whereArgs: [task.id],
    );
  }

  /// 删除任务
  Future<void> deleteTask(String taskId) async {
    if (!_initialized) await init();
    await _db!.delete(
      _tableTasks,
      where: 'id = ?',
      whereArgs: [taskId],
    );
  }

  /// 获取活动任务（未完成的）
  Future<List<TransferTask>> getActiveTasks() async {
    if (!_initialized) await init();

    final maps = await _db!.query(
      _tableTasks,
      where: 'status NOT IN (?, ?)',
      whereArgs: [TransferStatus.completed.name, TransferStatus.cancelled.name],
      orderBy: 'created_at DESC',
    );

    return maps.map(TransferTask.fromMap).toList();
  }

  /// 获取所有任务
  Future<List<TransferTask>> getAllTasks({
    TransferType? type,
    int? limit,
    int? offset,
  }) async {
    if (!_initialized) await init();

    final maps = await _db!.query(
      _tableTasks,
      where: type != null ? 'type = ?' : null,
      whereArgs: type != null ? [type.name] : null,
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );

    return maps.map(TransferTask.fromMap).toList();
  }

  /// 获取任务数量
  Future<int> getTaskCount({TransferType? type, TransferStatus? status}) async {
    if (!_initialized) await init();

    final conditions = <String>[];
    final args = <dynamic>[];

    if (type != null) {
      conditions.add('type = ?');
      args.add(type.name);
    }
    if (status != null) {
      conditions.add('status = ?');
      args.add(status.name);
    }

    final where = conditions.isNotEmpty ? conditions.join(' AND ') : null;

    final result = await _db!.rawQuery(
      'SELECT COUNT(*) as count FROM $_tableTasks${where != null ? ' WHERE $where' : ''}',
      args,
    );

    return Sqflite.firstIntValue(result) ?? 0;
  }

  // ============ 已上传标记操作 ============

  /// 检查是否已上传
  Future<bool> isUploaded(String localPath, String targetSourceId) async {
    if (!_initialized) await init();

    final result = await _db!.query(
      _tableUploadedMarks,
      where: 'local_path = ? AND target_source_id = ?',
      whereArgs: [localPath, targetSourceId],
      limit: 1,
    );

    return result.isNotEmpty;
  }

  /// 标记已上传
  Future<void> markUploaded(
    String localPath,
    String targetSourceId,
    String targetPath,
  ) async {
    if (!_initialized) await init();

    await _db!.insert(
      _tableUploadedMarks,
      {
        'local_path': localPath,
        'target_source_id': targetSourceId,
        'target_path': targetPath,
        'uploaded_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 取消标记
  Future<void> unmarkUploaded(String localPath, String targetSourceId) async {
    if (!_initialized) await init();

    await _db!.delete(
      _tableUploadedMarks,
      where: 'local_path = ? AND target_source_id = ?',
      whereArgs: [localPath, targetSourceId],
    );
  }

  /// 获取已上传到指定目标的所有本地路径
  Future<List<String>> getUploadedPaths(String targetSourceId) async {
    if (!_initialized) await init();

    final maps = await _db!.query(
      _tableUploadedMarks,
      columns: ['local_path'],
      where: 'target_source_id = ?',
      whereArgs: [targetSourceId],
    );

    return maps.map((m) => m['local_path']! as String).toList();
  }

  /// 获取所有已上传标记
  Future<List<UploadedMark>> getAllUploadedMarks({
    String? targetSourceId,
  }) async {
    if (!_initialized) await init();

    final maps = await _db!.query(
      _tableUploadedMarks,
      where: targetSourceId != null ? 'target_source_id = ?' : null,
      whereArgs: targetSourceId != null ? [targetSourceId] : null,
      orderBy: 'uploaded_at DESC',
    );

    return maps.map(UploadedMark.fromMap).toList();
  }

  // ============ 缓存媒体操作 ============

  /// 记录缓存
  Future<void> recordCache(CachedMediaItem item) async {
    if (!_initialized) await init();

    await _db!.insert(
      _tableCachedMedia,
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 检查是否已缓存
  Future<bool> isCached(String sourceId, String sourcePath) async {
    if (!_initialized) await init();

    final result = await _db!.query(
      _tableCachedMedia,
      where: 'source_id = ? AND source_path = ?',
      whereArgs: [sourceId, sourcePath],
      limit: 1,
    );

    return result.isNotEmpty;
  }

  /// 获取缓存路径
  Future<String?> getCachePath(String sourceId, String sourcePath) async {
    if (!_initialized) await init();

    final result = await _db!.query(
      _tableCachedMedia,
      columns: ['cache_path'],
      where: 'source_id = ? AND source_path = ?',
      whereArgs: [sourceId, sourcePath],
      limit: 1,
    );

    if (result.isEmpty) return null;
    return result.first['cache_path'] as String?;
  }

  /// 删除缓存记录
  Future<void> deleteCache(String sourceId, String sourcePath) async {
    if (!_initialized) await init();

    await _db!.delete(
      _tableCachedMedia,
      where: 'source_id = ? AND source_path = ?',
      whereArgs: [sourceId, sourcePath],
    );
  }

  /// 获取所有缓存项
  Future<List<CachedMediaItem>> getCachedItems({
    String? mediaType,
    int? limit,
    int? offset,
  }) async {
    if (!_initialized) await init();

    final maps = await _db!.query(
      _tableCachedMedia,
      where: mediaType != null ? 'media_type = ?' : null,
      whereArgs: mediaType != null ? [mediaType] : null,
      orderBy: 'cached_at DESC',
      limit: limit,
      offset: offset,
    );

    return maps.map(CachedMediaItem.fromMap).toList();
  }

  /// 获取缓存总大小
  Future<int> getCacheSize({String? mediaType}) async {
    if (!_initialized) await init();

    final query = mediaType != null
        ? 'SELECT SUM(file_size) as total FROM $_tableCachedMedia WHERE media_type = ?'
        : 'SELECT SUM(file_size) as total FROM $_tableCachedMedia';

    final result = await _db!.rawQuery(
      query,
      mediaType != null ? [mediaType] : null,
    );

    return (result.first['total'] as int?) ?? 0;
  }

  /// 获取缓存数量
  Future<int> getCacheCount({String? mediaType}) async {
    if (!_initialized) await init();

    final result = await _db!.rawQuery(
      mediaType != null
          ? 'SELECT COUNT(*) as count FROM $_tableCachedMedia WHERE media_type = ?'
          : 'SELECT COUNT(*) as count FROM $_tableCachedMedia',
      mediaType != null ? [mediaType] : null,
    );

    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// 更新最后访问时间
  Future<void> updateLastAccessed(String sourceId, String sourcePath) async {
    if (!_initialized) await init();

    await _db!.update(
      _tableCachedMedia,
      {'last_accessed': DateTime.now().millisecondsSinceEpoch},
      where: 'source_id = ? AND source_path = ?',
      whereArgs: [sourceId, sourcePath],
    );
  }

  /// 清空所有缓存记录
  Future<void> clearAllCache({String? mediaType}) async {
    if (!_initialized) await init();

    await _db!.delete(
      _tableCachedMedia,
      where: mediaType != null ? 'media_type = ?' : null,
      whereArgs: mediaType != null ? [mediaType] : null,
    );
  }
}
