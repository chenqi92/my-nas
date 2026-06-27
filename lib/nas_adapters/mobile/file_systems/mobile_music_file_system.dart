import 'dart:io';
import 'dart:typed_data';

import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:on_audio_query/on_audio_query.dart';

/// 移动端音乐库文件系统
///
/// 将系统音乐库映射为虚拟文件系统结构：
/// - /songs/          - 所有歌曲
/// - /albums/         - 按专辑分组
/// - /artists/        - 按艺术家分组
/// - /playlists/      - 播放列表
///
/// 路径格式：
/// - music://songs/{songId}
/// - music://albums/{albumId}/{songId}
/// - music://artists/{artistId}/{songId}
class MobileMusicFileSystem implements NasFileSystem {
  MobileMusicFileSystem();

  final OnAudioQuery _audioQuery = OnAudioQuery();

  @override
  bool get supportsWriteOperations => false;

  @override
  bool get supportsServerSideCopy => false;

  @override
  bool get supportsDirectFileUrl => false;

  List<SongModel>? _cachedSongs;
  List<AlbumModel>? _cachedAlbums;
  List<ArtistModel>? _cachedArtists;
  final Map<int, SongModel> _songCache = {};

  /// 请求音乐库访问权限
  ///
  /// iOS 需要 NSAppleMusicUsageDescription 权限声明才能访问 Apple Music 库
  /// Android 需要 READ_EXTERNAL_STORAGE 权限
  Future<bool> requestPermission() async {
    logger.d('🎵 MobileMusicFileSystem: 请求音乐库权限...');
    // iOS 和 Android 都需要请求权限
    final hasPermission = await _audioQuery.permissionsStatus();
    logger.d('🎵 MobileMusicFileSystem: 当前权限状态: $hasPermission');
    if (!hasPermission) {
      final granted = await _audioQuery.permissionsRequest();
      logger.d('🎵 MobileMusicFileSystem: 权限请求结果: $granted');
      if (!granted) {
        logger.w('MobileMusicFileSystem: 权限被拒绝 (${Platform.operatingSystem})');
        return false;
      }
    }
    logger.d('🎵 MobileMusicFileSystem: ✓ 权限已获取');
    return true;
  }

  /// 刷新缓存
  Future<void> refreshCache() async {
    _cachedSongs = null;
    _cachedAlbums = null;
    _cachedArtists = null;
    _songCache.clear();
  }

  /// 获取所有歌曲
  Future<List<SongModel>> _getSongs() async {
    logger.d(
      '🎵 MobileMusicFileSystem: _getSongs() 被调用, _cachedSongs=${_cachedSongs?.length}',
    );
    if (_cachedSongs != null) {
      logger.d(
        '🎵 MobileMusicFileSystem: 使用缓存歌曲列表，数量: ${_cachedSongs!.length}',
      );
      return _cachedSongs!;
    }

    logger.d('🎵 MobileMusicFileSystem: 开始查询歌曲...');
    _cachedSongs = await _audioQuery.querySongs(
      sortType: SongSortType.DATE_ADDED,
      orderType: OrderType.DESC_OR_GREATER,
      uriType: UriType.EXTERNAL,
    );

    logger.d(
      '🎵 MobileMusicFileSystem: querySongs 返回 ${_cachedSongs!.length} 首歌曲',
    );

    // 缓存歌曲
    for (final song in _cachedSongs!) {
      _songCache[song.id] = song;
    }

    // 打印前几首歌曲的信息用于调试
    for (var i = 0; i < _cachedSongs!.length && i < 3; i++) {
      final song = _cachedSongs![i];
      logger.d(
        '🎵   - ${song.displayName} (ext: ${song.fileExtension}, size: ${song.size})',
      );
    }

    if (_cachedSongs!.isEmpty) {
      logger.w('🎵 MobileMusicFileSystem: ⚠️ 歌曲列表为空！');
    }

    return _cachedSongs!;
  }

