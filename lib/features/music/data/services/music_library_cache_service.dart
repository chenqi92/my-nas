import 'dart:convert';

import 'package:hive_ce/hive.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';

/// 音乐库缓存条目
class MusicLibraryCacheEntry {
  MusicLibraryCacheEntry({
    required this.sourceId,
    required this.filePath,
    required this.fileName,
    this.thumbnailUrl,
    this.size = 0,
    this.modifiedTime,
    // 元数据字段
    this.title,
    this.artist,
    this.album,
    this.duration,
    this.trackNumber,
    this.year,
    this.genre,
    this.coverBase64,
    this.metadataExtracted = false,
  });

  factory MusicLibraryCacheEntry.fromMap(Map<dynamic, dynamic> map) => MusicLibraryCacheEntry(
      sourceId: map['sourceId'] as String,
      filePath: map['filePath'] as String,
      fileName: map['fileName'] as String,
      thumbnailUrl: map['thumbnailUrl'] as String?,
      size: map['size'] as int? ?? 0,
      modifiedTime: map['modifiedTime'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['modifiedTime'] as int)
          : null,
      title: map['title'] as String?,
      artist: map['artist'] as String?,
      album: map['album'] as String?,
      duration: map['duration'] as int?,
      trackNumber: map['trackNumber'] as int?,
      year: map['year'] as int?,
      genre: map['genre'] as String?,
      coverBase64: map['coverBase64'] as String?,
      metadataExtracted: map['metadataExtracted'] as bool? ?? false,
    );

  final String sourceId;
  final String filePath;
  final String fileName;
  final String? thumbnailUrl;
  final int size;
  final DateTime? modifiedTime;

  // 元数据字段
  final String? title;
  final String? artist;
  final String? album;
  final int? duration; // 毫秒
  final int? trackNumber;
  final int? year;
  final String? genre;
  final String? coverBase64; // Base64 编码的封面图片
  final bool metadataExtracted; // 是否已提取过元数据

  String get uniqueKey => '${sourceId}_$filePath';

  /// 显示的标题（优先使用元数据标题，否则从文件名解析）
  String get displayTitle {
    if (title != null && title!.isNotEmpty) return title!;
    final nameWithoutExt = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
    // 尝试解析 "艺术家 - 歌曲名" 格式
    final match = RegExp(r'^.+?\s*[-–—]\s*(.+)$').firstMatch(nameWithoutExt);
    return match?.group(1)?.trim() ?? nameWithoutExt;
  }

  /// 显示的艺术家
  String get displayArtist {
    if (artist != null && artist!.isNotEmpty) return artist!;
    // 尝试从文件名解析
    final nameWithoutExt = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
    final match = RegExp(r'^(.+?)\s*[-–—]\s*.+$').firstMatch(nameWithoutExt);
    return match?.group(1)?.trim() ?? appL10n.musicCacheUnknownArtist;
  }

  /// 显示的专辑
  String get displayAlbum => album?.isNotEmpty ?? false ? album! : appL10n.musicCacheUnknownAlbum;

  /// 是否有封面
  bool get hasCover => coverBase64 != null && coverBase64!.isNotEmpty;

  /// 复制并更新元数据
  MusicLibraryCacheEntry copyWithMetadata({
    String? title,
    String? artist,
    String? album,
    int? duration,
    int? trackNumber,
    int? year,
    String? genre,
    String? coverBase64,
    bool? metadataExtracted,
  }) => MusicLibraryCacheEntry(
      sourceId: sourceId,
      filePath: filePath,
      fileName: fileName,
      thumbnailUrl: thumbnailUrl,
      size: size,
      modifiedTime: modifiedTime,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      duration: duration ?? this.duration,
      trackNumber: trackNumber ?? this.trackNumber,
      year: year ?? this.year,
      genre: genre ?? this.genre,
      coverBase64: coverBase64 ?? this.coverBase64,
      metadataExtracted: metadataExtracted ?? this.metadataExtracted,
    );

  Map<String, dynamic> toMap() => {
        'sourceId': sourceId,
        'filePath': filePath,
        'fileName': fileName,
        'thumbnailUrl': thumbnailUrl,
        'size': size,
        'modifiedTime': modifiedTime?.millisecondsSinceEpoch,
        'title': title,
        'artist': artist,
        'album': album,
        'duration': duration,
        'trackNumber': trackNumber,
        'year': year,
        'genre': genre,
        'coverBase64': coverBase64,
        'metadataExtracted': metadataExtracted,
      };
}

/// 音乐库缓存
class MusicLibraryCache {
  MusicLibraryCache({
    required this.tracks,
    required this.lastUpdated,
    this.sourceIds = const [],
  });

