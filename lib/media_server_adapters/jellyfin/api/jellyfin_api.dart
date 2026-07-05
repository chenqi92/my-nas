import 'dart:io';

import 'package:dio/dio.dart';
import 'package:my_nas/core/network/dio_client.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/media_server_adapters/base/media_server_entities.dart';
import 'package:my_nas/media_server_adapters/jellyfin/api/jellyfin_models.dart';

/// Jellyfin API 客户端
class JellyfinApi {
  JellyfinApi({Dio? dio}) : _dio = dio ?? DioClient().dio;

  final Dio _dio;
  String? _baseUrl;
  String? _accessToken;
  String? _userId;
  String? _serverId;
  String? _serverName;
  String? _serverVersion;

  /// 设置服务器地址
  void setBaseUrl(String url) {
    // 确保 URL 末尾没有斜杠
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    logger.i('JellyfinApi: baseUrl 设置为 $_baseUrl');
  }

  /// 获取当前用户 ID
  String? get userId => _userId;

  /// 获取服务器 ID
  String? get serverId => _serverId;

  /// 获取服务器名称
  String? get serverName => _serverName;

  /// 获取服务器版本
  String? get serverVersion => _serverVersion;

  /// 是否已认证
  bool get isAuthenticated => _accessToken != null && _userId != null;

  /// 设置认证信息
  void setAuth({
    required String accessToken,
    required String userId,
    String? serverId,
  }) {
    _accessToken = accessToken;
    _userId = userId;
    _serverId = serverId;
    logger.i('JellyfinApi: 认证信息已设置, userId=$userId');
  }

  /// 清除认证信息
  void clearAuth() {
    _accessToken = null;
    _userId = null;
    logger.i('JellyfinApi: 认证信息已清除');
  }

  /// 直接设置 Access Token（用于 Quick Connect 等外部认证）
  void setAccessToken(String accessToken, [String? userId]) {
    _accessToken = accessToken;
    if (userId != null) {
      _userId = userId;
    }
    logger.i('JellyfinApi: Access Token 已设置');
  }

  /// 构建请求头
  Map<String, String> _buildHeaders({bool requireAuth = true}) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    // 添加客户端标识头
    final authValue = _buildAuthorizationHeader();
    headers['Authorization'] = authValue;

    // 如果有 access token，也添加 X-Emby-Token
    if (_accessToken != null && requireAuth) {
      headers['X-Emby-Token'] = _accessToken!;
    }

