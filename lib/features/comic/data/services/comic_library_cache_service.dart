import 'dart:convert';

import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/platform/spotlight/spotlight_hook.dart';
import 'package:my_nas/core/platform/spotlight/spotlight_item.dart';
import 'package:my_nas/core/storage/secure_storage_options.dart';
import 'package:my_nas/core/utils/logger.dart';

/// 漫画缓存条目
class ComicLibraryCacheEntry {
  ComicLibraryCacheEntry({
    required this.sourceId,
    required this.folderPath,
    required this.folderName,
    this.coverPath,
    this.pageCount = 0,
    this.modifiedTime,
    this.comicType = 'folder',
    this.fileSize,
  });

  factory ComicLibraryCacheEntry.fromJson(Map<String, dynamic> json) =>
      ComicLibraryCacheEntry(
        sourceId: json['sourceId'] as String,
        folderPath: json['folderPath'] as String,
        folderName: json['folderName'] as String,
        coverPath: json['coverPath'] as String?,
        pageCount: json['pageCount'] as int? ?? 0,
        modifiedTime: json['modifiedTime'] != null
            ? DateTime.parse(json['modifiedTime'] as String)
            : null,
        comicType: json['comicType'] as String? ?? 'folder',
        fileSize: json['fileSize'] as int?,
      );

  final String sourceId;
  final String folderPath;
  final String folderName;
  final String? coverPath;
  final int pageCount;
  final DateTime? modifiedTime;
  final String comicType;
  final int? fileSize;

  Map<String, dynamic> toJson() => {
    'sourceId': sourceId,
    'folderPath': folderPath,
    'folderName': folderName,
    'coverPath': coverPath,
    'pageCount': pageCount,
    'modifiedTime': modifiedTime?.toIso8601String(),
    'comicType': comicType,
    'fileSize': fileSize,
  };
}

/// 漫画库缓存
class ComicLibraryCache {
  ComicLibraryCache({
    required this.comics,
    required this.lastUpdated,
    required this.sourceIds,
  });

  factory ComicLibraryCache.fromJson(Map<String, dynamic> json) =>
      ComicLibraryCache(
        comics: (json['comics'] as List<dynamic>)
            .map(
              (e) => ComicLibraryCacheEntry.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList(),
        lastUpdated: DateTime.parse(json['lastUpdated'] as String),
        sourceIds: List<String>.from(json['sourceIds'] as List),
      );

  final List<ComicLibraryCacheEntry> comics;
  final DateTime lastUpdated;
  final List<String> sourceIds;

  Map<String, dynamic> toJson() => {
    'comics': comics.map((c) => c.toJson()).toList(),
    'lastUpdated': lastUpdated.toIso8601String(),
    'sourceIds': sourceIds,
  };
}

/// 漫画库缓存服务
class ComicLibraryCacheService {
  factory ComicLibraryCacheService() =>
      _instance ??= ComicLibraryCacheService._();
  ComicLibraryCacheService._();

  static ComicLibraryCacheService? _instance;

  static const _cacheKey = 'comic_library_cache';
  static const _cacheDuration = Duration(hours: 24);

  final _storage = defaultSecureStorage;
  ComicLibraryCache? _cache;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    try {
      final data = await _storage.read(key: _cacheKey);
      if (data != null) {
        _cache = ComicLibraryCache.fromJson(
          Map<String, dynamic>.from(jsonDecode(data) as Map),
        );
        logger.i(
          'ComicLibraryCacheService: 加载缓存成功，共 ${_cache!.comics.length} 本漫画',
        );
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'ComicLibraryCacheService加载缓存失败');
      _cache = null;
    }

    _initialized = true;
  }

  ComicLibraryCache? getCache() => _cache;

  bool isCacheValid(List<String> sourceIds) {
    if (_cache == null) return false;

    final now = DateTime.now();
    final cacheAge = now.difference(_cache!.lastUpdated);
    if (cacheAge > _cacheDuration) return false;

    final cachedSourceIds = Set<String>.from(_cache!.sourceIds);
    final currentSourceIds = Set<String>.from(sourceIds);
    return cachedSourceIds.containsAll(currentSourceIds) &&
        currentSourceIds.containsAll(cachedSourceIds);
  }