  /// 获取所有专辑
  Future<List<AlbumModel>> _getAlbums() async {
    if (_cachedAlbums != null) return _cachedAlbums!;

    _cachedAlbums = await _audioQuery.queryAlbums(
      sortType: AlbumSortType.ALBUM,
      orderType: OrderType.ASC_OR_SMALLER,
    );

    return _cachedAlbums!;
  }

  /// 获取所有艺术家
  Future<List<ArtistModel>> _getArtists() async {
    if (_cachedArtists != null) return _cachedArtists!;

    _cachedArtists = await _audioQuery.queryArtists(
      sortType: ArtistSortType.ARTIST,
      orderType: OrderType.ASC_OR_SMALLER,
    );

    return _cachedArtists!;
  }

  @override
  Future<List<FileItem>> listDirectory(String path) async {
    logger.d('MobileMusicFileSystem: listDirectory - $path');

    // 根目录
    if (path == '/' || path.isEmpty) {
      logger.d('🎵 MobileMusicFileSystem: → 调用 _listRoot()');
      return _listRoot();
    }

    // 所有歌曲
    if (path == '/songs' || path == '/songs/') {
      return _listAllSongs();
    }

    // 专辑列表
    if (path == '/albums' || path == '/albums/') {
      return _listAlbums();
    }

    // 艺术家列表
    if (path == '/artists' || path == '/artists/') {
      return _listArtists();
    }

    // 具体专辑内容
    if (path.startsWith('/albums/')) {
      final segments = path.replaceFirst('/albums/', '').split('/');
      final albumId = int.tryParse(segments.first);

      // 如果路径包含多个段（如 /albums/{albumId}/{songId}），
      // 说明是访问具体歌曲，不是目录，返回空列表
      if (segments.length > 1 && segments[1].isNotEmpty) {
        logger.d('MobileMusicFileSystem: 跳过歌曲路径 - $path');
        return [];
      }

      if (albumId != null) {
        return _listAlbumSongs(albumId);
      }
    }

    // 具体艺术家内容
    if (path.startsWith('/artists/')) {
      final segments = path.replaceFirst('/artists/', '').split('/');
      final artistId = int.tryParse(segments.first);

      // 如果路径包含多个段，说明是访问具体歌曲
      if (segments.length > 1 && segments[1].isNotEmpty) {
        logger.d('MobileMusicFileSystem: 跳过歌曲路径 - $path');
        return [];
      }

      if (artistId != null) {
        return _listArtistSongs(artistId);
      }
    }

    return [];
  }

  /// 列出根目录
  Future<List<FileItem>> _listRoot() async {
    logger.d('🎵 MobileMusicFileSystem: _listRoot() 开始');
    final songs = await _getSongs();
    final albums = await _getAlbums();
    final artists = await _getArtists();

    logger.d(
      '🎵 MobileMusicFileSystem: _listRoot() 返回 songs=${songs.length}, albums=${albums.length}, artists=${artists.length}',
    );

    return [
      FileItem(
        name: 'songs (${songs.length})',
        path: '/songs',
        isDirectory: true,
        size: songs.length,
      ),
      FileItem(
        name: 'albums (${albums.length})',
        path: '/albums',
        isDirectory: true,
        size: albums.length,
      ),
      FileItem(
        name: 'artists (${artists.length})',
        path: '/artists',
        isDirectory: true,
        size: artists.length,
      ),
    ];
  }

  /// 列出所有歌曲
  Future<List<FileItem>> _listAllSongs() async {
    final songs = await _getSongs();
    return songs.map((song) => _songToFileItem(song, '/songs')).toList();
  }

  /// 列出所有专辑
  Future<List<FileItem>> _listAlbums() async {
    final albums = await _getAlbums();
    return albums
        .map(
          (album) => FileItem(
            name: album.album,
            path: '/albums/${album.id}',
            isDirectory: true,
            size: album.numOfSongs,
          ),
        )
        .toList();
  }

