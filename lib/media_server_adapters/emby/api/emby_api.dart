import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/media_server_adapters/jellyfin/api/jellyfin_models.dart';

/// Emby API 客户端
///
/// Emby API 与 Jellyfin 几乎相同，但有一些细微差异：
/// - 认证头格式略有不同
/// - 部分端点路径可能不同
/// - Quick Connect 实现不同
class EmbyApi {
  EmbyApi({
    required this.serverUrl,
    this.accessToken,
    this.userId,
    this.deviceId,
    this.deviceName,
    this.clientName = 'MyNas',
    this.clientVersion = '1.0.0',
    http.Client? client,
  }) {
    _client = client ?? http.Client();
    // 确保 URL 不以斜杠结尾
    if (serverUrl.endsWith('/')) {
      serverUrl = serverUrl.substring(0, serverUrl.length - 1);
    }
  }

  String serverUrl;
  String? accessToken;
  String? userId;
  String? deviceId;
  String? deviceName;
  String clientName;
  String clientVersion;

  /// HTTP 客户端
  late final http.Client _client;

  /// 获取认证头
  Map<String, String> get _headers {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    // Emby 使用 X-Emby-Authorization 头
    final authParts = <String>[
      'MediaBrowser Client="$clientName"',
      'Device="${deviceName ?? Platform.operatingSystem}"',
      'DeviceId="${deviceId ?? 'unknown'}"',
      'Version="$clientVersion"',
    ];
    if (accessToken != null) {
      authParts.add('Token="$accessToken"');
    }

    headers['X-Emby-Authorization'] = authParts.join(', ');

    return headers;
  }

  // === 认证相关 ===

  /// 获取服务器公开信息
  Future<JellyfinServerInfo> getPublicSystemInfo() async {
    final response = await _get('/System/Info/Public');
    return JellyfinServerInfo.fromJson(response as Map<String, dynamic>);
  }

  /// 用户名密码登录
  Future<JellyfinAuthResult> login(String username, String password) async {
    final response = await _post(
      '/Users/AuthenticateByName',
      body: {'Username': username, 'Pw': password},
    );

    final result = JellyfinAuthResult.fromJson(
      response as Map<String, dynamic>,
    );
    accessToken = result.accessToken;
    userId = result.userId;
    return result;
  }

  /// 使用 API Key 登录
  Future<JellyfinAuthResult> loginWithApiKey(String apiKey) async {
    accessToken = apiKey;

    // 获取当前用户信息
    final response = await _get('/Users/Me');
    final user = response as Map<String, dynamic>;

    userId = user['Id'] as String?;
    return JellyfinAuthResult(
      userId: userId ?? '',
      accessToken: apiKey,
      serverId: user['ServerId'] as String? ?? '',
      username: user['Name'] as String?,
    );
  }

