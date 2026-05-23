import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/data/services/video_database_service.dart';
import 'package:my_nas/media_server_adapters/base/media_server_entities.dart';
import 'package:sqflite/sqflite.dart';

/// 媒体服务器缓存条目
class MediaServerCacheEntry {
  const MediaServerCacheEntry({
    required this.id,
    required this.sourceId,
    required this.itemId,
    this.parentId,
    required this.itemType,
    required this.name,
    required this.metadataJson,
    this.imageUrlsJson,
    required this.lastUpdated,
  });

  factory MediaServerCacheEntry.fromMap(Map<String, dynamic> map) => MediaServerCacheEntry(
      id: map['id'] as String,
      sourceId: map['source_id'] as String,
      itemId: map['item_id'] as String,
      parentId: map['parent_id'] as String?,
      itemType: map['item_type'] as String,
      name: map['name'] as String,
      metadataJson: map['metadata_json'] as String,
      imageUrlsJson: map['image_urls_json'] as String?,
      lastUpdated: DateTime.fromMillisecondsSinceEpoch(map['last_updated'] as int),
    );

  final String id;
  final String sourceId;
  final String itemId;
  final String? parentId;
  final String itemType;
  final String name;
  final String metadataJson;
  final String? imageUrlsJson;
  final DateTime lastUpdated;

  Map<String, dynamic> toMap() => {
        'id': id,
        'source_id': sourceId,
        'item_id': itemId,
        'parent_id': parentId,
        'item_type': itemType,
        'name': name,
        'metadata_json': metadataJson,
        'image_urls_json': imageUrlsJson,
        'last_updated': lastUpdated.millisecondsSinceEpoch,
      };

  /// 解析元数据 JSON
  Map<String, dynamic>? get metadata {
    try {
      return jsonDecode(metadataJson) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  /// 解析图片 URL JSON
  Map<String, String>? get imageUrls {
    if (imageUrlsJson == null) return null;
    try {
      final map = jsonDecode(imageUrlsJson!) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, v as String));
    } catch (e) {
      return null;
    }
  }
}

/// 媒体服务器缓存服务
///
/// 用于缓存媒体服务器的元数据，减少 API 请求
class MediaServerCacheService {
  MediaServerCacheService();

  static const String _table = 'media_server_cache';

  Database? _db;

  Future<void> init() async {
    // 复用 VideoDatabaseService 的数据库
    await VideoDatabaseService().init();
    _db = VideoDatabaseService().database;
  }

  /// 获取缓存条目
  Future<MediaServerCacheEntry?> get(String sourceId, String itemId) async {
    if (_db == null) await init();

    final results = await _db!.query(
      _table,
      where: 'source_id = ? AND item_id = ?',
      whereArgs: [sourceId, itemId],
      limit: 1,
    );

    if (results.isEmpty) return null;
    return MediaServerCacheEntry.fromMap(results.first);
  }

  /// 获取子项列表
  Future<List<MediaServerCacheEntry>> getChildren(
    String sourceId,
    String? parentId,
  ) async {
    if (_db == null) await init();

    final results = await _db!.query(
      _table,
      where: parentId == null
          ? 'source_id = ? AND parent_id IS NULL'
          : 'source_id = ? AND parent_id = ?',
      whereArgs: parentId == null ? [sourceId] : [sourceId, parentId],
      orderBy: 'name ASC',
    );

    return results.map(MediaServerCacheEntry.fromMap).toList();
  }

  /// 按类型获取项目
  Future<List<MediaServerCacheEntry>> getByType(
    String sourceId,
    String itemType, {
    int? limit,
    int? offset,
  }) async {
    if (_db == null) await init();

    final results = await _db!.query(
      _table,
      where: 'source_id = ? AND item_type = ?',
      whereArgs: [sourceId, itemType],
      orderBy: 'name ASC',
      limit: limit,
      offset: offset,
    );

    return results.map(MediaServerCacheEntry.fromMap).toList();
  }

  /// 保存或更新缓存
  Future<void> upsert(MediaServerCacheEntry entry) async {
    if (_db == null) await init();

    await _db!.insert(
      _table,
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 批量保存
  Future<void> upsertAll(List<MediaServerCacheEntry> entries) async {
    if (_db == null) await init();
    if (entries.isEmpty) return;

    final batch = _db!.batch();
    for (final entry in entries) {
      batch.insert(
        _table,
        entry.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// 从 MediaItem 创建缓存条目
  MediaServerCacheEntry createEntry({
    required String sourceId,
    required MediaItem item,
    String? parentId,
  }) {
    final metadata = {
      'id': item.id,
      'name': item.name,
      'type': item.type.name,
      'year': item.productionYear,
      'overview': item.overview,
      'communityRating': item.communityRating,
      'runtimeTicks': item.runTimeTicks,
      'seriesName': item.seriesName,
      'seasonNumber': item.parentIndexNumber,
      'episodeNumber': item.indexNumber,
      'premiereDate': item.premiereDate?.toIso8601String(),
      'tmdbId': item.tmdbId,
      'imdbId': item.imdbId,
    };

    // 图片 URL 需要通过适配器的 getImageUrl 方法获取，这里不存储
    final imageUrls = <String, String>{};

    return MediaServerCacheEntry(
      id: '${sourceId}_${item.id}',
      sourceId: sourceId,
      itemId: item.id,
      parentId: parentId,
      itemType: item.type.name,
      name: item.name,
      metadataJson: jsonEncode(metadata),
      imageUrlsJson: imageUrls.isNotEmpty ? jsonEncode(imageUrls) : null,
      lastUpdated: DateTime.now(),
    );
  }

  /// 删除指定源的所有缓存
  Future<void> deleteBySource(String sourceId) async {
    if (_db == null) await init();

    await _db!.delete(
      _table,
      where: 'source_id = ?',
      whereArgs: [sourceId],
    );
    logger.i('MediaServerCacheService: 已删除源 $sourceId 的所有缓存');
  }

  /// 删除过期缓存
  Future<int> deleteExpired(Duration maxAge) async {
    if (_db == null) await init();

    final threshold = DateTime.now().subtract(maxAge).millisecondsSinceEpoch;
    final count = await _db!.delete(
      _table,
      where: 'last_updated < ?',
      whereArgs: [threshold],
    );
    if (count > 0) {
      logger.i('MediaServerCacheService: 已删除 $count 条过期缓存');
    }
    return count;
  }

  /// 检查缓存是否存在且有效
  Future<bool> isValid(String sourceId, String itemId, Duration maxAge) async {
    final entry = await get(sourceId, itemId);
    if (entry == null) return false;

    final age = DateTime.now().difference(entry.lastUpdated);
    return age < maxAge;
  }

  /// 获取缓存统计
  Future<Map<String, int>> getStats(String sourceId) async {
    if (_db == null) await init();

    final results = await _db!.rawQuery('''
      SELECT item_type, COUNT(*) as count
      FROM $_table
      WHERE source_id = ?
      GROUP BY item_type
    ''', [sourceId]);

    return {
      for (final row in results)
        row['item_type']! as String: row['count']! as int,
    };
  }
}

/// 媒体服务器缓存服务 Provider
final mediaServerCacheServiceProvider = Provider<MediaServerCacheService>((ref) => MediaServerCacheService());
