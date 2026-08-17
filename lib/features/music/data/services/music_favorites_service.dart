import 'dart:io';

import 'package:hive_ce/hive.dart';
import 'package:my_nas/core/utils/local_file_uri.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/music/data/services/music_cover_cache_service.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';

/// 音乐收藏项
class MusicFavoriteItem {
  const MusicFavoriteItem({
    required this.musicPath,
    required this.musicName,
    required this.musicUrl,
    required this.addedAt,
    this.sourceId,
    this.artist,
    this.album,
    this.coverUrl,
    this.duration,
  });

  factory MusicFavoriteItem.fromMap(Map<dynamic, dynamic> map) =>
      MusicFavoriteItem(
        musicPath: map['musicPath'] as String,
        musicName: map['musicName'] as String,
        musicUrl: map['musicUrl'] as String,
        sourceId: map['sourceId'] as String?,
        artist: map['artist'] as String?,
        album: map['album'] as String?,
        coverUrl: map['coverUrl'] as String?,
        duration: map['duration'] != null
            ? Duration(milliseconds: map['duration'] as int)
            : null,
        addedAt: DateTime.fromMillisecondsSinceEpoch(map['addedAt'] as int),
      );

  factory MusicFavoriteItem.fromMusicItem(MusicItem item) => MusicFavoriteItem(
    musicPath: item.path,
    musicName: item.name,
    musicUrl: item.url,
    sourceId: item.sourceId,
    artist: item.artist,
    album: item.album,
    coverUrl: item.coverUrl,
    duration: item.duration,
    addedAt: DateTime.now(),
  );

  final String musicPath;
  final String musicName;
  final String musicUrl;
  final String? sourceId;
  final String? artist;
  final String? album;
  final String? coverUrl;
  final Duration? duration;
  final DateTime addedAt;

  Map<String, dynamic> toMap() => {
    'musicPath': musicPath,
    'musicName': musicName,
    'musicUrl': musicUrl,
    'sourceId': sourceId,
    'artist': artist,
    'album': album,
    'coverUrl': coverUrl,
    'duration': duration?.inMilliseconds,
    'addedAt': addedAt.millisecondsSinceEpoch,
  };

  MusicItem toMusicItem() => MusicItem(
    id: musicPath,
    name: musicName,
    path: musicPath,
    url: musicUrl,
    sourceId: sourceId,
    artist: artist,
    album: album,
    coverUrl: _resolveEffectiveCoverUrl(),
    duration: duration,
  );

  /// 动态解析有效的封面 URL
  String? _resolveEffectiveCoverUrl() {
    // 1. 如果有存储的 coverUrl 且文件存在，使用它
    if (coverUrl != null && coverUrl!.isNotEmpty) {
      if (coverUrl!.startsWith('file://')) {
        final path = localPathFromFileUri(coverUrl!);
        if (path != null && File(path).existsSync()) {
          return coverUrl;
        }
      } else {
        return coverUrl; // 网络URL直接返回
      }
    }
    // 2. 尝试从缓存服务动态获取
    final coverCache = MusicCoverCacheService();
    final uniqueKey = '${sourceId ?? ''}_$musicPath';
    return coverCache.getCachedCoverUrl(uniqueKey);
  }
}

/// 音乐播放历史项
class MusicHistoryItem {
  const MusicHistoryItem({
    required this.musicPath,
    required this.musicName,
    required this.musicUrl,
    required this.playedAt,
    this.sourceId,
    this.artist,
    this.album,
    this.coverUrl,
    this.duration,
    this.lastPosition,
  });

  factory MusicHistoryItem.fromMusicItem(MusicItem item) => MusicHistoryItem(
    musicPath: item.path,
    musicName: item.name,
    musicUrl: item.url,
    sourceId: item.sourceId,
    artist: item.artist,
    album: item.album,
    coverUrl: item.coverUrl,
    duration: item.duration,
    playedAt: DateTime.now(),
    lastPosition: item.lastPosition,
  );

  factory MusicHistoryItem.fromMap(Map<dynamic, dynamic> map) =>
      MusicHistoryItem(
        musicPath: map['musicPath'] as String,
        musicName: map['musicName'] as String,
        musicUrl: map['musicUrl'] as String,
        sourceId: map['sourceId'] as String?,
        artist: map['artist'] as String?,
        album: map['album'] as String?,
        coverUrl: map['coverUrl'] as String?,
        duration: map['duration'] != null
            ? Duration(milliseconds: map['duration'] as int)
            : null,
        playedAt: DateTime.fromMillisecondsSinceEpoch(map['playedAt'] as int),
        lastPosition: map['lastPosition'] != null
            ? Duration(milliseconds: map['lastPosition'] as int)
            : null,
      );

