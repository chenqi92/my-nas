import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/hive_utils.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/media_server_adapters/base/media_server_adapter.dart';
import 'package:my_nas/media_server_adapters/base/media_server_entities.dart';
import 'package:my_nas/media_server_adapters/emby/api/emby_api.dart';
import 'package:my_nas/media_server_adapters/emby/emby_virtual_fs.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/service_adapters/base/service_adapter.dart';
import 'package:uuid/uuid.dart';

/// Emby 媒体服务器适配器
class EmbyAdapter extends MediaServerAdapter {
  EmbyAdapter();

  // 持久化 deviceId 的键名
  static const String _deviceIdKey = 'emby_device_id';

  // 缓存的 deviceId（内存级别）
  static String? _cachedDeviceId;

  late EmbyApi _api;
  late String _deviceId;
  bool _isConnected = false;
  ServiceConnectionConfig? _config;
  String? _userId;
  String? _serverName;
  String? _serverVersion;
  EmbyVirtualFileSystem? _virtualFs;

  @override
  ServiceAdapterInfo get info => ServiceAdapterInfo(
        name: 'Emby',
        type: SourceType.emby,
        description: appL10n.embyAdapterDescription,
      );

  @override
  bool get isConnected => _isConnected;

  @override
  ServiceConnectionConfig? get connection => _config;

  /// 加载或生成持久化的 deviceId
  Future<void> _loadOrGenerateDeviceId() async {
    if (_cachedDeviceId != null) {
      _deviceId = _cachedDeviceId!;
      return;
    }

    try {
      final box = await HiveUtils.getSettingsBox();
      final storedId = box.get(_deviceIdKey) as String?;
      if (storedId != null && storedId.isNotEmpty) {
        _cachedDeviceId = storedId;
        _deviceId = storedId;
        logger.d('EmbyAdapter: 使用已存储的 deviceId');
      } else {
        _cachedDeviceId = 'mynas-emby-${const Uuid().v4()}';
        await box.put(_deviceIdKey, _cachedDeviceId);
        _deviceId = _cachedDeviceId!;
        logger.d('EmbyAdapter: 生成并存储新的 deviceId');
      }
    } on Exception catch (e, st) {
      // 存储失败（如 Hive 未初始化），降级到内存临时 deviceId，不影响连接
      AppError.ignore(e, st, 'Emby deviceId 持久化失败，使用临时 ID');
      _deviceId = 'mynas-emby-${const Uuid().v4()}';
    }
  }

