import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:http/http.dart' as http;
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/network/resolved_http_client.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/shared/providers/language_preference_provider.dart';

/// TMDB API 服务
class TmdbService {
  factory TmdbService() => _instance ??= TmdbService._();
  TmdbService._();

  static TmdbService? _instance;

  // TMDB API Key - 可以在设置中配置
  static const String _defaultApiKey = ''; // 用户需要自己申请
  String _apiKey = _defaultApiKey;

  /// 默认 API URL
  static const String _defaultApiUrl = 'https://api.themoviedb.org/3';

  /// 默认图片 URL
  static const String _defaultImageUrl = 'https://image.tmdb.org/t/p';

  /// 当前使用的 API URL（支持自定义代理）
  String _apiUrl = _defaultApiUrl;

  /// 当前使用的图片 URL（支持自定义代理）
  String _imageUrl = _defaultImageUrl;

  /// HTTP 请求超时时间
  static const Duration _requestTimeout = Duration(seconds: 15);

  /// 带超时的 HTTP GET 请求
  ///
  /// 使用 [ResolvedHttpClient] 让请求经过应用内 hosts 映射，绕过 DNS 污染。
  /// 防止网络不稳定时请求无限挂起。
  Future<http.Response> _httpGet(Uri uri) => ResolvedHttpClient.get(uri).timeout(
        _requestTimeout,
        onTimeout: () => throw TimeoutException(appL10n.tmdbApiRequestTimeout(uri.toString())),
      );

  // 语言偏好缓存
  LanguagePreference? _languagePreference;
  Locale _systemLocale = const Locale('zh', 'CN');

  /// 设置 API Key
  void setApiKey(String key) {
    _apiKey = key;
  }

