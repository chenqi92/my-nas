import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

/// 音乐项实体
class MusicItem {
  const MusicItem({
    required this.id,
    required this.name,
    required this.path,
    required this.url,
    this.sourceId,
    this.title,
    this.artist,
    this.album,
    this.duration,
    this.coverUrl,
    this.size,
    this.lastPosition = Duration.zero,
    this.folder,
    this.trackNumber,
    this.year,
    this.genre,
    this.lyrics,
    this.coverData,
  }); // 嵌入的封面图片数据

  /// 从文件项创建音乐项
  factory MusicItem.fromFileItem(
    FileItem file,
    String url, {
    String? sourceId,
    // 可选的预提取元数据
    String? title,
    String? artist,
    String? album,
    int? durationMs,
    int? trackNumber,
    int? year,
    String? genre,
    List<int>? coverData,
    String? coverUrl,
  }) {
    final parsed = parseFileName(file.name);
    final folderPath = file.path.split('/');
    final folderName = folderPath.length >= 2 ? folderPath[folderPath.length - 2] : '';

    return MusicItem(
      id: '${sourceId ?? ''}_${file.path}',
      name: file.name,
      path: file.path,
      url: url,
      sourceId: sourceId,
      title: title,
      artist: artist ?? parsed.$1,
      album: album,
      duration: durationMs != null ? Duration(milliseconds: durationMs) : null,
      trackNumber: trackNumber,
      year: year,
      genre: genre,
      coverData: coverData,
      coverUrl: coverUrl,
      size: file.size,
      folder: folderName,
    );
  }

  final String id;
  final String name;
  final String path;
  final String url;
  final String? sourceId;
  final String? title; // 元数据中的标题
  final String? artist;
  final String? album;
  final Duration? duration;
  final String? coverUrl;
  final int? size;
  final Duration lastPosition;
  final String? folder;
  final int? trackNumber;
  final int? year;
  final String? genre;
  final String? lyrics;
  final List<int>? coverData;

  /// 显示的艺术家名称
  String get displayArtist => artist?.isNotEmpty ?? false ? artist! : appL10n.musicDisplayArtistUnknown;

  /// 显示的专辑名称
  String get displayAlbum => album?.isNotEmpty ?? false ? album! : appL10n.musicDisplayAlbumUnknown;

  /// 显示标题（优先使用元数据标题，否则从文件名解析）
  String get displayTitle {
    if (title != null && title!.isNotEmpty) return title!;
    final parsed = parseFileName(name);
    return parsed.$2;
  }

  /// 文件夹名称
  String get folderName {
    if (folder != null && folder!.isNotEmpty) return folder!;
    final parts = path.split('/');
    if (parts.length >= 2) {
      return parts[parts.length - 2];
    }
    return appL10n.musicFolderNameRoot;
  }