  /// 列出所有艺术家
  Future<List<FileItem>> _listArtists() async {
    final artists = await _getArtists();
    return artists
        .map(
          (artist) => FileItem(
            name: artist.artist,
            path: '/artists/${artist.id}',
            isDirectory: true,
            size: artist.numberOfTracks ?? 0,
          ),
        )
        .toList();
  }

  /// 列出专辑内歌曲
  Future<List<FileItem>> _listAlbumSongs(int albumId) async {
    final songs = await _audioQuery.queryAudiosFrom(
      AudiosFromType.ALBUM_ID,
      albumId,
    );

    for (final song in songs) {
      _songCache[song.id] = song;
    }

    return songs
        .map((song) => _songToFileItem(song, '/albums/$albumId'))
        .toList();
  }

  /// 列出艺术家的歌曲
  Future<List<FileItem>> _listArtistSongs(int artistId) async {
    final songs = await _audioQuery.queryAudiosFrom(
      AudiosFromType.ARTIST_ID,
      artistId,
    );

    for (final song in songs) {
      _songCache[song.id] = song;
    }

    return songs
        .map((song) => _songToFileItem(song, '/artists/$artistId'))
        .toList();
  }

  /// 将 SongModel 转换为 FileItem
  FileItem _songToFileItem(SongModel song, String parentPath) {
    // 从文件名获取扩展名
    final displayName = song.displayName;
    String? extension;
    if (displayName.contains('.')) {
      extension = displayName.split('.').last.toLowerCase();
    }

    // 构建正确的 mimeType（on_audio_query 的 fileExtension 只是扩展名，不是完整的 mimeType）
    // 需要转换为 "audio/mp3" 格式
    final ext = extension ?? song.fileExtension.toLowerCase();
    // 常见音频格式映射
    final mimeType = switch (ext) {
      'mp3' => 'audio/mpeg',
      'm4a' => 'audio/mp4',
      'aac' => 'audio/aac',
      'wav' => 'audio/wav',
      'flac' => 'audio/flac',
      'ogg' => 'audio/ogg',
      'wma' => 'audio/x-ms-wma',
      'aiff' || 'aif' => 'audio/aiff',
      'opus' => 'audio/opus',
      _ => 'audio/$ext',
    };
    extension ??= ext;

    return FileItem(
      name: displayName,
      path: '$parentPath/${song.id}',
      isDirectory: false,
      size: song.size,
      modifiedTime: song.dateModified != null
          ? DateTime.fromMillisecondsSinceEpoch(song.dateModified! * 1000)
          : null,
      createdTime: song.dateAdded != null
          ? DateTime.fromMillisecondsSinceEpoch(song.dateAdded! * 1000)
          : null,
      extension: extension,
      mimeType: mimeType,
    );
  }

  @override
  Future<FileItem> getFileInfo(String path) async {
    final songId = int.tryParse(path.split('/').last);
    if (songId == null) {
      throw Exception(appL10n.mobileMusicInvalidSongId(path));
    }

    final song = _songCache[songId];
    if (song == null) {
      throw Exception(appL10n.mobileMusicSongNotFound(songId));
    }

    return _songToFileItem(song, path.substring(0, path.lastIndexOf('/')));
  }

  @override
  Future<Stream<List<int>>> getFileStream(
    String path, {
    FileRange? range,
  }) async {
    final songId = int.tryParse(path.split('/').last);
    if (songId == null) {
      throw Exception(appL10n.mobileMusicInvalidSongId(path));
    }

    final song = _songCache[songId];
    if (song == null) {
      throw Exception(appL10n.mobileMusicSongNotFound(songId));
    }

    final file = File(song.data);
    if (!await file.exists()) {
      throw Exception(appL10n.mobileMusicFileNotFound(song.data));
    }

    if (range != null) {
      final length = await file.length();
      // FileRange.end 为排他边界（同 openRead 的 end），null 表示读到文件结尾
      final end = range.end ?? length;
      return file.openRead(range.start, end);
    }

    return file.openRead();
  }