  /// 设置 API URL（支持自定义代理，如 api.tmdb.org）
  ///
  /// [url] API 基础 URL，不需要包含 /3 后缀（会自动添加）
  void setApiUrl(String? url) {
    if (url == null || url.isEmpty) {
      _apiUrl = _defaultApiUrl;
      return;
    }
    // 规范化 URL：移除末尾斜杠，确保包含 /3
    var normalized = url.trimRight();
    if (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    // 如果用户输入的是不带 /3 的 URL，自动添加
    if (!normalized.endsWith('/3')) {
      normalized = '$normalized/3';
    }
    _apiUrl = normalized;
    logger.i('TmdbService: API URL 已设置为 $_apiUrl');
  }

  /// 设置图片 URL（支持自定义代理）
  void setImageUrl(String? url) {
    if (url == null || url.isEmpty) {
      _imageUrl = _defaultImageUrl;
      return;
    }
    var normalized = url.trimRight();
    if (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    _imageUrl = normalized;
    logger.i('TmdbService: 图片 URL 已设置为 $_imageUrl');
  }

  /// 获取当前 API URL
  String get apiUrl => _apiUrl;

  /// 获取当前图片 URL
  String get imageUrl => _imageUrl;

  /// 检查是否配置了 API Key
  bool get hasApiKey => _apiKey.isNotEmpty;

  /// 设置语言偏好
  void setLanguagePreference(LanguagePreference preference) {
    _languagePreference = preference;
  }

  /// 设置系统语言环境
  void setSystemLocale(Locale locale) {
    _systemLocale = locale;
  }

  /// 获取元数据的首选语言代码
  String getPreferredMetadataLanguage() {
    if (_languagePreference == null) {
      return 'zh-CN';
    }

    final languages = _languagePreference!.metadataLanguages;
    if (languages.isEmpty) {
      return 'zh-CN';
    }

    // 获取第一个有效的语言代码
    for (final lang in languages) {
      final code = lang.getActualCode(_systemLocale);
      if (code.isNotEmpty) {
        return code;
      }
    }

    // 如果都是 original，返回系统语言
    return _systemLocale.languageCode;
  }

  /// 获取图片完整 URL
  ///
  /// 使用当前配置的图片 URL（支持自定义代理）
  static String getImageUrl(String? path, {ImageSize size = ImageSize.w500}) {
    if (path == null || path.isEmpty) return '';
    // 使用实例的图片 URL 配置
    final imageUrl = _instance?._imageUrl ?? _defaultImageUrl;
    return '$imageUrl/${size.value}$path';
  }

  /// 搜索电影
  ///
  /// [language] 可选，不传则使用用户语言偏好设置
  Future<TmdbSearchResult> searchMovies(
    String query, {
    int page = 1,
    String? language,
    int? year,
  }) async {
    if (!hasApiKey) {
      return TmdbSearchResult.empty();
    }

    try {
      final params = {
        'api_key': _apiKey,
        'query': query,
        'page': page.toString(),
        'language': language ?? getPreferredMetadataLanguage(),
        'include_adult': 'false',
      };
      if (year != null) {
        params['year'] = year.toString();
      }

      final uri = Uri.parse('$_apiUrl/search/movie').replace(queryParameters: params);
      final response = await _httpGet(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return TmdbSearchResult.fromJson(data, isMovie: true);
      } else {
        logger.e('TMDB搜索电影失败: ${response.statusCode}');
        return TmdbSearchResult.empty();
      }
    } on Exception catch (e) {
      logger.e('TMDB搜索电影异常', e);
      return TmdbSearchResult.empty();
    }
  }

  /// 搜索电视剧
  ///
  /// [language] 可选，不传则使用用户语言偏好设置
  Future<TmdbSearchResult> searchTvShows(
    String query, {
    int page = 1,
    String? language,
    int? year,
  }) async {
    if (!hasApiKey) {
      return TmdbSearchResult.empty();
    }

    try {
      final params = {
        'api_key': _apiKey,
        'query': query,
        'page': page.toString(),
        'language': language ?? getPreferredMetadataLanguage(),
      };
      if (year != null) {
        params['first_air_date_year'] = year.toString();
      }

      final uri = Uri.parse('$_apiUrl/search/tv').replace(queryParameters: params);
      final response = await _httpGet(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return TmdbSearchResult.fromJson(data, isMovie: false);
      } else {
        logger.e('TMDB搜索电视剧失败: ${response.statusCode}');
        return TmdbSearchResult.empty();
      }
    } on Exception catch (e) {
      logger.e('TMDB搜索电视剧异常', e);
      return TmdbSearchResult.empty();
    }
  }

  /// 获取电影详情
  ///
  /// [language] 可选，不传则使用用户语言偏好设置
  Future<TmdbMovieDetail?> getMovieDetail(
    int movieId, {
    String? language,
  }) async {
    if (!hasApiKey) return null;

    try {
      final params = {
        'api_key': _apiKey,
        'language': language ?? getPreferredMetadataLanguage(),
        // 添加 release_dates 获取内容分级，external_ids 获取 IMDb ID
        'append_to_response': 'credits,videos,images,release_dates,external_ids',
      };

      final uri = Uri.parse('$_apiUrl/movie/$movieId').replace(queryParameters: params);
      final response = await _httpGet(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return TmdbMovieDetail.fromJson(data);
      } else {
        logger.e('TMDB获取电影详情失败: ${response.statusCode}');
        return null;
      }
    } on Exception catch (e) {
      logger.e('TMDB获取电影详情异常', e);
      return null;
    }
  }

  /// 获取电视剧详情
  ///
  /// [language] 可选，不传则使用用户语言偏好设置
  Future<TmdbTvDetail?> getTvDetail(
    int tvId, {
    String? language,
  }) async {
    if (!hasApiKey) return null;

    try {
      final params = {
        'api_key': _apiKey,
        'language': language ?? getPreferredMetadataLanguage(),
        'append_to_response': 'credits,videos,images',
      };

      final uri = Uri.parse('$_apiUrl/tv/$tvId').replace(queryParameters: params);
      final response = await _httpGet(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return TmdbTvDetail.fromJson(data);
      } else {
        logger.e('TMDB获取电视剧详情失败: ${response.statusCode}');
        return null;
      }
    } on Exception catch (e) {
      logger.e('TMDB获取电视剧详情异常', e);
      return null;
    }
  }

  /// 获取电视剧季详情
  ///
  /// [language] 可选，不传则使用用户语言偏好设置
  Future<TmdbSeasonDetail?> getSeasonDetail(
    int tvId,
    int seasonNumber, {
    String? language,
  }) async {
    if (!hasApiKey) return null;

    try {
      final params = {
        'api_key': _apiKey,
        'language': language ?? getPreferredMetadataLanguage(),
      };

      final uri = Uri.parse('$_apiUrl/tv/$tvId/season/$seasonNumber')
          .replace(queryParameters: params);
      final response = await _httpGet(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return TmdbSeasonDetail.fromJson(data);
      } else {
        logger.e('TMDB获取季详情失败: ${response.statusCode}');
        return null;
      }
    } on Exception catch (e) {
      logger.e('TMDB获取季详情异常', e);
      return null;
    }
  }

  /// 获取电影推荐
  ///
  /// [language] 可选，不传则使用用户语言偏好设置
  Future<TmdbSearchResult> getMovieRecommendations(
    int movieId, {
    int page = 1,
    String? language,
  }) async {
    if (!hasApiKey) return TmdbSearchResult.empty();

    try {
      final params = {
        'api_key': _apiKey,
        'page': page.toString(),
        'language': language ?? getPreferredMetadataLanguage(),
      };

      final uri = Uri.parse('$_apiUrl/movie/$movieId/recommendations')
          .replace(queryParameters: params);
      final response = await _httpGet(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return TmdbSearchResult.fromJson(data, isMovie: true);
      } else {
        logger.e('TMDB获取电影推荐失败: ${response.statusCode}');
        return TmdbSearchResult.empty();
      }
    } on Exception catch (e) {
      logger.e('TMDB获取电影推荐异常', e);
      return TmdbSearchResult.empty();
    }
  }

  /// 获取电视剧推荐
  ///
  /// [language] 可选，不传则使用用户语言偏好设置
  Future<TmdbSearchResult> getTvRecommendations(
    int tvId, {
    int page = 1,
    String? language,
  }) async {
    if (!hasApiKey) return TmdbSearchResult.empty();

    try {
      final params = {
        'api_key': _apiKey,
        'page': page.toString(),
        'language': language ?? getPreferredMetadataLanguage(),
      };

      final uri = Uri.parse('$_apiUrl/tv/$tvId/recommendations')
          .replace(queryParameters: params);
      final response = await _httpGet(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return TmdbSearchResult.fromJson(data, isMovie: false);
      } else {
        logger.e('TMDB获取电视剧推荐失败: ${response.statusCode}');
        return TmdbSearchResult.empty();
      }
    } on Exception catch (e) {
      logger.e('TMDB获取电视剧推荐异常', e);
      return TmdbSearchResult.empty();
    }
  }

  /// 获取相似电影
  ///
  /// [language] 可选，不传则使用用户语言偏好设置
  Future<TmdbSearchResult> getSimilarMovies(
    int movieId, {
    int page = 1,
    String? language,
  }) async {
    if (!hasApiKey) return TmdbSearchResult.empty();

    try {
      final params = {
        'api_key': _apiKey,
        'page': page.toString(),
        'language': language ?? getPreferredMetadataLanguage(),
      };

      final uri = Uri.parse('$_apiUrl/movie/$movieId/similar')
          .replace(queryParameters: params);
      final response = await _httpGet(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return TmdbSearchResult.fromJson(data, isMovie: true);
      } else {
        logger.e('TMDB获取相似电影失败: ${response.statusCode}');
        return TmdbSearchResult.empty();
      }
    } on Exception catch (e) {
      logger.e('TMDB获取相似电影异常', e);
      return TmdbSearchResult.empty();
    }
  }

  /// 获取相似电视剧
  ///
  /// [language] 可选，不传则使用用户语言偏好设置
  Future<TmdbSearchResult> getSimilarTvShows(
    int tvId, {
    int page = 1,
    String? language,
  }) async {
    if (!hasApiKey) return TmdbSearchResult.empty();

    try {
      final params = {
        'api_key': _apiKey,
        'page': page.toString(),
        'language': language ?? getPreferredMetadataLanguage(),
      };

      final uri = Uri.parse('$_apiUrl/tv/$tvId/similar')
          .replace(queryParameters: params);
      final response = await _httpGet(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return TmdbSearchResult.fromJson(data, isMovie: false);
      } else {
        logger.e('TMDB获取相似电视剧失败: ${response.statusCode}');
        return TmdbSearchResult.empty();
      }
    } on Exception catch (e) {
      logger.e('TMDB获取相似电视剧异常', e);
      return TmdbSearchResult.empty();
    }
  }

  /// 获取电影合集/系列详情
  ///
  /// [language] 可选，不传则使用用户语言偏好设置
  Future<TmdbCollection?> getCollection(
    int collectionId, {
    String? language,
  }) async {
    if (!hasApiKey) return null;

    try {
      final params = {
        'api_key': _apiKey,
        'language': language ?? getPreferredMetadataLanguage(),
      };

      final uri = Uri.parse('$_apiUrl/collection/$collectionId')
          .replace(queryParameters: params);
      final response = await _httpGet(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return TmdbCollection.fromJson(data);
      } else {
        logger.e('TMDB获取合集详情失败: ${response.statusCode}');
        return null;
      }
    } on Exception catch (e) {
      logger.e('TMDB获取合集详情异常', e);
      return null;
    }
  }

  /// 获取电影的多语言翻译
  ///
  /// 返回所有可用语言的标题和简介
  Future<TmdbTranslations?> getMovieTranslations(int movieId) async {
    if (!hasApiKey) return null;

    try {
      final params = {'api_key': _apiKey};
      final uri = Uri.parse('$_apiUrl/movie/$movieId/translations')
          .replace(queryParameters: params);
      final response = await _httpGet(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return TmdbTranslations.fromJson(data);
      } else {
        logger.e('TMDB获取电影翻译失败: ${response.statusCode}');
        return null;
      }
    } on Exception catch (e) {
      logger.e('TMDB获取电影翻译异常', e);
      return null;
    }
  }

  /// 获取电视剧的多语言翻译
  ///
  /// 返回所有可用语言的标题和简介
  Future<TmdbTranslations?> getTvTranslations(int tvId) async {
    if (!hasApiKey) return null;

    try {
      final params = {'api_key': _apiKey};
      final uri = Uri.parse('$_apiUrl/tv/$tvId/translations')
          .replace(queryParameters: params);
      final response = await _httpGet(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return TmdbTranslations.fromJson(data);
      } else {
        logger.e('TMDB获取电视剧翻译失败: ${response.statusCode}');
        return null;
      }
    } on Exception catch (e) {
      logger.e('TMDB获取电视剧翻译异常', e);
      return null;
    }
  }

  /// 获取用户偏好的语言代码列表
  ///
  /// 用于多语言获取和显示
  List<String> getPreferredLanguageCodes() {
    if (_languagePreference == null) {
      return ['zh-CN', 'en'];
    }

    final codes = <String>[];
    for (final lang in _languagePreference!.metadataLanguages) {
      final code = lang.getActualCode(_systemLocale);
      if (code.isNotEmpty && !codes.contains(code)) {
        codes.add(code);
      }
    }

    // 确保至少有一个语言
    if (codes.isEmpty) {
      codes.add('zh-CN');
    }

    return codes;
  }
}

/// TMDB 翻译信息
class TmdbTranslation {
  TmdbTranslation({
    required this.iso31661,
    required this.iso6391,
    required this.name,
    required this.englishName,
    this.title,
    this.overview,
    this.tagline,
  });

  factory TmdbTranslation.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? {};
    return TmdbTranslation(
      iso31661: json['iso_3166_1'] as String? ?? '',
      iso6391: json['iso_639_1'] as String? ?? '',
      name: json['name'] as String? ?? '',
      englishName: json['english_name'] as String? ?? '',
      title: data['title'] as String? ?? data['name'] as String?,
      overview: data['overview'] as String?,
      tagline: data['tagline'] as String?,
    );
  }

  final String iso31661;
  final String iso6391;
  final String name;
  final String englishName;
  final String? title;
  final String? overview;
  final String? tagline;

  /// 获取完整的语言代码（如 zh-CN, en-US）
  String get languageCode {
    if (iso6391.isEmpty) return '';
    if (iso31661.isEmpty) return iso6391;
    return '$iso6391-$iso31661';
  }

  /// 获取简短语言代码（如 zh, en）
  String get shortLanguageCode => iso6391;
}

/// TMDB 翻译列表
class TmdbTranslations {
  TmdbTranslations({
    required this.id,
    required this.translations,
  });

