import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/network/resolved_http_client.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/domain/entities/scraper_result.dart';
import 'package:my_nas/features/video/domain/entities/scraper_source.dart';
import 'package:my_nas/features/video/domain/interfaces/media_scraper.dart';

/// TMDB 刮削器实现
class TmdbScraper implements MediaScraper {
  TmdbScraper({required this.apiKey, String? apiUrl, String? imageProxy})
      : _baseUrl = apiUrl ?? _defaultApiUrl,
        _imageBaseUrl = imageProxy ?? _defaultImageUrl;

  /// API Key
  final String apiKey;

  /// API 基础 URL
  final String _baseUrl;

  /// 图片基础 URL
  final String _imageBaseUrl;

  /// 默认 API URL
  static const String _defaultApiUrl = 'https://api.themoviedb.org/3';

  /// 默认图片 URL
  static const String _defaultImageUrl = 'https://image.tmdb.org/t/p';

  static const Duration _requestTimeout = Duration(seconds: 15);

  @override
  ScraperType get type => ScraperType.tmdb;

  @override
  bool get isConfigured => apiKey.isNotEmpty;

  /// 获取图片完整 URL（使用默认图片服务器）
  static String getImageUrl(String? path, {String size = 'w500'}) {
    if (path == null || path.isEmpty) return '';
    return '$_defaultImageUrl/$size$path';
  }

  /// 获取图片完整 URL（使用实例配置的图片服务器）
  String getImageUrlWithProxy(String? path, {String size = 'w500'}) {
    if (path == null || path.isEmpty) return '';
    return '$_imageBaseUrl/$size$path';
  }

  /// 带超时的 HTTP GET 请求
  Future<http.Response> _httpGet(Uri uri) =>
      ResolvedHttpClient.get(uri).timeout(
        _requestTimeout,
        onTimeout: () =>
            throw TimeoutException(appL10n.tmdbScraperRequestTimeout(uri)),
      );

  @override
  Future<bool> testConnection() async {
    if (!isConfigured) return false;

    try {
      final uri = Uri.parse(
        '$_baseUrl/configuration',
      ).replace(queryParameters: {'api_key': apiKey});
      final response = await _httpGet(uri);
      return response.statusCode == 200;
    } on Exception catch (e) {
      logger.w('TMDB 连接测试失败', e);
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
      return ScraperSearchResult.empty(ScraperType.tmdb);
    }

    try {
      final params = {
        'api_key': apiKey,
        'query': query,
        'page': page.toString(),
        'language': language ?? 'zh-CN',
        'include_adult': 'false',
      };
      if (year != null) {
        params['year'] = year.toString();
      }

      final uri = Uri.parse(
        '$_baseUrl/search/movie',
      ).replace(queryParameters: params);
      final response = await _httpGet(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return _parseSearchResult(data, isMovie: true);
      } else if (response.statusCode == 401) {
        throw ScraperAuthException(
          appL10n.tmdbScraperAuthenticationFailed,
          source: ScraperType.tmdb,
        );
      } else if (response.statusCode == 429) {
        throw ScraperRateLimitException(
          appL10n.tmdbScraperRateLimited,
          source: ScraperType.tmdb,
        );
      } else {
        logger.e('TMDB搜索电影失败: ${response.statusCode}');
        return ScraperSearchResult.empty(ScraperType.tmdb);
      }
    } on ScraperException {
      rethrow;
    } on Exception catch (e) {
      logger.e('TMDB搜索电影异常', e);
      return ScraperSearchResult.empty(ScraperType.tmdb);
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
      return ScraperSearchResult.empty(ScraperType.tmdb);
    }

    try {
      final params = {
        'api_key': apiKey,
        'query': query,
        'page': page.toString(),
        'language': language ?? 'zh-CN',
      };
      if (year != null) {
        params['first_air_date_year'] = year.toString();
      }

      final uri = Uri.parse(
        '$_baseUrl/search/tv',
      ).replace(queryParameters: params);
      final response = await _httpGet(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return _parseSearchResult(data, isMovie: false);
      } else if (response.statusCode == 401) {
        throw ScraperAuthException(
          appL10n.tmdbScraperAuthenticationFailed,
          source: ScraperType.tmdb,
        );
      } else if (response.statusCode == 429) {
        throw ScraperRateLimitException(
          appL10n.tmdbScraperRateLimited,
          source: ScraperType.tmdb,
        );
      } else {
        logger.e('TMDB搜索电视剧失败: ${response.statusCode}');
        return ScraperSearchResult.empty(ScraperType.tmdb);
      }
    } on ScraperException {
      rethrow;
    } on Exception catch (e) {
      logger.e('TMDB搜索电视剧异常', e);
      return ScraperSearchResult.empty(ScraperType.tmdb);
    }
  }