  @override
  Future<String> getFileUrl(String path, {Duration? expiry}) async {
    final songId = int.tryParse(path.split('/').last);
    if (songId == null) {
      throw Exception(appL10n.mobileMusicInvalidSongId(path));
    }

    final song = _songCache[songId];
    if (song == null) {
      throw Exception(appL10n.mobileMusicSongNotFound(songId));
    }

    return File(song.data).uri.toString();
  }

  // on_audio_query 不支持缩略图 URL
  @override
  Future<String?> getThumbnailUrl(String path, {ThumbnailSize? size}) async =>
      null;

  /// 获取歌曲封面作为缩略图数据
  @override
  Future<Uint8List?> getThumbnailData(
    String path, {
    ThumbnailSize? size,
  }) async {
    final songId = int.tryParse(path.split('/').last);
    if (songId == null) return null;
    return getSongArtwork(songId, size: size);
  }

  @override
  Future<Stream<List<int>>> getUrlStream(String url) {
    throw UnimplementedError(appL10n.mobileMusicUrlStreamUnsupported);
  }

  /// 获取专辑封面数据
  Future<Uint8List?> getAlbumArtwork(int albumId, {ThumbnailSize? size}) async {
    final thumbnailSize = size ?? ThumbnailSize.medium;
    return _audioQuery.queryArtwork(
      albumId,
      ArtworkType.ALBUM,
      size: thumbnailSize.pixels,
    );
  }

  /// 获取歌曲封面数据
  Future<Uint8List?> getSongArtwork(int songId, {ThumbnailSize? size}) async {
    final thumbnailSize = size ?? ThumbnailSize.medium;
    return _audioQuery.queryArtwork(
      songId,
      ArtworkType.AUDIO,
      size: thumbnailSize.pixels,
    );
  }

  /// 获取歌曲模型
  SongModel? getSong(int songId) => _songCache[songId];

  // ==================== 不支持的写操作 ====================

  @override
  Future<void> createDirectory(String path) async {
    throw UnsupportedError(appL10n.mobileMusicCreateDirectoryUnsupported);
  }

  @override
  Future<void> delete(String path) async {
    throw UnsupportedError(appL10n.mobileMusicDeleteUnsupported);
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {
    throw UnsupportedError(appL10n.mobileMusicRenameUnsupported);
  }

  @override
  Future<void> copy(String sourcePath, String destPath) async {
    throw UnsupportedError(appL10n.mobileMusicCopyUnsupported);
  }

  @override
  Future<void> move(String sourcePath, String destPath) async {
    throw UnsupportedError(appL10n.mobileMusicMoveUnsupported);
  }

  @override
  Future<void> upload(
    String localPath,
    String remotePath, {
    String? fileName,
    void Function(int sent, int total)? onProgress,
  }) async {
    throw UnsupportedError(appL10n.mobileMusicUploadUnsupported);
  }

  @override
  Future<void> writeFile(String remotePath, List<int> data) async {
    throw UnsupportedError(appL10n.mobileMusicWriteUnsupported);
  }

  @override
  Future<List<FileItem>> search(String query, {String? path}) async {
    final songs = await _getSongs();
    final queryLower = query.toLowerCase();

    final results = <FileItem>[];
    for (final song in songs) {
      final title = song.title.toLowerCase();
      final artist = song.artist?.toLowerCase() ?? '';
      final album = song.album?.toLowerCase() ?? '';

      if (title.contains(queryLower) ||
          artist.contains(queryLower) ||
          album.contains(queryLower)) {
        results.add(_songToFileItem(song, '/songs'));
      }
    }

    return results;
  }
}
