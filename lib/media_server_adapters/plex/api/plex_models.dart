/// Plex 服务器信息
class PlexServerInfo {
  const PlexServerInfo({
    required this.name,
    required this.machineIdentifier,
    this.version,
    this.platform,
    this.platformVersion,
  });

  factory PlexServerInfo.fromJson(Map<String, dynamic> json) {
    final mediaContainer = json['MediaContainer'] as Map<String, dynamic>? ?? json;
    return PlexServerInfo(
      name: mediaContainer['friendlyName'] as String? ?? 'Plex',
      machineIdentifier: mediaContainer['machineIdentifier'] as String? ?? '',
      version: mediaContainer['version'] as String?,
      platform: mediaContainer['platform'] as String?,
      platformVersion: mediaContainer['platformVersion'] as String?,
    );
  }

  final String name;
  final String machineIdentifier;
  final String? version;
  final String? platform;
  final String? platformVersion;
}

/// Plex 媒体库
class PlexLibrary {
  const PlexLibrary({
    required this.key,
    required this.title,
    required this.type,
    this.agent,
    this.scanner,
    this.uuid,
  });

  factory PlexLibrary.fromJson(Map<String, dynamic> json) => PlexLibrary(
      key: json['key'] as String? ?? '',
      title: json['title'] as String? ?? '',
      type: json['type'] as String? ?? '',
      agent: json['agent'] as String?,
      scanner: json['scanner'] as String?,
      uuid: json['uuid'] as String?,
    );

  final String key;
  final String title;
  final String type; // movie, show, artist, photo
  final String? agent;
  final String? scanner;
  final String? uuid;

  /// 是否是视频库
  bool get isVideo => type == 'movie' || type == 'show';
}

/// Plex 媒体项目
class PlexMediaItem {
  const PlexMediaItem({
    required this.ratingKey,
    required this.title,
    required this.type,
    this.parentRatingKey,
    this.grandparentRatingKey,
    this.parentTitle,
    this.grandparentTitle,
    this.index,
    this.parentIndex,
    this.summary,
    this.year,
    this.rating,
    this.audienceRating,
    this.duration,
    this.thumb,
    this.art,
    this.originallyAvailableAt,
    this.viewCount,
    this.viewOffset,
    this.lastViewedAt,
    this.genres,
    this.directors,
    this.actors,
    this.media,
    this.guids,
  });

  factory PlexMediaItem.fromJson(Map<String, dynamic> json) {
    // 解析 Genre
    List<String>? genres;
    final genreList = json['Genre'] as List?;
    if (genreList != null) {
      genres = genreList
          .map((g) => (g as Map<String, dynamic>)['tag'] as String?)
          .whereType<String>()
          .toList();
    }

    // 解析 Director
    List<String>? directors;
    final directorList = json['Director'] as List?;
    if (directorList != null) {
      directors = directorList
          .map((d) => (d as Map<String, dynamic>)['tag'] as String?)
          .whereType<String>()
          .toList();
    }

    // 解析 Role (actors)
    List<String>? actors;
    final roleList = json['Role'] as List?;
    if (roleList != null) {
      actors = roleList
          .map((r) => (r as Map<String, dynamic>)['tag'] as String?)
          .whereType<String>()
          .toList();
    }

    // 解析 Media
    List<PlexMedia>? media;
    final mediaList = json['Media'] as List?;
    if (mediaList != null) {
      media = mediaList
          .map((m) => PlexMedia.fromJson(m as Map<String, dynamic>))
          .toList();
    }

    // 解析 Guid
    List<PlexGuid>? guids;
    final guidList = json['Guid'] as List?;
    if (guidList != null) {
      guids = guidList
          .map((g) => PlexGuid.fromJson(g as Map<String, dynamic>))
          .toList();
    }

    return PlexMediaItem(
      ratingKey: json['ratingKey'] as String? ?? '',
      title: json['title'] as String? ?? '',
      type: json['type'] as String? ?? '',
      parentRatingKey: json['parentRatingKey'] as String?,
      grandparentRatingKey: json['grandparentRatingKey'] as String?,
      parentTitle: json['parentTitle'] as String?,
      grandparentTitle: json['grandparentTitle'] as String?,
      index: json['index'] as int?,
      parentIndex: json['parentIndex'] as int?,
      summary: json['summary'] as String?,
      year: json['year'] as int?,
      rating: (json['rating'] as num?)?.toDouble(),
      audienceRating: (json['audienceRating'] as num?)?.toDouble(),
      duration: json['duration'] as int?,
      thumb: json['thumb'] as String?,
      art: json['art'] as String?,
      originallyAvailableAt: json['originallyAvailableAt'] as String?,
      viewCount: json['viewCount'] as int?,
      viewOffset: json['viewOffset'] as int?,
      lastViewedAt: json['lastViewedAt'] as int?,
      genres: genres,
      directors: directors,
      actors: actors,
      media: media,
      guids: guids,
    );
  }

