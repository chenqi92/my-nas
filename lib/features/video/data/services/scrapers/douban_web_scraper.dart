import 'dart:async';

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/domain/entities/scraper_result.dart';
import 'package:my_nas/features/video/domain/entities/scraper_source.dart';
import 'package:my_nas/features/video/domain/interfaces/media_scraper.dart';

/// 豆瓣网页爬虫刮削器
///
/// 通过解析豆瓣网页获取影视信息
/// 注意：频繁请求可能触发验证码或被封禁
class DoubanWebScraper implements MediaScraper {
  DoubanWebScraper({
    required this.cookie,
    this.requestInterval = 3,
  });

  /// Cookie（登录后的 Cookie）
  final String cookie;

  /// 请求间隔（秒）
  final int requestInterval;

  static const String _movieBaseUrl = 'https://movie.douban.com';
  static const String _searchUrl = 'https://search.douban.com/movie/subject_search';
  static const Duration _requestTimeout = Duration(seconds: 20);

  DateTime? _lastRequestTime;

  @override
  ScraperType get type => ScraperType.doubanWeb;

  @override
  bool get isConfigured => cookie.isNotEmpty;

  /// 获取请求头
  Map<String, String> get _headers => {
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Cookie': cookie,
        'Referer': _movieBaseUrl,
      };

  /// 等待请求间隔
  Future<void> _waitForRateLimit() async {
    if (_lastRequestTime != null && requestInterval > 0) {
      final elapsed = DateTime.now().difference(_lastRequestTime!).inSeconds;
      if (elapsed < requestInterval) {
        await Future<void>.delayed(
          Duration(seconds: requestInterval - elapsed),
        );
      }
    }
    _lastRequestTime = DateTime.now();
  }

  /// 带超时和速率限制的 HTTP GET 请求
  Future<http.Response> _httpGet(Uri uri) async {
    await _waitForRateLimit();
    return http.get(uri, headers: _headers).timeout(
          _requestTimeout,
          onTimeout: () => throw TimeoutException(appL10n.videoScraperDoubanRequestTimeout(uri)),
        );
  }

  @override
  Future<bool> testConnection() async {
    if (!isConfigured) return false;

    try {
      final uri = Uri.parse(_movieBaseUrl);
      final response = await _httpGet(uri);

      // 检查是否需要登录或被封禁
      if (response.statusCode == 200) {
        final body = response.body;
        // 检查是否被重定向到登录页
        if (body.contains('accounts.douban.com') ||
            body.contains('请先登录')) {
          logger.w('豆瓣 Cookie 已失效，需要重新登录');
          return false;
        }
        return true;
      }
      return false;
    } on Exception catch (e) {
      logger.w('豆瓣网页连接测试失败', e);
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
      return ScraperSearchResult.empty(ScraperType.doubanWeb);
    }

    try {
      final start = (page - 1) * 15; // 豆瓣每页 15 条
      final params = {
        'search_text': query,
        'start': start.toString(),
      };

      final uri = Uri.parse(_searchUrl).replace(queryParameters: params);
      final response = await _httpGet(uri);

      if (response.statusCode == 200) {
        return _parseSearchResult(response.body, isMovie: true, page: page);
      } else if (response.statusCode == 403) {
        throw ScraperAuthException(
          appL10n.videoScraperDoubanAuthInvalid,
          source: ScraperType.doubanWeb,
        );
      } else {
        logger.e('豆瓣网页搜索失败: ${response.statusCode}');
        return ScraperSearchResult.empty(ScraperType.doubanWeb);
      }
    } on ScraperException {
      rethrow;
    } on Exception catch (e) {
      logger.e('豆瓣网页搜索异常', e);
      return ScraperSearchResult.empty(ScraperType.doubanWeb);
    }
  }

  @override
  Future<ScraperSearchResult> searchTvShows(
    String query, {
    int page = 1,
    String? language,
    int? year,
  }) async => searchMovies(query, page: page, language: language, year: year); // 豆瓣搜索不区分电影和电视剧

  @override
  Future<ScraperMovieDetail?> getMovieDetail(
    String externalId, {
    String? language,
  }) async {
    if (!isConfigured) return null;

    try {
      final uri = Uri.parse('$_movieBaseUrl/subject/$externalId/');
      final response = await _httpGet(uri);

      if (response.statusCode == 200) {
        return _parseMovieDetail(response.body, externalId);
      } else {
        logger.e('豆瓣网页获取电影详情失败: ${response.statusCode}');
        return null;
      }
    } on Exception catch (e) {
      logger.e('豆瓣网页获取电影详情异常', e);
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
      final uri = Uri.parse('$_movieBaseUrl/subject/$externalId/');
      final response = await _httpGet(uri);

      if (response.statusCode == 200) {
        return _parseTvDetail(response.body, externalId);
      } else {
        logger.e('豆瓣网页获取电视剧详情失败: ${response.statusCode}');
        return null;
      }
    } on Exception catch (e) {
      logger.e('豆瓣网页获取电视剧详情异常', e);
      return null;
    }
  }

  @override
  Future<ScraperEpisodeDetail?> getEpisodeDetail(
    String tvId,
    int seasonNumber,
    int episodeNumber, {
    String? language,
  }) async => null; // 豆瓣网页不提供详细的剧集信息

  @override
  Future<ScraperSeasonDetail?> getSeasonDetail(
    String tvId,
    int seasonNumber, {
    String? language,
  }) async => null; // 豆瓣网页不提供详细的季信息

  @override
  void dispose() {
    // No resources to dispose
  }

  // === 解析方法 ===