  final String musicPath;
  final String musicName;
  final String musicUrl;
  final String? sourceId;
  final String? artist;
  final String? album;
  final String? coverUrl;
  final Duration? duration;
  final DateTime playedAt;
  final Duration? lastPosition;

  Map<String, dynamic> toMap() => {
    'musicPath': musicPath,
    'musicName': musicName,
    'musicUrl': musicUrl,
    'sourceId': sourceId,
    'artist': artist,
    'album': album,
    'coverUrl': coverUrl,
    'duration': duration?.inMilliseconds,
    'playedAt': playedAt.millisecondsSinceEpoch,
    'lastPosition': lastPosition?.inMilliseconds,
  };

  MusicItem toMusicItem() => MusicItem(
    id: musicPath,
    name: musicName,
    path: musicPath,
    url: musicUrl,
    sourceId: sourceId,
    artist: artist,
    album: album,
    coverUrl: _resolveEffectiveCoverUrl(),
    duration: duration,
    lastPosition: lastPosition ?? Duration.zero,
  );

  /// 动态解析有效的封面 URL
  String? _resolveEffectiveCoverUrl() {
    // 1. 如果有存储的 coverUrl 且文件存在，使用它
    if (coverUrl != null && coverUrl!.isNotEmpty) {
      if (coverUrl!.startsWith('file://')) {
        final path = localPathFromFileUri(coverUrl!);
        if (path != null && File(path).existsSync()) {
          return coverUrl;
        }
      } else {
        return coverUrl; // 网络URL直接返回
      }
    }
    // 2. 尝试从缓存服务动态获取
    final coverCache = MusicCoverCacheService();
    final uniqueKey = '${sourceId ?? ''}_$musicPath';
    return coverCache.getCachedCoverUrl(uniqueKey);
  }
}

/// 音乐收藏和历史服务
class MusicFavoritesService {
  factory MusicFavoritesService() => _instance ??= MusicFavoritesService._();
  MusicFavoritesService._();

  static MusicFavoritesService? _instance;

  static const _favoritesBoxName = 'music_favorites';
  static const _historyBoxName = 'music_history';
  static const _lastPlayedBoxName = 'music_last_played';
  static const _maxHistoryItems = 100;

