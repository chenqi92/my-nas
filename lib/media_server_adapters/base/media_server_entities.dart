/// 媒体服务器通用实体定义
///
/// 定义媒体库、媒体项目等通用数据模型，供各媒体服务器适配器使用
library;

import 'package:my_nas/core/i18n/app_l10n.dart';

/// 媒体库信息
class MediaLibrary {
  const MediaLibrary({
    required this.id,
    required this.name,
    required this.type,
    this.itemCount,
    this.primaryImageId,
  });

  final String id;
  final String name;
  final MediaLibraryType type;
  final int? itemCount;
  final String? primaryImageId;
}

/// 媒体库类型
enum MediaLibraryType {
  movies,
  tvShows,
  music,
  photos,
  musicVideos,
  homeVideos,
  books,
  mixed,
  unknown;

  static MediaLibraryType fromJellyfinType(String? type) => switch (type) {
        'movies' => MediaLibraryType.movies,
        'tvshows' => MediaLibraryType.tvShows,
        'music' => MediaLibraryType.music,
        'photos' => MediaLibraryType.photos,
        'musicvideos' => MediaLibraryType.musicVideos,
        'homevideos' => MediaLibraryType.homeVideos,
        'books' => MediaLibraryType.books,
        'mixed' => MediaLibraryType.mixed,
        _ => MediaLibraryType.unknown,
      };
}

/// 媒体项目类型
enum MediaItemType {
  movie,
  series,
  season,
  episode,
  musicAlbum,
  audio,
  photo,
  folder,
  person,
  unknown;

  static MediaItemType fromJellyfinType(String? type) => switch (type) {
        'Movie' => MediaItemType.movie,
        'Series' => MediaItemType.series,
        'Season' => MediaItemType.season,
        'Episode' => MediaItemType.episode,
        'MusicAlbum' => MediaItemType.musicAlbum,
        'Audio' => MediaItemType.audio,
        'Photo' => MediaItemType.photo,
        'Folder' || 'CollectionFolder' => MediaItemType.folder,
        'Person' => MediaItemType.person,
        _ => MediaItemType.unknown,
      };

  bool get isPlayable => this == movie || this == episode || this == audio;

  bool get isContainer =>
      this == series || this == season || this == folder || this == musicAlbum;
}

/// 媒体项目基础信息
class MediaItem {
  const MediaItem({
    required this.id,
    required this.name,
    required this.type,
    this.sortName,
    this.parentId,
    this.seriesId,
    this.seriesName,
    this.seasonId,
    this.seasonName,
    this.indexNumber,
    this.parentIndexNumber,
    this.overview,
    this.communityRating,
    this.officialRating,
    this.productionYear,
    this.premiereDate,
    this.runTimeTicks,
    this.genres,
    this.primaryImageAspectRatio,
    this.userData,
    this.mediaStreams,
    this.providerIds,
  });

  final String id;
  final String name;
  final MediaItemType type;
  final String? sortName;
  final String? parentId;

  // 剧集相关
  final String? seriesId;
  final String? seriesName;
  final String? seasonId;
  final String? seasonName;
  final int? indexNumber; // 集数或季数
  final int? parentIndexNumber; // 季数（用于集）

  // 元数据
  final String? overview;
  final double? communityRating;
  final String? officialRating;
  final int? productionYear;
  final DateTime? premiereDate;
  final int? runTimeTicks;
  final List<String>? genres;
  final double? primaryImageAspectRatio;

  // 用户数据和流信息
  final MediaUserData? userData;
  final List<MediaStream>? mediaStreams;
  final Map<String, String>? providerIds;

  /// 获取格式化的运行时长
  String? get formattedRuntime {
    if (runTimeTicks == null) return null;
    final minutes = runTimeTicks! ~/ (10000000 * 60);
    if (minutes < 60) return appL10n.videoEpisodeCardRuntimeMinutes(minutes);
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    return remainingMinutes > 0
        ? appL10n.videoEpisodeCardRuntimeHoursMinutes(hours, remainingMinutes)
        : appL10n.videoEpisodeCardRuntimeHours(hours);
  }

  /// 获取显示名称（剧集包含集数信息）
  String get displayName {
    if (type == MediaItemType.episode) {
      final season = parentIndexNumber ?? 0;
      final episode = indexNumber ?? 0;
      return 'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')} $name';
    }
    return name;
  }

  /// 获取 TMDB ID
  String? get tmdbId => providerIds?['Tmdb'];

  /// 获取 IMDB ID
  String? get imdbId => providerIds?['Imdb'];

  /// 获取 TVDB ID
  String? get tvdbId => providerIds?['Tvdb'];
}

/// 媒体项目列表结果
class MediaItemsResult {
  const MediaItemsResult({
    required this.items,
    required this.totalRecordCount,
    this.startIndex = 0,
  });