  Future<void> saveCache(ComicLibraryCache cache) async {
    _cache = cache;
    try {
      await writeSecureValueVerified(
        _storage,
        key: _cacheKey,
        value: jsonEncode(cache.toJson()),
      );
      logger.i('ComicLibraryCacheService: 保存缓存成功，共 ${cache.comics.length} 本漫画');
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'saveComicLibraryCache');
    }
  }

  Future<void> clearCache() async {
    _cache = null;
    try {
      await _storage.delete(key: _cacheKey);
      logger.i('ComicLibraryCacheService: 清除缓存成功');
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'clearComicLibraryCache');
    }
  }

  /// 根据 sourceId 删除所有漫画
  Future<int> deleteBySourceId(String sourceId) async {
    if (_cache == null) await init();
    if (_cache == null) return 0;

    final originalCount = _cache!.comics.length;
    final removedComics = _cache!.comics
        .where((c) => c.sourceId == sourceId)
        .toList();
    final filteredComics = _cache!.comics
        .where((c) => c.sourceId != sourceId)
        .toList();
    final deletedCount = originalCount - filteredComics.length;

    if (deletedCount > 0) {
      final newCache = ComicLibraryCache(
        comics: filteredComics,
        lastUpdated: _cache!.lastUpdated,
        sourceIds: _cache!.sourceIds.where((id) => id != sourceId).toList(),
      );
      await saveCache(newCache);
      logger.i(
        'ComicLibraryCacheService: 已删除 $deletedCount 本漫画 (sourceId: $sourceId)',
      );

      SpotlightHook.afterDelete(
        SpotlightItemKind.comic,
        removedComics.map((c) => '${c.sourceId}|${c.folderPath}'),
      );
    }
    return deletedCount;
  }

  /// 根据 sourceId 和路径前缀删除（用于移除文件夹）
  Future<int> deleteByPath(String sourceId, String pathPrefix) async {
    if (_cache == null) await init();
    if (_cache == null) return 0;

    final originalCount = _cache!.comics.length;
    final filteredComics = _cache!.comics
        .where(
          (c) =>
              !(c.sourceId == sourceId && c.folderPath.startsWith(pathPrefix)),
        )
        .toList();
    final deletedCount = originalCount - filteredComics.length;

    if (deletedCount > 0) {
      final newCache = ComicLibraryCache(
        comics: filteredComics,
        lastUpdated: _cache!.lastUpdated,
        sourceIds: _cache!.sourceIds,
      );
      await saveCache(newCache);
      logger.i(
        'ComicLibraryCacheService: 已删除 $deletedCount 本漫画 (sourceId: $sourceId, path: $pathPrefix)',
      );
    }
    return deletedCount;
  }

  /// 获取缓存大小（字节）
  int getCacheSize() {
    if (_cache == null) return 0;
    try {
      final jsonStr = jsonEncode(_cache!.toJson());
      return jsonStr.length;
    } on Exception {
      return 0;
    }
  }

  /// 获取缓存信息文本
  String getCacheInfo() {
    final cache = getCache();
    if (cache == null) return appL10n.comicCacheServiceNoCache;

    final size = getCacheSize();
    final sizeText = size < 1024
        ? '$size B'
        : size < 1024 * 1024
        ? '${(size / 1024).toStringAsFixed(1)} KB'
        : '${(size / (1024 * 1024)).toStringAsFixed(2)} MB';

    final age = DateTime.now().difference(cache.lastUpdated);
    final ageText = age.inHours < 1
        ? appL10n.comicCacheServiceMinutesAgo(age.inMinutes)
        : age.inHours < 24
        ? appL10n.comicCacheServiceHoursAgo(age.inHours)
        : appL10n.comicCacheServiceDaysAgo(age.inDays);

    return appL10n.comicCacheServiceInfoFormat(
      cache.comics.length,
      sizeText,
      ageText,
    );
  }

  /// 获取漫画数量
  ///
  /// [sourceId] 可选，按源ID筛选
  /// [pathPrefix] 可选，按路径前缀筛选（需要同时提供 sourceId）
  Future<int> getCount({String? sourceId, String? pathPrefix}) async {
    if (_cache == null) await init();
    if (_cache == null) return 0;

    if (sourceId != null && pathPrefix != null) {
      return _cache!.comics
          .where(
            (c) =>
                c.sourceId == sourceId && c.folderPath.startsWith(pathPrefix),
          )
          .length;
    } else if (sourceId != null) {
      return _cache!.comics.where((c) => c.sourceId == sourceId).length;
    }

    return _cache!.comics.length;
  }
}
