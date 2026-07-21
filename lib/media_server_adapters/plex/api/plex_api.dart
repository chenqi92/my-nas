import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/media_server_adapters/plex/api/plex_models.dart';

/// Plex API 客户端
class PlexApi {
  PlexApi({
    required this.serverUrl,
    this.authToken,
    this.clientIdentifier,
    this.clientName = 'MyNas',
    this.clientVersion = '1.0.0',
    this.platform = 'iOS',
    this.device = 'iPhone',
    http.Client? client,
  }) {
    _client = client ?? http.Client();
    // 确保 URL 不以斜杠结尾
    if (serverUrl.endsWith('/')) {
      serverUrl = serverUrl.substring(0, serverUrl.length - 1);
    }
  }

  String serverUrl;
  String? authToken;
  String? clientIdentifier;
  String clientName;
  String clientVersion;
  String platform;
  String device;

  /// HTTP 客户端
  late final http.Client _client;

  /// 获取请求头
  Map<String, String> get _headers {
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'X-Plex-Client-Identifier': clientIdentifier ?? 'mynas-client',
      'X-Plex-Product': clientName,
      'X-Plex-Version': clientVersion,
      'X-Plex-Platform': platform,
      'X-Plex-Device': device,
    };

    if (authToken != null) {
      headers['X-Plex-Token'] = authToken!;
    }