  @override
  Future<ScraperMovieDetail?> getMovieDetail(
    String externalId, {
    String? language,
  }) async {
    if (!isConfigured) return null;

    try {
      final params = {
        'api_key': apiKey,
        'language': language ?? 'zh-CN',
        'append_to_response': 'credits,videos,images',
      };

      final uri = Uri.parse(
        '$_baseUrl/movie/$externalId',
      ).replace(queryParameters: params);
      final response = await _httpGet(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return _parseMovieDetail(data);
      } else {
        logger.e('TMDB获取电影详情失败: ${response.statusCode}');
        return null;
      }
    } on Exception catch (e) {
      logger.e('TMDB获取电影详情异常', e);
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
      final params = {
        'api_key': apiKey,
        'language': language ?? 'zh-CN',
        'append_to_response': 'credits,videos,images',
      };

      final uri = Uri.parse(
        '$_baseUrl/tv/$externalId',
      ).replace(queryParameters: params);
      final response = await _httpGet(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return _parseTvDetail(data);
      } else {
        logger.e('TMDB获取电视剧详情失败: ${response.statusCode}');
        return null;
      }
    } on Exception catch (e) {
      logger.e('TMDB获取电视剧详情异常', e);
      return null;
    }
  }

  @override
  Future<ScraperEpisodeDetail?> getEpisodeDetail(
    String tvId,
    int seasonNumber,
    int episodeNumber, {
    String? language,
  }) async {
    final seasonDetail = await getSeasonDetail(
      tvId,
      seasonNumber,
      language: language,
    );
    return seasonDetail?.getEpisode(episodeNumber);
  }

  @override
  Future<ScraperSeasonDetail?> getSeasonDetail(
    String tvId,
    int seasonNumber, {
    String? language,
  }) async {
    if (!isConfigured) return null;

    try {
      final params = {'api_key': apiKey, 'language': language ?? 'zh-CN'};

      final uri = Uri.parse(
        '$_baseUrl/tv/$tvId/season/$seasonNumber',
      ).replace(queryParameters: params);
      final response = await _httpGet(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return _parseSeasonDetail(data, tvId);
      } else {
        logger.e('TMDB获取季详情失败: ${response.statusCode}');
        return null;
      }
    } on Exception catch (e) {
      logger.e('TMDB获取季详情异常', e);
      return null;
    }
  }

  @override
  void dispose() {
    // No resources to dispose
  }

  // === 解析方法 ===

  ScraperSearchResult _parseSearchResult(
    Map<String, dynamic> json, {
    required bool isMovie,
  }) {
    final results = (json['results'] as List?)?.map((e) {
          final item = e as Map<String, dynamic>;
          return ScraperMediaItem(
            externalId: (item['id'] as int).toString(),
            source: ScraperType.tmdb,
            title: (isMovie ? item['title'] : item['name']) as String? ?? '',
            originalTitle: (isMovie
                ? item['original_title']
                : item['original_name']) as String?,
            overview: item['overview'] as String?,
            posterUrl: getImageUrlWithProxy(item['poster_path'] as String?),
            backdropUrl: getImageUrlWithProxy(
              item['backdrop_path'] as String?,
              size: 'w780',
            ),
            year: _parseYear(
              isMovie
                  ? item['release_date'] as String?
                  : item['first_air_date'] as String?,
            ),
            rating: (item['vote_average'] as num?)?.toDouble(),
            isMovie: isMovie,
            voteCount: item['vote_count'] as int?,
            genres: null, // 搜索结果中只有 genre_ids
          );
        }).toList() ??
        [];

    return ScraperSearchResult(
      items: results,
      source: ScraperType.tmdb,
      page: json['page'] as int? ?? 1,
      totalPages: json['total_pages'] as int? ?? 1,
      totalResults: json['total_results'] as int? ?? 0,
    );
  }

