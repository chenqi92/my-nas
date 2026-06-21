import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/platform/spotlight/spotlight_hook.dart';
import 'package:my_nas/core/platform/spotlight/spotlight_item.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/book/domain/entities/book_item.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// 图书实体（用于 SQLite 存储）
class BookEntity {
  const BookEntity({
    required this.sourceId,
    required this.filePath,
    required this.fileName,
    required this.format,
    this.title,
    this.author,
    this.description,
    this.coverPath,
    this.totalPages,
    this.size = 0,
    this.modifiedTime,
    this.lastUpdated,
    this.lastReadTime, // 最后阅读时间
    this.metadataExtracted = false,
  });

  final String sourceId;
  final String filePath;
  final String fileName;
  final BookFormat format;
  final String? title;
  final String? author;
  final String? description;
  final String? coverPath; // 封面文件路径（磁盘缓存）
  final int? totalPages;
  final int size;
  final DateTime? modifiedTime;
  final DateTime? lastUpdated;
  final DateTime? lastReadTime; // 最后阅读时间
  final bool metadataExtracted; // 是否已提取元数据

  String get uniqueKey => '${sourceId}_$filePath';

  /// 显示名称（优先使用元数据标题）
  String get displayName {
    if (title != null && title!.isNotEmpty) return title!;
    final dotIndex = fileName.lastIndexOf('.');
    return dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
  }

  /// 显示的作者
  String get displayAuthor => author ?? appL10n.bookUnknownAuthor;

  /// 显示的文件大小
  String get displaySize {
    if (size <= 0) return appL10n.bookUnknownSize;
    const units = ['B', 'KB', 'MB', 'GB'];
    var unitIndex = 0;
    var displaySize = size.toDouble();
    while (displaySize >= 1024 && unitIndex < units.length - 1) {
      displaySize /= 1024;
      unitIndex++;
    }
    return '${displaySize.toStringAsFixed(displaySize < 10 ? 1 : 0)} ${units[unitIndex]}';
  }

  BookEntity copyWith({
    String? sourceId,
    String? filePath,
    String? fileName,
    BookFormat? format,
    Object? title = _sentinel,
    Object? author = _sentinel,
    Object? description = _sentinel,
    Object? coverPath = _sentinel,
    Object? totalPages = _sentinel,
    int? size,
    DateTime? modifiedTime,
    DateTime? lastUpdated,
    Object? lastReadTime = _sentinel,
    bool? metadataExtracted,
  }) =>
      BookEntity(
        sourceId: sourceId ?? this.sourceId,
        filePath: filePath ?? this.filePath,
        fileName: fileName ?? this.fileName,
        format: format ?? this.format,
        title: title == _sentinel ? this.title : title as String?,
        author: author == _sentinel ? this.author : author as String?,
        description: description == _sentinel ? this.description : description as String?,
        coverPath: coverPath == _sentinel ? this.coverPath : coverPath as String?,
        totalPages: totalPages == _sentinel ? this.totalPages : totalPages as int?,
        size: size ?? this.size,
        modifiedTime: modifiedTime ?? this.modifiedTime,
        lastUpdated: lastUpdated ?? this.lastUpdated,
        lastReadTime: lastReadTime == _sentinel ? this.lastReadTime : lastReadTime as DateTime?,
        metadataExtracted: metadataExtracted ?? this.metadataExtracted,
      );
}

/// 用于 copyWith 方法中区分 null 和未提供参数的哨兵值
const _sentinel = Object();

/// 图书数据库服务 - 使用 SQLite 支持大规模数据和索引查询
class BookDatabaseService {
  factory BookDatabaseService() => _instance ??= BookDatabaseService._();
  BookDatabaseService._();

  static BookDatabaseService? _instance;

  Database? _db;
  bool _initialized = false;

  static const String _tableBooks = 'books';
  static const String _colSourceId = 'source_id';
  static const String _colFilePath = 'file_path';
  static const String _colFileName = 'file_name';
  static const String _colFormat = 'format';
  static const String _colTitle = 'title';
  static const String _colAuthor = 'author';
  static const String _colDescription = 'description';
  static const String _colCoverPath = 'cover_path';
  static const String _colTotalPages = 'total_pages';
  static const String _colSize = 'size';
  static const String _colModifiedTime = 'modified_time';
  static const String _colLastUpdated = 'last_updated';
  static const String _colLastReadTime = 'last_read_time'; // 最后阅读时间
  static const String _colMetadataExtracted = 'metadata_extracted';

