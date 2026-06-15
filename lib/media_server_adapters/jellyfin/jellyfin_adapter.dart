import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/network/dio_client.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/media_server_adapters/base/media_server_adapter.dart';
import 'package:my_nas/media_server_adapters/base/media_server_entities.dart';
import 'package:my_nas/media_server_adapters/jellyfin/api/jellyfin_api.dart';
import 'package:my_nas/media_server_adapters/jellyfin/jellyfin_virtual_fs.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/service_adapters/base/service_adapter.dart';

/// Jellyfin 媒体服务器适配器
class JellyfinAdapter extends MediaServerAdapter {
  JellyfinAdapter() {
    logger.i('JellyfinAdapter: 初始化适配器');
    _dioClient = DioClient(allowSelfSigned: true);
    _api = JellyfinApi(dio: _dioClient.dio);
  }

  late final DioClient _dioClient;
  late final JellyfinApi _api;
  JellyfinVirtualFileSystem? _virtualFs;

  ServiceConnectionConfig? _connection;
  bool _connected = false;

  /// 获取 API 客户端（供高级用法）
  JellyfinApi get api => _api;

  // === ServiceAdapter 接口实现 ===

  @override
  ServiceAdapterInfo get info => const ServiceAdapterInfo(
        name: 'Jellyfin',
        type: SourceType.jellyfin,
        description: 'Jellyfin 媒体服务器',
      );

  @override
  bool get isConnected => _connected;

  @override
  ServiceConnectionConfig? get connection => _connection;

