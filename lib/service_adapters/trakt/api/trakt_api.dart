import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:my_nas/core/i18n/app_l10n.dart';

/// Trakt API 客户端
///
/// 支持 Trakt API v2
/// 文档: https://trakt.docs.apiary.io/
class TraktApi {
  TraktApi({
    required this.clientId,
    required this.clientSecret,
    this.redirectUri = defaultOobRedirectUri,
    this.accessToken,
    this.refreshToken,
    this.tokenExpiresAt,
  });

  static const String apiUrl = 'https://api.trakt.tv';
  static const String authUrl = 'https://trakt.tv';
  static const String apiVersion = '2';

  /// OOB (Out-of-Band) 重定向 URI - 用户手动输入授权码
  static const String defaultOobRedirectUri = 'urn:ietf:wg:oauth:2.0:oob';

  /// 深度链接重定向 URI - 自动回调应用
  static const String deepLinkRedirectUri = 'mynas://trakt/callback';

  final String clientId;
  final String clientSecret;
  final String redirectUri;
  String? accessToken;
  String? refreshToken;
  DateTime? tokenExpiresAt;

  http.Client? _client;

  /// 获取 HTTP 客户端
  http.Client get client {
    _client ??= http.Client();
    return _client!;
  }

  /// 是否已认证
  bool get isAuthenticated =>
      accessToken != null && accessToken!.isNotEmpty && !isTokenExpired;

  /// Token 是否已过期
  bool get isTokenExpired {
    if (tokenExpiresAt == null) return false;
    return DateTime.now().isAfter(tokenExpiresAt!);
  }

  /// Token 是否需要刷新（提前 1 小时）
  bool get needsTokenRefresh {
    if (tokenExpiresAt == null) return false;
    final expiresIn = tokenExpiresAt!.difference(DateTime.now());
    return expiresIn.inHours < 1;
  }

  /// 获取 OAuth 授权 URL
  String getAuthorizationUrl() => '$authUrl/oauth/authorize'
        '?response_type=code'
        '&client_id=$clientId'
        '&redirect_uri=$redirectUri';

  // ==================== Device Code Flow ====================

  /// 请求设备码（Device Code Flow 第一步）
  ///
  /// 返回设备码信息，用户需要访问 verification_url 并输入 user_code
  Future<TraktDeviceCode> requestDeviceCode() async {
    final url = Uri.parse('$apiUrl/oauth/device/code');

    try {
      final response = await client.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'client_id': clientId}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return TraktDeviceCode.fromJson(data);
      }