  factory TmdbTranslations.fromJson(Map<String, dynamic> json) => TmdbTranslations(
      id: json['id'] as int? ?? 0,
      translations: (json['translations'] as List?)
              ?.map((e) => TmdbTranslation.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );

  final int id;
  final List<TmdbTranslation> translations;

  /// 获取指定语言的翻译
  TmdbTranslation? getTranslation(String languageCode) {
    // 精确匹配（如 zh-CN）
    for (final t in translations) {
      if (t.languageCode == languageCode) return t;
    }
    // 前缀匹配（如 zh 匹配 zh-CN, zh-TW）
    final prefix = languageCode.split('-').first;
    for (final t in translations) {
      if (t.shortLanguageCode == prefix) return t;
    }
    return null;
  }

  /// 转换为多语言 Map（语言代码 -> 标题）
  Map<String, String> toTitleMap() {
    final map = <String, String>{};
    for (final t in translations) {
      if (t.title != null && t.title!.isNotEmpty) {
        // 使用完整语言代码
        map[t.languageCode] = t.title!;
        // 也存储简短代码，方便查找
        if (!map.containsKey(t.shortLanguageCode)) {
          map[t.shortLanguageCode] = t.title!;
        }
      }
    }
    return map;
  }

  /// 转换为多语言 Map（语言代码 -> 简介）
  Map<String, String> toOverviewMap() {
    final map = <String, String>{};
    for (final t in translations) {
      if (t.overview != null && t.overview!.isNotEmpty) {
        map[t.languageCode] = t.overview!;
        if (!map.containsKey(t.shortLanguageCode)) {
          map[t.shortLanguageCode] = t.overview!;
        }
      }
    }
    return map;
  }
}

/// 图片尺寸
enum ImageSize {
  w92('w92'),
  w154('w154'),
  w185('w185'),
  w342('w342'),
  w500('w500'),
  w780('w780'),
  original('original');

