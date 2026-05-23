import 'package:my_nas/media_server_adapters/base/media_server_entities.dart';

/// Jellyfin 认证响应
class JellyfinAuthResult {
  const JellyfinAuthResult({
    required this.userId,
    required this.accessToken,
    required this.serverId,
    this.username,
    this.serverName,
  });

  factory JellyfinAuthResult.fromJson(Map<String, dynamic> json) {
    final user = json['User'] as Map<String, dynamic>?;
    return JellyfinAuthResult(
      userId: user?['Id'] as String? ?? '',
      accessToken: json['AccessToken'] as String? ?? '',
      serverId: user?['ServerId'] as String? ?? json['ServerId'] as String? ?? '',
      username: user?['Name'] as String?,
      serverName: json['ServerName'] as String?,
    );
  }

  final String userId;
  final String accessToken;
  final String serverId;
  final String? username;
  final String? serverName;
}

/// Quick Connect 结果
class QuickConnectResult {
  const QuickConnectResult({
    required this.code,
    required this.secret,
    this.isAuthenticated = false,
    this.dateAdded,
  });

  factory QuickConnectResult.fromJson(Map<String, dynamic> json) => QuickConnectResult(
      code: json['Code'] as String? ?? '',
      secret: json['Secret'] as String? ?? '',
      isAuthenticated: json['Authenticated'] as bool? ?? false,
      dateAdded: json['DateAdded'] != null
          ? DateTime.tryParse(json['DateAdded'] as String)
          : null,
    );

  /// 用户需要输入的验证码（显示给用户）
  final String code;

  /// API 使用的密钥（用于轮询状态）
  final String secret;

  /// 是否已通过认证
  final bool isAuthenticated;

  /// 添加时间
  final DateTime? dateAdded;
}

/// Jellyfin 服务器信息
class JellyfinServerInfo {
  const JellyfinServerInfo({
    required this.serverName,
    required this.serverId,
    required this.version,
    this.operatingSystem,
    this.startupWizardCompleted = true,
  });

  factory JellyfinServerInfo.fromJson(Map<String, dynamic> json) =>
      JellyfinServerInfo(
        serverName: json['ServerName'] as String? ?? 'Jellyfin',
        serverId: json['Id'] as String? ?? '',
        version: json['Version'] as String? ?? '',
        operatingSystem: json['OperatingSystem'] as String?,
        startupWizardCompleted:
            json['StartupWizardCompleted'] as bool? ?? true,
      );

  final String serverName;
  final String serverId;
  final String version;
  final String? operatingSystem;
  final bool startupWizardCompleted;
}

/// Jellyfin 用户信息
class JellyfinUser {
  const JellyfinUser({
    required this.id,
    required this.name,
    this.serverId,
    this.primaryImageTag,
    this.hasPassword = true,
  });

  factory JellyfinUser.fromJson(Map<String, dynamic> json) => JellyfinUser(
        id: json['Id'] as String? ?? '',
        name: json['Name'] as String? ?? '',
        serverId: json['ServerId'] as String?,
        primaryImageTag: json['PrimaryImageTag'] as String?,
        hasPassword: json['HasPassword'] as bool? ?? true,
      );

  final String id;
  final String name;
  final String? serverId;
  final String? primaryImageTag;
  final bool hasPassword;
}

/// Jellyfin 媒体库（虚拟文件夹）
class JellyfinLibrary {
  const JellyfinLibrary({
    required this.id,
    required this.name,
    this.collectionType,
    this.primaryImageItemId,
    this.itemCount,
  });

  factory JellyfinLibrary.fromJson(Map<String, dynamic> json) =>
      JellyfinLibrary(
        id: json['Id'] as String? ?? '',
        name: json['Name'] as String? ?? '',
        collectionType: json['CollectionType'] as String?,
        primaryImageItemId: json['PrimaryImageItemId'] as String?,
        itemCount: json['ChildCount'] as int?,
      );

  final String id;
  final String name;
  final String? collectionType;
  final String? primaryImageItemId;
  final int? itemCount;

  MediaLibrary toMediaLibrary() => MediaLibrary(
        id: id,
        name: name,
        type: MediaLibraryType.fromJellyfinType(collectionType),
        itemCount: itemCount,
        primaryImageId: primaryImageItemId,
      );
}

