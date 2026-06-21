import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_result.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_source.dart';
import 'package:my_nas/features/music/domain/interfaces/music_scraper.dart';

/// 酷狗音乐刮削器
///
/// 使用酷狗音乐 API 获取元数据、封面和歌词
/// 歌词库丰富，特别是翻唱和小众歌曲
class KugouScraper implements MusicScraper {
  KugouScraper() {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      },
    ));

    // 酷狗 CDN 使用腾讯云，可能存在证书域名不匹配问题（*.cdn.myqcloud.com）
    // 仅针对酷狗的请求跳过 SSL 验证
    // Web 平台使用浏览器的 HTTP 实现，不需要此配置
    if (!kIsWeb) {
      _dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient()
          ..badCertificateCallback = (cert, host, port) => host.endsWith('.kugou.com') ||
                   host.endsWith('.myqcloud.com') ||
                   host == 'mobilecdn.kugou.com' ||
                   host == 'krcs.kugou.com' ||
                   host == 'lyrics.kugou.com' ||
                   host == 'imge.kugou.com';
          return client;
        },
      );
    }
  }

  static const String _searchUrl = 'https://mobilecdn.kugou.com/api/v3/search/song';
  static const String _lyricSearchUrl = 'https://krcs.kugou.com/search';
  static const String _lyricDownloadUrl = 'https://lyrics.kugou.com/download';

  late final Dio _dio;

  /// 上次请求时间
  DateTime? _lastRequestTime;

  /// 最小请求间隔
  static const Duration _minInterval = Duration(milliseconds: 300);

  @override
  MusicScraperType get type => MusicScraperType.kugouMusic;

  @override
  bool get isConfigured => true; // 无需认证

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

      debugPrint('[KugouScraper] search: query=$searchQuery, page=$page, limit=$limit');
      debugPrint('[KugouScraper] request URL: $_searchUrl');

      final response = await _rateLimitedRequest(() => _dio.get<dynamic>(
            _searchUrl,
            queryParameters: {
              'keyword': searchQuery,
              'page': page,
              'pagesize': limit,
              'showtype': 1,
            },
          ));

      debugPrint('[KugouScraper] response status: ${response.statusCode}');
      debugPrint('[KugouScraper] response data type: ${response.data.runtimeType}');
      debugPrint('[KugouScraper] response data: ${response.data}');

      // 处理响应数据 - 可能是 String 或 Map
      Map<String, dynamic> data;
      if (response.data == null) {
        debugPrint('[KugouScraper] Response data is null');
        return MusicScraperSearchResult.empty(type);
      } else if (response.data is String) {
        // 服务器可能返回 JSON 字符串，需要手动解析
        try {
          data = json.decode(response.data as String) as Map<String, dynamic>;
          debugPrint('[KugouScraper] Parsed JSON string to Map');
        } on FormatException catch (e) {
          debugPrint('[KugouScraper] Failed to parse JSON: $e');
          return MusicScraperSearchResult.empty(type);
        }
      } else if (response.data is Map<String, dynamic>) {
        data = response.data as Map<String, dynamic>;
      } else {
        debugPrint('[KugouScraper] Invalid response data format: ${response.data.runtimeType}');
        return MusicScraperSearchResult.empty(type);
      }
      final status = data['status'] as int?;
      final errcode = data['errcode'] as int?;
      debugPrint('[KugouScraper] status: $status, errcode: $errcode');

      if (status != 1) {
        debugPrint('[KugouScraper] API returned error status: $status, error: ${data['error']}');
        return MusicScraperSearchResult.empty(type);
      }

      final dataSection = data['data'] as Map<String, dynamic>?;
      if (dataSection == null) {
        debugPrint('[KugouScraper] No data section in response');
        return MusicScraperSearchResult.empty(type);
      }

      final songs = (dataSection['info'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .toList() ??
          [];
      final total = dataSection['total'] as int? ?? 0;

      debugPrint('[KugouScraper] Found ${songs.length} songs, total: $total');

      final items = songs.map(_parseSong).toList();

      return MusicScraperSearchResult(
        items: items,
        source: type,
        page: page,
        totalPages: (total / limit).ceil(),
        totalResults: total,
      );
    } on DioException catch (e) {
      debugPrint('[KugouScraper] DioException: ${e.type}, message: ${e.message}');
      debugPrint('[KugouScraper] Response: ${e.response?.data}');
      throw _handleDioError(e);
    } on Exception catch (e, st) {
      debugPrint('[KugouScraper] Exception: $e');
      debugPrint('[KugouScraper] StackTrace: $st');
      rethrow;
    }
  }

  @override
  Future<MusicScraperDetail?> getDetail(String externalId) async {
    // 酷狗的 externalId 格式: hash|albumId|songName|singerName|duration
    final parts = externalId.split('|');
    if (parts.length < 5) return null;

    // hash 用于歌词搜索，这里不需要
    final albumId = parts[1];
    final songName = parts[2];
    final singerName = parts[3];
    final duration = int.tryParse(parts[4]) ?? 0;

    // 获取封面
    String? coverUrl;
    if (albumId.isNotEmpty && albumId != '0') {
      coverUrl = 'https://imge.kugou.com/stdmusic/150/$albumId.jpg';
    }

    return MusicScraperDetail(
      externalId: externalId,
      source: type,
      title: songName,
      artist: singerName.isEmpty ? null : singerName,
      durationMs: duration * 1000,
      coverUrl: coverUrl,
    );
  }

  @override
  Future<List<CoverScraperResult>> getCoverArt(String externalId) async {
    final parts = externalId.split('|');
    if (parts.length < 2) return [];

    final albumId = parts[1];
    if (albumId.isEmpty || albumId == '0') return [];

    // 酷狗封面 URL 格式
    final coverUrl = 'https://imge.kugou.com/stdmusic/400/$albumId.jpg';
    final thumbnailUrl = 'https://imge.kugou.com/stdmusic/150/$albumId.jpg';

    return [
      CoverScraperResult(
        source: type,
        coverUrl: coverUrl,
        thumbnailUrl: thumbnailUrl,
        type: CoverType.front,
      ),
    ];
  }

  @override
  Future<LyricScraperResult?> getLyrics(String externalId) async {
    try {
      final parts = externalId.split('|');
      if (parts.length < 5) return null;

      final hash = parts[0];
      final songName = parts[2];
      final singerName = parts[3];
      final duration = int.tryParse(parts[4]) ?? 0;

      // 搜索歌词
      final searchResponse = await _rateLimitedRequest(() => _dio.get<dynamic>(
            _lyricSearchUrl,
            queryParameters: {
              'ver': 1,
              'man': 'yes',
              'client': 'mobi',
              'keyword': '$songName - $singerName',
              'duration': duration * 1000,
              'hash': hash,
            },
          ));

      if (searchResponse.data == null ||
          searchResponse.data is! Map<String, dynamic>) {
        return null;
      }

      final searchData = searchResponse.data as Map<String, dynamic>;
      final candidates =
          (searchData['candidates'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? [];

      if (candidates.isEmpty) {
        return null;
      }

      // 选择第一个候选歌词
      final candidate = candidates.first;
      final id = candidate['id'] as String?;
      final accesskey = candidate['accesskey'] as String?;

      if (id == null || accesskey == null) {
        return null;
      }

      // 下载歌词
      final downloadResponse = await _rateLimitedRequest(() => _dio.get<dynamic>(
            _lyricDownloadUrl,
            queryParameters: {
              'ver': 1,
              'client': 'pc',
              'id': id,
              'accesskey': accesskey,
              'fmt': 'lrc',
              'charset': 'utf8',
            },
          ));

      if (downloadResponse.data == null ||
          downloadResponse.data is! Map<String, dynamic>) {
        return null;
      }

      final downloadData = downloadResponse.data as Map<String, dynamic>;
      final content = downloadData['content'] as String?;

      if (content == null || content.isEmpty) {
        return null;
      }

      // Base64 解码歌词
      String lrcContent;
      try {
        lrcContent = utf8.decode(base64.decode(content));
      } on Exception {
        lrcContent = content;
      }

      if (lrcContent.isEmpty) {
        return null;
      }

      return LyricScraperResult(
        source: type,
        lrcContent: lrcContent,
        title: songName,
        artist: singerName,
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
    final hash = data['hash'] as String? ?? '';
    final songName = data['songname'] as String? ?? '';
    final singerName = data['singername'] as String? ?? '';
    final albumId = data['album_id']?.toString() ?? '0';
    final albumName = data['album_name'] as String?;
    final duration = data['duration'] as int? ?? 0;

    // 构建 externalId: hash|albumId|songName|singerName|duration
    final externalId = '$hash|$albumId|$songName|$singerName|$duration';

    // 封面 URL
    String? coverUrl;
    if (albumId.isNotEmpty && albumId != '0') {
      coverUrl = 'https://imge.kugou.com/stdmusic/150/$albumId.jpg';
    }

    return MusicScraperItem(
      externalId: externalId,
      source: type,
      title: songName,
      artist: singerName.isEmpty ? null : singerName,
      album: albumName,
      durationMs: duration * 1000,
      coverUrl: coverUrl,
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
    debugPrint('[KugouScraper] DioException: ${e.type}');
    debugPrint('[KugouScraper] Request URL: $requestUrl');
    debugPrint('[KugouScraper] Status: $statusCode $statusMessage');
    debugPrint('[KugouScraper] Response: $responseData');
    debugPrint('[KugouScraper] Error: ${e.error}');
    debugPrint('[KugouScraper] Message: ${e.message}');

    if (statusCode == 429) {
      return MusicScraperRateLimitException(
        appL10n.kugouScraperRateLimitError,
        source: type,
        cause: e,
      );
    }

    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      final errorDetail = e.error?.toString() ?? '';
      return MusicScraperNetworkException(
        appL10n.kugouScraperNetworkError(e.type.name, errorDetail.isNotEmpty ? ' ($errorDetail)' : ''),
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
      errorMessage = e.message ?? e.error?.toString() ?? appL10n.kugouScraperUnknownError(e.type.name);
    }

    return MusicScraperException(
      errorMessage,
      source: type,
      cause: e,
    );
  }
}