  ScraperMovieDetail _parseMovieDetail(Map<String, dynamic> json) {
    final credits = json['credits'] as Map<String, dynamic>?;
    final collectionData =
        json['belongs_to_collection'] as Map<String, dynamic>?;

    // 解析导演
    String? director;
    final crew = credits?['crew'] as List?;
    if (crew != null) {
      for (final c in crew) {
        final crewMember = c as Map<String, dynamic>;
        if (crewMember['job'] == 'Director') {
          director = crewMember['name'] as String?;
          break;
        }
      }
    }

    // 解析演员
    final castList = (credits?['cast'] as List?)
        ?.take(10)
        .map((c) => (c as Map<String, dynamic>)['name'] as String)
        .toList();

    // 解析类型
    final genres = (json['genres'] as List?)
        ?.map((g) => (g as Map<String, dynamic>)['name'] as String)
        .toList();

    // 解析制片国家/地区
    final countries = (json['production_countries'] as List?)
        ?.map((c) => (c as Map<String, dynamic>)['name'] as String)
        .where((name) => name.isNotEmpty)
        .toList();

    return ScraperMovieDetail(
      externalId: (json['id'] as int).toString(),
      source: ScraperType.tmdb,
      title: json['title'] as String? ?? '',
      originalTitle: json['original_title'] as String?,
      overview: json['overview'] as String?,
      posterUrl: getImageUrlWithProxy(json['poster_path'] as String?),
      backdropUrl: getImageUrlWithProxy(
        json['backdrop_path'] as String?,
        size: 'original',
      ),
      year: _parseYear(json['release_date'] as String?),
      rating: (json['vote_average'] as num?)?.toDouble(),
      voteCount: json['vote_count'] as int?,
      runtime: json['runtime'] as int?,
      genres: genres,
      countries: countries,
      director: director,
      cast: castList,
      tagline: json['tagline'] as String?,
      status: json['status'] as String?,
      collectionId: collectionData?['id']?.toString(),
      collectionName: collectionData?['name'] as String?,
      collectionPosterUrl: getImageUrlWithProxy(
        collectionData?['poster_path'] as String?,
      ),
      collectionBackdropUrl: getImageUrlWithProxy(
        collectionData?['backdrop_path'] as String?,
        size: 'w780',
      ),
      imdbId: json['imdb_id'] as String?,
    );
  }

  ScraperTvDetail _parseTvDetail(Map<String, dynamic> json) {
    final credits = json['credits'] as Map<String, dynamic>?;

    // 解析演员
    final castList = (credits?['cast'] as List?)
        ?.take(10)
        .map((c) => (c as Map<String, dynamic>)['name'] as String)
        .toList();

    // 解析类型
    final genres = (json['genres'] as List?)
        ?.map((g) => (g as Map<String, dynamic>)['name'] as String)
        .toList();

    // 解析制片国家/地区
    // TV 详情使用 production_countries，如果为空则使用 origin_country
    var countries = (json['production_countries'] as List?)
        ?.map((c) => (c as Map<String, dynamic>)['name'] as String)
        .where((name) => name.isNotEmpty)
        .toList();
    // 如果 production_countries 为空，使用 origin_country（ISO 代码列表）
    if (countries == null || countries.isEmpty) {
      final originCountries = json['origin_country'] as List?;
      if (originCountries != null && originCountries.isNotEmpty) {
        countries = originCountries
            .map((c) => _countryCodeToName(c as String))
            .where((name) => name.isNotEmpty)
            .toList();
      }
    }

    // 解析季列表
    final seasons = (json['seasons'] as List?)?.map((s) {
          final season = s as Map<String, dynamic>;
          return ScraperSeasonInfo(
            seasonNumber: season['season_number'] as int? ?? 0,
            name: season['name'] as String?,
            overview: season['overview'] as String?,
            posterUrl: getImageUrlWithProxy(season['poster_path'] as String?),
            airDate: season['air_date'] as String?,
            episodeCount: season['episode_count'] as int?,
          );
        }).toList() ??
        [];

    // 获取单集时长
    final episodeRunTime = json['episode_run_time'] as List?;
    final runtime = episodeRunTime != null && episodeRunTime.isNotEmpty
        ? episodeRunTime.first as int
        : null;

    return ScraperTvDetail(
      externalId: (json['id'] as int).toString(),
      source: ScraperType.tmdb,
      title: json['name'] as String? ?? '',
      originalTitle: json['original_name'] as String?,
      overview: json['overview'] as String?,
      posterUrl: getImageUrlWithProxy(json['poster_path'] as String?),
      backdropUrl: getImageUrlWithProxy(
        json['backdrop_path'] as String?,
        size: 'original',
      ),
      year: _parseYear(json['first_air_date'] as String?),
      rating: (json['vote_average'] as num?)?.toDouble(),
      voteCount: json['vote_count'] as int?,
      episodeRuntime: runtime,
      genres: genres,
      countries: countries,
      cast: castList,
      status: json['status'] as String?,
      numberOfSeasons: json['number_of_seasons'] as int?,
      numberOfEpisodes: json['number_of_episodes'] as int?,
      seasons: seasons,
    );
  }

