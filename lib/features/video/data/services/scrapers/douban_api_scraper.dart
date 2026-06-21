import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/domain/entities/scraper_result.dart';
import 'package:my_nas/features/video/domain/entities/scraper_source.dart';
import 'package:my_nas/features/video/domain/interfaces/media_scraper.dart';

/// 豆瓣第三方 API 刮削器
///
/// 支持的第三方 API 格式：
/// - NeoDB API (api.neodb.social)
/// - 其他兼容 API
class DoubanApiScraper implements MediaScraper {
  DoubanApiScraper({required this.apiUrl, this.apiKey});

  /// API 基础地址
  final String apiUrl;

  /// API Key（可选，部分服务需要）
  final String? apiKey;

  static const Duration _requestTimeout = Duration(seconds: 15);

  @override
  ScraperType get type => ScraperType.doubanApi;

  @override
  bool get isConfigured => apiUrl.isNotEmpty;

  /// 获取请求头
  Map<String, String> get _headers {
    final headers = <String, String>{
      'Accept': 'application/json',
      'User-Agent': 'MyNAS/1.0',
    };
    if (apiKey != null && apiKey!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $apiKey';
    }
    return headers;
  }

  /// 带超时的 HTTP GET 请求
  Future<http.Response> _httpGet(Uri uri) => http
      .get(uri, headers: _headers)
      .timeout(
        _requestTimeout,
        onTimeout: () => throw TimeoutException(appL10n.scraperDoubanApiTimeoutError(uri)),
      );

  @override
  Future<bool> testConnection() async {
    if (!isConfigured) return false;

    try {
      // 尝试搜索一个常见电影来测试连接
      final result = await searchMovies('霸王别姬');
      return result.isNotEmpty;
    } on Exception catch (e) {
      logger.w('豆瓣 API 连接测试失败', e);
      return false;
    }
  }

  @override
  Future<ScraperSearchResult> searchMovies(
    String query, {
    int page = 1,
    String? language,
    int? year,
  }) async {
    if (!isConfigured) {
      return ScraperSearchResult.empty(ScraperType.doubanApi);
    }

    try {
      // 构建搜索 URL
      // 支持多种 API 格式
      final baseUrl = apiUrl.endsWith('/')
          ? apiUrl.substring(0, apiUrl.length - 1)
          : apiUrl;

      final params = <String, String>{
        'q': query,
        'page': page.toString(),
        'type': 'movie',
      };
      if (year != null) {
        params['year'] = year.toString();
      }

      final uri = Uri.parse('$baseUrl/search').replace(queryParameters: params);
      final response = await _httpGet(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return _parseSearchResult(data, isMovie: true);
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw ScraperAuthException(
          appL10n.scraperDoubanApiAuthError(response.statusCode),
          source: ScraperType.doubanApi,
        );
      } else if (response.statusCode == 429) {
        throw ScraperRateLimitException(
          appL10n.scraperDoubanApiRateLimitError,
          source: ScraperType.doubanApi,
        );
      } else {
        logger.e('豆瓣 API 搜索电影失败: ${response.statusCode}');
        return ScraperSearchResult.empty(ScraperType.doubanApi);
      }
    } on ScraperException {
      rethrow;
    } on Exception catch (e) {
      logger.e('豆瓣 API 搜索电影异常', e);
      return ScraperSearchResult.empty(ScraperType.doubanApi);
    }
  }

  @override
  Future<ScraperSearchResult> searchTvShows(
    String query, {
    int page = 1,
    String? language,
    int? year,
  }) async {
    if (!isConfigured) {
      return ScraperSearchResult.empty(ScraperType.doubanApi);
    }

    try {
      final baseUrl = apiUrl.endsWith('/')
          ? apiUrl.substring(0, apiUrl.length - 1)
          : apiUrl;

      final params = <String, String>{
        'q': query,
        'page': page.toString(),
        'type': 'tv',
      };
      if (year != null) {
        params['year'] = year.toString();
      }

      final uri = Uri.parse('$baseUrl/search').replace(queryParameters: params);
      final response = await _httpGet(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return _parseSearchResult(data, isMovie: false);
      } else {
        logger.e('豆瓣 API 搜索电视剧失败: ${response.statusCode}');
        return ScraperSearchResult.empty(ScraperType.doubanApi);
      }
    } on ScraperException {
      rethrow;
    } on Exception catch (e) {
      logger.e('豆瓣 API 搜索电视剧异常', e);
      return ScraperSearchResult.empty(ScraperType.doubanApi);
    }
  }