  /// 初始化数据库
  Future<void> init() async {
    if (_initialized) return;

    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      final dbPath = join(documentsDir.path, 'book_library.db');

      _db = await openDatabase(
        dbPath,
        version: 3, // 升级版本以添加 last_read_time 字段
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        onConfigure: _onConfigure,
      );

      _initialized = true;
      logger.i('BookDatabaseService: 数据库初始化完成');
    } catch (e, st) {
      AppError.handle(e, st, 'BookDatabaseService.init');
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
    logger.d('BookDatabaseService: 数据库配置完成 (WAL模式)');
  }

  /// 创建表
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_tableBooks (
        $_colSourceId TEXT NOT NULL,
        $_colFilePath TEXT NOT NULL,
        $_colFileName TEXT NOT NULL,
        $_colFormat TEXT NOT NULL,
        $_colTitle TEXT,
        $_colAuthor TEXT,
        $_colDescription TEXT,
        $_colCoverPath TEXT,
        $_colTotalPages INTEGER,
        $_colSize INTEGER DEFAULT 0,
        $_colModifiedTime INTEGER,
        $_colLastUpdated INTEGER,
        $_colLastReadTime INTEGER,
        $_colMetadataExtracted INTEGER DEFAULT 0,
        PRIMARY KEY ($_colSourceId, $_colFilePath)
      )
    ''');

    // 创建索引以加速查询
    await db.execute('CREATE INDEX idx_books_format ON $_tableBooks ($_colFormat)');
    await db.execute('CREATE INDEX idx_books_modified ON $_tableBooks ($_colModifiedTime DESC)');
    await db.execute('CREATE INDEX idx_books_last_read ON $_tableBooks ($_colLastReadTime DESC)'); // 最后阅读时间索引
    await db.execute('CREATE INDEX idx_books_filename ON $_tableBooks ($_colFileName)');
    await db.execute('CREATE INDEX idx_books_title ON $_tableBooks ($_colTitle)');
    await db.execute('CREATE INDEX idx_books_author ON $_tableBooks ($_colAuthor)');
    await db.execute('CREATE INDEX idx_books_metadata ON $_tableBooks ($_colMetadataExtracted)');
  }

  /// 升级数据库
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    logger.i('BookDatabaseService: 数据库升级 $oldVersion -> $newVersion');

    if (oldVersion < 2) {
      // 添加新字段
      await db.execute('ALTER TABLE $_tableBooks ADD COLUMN $_colTitle TEXT');
      await db.execute('ALTER TABLE $_tableBooks ADD COLUMN $_colAuthor TEXT');
      await db.execute('ALTER TABLE $_tableBooks ADD COLUMN $_colDescription TEXT');
      await db.execute('ALTER TABLE $_tableBooks ADD COLUMN $_colCoverPath TEXT');
      await db.execute('ALTER TABLE $_tableBooks ADD COLUMN $_colTotalPages INTEGER');
      await db.execute('ALTER TABLE $_tableBooks ADD COLUMN $_colMetadataExtracted INTEGER DEFAULT 0');

      // 创建新索引
      await db.execute('CREATE INDEX IF NOT EXISTS idx_books_title ON $_tableBooks ($_colTitle)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_books_author ON $_tableBooks ($_colAuthor)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_books_metadata ON $_tableBooks ($_colMetadataExtracted)');
    }

    if (oldVersion < 3) {
      // 添加最后阅读时间字段
      await db.execute('ALTER TABLE $_tableBooks ADD COLUMN $_colLastReadTime INTEGER');
      // 创建索引
      await db.execute('CREATE INDEX IF NOT EXISTS idx_books_last_read ON $_tableBooks ($_colLastReadTime DESC)');
      logger.i('BookDatabaseService: 已添加 last_read_time 字段和索引');
    }
  }

  /// 插入或更新图书
  Future<void> upsert(BookEntity book) async {
    if (!_initialized) await init();

    await _db!.insert(
      _tableBooks,
      _toRow(book),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 批量插入或更新
  ///
  /// 使用事务保护确保原子性
  Future<void> upsertBatch(List<BookEntity> books) async {
    if (!_initialized) await init();
    if (books.isEmpty) return;

    await _db!.transaction((txn) async {
      final batch = txn.batch();
      for (final book in books) {
        batch.insert(
          _tableBooks,
          _toRow(book),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// 获取单本图书
  Future<BookEntity?> get(String sourceId, String filePath) async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tableBooks,
      where: '$_colSourceId = ? AND $_colFilePath = ?',
      whereArgs: [sourceId, filePath],
      limit: 1,
    );

    if (results.isEmpty) return null;
    return _fromRow(results.first);
  }

  /// 获取所有图书
  /// 默认按最后阅读时间倒序排列(最近阅读的在最前面)
  Future<List<BookEntity>> getAll({
    String orderBy = 'last_read_time',
    bool descending = true,
  }) async {
    if (!_initialized) await init();

    final order = descending ? 'DESC' : 'ASC';
    // 对于 last_read_time, NULL值排在最后
    // 使用兼容写法，避免老版本 SQLite 不支持 NULLS LAST 语法
    final orderByClause = orderBy == 'last_read_time'
        ? 'CASE WHEN $orderBy IS NULL THEN 1 ELSE 0 END, $orderBy $order'
        : '$orderBy $order';

    final results = await _db!.query(
      _tableBooks,
      orderBy: orderByClause,
    );

    return results.map(_fromRow).toList();
  }

  /// 按格式获取图书
  Future<List<BookEntity>> getByFormat(
    BookFormat format, {
    int? limit,
    int offset = 0,
  }) async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tableBooks,
      where: '$_colFormat = ?',
      whereArgs: [format.name],
      orderBy: '$_colFileName ASC',
      limit: limit,
      offset: offset,
    );

    return results.map(_fromRow).toList();
  }

  /// 搜索图书
  Future<List<BookEntity>> search(
    String query, {
    int limit = 100,
  }) async {
    if (!_initialized) await init();
    if (query.isEmpty) return [];

    final results = await _db!.query(
      _tableBooks,
      where: '$_colFileName LIKE ?',
      whereArgs: ['%$query%'],
      orderBy: '$_colFileName ASC',
      limit: limit,
    );

    return results.map(_fromRow).toList();
  }

  /// 获取统计信息
  Future<Map<String, dynamic>> getStats() async {
    if (!_initialized) await init();

    final totalCount = Sqflite.firstIntValue(
        await _db!.rawQuery('SELECT COUNT(*) FROM $_tableBooks'));

    final totalSize = Sqflite.firstIntValue(
            await _db!.rawQuery('SELECT SUM($_colSize) FROM $_tableBooks')) ??
        0;

    // 按格式统计
    final formatResults = await _db!.rawQuery('''
      SELECT $_colFormat, COUNT(*) as count
      FROM $_tableBooks
      GROUP BY $_colFormat
    ''');

    final formatStats = <String, int>{};
    for (final row in formatResults) {
      final format = row[_colFormat]! as String;
      final count = row['count']! as int;
      formatStats[format] = count;
    }

    return {
      'total': totalCount ?? 0,
      'totalSize': totalSize,
      'formatStats': formatStats,
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
            await _db!.rawQuery('SELECT COUNT(*) FROM $_tableBooks$whereClause', args)) ??
        0;
  }

  /// 删除图书
  Future<void> delete(String sourceId, String filePath) async {
    if (!_initialized) await init();

    await _db!.delete(
      _tableBooks,
      where: '$_colSourceId = ? AND $_colFilePath = ?',
      whereArgs: [sourceId, filePath],
    );

    SpotlightHook.afterDelete(SpotlightItemKind.book, ['$sourceId|$filePath']);
  }

  /// 清空所有数据
  Future<void> clear() async {
    if (!_initialized) await init();
    await _db!.delete(_tableBooks);
    logger.i('BookDatabaseService: 已清空所有数据');
  }

  /// 按来源ID删除
  Future<int> deleteBySourceId(String sourceId) async {
    if (!_initialized) await init();

    final count = await _db!.delete(
      _tableBooks,
      where: '$_colSourceId = ?',
      whereArgs: [sourceId],
    );
    logger.i('BookDatabaseService: 已删除 $count 本图书 (sourceId: $sourceId)');
    return count;
  }

  /// 根据 sourceId 和路径前缀删除（用于移除文件夹）
  Future<int> deleteByPath(String sourceId, String pathPrefix) async {
    if (!_initialized) await init();

    final count = await _db!.delete(
      _tableBooks,
      where: '$_colSourceId = ? AND $_colFilePath LIKE ?',
      whereArgs: [sourceId, '$pathPrefix%'],
    );
    logger.i('BookDatabaseService: 已删除 $count 本图书 (sourceId: $sourceId, path: $pathPrefix)');
    return count;
  }

  /// 安全关闭数据库
  ///
  /// 执行 WAL checkpoint 确保数据安全持久化
  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      try {
        await _db!.execute('PRAGMA wal_checkpoint(TRUNCATE)');
        logger.d('BookDatabaseService: WAL checkpoint 完成');
      } on Exception catch (e, st) {
        AppError.ignore(e, st, 'WAL checkpoint 失败，不影响关闭流程');
      }
      await _db!.close();
      _db = null;
      _initialized = false;
      logger.i('BookDatabaseService: 数据库已安全关闭');
    }
  }

  /// 获取未提取元数据的图书
  Future<List<BookEntity>> getUnextractedMetadata({int limit = 50}) async {
    if (!_initialized) await init();

    final results = await _db!.query(
      _tableBooks,
      where: '$_colMetadataExtracted = 0',
      limit: limit,
    );

    return results.map(_fromRow).toList();
  }

  /// 转换为数据库行
  Map<String, dynamic> _toRow(BookEntity b) => {
        _colSourceId: b.sourceId,
        _colFilePath: b.filePath,
        _colFileName: b.fileName,
        _colFormat: b.format.name,
        _colTitle: b.title,
        _colAuthor: b.author,
        _colDescription: b.description,
        _colCoverPath: b.coverPath,
        _colTotalPages: b.totalPages,
        _colSize: b.size,
        _colModifiedTime: b.modifiedTime?.millisecondsSinceEpoch,
        _colLastUpdated:
            b.lastUpdated?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch,
        _colLastReadTime: b.lastReadTime?.millisecondsSinceEpoch,
        _colMetadataExtracted: b.metadataExtracted ? 1 : 0,
      };

  /// 从数据库行转换
  BookEntity _fromRow(Map<String, dynamic> row) => BookEntity(
        sourceId: row[_colSourceId] as String,
        filePath: row[_colFilePath] as String,
        fileName: row[_colFileName] as String,
        format: BookFormat.values.firstWhere(
          (f) => f.name == row[_colFormat],
          orElse: () => BookFormat.unknown,
        ),
        title: row[_colTitle] as String?,
        author: row[_colAuthor] as String?,
        description: row[_colDescription] as String?,
        coverPath: row[_colCoverPath] as String?,
        totalPages: row[_colTotalPages] as int?,
        size: row[_colSize] as int? ?? 0,
        modifiedTime: row[_colModifiedTime] != null
            ? DateTime.fromMillisecondsSinceEpoch(row[_colModifiedTime] as int)
            : null,
        lastUpdated: row[_colLastUpdated] != null
            ? DateTime.fromMillisecondsSinceEpoch(row[_colLastUpdated] as int)
            : null,
        lastReadTime: row[_colLastReadTime] != null
            ? DateTime.fromMillisecondsSinceEpoch(row[_colLastReadTime] as int)
            : null,
        metadataExtracted: (row[_colMetadataExtracted] as int? ?? 0) == 1,
      );

  /// 更新图书的最后阅读时间
  Future<void> updateLastReadTime(String sourceId, String filePath) async {
    if (!_initialized) await init();

    await _db!.update(
      _tableBooks,
      {_colLastReadTime: DateTime.now().millisecondsSinceEpoch},
      where: '$_colSourceId = ? AND $_colFilePath = ?',
      whereArgs: [sourceId, filePath],
    );
  }
}