  final String ratingKey; // 唯一标识
  final String title;
  final String type; // movie, show, season, episode, artist, album, track
  final String? parentRatingKey;
  final String? grandparentRatingKey;
  final String? parentTitle; // 季名 (for episode)
  final String? grandparentTitle; // 剧名 (for episode)
  final int? index; // 集号
  final int? parentIndex; // 季号
  final String? summary;
  final int? year;
  final double? rating;
  final double? audienceRating;
  final int? duration; // 毫秒
  final String? thumb;
  final String? art;
  final String? originallyAvailableAt;
  final int? viewCount;
  final int? viewOffset; // 播放位置（毫秒）
  final int? lastViewedAt;
  final List<String>? genres;
  final List<String>? directors;
  final List<String>? actors;
  final List<PlexMedia>? media;
  final List<PlexGuid>? guids;

  /// 是否已观看
  bool get isWatched => viewCount != null && viewCount! > 0;

  /// 是否可播放
  bool get isPlayable =>
      type == 'movie' || type == 'episode' || type == 'track';

  /// 获取 TMDB ID
  String? get tmdbId {
    if (guids == null) return null;
    for (final guid in guids!) {
      if (guid.id.startsWith('tmdb://')) {
        return guid.id.substring(7);
      }
    }
    return null;
  }

  /// 获取 IMDB ID
  String? get imdbId {
    if (guids == null) return null;
    for (final guid in guids!) {
      if (guid.id.startsWith('imdb://')) {
        return guid.id.substring(7);
      }
    }
    return null;
  }

  /// 获取 TVDB ID
  String? get tvdbId {
    if (guids == null) return null;
    for (final guid in guids!) {
      if (guid.id.startsWith('tvdb://')) {
        return guid.id.substring(7);
      }
    }
    return null;
  }
}

/// Plex 媒体信息
class PlexMedia {
  const PlexMedia({
    required this.id,
    this.duration,
    this.bitrate,
    this.width,
    this.height,
    this.aspectRatio,
    this.audioChannels,
    this.audioCodec,
    this.videoCodec,
    this.videoResolution,
    this.container,
    this.videoFrameRate,
    this.parts,
  });

  factory PlexMedia.fromJson(Map<String, dynamic> json) {
    List<PlexPart>? parts;
    final partList = json['Part'] as List?;
    if (partList != null) {
      parts = partList
          .map((p) => PlexPart.fromJson(p as Map<String, dynamic>))
          .toList();
    }

    return PlexMedia(
      id: json['id'] as int? ?? 0,
      duration: json['duration'] as int?,
      bitrate: json['bitrate'] as int?,
      width: json['width'] as int?,
      height: json['height'] as int?,
      aspectRatio: (json['aspectRatio'] as num?)?.toDouble(),
      audioChannels: json['audioChannels'] as int?,
      audioCodec: json['audioCodec'] as String?,
      videoCodec: json['videoCodec'] as String?,
      videoResolution: json['videoResolution'] as String?,
      container: json['container'] as String?,
      videoFrameRate: json['videoFrameRate'] as String?,
      parts: parts,
    );
  }

  final int id;
  final int? duration;
  final int? bitrate;
  final int? width;
  final int? height;
  final double? aspectRatio;
  final int? audioChannels;
  final String? audioCodec;
  final String? videoCodec;
  final String? videoResolution;
  final String? container;
  final String? videoFrameRate;
  final List<PlexPart>? parts;
}

/// Plex 媒体部分
class PlexPart {
  const PlexPart({
    required this.id,
    this.key,
    this.duration,
    this.file,
    this.size,
    this.container,
    this.streams,
  });

