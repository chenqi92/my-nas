import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/utils/hive_utils.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/media_server_adapters/base/media_server_adapter.dart';
import 'package:my_nas/media_server_adapters/base/media_server_entities.dart';
import 'package:my_nas/media_server_adapters/plex/api/plex_api.dart';
import 'package:my_nas/media_server_adapters/plex/api/plex_models.dart';
import 'package:my_nas/media_server_adapters/plex/plex_virtual_fs.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/service_adapters/base/service_adapter.dart';
import 'package:uuid/uuid.dart';

/// Plex 媒体服务器适配器
class PlexAdapter extends MediaServerAdapter {
  PlexAdapter();

  // 与 PlexAuthWidget 共用同一个 key，确保 PIN 授权和连接使用相同的 clientId
  static const String _clientIdKey = 'plex_client_identifier';

  // 缓存的 clientId（内存级别，与 PlexAuthWidget 共享）
  static String? _cachedClientId;

  late PlexApi _api;
  late String _clientId;
  bool _isConnected = false;
  ServiceConnectionConfig? _config;
  String? _serverName;
  String? _serverVersion;
  String? _machineIdentifier;
  PlexVirtualFileSystem? _virtualFs;

  @override
  ServiceAdapterInfo get info => const ServiceAdapterInfo(
        name: 'Plex',
        type: SourceType.plex,
        description: 'Plex 媒体服务器适配器',
      );

  @override
  bool get isConnected => _isConnected;

  @override
  ServiceConnectionConfig? get connection => _config;

  /// 加载或生成持久化的 clientId
  /// 与 PlexAuthWidget 共享同一个存储 key，确保一致性
  Future<void> _loadOrGenerateClientId() async {
    if (_cachedClientId != null) {
      _clientId = _cachedClientId!;
      return;
    }

    try {
      final box = await HiveUtils.getSettingsBox();
      final storedId = box.get(_clientIdKey) as String?;
      if (storedId != null && storedId.isNotEmpty) {
        _cachedClientId = storedId;
        _clientId = storedId;
        logger.d('PlexAdapter: 使用已存储的 clientId');
      } else {
        _cachedClientId = 'mynas-${const Uuid().v4()}';
        await box.put(_clientIdKey, _cachedClientId);
        _clientId = _cachedClientId!;
        logger.d('PlexAdapter: 生成并存储新的 clientId');
      }
    } on Exception catch (e, st) {
      // 存储失败（如 Hive 未初始化），降级到内存临时 clientId，不影响连接
      AppError.ignore(e, st, 'Plex clientId 持久化失败，使用临时 ID');
      _clientId = 'mynas-${const Uuid().v4()}';
    }
  }

