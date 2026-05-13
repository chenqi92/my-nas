import 'package:audio_service/audio_service.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/features/music/data/services/music_favorites_service.dart';
import 'package:my_nas/features/music/data/services/playlist_service.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';

/// MediaBrowserService 树根 ID
const String kMediaRootId = 'root';
const String kMediaFavoritesId = 'favorites';
const String kMediaRecentId = 'recent';
const String kMediaArtistsId = 'artists';
const String kMediaAlbumsId = 'albums';
const String kMediaPlaylistsId = 'playlists';
const String _kPlaylistPrefix = 'playlist:';
const String _kArtistPrefix = 'artist:';
const String _kAlbumPrefix = 'album:';
const String _kTrackPrefix = 'track:';

/// 提供给 Android Auto / CarPlay 浏览的内容树。
///
/// 树结构：
///   root
///   ├─ favorites          (用户收藏)
///   ├─ recent             (最近播放)
///   ├─ artists/`<name>`   (按艺术家分组，数据来自 favorites + history)
///   ├─ albums/`<name>`    (按专辑分组，数据来自 favorites + history)
///   └─ playlists/`<id>`   (用户歌单)
///
/// 播放回调由播放层注入：在 MusicPlayerNotifier 初始化时把
/// `playQueueByPaths` 函数注册到 [playFromPathsHandler]。当用户在车载界面
/// 触发播放时，本服务负责把 mediaId → 路径列表，再交给注入的回调真正起播。
class MusicBrowserService {
  MusicBrowserService._();
  static final MusicBrowserService instance = MusicBrowserService._();

  /// 由播放层注入：把一组 `(sourceId, path)` 入队并起播。
  ///
  /// `sourceId` 可以为 null（兼容老缓存里只有 path 的情况）；播放层会先查
  /// favorites + history 缓存，命中失败再用 sourceId 通过 NAS 适配器
  /// `getFileUrl(path)` 解析 URL。
  Future<void> Function(List<({String? sourceId, String path})> entries,
      int startIndex)? playFromPathsHandler;