  factory PlexPart.fromJson(Map<String, dynamic> json) {
    List<PlexStream>? streams;
    final streamList = json['Stream'] as List?;
    if (streamList != null) {
      streams = streamList
          .map((s) => PlexStream.fromJson(s as Map<String, dynamic>))
          .toList();
    }

    return PlexPart(
      id: json['id'] as int? ?? 0,
      key: json['key'] as String?,
      duration: json['duration'] as int?,
      file: json['file'] as String?,
      size: json['size'] as int?,
      container: json['container'] as String?,
      streams: streams,
    );
  }

  final int id;
  final String? key;
  final int? duration;
  final String? file;
  final int? size;
  final String? container;
  final List<PlexStream>? streams;
}

/// Plex 流信息
class PlexStream {
  const PlexStream({
    required this.id,
    required this.streamType,
    this.index,
    this.codec,
    this.language,
    this.languageCode,
    this.title,
    this.selected = false,
    this.isDefault = false,
    this.forced = false,
    // 视频
    this.width,
    this.height,
    this.bitrate,
    this.frameRate,
    // 音频
    this.channels,
    this.samplingRate,
  });

  factory PlexStream.fromJson(Map<String, dynamic> json) => PlexStream(
      id: json['id'] as int? ?? 0,
      streamType: json['streamType'] as int? ?? 0, // 1=video, 2=audio, 3=subtitle
      index: json['index'] as int?,
      codec: json['codec'] as String?,
      language: json['language'] as String?,
      languageCode: json['languageCode'] as String?,
      title: json['title'] as String?,
      selected: json['selected'] as bool? ?? false,
      isDefault: json['default'] as bool? ?? false,
      forced: json['forced'] as bool? ?? false,
      width: json['width'] as int?,
      height: json['height'] as int?,
      bitrate: json['bitrate'] as int?,
      frameRate: json['frameRate'] as String?,
      channels: json['channels'] as int?,
      samplingRate: json['samplingRate'] as int?,
    );

  final int id;
  final int streamType; // 1=video, 2=audio, 3=subtitle
  final int? index;
  final String? codec;
  final String? language;
  final String? languageCode;
  final String? title;
  final bool selected;
  final bool isDefault;
  final bool forced;
  // 视频属性
  final int? width;
  final int? height;
  final int? bitrate;
  final String? frameRate;
  // 音频属性
  final int? channels;
  final int? samplingRate;

  bool get isVideo => streamType == 1;
  bool get isAudio => streamType == 2;
  bool get isSubtitle => streamType == 3;
}

/// Plex GUID（外部 ID）
class PlexGuid {
  const PlexGuid({required this.id});

  factory PlexGuid.fromJson(Map<String, dynamic> json) => PlexGuid(id: json['id'] as String? ?? '');

  final String id; // 格式: provider://id, 如 tmdb://12345
}

/// Plex 项目列表结果
class PlexItemsResult {
  const PlexItemsResult({
    required this.items,
    this.totalSize,
    this.size,
    this.offset,
  });

  factory PlexItemsResult.fromJson(Map<String, dynamic> json) {
    final mediaContainer = json['MediaContainer'] as Map<String, dynamic>? ?? json;
    final metadata = mediaContainer['Metadata'] as List? ?? [];

    return PlexItemsResult(
      items: metadata
          .map((e) => PlexMediaItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      totalSize: mediaContainer['totalSize'] as int?,
      size: mediaContainer['size'] as int?,
      offset: mediaContainer['offset'] as int?,
    );
  }

  final List<PlexMediaItem> items;
  final int? totalSize;
  final int? size;
  final int? offset;

  bool get hasMore =>
      totalSize != null && offset != null && size != null &&
      (offset! + size!) < totalSize!;
}

/// Plex PIN 认证信息
class PlexPinInfo {
  const PlexPinInfo({
    required this.id,
    required this.code,
    this.authToken,
    this.expiresAt,
    this.trusted,
    this.clientIdentifier,
  });

  factory PlexPinInfo.fromJson(Map<String, dynamic> json) => PlexPinInfo(
      id: json['id'] as int? ?? 0,
      code: json['code'] as String? ?? '',
      authToken: json['authToken'] as String?,
      expiresAt: json['expiresAt'] != null
          ? DateTime.tryParse(json['expiresAt'] as String)
          : null,
      trusted: json['trusted'] as bool? ?? false,
      clientIdentifier: json['clientIdentifier'] as String?,
    );