  @override
  Future<ServiceConnectionResult> connect(ServiceConnectionConfig config) async {
    logger
      ..i('JellyfinAdapter: 开始连接')
      ..i('JellyfinAdapter: 目标地址 => ${config.baseUrl}')
      ..i('JellyfinAdapter: 用户名 => ${config.username}');

    _connection = config;
    _api.setBaseUrl(config.baseUrl);

    try {
      // 先获取服务器信息
      await _api.getPublicServerInfo();
      logger
        ..i('JellyfinAdapter: 服务器名称 => ${_api.serverName}')
        ..i('JellyfinAdapter: 服务器版本 => ${_api.serverVersion}');

      // 检查服务器版本兼容性
      if (_api.serverVersion != null) {
        final compatibility = MediaServerVersionRequirements.checkJellyfin(
          _api.serverVersion!,
        );
        if (!compatibility.isCompatible) {
          logger.w('JellyfinAdapter: 服务器版本不兼容 - ${compatibility.message}');
          return ServiceConnectionFailure(compatibility.message!);
        }
        if (compatibility.warnings.isNotEmpty) {
          for (final warning in compatibility.warnings) {
            logger.w('JellyfinAdapter: 版本警告 - $warning');
          }
        }
      }

      // 根据配置选择认证方式
      final accessToken = config.extraConfig?['accessToken'] as String?;
      final userId = config.extraConfig?['userId'] as String?;

      if (accessToken != null && accessToken.isNotEmpty) {
        // 使用已有的 Access Token 认证（Quick Connect）
        logger.i('JellyfinAdapter: 使用 Access Token 认证 (Quick Connect)');
        _api.setAccessToken(accessToken, userId);
        // 验证 token 是否有效
        try {
          await _api.getLibraries();
        } on Exception {
          return const ServiceConnectionFailure('Access Token 无效或已过期');
        }
      } else if (config.apiKey != null && config.apiKey!.isNotEmpty) {
        // 使用 API Key 认证
        logger.i('JellyfinAdapter: 使用 API Key 认证');
        final success = await _api.authenticateWithApiKey(config.apiKey!);
        if (!success) {
          return const ServiceConnectionFailure('API Key 无效或没有可用用户');
        }
      } else if (config.username != null && config.password != null) {
        // 使用用户名密码认证
        logger.i('JellyfinAdapter: 使用用户名密码认证');
        await _api.authenticateByName(
          username: config.username!,
          password: config.password!,
        );
      } else {
        return const ServiceConnectionFailure('请提供 API Key 或用户名密码');
      }

      _connected = true;
      _virtualFs = JellyfinVirtualFileSystem(api: _api);

      logger.i('JellyfinAdapter: 连接成功');
      return ServiceConnectionSuccess(this);
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'jellyfinAdapter.connect', {'host': config.baseUrl});
      return ServiceConnectionFailure(_parseError(e));
    }
  }

  @override
  Future<void> disconnect() async {
    logger.i('JellyfinAdapter: 断开连接');
    try {
      await _api.logout();
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'Jellyfin 登出失败（已断开连接，无影响）');
    }
    _connected = false;
    _virtualFs = null;
  }

  @override
  Future<void> dispose() async {
    logger.i('JellyfinAdapter: 释放资源');
    await disconnect();
  }

  // === MediaServerAdapter 特有功能 ===

  @override
  SourceType get serverType => SourceType.jellyfin;

  @override
  String? get userId => _api.userId;

  @override
  String? get serverName => _api.serverName;

  @override
  String? get serverVersion => _api.serverVersion;

  @override
  Future<List<MediaLibrary>> getLibraries() async {
    logger.i('JellyfinAdapter: 获取媒体库列表');
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
    final effectiveParentId = parentId ?? libraryId;

    // 将 MediaItemType 转换为 Jellyfin 类型字符串
    List<String>? jellyfinTypes;
    if (includeItemTypes != null) {
      jellyfinTypes = includeItemTypes.map(_toJellyfinType).toList();
    }

    final result = await _api.getItems(
      parentId: effectiveParentId,
      startIndex: startIndex,
      limit: limit,
      sortBy: sortBy,
      sortOrder: sortOrder,
      includeItemTypes: jellyfinTypes,
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
      imageType,
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
    logger.i('JellyfinAdapter: 获取视频流信息, itemId=$itemId');

    final playbackInfo = await _api.getPlaybackInfo(itemId);
    if (playbackInfo.mediaSources.isEmpty) {
      throw Exception('没有可用的媒体源');
    }

    final source = playbackInfo.mediaSources.first;

    // 根据偏好和支持情况选择播放方式
    if (preferDirectPlay && source.supportsDirectPlay) {
      return MediaStreamInfo(
        url: _api.getDirectStreamUrl(itemId, mediaSourceId: source.id),
        playMethod: MediaPlayMethod.directPlay,
        container: source.container,
      );
    } else if (source.supportsDirectStream) {
      return MediaStreamInfo(
        url: _api.getDirectStreamUrl(itemId, mediaSourceId: source.id),
        playMethod: MediaPlayMethod.directStream,
        container: source.container,
      );
    } else if (source.supportsTranscoding) {
      return MediaStreamInfo(
        url: _api.getHlsStreamUrl(
          itemId,
          playSessionId: playbackInfo.playSessionId,
          mediaSourceId: source.id,
        ),
        playMethod: MediaPlayMethod.transcode,
        container: 'ts',
        transcodingUrl: source.transcodingUrl,
        transcodingContainer: source.transcodingContainer,
      );
    } else {
      throw Exception('媒体源不支持任何播放方式');
    }
  }

  @override
  Future<void> reportPlayback(PlaybackReport report) async {
    switch (report.reportType) {
      case PlaybackReportType.start:
        await _api.reportPlaybackStart(
          itemId: report.itemId,
          positionTicks: report.positionTicks,
          playSessionId: report.playSessionId,
        );
      case PlaybackReportType.progress:
        await _api.reportPlaybackProgress(
          itemId: report.itemId,
          positionTicks: report.positionTicks ?? 0,
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
      throw StateError('适配器未连接，无法获取虚拟文件系统');
    }
    return _virtualFs!;
  }

  @override
  Future<MediaItemsResult> search(
    String query, {
    int limit = 20,
    List<MediaItemType>? includeItemTypes,
  }) async {
    List<String>? jellyfinTypes;
    if (includeItemTypes != null) {
      jellyfinTypes = includeItemTypes.map(_toJellyfinType).toList();
    }

    final result = await _api.search(
      query,
      limit: limit,
      includeItemTypes: jellyfinTypes,
    );
    return result.toMediaItemsResult();
  }

  @override
  Future<MediaItemsResult> getRecommendations({int limit = 20}) =>
      // Jellyfin 没有专门的推荐 API，返回最新添加的内容
      getLatestMedia(limit: limit);

  @override
  Future<MediaItemsResult> getLatestMedia({
    String? libraryId,
    int limit = 20,
    List<MediaItemType>? includeItemTypes,
  }) async {
    List<String>? jellyfinTypes;
    if (includeItemTypes != null) {
      jellyfinTypes = includeItemTypes.map(_toJellyfinType).toList();
    }

    final result = await _api.getLatestMedia(
      parentId: libraryId,
      limit: limit,
      includeItemTypes: jellyfinTypes,
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
  Future<bool> toggleFavorite(String itemId) async {
    // 获取当前状态
    final item = await _api.getItem(itemId);
    final isFavorite = item.userData?.isFavorite ?? false;
    // 切换状态
    await _api.toggleFavorite(itemId, !isFavorite);
    return !isFavorite;
  }

  @override
  Future<MediaItemsResult> getRecentlyAdded({int limit = 100}) async {
    final result = await _api.getLatestMedia(limit: limit);
    return result.toMediaItemsResult();
  }

  // === 辅助方法 ===

  /// 将 MediaItemType 转换为 Jellyfin 类型字符串
  String _toJellyfinType(MediaItemType type) => switch (type) {
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

  /// 解析错误信息
  String _parseError(Object e) {
    final message = e.toString();
    if (message.contains('401')) {
      return '认证失败：用户名或密码错误';
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
