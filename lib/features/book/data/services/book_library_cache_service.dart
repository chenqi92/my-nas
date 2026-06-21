import 'dart:convert';

import 'package:hive_ce/hive.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';

/// 图书库缓存条目
class BookLibraryCacheEntry {
  BookLibraryCacheEntry({
    required this.sourceId,
    required this.filePath,
    required this.fileName,
    this.size = 0,
    this.modifiedTime,
  });

  factory BookLibraryCacheEntry.fromMap(Map<dynamic, dynamic> map) => BookLibraryCacheEntry(
      sourceId: map['sourceId'] as String,
      filePath: map['filePath'] as String,
      fileName: map['fileName'] as String,
      size: map['size'] as int? ?? 0,
      modifiedTime: map['modifiedTime'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['modifiedTime'] as int)
          : null,
    );

  final String sourceId;
  final String filePath;
  final String fileName;
  final int size;
  final DateTime? modifiedTime;

  String get uniqueKey => '${sourceId}_$filePath';

  Map<String, dynamic> toMap() => {
        'sourceId': sourceId,
        'filePath': filePath,
        'fileName': fileName,
        'size': size,
        'modifiedTime': modifiedTime?.millisecondsSinceEpoch,
      };
}

/// 图书库缓存
class BookLibraryCache {
  BookLibraryCache({
    required this.books,
    required this.lastUpdated,
    this.sourceIds = const [],
  });

  factory BookLibraryCache.fromMap(Map<dynamic, dynamic> map) {
    final booksList = (map['books'] as List<dynamic>?)
            ?.map((b) => BookLibraryCacheEntry.fromMap(b as Map<dynamic, dynamic>))
            .toList() ??
        [];
    return BookLibraryCache(
      books: booksList,
      lastUpdated:
          DateTime.fromMillisecondsSinceEpoch(map['lastUpdated'] as int),
      sourceIds: (map['sourceIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }

  final List<BookLibraryCacheEntry> books;
  final DateTime lastUpdated;
  final List<String> sourceIds;

  /// 缓存是否过期（默认24小时）
  bool get isExpired => DateTime.now().difference(lastUpdated).inHours > 24;

  Map<String, dynamic> toMap() => {
        'books': books.map((b) => b.toMap()).toList(),
        'lastUpdated': lastUpdated.millisecondsSinceEpoch,
        'sourceIds': sourceIds,
      };
}

/// 图书库缓存服务
/// 缓存图书文件列表，避免每次启动都扫描 NAS
class BookLibraryCacheService {
  factory BookLibraryCacheService() => _instance ??= BookLibraryCacheService._();
  BookLibraryCacheService._();

  static BookLibraryCacheService? _instance;

  static const String _boxName = 'book_library_cache';
  static const String _cacheKey = 'library_cache';

  Box<dynamic>? _box;

  /// 初始化
  Future<void> init() async {
    if (_box != null && _box!.isOpen) return;
    try {
      _box = await Hive.openBox(_boxName);
      logger.i('BookLibraryCacheService: 初始化完成');
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'openBookLibraryCacheBox');
      await Hive.deleteBoxFromDisk(_boxName);
      _box = await Hive.openBox(_boxName);
      logger.i('BookLibraryCacheService: 重建缓存完成');
    }
  }

  /// 获取缓存
  BookLibraryCache? getCache() {
    final data = _box?.get(_cacheKey);
    if (data == null) return null;
    try {
      return BookLibraryCache.fromMap(data as Map<dynamic, dynamic>);
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'parseBookLibraryCache');
      return null;
    }
  }

  /// 检查缓存是否有效（未过期且源ID匹配）
  bool isCacheValid(List<String> currentSourceIds) {
    final cache = getCache();
    if (cache == null) return false;
    if (cache.isExpired) return false;

    final cachedSourceIds = Set.of(cache.sourceIds);
    final currentIds = Set.of(currentSourceIds);
    return cachedSourceIds.containsAll(currentIds) &&
        currentIds.containsAll(cachedSourceIds);
  }

  /// 保存缓存
  Future<void> saveCache(BookLibraryCache cache) async {
    await _box?.put(_cacheKey, cache.toMap());
    logger.i('BookLibraryCacheService: 保存缓存，${cache.books.length} 本图书');
  }

  /// 清除缓存
  Future<void> clearCache() async {
    await _box?.delete(_cacheKey);
    logger.i('BookLibraryCacheService: 缓存已清除');
  }

  /// 根据 sourceId 和路径前缀删除（用于移除文件夹）
  Future<int> deleteByPath(String sourceId, String pathPrefix) async {
    await init();
    final cache = getCache();
    if (cache == null) return 0;

    final originalCount = cache.books.length;
    final filteredBooks = cache.books.where((b) {
      // 保留不匹配的条目
      if (b.sourceId != sourceId) return true;
      if (!b.filePath.startsWith(pathPrefix)) return true;
      return false;
    }).toList();

    final deletedCount = originalCount - filteredBooks.length;
    if (deletedCount > 0) {
      final newCache = BookLibraryCache(
        books: filteredBooks,
        lastUpdated: cache.lastUpdated,
        sourceIds: cache.sourceIds,
      );
      await saveCache(newCache);
      logger.i('BookLibraryCacheService: 已删除 $deletedCount 本图书 (sourceId: $sourceId, path: $pathPrefix)');
    }
    return deletedCount;
  }

  /// 获取缓存大小（字节）
  int getCacheSize() {
    final data = _box?.get(_cacheKey);
    if (data == null) return 0;
    try {
      final jsonStr = jsonEncode(data);
      return jsonStr.length;
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '缓存大小计算失败不影响功能');
      return 0;
    }
  }

  /// 获取缓存信息文本
  String getCacheInfo() {
    final cache = getCache();
    if (cache == null) return appL10n.bookLibraryCacheServiceNoCache;

    final size = getCacheSize();
    final sizeText = size < 1024
        ? '$size B'
        : size < 1024 * 1024
            ? '${(size / 1024).toStringAsFixed(1)} KB'
            : '${(size / (1024 * 1024)).toStringAsFixed(2)} MB';

    final age = DateTime.now().difference(cache.lastUpdated);
    final ageText = age.inHours < 1
        ? appL10n.bookLibraryCacheServiceMinutesAgo(age.inMinutes)
        : age.inHours < 24
            ? appL10n.bookLibraryCacheServiceHoursAgo(age.inHours)
            : appL10n.bookLibraryCacheServiceDaysAgo(age.inDays);

    return appL10n.bookLibraryCacheServiceInfo(cache.books.length, sizeText, ageText);
  }
}