  final int id;
  final String code;
  final String? authToken;
  final DateTime? expiresAt;
  final bool? trusted;
  final String? clientIdentifier;

  /// PIN 是否已过期
  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);

  /// 是否已授权
  bool get isAuthorized => authToken != null && authToken!.isNotEmpty;

  /// 获取授权 URL
  String getAuthUrl({
    required String clientId,
    String? clientName,
  }) {
    final params = <String, String>{
      'clientID': clientId,
      'code': code,
      'context[device][product]': clientName ?? 'MyNas',
    };
    final query = params.entries
        .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
    return 'https://app.plex.tv/auth#?$query';
  }
}

/// Plex 用户信息
class PlexUser {
  const PlexUser({
    required this.id,
    required this.uuid,
    this.username,
    this.email,
    this.thumb,
    this.authToken,
    this.subscription,
  });

  factory PlexUser.fromJson(Map<String, dynamic> json) => PlexUser(
      id: json['id'] as int? ?? 0,
      uuid: json['uuid'] as String? ?? '',
      username: json['username'] as String?,
      email: json['email'] as String?,
      thumb: json['thumb'] as String?,
      authToken: json['authToken'] as String?,
      subscription: json['subscription'] != null
          ? PlexSubscription.fromJson(json['subscription'] as Map<String, dynamic>)
          : null,
    );

  final int id;
  final String uuid;
  final String? username;
  final String? email;
  final String? thumb;
  final String? authToken;
  final PlexSubscription? subscription;
}

/// Plex 订阅信息
class PlexSubscription {
  const PlexSubscription({
    this.active,
    this.status,
    this.plan,
    this.features,
  });

  factory PlexSubscription.fromJson(Map<String, dynamic> json) => PlexSubscription(
      active: json['active'] as bool? ?? false,
      status: json['status'] as String?,
      plan: json['plan'] as String?,
      features: (json['features'] as List?)?.cast<String>(),
    );

  final bool? active;
  final String? status;
  final String? plan;
  final List<String>? features;
}

/// Plex 服务器资源（从 plex.tv 获取）
class PlexServerResource {
  const PlexServerResource({
    required this.name,
    required this.clientIdentifier,
    this.accessToken,
    this.owned,
    this.connections,
  });

  factory PlexServerResource.fromJson(Map<String, dynamic> json) {
    List<PlexConnection>? connections;
    final connList = json['connections'] as List?;
    if (connList != null) {
      connections = connList
          .map((c) => PlexConnection.fromJson(c as Map<String, dynamic>))
          .toList();
    }

    return PlexServerResource(
      name: json['name'] as String? ?? '',
      clientIdentifier: json['clientIdentifier'] as String? ?? '',
      accessToken: json['accessToken'] as String?,
      owned: json['owned'] as bool? ?? false,
      connections: connections,
    );
  }

  final String name;
  final String clientIdentifier;
  final String? accessToken;
  final bool? owned;
  final List<PlexConnection>? connections;

  /// 获取最佳连接 URL（优先本地）
  String? get bestConnectionUrl {
    if (connections == null || connections!.isEmpty) return null;

    // 优先选择本地连接
    final local = connections!.where((c) => c.local ?? false).firstOrNull;
    if (local != null) return local.uri;

    // 其次选择 relay 连接
    final relay = connections!.where((c) => c.relay ?? false).firstOrNull;
    if (relay != null) return relay.uri;

    // 最后返回第一个
    return connections!.first.uri;
  }
}

/// Plex 连接信息
class PlexConnection {
  const PlexConnection({
    this.protocol,
    this.address,
    this.port,
    this.uri,
    this.local,
    this.relay,
  });

  factory PlexConnection.fromJson(Map<String, dynamic> json) => PlexConnection(
      protocol: json['protocol'] as String?,
      address: json['address'] as String?,
      port: json['port'] as int?,
      uri: json['uri'] as String?,
      local: json['local'] as bool? ?? false,
      relay: json['relay'] as bool? ?? false,
    );

  final String? protocol;
  final String? address;
  final int? port;
  final String? uri;
  final bool? local;
  final bool? relay;
}