/// Jellyfin 媒体项目
class JellyfinItem {
  const JellyfinItem({
    required this.id,
    required this.name,
    this.type,
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
    this.imageTags,
    this.backdropImageTags,
    this.userData,
    this.mediaStreams,
    this.providerIds,
    this.mediaSources,
  });

  factory JellyfinItem.fromJson(Map<String, dynamic> json) {
    // 解析流信息
    List<MediaStream>? mediaStreams;
    if (json['MediaStreams'] != null) {
      mediaStreams = (json['MediaStreams'] as List)
          .map((e) => _parseMediaStream(e as Map<String, dynamic>))
          .toList();
    }

    // 解析用户数据
    MediaUserData? userData;
    if (json['UserData'] != null) {
      userData = _parseUserData(json['UserData'] as Map<String, dynamic>);
    }

    // 解析 Provider IDs
    Map<String, String>? providerIds;
    if (json['ProviderIds'] != null) {
      providerIds = (json['ProviderIds'] as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, v.toString()));
    }

    return JellyfinItem(
      id: json['Id'] as String? ?? '',
      name: json['Name'] as String? ?? '',
      type: json['Type'] as String?,
      sortName: json['SortName'] as String?,
      parentId: json['ParentId'] as String?,
      seriesId: json['SeriesId'] as String?,
      seriesName: json['SeriesName'] as String?,
      seasonId: json['SeasonId'] as String?,
      seasonName: json['SeasonName'] as String?,
      indexNumber: json['IndexNumber'] as int?,
      parentIndexNumber: json['ParentIndexNumber'] as int?,
      overview: json['Overview'] as String?,
      communityRating: (json['CommunityRating'] as num?)?.toDouble(),
      officialRating: json['OfficialRating'] as String?,
      productionYear: json['ProductionYear'] as int?,
      premiereDate: json['PremiereDate'] != null
          ? DateTime.tryParse(json['PremiereDate'] as String)
          : null,
      runTimeTicks: json['RunTimeTicks'] as int?,
      genres: (json['Genres'] as List?)?.cast<String>(),
      primaryImageAspectRatio:
          (json['PrimaryImageAspectRatio'] as num?)?.toDouble(),
      imageTags: (json['ImageTags'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, v.toString())),
      backdropImageTags: (json['BackdropImageTags'] as List?)?.cast<String>(),
      userData: userData,
      mediaStreams: mediaStreams,
      providerIds: providerIds,
      mediaSources: json['MediaSources'] as List?,
    );
  }

  final String id;
  final String name;
  final String? type;
  final String? sortName;
  final String? parentId;

  // 剧集相关
  final String? seriesId;
  final String? seriesName;
  final String? seasonId;
  final String? seasonName;
  final int? indexNumber;
  final int? parentIndexNumber;

  // 元数据
  final String? overview;
  final double? communityRating;
  final String? officialRating;
  final int? productionYear;
  final DateTime? premiereDate;
  final int? runTimeTicks;
  final List<String>? genres;
  final double? primaryImageAspectRatio;

  // 图片
  final Map<String, String>? imageTags;
  final List<String>? backdropImageTags;

  // 用户数据和流信息
  final MediaUserData? userData;
  final List<MediaStream>? mediaStreams;
  final Map<String, String>? providerIds;
  final List<dynamic>? mediaSources;

  MediaItem toMediaItem() => MediaItem(
        id: id,
        name: name,
        type: MediaItemType.fromJellyfinType(type),
        sortName: sortName,
        parentId: parentId,
        seriesId: seriesId,
        seriesName: seriesName,
        seasonId: seasonId,
        seasonName: seasonName,
        indexNumber: indexNumber,
        parentIndexNumber: parentIndexNumber,
        overview: overview,
        communityRating: communityRating,
        officialRating: officialRating,
        productionYear: productionYear,
        premiereDate: premiereDate,
        runTimeTicks: runTimeTicks,
        genres: genres,
        primaryImageAspectRatio: primaryImageAspectRatio,
        userData: userData,
        mediaStreams: mediaStreams,
        providerIds: providerIds,
      );

  /// 是否有主图
  bool get hasPrimaryImage => imageTags?.containsKey('Primary') ?? false;

  /// 是否有背景图
  bool get hasBackdrop =>
      backdropImageTags != null && backdropImageTags!.isNotEmpty;
}

/// Jellyfin 项目列表响应
class JellyfinItemsResult {
  const JellyfinItemsResult({
    required this.items,
    required this.totalRecordCount,
    this.startIndex = 0,
  });

