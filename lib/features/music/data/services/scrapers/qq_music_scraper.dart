import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_result.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_source.dart';
import 'package:my_nas/features/music/domain/interfaces/music_scraper.dart';

/// QQ音乐刮削器
///
/// 使用 QQ音乐 API 获取元数据、封面和歌词
class QQMusicScraper implements MusicScraper {
  QQMusicScraper({
    this.cookie,
  }) {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Referer': 'https://y.qq.com/',
        'Origin': 'https://y.qq.com',
        if (cookie != null && cookie!.isNotEmpty) 'Cookie': cookie,
      },
    ));

    // QQ音乐可能使用腾讯云 CDN，可能存在证书域名不匹配问题
    // 仅针对 QQ 音乐的请求跳过 SSL 验证
    // Web 平台使用浏览器的 HTTP 实现，不需要此配置
    if (!kIsWeb) {
      _dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient()
          ..badCertificateCallback = (cert, host, port) => host.endsWith('.qq.com') ||
                   host.endsWith('.myqcloud.com') ||
                   host == 'y.qq.com' ||
                   host == 'c.y.qq.com';
          return client;
        },
      );
    }
  }

  static const String _searchUrl = 'https://c.y.qq.com/soso/fcgi-bin/client_search_cp';
  static const String _songDetailUrl = 'https://c.y.qq.com/v8/fcg-bin/fcg_play_single_song.fcg';
  static const String _lyricUrl = 'https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg';

  final String? cookie;
  late final Dio _dio;

  /// 上次请求时间
  DateTime? _lastRequestTime;

  /// 最小请求间隔
  static const Duration _minInterval = Duration(milliseconds: 500);

  @override
  MusicScraperType get type => MusicScraperType.qqMusic;

  @override
  bool get isConfigured => true; // Cookie 可选

  @override
  Future<bool> testConnection() async {
    try {
      final _ = await search('test', limit: 1);
      return true;
    } on Exception {
      return false;
    }
  }

  @override
  Future<MusicScraperSearchResult> search(
    String query, {
    String? artist,
    String? album,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      // 构建搜索关键词
      var searchQuery = query;
      if (artist != null && artist.isNotEmpty) {
        searchQuery += ' $artist';
      }
      if (album != null && album.isNotEmpty) {
        searchQuery += ' $album';
      }

      final response = await _rateLimitedRequest(() => _dio.get<dynamic>(
            _searchUrl,
            queryParameters: {
              'w': searchQuery,
              'p': page,
              'n': limit,
              'format': 'json',
              'inCharset': 'utf8',
              'outCharset': 'utf-8',
              'platform': 'yqq.json',
              'needNewCode': 0,
            },
          ));

      // QQ音乐返回的是 JSONP，需要处理
      var dataStr = response.data.toString();
      if (dataStr.startsWith('callback(')) {
        dataStr = dataStr.substring(9, dataStr.length - 1);
      }

      final data = json.decode(dataStr) as Map<String, dynamic>;
      final dataContent = data['data'] as Map<String, dynamic>?;
      final songData = dataContent?['song'] as Map<String, dynamic>?;

      if (songData == null) {
        return MusicScraperSearchResult.empty(type);
      }

      final songs = (songData['list'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final totalNum = songData['totalnum'] as int? ?? 0;

      final items = songs.map(_parseSong).toList();

      return MusicScraperSearchResult(
        items: items,
        source: type,
        page: page,
        totalPages: (totalNum / limit).ceil(),
        totalResults: totalNum,
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    } on FormatException catch (e) {
      throw MusicScraperException(
        appL10n.qqMusicScraperParseResponseFailed(e),
        source: type,
        cause: e,
      );
    }
  }

  @override
  Future<MusicScraperDetail?> getDetail(String externalId) async {
    try {
      final response = await _rateLimitedRequest(() => _dio.get<dynamic>(
            _songDetailUrl,
            queryParameters: {
              'songmid': externalId,
              'format': 'json',
              'inCharset': 'utf8',
              'outCharset': 'utf-8',
              'platform': 'yqq.json',
            },
          ));

      // 检查返回数据类型
      if (response.data is! Map<String, dynamic>) {
        logger.w('QQMusicScraper: getDetail 返回非 JSON 数据: ${response.data.runtimeType}');
        return null;
      }

      final data = response.data as Map<String, dynamic>;
      final songs = (data['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      if (songs.isEmpty) {
        return null;
      }

      return _parseSongDetail(songs.first);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null;
      }
      throw _handleDioError(e);
    }
  }

  @override
  Future<List<CoverScraperResult>> getCoverArt(String externalId) async {
    try {
      final detail = await getDetail(externalId);
      if (detail?.coverUrl == null) {
        return [];
      }

      return [
        CoverScraperResult(
          source: type,
          coverUrl: detail!.coverUrl!,
          thumbnailUrl: detail.coverUrl!.replaceAll('300x300', '150x150'),
          type: CoverType.front,
        ),
      ];
    } on Exception {
      return [];
    }
  }

  @override
  Future<LyricScraperResult?> getLyrics(String externalId) async {
    try {
      final response = await _rateLimitedRequest(() => _dio.get<dynamic>(
            _lyricUrl,
            queryParameters: {
              'songmid': externalId,
              'format': 'json',
              'nobase64': 1,
              'g_tk': 5381,
            },
            options: Options(
              headers: {
                'Referer': 'https://y.qq.com/portal/player.html',
              },
            ),
          ));

      // 检查返回数据类型，API 可能返回字符串（错误信息或 HTML）
      if (response.data is! Map<String, dynamic>) {
        logger.w('QQMusicScraper: getLyrics 返回非 JSON 数据: ${response.data.runtimeType}');
        return null;
      }

      final data = response.data as Map<String, dynamic>;

      // 检查返回码
      final retcode = data['retcode'] as int? ?? data['code'] as int? ?? -1;
      if (retcode != 0) {
        return null;
      }

      // 原文歌词
      var lyric = data['lyric'] as String?;
      if (lyric != null && lyric.isNotEmpty) {
        // 如果是 Base64 编码
        try {
          lyric = utf8.decode(base64.decode(lyric));
        } on Exception {
          // 不是 Base64，直接使用
        }
      }

      // 翻译歌词
      var trans = data['trans'] as String?;
      if (trans != null && trans.isNotEmpty) {
        try {
          trans = utf8.decode(base64.decode(trans));
        } on Exception {
          // 不是 Base64，直接使用
        }
      }

      if (lyric == null || lyric.isEmpty) {
        return null;
      }

      return LyricScraperResult(
        source: type,
        lrcContent: lyric,
        translation: trans,
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  @override
  void dispose() {
    _dio.close();
  }

  /// 速率限制请求
  Future<Response<T>> _rateLimitedRequest<T>(
    Future<Response<T>> Function() request,
  ) async {
    if (_lastRequestTime != null) {
      final elapsed = DateTime.now().difference(_lastRequestTime!);
      if (elapsed < _minInterval) {
        await Future<void>.delayed(_minInterval - elapsed);
      }
    }
    _lastRequestTime = DateTime.now();
    return request();
  }

  /// 解析歌曲搜索结果
  MusicScraperItem _parseSong(Map<String, dynamic> data) {
    final mid = data['songmid'] as String? ?? data['mid'] as String? ?? '';
    final name = data['songname'] as String? ?? data['name'] as String? ?? '';

    // 艺术家
    final singers = (data['singer'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final artist = singers
        .map((s) => s['name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .join(' / ');

    // 专辑
    final albumMid = data['albummid'] as String?;
    final albumName = data['albumname'] as String?;

    // 封面 URL
    String? coverUrl;
    if (albumMid != null && albumMid.isNotEmpty) {
      coverUrl = 'https://y.qq.com/music/photo_new/T002R300x300M000$albumMid.jpg';
    }

    // 时长（秒转毫秒）
    final interval = data['interval'] as int?;
    final durationMs = interval != null ? interval * 1000 : null;

    return MusicScraperItem(
      externalId: mid,
      source: type,
      title: name,
      artist: artist.isEmpty ? null : artist,
      album: albumName,
      durationMs: durationMs,
      coverUrl: coverUrl,
    );
  }

  /// 解析歌曲详情
  MusicScraperDetail _parseSongDetail(Map<String, dynamic> data) {
    final mid = data['mid'] as String? ?? '';
    final name = data['name'] as String? ?? '';

    // 艺术家
    final singers = (data['singer'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final artist = singers
        .map((s) => s['name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .join(' / ');

    // 专辑信息
    final album = data['album'] as Map<String, dynamic>?;
    final albumMid = album?['mid'] as String?;
    final albumName = album?['name'] as String?;

    // 封面 URL
    String? coverUrl;
    if (albumMid != null && albumMid.isNotEmpty) {
      coverUrl = 'https://y.qq.com/music/photo_new/T002R300x300M000$albumMid.jpg';
    }

    // 时长（秒转毫秒）
    final interval = data['interval'] as int?;
    final durationMs = interval != null ? interval * 1000 : null;

    // 音轨号
    final trackNumber = data['index_album'] as int?;

    // 碟号
    final discNumber = data['index_cd'] as int?;

    // 流派 - API 可能返回 String 或 int（流派 ID）
    String? genre;
    final genreValue = data['genre'];
    if (genreValue is String) {
      genre = genreValue;
    } else if (genreValue is int) {
      // 如果是 int，转换为字符串或忽略
      genre = null; // QQ音乐返回的是流派 ID，无法直接使用
    }

    // 发行时间
    final pubTime = data['time_public'] as String?;
    int? year;
    if (pubTime != null && pubTime.length >= 4) {
      year = int.tryParse(pubTime.substring(0, 4));
    }

    return MusicScraperDetail(
      externalId: mid,
      source: type,
      title: name,
      artist: artist.isEmpty ? null : artist,
      album: albumName,
      durationMs: durationMs,
      coverUrl: coverUrl,
      trackNumber: trackNumber,
      discNumber: discNumber,
      year: year,
      genres: genre != null && genre.isNotEmpty ? [genre] : null,
      releaseDate: pubTime,
    );
  }

  /// 处理 Dio 错误
  MusicScraperException _handleDioError(DioException e) {
    // 构建详细的错误信息用于调试
    final statusCode = e.response?.statusCode;
    final statusMessage = e.response?.statusMessage;
    final responseData = e.response?.data;
    final requestUrl = e.requestOptions.uri.toString();

    // 记录详细日志
    debugPrint('[QQMusicScraper] DioException: ${e.type}');
    debugPrint('[QQMusicScraper] Request URL: $requestUrl');
    debugPrint('[QQMusicScraper] Status: $statusCode $statusMessage');
    debugPrint('[QQMusicScraper] Response: $responseData');
    debugPrint('[QQMusicScraper] Error: ${e.error}');
    debugPrint('[QQMusicScraper] Message: ${e.message}');

    if (statusCode == 401 || statusCode == 403) {
      return MusicScraperAuthException(
        appL10n.qqMusicScraperCookieInvalidOrExpired,
        source: type,
        cause: e,
      );
    }
    if (statusCode == 429) {
      return MusicScraperRateLimitException(
        appL10n.qqMusicScraperRateLimit,
        source: type,
        cause: e,
      );
    }

    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      final errorDetail = e.error?.toString() ?? '';
      return MusicScraperNetworkException(
        errorDetail.isNotEmpty
            ? appL10n.qqMusicScraperNetworkErrorWithDetails(e.type.name, errorDetail)
            : appL10n.qqMusicScraperNetworkError(e.type.name),
        source: type,
        cause: e,
      );
    }

    // 构建更详细的错误信息
    String errorMessage;
    if (statusCode != null) {
      errorMessage = 'HTTP $statusCode';
      if (statusMessage != null && statusMessage.isNotEmpty) {
        errorMessage += ' $statusMessage';
      }
      // 尝试从响应中提取错误信息
      if (responseData is Map<String, dynamic>) {
        final errMsg = responseData['errcode'] ?? responseData['error'] ?? responseData['message'];
        if (errMsg != null) {
          errorMessage += ': $errMsg';
        }
      }
    } else {
      errorMessage = e.message ?? e.error?.toString() ?? appL10n.qqMusicScraperUnknownError(e.type.name);
    }

    return MusicScraperException(
      errorMessage,
      source: type,
      cause: e,
    );
  }
}