  /// 格式化时长
  String get durationText {
    if (duration == null || duration! <= Duration.zero) return '--:--';
    // 过滤异常值：超过 24 小时的时长视为无效
    if (duration! > const Duration(hours: 24)) return '--:--';
    final minutes = duration!.inMinutes;
    final seconds = duration!.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// 文件大小显示
  String get displaySize {
    final s = size ?? 0;
    if (s < 1024) return '$s B';
    if (s < 1024 * 1024) return '${(s / 1024).toStringAsFixed(1)} KB';
    return '${(s / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// 从文件名解析艺术家和标题
  static (String?, String) parseFileName(String fileName) {
    // 移除扩展名
    final nameWithoutExt = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');

    // 尝试解析 "艺术家 - 歌曲名" 格式
    final patterns = [
      RegExp(r'^(.+?)\s*-\s*(.+)$'), // 艺术家 - 歌曲
      RegExp(r'^(.+?)\s*–\s*(.+)$'), // 艺术家 – 歌曲 (en dash)
      RegExp(r'^(.+?)\s*—\s*(.+)$'), // 艺术家 — 歌曲 (em dash)
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(nameWithoutExt);
      if (match != null) {
        return (match.group(1)?.trim(), match.group(2)?.trim() ?? nameWithoutExt);
      }
    }

    return (null, nameWithoutExt);
  }

  MusicItem copyWith({
    String? id,
    String? name,
    String? path,
    String? url,
    String? sourceId,
    String? title,
    String? artist,
    String? album,
    Duration? duration,
    String? coverUrl,
    int? size,
    Duration? lastPosition,
    String? folder,
    int? trackNumber,
    int? year,
    String? genre,
    String? lyrics,
    List<int>? coverData,
  }) =>
      MusicItem(
        id: id ?? this.id,
        name: name ?? this.name,
        path: path ?? this.path,
        url: url ?? this.url,
        sourceId: sourceId ?? this.sourceId,
        title: title ?? this.title,
        artist: artist ?? this.artist,
        album: album ?? this.album,
        duration: duration ?? this.duration,
        coverUrl: coverUrl ?? this.coverUrl,
        size: size ?? this.size,
        lastPosition: lastPosition ?? this.lastPosition,
        folder: folder ?? this.folder,
        trackNumber: trackNumber ?? this.trackNumber,
        year: year ?? this.year,
        genre: genre ?? this.genre,
        lyrics: lyrics ?? this.lyrics,
        coverData: coverData ?? this.coverData,
      );

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MusicItem && other.id == id;
  }

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes
  int get hashCode => id.hashCode;
}

/// 播放列表
class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    required this.tracks,
    this.coverUrl,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final List<MusicItem> tracks;
  final String? coverUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  int get trackCount => tracks.length;

  Duration get totalDuration => tracks.fold(
        Duration.zero,
        (total, track) => total + (track.duration ?? Duration.zero),
      );

  String get totalDurationText {
    final hours = totalDuration.inHours;
    final minutes = totalDuration.inMinutes % 60;
    if (hours > 0) {
      return appL10n.musicPlaylistDurationHours(hours, minutes);
    }
    return appL10n.musicPlaylistDurationMinutes(minutes);
  }

  Playlist copyWith({
    String? id,
    String? name,
    List<MusicItem>? tracks,
    String? coverUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      tracks: tracks ?? this.tracks,
      coverUrl: coverUrl ?? this.coverUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
}

/// 艺术家
class Artist {
  const Artist({
    required this.name,
    this.tracks = const [],
    this.coverUrl,
  });

  final String name;
  final List<MusicItem> tracks;
  final String? coverUrl;

  int get trackCount => tracks.length;

  Set<String> get albums {
    final albumSet = <String>{};
    for (final track in tracks) {
      if (track.album != null && track.album!.isNotEmpty) {
        albumSet.add(track.album!);
      }
    }
    return albumSet;
  }

  int get albumCount => albums.length;

  /// 获取第一个有封面的歌曲的封面
  String? get displayCover {
    if (coverUrl != null) return coverUrl;
    for (final track in tracks) {
      if (track.coverUrl != null) return track.coverUrl;
    }
    return null;
  }
}

/// 专辑
class Album {
  const Album({
    required this.name,
    this.artist,
    this.tracks = const [],
    this.coverUrl,
    this.year,
  });

  final String name;
  final String? artist;
  final List<MusicItem> tracks;
  final String? coverUrl;
  final int? year;

  int get trackCount => tracks.length;

  Duration get totalDuration => tracks.fold(
        Duration.zero,
        (total, track) => total + (track.duration ?? Duration.zero),
      );

  /// 获取第一个有封面的歌曲的封面
  String? get displayCover {
    if (coverUrl != null) return coverUrl;
    for (final track in tracks) {
      if (track.coverUrl != null) return track.coverUrl;
    }
    return null;
  }
}

/// 文件夹
class MusicFolder {
  const MusicFolder({
    required this.name,
    required this.path,
    this.tracks = const [],
  });

  final String name;
  final String path;
  final List<MusicItem> tracks;

  int get trackCount => tracks.length;
}
