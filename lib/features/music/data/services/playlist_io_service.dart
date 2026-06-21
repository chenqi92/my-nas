import 'dart:convert';
import 'dart:io';

import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/music/data/services/duplicate_detector.dart';
import 'package:my_nas/features/music/data/services/music_database_service.dart';
import 'package:my_nas/features/music/data/services/playlist_service.dart';
import 'package:path/path.dart' as p;

/// 歌单导入导出。支持两种格式：
/// - **m3u8**：通用，文本格式 `#EXTM3U` + `#EXTINF:duration,artist - title` + 行
/// - **my-nas JSON**：自定义，含 trackPath / 元数据，跨设备导入命中率最高
class PlaylistIoService {
  PlaylistIoService._();
  static final PlaylistIoService instance = PlaylistIoService._();

  final _playlistService = PlaylistService();
  final _db = MusicDatabaseService();

  // ---------------------------- 导出 ----------------------------

  /// 导出为 m3u8 格式（UTF-8 编码）。
  /// 仅写入轨道路径相对元数据，不携带文件本体。
  Future<String> exportM3u8(PlaylistEntry playlist) async {
    await _db.init();
    final index = await _buildTrackIndex();
    final lines = <String>['#EXTM3U', '#PLAYLIST:${playlist.name}'];
    for (final path in playlist.trackPaths) {
      final track = index[path];
      final duration = (track?.duration ?? 0) ~/ 1000;
      final artist = track?.displayArtist ?? '';
      final title = track?.displayTitle ?? p.basenameWithoutExtension(path);
      final extinfPayload = artist.isEmpty ? title : '$artist - $title';
      lines
        ..add('#EXTINF:$duration,$extinfPayload')
        ..add(path);
    }
    return lines.join('\n');
  }

  /// 导出为 my-nas JSON：携带每曲的 sourceId / path / title / artist / album / duration / size，
  /// 导入端可用三级匹配 + qualityScore 选最优本地版本。
  Future<String> exportJson(PlaylistEntry playlist) async {
    await _db.init();
    final index = await _buildTrackIndex();
    final tracks = <Map<String, dynamic>>[];
    for (final path in playlist.trackPaths) {
      final t = index[path];
      tracks.add({
        'path': path,
        if (t != null) ...{
          'sourceId': t.sourceId,
          'fileName': t.fileName,
          'title': t.title,
          'artist': t.artist,
          'album': t.album,
          'duration': t.duration,
          'size': t.size,
        },
      });
    }
    final payload = <String, dynamic>{
      'format': 'my-nas-playlist',
      'version': 1,
      'name': playlist.name,
      'description': playlist.description,
      'createdAt': playlist.createdAt.millisecondsSinceEpoch,
      'tracks': tracks,
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// 一次性加载全库并构建 `filePath -> track` 索引，导出时 O(1) 查找。
  /// 同一 filePath 多命中时保留首个（与旧线性扫描首命中语义一致）。
  Future<Map<String, MusicTrackEntity>> _buildTrackIndex() async {
    final all = await _db.getPage(limit: 100000);
    final index = <String, MusicTrackEntity>{};
    for (final t in all) {
      index.putIfAbsent(t.filePath, () => t);
    }
    return index;
  }

  // ---------------------------- 导入 ----------------------------

  /// 解析 m3u8 文本。
  ///
  /// 返回 `(name, [(originalPath, extInfTitle?, extInfArtist?)])`
  ({String name, List<_M3uTrack> tracks}) parseM3u8(String content) {
    final lines = content.split('\n');
    var name = appL10n.playlistIoImportedPlaylistDefaultName;
    final tracks = <_M3uTrack>[];
    String? pendingTitle;
    String? pendingArtist;

    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#PLAYLIST:')) {
        name = line.substring('#PLAYLIST:'.length).trim();
      } else if (line.startsWith('#EXTINF:')) {
        // #EXTINF:duration,artist - title
        final payload = line.substring('#EXTINF:'.length);
        final commaIdx = payload.indexOf(',');
        if (commaIdx > 0 && commaIdx + 1 < payload.length) {
          final tail = payload.substring(commaIdx + 1).trim();
          final dashIdx = tail.indexOf(' - ');
          if (dashIdx > 0) {
            pendingArtist = tail.substring(0, dashIdx).trim();
            pendingTitle = tail.substring(dashIdx + 3).trim();
          } else {
            pendingTitle = tail;
          }
        }
      } else if (!line.startsWith('#')) {
        tracks.add(_M3uTrack(
          path: line,
          extTitle: pendingTitle,
          extArtist: pendingArtist,
        ));
        pendingTitle = null;
        pendingArtist = null;
      }
    }
    return (name: name, tracks: tracks);
  }