  ScraperSearchResult _parseSearchResult(
    String html, {
    required bool isMovie,
    required int page,
  }) {
    final document = html_parser.parse(html);
    final items = <ScraperMediaItem>[];

    // 解析搜索结果列表
    // 豆瓣搜索结果页面结构: div.item-root
    final resultItems = document.querySelectorAll('.item-root');

    for (final item in resultItems) {
      try {
        // 提取链接和 ID
        final link = item.querySelector('a.cover-link');
        final href = link?.attributes['href'] ?? '';
        final id = _extractIdFromUrl(href);
        if (id == null) continue;

        // 提取标题
        final titleElement = item.querySelector('.title-text');
        final title = titleElement?.text.trim() ?? '';
        if (title.isEmpty) continue;

        // 提取海报
        final posterElement = item.querySelector('img');
        final posterUrl = posterElement?.attributes['src'] ?? '';

        // 提取年份和其他信息
        final metaElement = item.querySelector('.meta');
        final metaText = metaElement?.text ?? '';
        final year = _extractYearFromMeta(metaText);

        // 提取评分
        final ratingElement = item.querySelector('.rating_nums');
        final ratingText = ratingElement?.text.trim() ?? '';
        final rating = double.tryParse(ratingText);

        items.add(
          ScraperMediaItem(
            externalId: id,
            source: ScraperType.doubanWeb,
            title: title,
            posterUrl: posterUrl.isNotEmpty ? posterUrl : null,
            year: year,
            rating: rating,
            isMovie: true, // 豆瓣搜索结果无法区分电影和电视剧
          ),
        );
      } on Exception catch (e) {
        logger.w('解析豆瓣搜索结果项失败', e);
        continue;
      }
    }

    // 估算总页数（豆瓣搜索页没有明确的总数）
    final hasMore = document.querySelector('.next') != null;

    return ScraperSearchResult(
      items: items,
      source: ScraperType.doubanWeb,
      page: page,
      totalPages: hasMore ? page + 1 : page,
      totalResults: items.length,
    );
  }

  ScraperMovieDetail? _parseMovieDetail(String html, String id) {
    final document = html_parser.parse(html);

    try {
      // 标题
      final titleElement = document.querySelector('h1 span[property="v:itemreviewed"]');
      final title = titleElement?.text.trim() ?? '';
      if (title.isEmpty) return null;

      // 年份
      final yearElement = document.querySelector('h1 span.year');
      final yearText = yearElement?.text.replaceAll(RegExp('[()]'), '') ?? '';
      final year = int.tryParse(yearText);

      // 海报
      final posterElement = document.querySelector('#mainpic img');
      final posterUrl = posterElement?.attributes['src'];

      // 评分
      final ratingElement = document.querySelector('strong.rating_num');
      final rating = double.tryParse(ratingElement?.text.trim() ?? '');

      // 简介
      final summaryElement = document.querySelector('span[property="v:summary"]');
      final summary = summaryElement?.text.trim();

      // 类型
      final genreElements = document.querySelectorAll('span[property="v:genre"]');
      final genres = genreElements.map((e) => e.text.trim()).toList();

      // 导演
      final directorElement = document.querySelector('a[rel="v:directedBy"]');
      final director = directorElement?.text.trim();

      // 演员
      final castElements = document.querySelectorAll('a[rel="v:starring"]');
      final cast = castElements.take(10).map((e) => e.text.trim()).toList();

      // 时长
      final runtimeElement = document.querySelector('span[property="v:runtime"]');
      final runtimeText = runtimeElement?.attributes['content'] ?? runtimeElement?.text ?? '';
      final runtime = int.tryParse(runtimeText.replaceAll(RegExp(r'\D'), ''));

      return ScraperMovieDetail(
        externalId: id,
        source: ScraperType.doubanWeb,
        title: title,
        overview: summary,
        posterUrl: posterUrl,
        year: year,
        rating: rating,
        runtime: runtime,
        genres: genres.isNotEmpty ? genres : null,
        director: director,
        cast: cast.isNotEmpty ? cast : null,
      );
    } on Exception catch (e) {
      logger.e('解析豆瓣电影详情失败', e);
      return null;
    }
  }

  ScraperTvDetail? _parseTvDetail(String html, String id) {
    // 电视剧详情页结构与电影类似
    final movieDetail = _parseMovieDetail(html, id);
    if (movieDetail == null) return null;

    final document = html_parser.parse(html);

    // 尝试提取集数
    int? episodeCount;
    final infoElements = document.querySelectorAll('#info span.pl');
    for (final el in infoElements) {
      if (el.text.contains('集数')) {
        final nextText = el.nextElementSibling?.text ?? el.parent?.text ?? '';
        final match = RegExp(r'(\d+)').firstMatch(nextText);
        if (match != null) {
          episodeCount = int.tryParse(match.group(1) ?? '');
        }
        break;
      }
    }

    return ScraperTvDetail(
      externalId: id,
      source: ScraperType.doubanWeb,
      title: movieDetail.title,
      originalTitle: movieDetail.originalTitle,
      overview: movieDetail.overview,
      posterUrl: movieDetail.posterUrl,
      year: movieDetail.year,
      rating: movieDetail.rating,
      genres: movieDetail.genres,
      cast: movieDetail.cast,
      numberOfEpisodes: episodeCount,
    );
  }

  String? _extractIdFromUrl(String url) {
    // https://movie.douban.com/subject/1291546/ -> 1291546
    final match = RegExp(r'/subject/(\d+)').firstMatch(url);
    return match?.group(1);
  }

  int? _extractYearFromMeta(String meta) {
    // 从 "2023 / 中国大陆 / 剧情" 中提取年份
    final match = RegExp(r'(\d{4})').firstMatch(meta);
    if (match != null) {
      return int.tryParse(match.group(1) ?? '');
    }
    return null;
  }
}