      throw TraktApiException(appL10n.traktApiRequestDeviceCodeFailed(response.statusCode));
    } on SocketException catch (e) {
      throw TraktApiException(appL10n.traktApiConnectionFailed(e.message));
    } on http.ClientException catch (e) {
      throw TraktApiException(appL10n.traktApiNetworkError(e.message));
    }
  }

  /// 轮询设备授权状态（Device Code Flow 第二步）
  ///
  /// 返回值：
  /// - TraktTokenResponse: 授权成功
  /// - null: 用户尚未完成授权，需要继续轮询
  /// - 抛出异常: 授权失败或过期
  Future<TraktTokenResponse?> pollDeviceToken(String deviceCode) async {
    final url = Uri.parse('$apiUrl/oauth/device/token');

    try {
      final response = await client.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'code': deviceCode,
          'client_id': clientId,
          'client_secret': clientSecret,
        }),
      );

      switch (response.statusCode) {
        case 200:
          // 授权成功
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final tokenResponse = TraktTokenResponse.fromJson(data);

          // 更新本地 token
          accessToken = tokenResponse.accessToken;
          refreshToken = tokenResponse.refreshToken;
          tokenExpiresAt = DateTime.now().add(
            Duration(seconds: tokenResponse.expiresIn),
          );

          return tokenResponse;

        case 400:
          // 用户尚未授权，继续轮询
          return null;

        case 404:
          throw TraktApiException(appL10n.traktApiInvalidDeviceCode);

        case 409:
          throw TraktApiException(appL10n.traktApiDeviceCodeAlreadyUsed);

        case 410:
          throw TraktApiException(appL10n.traktApiDeviceCodeExpired);

        case 418:
          throw TraktApiException(appL10n.traktApiUserAuthorizationDenied);

        case 429:
          throw TraktApiException(appL10n.traktApiPollingTooFrequent);

        default:
          throw TraktApiException(appL10n.traktApiPollAuthorizationFailed(response.statusCode));
      }
    } on SocketException catch (e) {
      throw TraktApiException(appL10n.traktApiConnectionFailed(e.message));
    } on http.ClientException catch (e) {
      throw TraktApiException(appL10n.traktApiNetworkError(e.message));
    }
  }

  /// 使用授权码获取 Token
  Future<TraktTokenResponse> exchangeCodeForToken(String code) async {
    final url = Uri.parse('$apiUrl/oauth/token');

    try {
      final response = await client.post(
        url,
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'code': code,
          'client_id': clientId,
          'client_secret': clientSecret,
          'redirect_uri': redirectUri,
          'grant_type': 'authorization_code',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final tokenResponse = TraktTokenResponse.fromJson(data);

        // 更新本地 token
        accessToken = tokenResponse.accessToken;
        refreshToken = tokenResponse.refreshToken;
        tokenExpiresAt = DateTime.now().add(
          Duration(seconds: tokenResponse.expiresIn),
        );

        return tokenResponse;
      }

      throw TraktApiException(appL10n.traktApiGetTokenFailed(response.statusCode));
    } on SocketException catch (e) {
      throw TraktApiException(appL10n.traktApiConnectionFailed(e.message));
    } on http.ClientException catch (e) {
      throw TraktApiException(appL10n.traktApiNetworkError(e.message));
    }
  }

  /// 刷新 Token
  Future<TraktTokenResponse> refreshAccessToken() async {
    if (refreshToken == null) {
      throw TraktApiException(appL10n.traktApiNoRefreshToken);
    }

    final url = Uri.parse('$apiUrl/oauth/token');

    try {
      final response = await client.post(
        url,
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'refresh_token': refreshToken,
          'client_id': clientId,
          'client_secret': clientSecret,
          'redirect_uri': redirectUri,
          'grant_type': 'refresh_token',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final tokenResponse = TraktTokenResponse.fromJson(data);

        // 更新本地 token
        accessToken = tokenResponse.accessToken;
        refreshToken = tokenResponse.refreshToken;
        tokenExpiresAt = DateTime.now().add(
          Duration(seconds: tokenResponse.expiresIn),
        );

        return tokenResponse;
      }

      throw TraktApiException(appL10n.traktApiRefreshTokenFailed(response.statusCode));
    } on SocketException catch (e) {
      throw TraktApiException(appL10n.traktApiConnectionFailed(e.message));
    } on http.ClientException catch (e) {
      throw TraktApiException(appL10n.traktApiNetworkError(e.message));
    }
  }

  /// 撤销 Token
  Future<void> revokeToken() async {
    if (accessToken == null) return;

    final url = Uri.parse('$apiUrl/oauth/revoke');

    try {
      await client.post(
        url,
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'token': accessToken,
          'client_id': clientId,
          'client_secret': clientSecret,
        }),
      );
    } finally {
      accessToken = null;
      refreshToken = null;
      tokenExpiresAt = null;
    }
  }

  /// 获取用户设置
  Future<TraktUserSettings> getUserSettings() async {
    final response = await _makeAuthenticatedRequest('GET', '/users/settings');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return TraktUserSettings.fromJson(data);
  }

  /// 获取用户统计数据
  Future<TraktUserStats> getUserStats() async {
    final response = await _makeAuthenticatedRequest('GET', '/users/me/stats');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return TraktUserStats.fromJson(data);
  }

  /// 获取观看历史
  Future<List<TraktHistoryItem>> getWatchedHistory({
    String type = 'movies,shows',
    int page = 1,
    int limit = 20,
  }) async {
    final response = await _makeAuthenticatedRequest(
      'GET',
      '/users/me/history/$type',
      queryParams: {
        'page': page.toString(),
        'limit': limit.toString(),
      },
    );

    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .map((e) => TraktHistoryItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 获取待看列表
  Future<List<TraktWatchlistItem>> getWatchlist({
    String type = 'movies,shows',
    String sort = 'added',
    int page = 1,
    int limit = 20,
  }) async {
    final response = await _makeAuthenticatedRequest(
      'GET',
      '/users/me/watchlist/$type/$sort',
      queryParams: {
        'page': page.toString(),
        'limit': limit.toString(),
      },
    );

    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .map((e) => TraktWatchlistItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 获取收藏列表
  Future<List<TraktCollectionItem>> getCollection({
    String type = 'movies',
  }) async {
    final response = await _makeAuthenticatedRequest(
      'GET',
      '/users/me/collection/$type',
    );

    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .map((e) => TraktCollectionItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 获取用户评分
  Future<List<TraktRatingItem>> getRatings({
    String type = 'movies,shows',
  }) async {
    final response = await _makeAuthenticatedRequest(
      'GET',
      '/users/me/ratings/$type',
    );

    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .map((e) => TraktRatingItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 添加到观看历史
  Future<void> addToHistory(List<TraktMediaItem> items) async {
    await _makeAuthenticatedRequest(
      'POST',
      '/sync/history',
      body: {
        'movies': items
            .where((i) => i.type == 'movie')
            .map((i) => i.toJson())
            .toList(),
        'shows': items
            .where((i) => i.type == 'show')
            .map((i) => i.toJson())
            .toList(),
        'episodes': items
            .where((i) => i.type == 'episode')
            .map((i) => i.toJson())
            .toList(),
      },
    );
  }

  /// 添加到待看列表
  Future<void> addToWatchlist(List<TraktMediaItem> items) async {
    await _makeAuthenticatedRequest(
      'POST',
      '/sync/watchlist',
      body: {
        'movies': items
            .where((i) => i.type == 'movie')
            .map((i) => i.toJson())
            .toList(),
        'shows': items
            .where((i) => i.type == 'show')
            .map((i) => i.toJson())
            .toList(),
      },
    );
  }

  /// 添加评分
  Future<void> addRating(TraktMediaItem item, int rating) async {
    await _makeAuthenticatedRequest(
      'POST',
      '/sync/ratings',
      body: {
        '${item.type}s': [
          {
            ...item.toJson(),
            'rating': rating,
          }
        ],
      },
    );
  }

  /// 搜索媒体
  Future<List<TraktSearchResult>> search(String query, {
    String type = 'movie,show',
    int page = 1,
    int limit = 10,
  }) async {
    final response = await _makeRequest(
      'GET',
      '/search/$type',
      queryParams: {
        'query': query,
        'page': page.toString(),
        'limit': limit.toString(),
      },
    );

    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .map((e) => TraktSearchResult.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ==================== Scrobble API ====================

  /// Scrobble 开始播放
  ///
  /// 当用户开始播放媒体时调用
  Future<TraktScrobbleResponse?> scrobbleStart(TraktScrobbleRequest request) =>
      _scrobble('start', request);

  /// Scrobble 暂停播放
  ///
  /// 当用户暂停播放时调用
  Future<TraktScrobbleResponse?> scrobblePause(TraktScrobbleRequest request) =>
      _scrobble('pause', request);

  /// Scrobble 停止播放
  ///
  /// 当用户停止播放或播放完成时调用
  /// 如果进度 >= 80%，Trakt 会自动标记为已观看
  Future<TraktScrobbleResponse?> scrobbleStop(TraktScrobbleRequest request) =>
      _scrobble('stop', request);

  /// 执行 Scrobble 请求
  Future<TraktScrobbleResponse?> _scrobble(String action, TraktScrobbleRequest request) async {
    try {
      final response = await _makeAuthenticatedRequest(
        'POST',
        '/scrobble/$action',
        body: request.toJson(),
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return TraktScrobbleResponse.fromJson(data);
      }

      // 404 表示未找到媒体（但不是错误，可能是用户的本地视频）
      if (response.statusCode == 404) {
        return null;
      }

      return null;
    } on TraktApiException {
      // Scrobble 失败不应该影响播放
      rethrow;
    }
  }

  // ==================== Playback Sync API ====================

  /// 获取播放进度（用于恢复播放）
  ///
  /// 返回所有未完成的播放进度
  Future<List<TraktPlaybackItem>> getPlaybackProgress({
    String type = 'movies,episodes',
    int? startAt,
    int? endAt,
  }) async {
    final queryParams = <String, String>{};
    if (startAt != null) queryParams['start_at'] = startAt.toString();
    if (endAt != null) queryParams['end_at'] = endAt.toString();

    final response = await _makeAuthenticatedRequest(
      'GET',
      '/sync/playback/$type',
      queryParams: queryParams.isNotEmpty ? queryParams : null,
    );

    final data = jsonDecode(response.body) as List<dynamic>;
    return data
        .map((e) => TraktPlaybackItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 删除播放进度
  ///
  /// [playbackId] 从 getPlaybackProgress 返回的 id
  Future<void> deletePlaybackProgress(int playbackId) async {
    await _makeAuthenticatedRequest(
      'DELETE',
      '/sync/playback/$playbackId',
    );
  }

  /// 从观看历史中移除
  Future<void> removeFromHistory(List<TraktMediaItem> items) async {
    await _makeAuthenticatedRequest(
      'POST',
      '/sync/history/remove',
      body: {
        'movies': items
            .where((i) => i.type == 'movie')
            .map((i) => i.toJson())
            .toList(),
        'shows': items
            .where((i) => i.type == 'show')
            .map((i) => i.toJson())
            .toList(),
        'episodes': items
            .where((i) => i.type == 'episode')
            .map((i) => i.toJson())
            .toList(),
      },
    );
  }

  /// 从待看列表中移除
  Future<void> removeFromWatchlist(List<TraktMediaItem> items) async {
    await _makeAuthenticatedRequest(
      'POST',
      '/sync/watchlist/remove',
      body: {
        'movies': items
            .where((i) => i.type == 'movie')
            .map((i) => i.toJson())
            .toList(),
        'shows': items
            .where((i) => i.type == 'show')
            .map((i) => i.toJson())
            .toList(),
      },
    );
  }

  /// 通过 ID 查找媒体
  Future<TraktSearchResult?> lookupById({
    String? imdbId,
    int? tmdbId,
    int? tvdbId,
    String type = 'movie,show,episode',
  }) async {
    String? idType;
    String? idValue;

    if (imdbId != null) {
      idType = 'imdb';
      idValue = imdbId;
    } else if (tmdbId != null) {
      idType = 'tmdb';
      idValue = tmdbId.toString();
    } else if (tvdbId != null) {
      idType = 'tvdb';
      idValue = tvdbId.toString();
    }

    if (idType == null || idValue == null) {
      return null;
    }

    final response = await _makeRequest(
      'GET',
      '/search/$idType/$idValue',
      queryParams: {'type': type},
    );

    final data = jsonDecode(response.body) as List<dynamic>;
    if (data.isEmpty) return null;

    return TraktSearchResult.fromJson(data.first as Map<String, dynamic>);
  }

  /// 发起认证请求
  Future<http.Response> _makeAuthenticatedRequest(String method,
      String path, {
        Map<String, String>? queryParams,
        Map<String, dynamic>? body,
      }) async {
    // 检查 token 是否需要刷新
    if (needsTokenRefresh && refreshToken != null) {
      await refreshAccessToken();
    }

    if (!isAuthenticated) {
      throw TraktApiException(appL10n.traktApiNotAuthenticated);
    }

    return _makeRequest(
      method,
      path,
      queryParams: queryParams,
      body: body,
      authenticated: true,
    );
  }

  /// 发起请求
  Future<http.Response> _makeRequest(String method,
      String path, {
        Map<String, String>? queryParams,
        Map<String, dynamic>? body,
        bool authenticated = false,
      }) async {
    var url = Uri.parse('$apiUrl$path');
    if (queryParams != null && queryParams.isNotEmpty) {
      url = url.replace(queryParameters: queryParams);
    }

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'trakt-api-version': apiVersion,
      'trakt-api-key': clientId,
    };

    if (authenticated && accessToken != null) {
      headers['Authorization'] = 'Bearer $accessToken';
    }

    http.Response response;

    try {
      if (method == 'GET') {
        response = await client.get(url, headers: headers);
      } else if (method == 'POST') {
        response = await client.post(
          url,
          headers: headers,
          body: body != null ? jsonEncode(body) : null,
        );
      } else if (method == 'DELETE') {
        response = await client.delete(url, headers: headers);
      } else {
        throw TraktApiException(appL10n.traktApiUnsupportedHttpMethod(method));
      }

      if (response.statusCode == 401) {
        accessToken = null;
        throw TraktApiException(appL10n.traktApiAuthorizationExpired);
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw TraktApiException(
          appL10n.traktApiRequestFailed(response.statusCode, response.reasonPhrase ?? 'unknown'),
        );
      }

      return response;
    } on SocketException catch (e) {
      throw TraktApiException(appL10n.traktApiConnectionFailed(e.message));
    } on http.ClientException catch (e) {
      throw TraktApiException(appL10n.traktApiNetworkError(e.message));
    }
  }

  /// 释放资源
  void dispose() {
    _client?.close();
    _client = null;
  }
}

/// Trakt API 异常
class TraktApiException implements Exception {
  const TraktApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Token 响应
class TraktTokenResponse {
  const TraktTokenResponse({
    required this.accessToken,
    required this.tokenType,
    required this.expiresIn,
    required this.refreshToken,
    required this.scope,
    required this.createdAt,
  });

  factory TraktTokenResponse.fromJson(Map<String, dynamic> json) => TraktTokenResponse(
      accessToken: json['access_token'] as String,
      tokenType: json['token_type'] as String,
      expiresIn: json['expires_in'] as int,
      refreshToken: json['refresh_token'] as String,
      scope: json['scope'] as String,
      createdAt: json['created_at'] as int,
    );

  final String accessToken;
  final String tokenType;
  final int expiresIn;
  final String refreshToken;
  final String scope;
  final int createdAt;
}

/// 用户设置
class TraktUserSettings {
  const TraktUserSettings({
    required this.username,
    this.name,
    this.vip,
    this.avatarUrl,
  });

  factory TraktUserSettings.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>?;
    final images = user?['images'] as Map<String, dynamic>?;
    final avatar = images?['avatar'] as Map<String, dynamic>?;

    return TraktUserSettings(
      username: user?['username'] as String? ?? '',
      name: user?['name'] as String?,
      vip: user?['vip'] as bool?,
      avatarUrl: avatar?['full'] as String?,
    );
  }

  final String username;
  final String? name;
  final bool? vip;
  final String? avatarUrl;
}

/// 用户统计数据
class TraktUserStats {
  const TraktUserStats({
    this.moviesWatched = 0,
    this.moviesCollected = 0,
    this.moviesMinutes = 0,
    this.showsWatched = 0,
    this.showsCollected = 0,
    this.episodesWatched = 0,
    this.episodesMinutes = 0,
    this.ratingsTotal = 0,
  });

  factory TraktUserStats.fromJson(Map<String, dynamic> json) {
    final movies = json['movies'] as Map<String, dynamic>? ?? {};
    final shows = json['shows'] as Map<String, dynamic>? ?? {};
    final episodes = json['episodes'] as Map<String, dynamic>? ?? {};
    final ratings = json['ratings'] as Map<String, dynamic>? ?? {};

    return TraktUserStats(
      moviesWatched: movies['watched'] as int? ?? 0,
      moviesCollected: movies['collected'] as int? ?? 0,
      moviesMinutes: movies['minutes'] as int? ?? 0,
      showsWatched: shows['watched'] as int? ?? 0,
      showsCollected: shows['collected'] as int? ?? 0,
      episodesWatched: episodes['watched'] as int? ?? 0,
      episodesMinutes: episodes['minutes'] as int? ?? 0,
      ratingsTotal: ratings['total'] as int? ?? 0,
    );
  }

  final int moviesWatched;
  final int moviesCollected;
  final int moviesMinutes;
  final int showsWatched;
  final int showsCollected;
  final int episodesWatched;
  final int episodesMinutes;
  final int ratingsTotal;
}

/// 观看历史项
class TraktHistoryItem {
  const TraktHistoryItem({
    required this.id,
    required this.watchedAt,
    required this.action,
    required this.type,
    this.movie,
    this.show,
    this.episode,
  });

  factory TraktHistoryItem.fromJson(Map<String, dynamic> json) => TraktHistoryItem(
      id: json['id'] as int,
      watchedAt: DateTime.parse(json['watched_at'] as String),
      action: json['action'] as String,
      type: json['type'] as String,
      movie: json['movie'] != null
          ? TraktMovie.fromJson(json['movie'] as Map<String, dynamic>)
          : null,
      show: json['show'] != null
          ? TraktShow.fromJson(json['show'] as Map<String, dynamic>)
          : null,
      episode: json['episode'] != null
          ? TraktEpisode.fromJson(json['episode'] as Map<String, dynamic>)
          : null,
    );

  final int id;
  final DateTime watchedAt;
  final String action;
  final String type;
  final TraktMovie? movie;
  final TraktShow? show;
  final TraktEpisode? episode;
}

/// 待看列表项
class TraktWatchlistItem {
  const TraktWatchlistItem({
    required this.id,
    required this.listedAt,
    required this.type,
    this.movie,
    this.show,
  });

  factory TraktWatchlistItem.fromJson(Map<String, dynamic> json) => TraktWatchlistItem(
      id: json['id'] as int,
      listedAt: DateTime.parse(json['listed_at'] as String),
      type: json['type'] as String,
      movie: json['movie'] != null
          ? TraktMovie.fromJson(json['movie'] as Map<String, dynamic>)
          : null,
      show: json['show'] != null
          ? TraktShow.fromJson(json['show'] as Map<String, dynamic>)
          : null,
    );

  final int id;
  final DateTime listedAt;
  final String type;
  final TraktMovie? movie;
  final TraktShow? show;
}

/// 收藏项
class TraktCollectionItem {
  const TraktCollectionItem({
    required this.collectedAt,
    this.movie,
    this.show,
  });

  factory TraktCollectionItem.fromJson(Map<String, dynamic> json) => TraktCollectionItem(
      collectedAt: DateTime.parse(json['collected_at'] as String),
      movie: json['movie'] != null
          ? TraktMovie.fromJson(json['movie'] as Map<String, dynamic>)
          : null,
      show: json['show'] != null
          ? TraktShow.fromJson(json['show'] as Map<String, dynamic>)
          : null,
    );

  final DateTime collectedAt;
  final TraktMovie? movie;
  final TraktShow? show;
}

/// 评分项
class TraktRatingItem {
  const TraktRatingItem({
    required this.rating,
    required this.ratedAt,
    required this.type,
    this.movie,
    this.show,
  });

  factory TraktRatingItem.fromJson(Map<String, dynamic> json) => TraktRatingItem(
      rating: json['rating'] as int,
      ratedAt: DateTime.parse(json['rated_at'] as String),
      type: json['type'] as String,
      movie: json['movie'] != null
          ? TraktMovie.fromJson(json['movie'] as Map<String, dynamic>)
          : null,
      show: json['show'] != null
          ? TraktShow.fromJson(json['show'] as Map<String, dynamic>)
          : null,
    );

  final int rating;
  final DateTime ratedAt;
  final String type;
  final TraktMovie? movie;
  final TraktShow? show;
}

/// 搜索结果
class TraktSearchResult {
  const TraktSearchResult({
    required this.type,
    required this.score,
    this.movie,
    this.show,
  });

  factory TraktSearchResult.fromJson(Map<String, dynamic> json) => TraktSearchResult(
      type: json['type'] as String,
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      movie: json['movie'] != null
          ? TraktMovie.fromJson(json['movie'] as Map<String, dynamic>)
          : null,
      show: json['show'] != null
          ? TraktShow.fromJson(json['show'] as Map<String, dynamic>)
          : null,
    );

  final String type;
  final double score;
  final TraktMovie? movie;
  final TraktShow? show;
}

/// 电影
class TraktMovie {
  const TraktMovie({
    required this.title,
    required this.year,
    required this.ids,
  });

  factory TraktMovie.fromJson(Map<String, dynamic> json) => TraktMovie(
      title: json['title'] as String? ?? '',
      year: json['year'] as int?,
      ids: TraktIds.fromJson(json['ids'] as Map<String, dynamic>? ?? {}),
    );

  final String title;
  final int? year;
  final TraktIds ids;
}

/// 剧集
class TraktShow {
  const TraktShow({
    required this.title,
    required this.year,
    required this.ids,
  });

  factory TraktShow.fromJson(Map<String, dynamic> json) => TraktShow(
      title: json['title'] as String? ?? '',
      year: json['year'] as int?,
      ids: TraktIds.fromJson(json['ids'] as Map<String, dynamic>? ?? {}),
    );

  final String title;
  final int? year;
  final TraktIds ids;
}

/// 单集
class TraktEpisode {
  const TraktEpisode({
    required this.season,
    required this.number,
    required this.title,
    required this.ids,
  });

  factory TraktEpisode.fromJson(Map<String, dynamic> json) => TraktEpisode(
      season: json['season'] as int? ?? 0,
      number: json['number'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      ids: TraktIds.fromJson(json['ids'] as Map<String, dynamic>? ?? {}),
    );

  final int season;
  final int number;
  final String title;
  final TraktIds ids;
}

/// Trakt IDs
class TraktIds {
  const TraktIds({
    this.trakt,
    this.slug,
    this.imdb,
    this.tmdb,
    this.tvdb,
  });

  factory TraktIds.fromJson(Map<String, dynamic> json) => TraktIds(
      trakt: json['trakt'] as int?,
      slug: json['slug'] as String?,
      imdb: json['imdb'] as String?,
      tmdb: json['tmdb'] as int?,
      tvdb: json['tvdb'] as int?,
    );

  final int? trakt;
  final String? slug;
  final String? imdb;
  final int? tmdb;
  final int? tvdb;
}

/// 设备码响应（Device Code Flow）
class TraktDeviceCode {
  const TraktDeviceCode({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUrl,
    required this.expiresIn,
    required this.interval,
  });

  factory TraktDeviceCode.fromJson(Map<String, dynamic> json) => TraktDeviceCode(
        deviceCode: json['device_code'] as String,
        userCode: json['user_code'] as String,
        verificationUrl: json['verification_url'] as String,
        expiresIn: json['expires_in'] as int,
        interval: json['interval'] as int,
      );

  /// 设备码（用于轮询）
  final String deviceCode;

  /// 用户码（用户需要输入这个）
  final String userCode;

  /// 验证 URL（用户需要访问这个网址）
  final String verificationUrl;

  /// 过期时间（秒）
  final int expiresIn;

  /// 轮询间隔（秒）
  final int interval;
}

/// 媒体项（用于同步操作）
class TraktMediaItem {
  const TraktMediaItem({
    required this.type,
    this.traktId,
    this.imdbId,
    this.tmdbId,
    this.tvdbId,
    this.season,
    this.episode,
    this.watchedAt,
    this.title,
    this.year,
  });

  final String type; // 'movie', 'show', 'episode'
  final int? traktId;
  final String? imdbId;
  final int? tmdbId;
  final int? tvdbId;
  final int? season;
  final int? episode;
  final DateTime? watchedAt;
  final String? title;
  final int? year;

  Map<String, dynamic> toJson() {
    final ids = <String, dynamic>{};
    if (traktId != null) ids['trakt'] = traktId;
    if (imdbId != null) ids['imdb'] = imdbId;
    if (tmdbId != null) ids['tmdb'] = tmdbId;
    if (tvdbId != null) ids['tvdb'] = tvdbId;

    final result = <String, dynamic>{
      'ids': ids,
    };

    if (title != null) result['title'] = title;
    if (year != null) result['year'] = year;

    if (watchedAt != null) {
      result['watched_at'] = watchedAt!.toUtc().toIso8601String();
    }

    return result;
  }
}

/// Scrobble 动作类型
enum TraktScrobbleAction {
  start,
  pause,
  stop,
}

/// Scrobble 请求
class TraktScrobbleRequest {
  const TraktScrobbleRequest({
    required this.media,
    required this.progress,
    this.appVersion,
    this.appDate,
  });

  final TraktMediaItem media;
  final double progress; // 0.0 - 100.0
  final String? appVersion;
  final String? appDate;

  Map<String, dynamic> toJson() {
    final result = <String, dynamic>{
      'progress': progress,
    };

    // 根据媒体类型添加对应字段
    if (media.type == 'movie') {
      result['movie'] = media.toJson();
    } else if (media.type == 'episode') {
      result['show'] = {
        'ids': {
          if (media.traktId != null) 'trakt': media.traktId,
          if (media.imdbId != null) 'imdb': media.imdbId,
          if (media.tmdbId != null) 'tmdb': media.tmdbId,
          if (media.tvdbId != null) 'tvdb': media.tvdbId,
        },
        if (media.title != null) 'title': media.title,
        if (media.year != null) 'year': media.year,
      };
      result['episode'] = {
        'season': media.season ?? 1,
        'number': media.episode ?? 1,
      };
    }

    if (appVersion != null) result['app_version'] = appVersion;
    if (appDate != null) result['app_date'] = appDate;

    return result;
  }
}

/// Scrobble 响应
class TraktScrobbleResponse {
  const TraktScrobbleResponse({
    required this.id,
    required this.action,
    required this.progress,
    this.sharing,
    this.movie,
    this.show,
    this.episode,
  });

  factory TraktScrobbleResponse.fromJson(Map<String, dynamic> json) =>
      TraktScrobbleResponse(
        id: json['id'] as int? ?? 0,
        action: json['action'] as String? ?? '',
        progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
        sharing: json['sharing'] as Map<String, dynamic>?,
        movie: json['movie'] != null
            ? TraktMovie.fromJson(json['movie'] as Map<String, dynamic>)
            : null,
        show: json['show'] != null
            ? TraktShow.fromJson(json['show'] as Map<String, dynamic>)
            : null,
        episode: json['episode'] != null
            ? TraktEpisode.fromJson(json['episode'] as Map<String, dynamic>)
            : null,
      );

  final int id;
  final String action;
  final double progress;
  final Map<String, dynamic>? sharing;
  final TraktMovie? movie;
  final TraktShow? show;
  final TraktEpisode? episode;
}

/// 播放进度项（用于恢复播放）
class TraktPlaybackItem {
  const TraktPlaybackItem({
    required this.id,
    required this.progress,
    required this.pausedAt,
    required this.type,
    this.movie,
    this.show,
    this.episode,
  });

  factory TraktPlaybackItem.fromJson(Map<String, dynamic> json) =>
      TraktPlaybackItem(
        id: json['id'] as int,
        progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
        pausedAt: DateTime.parse(json['paused_at'] as String),
        type: json['type'] as String,
        movie: json['movie'] != null
            ? TraktMovie.fromJson(json['movie'] as Map<String, dynamic>)
            : null,
        show: json['show'] != null
            ? TraktShow.fromJson(json['show'] as Map<String, dynamic>)
            : null,
        episode: json['episode'] != null
            ? TraktEpisode.fromJson(json['episode'] as Map<String, dynamic>)
            : null,
      );

  final int id;
  final double progress; // 0.0 - 100.0
  final DateTime pausedAt;
  final String type; // 'movie' or 'episode'
  final TraktMovie? movie;
  final TraktShow? show;
  final TraktEpisode? episode;

  /// 获取 TMDB ID
  int? get tmdbId {
    if (type == 'movie') return movie?.ids.tmdb;
    return show?.ids.tmdb;
  }

  /// 获取 IMDB ID
  String? get imdbId {
    if (type == 'movie') return movie?.ids.imdb;
    return show?.ids.imdb;
  }

  /// 获取剧集信息
  (int season, int episode)? get episodeInfo {
    if (type != 'episode' || episode == null) return null;
    return (episode!.season, episode!.number);
  }
}