  final List<MediaItem> items;
  final int totalRecordCount;
  final int startIndex;

  bool get hasMore => startIndex + items.length < totalRecordCount;
}

/// 用户数据（观看状态、播放进度等）
class MediaUserData {
  const MediaUserData({
    this.playbackPositionTicks,
    this.playCount,
    this.isFavorite = false,
    this.played = false,
    this.lastPlayedDate,
  });

  final int? playbackPositionTicks;
  final int? playCount;
  final bool isFavorite;
  final bool played;
  final DateTime? lastPlayedDate;

  /// 获取播放进度百分比
  double? getProgressPercent(int? totalTicks) {
    if (playbackPositionTicks == null || totalTicks == null || totalTicks == 0) {
      return null;
    }
    return playbackPositionTicks! / totalTicks;
  }

  /// 获取格式化的播放位置
  String? get formattedPosition {
    if (playbackPositionTicks == null) return null;
    final seconds = playbackPositionTicks! ~/ 10000000;
    final minutes = seconds ~/ 60;
    final hours = minutes ~/ 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}

/// 媒体流信息（视频/音频/字幕轨道）
class MediaStream {
  const MediaStream({
    required this.type,
    required this.index,
    this.codec,
    this.language,
    this.title,
    this.isDefault = false,
    this.isForced = false,
    this.isExternal = false,
    // 视频属性
    this.width,
    this.height,
    this.bitRate,
    this.aspectRatio,
    // 音频属性
    this.channels,
    this.sampleRate,
  });

  final MediaStreamType type;
  final int index;
  final String? codec;
  final String? language;
  final String? title;
  final bool isDefault;
  final bool isForced;
  final bool isExternal;

  // 视频属性
  final int? width;
  final int? height;
  final int? bitRate;
  final String? aspectRatio;

  // 音频属性
  final int? channels;
  final int? sampleRate;

  /// 获取显示名称
  String get displayName {
    final parts = <String>[];
    if (language != null) parts.add(language!);
    if (codec != null) parts.add(codec!);
    if (title != null) parts.add(title!);
    if (type == MediaStreamType.video && width != null && height != null) {
      parts.add('${width}x$height');
    }
    if (type == MediaStreamType.audio && channels != null) {
      parts.add('${channels}ch');
    }
    return parts.isEmpty ? appL10n.infuseTrackName(index.toString()) : parts.join(' - ');
  }
}

/// 媒体流类型
enum MediaStreamType {
  video,
  audio,
  subtitle,
  embeddedImage,
  unknown;

  static MediaStreamType fromString(String? type) => switch (type) {
        'Video' => MediaStreamType.video,
        'Audio' => MediaStreamType.audio,
        'Subtitle' => MediaStreamType.subtitle,
        'EmbeddedImage' => MediaStreamType.embeddedImage,
        _ => MediaStreamType.unknown,
      };
}

/// 媒体图片类型
enum MediaImageType {
  primary,
  backdrop,
  banner,
  thumb,
  logo,
  art,
  disc,
  screenshot,
  chapter;

  String toJellyfinType() => switch (this) {
        primary => 'Primary',
        backdrop => 'Backdrop',
        banner => 'Banner',
        thumb => 'Thumb',
        logo => 'Logo',
        art => 'Art',
        disc => 'Disc',
        screenshot => 'Screenshot',
        chapter => 'Chapter',
      };
}

/// 媒体流信息（用于播放）
class MediaStreamInfo {
  const MediaStreamInfo({
    required this.url,
    required this.playMethod,
    this.container,
    this.videoCodec,
    this.audioCodec,
    this.transcodingUrl,
    this.transcodingContainer,
  });

  final String url;
  final MediaPlayMethod playMethod;
  final String? container;
  final String? videoCodec;
  final String? audioCodec;

  // 转码信息
  final String? transcodingUrl;
  final String? transcodingContainer;

  bool get isTranscoding => playMethod == MediaPlayMethod.transcode;
}

/// 播放方式
enum MediaPlayMethod {
  directPlay, // 直接播放原始文件
  directStream, // 直接流（不转码，但可能重封装）
  transcode; // 转码播放
}

/// 播放报告
class PlaybackReport {
  const PlaybackReport({
    required this.itemId,
    required this.reportType,
    this.positionTicks,
    this.playSessionId,
    this.isPaused = false,
    this.isMuted = false,
    this.volumeLevel,
    this.audioStreamIndex,
    this.subtitleStreamIndex,
  });

  final String itemId;
  final PlaybackReportType reportType;
  final int? positionTicks;
  final String? playSessionId;
  final bool isPaused;
  final bool isMuted;
  final int? volumeLevel;
  final int? audioStreamIndex;
  final int? subtitleStreamIndex;
}

/// 播放报告类型
enum PlaybackReportType {
  start,
  progress,
  stop,
}