  factory JellyfinItemsResult.fromJson(Map<String, dynamic> json) {
    final items = (json['Items'] as List? ?? [])
        .map((e) => JellyfinItem.fromJson(e as Map<String, dynamic>))
        .toList();
    return JellyfinItemsResult(
      items: items,
      totalRecordCount: json['TotalRecordCount'] as int? ?? items.length,
      startIndex: json['StartIndex'] as int? ?? 0,
    );
  }

  final List<JellyfinItem> items;
  final int totalRecordCount;
  final int startIndex;

  MediaItemsResult toMediaItemsResult() => MediaItemsResult(
        items: items.map((e) => e.toMediaItem()).toList(),
        totalRecordCount: totalRecordCount,
        startIndex: startIndex,
      );
}

/// Jellyfin 播放信息
class JellyfinPlaybackInfo {
  const JellyfinPlaybackInfo({
    required this.mediaSources,
    this.playSessionId,
  });

  factory JellyfinPlaybackInfo.fromJson(Map<String, dynamic> json) {
    final sources = (json['MediaSources'] as List? ?? [])
        .map((e) => JellyfinMediaSource.fromJson(e as Map<String, dynamic>))
        .toList();
    return JellyfinPlaybackInfo(
      mediaSources: sources,
      playSessionId: json['PlaySessionId'] as String?,
    );
  }

  final List<JellyfinMediaSource> mediaSources;
  final String? playSessionId;
}

/// Jellyfin 媒体源
class JellyfinMediaSource {
  const JellyfinMediaSource({
    required this.id,
    this.name,
    this.path,
    this.container,
    this.size,
    this.bitrate,
    this.supportsDirectPlay = true,
    this.supportsDirectStream = true,
    this.supportsTranscoding = true,
    this.directStreamUrl,
    this.transcodingUrl,
    this.transcodingContainer,
  });

  factory JellyfinMediaSource.fromJson(Map<String, dynamic> json) =>
      JellyfinMediaSource(
        id: json['Id'] as String? ?? '',
        name: json['Name'] as String?,
        path: json['Path'] as String?,
        container: json['Container'] as String?,
        size: json['Size'] as int?,
        bitrate: json['Bitrate'] as int?,
        supportsDirectPlay: json['SupportsDirectPlay'] as bool? ?? true,
        supportsDirectStream: json['SupportsDirectStream'] as bool? ?? true,
        supportsTranscoding: json['SupportsTranscoding'] as bool? ?? true,
        directStreamUrl: json['DirectStreamUrl'] as String?,
        transcodingUrl: json['TranscodingUrl'] as String?,
        transcodingContainer: json['TranscodingContainer'] as String?,
      );

  final String id;
  final String? name;
  final String? path;
  final String? container;
  final int? size;
  final int? bitrate;
  final bool supportsDirectPlay;
  final bool supportsDirectStream;
  final bool supportsTranscoding;
  final String? directStreamUrl;
  final String? transcodingUrl;
  final String? transcodingContainer;
}

// === Helper functions ===

MediaStream _parseMediaStream(Map<String, dynamic> json) => MediaStream(
      type: MediaStreamType.fromString(json['Type'] as String?),
      index: json['Index'] as int? ?? 0,
      codec: json['Codec'] as String?,
      language: json['Language'] as String?,
      title: json['Title'] as String?,
      isDefault: json['IsDefault'] as bool? ?? false,
      isForced: json['IsForced'] as bool? ?? false,
      isExternal: json['IsExternal'] as bool? ?? false,
      width: json['Width'] as int?,
      height: json['Height'] as int?,
      bitRate: json['BitRate'] as int?,
      aspectRatio: json['AspectRatio'] as String?,
      channels: json['Channels'] as int?,
      sampleRate: json['SampleRate'] as int?,
    );

MediaUserData _parseUserData(Map<String, dynamic> json) => MediaUserData(
      playbackPositionTicks: json['PlaybackPositionTicks'] as int?,
      playCount: json['PlayCount'] as int?,
      isFavorite: json['IsFavorite'] as bool? ?? false,
      played: json['Played'] as bool? ?? false,
      lastPlayedDate: json['LastPlayedDate'] != null
          ? DateTime.tryParse(json['LastPlayedDate'] as String)
          : null,
    );