  const ImageSize(this.value);
  final String value;
}

/// 搜索结果
class TmdbSearchResult {
  TmdbSearchResult({
    required this.page,
    required this.totalPages,
    required this.totalResults,
    required this.results,
  });

  factory TmdbSearchResult.empty() => TmdbSearchResult(
        page: 0,
        totalPages: 0,
        totalResults: 0,
        results: [],
      );

  factory TmdbSearchResult.fromJson(Map<String, dynamic> json, {required bool isMovie}) {
    final results = (json['results'] as List?)
            ?.map((e) => TmdbMediaItem.fromJson(e as Map<String, dynamic>, isMovie: isMovie))
            .toList() ??
        [];

    return TmdbSearchResult(
      page: json['page'] as int? ?? 0,
      totalPages: json['total_pages'] as int? ?? 0,
      totalResults: json['total_results'] as int? ?? 0,
      results: results,
    );
  }

  final int page;
  final int totalPages;
  final int totalResults;
  final List<TmdbMediaItem> results;

  bool get isEmpty => results.isEmpty;
  bool get isNotEmpty => results.isNotEmpty;
}

/// 媒体项
class TmdbMediaItem {
  TmdbMediaItem({
    required this.id,
    required this.title,
    required this.originalTitle,
    required this.overview,
    required this.posterPath,
    required this.backdropPath,
    required this.releaseDate,
    required this.voteAverage,
    required this.voteCount,
    required this.popularity,
    required this.isMovie,
    required this.genreIds,
  });

  factory TmdbMediaItem.fromJson(Map<String, dynamic> json, {required bool isMovie}) => TmdbMediaItem(
      id: json['id'] as int,
      title: (isMovie ? json['title'] : json['name']) as String? ?? '',
      originalTitle:
          (isMovie ? json['original_title'] : json['original_name']) as String? ?? '',
      overview: json['overview'] as String? ?? '',
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      releaseDate:
          (isMovie ? json['release_date'] : json['first_air_date']) as String? ?? '',
      voteAverage: (json['vote_average'] as num?)?.toDouble() ?? 0.0,
      voteCount: json['vote_count'] as int? ?? 0,
      popularity: (json['popularity'] as num?)?.toDouble() ?? 0.0,
      isMovie: isMovie,
      genreIds:
          (json['genre_ids'] as List?)?.map((e) => e as int).toList() ?? [],
    );

  final int id;
  final String title;
  final String originalTitle;
  final String overview;
  final String? posterPath;
  final String? backdropPath;
  final String releaseDate;
  final double voteAverage;
  final int voteCount;
  final double popularity;
  final bool isMovie;
  final List<int> genreIds;

  String get posterUrl => TmdbService.getImageUrl(posterPath);
  String get backdropUrl => TmdbService.getImageUrl(backdropPath, size: ImageSize.w780);