  Box<Map<dynamic, dynamic>>? _favoritesBox;
  Box<Map<dynamic, dynamic>>? _historyBox;
  Box<Map<dynamic, dynamic>>? _lastPlayedBox;

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    try {
      _favoritesBox = await Hive.openBox<Map<dynamic, dynamic>>(
        _favoritesBoxName,
      );
      _historyBox = await Hive.openBox<Map<dynamic, dynamic>>(_historyBoxName);
      _lastPlayedBox = await Hive.openBox<Map<dynamic, dynamic>>(
        _lastPlayedBoxName,
      );
      _initialized = true;
      logger.i('MusicFavoritesService: 初始化完成');
    } on Exception catch (e) {
      logger.e('MusicFavoritesService: 初始化失败', e);
    }
  }

  // ==================== 收藏相关 ====================

  /// 添加到收藏
  Future<void> addToFavorites(MusicItem item) async {
    await init();
    if (_favoritesBox == null) return;

    final favorite = MusicFavoriteItem.fromMusicItem(item);
    await _favoritesBox!.put(item.path, favorite.toMap());
    logger.i('MusicFavoritesService: 添加收藏 ${item.name}');
  }

  /// 从收藏移除
  Future<void> removeFromFavorites(String musicPath) async {
    await init();
    if (_favoritesBox == null) return;

    await _favoritesBox!.delete(musicPath);
    logger.i('MusicFavoritesService: 移除收藏 $musicPath');
  }

  /// 检查是否已收藏
  Future<bool> isFavorite(String musicPath) async {
    await init();
    if (_favoritesBox == null) return false;

    return _favoritesBox!.containsKey(musicPath);
  }

  /// 切换收藏状态
  Future<bool> toggleFavorite(MusicItem item) async {
    final isFav = await isFavorite(item.path);
    if (isFav) {
      await removeFromFavorites(item.path);
      return false;
    } else {
      await addToFavorites(item);
      return true;
    }
  }

  /// 获取所有收藏
  Future<List<MusicFavoriteItem>> getAllFavorites() async {
    await init();
    if (_favoritesBox == null) return [];

    final favorites = <MusicFavoriteItem>[];
    for (final key in _favoritesBox!.keys) {
      final data = _favoritesBox!.get(key);
      if (data != null) {
        try {
          favorites.add(MusicFavoriteItem.fromMap(data));
        } on Exception catch (_) {
          // 跳过无效数据
        }
      }
    }

    // 按添加时间倒序排列
    favorites.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return favorites;
  }

  /// 清空所有收藏
  Future<void> clearAllFavorites() async {
    await init();
    if (_favoritesBox == null) return;

    await _favoritesBox!.clear();
    logger.i('MusicFavoritesService: 清空所有收藏');
  }

  // ==================== 历史相关 ====================

  /// 添加到播放历史
  Future<void> addToHistory(MusicItem item) async {
    await init();
    if (_historyBox == null) return;

    final history = MusicHistoryItem.fromMusicItem(item);
    await _historyBox!.put(item.path, history.toMap());

    // 限制历史记录数量
    await _trimHistory();

    logger.d('MusicFavoritesService: 添加播放历史 ${item.name}');
  }

  /// 更新播放位置
  Future<void> updatePlayPosition(String musicPath, Duration position) async {
    await init();
    if (_historyBox == null) return;

    final data = _historyBox!.get(musicPath);
    if (data != null) {
      final history = MusicHistoryItem.fromMap(data);
      final updated = MusicHistoryItem(
        musicPath: history.musicPath,
        musicName: history.musicName,
        musicUrl: history.musicUrl,
        artist: history.artist,
        album: history.album,
        coverUrl: history.coverUrl,
        duration: history.duration,
        playedAt: DateTime.now(),
        lastPosition: position,
      );
      await _historyBox!.put(musicPath, updated.toMap());
    }
  }

  /// 获取所有播放历史
  Future<List<MusicHistoryItem>> getAllHistory() async {
    await init();
    if (_historyBox == null) return [];

    final history = <MusicHistoryItem>[];
    for (final key in _historyBox!.keys) {
      final data = _historyBox!.get(key);
      if (data != null) {
        try {
          history.add(MusicHistoryItem.fromMap(data));
        } on Exception catch (_) {
          // 跳过无效数据
        }
      }
    }

    // 按播放时间倒序排列
    history.sort((a, b) => b.playedAt.compareTo(a.playedAt));
    return history;
  }

  /// 获取最近播放
  Future<List<MusicHistoryItem>> getRecentHistory({int limit = 20}) async {
    final all = await getAllHistory();
    return all.take(limit).toList();
  }

  /// 清空播放历史
  Future<void> clearAllHistory() async {
    await init();
    if (_historyBox == null) return;

    await _historyBox!.clear();
    logger.i('MusicFavoritesService: 清空播放历史');
  }

  /// 从历史中移除
  Future<void> removeFromHistory(String musicPath) async {
    await init();
    if (_historyBox == null) return;

    await _historyBox!.delete(musicPath);
  }

  /// 限制历史记录数量
  Future<void> _trimHistory() async {
    if (_historyBox == null) return;

    if (_historyBox!.length > _maxHistoryItems) {
      final history = await getAllHistory();
      final toRemove = history.skip(_maxHistoryItems).toList();
      for (final item in toRemove) {
        await _historyBox!.delete(item.musicPath);
      }
    }
  }

  // ==================== 最后播放状态相关 ====================

  /// 保存最后播放状态
  Future<void> saveLastPlayedState({
    required MusicItem music,
    required Duration position,
    required List<MusicItem> queue,
    required int queueIndex,
  }) async {
    await init();
    if (_lastPlayedBox == null) return;

    final state = {
      'music': MusicHistoryItem.fromMusicItem(music).toMap(),
      'position': position.inMilliseconds,
      'queueIndex': queueIndex,
      'queue': queue
          .map((m) => MusicHistoryItem.fromMusicItem(m).toMap())
          .toList(),
      'savedAt': DateTime.now().millisecondsSinceEpoch,
    };

    await _lastPlayedBox!.put('state', state);
    logger.d(
      'MusicFavoritesService: 保存播放状态 ${music.name} @ ${position.inSeconds}s',
    );
  }

  /// 获取最后播放状态
  Future<LastPlayedState?> getLastPlayedState() async {
    await init();
    if (_lastPlayedBox == null) return null;

    final data = _lastPlayedBox!.get('state');
    if (data == null) return null;

    try {
      final musicData = data['music'] as Map<dynamic, dynamic>?;
      if (musicData == null) return null;

      final music = MusicHistoryItem.fromMap(musicData).toMusicItem();
      final position = Duration(milliseconds: data['position'] as int? ?? 0);
      final queueIndex = data['queueIndex'] as int? ?? 0;

      final queueData = data['queue'] as List<dynamic>? ?? [];
      final queue = queueData
          .map(
            (m) => MusicHistoryItem.fromMap(
              m as Map<dynamic, dynamic>,
            ).toMusicItem(),
          )
          .toList();

      return LastPlayedState(
        music: music,
        position: position,
        queue: queue,
        queueIndex: queueIndex,
      );
    } on Exception catch (e) {
      logger.e('MusicFavoritesService: 解析播放状态失败', e);
      return null;
    }
  }

  /// 清除最后播放状态
  Future<void> clearLastPlayedState() async {
    await init();
    if (_lastPlayedBox == null) return;

    await _lastPlayedBox!.delete('state');
  }

  // ==================== 元数据更新相关 ====================

  /// 更新指定音乐的元数据
  ///
  /// 当刮削完成后调用此方法，更新收藏和播放历史中的元数据
  Future<void> updateMetadata(
    String musicPath, {
    String? title,
    String? artist,
    String? album,
    String? coverUrl,
  }) async {
    await init();

    // 更新收藏中的元数据
    if (_favoritesBox != null) {
      final favData = _favoritesBox!.get(musicPath);
      if (favData != null) {
        try {
          final fav = MusicFavoriteItem.fromMap(favData);
          final updated = MusicFavoriteItem(
            musicPath: fav.musicPath,
            musicName: title ?? fav.musicName,
            musicUrl: fav.musicUrl,
            sourceId: fav.sourceId,
            artist: artist ?? fav.artist,
            album: album ?? fav.album,
            coverUrl: coverUrl ?? fav.coverUrl,
            duration: fav.duration,
            addedAt: fav.addedAt,
          );
          await _favoritesBox!.put(musicPath, updated.toMap());
          logger.d('MusicFavoritesService: 更新收藏元数据 ${updated.musicName}');
        } on Exception catch (_) {
          // 跳过无效数据
        }
      }
    }

    // 更新播放历史中的元数据
    if (_historyBox != null) {
      final histData = _historyBox!.get(musicPath);
      if (histData != null) {
        try {
          final hist = MusicHistoryItem.fromMap(histData);
          final updated = MusicHistoryItem(
            musicPath: hist.musicPath,
            musicName: title ?? hist.musicName,
            musicUrl: hist.musicUrl,
            sourceId: hist.sourceId,
            artist: artist ?? hist.artist,
            album: album ?? hist.album,
            coverUrl: coverUrl ?? hist.coverUrl,
            duration: hist.duration,
            playedAt: hist.playedAt,
            lastPosition: hist.lastPosition,
          );
          await _historyBox!.put(musicPath, updated.toMap());
          logger.d('MusicFavoritesService: 更新播放历史元数据 ${updated.musicName}');
        } on Exception catch (_) {
          // 跳过无效数据
        }
      }
    }
  }

  /// 更新指定音乐的封面 URL
  ///
  /// 当刮削完成后调用此方法，更新收藏和播放历史中的封面
  Future<void> updateCoverUrl(String musicPath, String? newCoverUrl) async {
    await init();

    // 更新收藏中的封面
    if (_favoritesBox != null) {
      final favData = _favoritesBox!.get(musicPath);
      if (favData != null) {
        try {
          final fav = MusicFavoriteItem.fromMap(favData);
          final updated = MusicFavoriteItem(
            musicPath: fav.musicPath,
            musicName: fav.musicName,
            musicUrl: fav.musicUrl,
            sourceId: fav.sourceId,
            artist: fav.artist,
            album: fav.album,
            coverUrl: newCoverUrl,
            duration: fav.duration,
            addedAt: fav.addedAt,
          );
          await _favoritesBox!.put(musicPath, updated.toMap());
          logger.d('MusicFavoritesService: 更新收藏封面 ${fav.musicName}');
        } on Exception catch (_) {
          // 跳过无效数据
        }
      }
    }

    // 更新播放历史中的封面
    if (_historyBox != null) {
      final histData = _historyBox!.get(musicPath);
      if (histData != null) {
        try {
          final hist = MusicHistoryItem.fromMap(histData);
          final updated = MusicHistoryItem(
            musicPath: hist.musicPath,
            musicName: hist.musicName,
            musicUrl: hist.musicUrl,
            sourceId: hist.sourceId,
            artist: hist.artist,
            album: hist.album,
            coverUrl: newCoverUrl,
            duration: hist.duration,
            playedAt: hist.playedAt,
            lastPosition: hist.lastPosition,
          );
          await _historyBox!.put(musicPath, updated.toMap());
          logger.d('MusicFavoritesService: 更新播放历史封面 ${hist.musicName}');
        } on Exception catch (_) {
          // 跳过无效数据
        }
      }
    }
  }
}

/// 最后播放状态
class LastPlayedState {
  const LastPlayedState({
    required this.music,
    required this.position,
    required this.queue,
    required this.queueIndex,
  });

  final MusicItem music;
  final Duration position;
  final List<MusicItem> queue;
  final int queueIndex;
}