  factory MusicLibraryCache.fromMap(Map<dynamic, dynamic> map) {
    final tracksList = (map['tracks'] as List<dynamic>?)
            ?.map((t) => MusicLibraryCacheEntry.fromMap(t as Map<dynamic, dynamic>))
            .toList() ??
        [];
    return MusicLibraryCache(
      tracks: tracksList,
      lastUpdated:
          DateTime.fromMillisecondsSinceEpoch(map['lastUpdated'] as int),
      sourceIds: (map['sourceIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }

  final List<MusicLibraryCacheEntry> tracks;
  final DateTime lastUpdated;
  final List<String> sourceIds;

  /// 缓存是否过期（默认24小时）
  bool get isExpired => DateTime.now().difference(lastUpdated).inHours > 24;

  Map<String, dynamic> toMap() => {
        'tracks': tracks.map((t) => t.toMap()).toList(),
        'lastUpdated': lastUpdated.millisecondsSinceEpoch,
        'sourceIds': sourceIds,
      };
}

/// 音乐库缓存服务
/// 缓存音乐文件列表，避免每次启动都扫描 NAS
class MusicLibraryCacheService {
  factory MusicLibraryCacheService() => _instance ??= MusicLibraryCacheService._();
  MusicLibraryCacheService._();

  static MusicLibraryCacheService? _instance;

  static const String _boxName = 'music_library_cache';
  static const String _cacheKey = 'library_cache';

  Box<dynamic>? _box;

  /// 初始化
  Future<void> init() async {
    if (_box != null && _box!.isOpen) return;
    try {
      _box = await Hive.openBox(_boxName);
      logger.i('MusicLibraryCacheService: 初始化完成');
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'openMusicLibraryCache');
      await Hive.deleteBoxFromDisk(_boxName);
      _box = await Hive.openBox(_boxName);
      logger.i('MusicLibraryCacheService: 重建缓存完成');
    }
  }

  /// 获取缓存
  MusicLibraryCache? getCache() {
    final data = _box?.get(_cacheKey);
    if (data == null) return null;
    try {
      return MusicLibraryCache.fromMap(data as Map<dynamic, dynamic>);
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'parseMusicLibraryCache');
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
  Future<void> saveCache(MusicLibraryCache cache) async {
    await _box?.put(_cacheKey, cache.toMap());
    logger.i('MusicLibraryCacheService: 保存缓存，${cache.tracks.length} 首音乐');
  }

  /// 清除缓存
  Future<void> clearCache() async {
    await _box?.delete(_cacheKey);
    logger.i('MusicLibraryCacheService: 缓存已清除');
  }

  /// 获取缓存大小（字节）
  int getCacheSize() {
    final data = _box?.get(_cacheKey);
    if (data == null) return 0;
    try {
      final jsonStr = jsonEncode(data);
      return jsonStr.length;
    } on Exception catch (e) {
      logger.e('MusicLibraryCacheService: 获取缓存大小失败', e);
      return 0;
    }
  }

  /// 获取缓存信息文本
  String getCacheInfo() {
    final cache = getCache();
    if (cache == null) return appL10n.musicCacheNoCache;

    final size = getCacheSize();
    final sizeText = size < 1024
        ? '$size B'
        : size < 1024 * 1024
            ? '${(size / 1024).toStringAsFixed(1)} KB'
            : '${(size / (1024 * 1024)).toStringAsFixed(2)} MB';

    final age = DateTime.now().difference(cache.lastUpdated);
    final ageText = age.inHours < 1
        ? appL10n.musicCacheAgeMinutes(age.inMinutes)
        : age.inHours < 24
            ? appL10n.musicCacheAgeHours(age.inHours)
            : appL10n.musicCacheAgeDays(age.inDays);

    return appL10n.musicCacheInfoFormat(cache.tracks.length, sizeText, ageText);
  }

  /// 更新单个曲目的元数据
  Future<void> updateTrackMetadata(String uniqueKey, MusicLibraryCacheEntry updatedEntry) async {
    final cache = getCache();
    if (cache == null) return;

    final tracks = cache.tracks.map((t) {
      if (t.uniqueKey == uniqueKey) {
        return updatedEntry;
      }
      return t;
    }).toList();

    final newCache = MusicLibraryCache(
      tracks: tracks,
      lastUpdated: cache.lastUpdated,
      sourceIds: cache.sourceIds,
    );

    await _box?.put(_cacheKey, newCache.toMap());
  }

  /// 批量更新曲目元数据
  Future<void> updateTracksMetadata(Map<String, MusicLibraryCacheEntry> updates) async {
    final cache = getCache();
    if (cache == null) return;

    final tracks = cache.tracks.map((t) {
      final updated = updates[t.uniqueKey];
      return updated ?? t;
    }).toList();

    final newCache = MusicLibraryCache(
      tracks: tracks,
      lastUpdated: cache.lastUpdated,
      sourceIds: cache.sourceIds,
    );

    await _box?.put(_cacheKey, newCache.toMap());
    logger.d('MusicLibraryCacheService: 批量更新 ${updates.length} 首音乐的元数据');
  }

  /// 获取未提取元数据的曲目
  List<MusicLibraryCacheEntry> getTracksWithoutMetadata() {
    final cache = getCache();
    if (cache == null) return [];
    return cache.tracks.where((t) => !t.metadataExtracted).toList();
  }

  /// 根据 sourceId 和路径前缀删除缓存条目（用于移除文件夹）
  Future<int> deleteByPath(String sourceId, String pathPrefix) async {
    await init();
    final cache = getCache();
    if (cache == null) return 0;

    final originalCount = cache.tracks.length;
    final filteredTracks = cache.tracks
        .where((t) => !(t.sourceId == sourceId && t.filePath.startsWith(pathPrefix)))
        .toList();

    final deletedCount = originalCount - filteredTracks.length;
    if (deletedCount > 0) {
      final newCache = MusicLibraryCache(
        tracks: filteredTracks,
        lastUpdated: cache.lastUpdated,
        sourceIds: cache.sourceIds,
      );
      await _box?.put(_cacheKey, newCache.toMap());
      logger.i('MusicLibraryCacheService: 已删除 $deletedCount 首音乐缓存 (sourceId: $sourceId, path: $pathPrefix)');
    }

    return deletedCount;
  }
}
