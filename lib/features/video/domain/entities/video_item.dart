import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

/// 视频项目
class VideoItem {
  const VideoItem({
    required this.name,
    required this.path,
    this.url = '',
    this.sourceId,
    this.size = 0,
    this.duration,
    this.thumbnailUrl,
    this.lastPosition,
    this.subtitles = const [],
    this.serverItemId,
    this.serverType,
  });

  factory VideoItem.fromFileItem(FileItem file, String url, {String? sourceId}) => VideoItem(
        name: file.name,
        path: file.path,
        url: url,
        sourceId: sourceId,
        size: file.size,
        thumbnailUrl: file.thumbnailUrl,
      );

  final String name;
  final String path;
  final String url;
  final String? sourceId;
  final int size;
  final Duration? duration;
  final String? thumbnailUrl;
  final Duration? lastPosition;
  final List<VideoSubtitle> subtitles;

  /// 媒体服务器中的项目 ID（Jellyfin/Emby/Plex）
  final String? serverItemId;

  /// 媒体服务器类型（jellyfin, emby, plex）
  final String? serverType;

  /// 是否来自媒体服务器
  bool get isFromMediaServer => serverItemId != null && serverType != null;

  /// 检查是否需要代理（SMB / WebDAV 等不支持直接 URL 访问的协议）
  bool get needsProxy =>
      url.startsWith('smb://') || url.startsWith('webdav://');
  
  /// 检查是否需要解析 URL（URL 为空时需要）
  bool get needsUrlResolution => url.isEmpty;

  VideoItem copyWith({
    String? name,
    String? path,
    String? url,
    String? sourceId,
    int? size,
    Duration? duration,
    String? thumbnailUrl,
    Duration? lastPosition,
    List<VideoSubtitle>? subtitles,
    String? serverItemId,
    String? serverType,
  }) =>
      VideoItem(
        name: name ?? this.name,
        path: path ?? this.path,
        url: url ?? this.url,
        sourceId: sourceId ?? this.sourceId,
        size: size ?? this.size,
        duration: duration ?? this.duration,
        thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
        lastPosition: lastPosition ?? this.lastPosition,
        subtitles: subtitles ?? this.subtitles,
        serverItemId: serverItemId ?? this.serverItemId,
        serverType: serverType ?? this.serverType,
      );
}

/// 字幕轨道
class VideoSubtitle {
  const VideoSubtitle({
    required this.id,
    required this.title,
    required this.url,
    this.language,
    this.isExternal = true,
  });

  final String id;
  final String title;
  final String url;
  final String? language;
  final bool isExternal;
}

/// 音频轨道
class VideoAudioTrack {
  const VideoAudioTrack({
    required this.id,
    required this.title,
    this.language,
  });

  final String id;
  final String title;
  final String? language;
}