  /// 获取公开用户列表
  Future<List<JellyfinUser>> getPublicUsers() async {
    final response = await _get('/Users/Public');
    return (response as List)
        .map((e) => JellyfinUser.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // === 媒体库相关 ===

  /// 获取媒体库列表
  Future<List<JellyfinLibrary>> getLibraries() async {
    final response = await _get('/Users/$userId/Views');
    final items = (response as Map<String, dynamic>)['Items'] as List;
    return items
        .map((e) => JellyfinLibrary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 获取项目列表
  Future<JellyfinItemsResult> getItems({
    String? parentId,
    String? includeItemTypes,
    int startIndex = 0,
    int limit = 100,
    String? sortBy,
    String? sortOrder,
    String? fields,
  }) async {
    final params = <String, String>{
      'StartIndex': startIndex.toString(),
      'Limit': limit.toString(),
      'Recursive': 'true',
      'Fields':
          fields ??
          'Overview,Genres,DateCreated,MediaStreams,ProviderIds,MediaSources',
    };
    if (parentId != null) params['ParentId'] = parentId;
    if (includeItemTypes != null) params['IncludeItemTypes'] = includeItemTypes;
    if (sortBy != null) params['SortBy'] = sortBy;
    if (sortOrder != null) params['SortOrder'] = sortOrder;

    final response = await _get('/Users/$userId/Items', params);
    return JellyfinItemsResult.fromJson(response as Map<String, dynamic>);
  }

  /// 获取单个项目详情
  Future<JellyfinItem> getItem(String itemId) async {
    final response = await _get('/Users/$userId/Items/$itemId', {
      'Fields': 'MediaSources',
    });
    return JellyfinItem.fromJson(response as Map<String, dynamic>);
  }

  /// 搜索
  Future<JellyfinItemsResult> search(
    String query, {
    int limit = 20,
    String? includeItemTypes,
  }) async {
    final params = <String, String>{
      'SearchTerm': query,
      'Limit': limit.toString(),
      'Fields': 'Overview,Genres,ProviderIds',
      'Recursive': 'true',
    };
    if (includeItemTypes != null) params['IncludeItemTypes'] = includeItemTypes;

    final response = await _get('/Users/$userId/Items', params);
    return JellyfinItemsResult.fromJson(response as Map<String, dynamic>);
  }

  /// 获取最新项目
  Future<JellyfinItemsResult> getLatestItems({
    String? parentId,
    int limit = 20,
    String? includeItemTypes,
  }) async {
    final params = <String, String>{
      'Limit': limit.toString(),
      'Fields': 'Overview,Genres,ProviderIds,DateCreated',
    };
    if (parentId != null) params['ParentId'] = parentId;
    if (includeItemTypes != null) params['IncludeItemTypes'] = includeItemTypes;

    final response = await _get('/Users/$userId/Items/Latest', params);
    // Latest 端点返回数组而不是包含 Items 的对象
    final items = response as List;
    return JellyfinItemsResult(
      items: items
          .map((e) => JellyfinItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      totalRecordCount: items.length,
    );
  }

  /// 获取继续观看列表
  Future<JellyfinItemsResult> getResumeItems({int limit = 20}) async {
    final response = await _get('/Users/$userId/Items/Resume', {
      'Limit': limit.toString(),
      'Fields': 'Overview,Genres,ProviderIds',
      'MediaTypes': 'Video',
    });
    return JellyfinItemsResult.fromJson(response as Map<String, dynamic>);
  }

  /// 获取下一集
  Future<JellyfinItem?> getNextUp({String? seriesId}) async {
    final params = <String, String>{
      'Limit': '1',
      'Fields': 'Overview,Genres,ProviderIds',
    };
    if (seriesId != null) params['SeriesId'] = seriesId;

    final response = await _get('/Shows/NextUp', params);
    final items = (response as Map<String, dynamic>)['Items'] as List;
    if (items.isEmpty) return null;
    return JellyfinItem.fromJson(items.first as Map<String, dynamic>);
  }

  // === 播放相关 ===

  /// 获取播放信息
  Future<JellyfinPlaybackInfo> getPlaybackInfo(String itemId) async {
    final response = await _post(
      '/Items/$itemId/PlaybackInfo',
      body: {'UserId': userId, 'DeviceProfile': _getDeviceProfile()},
    );
    return JellyfinPlaybackInfo.fromJson(response as Map<String, dynamic>);
  }

  /// 获取直接流 URL
  String getDirectStreamUrl(
    String itemId, {
    String? mediaSourceId,
    bool isAudio = false,
  }) {
    final params = <String, String>{
      'Static': 'true',
      'api_key': accessToken ?? '',
    };
    if (mediaSourceId != null) params['MediaSourceId'] = mediaSourceId;

    final query = params.entries.map((e) => '${e.key}=${e.value}').join('&');
    final mediaPath = isAudio ? 'Audio' : 'Videos';
    return '$serverUrl/$mediaPath/$itemId/stream?$query';
  }

  /// 报告播放开始
  Future<void> reportPlaybackStart({
    required String itemId,
    int? positionTicks,
    String? playSessionId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {
    await _post(
      '/Sessions/Playing',
      body: {
        'ItemId': itemId,
        'PositionTicks': ?positionTicks,
        'PlaySessionId': ?playSessionId,
        'AudioStreamIndex': ?audioStreamIndex,
        'SubtitleStreamIndex': ?subtitleStreamIndex,
      },
    );
  }

  /// 报告播放进度
  Future<void> reportPlaybackProgress({
    required String itemId,
    int? positionTicks,
    String? playSessionId,
    bool isPaused = false,
  }) async {
    await _post(
      '/Sessions/Playing/Progress',
      body: {
        'ItemId': itemId,
        'PositionTicks': ?positionTicks,
        'PlaySessionId': ?playSessionId,
        'IsPaused': isPaused,
      },
    );
  }

  /// 报告播放停止
  Future<void> reportPlaybackStopped({
    required String itemId,
    int? positionTicks,
    String? playSessionId,
  }) async {
    await _post(
      '/Sessions/Playing/Stopped',
      body: {
        'ItemId': itemId,
        'PositionTicks': ?positionTicks,
        'PlaySessionId': ?playSessionId,
      },
    );
  }

  // === 用户数据 ===

  /// 标记已观看
  Future<void> markWatched(String itemId) async {
    await _post('/Users/$userId/PlayedItems/$itemId');
  }

  /// 标记未观看
  Future<void> markUnwatched(String itemId) async {
    await _delete('/Users/$userId/PlayedItems/$itemId');
  }

  /// 切换收藏状态
  Future<bool> toggleFavorite(String itemId) async {
    // 获取当前状态
    final item = await getItem(itemId);
    final isFavorite = item.userData?.isFavorite ?? false;

    if (isFavorite) {
      await _delete('/Users/$userId/FavoriteItems/$itemId');
      return false;
    } else {
      await _post('/Users/$userId/FavoriteItems/$itemId');
      return true;
    }
  }

  // === 图片 ===

  /// 获取图片 URL
  String getImageUrl(
    String itemId,
    String imageType, {
    int? maxWidth,
    int? maxHeight,
    String? tag,
  }) {
    final params = <String, String>{};
    if (maxWidth != null) params['maxWidth'] = maxWidth.toString();
    if (maxHeight != null) params['maxHeight'] = maxHeight.toString();
    if (tag != null) params['tag'] = tag;
    if (accessToken != null) params['api_key'] = accessToken!;

    final query = params.isNotEmpty
        ? '?${params.entries.map((e) => '${e.key}=${e.value}').join('&')}'
        : '';

    return '$serverUrl/Items/$itemId/Images/$imageType$query';
  }

  // === 私有方法 ===

  Future<dynamic> _get(String path, [Map<String, String>? params]) async {
    var url = '$serverUrl$path';
    if (params != null && params.isNotEmpty) {
      url +=
          '?${params.entries.map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}').join('&')}';
    }

    logger.d('EmbyApi GET: $url');

    final response = await _client.get(Uri.parse(url), headers: _headers);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    }

    throw Exception('HTTP ${response.statusCode}: ${response.body}');
  }

  Future<dynamic> _post(String path, {Map<String, dynamic>? body}) async {
    final url = '$serverUrl$path';
    logger.d('EmbyApi POST: $url');

    final response = await _client.post(
      Uri.parse(url),
      headers: _headers,
      body: body != null ? jsonEncode(body) : null,
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    }

    throw Exception('HTTP ${response.statusCode}: ${response.body}');
  }

  Future<void> _delete(String path) async {
    final url = '$serverUrl$path';
    logger.d('EmbyApi DELETE: $url');

    final response = await _client.delete(Uri.parse(url), headers: _headers);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
  }

  /// 获取设备配置（用于转码决策）
  Map<String, dynamic> _getDeviceProfile() => {
    'MaxStreamingBitrate': 120000000,
    'MaxStaticBitrate': 100000000,
    'MusicStreamingTranscodingBitrate': 384000,
    'DirectPlayProfiles': [
      {
        'Container': 'mp4,m4v,mov,mkv,webm',
        'Type': 'Video',
        'VideoCodec': 'h264,hevc,vp9',
        'AudioCodec': 'aac,mp3,ac3,eac3,flac,opus',
      },
    ],
    'TranscodingProfiles': [
      {
        'Container': 'mp4',
        'Type': 'Video',
        'VideoCodec': 'h264',
        'AudioCodec': 'aac',
        'Protocol': 'hls',
      },
    ],
  };

  void dispose() {
    _client.close();
  }
}