  ScraperSeasonDetail _parseSeasonDetail(
    Map<String, dynamic> json,
    String tvId,
  ) {
    final episodes = (json['episodes'] as List?)?.map((e) {
          final ep = e as Map<String, dynamic>;
          return ScraperEpisodeDetail(
            externalId: tvId,
            source: ScraperType.tmdb,
            seasonNumber: ep['season_number'] as int? ?? 0,
            episodeNumber: ep['episode_number'] as int? ?? 0,
            name: ep['name'] as String?,
            overview: ep['overview'] as String?,
            stillUrl: getImageUrlWithProxy(ep['still_path'] as String?),
            airDate: ep['air_date'] as String?,
            runtime: ep['runtime'] as int?,
            rating: (ep['vote_average'] as num?)?.toDouble(),
          );
        }).toList() ??
        [];

    return ScraperSeasonDetail(
      externalId: tvId,
      source: ScraperType.tmdb,
      seasonNumber: json['season_number'] as int? ?? 0,
      name: json['name'] as String?,
      overview: json['overview'] as String?,
      posterUrl: getImageUrlWithProxy(json['poster_path'] as String?),
      airDate: json['air_date'] as String?,
      episodes: episodes,
    );
  }

  int? _parseYear(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return null;
    return int.tryParse(dateStr.split('-').first);
  }

  /// ISO 国家代码转换为本地化名称
  String _countryCodeToName(String code) => switch (code.toUpperCase()) {
        'US' => appL10n.tmdbScraperCountryUs,
        'CN' => appL10n.tmdbScraperCountryCn,
        'JP' => appL10n.tmdbScraperCountryJp,
        'KR' => appL10n.tmdbScraperCountryKr,
        'GB' => appL10n.tmdbScraperCountryGb,
        'FR' => appL10n.tmdbScraperCountryFr,
        'DE' => appL10n.tmdbScraperCountryDe,
        'IT' => appL10n.tmdbScraperCountryIt,
        'ES' => appL10n.tmdbScraperCountryEs,
        'CA' => appL10n.tmdbScraperCountryCa,
        'AU' => appL10n.tmdbScraperCountryAu,
        'IN' => appL10n.tmdbScraperCountryIn,
        'TW' => appL10n.tmdbScraperCountryTw,
        'HK' => appL10n.tmdbScraperCountryHk,
        'TH' => appL10n.tmdbScraperCountryTh,
        'RU' => appL10n.tmdbScraperCountryRu,
        'BR' => appL10n.tmdbScraperCountryBr,
        'MX' => appL10n.tmdbScraperCountryMx,
        'NL' => appL10n.tmdbScraperCountryNl,
        'SE' => appL10n.tmdbScraperCountrySe,
        'DK' => appL10n.tmdbScraperCountryDk,
        'NO' => appL10n.tmdbScraperCountryNo,
        'FI' => appL10n.tmdbScraperCountryFi,
        'BE' => appL10n.tmdbScraperCountryBe,
        'AT' => appL10n.tmdbScraperCountryAt,
        'CH' => appL10n.tmdbScraperCountryCh,
        'NZ' => appL10n.tmdbScraperCountryNz,
        'IE' => appL10n.tmdbScraperCountryIe,
        'PL' => appL10n.tmdbScraperCountryPl,
        'TR' => appL10n.tmdbScraperCountryTr,
        'ZA' => appL10n.tmdbScraperCountryZa,
        'SG' => appL10n.tmdbScraperCountrySg,
        'MY' => appL10n.tmdbScraperCountryMy,
        'ID' => appL10n.tmdbScraperCountryId,
        'PH' => appL10n.tmdbScraperCountryPh,
        'VN' => appL10n.tmdbScraperCountryVn,
        'AR' => appL10n.tmdbScraperCountryAr,
        'CL' => appL10n.tmdbScraperCountryCl,
        'CO' => appL10n.tmdbScraperCountryCo,
        'PE' => appL10n.tmdbScraperCountryPe,
        'EG' => appL10n.tmdbScraperCountryEg,
        'IL' => appL10n.tmdbScraperCountryIl,
        'AE' => appL10n.tmdbScraperCountryAe,
        'SA' => appL10n.tmdbScraperCountrySa,
        'UA' => appL10n.tmdbScraperCountryUa,
        'CZ' => appL10n.tmdbScraperCountryCz,
        'HU' => appL10n.tmdbScraperCountryHu,
        'PT' => appL10n.tmdbScraperCountryPt,
        'GR' => appL10n.tmdbScraperCountryGr,
        _ => code,
      };
}
