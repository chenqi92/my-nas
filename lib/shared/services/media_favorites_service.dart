import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';

/// 通用媒体收藏服务（适用于 video / photo / note / comic / book）
///
/// 单 Hive box `media_favorites`，key 由 `${mediaType.id}|${sourceId}|${path}`
/// 组成，避免不同媒体类型的 path 撞车。
///
/// 不与 `MusicFavoritesService` 合并的原因：后者还跟踪播放历史 / 最后播放
/// 状态 / 封面缓存等音乐特化数据。
class MediaFavoritesService {
  factory MediaFavoritesService() => _instance ??= MediaFavoritesService._();
  MediaFavoritesService._();

  static MediaFavoritesService? _instance;

  static const String _boxName = 'media_favorites';

  Box<dynamic>? _box;

  Future<void> init() async {
    if (_box != null && _box!.isOpen) return;
    _box = await Hive.openBox<dynamic>(_boxName);
  }

  Future<void> _ensureInit() async {
    if (_box == null || !_box!.isOpen) {
      await init();
    }
  }

  /// 唯一 key：mediaType|sourceId|path
  static String _keyOf(MediaType type, String sourceId, String path) =>
      '${type.id}|$sourceId|$path';

  /// 是否已收藏
  Future<bool> isFavorite({
    required MediaType type,
    required String sourceId,
    required String path,
  }) async {
    await _ensureInit();
    return _box!.containsKey(_keyOf(type, sourceId, path));
  }

  /// 同步版本——调用前必须先 init() 过；用于 UI 同步路径（避免 build 中 await）
  bool isFavoriteSync({
    required MediaType type,
    required String sourceId,
    required String path,
  }) {
    final box = _box;
    if (box == null || !box.isOpen) return false;
    return box.containsKey(_keyOf(type, sourceId, path));
  }

  /// 添加收藏
  Future<void> add({
    required MediaType type,
    required String sourceId,
    required String path,
    required String displayName,
  }) async {
    await _ensureInit();
    await _box!.put(_keyOf(type, sourceId, path), {
      'mediaType': type.id,
      'sourceId': sourceId,
      'path': path,
      'displayName': displayName,
      'addedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// 移除收藏
  Future<void> remove({
    required MediaType type,
    required String sourceId,
    required String path,
  }) async {
    await _ensureInit();
    await _box!.delete(_keyOf(type, sourceId, path));
  }

  /// 切换收藏状态，返回切换后是否为已收藏
  Future<bool> toggle({
    required MediaType type,
    required String sourceId,
    required String path,
    required String displayName,
  }) async {
    final isCurrentlyFavorite = await isFavorite(
      type: type,
      sourceId: sourceId,
      path: path,
    );
    if (isCurrentlyFavorite) {
      await remove(type: type, sourceId: sourceId, path: path);
      return false;
    } else {
      await add(
        type: type,
        sourceId: sourceId,
        path: path,
        displayName: displayName,
      );
      return true;
    }
  }

  /// 获取指定类型的所有收藏（按 addedAt 倒序）
  ///
  /// 传 [type] 为 null 返回所有类型。
  Future<List<MediaFavoriteItem>> getAll({MediaType? type}) async {
    await _ensureInit();
    final result = <MediaFavoriteItem>[];
    for (final value in _box!.values) {
      if (value is! Map) continue;
      try {
        final item = MediaFavoriteItem.fromMap(
          Map<String, dynamic>.from(value),
        );
        if (type == null || item.type == type) {
          result.add(item);
        }
      } on Exception catch (e, st) {
        AppError.ignore(e, st, '解析 media favorite 失败');
      }
    }
    result.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return result;
  }

  /// 清空指定类型的收藏（type=null 清空全部）
  Future<void> clear({MediaType? type}) async {
    await _ensureInit();
    if (type == null) {
      await _box!.clear();
      return;
    }
    final keysToDelete = <dynamic>[];
    for (final entry in _box!.toMap().entries) {
      final v = entry.value;
      if (v is Map && v['mediaType'] == type.id) {
        keysToDelete.add(entry.key);
      }
    }
    await _box!.deleteAll(keysToDelete);
  }
}

/// 收藏条目
class MediaFavoriteItem {
  const MediaFavoriteItem({
    required this.type,
    required this.sourceId,
    required this.path,
    required this.displayName,
    required this.addedAt,
  });

  factory MediaFavoriteItem.fromMap(Map<String, dynamic> map) =>
      MediaFavoriteItem(
        type: MediaType.values.firstWhere(
          (t) => t.id == map['mediaType'],
          orElse: () => MediaType.note,
        ),
        sourceId: map['sourceId'] as String? ?? '',
        path: map['path'] as String? ?? '',
        displayName: map['displayName'] as String? ?? '',
        addedAt: DateTime.fromMillisecondsSinceEpoch(
          map['addedAt'] as int? ?? 0,
        ),
      );

  final MediaType type;
  final String sourceId;
  final String path;
  final String displayName;
  final DateTime addedAt;
}