  @override
  Future<ServiceConnectionResult> connect(ServiceConnectionConfig config) async {
    try {
      // 加载或生成持久化的 clientId
      await _loadOrGenerateClientId();

      _api = PlexApi(
        serverUrl: config.baseUrl,
        authToken: config.apiKey,
        clientIdentifier: _clientId,
        clientName: 'MyNas App',
      );

      // 验证令牌并获取服务器信息
      final serverInfo = await _api.getServerInfo();
      _serverName = serverInfo.name;
      _serverVersion = serverInfo.version;
      _machineIdentifier = serverInfo.machineIdentifier;

      // 检查服务器版本兼容性（Plex 版本检查为建议性质）
      // Plex 不强制版本要求，连接都能成功，但可能功能受限

      _isConnected = true;
      _config = config;

      // 创建虚拟文件系统
      _virtualFs = PlexVirtualFileSystem(
        api: _api,
        sourceId: config.extraConfig?['sourceId'] as String? ?? '',
      );

      return ServiceConnectionSuccess(this);
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'plexAdapter.connect', {'host': config.baseUrl});
      return ServiceConnectionFailure(_parseError(e));
    }
  }

  @override
  Future<void> disconnect() async {
    _isConnected = false;
    _config = null;
    _serverName = null;
    _serverVersion = null;
    _machineIdentifier = null;
    _virtualFs = null;
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    _api.dispose();
  }

  @override
  SourceType get serverType => SourceType.plex;

  @override
  String? get userId => _machineIdentifier;

  @override
  String? get serverName => _serverName;

  @override
  String? get serverVersion => _serverVersion;

  @override
  Future<List<MediaLibrary>> getLibraries() async {
    final libraries = await _api.getLibraries();
    return libraries
        .where((lib) => lib.isVideo)
        .map((lib) => MediaLibrary(
              id: lib.key,
              name: lib.title,
              type: _toMediaLibraryType(lib.type),
            ))
        .toList();
  }

  @override
  Future<MediaItemsResult> getItems({
    String? libraryId,
    String? parentId,
    int startIndex = 0,
    int limit = 100,
    String? sortBy,
    String? sortOrder,
    List<MediaItemType>? includeItemTypes,
  }) async {
    PlexItemsResult result;

    if (parentId != null) {
      // 获取子项目
      result = await _api.getItemChildren(parentId);
    } else if (libraryId != null) {
      // 获取媒体库内容
      result = await _api.getLibraryContents(
        libraryId,
        start: startIndex,
        size: limit,
        sort: _toPlexSort(sortBy, sortOrder),
      );
    } else {
      // 返回空结果
      return const MediaItemsResult(items: [], totalRecordCount: 0);
    }

    return MediaItemsResult(
      items: result.items.map(_toMediaItem).toList(),
      totalRecordCount: result.totalSize ?? result.items.length,
      startIndex: result.offset ?? startIndex,
    );
  }

  @override
  Future<MediaItem> getItemDetail(String itemId) async {
    final item = await _api.getItem(itemId);
    if (item == null) {
      throw Exception('项目不存在: $itemId');
    }
    return _toMediaItem(item);
  }

  @override
  String getImageUrl(
    String itemId,
    MediaImageType imageType, {
    int? maxWidth,
    int? maxHeight,
    String? tag,
  }) {
    // Plex 需要使用 thumb/art 路径
    final path = imageType == MediaImageType.backdrop
        ? '/library/metadata/$itemId/art'
        : '/library/metadata/$itemId/thumb';

    return _api.getImageUrl(path, width: maxWidth, height: maxHeight);
  }

  @override
  Future<MediaStreamInfo> getStreamInfo(
    String itemId, {
    bool preferDirectPlay = true,
    int? maxStreamingBitrate,
  }) async {
    final item = await _api.getItem(itemId);
    if (item == null || item.media == null || item.media!.isEmpty) {
      throw Exception('没有可用的媒体源');
    }

    final media = item.media!.first;
    if (media.parts == null || media.parts!.isEmpty) {
      throw Exception('没有可用的媒体部分');
    }

    final part = media.parts!.first;

    if (preferDirectPlay && part.key != null) {
      return MediaStreamInfo(
        url: _api.getPlayUrl(part.key!),
        playMethod: MediaPlayMethod.directPlay,
        container: part.container,
        videoCodec: media.videoCodec,
        audioCodec: media.audioCodec,
      );
    }

    // 使用转码
    return MediaStreamInfo(
      url: _api.getTranscodeUrl(
        itemId,
        maxWidth: 1920,
        maxHeight: 1080,
        videoBitrate: maxStreamingBitrate,
      ),
      playMethod: MediaPlayMethod.transcode,
      transcodingUrl: _api.getTranscodeUrl(itemId),
      transcodingContainer: 'ts',
    );
  }

  @override
  Future<void> reportPlayback(PlaybackReport report) async {
    // 计算时长（Plex 使用毫秒）
    final timeMs = report.positionTicks != null
        ? (report.positionTicks! / 10000).round()
        : 0;

    switch (report.reportType) {
      case PlaybackReportType.start:
        await _api.reportPlaybackStart(
          ratingKey: report.itemId,
          sessionKey: report.playSessionId ?? '',
          offset: timeMs,
        );
      case PlaybackReportType.progress:
        await _api.reportPlaybackProgress(
          ratingKey: report.itemId,
          time: timeMs,
          duration: 0,
          state: report.isPaused ? 'paused' : 'playing',
        );
      case PlaybackReportType.stop:
        await _api.reportPlaybackStopped(
          ratingKey: report.itemId,
          time: timeMs,
          duration: 0,
        );
    }
  }

  @override
  Future<void> setWatched(String itemId, bool watched) async {
    if (watched) {
      await _api.markWatched(itemId);
    } else {
      await _api.markUnwatched(itemId);
    }
  }

  @override
  NasFileSystem get virtualFileSystem {
    if (_virtualFs == null) {
      throw StateError('Adapter not connected');
    }
    return _virtualFs!;
  }

  @override
  Future<MediaItemsResult> search(
    String query, {
    int limit = 20,
    List<MediaItemType>? includeItemTypes,
  }) async {
    final result = await _api.search(query, limit: limit);
    return MediaItemsResult(
      items: result.items.map(_toMediaItem).toList(),
      totalRecordCount: result.items.length,
    );
  }

  @override
  // Plex 没有直接的推荐 API，使用最近添加
  Future<MediaItemsResult> getRecommendations({int limit = 20}) =>
      getRecentlyAdded(limit: limit);

  @override
  Future<MediaItemsResult> getLatestMedia({
    String? libraryId,
    int limit = 20,
    List<MediaItemType>? includeItemTypes,
  }) async {
    final result = await _api.getRecentlyAdded(
      libraryKey: libraryId,
      limit: limit,
    );
    return MediaItemsResult(
      items: result.items.map(_toMediaItem).toList(),
      totalRecordCount: result.items.length,
    );
  }

  @override
  Future<MediaItemsResult> getResumeItems({int limit = 20}) async {
    final result = await _api.getOnDeck(limit: limit);
    return MediaItemsResult(
      items: result.items.map(_toMediaItem).toList(),
      totalRecordCount: result.items.length,
    );
  }

  @override
  Future<MediaItem?> getNextUp({String? seriesId}) async {
    if (seriesId == null) {
      final onDeck = await getResumeItems(limit: 1);
      return onDeck.items.isNotEmpty ? onDeck.items.first : null;
    }

    // 1. 优先从 On Deck 中找属于该剧集的集（包含正在看且未完成的，有 viewOffset）
    //    Plex 的 episode 通过 grandparentRatingKey 关联到 series
    final onDeck = await _api.getOnDeck(limit: 50);
    PlexMediaItem? inProgress;
    for (final item in onDeck.items) {
      if (item.grandparentRatingKey == seriesId) {
        inProgress = item;
        break;
      }
    }
    if (inProgress != null) {
      return _toMediaItem(inProgress);
    }

    // 2. On Deck 没有，则按季依次找首个未看的集
    final children = await _api.getItemChildren(seriesId);
    for (final child in children.items) {
      if (child.type == 'season') {
        // 跳过 "All Episodes" / 特别篇 等空季
        final episodes = await _api.getItemChildren(child.ratingKey);
        for (final ep in episodes.items) {
          if (!ep.isWatched) {
            return _toMediaItem(ep);
          }
        }
      } else if (child.type == 'episode') {
        // children 已经是 episodes（部分 Plex 设置直接返回扁平剧集列表）
        if (!child.isWatched) {
          return _toMediaItem(child);
        }
      }
    }

    return null;
  }

  @override
  Future<bool> toggleFavorite(String itemId) async {
    // Plex 没有收藏功能，使用评分代替
    final item = await _api.getItem(itemId);
    if (item == null) return false;

    final currentRating = item.rating ?? 0;
    if (currentRating > 0) {
      await _api.setRating(itemId, 0);
      return false;
    } else {
      await _api.setRating(itemId, 10);
      return true;
    }
  }

  @override
  Future<MediaItemsResult> getRecentlyAdded({int limit = 100}) async {
    final result = await _api.getRecentlyAdded(limit: limit);
    return MediaItemsResult(
      items: result.items.map(_toMediaItem).toList(),
      totalRecordCount: result.items.length,
    );
  }

  // === 转换方法 ===

  MediaLibraryType _toMediaLibraryType(String type) => switch (type) {
        'movie' => MediaLibraryType.movies,
        'show' => MediaLibraryType.tvShows,
        'artist' => MediaLibraryType.music,
        'photo' => MediaLibraryType.photos,
        _ => MediaLibraryType.unknown,
      };

  MediaItemType _toMediaItemType(String type) => switch (type) {
        'movie' => MediaItemType.movie,
        'show' => MediaItemType.series,
        'season' => MediaItemType.season,
        'episode' => MediaItemType.episode,
        'artist' => MediaItemType.folder,
        'album' => MediaItemType.musicAlbum,
        'track' => MediaItemType.audio,
        'photo' => MediaItemType.photo,
        _ => MediaItemType.unknown,
      };

  MediaItem _toMediaItem(PlexMediaItem item) {
    // 获取流信息
    List<MediaStream>? streams;
    if (item.media != null && item.media!.isNotEmpty) {
      final media = item.media!.first;
      if (media.parts != null && media.parts!.isNotEmpty) {
        final part = media.parts!.first;
        if (part.streams != null) {
          streams = part.streams!.map((s) => MediaStream(
              type: s.isVideo
                  ? MediaStreamType.video
                  : s.isAudio
                      ? MediaStreamType.audio
                      : MediaStreamType.subtitle,
              index: s.index ?? 0,
              codec: s.codec,
              language: s.language,
              title: s.title,
              isDefault: s.isDefault,
              isForced: s.forced,
              width: s.width,
              height: s.height,
              bitRate: s.bitrate,
              channels: s.channels,
              sampleRate: s.samplingRate,
            )).toList();
        }
      }
    }

    // 构建 Provider IDs
    Map<String, String>? providerIds;
    if (item.tmdbId != null || item.imdbId != null || item.tvdbId != null) {
      providerIds = {};
      if (item.tmdbId != null) providerIds['Tmdb'] = item.tmdbId!;
      if (item.imdbId != null) providerIds['Imdb'] = item.imdbId!;
      if (item.tvdbId != null) providerIds['Tvdb'] = item.tvdbId!;
    }

    return MediaItem(
      id: item.ratingKey,
      name: item.title,
      type: _toMediaItemType(item.type),
      parentId: item.parentRatingKey,
      seriesId: item.grandparentRatingKey,
      seriesName: item.grandparentTitle,
      seasonId: item.parentRatingKey,
      seasonName: item.parentTitle,
      indexNumber: item.index,
      parentIndexNumber: item.parentIndex,
      overview: item.summary,
      communityRating: item.audienceRating ?? item.rating,
      productionYear: item.year,
      premiereDate: item.originallyAvailableAt != null
          ? DateTime.tryParse(item.originallyAvailableAt!)
          : null,
      runTimeTicks: item.duration != null
          ? item.duration! * 10000 // 毫秒转 ticks
          : null,
      genres: item.genres,
      mediaStreams: streams,
      providerIds: providerIds,
      userData: MediaUserData(
        playbackPositionTicks: item.viewOffset != null
            ? item.viewOffset! * 10000
            : null,
        playCount: item.viewCount,
        played: item.isWatched,
        lastPlayedDate: item.lastViewedAt != null
            ? DateTime.fromMillisecondsSinceEpoch(item.lastViewedAt! * 1000)
            : null,
      ),
    );
  }

  String? _toPlexSort(String? sortBy, String? sortOrder) {
    if (sortBy == null) return null;

    final direction = sortOrder?.toLowerCase() == 'descending' ? ':desc' : '';

    return switch (sortBy.toLowerCase()) {
      'sortname' || 'name' => 'titleSort$direction',
      'datecreated' => 'addedAt$direction',
      'premieredate' => 'originallyAvailableAt$direction',
      'communityrating' => 'rating$direction',
      'productionyear' => 'year$direction',
      _ => sortBy + direction,
    };
  }

  String _parseError(Object e) {
    final message = e.toString();
    if (message.contains('401')) {
      return '认证失败：Plex Token 无效';
    } else if (message.contains('403')) {
      return '访问被拒绝：权限不足';
    } else if (message.contains('404')) {
      return '服务器未找到：请检查地址是否正确';
    } else if (message.contains('timeout') || message.contains('Timeout')) {
      return '连接超时：请检查网络或服务器状态';
    } else if (message.contains('SocketException') ||
        message.contains('Connection refused')) {
      return '无法连接：请检查服务器地址和端口';
    }
    return '连接失败：$message';
  }
}