  /// 根节点 / 所有可浏览节点
  Future<List<MediaItem>> getChildren(String parentMediaId) async {
    try {
      if (parentMediaId == AudioService.browsableRootId ||
          parentMediaId == kMediaRootId) {
        return _rootChildren();
      }
      if (parentMediaId == kMediaFavoritesId) return _favoriteChildren();
      if (parentMediaId == kMediaRecentId) return _recentChildren();
      if (parentMediaId == kMediaArtistsId) return _artistFolderChildren();
      if (parentMediaId == kMediaAlbumsId) return _albumFolderChildren();
      if (parentMediaId == kMediaPlaylistsId) return _playlistFolderChildren();
      if (parentMediaId.startsWith(_kPlaylistPrefix)) {
        return _playlistTrackChildren(
          parentMediaId.substring(_kPlaylistPrefix.length),
        );
      }
      if (parentMediaId.startsWith(_kArtistPrefix)) {
        return _tracksByArtist(parentMediaId.substring(_kArtistPrefix.length));
      }
      if (parentMediaId.startsWith(_kAlbumPrefix)) {
        return _tracksByAlbum(parentMediaId.substring(_kAlbumPrefix.length));
      }
      return const [];
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'browser.getChildren', {'parent': parentMediaId});
      return const [];
    }
  }

  Future<MediaItem?> getMediaItem(String mediaId) async {
    if (mediaId == kMediaFavoritesId) {
      return _folder(kMediaFavoritesId, '收藏');
    }
    if (mediaId == kMediaRecentId) {
      return _folder(kMediaRecentId, '最近播放');
    }
    if (mediaId == kMediaPlaylistsId) {
      return _folder(kMediaPlaylistsId, '播放列表');
    }
    return null;
  }

  /// 用户在 Auto / CarPlay 选中曲目后回调进来。
  Future<void> playFromMediaId(String mediaId) async {
    final handler = playFromPathsHandler;
    if (handler == null) return;

    if (mediaId.startsWith(_kTrackPrefix)) {
      // 单曲：曲目 id 编码为 `track:<sourceId>|<path>`，sourceId 可空
      final body = mediaId.substring(_kTrackPrefix.length);
      final entry = _parseTrackId(body);
      await handler([entry], 0);
      return;
    }

    if (mediaId.startsWith(_kPlaylistPrefix)) {
      // 整张歌单：从头开始播。歌单里只有 path，sourceId 留空让播放层自己查
      final id = mediaId.substring(_kPlaylistPrefix.length);
      final entry = await PlaylistService().getPlaylist(id);
      if (entry != null && entry.trackPaths.isNotEmpty) {
        await handler(
          [for (final p in entry.trackPaths) (sourceId: null, path: p)],
          0,
        );
      }
      return;
    }

    if (mediaId.startsWith(_kArtistPrefix)) {
      final artist = mediaId.substring(_kArtistPrefix.length);
      final tracks = await _collectKnownTracks();
      final entries = [
        for (final t in tracks)
          if ((t.artist ?? '').trim() == artist)
            (sourceId: t.sourceId, path: t.path),
      ];
      if (entries.isNotEmpty) await handler(entries, 0);
      return;
    }

    if (mediaId.startsWith(_kAlbumPrefix)) {
      final album = mediaId.substring(_kAlbumPrefix.length);
      final tracks = await _collectKnownTracks();
      final entries = [
        for (final t in tracks)
          if ((t.album ?? '').trim() == album)
            (sourceId: t.sourceId, path: t.path),
      ];
      if (entries.isNotEmpty) await handler(entries, 0);
      return;
    }

    if (mediaId == kMediaFavoritesId) {
      final favs = await MusicFavoritesService().getAllFavorites();
      final entries = [
        for (final f in favs) (sourceId: f.sourceId, path: f.musicPath),
      ];
      if (entries.isNotEmpty) await handler(entries, 0);
    }
  }

  /// 把 `<sourceId>|<path>` 拆回 (sourceId, path)。空字符串 sourceId 视为 null。
  ({String? sourceId, String path}) _parseTrackId(String body) {
    final i = body.indexOf('|');
    if (i < 0) return (sourceId: null, path: body);
    final src = body.substring(0, i);
    final path = body.substring(i + 1);
    return (sourceId: src.isEmpty ? null : src, path: path);
  }

  /// 语音搜索：按曲目名 / 歌手匹配收藏 + 最近播放。
  Future<void> playFromSearch(String query) async {
    final handler = playFromPathsHandler;
    if (handler == null || query.trim().isEmpty) return;
    final results = await search(query);
    if (results.isEmpty) return;
    final entries = <({String? sourceId, String path})>[];
    for (final m in results) {
      if (!m.id.startsWith(_kTrackPrefix)) continue;
      entries.add(_parseTrackId(m.id.substring(_kTrackPrefix.length)));
    }
    if (entries.isNotEmpty) await handler(entries, 0);
  }

  Future<List<MediaItem>> search(String query) async {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return const [];
    final favSvc = MusicFavoritesService();
    await favSvc.init();
    final favs = await favSvc.getAllFavorites();
    final history = await favSvc.getRecentHistory(limit: 200);

    final hits = <MediaItem>[];
    final seen = <String>{};
    for (final f in favs) {
      final name = f.musicName.toLowerCase();
      final artist = (f.artist ?? '').toLowerCase();
      if ((name.contains(q) || artist.contains(q)) && seen.add(f.musicPath)) {
        hits.add(_trackItem(
          sourceId: f.sourceId,
          path: f.musicPath,
          title: f.musicName,
          artist: f.artist,
          album: f.album,
          coverUrl: f.coverUrl,
          duration: f.duration,
        ));
      }
    }
    for (final h in history) {
      final name = h.musicName.toLowerCase();
      final artist = (h.artist ?? '').toLowerCase();
      if ((name.contains(q) || artist.contains(q)) && seen.add(h.musicPath)) {
        hits.add(_trackItem(
          sourceId: h.sourceId,
          path: h.musicPath,
          title: h.musicName,
          artist: h.artist,
          album: h.album,
          coverUrl: h.coverUrl,
          duration: h.duration,
        ));
      }
    }
    return hits;
  }

  // ============ 私有：构建子项 ============

  List<MediaItem> _rootChildren() => [
        _folder(kMediaFavoritesId, '收藏'),
        _folder(kMediaRecentId, '最近播放'),
        _folder(kMediaArtistsId, '艺术家'),
        _folder(kMediaAlbumsId, '专辑'),
        _folder(kMediaPlaylistsId, '播放列表'),
      ];

  Future<List<MediaItem>> _favoriteChildren() async {
    final svc = MusicFavoritesService();
    await svc.init();
    final list = await svc.getAllFavorites();
    return [
      for (final f in list)
        _trackItem(
          sourceId: f.sourceId,
          path: f.musicPath,
          title: f.musicName,
          artist: f.artist,
          album: f.album,
          coverUrl: f.coverUrl,
          duration: f.duration,
        ),
    ];
  }

  Future<List<MediaItem>> _recentChildren() async {
    final svc = MusicFavoritesService();
    await svc.init();
    final list = await svc.getRecentHistory(limit: 100);
    return [
      for (final h in list)
        _trackItem(
          sourceId: h.sourceId,
          path: h.musicPath,
          title: h.musicName,
          artist: h.artist,
          album: h.album,
          coverUrl: h.coverUrl,
          duration: h.duration,
        ),
    ];
  }

  Future<List<MediaItem>> _playlistFolderChildren() async {
    final list = await PlaylistService().getAllPlaylists();
    return [
      for (final p in list)
        MediaItem(
          id: '$_kPlaylistPrefix${p.id}',
          title: p.name,
          album: '${p.trackCount} 首',
          playable: false,
          extras: const {'browsable': true},
        ),
    ];
  }

  Future<List<MediaItem>> _playlistTrackChildren(String playlistId) async {
    final entry = await PlaylistService().getPlaylist(playlistId);
    if (entry == null) return const [];
    return [
      for (final p in entry.trackPaths)
        _trackItem(path: p, title: _basenameOf(p)),
    ];
  }

  // ============ 私有：按艺术家 / 专辑分组 ============
  //
  // 数据来源仅限本地有 musicUrl 缓存的曲目（favorites + history）；
  // 跨设备 / 大库扫描需要 NAS 适配器把全库索引暴露上来，目前不做。

  /// 收集所有可用条目（去重，path 主键）
  Future<List<_BrowserTrack>> _collectKnownTracks() async {
    final svc = MusicFavoritesService();
    await svc.init();
    final favs = await svc.getAllFavorites();
    final history = await svc.getRecentHistory(limit: 500);
    final byPath = <String, _BrowserTrack>{};
    for (final f in favs) {
      byPath[f.musicPath] = _BrowserTrack(
        sourceId: f.sourceId,
        path: f.musicPath,
        title: f.musicName,
        artist: f.artist,
        album: f.album,
        coverUrl: f.coverUrl,
        duration: f.duration,
      );
    }
    for (final h in history) {
      byPath.putIfAbsent(
        h.musicPath,
        () => _BrowserTrack(
          sourceId: h.sourceId,
          path: h.musicPath,
          title: h.musicName,
          artist: h.artist,
          album: h.album,
          coverUrl: h.coverUrl,
          duration: h.duration,
        ),
      );
    }
    return byPath.values.toList();
  }

  Future<List<MediaItem>> _artistFolderChildren() async {
    final tracks = await _collectKnownTracks();
    final byArtist = <String, int>{};
    for (final t in tracks) {
      final a = (t.artist ?? '').trim();
      if (a.isEmpty) continue;
      byArtist[a] = (byArtist[a] ?? 0) + 1;
    }
    final names = byArtist.keys.toList()..sort();
    return [
      for (final a in names)
        MediaItem(
          id: '$_kArtistPrefix$a',
          title: a,
          album: '${byArtist[a]} 首',
          playable: false,
          extras: const {'browsable': true},
        ),
    ];
  }

  Future<List<MediaItem>> _albumFolderChildren() async {
    final tracks = await _collectKnownTracks();
    final byAlbum = <String, int>{};
    for (final t in tracks) {
      final a = (t.album ?? '').trim();
      if (a.isEmpty) continue;
      byAlbum[a] = (byAlbum[a] ?? 0) + 1;
    }
    final names = byAlbum.keys.toList()..sort();
    return [
      for (final a in names)
        MediaItem(
          id: '$_kAlbumPrefix$a',
          title: a,
          album: '${byAlbum[a]} 首',
          playable: false,
          extras: const {'browsable': true},
        ),
    ];
  }

  Future<List<MediaItem>> _tracksByArtist(String artist) async {
    final tracks = await _collectKnownTracks();
    return [
      for (final t in tracks)
        if ((t.artist ?? '').trim() == artist)
          _trackItem(
            sourceId: t.sourceId,
            path: t.path,
            title: t.title,
            artist: t.artist,
            album: t.album,
            coverUrl: t.coverUrl,
            duration: t.duration,
          ),
    ];
  }

  Future<List<MediaItem>> _tracksByAlbum(String album) async {
    final tracks = await _collectKnownTracks();
    return [
      for (final t in tracks)
        if ((t.album ?? '').trim() == album)
          _trackItem(
            sourceId: t.sourceId,
            path: t.path,
            title: t.title,
            artist: t.artist,
            album: t.album,
            coverUrl: t.coverUrl,
            duration: t.duration,
          ),
    ];
  }

  MediaItem _folder(String id, String title) => MediaItem(
        id: id,
        title: title,
        playable: false,
        extras: const {'browsable': true},
      );

  MediaItem _trackItem({
    required String path,
    required String title,
    String? sourceId,
    String? artist,
    String? album,
    String? coverUrl,
    Duration? duration,
  }) {
    final art =
        coverUrl != null && coverUrl.isNotEmpty ? Uri.tryParse(coverUrl) : null;
    final id = '$_kTrackPrefix${sourceId ?? ''}|$path';
    return MediaItem(
      id: id,
      title: title,
      artist: artist,
      album: album,
      duration: duration,
      artUri: art,
      playable: true,
    );
  }

  String _basenameOf(String path) {
    final i = path.lastIndexOf('/');
    if (i < 0) return path;
    return path.substring(i + 1);
  }

  /// 由播放层调用：根据收藏/历史里的元数据构造一个最小可播放的 [MusicItem]。
  /// 若信息不全，调用方仍需在拿到队列后用真正的源管理器解析 url。
  static MusicItem buildMusicItemFromFavorite(MusicFavoriteItem f) =>
      MusicItem(
        id: '${f.sourceId ?? ''}_${f.musicPath}',
        name: f.musicName,
        path: f.musicPath,
        url: f.musicUrl,
        sourceId: f.sourceId,
        title: f.musicName,
        artist: f.artist,
        album: f.album,
        coverUrl: f.coverUrl,
        duration: f.duration,
      );
}

/// 浏览树用的轻量曲目快照（去重后的统一视图）
class _BrowserTrack {
  _BrowserTrack({
    required this.path,
    required this.title,
    this.sourceId,
    this.artist,
    this.album,
    this.coverUrl,
    this.duration,
  });

  final String? sourceId;
  final String path;
  final String title;
  final String? artist;
  final String? album;
  final String? coverUrl;
  final Duration? duration;
}