  @override
  Future<ServiceConnectionResult> connect(ServiceConnectionConfig config) async {
    try {
      // 加载或生成持久化的 deviceId
      await _loadOrGenerateDeviceId();

      _api = EmbyApi(
        serverUrl: config.baseUrl,
        deviceId: _deviceId,
        deviceName: 'MyNas App',
      );

      // 获取服务器信息
      final serverInfo = await _api.getPublicSystemInfo();
      _serverName = serverInfo.serverName;
      _serverVersion = serverInfo.version;

      // 检查服务器版本兼容性
      if (_serverVersion != null) {
        final compatibility = MediaServerVersionRequirements.checkEmby(
          _serverVersion!,
        );
        if (!compatibility.isCompatible) {
          return ServiceConnectionFailure(compatibility.message!);
        }
      }

      // 认证
      if (config.apiKey != null && config.apiKey!.isNotEmpty) {
        // API Key 认证
        final result = await _api.loginWithApiKey(config.apiKey!);
        _userId = result.userId;
      } else if (config.username != null) {
        // 用户名密码认证
        final result = await _api.login(
          config.username!,
          config.password ?? '',
        );
        _userId = result.userId;
      } else {
        return ServiceConnectionFailure(appL10n.embyConnectAuthRequired);
      }

      _isConnected = true;
      _config = config;

      // 创建虚拟文件系统
      _virtualFs = EmbyVirtualFileSystem(
        api: _api,
        sourceId: config.extraConfig?['sourceId'] as String? ?? '',
      );

      return ServiceConnectionSuccess(this);
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'embyAdapter.connect', {'host': config.baseUrl});
      return ServiceConnectionFailure(_parseError(e));
    }
  }

  @override
  Future<void> disconnect() async {
    _isConnected = false;
    _userId = null;
    _config = null;
    _virtualFs = null;
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    _api.dispose();
  }

  @override
  SourceType get serverType => SourceType.emby;

  @override
  String? get userId => _userId;

  @override
  String? get serverName => _serverName;

  @override
  String? get serverVersion => _serverVersion;

  @override
  Future<List<MediaLibrary>> getLibraries() async {
    final libraries = await _api.getLibraries();
    return libraries.map((e) => e.toMediaLibrary()).toList();
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
    final result = await _api.getItems(
      parentId: parentId ?? libraryId,
      startIndex: startIndex,
      limit: limit,
      sortBy: sortBy,
      sortOrder: sortOrder,
      includeItemTypes:
          includeItemTypes?.map(_toEmbyType).join(','),
    );
    return result.toMediaItemsResult();
  }

  @override
  Future<MediaItem> getItemDetail(String itemId) async {
    final item = await _api.getItem(itemId);
    return item.toMediaItem();
  }

  @override
  String getImageUrl(
    String itemId,
    MediaImageType imageType, {
    int? maxWidth,
    int? maxHeight,
    String? tag,
  }) => _api.getImageUrl(
      itemId,
      imageType.toJellyfinType(),
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      tag: tag,
    );

  @override
  Future<MediaStreamInfo> getStreamInfo(
    String itemId, {
    bool preferDirectPlay = true,
    int? maxStreamingBitrate,
  }) async {
    final playbackInfo = await _api.getPlaybackInfo(itemId);

    if (playbackInfo.mediaSources.isEmpty) {
      throw Exception(appL10n.embyStreamNoMediaSource);
    }

    final source = playbackInfo.mediaSources.first;

    // 确定播放方式
    MediaPlayMethod playMethod;
    String url;

    if (preferDirectPlay && source.supportsDirectPlay) {
      playMethod = MediaPlayMethod.directPlay;
      url = _api.getDirectStreamUrl(itemId, mediaSourceId: source.id);
    } else if (source.supportsDirectStream) {
      playMethod = MediaPlayMethod.directStream;
      url = source.directStreamUrl ?? _api.getDirectStreamUrl(itemId);
    } else if (source.supportsTranscoding && source.transcodingUrl != null) {
      playMethod = MediaPlayMethod.transcode;
      url = '${_api.serverUrl}${source.transcodingUrl}';
    } else {
      playMethod = MediaPlayMethod.directPlay;
      url = _api.getDirectStreamUrl(itemId, mediaSourceId: source.id);
    }

    return MediaStreamInfo(
      url: url,
      playMethod: playMethod,
      container: source.container,
      transcodingUrl:
          source.transcodingUrl != null ? '${_api.serverUrl}${source.transcodingUrl}' : null,
      transcodingContainer: source.transcodingContainer,
    );
  }

  @override
  Future<void> reportPlayback(PlaybackReport report) async {
    switch (report.reportType) {
      case PlaybackReportType.start:
        await _api.reportPlaybackStart(
          itemId: report.itemId,
          positionTicks: report.positionTicks,
          playSessionId: report.playSessionId,
          audioStreamIndex: report.audioStreamIndex,
          subtitleStreamIndex: report.subtitleStreamIndex,
        );
      case PlaybackReportType.progress:
        await _api.reportPlaybackProgress(
          itemId: report.itemId,
          positionTicks: report.positionTicks,
          playSessionId: report.playSessionId,
          isPaused: report.isPaused,
        );
      case PlaybackReportType.stop:
        await _api.reportPlaybackStopped(
          itemId: report.itemId,
          positionTicks: report.positionTicks,
          playSessionId: report.playSessionId,
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
    final result = await _api.search(
      query,
      limit: limit,
      includeItemTypes: includeItemTypes?.map(_toEmbyType).join(','),
    );
    return result.toMediaItemsResult();
  }

  @override
  Future<MediaItemsResult> getRecommendations({int limit = 20}) async {
    // Emby 的推荐 API 与 Jellyfin 相同
    final result = await _api.getLatestItems(limit: limit);
    return result.toMediaItemsResult();
  }

  @override
  Future<MediaItemsResult> getLatestMedia({
    String? libraryId,
    int limit = 20,
    List<MediaItemType>? includeItemTypes,
  }) async {
    final result = await _api.getLatestItems(
      parentId: libraryId,
      limit: limit,
      includeItemTypes: includeItemTypes?.map(_toEmbyType).join(','),
    );
    return result.toMediaItemsResult();
  }

  @override
  Future<MediaItemsResult> getResumeItems({int limit = 20}) async {
    final result = await _api.getResumeItems(limit: limit);
    return result.toMediaItemsResult();
  }

  @override
  Future<MediaItem?> getNextUp({String? seriesId}) async {
    final item = await _api.getNextUp(seriesId: seriesId);
    return item?.toMediaItem();
  }

  @override
  Future<bool> toggleFavorite(String itemId) async => _api.toggleFavorite(itemId);

  @override
  Future<MediaItemsResult> getRecentlyAdded({int limit = 100}) async {
    final result = await _api.getLatestItems(limit: limit);
    return result.toMediaItemsResult();
  }

  // === 辅助方法 ===

  String _toEmbyType(MediaItemType type) => switch (type) {
        MediaItemType.movie => 'Movie',
        MediaItemType.series => 'Series',
        MediaItemType.season => 'Season',
        MediaItemType.episode => 'Episode',
        MediaItemType.musicAlbum => 'MusicAlbum',
        MediaItemType.audio => 'Audio',
        MediaItemType.photo => 'Photo',
        MediaItemType.folder => 'Folder',
        MediaItemType.person => 'Person',
        MediaItemType.unknown => 'Unknown',
      };

  String _parseError(Object e) {
    final message = e.toString();
    if (message.contains('401')) {
      return appL10n.embyErrorAuth;
    } else if (message.contains('403')) {
      return appL10n.embyErrorAccessDenied;
    } else if (message.contains('404')) {
      return appL10n.embyErrorNotFound;
    } else if (message.contains('timeout') || message.contains('Timeout')) {
      return appL10n.embyErrorTimeout;
    } else if (message.contains('SocketException') ||
        message.contains('Connection refused')) {
      return appL10n.embyErrorCannotConnect;
    }
    return appL10n.embyErrorConnectionFailed(message);
  }
}