    return headers;
  }

  /// 构建 MediaBrowser 格式的 Authorization 头
  String _buildAuthorizationHeader() {
    final parts = <String>[
      'Client="MyNAS"',
      'Device="${Platform.operatingSystem}"',
      'DeviceId="mynas-${Platform.localHostname}"',
      'Version="1.0.0"',
    ];
    if (_accessToken != null) {
      parts.add('Token="$_accessToken"');
    }
    return 'MediaBrowser ${parts.join(", ")}';
  }

  /// 发送 GET 请求
  Future<Response<T>> _get<T>(
    String path, {
    Map<String, dynamic>? queryParams,
    bool requireAuth = true,
  }) async {
    final url = '$_baseUrl$path';
    return _dio.get<T>(
      url,
      queryParameters: queryParams,
      options: Options(headers: _buildHeaders(requireAuth: requireAuth)),
    );
  }

  /// 发送 POST 请求
  Future<Response<T>> _post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParams,
    bool requireAuth = true,
  }) async {
    final url = '$_baseUrl$path';
    return _dio.post<T>(
      url,
      data: data,
      queryParameters: queryParams,
      options: Options(headers: _buildHeaders(requireAuth: requireAuth)),
    );
  }

  // === 认证相关 API ===

  /// 获取服务器公开信息（不需要认证）
  Future<JellyfinServerInfo> getPublicServerInfo() async {
    logger.i('JellyfinApi: 获取服务器公开信息');
    final response = await _get<Map<String, dynamic>>(
      '/System/Info/Public',
      requireAuth: false,
    );
    final info = JellyfinServerInfo.fromJson(response.data!);
    _serverId = info.serverId;
    _serverName = info.serverName;
    _serverVersion = info.version;
    return info;
  }

  /// 获取公开用户列表（不需要认证）
  Future<List<JellyfinUser>> getPublicUsers() async {
    logger.i('JellyfinApi: 获取公开用户列表');
    final response = await _get<List<dynamic>>(
      '/Users/Public',
      requireAuth: false,
    );
    return (response.data ?? [])
        .map((e) => JellyfinUser.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 使用用户名密码登录
  Future<JellyfinAuthResult> authenticateByName({
    required String username,
    required String password,
  }) async {
    logger.i('JellyfinApi: 开始用户名密码认证, username=$username');
    final response = await _post<Map<String, dynamic>>(
      '/Users/AuthenticateByName',
      data: {'Username': username, 'Pw': password},
      requireAuth: false,
    );

    final result = JellyfinAuthResult.fromJson(response.data!);
    _accessToken = result.accessToken;
    _userId = result.userId;
    _serverId = result.serverId;
    _serverName = result.serverName;

    logger.i('JellyfinApi: 认证成功, userId=${result.userId}');
    return result;
  }

  /// 使用 API Key 认证
  ///
  /// API Key 不需要登录，直接设置到请求头即可
  /// 需要额外获取一个可用的用户 ID
  Future<bool> authenticateWithApiKey(String apiKey) async {
    logger.i('JellyfinApi: 使用 API Key 认证');
    _accessToken = apiKey;

    // 获取服务器信息验证 API Key 有效性
    try {
      await getPublicServerInfo();

      // 获取用户列表，选择第一个管理员用户
      final users = await getUsers();
      if (users.isEmpty) {
        logger.w('JellyfinApi: 没有可用的用户');
        return false;
      }

      _userId = users.first.id;
      logger.i('JellyfinApi: API Key 认证成功, 使用用户 ${users.first.name}');
      return true;
    } on Exception catch (e) {
      logger.e('JellyfinApi: API Key 认证失败', e);
      _accessToken = null;
      return false;
    }
  }

  /// 登出
  Future<void> logout() async {
    if (_accessToken == null) return;

    try {
      await _post<void>('/Sessions/Logout');
    } on Exception catch (e) {
      logger.w('JellyfinApi: 登出请求失败', e);
    } finally {
      clearAuth();
    }
  }

  // === Quick Connect 认证 ===

  /// 检查 Quick Connect 是否可用
  Future<bool> isQuickConnectEnabled() async {
    try {
      final response = await _get<Map<String, dynamic>>(
        '/QuickConnect/Enabled',
        requireAuth: false,
      );
      // Jellyfin 10.8+ 返回布尔值，旧版本返回状态对象
      if (response.data is bool) {
        return response.data! as bool;
      }
      return response.data?['Enabled'] == true;
    } on Exception catch (e) {
      logger.w('JellyfinApi: 检查 Quick Connect 失败', e);
      return false;
    }
  }

  /// 发起 Quick Connect 认证
  ///
  /// 返回包含 Code 和 Secret 的结果
  Future<QuickConnectResult?> initiateQuickConnect() async {
    logger.i('JellyfinApi: 发起 Quick Connect');
    try {
      final response = await _post<Map<String, dynamic>>(
        '/QuickConnect/Initiate',
        requireAuth: false,
      );

      if (response.data == null) return null;

      return QuickConnectResult.fromJson(response.data!);
    } on Exception catch (e) {
      logger.e('JellyfinApi: Quick Connect 发起失败', e);
      return null;
    }
  }

  /// 检查 Quick Connect 状态
  ///
  /// 返回 true 表示用户已授权
  Future<QuickConnectResult?> checkQuickConnect(String secret) async {
    try {
      final response = await _get<Map<String, dynamic>>(
        '/QuickConnect/Connect',
        queryParams: {'Secret': secret},
        requireAuth: false,
      );

      if (response.data == null) return null;

      return QuickConnectResult.fromJson(response.data!);
    } on Exception catch (e) {
      logger.d('JellyfinApi: Quick Connect 检查失败', e);
      return null;
    }
  }

  /// 使用 Quick Connect 完成认证
  ///
  /// [secret] Quick Connect 的 secret
  Future<JellyfinAuthResult?> authenticateWithQuickConnect(
    String secret,
  ) async {
    logger.i('JellyfinApi: 使用 Quick Connect 完成认证');
    try {
      final response = await _post<Map<String, dynamic>>(
        '/Users/AuthenticateWithQuickConnect',
        data: {'Secret': secret},
        requireAuth: false,
      );

      if (response.data == null) return null;

      final result = JellyfinAuthResult.fromJson(response.data!);
      _accessToken = result.accessToken;
      _userId = result.userId;
      _serverId = result.serverId;
      _serverName = result.serverName;

      logger.i('JellyfinApi: Quick Connect 认证成功, userId=${result.userId}');
      return result;
    } on Exception catch (e) {
      logger.e('JellyfinApi: Quick Connect 认证失败', e);
      return null;
    }
  }

  // === 用户相关 API ===

  /// 获取所有用户（需要管理员权限或 API Key）
  Future<List<JellyfinUser>> getUsers() async {
    final response = await _get<List<dynamic>>('/Users');
    return (response.data ?? [])
        .map((e) => JellyfinUser.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 获取当前用户信息
  Future<JellyfinUser> getCurrentUser() async {
    final response = await _get<Map<String, dynamic>>('/Users/$_userId');
    return JellyfinUser.fromJson(response.data!);
  }

  // === 媒体库相关 API ===

  /// 获取媒体库列表
  Future<List<JellyfinLibrary>> getLibraries() async {
    logger.i('JellyfinApi: 获取媒体库列表');
    final response = await _get<Map<String, dynamic>>('/Users/$_userId/Views');
    final items = response.data?['Items'] as List? ?? [];
    return items
        .map((e) => JellyfinLibrary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 获取媒体库中的项目
  Future<JellyfinItemsResult> getItems({
    String? parentId,
    int startIndex = 0,
    int limit = 100,
    List<String>? includeItemTypes,
    String? sortBy,
    String? sortOrder,
    bool? recursive,
    String? searchTerm,
    List<String>? fields,
  }) async {
    logger.i('JellyfinApi: 获取项目列表, parentId=$parentId');

    final queryParams = <String, dynamic>{
      'StartIndex': startIndex,
      'Limit': limit,
    };

    if (parentId != null) queryParams['ParentId'] = parentId;
    if (includeItemTypes != null) {
      queryParams['IncludeItemTypes'] = includeItemTypes.join(',');
    }
    if (sortBy != null) queryParams['SortBy'] = sortBy;
    if (sortOrder != null) queryParams['SortOrder'] = sortOrder;
    if (recursive != null) queryParams['Recursive'] = recursive;
    if (searchTerm != null) queryParams['SearchTerm'] = searchTerm;

    // 默认请求的字段
    final requestFields =
        fields ??
        [
          'Overview',
          'Genres',
          'MediaStreams',
          'MediaSources',
          'ProviderIds',
          'PrimaryImageAspectRatio',
        ];
    queryParams['Fields'] = requestFields.join(',');

    final response = await _get<Map<String, dynamic>>(
      '/Users/$_userId/Items',
      queryParams: queryParams,
    );

    return JellyfinItemsResult.fromJson(response.data!);
  }

  /// 获取单个项目详情
  Future<JellyfinItem> getItem(String itemId) async {
    logger.i('JellyfinApi: 获取项目详情, itemId=$itemId');
    final response = await _get<Map<String, dynamic>>(
      '/Users/$_userId/Items/$itemId',
    );
    return JellyfinItem.fromJson(response.data!);
  }

  /// 获取剧集的季列表
  Future<JellyfinItemsResult> getSeasons(String seriesId) async {
    logger.i('JellyfinApi: 获取季列表, seriesId=$seriesId');
    final response = await _get<Map<String, dynamic>>(
      '/Shows/$seriesId/Seasons',
      queryParams: {
        'UserId': _userId,
        'Fields': 'Overview,PrimaryImageAspectRatio',
      },
    );
    return JellyfinItemsResult.fromJson(response.data!);
  }

  /// 获取季的集列表
  Future<JellyfinItemsResult> getEpisodes(
    String seriesId, {
    String? seasonId,
  }) async {
    logger.i('JellyfinApi: 获取集列表, seriesId=$seriesId, seasonId=$seasonId');
    final queryParams = <String, dynamic>{
      'UserId': _userId,
      'Fields':
          'Overview,MediaStreams,MediaSources,ProviderIds,PrimaryImageAspectRatio',
    };
    if (seasonId != null) queryParams['SeasonId'] = seasonId;

    final response = await _get<Map<String, dynamic>>(
      '/Shows/$seriesId/Episodes',
      queryParams: queryParams,
    );
    return JellyfinItemsResult.fromJson(response.data!);
  }

  /// 搜索媒体
  Future<JellyfinItemsResult> search(
    String query, {
    int limit = 20,
    List<String>? includeItemTypes,
  }) async {
    logger.i('JellyfinApi: 搜索, query=$query');
    return getItems(
      searchTerm: query,
      limit: limit,
      includeItemTypes: includeItemTypes,
      recursive: true,
    );
  }

  /// 获取最新添加的媒体
  Future<JellyfinItemsResult> getLatestMedia({
    String? parentId,
    int limit = 20,
    List<String>? includeItemTypes,
  }) async {
    logger.i('JellyfinApi: 获取最新媒体');
    final queryParams = <String, dynamic>{
      'Limit': limit,
      'Fields': 'Overview,PrimaryImageAspectRatio',
    };
    if (parentId != null) queryParams['ParentId'] = parentId;
    if (includeItemTypes != null) {
      queryParams['IncludeItemTypes'] = includeItemTypes.join(',');
    }

    final response = await _get<List<dynamic>>(
      '/Users/$_userId/Items/Latest',
      queryParams: queryParams,
    );

    final items = (response.data ?? [])
        .map((e) => JellyfinItem.fromJson(e as Map<String, dynamic>))
        .toList();

    return JellyfinItemsResult(items: items, totalRecordCount: items.length);
  }

  /// 获取继续观看列表
  Future<JellyfinItemsResult> getResumeItems({int limit = 20}) async {
    logger.i('JellyfinApi: 获取继续观看列表');
    return getItems(
      includeItemTypes: ['Movie', 'Episode'],
      sortBy: 'DatePlayed',
      sortOrder: 'Descending',
      limit: limit,
      recursive: true,
      fields: ['Overview', 'PrimaryImageAspectRatio', 'MediaStreams'],
    );
  }

  /// 获取下一集
  Future<JellyfinItem?> getNextUp({String? seriesId}) async {
    logger.i('JellyfinApi: 获取下一集, seriesId=$seriesId');
    final queryParams = <String, dynamic>{
      'UserId': _userId,
      'Limit': 1,
      'Fields': 'Overview,MediaStreams,PrimaryImageAspectRatio',
    };
    if (seriesId != null) queryParams['SeriesId'] = seriesId;

    final response = await _get<Map<String, dynamic>>(
      '/Shows/NextUp',
      queryParams: queryParams,
    );

    final items = response.data?['Items'] as List?;
    if (items == null || items.isEmpty) return null;

    return JellyfinItem.fromJson(items.first as Map<String, dynamic>);
  }

  // === 图片 URL 生成 ===

  /// 生成图片 URL
  String getImageUrl(
    String itemId,
    MediaImageType imageType, {
    int? maxWidth,
    int? maxHeight,
    String? tag,
  }) {
    final params = <String>[];
    if (maxWidth != null) params.add('maxWidth=$maxWidth');
    if (maxHeight != null) params.add('maxHeight=$maxHeight');
    if (tag != null) params.add('tag=$tag');

    final queryString = params.isEmpty ? '' : '?${params.join('&')}';
    return '$_baseUrl/Items/$itemId/Images/${imageType.toJellyfinType()}$queryString';
  }

  // === 播放相关 API ===

  /// 获取播放信息
  Future<JellyfinPlaybackInfo> getPlaybackInfo(String itemId) async {
    logger.i('JellyfinApi: 获取播放信息, itemId=$itemId');
    final response = await _post<Map<String, dynamic>>(
      '/Items/$itemId/PlaybackInfo',
      queryParams: {'UserId': _userId},
      data: {'DeviceProfile': _buildDeviceProfile()},
    );
    return JellyfinPlaybackInfo.fromJson(response.data!);
  }

  /// 构建设备配置文件（用于确定播放能力）
  Map<String, dynamic> _buildDeviceProfile() => {
    'MaxStreamingBitrate': 120000000, // 120 Mbps
    'MaxStaticBitrate': 100000000,
    'MusicStreamingTranscodingBitrate': 384000,
    'DirectPlayProfiles': [
      {'Container': 'mp4,mkv,webm,mov,avi,wmv', 'Type': 'Video'},
      {'Container': 'mp3,flac,aac,m4a,ogg,wav', 'Type': 'Audio'},
    ],
    'TranscodingProfiles': [
      {
        'Container': 'ts',
        'Type': 'Video',
        'VideoCodec': 'h264',
        'AudioCodec': 'aac',
        'Protocol': 'hls',
      },
    ],
    'ContainerProfiles': <Map<String, dynamic>>[],
    'CodecProfiles': <Map<String, dynamic>>[],
    'SubtitleProfiles': [
      {'Format': 'srt', 'Method': 'External'},
      {'Format': 'ass', 'Method': 'External'},
      {'Format': 'vtt', 'Method': 'External'},
    ],
  };

  /// 获取直接播放 URL
  String getDirectStreamUrl(String itemId, {String? mediaSourceId}) {
    final params = <String>['static=true', 'api_key=$_accessToken'];
    if (mediaSourceId != null) {
      params.add('MediaSourceId=$mediaSourceId');
    }
    return '$_baseUrl/Videos/$itemId/stream?${params.join('&')}';
  }

  /// 获取 HLS 转码 URL
  String getHlsStreamUrl(
    String itemId, {
    String? playSessionId,
    String? mediaSourceId,
    int? audioBitrate,
    int? videoBitrate,
  }) {
    final params = <String>[
      'api_key=$_accessToken',
      'PlaySessionId=${playSessionId ?? DateTime.now().millisecondsSinceEpoch}',
    ];
    if (mediaSourceId != null) params.add('MediaSourceId=$mediaSourceId');
    if (audioBitrate != null) {
      params.add('AudioBitrate=$audioBitrate');
    }
    if (videoBitrate != null) params.add('VideoBitrate=$videoBitrate');

    return '$_baseUrl/Videos/$itemId/master.m3u8?${params.join('&')}';
  }

  // === 播放状态报告 ===

  /// 报告播放开始
  Future<void> reportPlaybackStart({
    required String itemId,
    int? positionTicks,
    String? playSessionId,
    String? mediaSourceId,
  }) async {
    logger.i('JellyfinApi: 报告播放开始, itemId=$itemId');
    await _post<void>(
      '/Sessions/Playing',
      data: {
        'ItemId': itemId,
        'PositionTicks': positionTicks ?? 0,
        'PlaySessionId': playSessionId,
        'MediaSourceId': mediaSourceId,
        'CanSeek': true,
        'IsPaused': false,
        'IsMuted': false,
      },
    );
  }

  /// 报告播放进度
  Future<void> reportPlaybackProgress({
    required String itemId,
    required int positionTicks,
    String? playSessionId,
    bool isPaused = false,
  }) async {
    await _post<void>(
      '/Sessions/Playing/Progress',
      data: {
        'ItemId': itemId,
        'PositionTicks': positionTicks,
        'PlaySessionId': playSessionId,
        'IsPaused': isPaused,
        'CanSeek': true,
      },
    );
  }

  /// 报告播放停止
  Future<void> reportPlaybackStopped({
    required String itemId,
    int? positionTicks,
    String? playSessionId,
  }) async {
    logger.i('JellyfinApi: 报告播放停止, itemId=$itemId');
    await _post<void>(
      '/Sessions/Playing/Stopped',
      data: {
        'ItemId': itemId,
        'PositionTicks': positionTicks,
        'PlaySessionId': playSessionId,
      },
    );
  }

  // === 用户数据操作 ===

  /// 标记为已观看
  Future<void> markWatched(String itemId) async {
    logger.i('JellyfinApi: 标记已观看, itemId=$itemId');
    await _post<void>('/Users/$_userId/PlayedItems/$itemId');
  }

  /// 标记为未观看
  Future<void> markUnwatched(String itemId) async {
    logger.i('JellyfinApi: 标记未观看, itemId=$itemId');
    final url = '$_baseUrl/Users/$_userId/PlayedItems/$itemId';
    await _dio.delete<void>(url, options: Options(headers: _buildHeaders()));
  }

  /// 切换收藏状态
  Future<void> toggleFavorite(String itemId, bool isFavorite) async {
    logger.i('JellyfinApi: ${isFavorite ? '添加' : '移除'}收藏, itemId=$itemId');
    final url = '$_baseUrl/Users/$_userId/FavoriteItems/$itemId';
    if (isFavorite) {
      await _dio.post<void>(url, options: Options(headers: _buildHeaders()));
    } else {
      await _dio.delete<void>(url, options: Options(headers: _buildHeaders()));
    }
  }

  void dispose() {
    _dio.close();
  }
}