  @override
  Future<ScraperMovieDetail?> getMovieDetail(
    String externalId, {
    String? language,
  }) async {
    if (!isConfigured) return null;

    try {
      final baseUrl = apiUrl.endsWith('/')
          ? apiUrl.substring(0, apiUrl.length - 1)
          : apiUrl;
      final uri = Uri.parse('$baseUrl/movie/$externalId');
      final response = await _httpGet(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return _parseMovieDetail(data);
      } else {
        logger.e('豆瓣 API 获取电影详情失败: ${response.statusCode}');
        return null;
      }
    } on Exception catch (e) {
      logger.e('豆瓣 API 获取电影详情异常', e);
      return null;
    }
  }

  @override
  Future<ScraperTvDetail?> getTvDetail(
    String externalId, {
    String? language,
  }) async {
    if (!isConfigured) return null;

    try {
      final baseUrl = apiUrl.endsWith('/')
          ? apiUrl.substring(0, apiUrl.length - 1)
          : apiUrl;
      final uri = Uri.parse('$baseUrl/tv/$externalId');
      final response = await _httpGet(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return _parseTvDetail(data);
      } else {
        logger.e('豆瓣 API 获取电视剧详情失败: ${response.statusCode}');
        return null;
      }
    } on Exception catch (e) {
      logger.e('豆瓣 API 获取电视剧详情异常', e);
      return null;
    }
  }

  @override
  Future<ScraperEpisodeDetail?> getEpisodeDetail(
    String tvId,
    int seasonNumber,
    int episodeNumber, {
    String? language,
  }) async => null;

  @override
  Future<ScraperSeasonDetail?> getSeasonDetail(
    String tvId,
    int seasonNumber, {
    String? language,
  }) async => null; // 豆瓣通常不提供详细的季信息

  @override
  void dispose() {
    // No resources to dispose
  }

  // === 解析方法 ===

  ScraperSearchResult _parseSearchResult(
    dynamic data, {
    required bool isMovie,
  }) {
    // 支持多种 API 响应格式
    List<dynamic> results;
    var page = 1;
    var totalPages = 1;
    var totalResults = 0;

    if (data is Map<String, dynamic>) {
      // 格式1: { "data": [...], "page": 1, "total_pages": 10 }
      results = (data['data'] ??
          data['results'] ??
          data['subjects'] ??
          <dynamic>[]) as List<dynamic>;
      page = data['page'] as int? ?? 1;
      totalPages =
          data['total_pages'] as int? ?? data['totalPages'] as int? ?? 1;
      totalResults =
          data['total'] as int? ??
          data['total_results'] as int? ??
          results.length;
    } else if (data is List) {
      // 格式2: 直接返回数组
      results = data;
    } else {
      results = <dynamic>[];
    }

    final items = results.map((item) {
      final map = item as Map<String, dynamic>;
      return ScraperMediaItem(
        externalId: _extractId(map),
        source: ScraperType.doubanApi,
        title: (map['title'] ?? map['name'] ?? '') as String,
        originalTitle:
            map['original_title'] as String? ?? map['originalTitle'] as String?,
        overview: map['summary'] as String? ?? map['intro'] as String?,
        posterUrl: _extractPosterUrl(map),
        year: _extractYear(map),
        rating: _extractRating(map),
        isMovie: isMovie,
        genres: _extractGenres(map),
      );
    }).toList();

    return ScraperSearchResult(
      items: items,
      source: ScraperType.doubanApi,
      page: page,
      totalPages: totalPages,
      totalResults: totalResults,
    );
  }