  /// 把 m3u8 / JSON 文件导入为新的 playlist。返回新建 playlist。
  Future<PlaylistEntry?> importFromFile(String filePath) async {
    final content = await File(filePath).readAsString();
    if (filePath.toLowerCase().endsWith('.json')) {
      return _importJson(content);
    }
    return _importM3u8(content);
  }

  Future<PlaylistEntry?> _importM3u8(String content) async {
    await _db.init();
    final parsed = parseM3u8(content);
    final all = await _db.getPage(limit: 100000);
    final resolved = <String>[];
    var matched = 0;
    for (final entry in parsed.tracks) {
      final track = _matchTrack(
        all,
        path: entry.path,
        title: entry.extTitle,
        artist: entry.extArtist,
      );
      if (track != null) {
        resolved.add(track.filePath);
        matched++;
      }
    }
    logger.i(
      'PlaylistIo: m3u8 导入 ${parsed.tracks.length} 项命中 $matched',
    );
    return _playlistService.createPlaylist(
      name: parsed.name,
      initialTracks: resolved,
    );
  }

  Future<PlaylistEntry?> _importJson(String content) async {
    final data = jsonDecode(content) as Map<String, dynamic>;
    if (data['format'] != 'my-nas-playlist') {
      logger.w('PlaylistIo: JSON 格式不匹配，期待 my-nas-playlist');
      return null;
    }
    final name = data['name'] as String? ?? appL10n.playlistIoImportedPlaylistDefaultName;
    final tracks = (data['tracks'] as List).cast<Map<dynamic, dynamic>>();

    await _db.init();
    final all = await _db.getPage(limit: 100000);
    final resolved = <String>[];
    var matched = 0;
    for (final t in tracks) {
      final m = t.cast<String, dynamic>();
      final originalPath = m['path'] as String?;
      final title = m['title'] as String?;
      final artist = m['artist'] as String?;
      final fileName = m['fileName'] as String?;
      final track = _matchTrack(
        all,
        path: originalPath,
        title: title,
        artist: artist,
        fileName: fileName,
      );
      if (track != null) {
        resolved.add(track.filePath);
        matched++;
      }
    }
    logger.i('PlaylistIo: JSON 导入 ${tracks.length} 项命中 $matched');
    return _playlistService.createPlaylist(
      name: name,
      description: data['description'] as String?,
      initialTracks: resolved,
    );
  }

  /// 三级匹配：原 path 完全匹配 > basename + ext 匹配 > (title, artist) 模糊匹配。
  /// 多命中时按 [DuplicateDetector.qualityScore] 选最高质量本地版本。
  MusicTrackEntity? _matchTrack(
    List<MusicTrackEntity> all, {
    String? path,
    String? title,
    String? artist,
    String? fileName,
  }) {
    if (path != null && path.isNotEmpty) {
      for (final t in all) {
        if (t.filePath == path) return t;
      }
      // 文件名匹配（路径变了但文件名一致）
      final base = p.basename(path);
      final byBase = all.where((t) => t.fileName == base).toList();
      if (byBase.length == 1) return byBase.first;
      if (byBase.length > 1) {
        byBase.sort(
          (a, b) => DuplicateDetector.qualityScore(b)
              .compareTo(DuplicateDetector.qualityScore(a)),
        );
        return byBase.first;
      }
    }

    if (fileName != null && fileName.isNotEmpty) {
      final byName = all.where((t) => t.fileName == fileName).toList();
      if (byName.length == 1) return byName.first;
      if (byName.length > 1) {
        byName.sort(
          (a, b) => DuplicateDetector.qualityScore(b)
              .compareTo(DuplicateDetector.qualityScore(a)),
        );
        return byName.first;
      }
    }

    if (title != null && title.isNotEmpty) {
      final lowerT = title.toLowerCase().trim();
      final lowerA = artist?.toLowerCase().trim() ?? '';
      final fuzzy = all.where((t) {
        final ttl = t.displayTitle.toLowerCase().trim();
        if (!ttl.contains(lowerT) && !lowerT.contains(ttl)) return false;
        if (lowerA.isEmpty) return true;
        final ar = t.displayArtist.toLowerCase().trim();
        return ar == lowerA || ar.contains(lowerA) || lowerA.contains(ar);
      }).toList();
      if (fuzzy.isNotEmpty) {
        fuzzy.sort(
          (a, b) => DuplicateDetector.qualityScore(b)
              .compareTo(DuplicateDetector.qualityScore(a)),
        );
        return fuzzy.first;
      }
    }

    return null;
  }
}

class _M3uTrack {
  const _M3uTrack({
    required this.path,
    this.extTitle,
    this.extArtist,
  });
  final String path;
  final String? extTitle;
  final String? extArtist;
}