    return headers;
  }

  // === Plex.tv API (PIN 认证) ===

  static const String _plexTvUrl = 'https://plex.tv';

  /// 发起 PIN 认证
  /// 返回 PlexPinInfo，包含 PIN 码和授权 URL
  Future<PlexPinInfo> initiatePin() async {
    final response = await _postPlexTv('/api/v2/pins', {'strong': 'true'});
    return PlexPinInfo.fromJson(response as Map<String, dynamic>);
  }

  /// 检查 PIN 认证状态
  /// 返回更新后的 PlexPinInfo，如果已授权则包含 authToken
  Future<PlexPinInfo> checkPin(int pinId) async {
    final response = await _getPlexTv('/api/v2/pins/$pinId');
    return PlexPinInfo.fromJson(response as Map<String, dynamic>);
  }

  /// 轮询等待 PIN 认证完成
  /// [pinId] - PIN ID
  /// [timeout] - 超时时间（默认 5 分钟）
  /// [interval] - 轮询间隔（默认 2 秒）
  /// 返回授权后的 authToken，超时则返回 null
  Future<String?> waitForPinAuth(
    int pinId, {
    Duration timeout = const Duration(minutes: 5),
    Duration interval = const Duration(seconds: 2),
  }) async {
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      final pin = await checkPin(pinId);

      if (pin.isAuthorized) {
        authToken = pin.authToken;
        return pin.authToken;
      }

      if (pin.isExpired) {
        return null;
      }

      await Future<void>.delayed(interval);
    }

    return null;
  }

  /// 获取用户信息
  Future<PlexUser> getUser() async {
    final response = await _getPlexTv('/api/v2/user');
    return PlexUser.fromJson(response as Map<String, dynamic>);
  }

  /// 获取用户的服务器列表
  Future<List<PlexServerResource>> getServers() async {
    final response = await _getPlexTv('/api/v2/resources', {
      'includeHttps': '1',
      'includeRelay': '1',
    });

    if (response is List) {
      return response
          .where((r) => (r as Map<String, dynamic>)['provides'] == 'server')
          .map((r) => PlexServerResource.fromJson(r as Map<String, dynamic>))
          .toList();
    }

    return [];
  }

  /// 使用 PIN 登录（便捷方法）
  /// 返回 (authUrl, `Future<authToken?>`)
  /// 调用方需要在浏览器中打开 authUrl，然后等待 Future 完成
  Future<({String authUrl, Future<String?> authTokenFuture})>
  loginWithPin() async {
    final pin = await initiatePin();
    final authUrl = pin.getAuthUrl(
      clientId: clientIdentifier ?? 'mynas-client',
      clientName: clientName,
    );

    return (authUrl: authUrl, authTokenFuture: waitForPinAuth(pin.id));
  }

  // === 服务器信息 ===

  /// 获取服务器信息
  Future<PlexServerInfo> getServerInfo() async {
    final response = await _get('/');
    return PlexServerInfo.fromJson(response as Map<String, dynamic>);
  }

  /// 验证令牌
  Future<bool> validateToken() async {
    try {
      await getServerInfo();
      return true;
    } catch (e) {
      return false;
    }
  }

  // === 媒体库 ===

  /// 获取媒体库列表
  Future<List<PlexLibrary>> getLibraries() async {
    final response = await _get('/library/sections');
    final mediaContainer =
        (response as Map<String, dynamic>)['MediaContainer']
            as Map<String, dynamic>;
    final directories = mediaContainer['Directory'] as List? ?? [];

    return directories
        .map((e) => PlexLibrary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 获取媒体库内容
  Future<PlexItemsResult> getLibraryContents(
    String libraryKey, {
    int start = 0,
    int size = 100,
    String? sort,
  }) async {
    final params = <String, String>{
      'X-Plex-Container-Start': start.toString(),
      'X-Plex-Container-Size': size.toString(),
    };
    if (sort != null) params['sort'] = sort;

    final response = await _get('/library/sections/$libraryKey/all', params);
    return PlexItemsResult.fromJson(response as Map<String, dynamic>);
  }

  /// 获取项目详情
  Future<PlexMediaItem?> getItem(String ratingKey) async {
    final response = await _get('/library/metadata/$ratingKey');
    final result = PlexItemsResult.fromJson(response as Map<String, dynamic>);
    return result.items.isNotEmpty ? result.items.first : null;
  }

  /// 获取项目子内容（季/集）
  Future<PlexItemsResult> getItemChildren(String ratingKey) async {
    final response = await _get('/library/metadata/$ratingKey/children');
    return PlexItemsResult.fromJson(response as Map<String, dynamic>);
  }

  /// 搜索
  Future<PlexItemsResult> search(String query, {int limit = 20}) async {
    final response = await _get('/search', {
      'query': query,
      'limit': limit.toString(),
    });
    return PlexItemsResult.fromJson(response as Map<String, dynamic>);
  }

  /// 获取最近添加
  Future<PlexItemsResult> getRecentlyAdded({
    String? libraryKey,
    int limit = 20,
  }) async {
    final path = libraryKey != null
        ? '/library/sections/$libraryKey/recentlyAdded'
        : '/library/recentlyAdded';

    final response = await _get(path, {
      'X-Plex-Container-Size': limit.toString(),
    });
    return PlexItemsResult.fromJson(response as Map<String, dynamic>);
  }

  /// 获取继续观看
  Future<PlexItemsResult> getOnDeck({int limit = 20}) async {
    final response = await _get('/library/onDeck', {
      'X-Plex-Container-Size': limit.toString(),
    });
    return PlexItemsResult.fromJson(response as Map<String, dynamic>);
  }

  // === 播放 ===

  /// 获取播放 URL
  String getPlayUrl(String partKey) {
    final params = authToken != null ? '?X-Plex-Token=$authToken' : '';
    return '$serverUrl$partKey$params';
  }

  /// 获取转码 URL
  String getTranscodeUrl(
    String ratingKey, {
    int? maxWidth,
    int? maxHeight,
    int? videoBitrate,
    String? videoCodec,
    String? audioCodec,
  }) {
    final params = <String, String>{
      'path': '/library/metadata/$ratingKey',
      'mediaIndex': '0',
      'partIndex': '0',
      'protocol': 'hls',
      'directPlay': '0',
      'directStream': '1',
    };

    if (maxWidth != null) params['maxWidth'] = maxWidth.toString();
    if (maxHeight != null) params['maxHeight'] = maxHeight.toString();
    if (videoBitrate != null) {
      params['videoBitrate'] = videoBitrate.toString();
    }
    if (videoCodec != null) params['videoCodec'] = videoCodec;
    if (audioCodec != null) params['audioCodec'] = audioCodec;
    if (authToken != null) params['X-Plex-Token'] = authToken!;

    final query = params.entries
        .map(
          (e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
        )
        .join('&');

    return '$serverUrl/video/:/transcode/universal/start.m3u8?$query';
  }

  /// 报告播放开始
  Future<void> reportPlaybackStart({
    required String ratingKey,
    required String sessionKey,
    int? offset,
  }) async {
    await _get('/:/timeline', {
      'ratingKey': ratingKey,
      'key': '/library/metadata/$ratingKey',
      'state': 'playing',
      'time': (offset ?? 0).toString(),
      'duration': '0',
    });
  }

  /// 报告播放进度
  Future<void> reportPlaybackProgress({
    required String ratingKey,
    required int time,
    required int duration,
    String state = 'playing', // playing, paused, stopped
  }) async {
    await _get('/:/timeline', {
      'ratingKey': ratingKey,
      'key': '/library/metadata/$ratingKey',
      'state': state,
      'time': time.toString(),
      'duration': duration.toString(),
    });
  }

  /// 报告播放停止
  Future<void> reportPlaybackStopped({
    required String ratingKey,
    required int time,
    required int duration,
  }) async {
    await _get('/:/timeline', {
      'ratingKey': ratingKey,
      'key': '/library/metadata/$ratingKey',
      'state': 'stopped',
      'time': time.toString(),
      'duration': duration.toString(),
    });
  }

  // === 用户数据 ===

  /// 标记已观看
  Future<void> markWatched(String ratingKey) async {
    await _get('/:/scrobble', {
      'key': ratingKey,
      'identifier': 'com.plexapp.plugins.library',
    });
  }

  /// 标记未观看
  Future<void> markUnwatched(String ratingKey) async {
    await _get('/:/unscrobble', {
      'key': ratingKey,
      'identifier': 'com.plexapp.plugins.library',
    });
  }

  /// 设置评分
  Future<void> setRating(String ratingKey, double rating) async {
    // Plex 评分是 0-10
    final plexRating = (rating * 2).round();
    await _put('/library/metadata/$ratingKey', {
      'rating': plexRating.toString(),
    });
  }

  // === 图片 ===

  /// 获取图片 URL
  String getImageUrl(String thumbPath, {int? width, int? height}) {
    if (thumbPath.isEmpty) return '';

    final params = <String, String>{};
    if (width != null) params['width'] = width.toString();
    if (height != null) params['height'] = height.toString();
    if (authToken != null) params['X-Plex-Token'] = authToken!;

    final query = params.isNotEmpty
        ? '?${params.entries.map((e) => '${e.key}=${e.value}').join('&')}'
        : '';

    // 如果路径已经是完整 URL，直接返回
    if (thumbPath.startsWith('http')) {
      return '$thumbPath$query';
    }

    return '$serverUrl/photo/:/transcode$query&url=${Uri.encodeComponent(thumbPath)}';
  }

  // === 私有方法 ===

  Future<dynamic> _get(String path, [Map<String, String>? params]) async {
    var url = '$serverUrl$path';
    if (params != null && params.isNotEmpty) {
      url +=
          '?${params.entries.map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}').join('&')}';
    }

    logger.d('PlexApi GET: $url');

    final response = await _client.get(Uri.parse(url), headers: _headers);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    }

    throw Exception('HTTP ${response.statusCode}: ${response.body}');
  }

  Future<void> _put(String path, Map<String, String> params) async {
    var url = '$serverUrl$path';
    if (params.isNotEmpty) {
      url +=
          '?${params.entries.map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}').join('&')}';
    }

    logger.d('PlexApi PUT: $url');

    final response = await _client.put(Uri.parse(url), headers: _headers);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
  }

  // === Plex.tv API 方法 ===

  /// GET 请求到 plex.tv
  Future<dynamic> _getPlexTv(String path, [Map<String, String>? params]) async {
    var url = '$_plexTvUrl$path';
    if (params != null && params.isNotEmpty) {
      url +=
          '?${params.entries.map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}').join('&')}';
    }

    logger.d('PlexApi GET (plex.tv): $url');

    final response = await _client.get(Uri.parse(url), headers: _headers);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    }

    throw Exception('HTTP ${response.statusCode}: ${response.body}');
  }

  /// POST 请求到 plex.tv
  Future<dynamic> _postPlexTv(String path, Map<String, String> body) async {
    final url = '$_plexTvUrl$path';

    logger.d('PlexApi POST (plex.tv): $url');

    final response = await _client.post(
      Uri.parse(url),
      headers: {
        ..._headers,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: body,
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    }

    throw Exception('HTTP ${response.statusCode}: ${response.body}');
  }

  void dispose() {
    _client.close();
  }
}