  ScraperMovieDetail _parseMovieDetail(Map<String, dynamic> data) =>
      ScraperMovieDetail(
        externalId: _extractId(data),
        source: ScraperType.doubanApi,
        title: (data['title'] ?? data['name'] ?? '') as String,
        originalTitle:
            data['original_title'] as String? ??
            data['originalTitle'] as String?,
        overview: data['summary'] as String? ?? data['intro'] as String?,
        posterUrl: _extractPosterUrl(data),
        year: _extractYear(data),
        rating: _extractRating(data),
        runtime: data['duration'] as int? ?? data['runtime'] as int?,
        genres: _extractGenres(data),
        director: _extractDirector(data),
        cast: _extractCast(data),
      );

  ScraperTvDetail _parseTvDetail(Map<String, dynamic> data) => ScraperTvDetail(
    externalId: _extractId(data),
    source: ScraperType.doubanApi,
    title: (data['title'] ?? data['name'] ?? '') as String,
    originalTitle:
        data['original_title'] as String? ?? data['originalTitle'] as String?,
    overview: data['summary'] as String? ?? data['intro'] as String?,
    posterUrl: _extractPosterUrl(data),
    year: _extractYear(data),
    rating: _extractRating(data),
    genres: _extractGenres(data),
    cast: _extractCast(data),
    numberOfSeasons: data['seasons_count'] as int?,
    numberOfEpisodes: data['episodes_count'] as int?,
  );

  String _extractId(Map<String, dynamic> data) {
    // 尝试多种 ID 字段
    final id = data['id'] ?? data['douban_id'] ?? data['doubanId'] ?? '';
    return id.toString();
  }

  String? _extractPosterUrl(Map<String, dynamic> data) =>
      data['poster'] as String? ??
      data['cover'] as String? ??
      data['image'] as String? ??
      (data['images'] as Map<String, dynamic>?)?['large']
          as String?; // 尝试多种海报字段

  int? _extractYear(Map<String, dynamic> data) {
    final year = data['year'];
    if (year is int) return year;
    if (year is String) return int.tryParse(year);

    // 尝试从日期字段提取
    final date = data['release_date'] as String? ?? data['pubdate'] as String?;
    if (date != null && date.length >= 4) {
      return int.tryParse(date.substring(0, 4));
    }
    return null;
  }

  double? _extractRating(Map<String, dynamic> data) {
    // 尝试多种评分格式
    final rating = data['rating'];
    if (rating is num) return rating.toDouble();
    if (rating is Map<String, dynamic>) {
      final value = rating['value'] ?? rating['average'];
      if (value is num) return value.toDouble();
    }
    return null;
  }

  List<String>? _extractGenres(Map<String, dynamic> data) {
    final genres = data['genres'] ?? data['genre'];
    if (genres is List) {
      return genres
          .map((g) {
            if (g is String) return g;
            if (g is Map<String, dynamic>) return g['name'] as String? ?? '';
            return '';
          })
          .where((g) => g.isNotEmpty)
          .toList();
    }
    if (genres is String) {
      return genres.split('/').map((g) => g.trim()).toList();
    }
    return null;
  }

  String? _extractDirector(Map<String, dynamic> data) {
    final directors = data['directors'] ?? data['director'];
    if (directors is List && directors.isNotEmpty) {
      final first = directors.first;
      if (first is String) return first;
      if (first is Map<String, dynamic>) return first['name'] as String?;
    }
    if (directors is String) return directors;
    return null;
  }

  List<String>? _extractCast(Map<String, dynamic> data) {
    final cast = data['casts'] ?? data['cast'] ?? data['actors'];
    if (cast is List) {
      return cast
          .take(10)
          .map((c) {
            if (c is String) return c;
            if (c is Map<String, dynamic>) return c['name'] as String? ?? '';
            return '';
          })
          .where((c) => c.isNotEmpty)
          .toList();
    }
    return null;
  }
}
