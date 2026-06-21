import 'dart:convert';

import 'package:hive_ce/hive.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';

/// 照片库缓存条目
class PhotoLibraryCacheEntry {
  PhotoLibraryCacheEntry({
    required this.sourceId,
    required this.filePath,
    required this.fileName,
    this.thumbnailUrl,
    this.size = 0,
    this.modifiedTime,
  });

  factory PhotoLibraryCacheEntry.fromMap(Map<dynamic, dynamic> map) => PhotoLibraryCacheEntry(
      sourceId: map['sourceId'] as String,
      filePath: map['filePath'] as String,
      fileName: map['fileName'] as String,
      thumbnailUrl: map['thumbnailUrl'] as String?,
      size: map['size'] as int? ?? 0,
      modifiedTime: map['modifiedTime'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['modifiedTime'] as int)
          : null,
    );

  final String sourceId;
  final String filePath;
  final String fileName;
  final String? thumbnailUrl;
  final int size;
  final DateTime? modifiedTime;

  String get uniqueKey => '${sourceId}_$filePath';

  Map<String, dynamic> toMap() => {
        'sourceId': sourceId,
        'filePath': filePath,
        'fileName': fileName,
        'thumbnailUrl': thumbnailUrl,
        'size': size,
        'modifiedTime': modifiedTime?.millisecondsSinceEpoch,
      };
}

/// 照片库缓存
class PhotoLibraryCache {
  PhotoLibraryCache({
    required this.photos,
    required this.lastUpdated,
    this.sourceIds = const [],
  });

  factory PhotoLibraryCache.fromMap(Map<dynamic, dynamic> map) {
    final photosList = (map['photos'] as List<dynamic>?)
            ?.map((p) => PhotoLibraryCacheEntry.fromMap(p as Map<dynamic, dynamic>))
            .toList() ??
        [];
    return PhotoLibraryCache(
      photos: photosList,
      lastUpdated:
          DateTime.fromMillisecondsSinceEpoch(map['lastUpdated'] as int),
      sourceIds: (map['sourceIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }

  final List<PhotoLibraryCacheEntry> photos;
  final DateTime lastUpdated;
  final List<String> sourceIds;

  /// 缓存是否过期（默认24小时）
  bool get isExpired => DateTime.now().difference(lastUpdated).inHours > 24;

  Map<String, dynamic> toMap() => {
        'photos': photos.map((p) => p.toMap()).toList(),
        'lastUpdated': lastUpdated.millisecondsSinceEpoch,
        'sourceIds': sourceIds,
      };
}

/// 照片库缓存服务
/// 缓存照片文件列表，避免每次启动都扫描 NAS
class PhotoLibraryCacheService {
  factory PhotoLibraryCacheService() => _instance ??= PhotoLibraryCacheService._();
  PhotoLibraryCacheService._();

  static PhotoLibraryCacheService? _instance;

  static const String _boxName = 'photo_library_cache';
  static const String _cacheKey = 'library_cache';

  Box<dynamic>? _box;

  /// 初始化
  Future<void> init() async {
    if (_box != null && _box!.isOpen) return;
    try {
      _box = await Hive.openBox(_boxName);
      logger.i('PhotoLibraryCacheService: 初始化完成');
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'PhotoLibraryCacheService.init');
      await Hive.deleteBoxFromDisk(_boxName);
      _box = await Hive.openBox(_boxName);
      logger.i('PhotoLibraryCacheService: 重建缓存完成');
    }
  }

  /// 获取缓存
  PhotoLibraryCache? getCache() {
    final data = _box?.get(_cacheKey);
    if (data == null) return null;
    try {
      return PhotoLibraryCache.fromMap(data as Map<dynamic, dynamic>);
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '缓存解析失败，返回null');
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
  Future<void> saveCache(PhotoLibraryCache cache) async {
    await _box?.put(_cacheKey, cache.toMap());
    logger.i('PhotoLibraryCacheService: 保存缓存，${cache.photos.length} 张照片');
  }

  /// 清除缓存
  Future<void> clearCache() async {
    await _box?.delete(_cacheKey);
    logger.i('PhotoLibraryCacheService: 缓存已清除');
  }

  /// 根据 sourceId 和路径前缀删除（用于移除文件夹）
  Future<int> deleteByPath(String sourceId, String pathPrefix) async {
    await init();
    final cache = getCache();
    if (cache == null) return 0;

    final originalCount = cache.photos.length;
    final filteredPhotos = cache.photos.where((p) {
      // 保留不匹配的条目
      if (p.sourceId != sourceId) return true;
      if (!p.filePath.startsWith(pathPrefix)) return true;
      return false;
    }).toList();

    final deletedCount = originalCount - filteredPhotos.length;
    if (deletedCount > 0) {
      final newCache = PhotoLibraryCache(
        photos: filteredPhotos,
        lastUpdated: cache.lastUpdated,
        sourceIds: cache.sourceIds,
      );
      await saveCache(newCache);
      logger.i('PhotoLibraryCacheService: 已删除 $deletedCount 张照片 (sourceId: $sourceId, path: $pathPrefix)');
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
      AppError.ignore(e, st, '计算缓存大小失败，返回0');
      return 0;
    }
  }

  /// 获取缓存信息文本
  String getCacheInfo() {
    final cache = getCache();
    if (cache == null) return appL10n.photoLibraryCacheInfoNoCache;

    final size = getCacheSize();
    final sizeText = size < 1024
        ? appL10n.photoLibraryCacheInfoSizeBytes(size)
        : size < 1024 * 1024
            ? appL10n.photoLibraryCacheInfoSizeKB((size / 1024).toStringAsFixed(1))
            : appL10n.photoLibraryCacheInfoSizeMB((size / (1024 * 1024)).toStringAsFixed(2));

    final age = DateTime.now().difference(cache.lastUpdated);
    final ageText = age.inHours < 1
        ? appL10n.photoLibraryCacheInfoAgeMinutesAgo(age.inMinutes)
        : age.inHours < 24
            ? appL10n.photoLibraryCacheInfoAgeHoursAgo(age.inHours)
            : appL10n.photoLibraryCacheInfoAgeDaysAgo(age.inDays);

    return appL10n.photoLibraryCacheInfoFormat(cache.photos.length, sizeText, ageText);
  }
}