  int? get year {
    if (releaseDate.isEmpty) return null;
    return int.tryParse(releaseDate.split('-').first);
  }

  String get ratingText => voteAverage.toStringAsFixed(1);
}

/// 电影详情
class TmdbMovieDetail {
  TmdbMovieDetail({
    required this.id,
    required this.title,
    required this.originalTitle,
    required this.overview,
    required this.posterPath,
    required this.backdropPath,
    required this.releaseDate,
    required this.runtime,
    required this.voteAverage,
    required this.voteCount,
    required this.genres,
    required this.productionCompanies,
    required this.productionCountries,
    required this.cast,
    required this.crew,
    required this.tagline,
    required this.status,
    required this.budget,
    required this.revenue,
    this.belongsToCollection,
    this.imdbId,
    this.certification,
  });

  factory TmdbMovieDetail.fromJson(Map<String, dynamic> json) {
    final credits = json['credits'] as Map<String, dynamic>?;
    final collectionData = json['belongs_to_collection'] as Map<String, dynamic>?;
    final externalIds = json['external_ids'] as Map<String, dynamic>?;
    final releaseDates = json['release_dates'] as Map<String, dynamic>?;

    // 解析 IMDb ID
    final imdbId = externalIds?['imdb_id'] as String?;

    // 解析内容分级（优先 US，其次任意可用）
    String? certification;
    if (releaseDates != null) {
      final results = releaseDates['results'] as List?;
      if (results != null) {
        // 优先查找 US 分级
        for (final result in results) {
          if (result is Map && result['iso_3166_1'] == 'US') {
            final releases = result['release_dates'] as List?;
            if (releases != null && releases.isNotEmpty) {
              for (final release in releases) {
                if (release is Map) {
                  final cert = release['certification'] as String?;
                  if (cert != null && cert.isNotEmpty) {
                    certification = cert;
                    break;
                  }
                }
              }
            }
            break;
          }
        }
        // 如果没有 US 分级，尝试其他地区
        if (certification == null) {
          for (final result in results) {
            if (result is Map) {
              final releases = result['release_dates'] as List?;
              if (releases != null && releases.isNotEmpty) {
                for (final release in releases) {
                  if (release is Map) {
                    final cert = release['certification'] as String?;
                    if (cert != null && cert.isNotEmpty) {
                      certification = cert;
                      break;
                    }
                  }
                }
                if (certification != null) break;
              }
            }
          }
        }
      }
    }

    return TmdbMovieDetail(
      id: json['id'] as int,
      title: json['title'] as String? ?? '',
      originalTitle: json['original_title'] as String? ?? '',
      overview: json['overview'] as String? ?? '',
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      releaseDate: json['release_date'] as String? ?? '',
      runtime: json['runtime'] as int? ?? 0,
      voteAverage: (json['vote_average'] as num?)?.toDouble() ?? 0.0,
      voteCount: json['vote_count'] as int? ?? 0,
      genres: (json['genres'] as List?)
              ?.map((e) => TmdbGenre.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      productionCompanies: (json['production_companies'] as List?)
              ?.map((e) => TmdbCompany.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      productionCountries: (json['production_countries'] as List?)
              ?.map((e) => TmdbCountry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      cast: (credits?['cast'] as List?)
              ?.take(20)
              .map((e) => TmdbCast.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      crew: (credits?['crew'] as List?)
              ?.map((e) => TmdbCrew.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      tagline: json['tagline'] as String? ?? '',
      status: json['status'] as String? ?? '',
      budget: json['budget'] as int? ?? 0,
      revenue: json['revenue'] as int? ?? 0,
      belongsToCollection: collectionData != null
          ? TmdbCollectionInfo.fromJson(collectionData)
          : null,
      imdbId: imdbId,
      certification: certification,
    );
  }

  final int id;
  final String title;
  final String originalTitle;
  final String overview;
  final String? posterPath;
  final String? backdropPath;
  final String releaseDate;
  final int runtime;
  final double voteAverage;
  final int voteCount;
  final List<TmdbGenre> genres;
  final List<TmdbCompany> productionCompanies;
  final List<TmdbCountry> productionCountries;
  final List<TmdbCast> cast;
  final List<TmdbCrew> crew;
  final String tagline;
  final String status;
  final int budget;
  final int revenue;
  final TmdbCollectionInfo? belongsToCollection;
  final String? imdbId; // IMDb ID
  final String? certification; // 内容分级（PG, R, NC-17 等）

  String get posterUrl => TmdbService.getImageUrl(posterPath);
  String get backdropUrl => TmdbService.getImageUrl(backdropPath, size: ImageSize.original);

  int? get year {
    if (releaseDate.isEmpty) return null;
    return int.tryParse(releaseDate.split('-').first);
  }

  String get runtimeText {
    if (runtime == 0) return '';
    final hours = runtime ~/ 60;
    final minutes = runtime % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  String get genresText => genres.map((g) => g.name).join(' / ');

  /// 国家/地区文本（用于存储）
  String get countriesText => productionCountries.map((c) => c.name).join(', ');

  TmdbCrew? get director => crew.where((c) => c.job == 'Director').firstOrNull;

  // === 系列信息便捷访问 ===

  /// 系列 ID
  int? get collectionId => belongsToCollection?.id;

  /// 系列名称
  String? get collectionName => belongsToCollection?.name;

  /// 系列海报 URL
  String? get collectionPosterUrl =>
      belongsToCollection?.posterPath != null ? belongsToCollection!.posterUrl : null;

  /// 系列背景图 URL
  String? get collectionBackdropUrl =>
      belongsToCollection?.backdropPath != null ? belongsToCollection!.backdropUrl : null;

  /// 类型列表（字符串格式）
  List<String>? get genresList => genres.isNotEmpty ? genres.map((g) => g.name).toList() : null;

  /// 国家/地区列表（字符串格式）
  List<String>? get countriesList =>
      productionCountries.isNotEmpty ? productionCountries.map((c) => c.name).toList() : null;

  /// 导演名称
  String? get directorName => director?.name;

  /// 演员名称列表
  List<String>? get castNames => cast.isNotEmpty ? cast.map((c) => c.name).toList() : null;
}

/// 电视剧详情
class TmdbTvDetail {
  TmdbTvDetail({
    required this.id,
    required this.name,
    required this.originalName,
    required this.overview,
    required this.posterPath,
    required this.backdropPath,
    required this.firstAirDate,
    required this.lastAirDate,
    required this.voteAverage,
    required this.voteCount,
    required this.genres,
    required this.originCountry,
    required this.productionCountries,
    required this.seasons,
    required this.numberOfSeasons,
    required this.numberOfEpisodes,
    required this.episodeRunTime,
    required this.cast,
    required this.crew,
    required this.status,
    required this.tagline,
    required this.networks,
  });

  factory TmdbTvDetail.fromJson(Map<String, dynamic> json) {
    final credits = json['credits'] as Map<String, dynamic>?;

    return TmdbTvDetail(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      originalName: json['original_name'] as String? ?? '',
      overview: json['overview'] as String? ?? '',
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      firstAirDate: json['first_air_date'] as String? ?? '',
      lastAirDate: json['last_air_date'] as String? ?? '',
      voteAverage: (json['vote_average'] as num?)?.toDouble() ?? 0.0,
      voteCount: json['vote_count'] as int? ?? 0,
      genres: (json['genres'] as List?)
              ?.map((e) => TmdbGenre.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      originCountry: (json['origin_country'] as List?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      productionCountries: (json['production_countries'] as List?)
              ?.map((e) => TmdbCountry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      seasons: (json['seasons'] as List?)
              ?.map((e) => TmdbSeason.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      numberOfSeasons: json['number_of_seasons'] as int? ?? 0,
      numberOfEpisodes: json['number_of_episodes'] as int? ?? 0,
      episodeRunTime: (json['episode_run_time'] as List?)
              ?.map((e) => e as int)
              .toList() ??
          [],
      cast: (credits?['cast'] as List?)
              ?.take(20)
              .map((e) => TmdbCast.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      crew: (credits?['crew'] as List?)
              ?.map((e) => TmdbCrew.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      status: json['status'] as String? ?? '',
      tagline: json['tagline'] as String? ?? '',
      networks: (json['networks'] as List?)
              ?.map((e) => TmdbNetwork.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  final int id;
  final String name;
  final String originalName;
  final String overview;
  final String? posterPath;
  final String? backdropPath;
  final String firstAirDate;
  final String lastAirDate;
  final double voteAverage;
  final int voteCount;
  final List<TmdbGenre> genres;
  final List<String> originCountry;
  final List<TmdbCountry> productionCountries;
  final List<TmdbSeason> seasons;
  final int numberOfSeasons;
  final int numberOfEpisodes;
  final List<int> episodeRunTime;
  final List<TmdbCast> cast;
  final List<TmdbCrew> crew;
  final String status;
  final String tagline;
  final List<TmdbNetwork> networks;

  String get posterUrl => TmdbService.getImageUrl(posterPath);
  String get backdropUrl => TmdbService.getImageUrl(backdropPath, size: ImageSize.original);

  int? get year {
    if (firstAirDate.isEmpty) return null;
    return int.tryParse(firstAirDate.split('-').first);
  }

  String get genresText => genres.map((g) => g.name).join(' / ');

  /// 国家/地区文本（用于存储）
  /// 优先使用 production_countries（有完整名称），回退到 origin_country（ISO代码）
  String get countriesText {
    if (productionCountries.isNotEmpty) {
      return productionCountries.map((c) => c.name).join(', ');
    }
    // origin_country 是 ISO 代码列表，转换为可读名称
    return originCountry.map(_countryCodeToName).join(', ');
  }

  /// ISO 国家代码转换为显示名称（已本地化）
  static String _countryCodeToName(String code) {
    switch (code) {
      case 'US':
        return appL10n.tmdbCountryCodeUS;
      case 'CN':
        return appL10n.tmdbCountryCodeCN;
      case 'JP':
        return appL10n.tmdbCountryCodeJP;
      case 'KR':
        return appL10n.tmdbCountryCodeKR;
      case 'GB':
        return appL10n.tmdbCountryCodeGB;
      case 'FR':
        return appL10n.tmdbCountryCodeFR;
      case 'DE':
        return appL10n.tmdbCountryCodeDE;
      case 'IT':
        return appL10n.tmdbCountryCodeIT;
      case 'ES':
        return appL10n.tmdbCountryCodeES;
      case 'CA':
        return appL10n.tmdbCountryCodeCA;
      case 'AU':
        return appL10n.tmdbCountryCodeAU;
      case 'IN':
        return appL10n.tmdbCountryCodeIN;
      case 'TW':
        return appL10n.tmdbCountryCodeTW;
      case 'HK':
        return appL10n.tmdbCountryCodeHK;
      case 'TH':
        return appL10n.tmdbCountryCodeTH;
      case 'RU':
        return appL10n.tmdbCountryCodeRU;
      case 'BR':
        return appL10n.tmdbCountryCodeBR;
      case 'MX':
        return appL10n.tmdbCountryCodeMX;
      case 'NL':
        return appL10n.tmdbCountryCodeNL;
      case 'SE':
        return appL10n.tmdbCountryCodeSE;
      case 'DK':
        return appL10n.tmdbCountryCodeDK;
      case 'NO':
        return appL10n.tmdbCountryCodeNO;
      case 'FI':
        return appL10n.tmdbCountryCodeFI;
      case 'BE':
        return appL10n.tmdbCountryCodeBE;
      case 'AT':
        return appL10n.tmdbCountryCodeAT;
      case 'CH':
        return appL10n.tmdbCountryCodeCH;
      case 'NZ':
        return appL10n.tmdbCountryCodeNZ;
      case 'IE':
        return appL10n.tmdbCountryCodeIE;
      case 'PL':
        return appL10n.tmdbCountryCodePL;
      case 'TR':
        return appL10n.tmdbCountryCodeTR;
      case 'AR':
        return appL10n.tmdbCountryCodeAR;
      case 'ZA':
        return appL10n.tmdbCountryCodeZA;
      case 'SG':
        return appL10n.tmdbCountryCodeSG;
      case 'MY':
        return appL10n.tmdbCountryCodeMY;
      case 'ID':
        return appL10n.tmdbCountryCodeID;
      case 'PH':
        return appL10n.tmdbCountryCodePH;
      case 'VN':
        return appL10n.tmdbCountryCodeVN;
      default:
        return code;
    }
  }
}

/// 季详情
class TmdbSeasonDetail {
  TmdbSeasonDetail({
    required this.id,
    required this.name,
    required this.overview,
    required this.posterPath,
    required this.seasonNumber,
    required this.airDate,
    required this.episodes,
  });

  factory TmdbSeasonDetail.fromJson(Map<String, dynamic> json) => TmdbSeasonDetail(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      overview: json['overview'] as String? ?? '',
      posterPath: json['poster_path'] as String?,
      seasonNumber: json['season_number'] as int? ?? 0,
      airDate: json['air_date'] as String? ?? '',
      episodes: (json['episodes'] as List?)
              ?.map((e) => TmdbEpisode.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );

  final int id;
  final String name;
  final String overview;
  final String? posterPath;
  final int seasonNumber;
  final String airDate;
  final List<TmdbEpisode> episodes;

  String get posterUrl => TmdbService.getImageUrl(posterPath);
}

/// 季信息
class TmdbSeason {
  TmdbSeason({
    required this.id,
    required this.name,
    required this.overview,
    required this.posterPath,
    required this.seasonNumber,
    required this.episodeCount,
    required this.airDate,
  });

  factory TmdbSeason.fromJson(Map<String, dynamic> json) => TmdbSeason(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      overview: json['overview'] as String? ?? '',
      posterPath: json['poster_path'] as String?,
      seasonNumber: json['season_number'] as int? ?? 0,
      episodeCount: json['episode_count'] as int? ?? 0,
      airDate: json['air_date'] as String? ?? '',
    );

  final int id;
  final String name;
  final String overview;
  final String? posterPath;
  final int seasonNumber;
  final int episodeCount;
  final String airDate;

  String get posterUrl => TmdbService.getImageUrl(posterPath);
}

/// 剧集信息
class TmdbEpisode {
  TmdbEpisode({
    required this.id,
    required this.name,
    required this.overview,
    required this.stillPath,
    required this.episodeNumber,
    required this.seasonNumber,
    required this.airDate,
    required this.runtime,
    required this.voteAverage,
  });

  factory TmdbEpisode.fromJson(Map<String, dynamic> json) => TmdbEpisode(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      overview: json['overview'] as String? ?? '',
      stillPath: json['still_path'] as String?,
      episodeNumber: json['episode_number'] as int? ?? 0,
      seasonNumber: json['season_number'] as int? ?? 0,
      airDate: json['air_date'] as String? ?? '',
      runtime: json['runtime'] as int? ?? 0,
      voteAverage: (json['vote_average'] as num?)?.toDouble() ?? 0.0,
    );

  final int id;
  final String name;
  final String overview;
  final String? stillPath;
  final int episodeNumber;
  final int seasonNumber;
  final String airDate;
  final int runtime;
  final double voteAverage;

  String get stillUrl => TmdbService.getImageUrl(stillPath);
}

/// 类型
class TmdbGenre {
  TmdbGenre({required this.id, required this.name});

  factory TmdbGenre.fromJson(Map<String, dynamic> json) => TmdbGenre(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
    );

  final int id;
  final String name;
}

/// 国家/地区
class TmdbCountry {
  TmdbCountry({required this.iso31661, required this.name});

  factory TmdbCountry.fromJson(Map<String, dynamic> json) => TmdbCountry(
      iso31661: json['iso_3166_1'] as String? ?? '',
      name: json['name'] as String? ?? '',
    );

  final String iso31661;
  final String name;
}

/// 演员
class TmdbCast {
  TmdbCast({
    required this.id,
    required this.name,
    required this.character,
    required this.profilePath,
    required this.order,
  });

  factory TmdbCast.fromJson(Map<String, dynamic> json) => TmdbCast(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      character: json['character'] as String? ?? '',
      profilePath: json['profile_path'] as String?,
      order: json['order'] as int? ?? 0,
    );

  final int id;
  final String name;
  final String character;
  final String? profilePath;
  final int order;

  String get profileUrl => TmdbService.getImageUrl(profilePath, size: ImageSize.w185);
}

/// 剧组人员
class TmdbCrew {
  TmdbCrew({
    required this.id,
    required this.name,
    required this.job,
    required this.department,
    required this.profilePath,
  });

  factory TmdbCrew.fromJson(Map<String, dynamic> json) => TmdbCrew(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      job: json['job'] as String? ?? '',
      department: json['department'] as String? ?? '',
      profilePath: json['profile_path'] as String?,
    );

  final int id;
  final String name;
  final String job;
  final String department;
  final String? profilePath;

  String get profileUrl => TmdbService.getImageUrl(profilePath, size: ImageSize.w185);
}

/// 制作公司
class TmdbCompany {
  TmdbCompany({
    required this.id,
    required this.name,
    required this.logoPath,
    required this.originCountry,
  });

  factory TmdbCompany.fromJson(Map<String, dynamic> json) => TmdbCompany(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      logoPath: json['logo_path'] as String?,
      originCountry: json['origin_country'] as String? ?? '',
    );

  final int id;
  final String name;
  final String? logoPath;
  final String originCountry;

  String get logoUrl => TmdbService.getImageUrl(logoPath, size: ImageSize.w185);
}

/// 电视网络
class TmdbNetwork {
  TmdbNetwork({
    required this.id,
    required this.name,
    required this.logoPath,
    required this.originCountry,
  });

  factory TmdbNetwork.fromJson(Map<String, dynamic> json) => TmdbNetwork(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      logoPath: json['logo_path'] as String?,
      originCountry: json['origin_country'] as String? ?? '',
    );

  final int id;
  final String name;
  final String? logoPath;
  final String originCountry;

  String get logoUrl => TmdbService.getImageUrl(logoPath, size: ImageSize.w185);
}

/// 电影系列/合集信息 (基础信息，在电影详情中返回)
class TmdbCollectionInfo {
  TmdbCollectionInfo({
    required this.id,
    required this.name,
    required this.posterPath,
    required this.backdropPath,
  });

  factory TmdbCollectionInfo.fromJson(Map<String, dynamic> json) => TmdbCollectionInfo(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
    );

  final int id;
  final String name;
  final String? posterPath;
  final String? backdropPath;

  String get posterUrl => TmdbService.getImageUrl(posterPath);
  String get backdropUrl => TmdbService.getImageUrl(backdropPath, size: ImageSize.w780);
}

/// 电影系列/合集详情 (包含所有电影)
class TmdbCollection {
  TmdbCollection({
    required this.id,
    required this.name,
    required this.overview,
    required this.posterPath,
    required this.backdropPath,
    required this.parts,
  });

  factory TmdbCollection.fromJson(Map<String, dynamic> json) => TmdbCollection(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      overview: json['overview'] as String? ?? '',
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      parts: (json['parts'] as List?)
              ?.map((e) => TmdbCollectionPart.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );

  final int id;
  final String name;
  final String overview;
  final String? posterPath;
  final String? backdropPath;
  final List<TmdbCollectionPart> parts;

  String get posterUrl => TmdbService.getImageUrl(posterPath);
  String get backdropUrl => TmdbService.getImageUrl(backdropPath, size: ImageSize.w780);

  /// 按发布日期排序的电影列表
  List<TmdbCollectionPart> get sortedParts {
    final sorted = List<TmdbCollectionPart>.from(parts)
    ..sort((a, b) => a.releaseDate.compareTo(b.releaseDate));
    return sorted;
  }
}

/// 合集中的电影
class TmdbCollectionPart {
  TmdbCollectionPart({
    required this.id,
    required this.title,
    required this.originalTitle,
    required this.overview,
    required this.posterPath,
    required this.backdropPath,
    required this.releaseDate,
    required this.voteAverage,
    required this.voteCount,
  });

  factory TmdbCollectionPart.fromJson(Map<String, dynamic> json) => TmdbCollectionPart(
      id: json['id'] as int,
      title: json['title'] as String? ?? '',
      originalTitle: json['original_title'] as String? ?? '',
      overview: json['overview'] as String? ?? '',
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      releaseDate: json['release_date'] as String? ?? '',
      voteAverage: (json['vote_average'] as num?)?.toDouble() ?? 0.0,
      voteCount: json['vote_count'] as int? ?? 0,
    );

  final int id;
  final String title;
  final String originalTitle;
  final String overview;
  final String? posterPath;
  final String? backdropPath;
  final String releaseDate;
  final double voteAverage;
  final int voteCount;

  String get posterUrl => TmdbService.getImageUrl(posterPath);
  String get backdropUrl => TmdbService.getImageUrl(backdropPath, size: ImageSize.w780);

  int? get year {
    if (releaseDate.isEmpty) return null;
    return int.tryParse(releaseDate.split('-').first);
  }

  String get ratingText => voteAverage.toStringAsFixed(1);
}
