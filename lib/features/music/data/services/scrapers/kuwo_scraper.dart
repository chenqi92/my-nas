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

/// 酷我音乐刮削器
///
/// 使用酷我音乐 API 获取元数据、封面和歌词
class KuwoScraper implements MusicScraper {
  KuwoScraper() {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148',
        'Accept': 'application/json, text/plain, */*',
      },
    ));

    // 酷我部分接口可能存在证书问题
    if (!kIsWeb) {
      _dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient()
            ..badCertificateCallback = (cert, host, port) =>
                host.endsWith('.kuwo.cn') ||
                host.endsWith('searchapi.kuwo.cn') ||
                host == 'www.kuwo.cn';
          return client;
        },
      );
    }
  }

  // 使用移动端搜索 API（无需 csrf token）
  static const String _searchUrl =
      'http://search.kuwo.cn/r.s';
  static const String _lyricUrl =
      'http://m.kuwo.cn/newh5/singles/songinfoandlrc';

  late final Dio _dio;

  /// 上次请求时间
  DateTime? _lastRequestTime;

  /// 最小请求间隔
  static const Duration _minInterval = Duration(milliseconds: 300);

  @override
  MusicScraperType get type => MusicScraperType.kuwoMusic;

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

      debugPrint(
          '[KuwoScraper] search: query=$searchQuery, page=$page, limit=$limit');

      final response = await _rateLimitedRequest(() => _dio.get<dynamic>(
            _searchUrl,
            queryParameters: {
              'all': searchQuery,
              'ft': 'music',
              'itemset': 'web_2013',
              'client': 'kt',
              'pn': page - 1, // 0-indexed
              'rn': limit,
              'rformat': 'json',
              'encoding': 'utf8',
            },
          ));

      debugPrint('[KuwoScraper] response status: ${response.statusCode}');

      // 处理响应数据 - 移动端 API 返回格式不同
      if (response.data == null) {
        debugPrint('[KuwoScraper] Response data is null');
        return MusicScraperSearchResult.empty(type);
      }

      Map<String, dynamic> data;

      // 如果 Dio 已自动解析为 Map，直接使用
      if (response.data is Map<String, dynamic>) {
        data = response.data as Map<String, dynamic>;
        debugPrint('[KuwoScraper] Response is Map, keys: ${data.keys.take(5).join(', ')}...');
      } else if (response.data is String) {
        final responseStr = response.data as String;
        // 打印前200字符用于调试
        debugPrint('[KuwoScraper] Response preview: ${responseStr.substring(0, responseStr.length > 200 ? 200 : responseStr.length)}');

        // 尝试直接解析 JSON
        try {
          data = json.decode(responseStr) as Map<String, dynamic>;
        } on FormatException {
          // 可能是 JSONP 格式，尝试提取 JSON 部分
          // 格式可能是: callback({...}) 或直接 {...}
          var jsonStr = responseStr;

          // 移除 JSONP callback 包装
          final jsonpMatch = RegExp(r'^\s*\w+\s*\(\s*([\s\S]*)\s*\)\s*;?\s*$').firstMatch(responseStr);
          if (jsonpMatch != null) {
            jsonStr = jsonpMatch.group(1)!;
          }

          // 尝试提取 JSON 对象
          final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(jsonStr);
          if (jsonMatch == null) {
            debugPrint('[KuwoScraper] Failed to extract JSON from response');
            return MusicScraperSearchResult.empty(type);
          }
          try {
            data = json.decode(jsonMatch.group(0)!) as Map<String, dynamic>;
          } on FormatException catch (e) {
            debugPrint('[KuwoScraper] Failed to parse JSON: $e');
            return MusicScraperSearchResult.empty(type);
          }
        }
      } else {
        debugPrint('[KuwoScraper] Invalid response type: ${response.data.runtimeType}');
        return MusicScraperSearchResult.empty(type);
      }

      // 检查是否有 abslist（移动端 API 格式）
      final abslist = data['abslist'] as List?;
      final songs = abslist?.whereType<Map<String, dynamic>>().toList() ?? [];
      final total = int.tryParse(data['TOTAL']?.toString() ?? '0') ?? 0;

      debugPrint('[KuwoScraper] Found ${songs.length} songs, total: $total');

      final items = songs.map(_parseSong).toList();

      return MusicScraperSearchResult(
        items: items,
        source: type,
        page: page,
        totalPages: (total / limit).ceil(),
        totalResults: total,
      );
    } on DioException catch (e) {
      debugPrint('[KuwoScraper] DioException: ${e.type}, message: ${e.message}');
      throw _handleDioError(e);
    } on Exception catch (e, st) {
      debugPrint('[KuwoScraper] Exception: $e');
      debugPrint('[KuwoScraper] StackTrace: $st');
      rethrow;
    }
  }

  @override
  Future<MusicScraperDetail?> getDetail(String externalId) async {
    // externalId 格式: rid|songName|artist|albumName|albumId|duration|pic
    final parts = externalId.split('|');
    if (parts.length < 6) return null;

    // parts[0] 是 rid，用于歌词查询
    final songName = parts[1];
    final artistName = parts[2];
    final albumName = parts[3];
    final albumId = parts[4];
    final duration = int.tryParse(parts[5]) ?? 0;
    final pic = parts.length > 6 ? parts[6] : '';

    // 获取封面：优先使用搜索结果中的封面 URL
    String? coverUrl;
    if (pic.isNotEmpty) {
      // 使用高清版本
      coverUrl = pic.replaceAll('/120/', '/300/').replaceAll('/240/', '/500/');
    } else if (albumId.isNotEmpty && albumId != '0') {
      coverUrl = 'http://img1.kuwo.cn/star/albumcover/300/$albumId.jpg';
    }

    return MusicScraperDetail(
      externalId: externalId,
      source: type,
      title: songName,
      artist: artistName.isEmpty ? null : artistName,
      album: albumName.isEmpty ? null : albumName,
      durationMs: duration * 1000,
      coverUrl: coverUrl,
    );
  }

  @override
  Future<List<CoverScraperResult>> getCoverArt(String externalId) async {
    final parts = externalId.split('|');
    if (parts.length < 5) return [];

    // 尝试从 externalId 获取封面图片 URL
    // 格式: rid|songName|artist|albumName|albumId|duration|pic
    String? picUrl;
    if (parts.length >= 7 && parts[6].isNotEmpty) {
      picUrl = parts[6];
    }

    if (picUrl != null && picUrl.isNotEmpty) {
      // 替换为高清图片
      final hdUrl = picUrl.replaceAll('/120/', '/500/').replaceAll('/300/', '/500/');
      return [
        CoverScraperResult(
          source: type,
          coverUrl: hdUrl,
          thumbnailUrl: picUrl,
          type: CoverType.front,
        ),
      ];
    }

    return [];
  }

  @override
  Future<LyricScraperResult?> getLyrics(String externalId) async {
    try {
      final parts = externalId.split('|');
      if (parts.isEmpty) return null;

      final rid = parts[0];
      final songName = parts.length > 1 ? parts[1] : '';
      final artistName = parts.length > 2 ? parts[2] : '';

      debugPrint('[KuwoScraper] getLyrics: rid=$rid');

      final response = await _rateLimitedRequest(() => _dio.get<dynamic>(
            _lyricUrl,
            queryParameters: {
              'musicId': rid,
            },
          ));

      if (response.data == null) {
        return null;
      }

      Map<String, dynamic> data;
      if (response.data is String) {
        try {
          data = json.decode(response.data as String) as Map<String, dynamic>;
        } on FormatException {
          return null;
        }
      } else if (response.data is Map<String, dynamic>) {
        data = response.data as Map<String, dynamic>;
      } else {
        return null;
      }

      final status = data['status'] as int?;
      if (status != 200) {
        debugPrint('[KuwoScraper] Lyrics API error: status=$status');
        return null;
      }

      final dataSection = data['data'] as Map<String, dynamic>?;
      if (dataSection == null) {
        return null;
      }

      final lrcList =
          (dataSection['lrclist'] as List?)?.whereType<Map<String, dynamic>>().toList();

      if (lrcList == null || lrcList.isEmpty) {
        return null;
      }

      // 将歌词列表转换为 LRC 格式
      final lrcBuffer = StringBuffer();
      for (final line in lrcList) {
        final time = line['time'] as String? ?? '0';
        final text = line['lineLyric'] as String? ?? '';
        final seconds = double.tryParse(time) ?? 0;
        final minutes = (seconds / 60).floor();
        final secs = seconds % 60;
        lrcBuffer.writeln(
            '[${minutes.toString().padLeft(2, '0')}:${secs.toStringAsFixed(2).padLeft(5, '0')}]$text');
      }

      final lrcContent = lrcBuffer.toString().trim();
      if (lrcContent.isEmpty) {
        return null;
      }

      return LyricScraperResult(
        source: type,
        lrcContent: lrcContent,
        title: songName,
        artist: artistName,
      );
    } on DioException catch (e) {
      debugPrint('[KuwoScraper] getLyrics DioException: ${e.message}');
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

  /// 解析歌曲搜索结果（兼容 web API 和移动端 API）
  MusicScraperItem _parseSong(Map<String, dynamic> data) {
    // 兼容两种 API 格式（web API 和移动端 API）
    // 移动端 API 使用大写字段名，如 MUSICRID, NAME, ARTIST 等
    var rid = data['rid']?.toString() ?? '';
    if (rid.isEmpty) {
      // 移动端 API 格式: MUSICRID 或 DC_TARGETID 包含 "MUSIC_" 前缀
      rid = (data['MUSICRID'] as String? ?? data['DC_TARGETID'] as String? ?? '')
          .replaceFirst('MUSIC_', '');
    }

    final songName = data['name'] as String? ??
        data['NAME'] as String? ??
        data['SONGNAME'] as String? ??
        '';
    final artistName = data['artist'] as String? ??
        data['ARTIST'] as String? ??
        '';
    final albumName = data['album'] as String? ??
        data['ALBUM'] as String? ??
        '';
    final albumId = data['albumid']?.toString() ??
        data['ALBUMID']?.toString() ??
        '0';

    // 时长：返回秒数（兼容 int 和 String 类型）
    var duration = 0;
    final durationValue = data['duration'] ?? data['DURATION'];
    if (durationValue is int) {
      duration = durationValue;
    } else if (durationValue != null) {
      duration = int.tryParse(durationValue.toString()) ?? 0;
    }

    // 封面图片
    final pic = data['pic'] as String? ??
        data['albumpic'] as String? ??
        data['web_albumpic_short'] as String? ??
        data['hts_MVPIC'] as String? ??
        '';

    // 构建 externalId: rid|songName|artist|albumName|albumId|duration|pic
    final externalId =
        '$rid|$songName|$artistName|$albumName|$albumId|$duration|$pic';

    // 封面 URL
    var coverUrl = pic.isNotEmpty ? pic : null;
    if (coverUrl == null && albumId.isNotEmpty && albumId != '0') {
      coverUrl = 'http://img1.kuwo.cn/star/albumcover/120/$albumId.jpg';
    }

    return MusicScraperItem(
      externalId: externalId,
      source: type,
      title: songName,
      artist: artistName.isEmpty ? null : artistName,
      album: albumName.isEmpty ? null : albumName,
      durationMs: duration * 1000,
      coverUrl: coverUrl,
    );
  }

  /// 处理 Dio 错误
  MusicScraperException _handleDioError(DioException e) {
    final statusCode = e.response?.statusCode;

    debugPrint('[KuwoScraper] DioException: ${e.type}');
    debugPrint('[KuwoScraper] Status: $statusCode');
    debugPrint('[KuwoScraper] Error: ${e.error}');

    if (statusCode == 429) {
      return MusicScraperRateLimitException(
        appL10n.musicScraperKuwoRateLimitError,
        source: type,
        cause: e,
      );
    }

    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return MusicScraperNetworkException(
        appL10n.musicScraperKuwoNetworkError(e.type.name),
        source: type,
        cause: e,
      );
    }

    return MusicScraperException(
      e.message ?? appL10n.musicScraperKuwoUnknownError,
      source: type,
      cause: e,
    );
  }
}
