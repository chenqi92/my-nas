import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/features/music/data/services/scrapers/scraper_debug.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_result.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_source.dart';
import 'package:my_nas/features/music/domain/interfaces/music_scraper.dart';

/// 咪咕音乐刮削器
///
/// 使用咪咕音乐 API 获取元数据、封面和歌词
/// 咪咕音乐是中国移动旗下的音乐平台，无损音源丰富
class MiguScraper implements MusicScraper {
  MiguScraper() {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Referer': 'https://music.migu.cn/',
        },
      ),
    );
  }

  // 咪咕搜索 API
  static const String _searchUrl =
      'https://m.music.migu.cn/migu/remoting/scr_search_tag';
  // 咪咕歌词 API
  static const String _lyricUrl =
      'https://music.migu.cn/v3/api/music/audioPlayer/getLyric';

  late final Dio _dio;

  /// 上次请求时间
  DateTime? _lastRequestTime;

  /// 最小请求间隔
  static const Duration _minInterval = Duration(milliseconds: 300);

  @override
  MusicScraperType get type => MusicScraperType.miguMusic;

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

      scraperDebug(
        '[MiguScraper] search: query=$searchQuery, page=$page, limit=$limit',
      );

      final response = await _rateLimitedRequest(
        () => _dio.get<dynamic>(
          _searchUrl,
          queryParameters: {
            'keyword': searchQuery,
            'pgc': page,
            'rows': limit,
            'type': 2, // 2 表示歌曲搜索
          },
        ),
      );

      scraperDebug('[MiguScraper] response status: ${response.statusCode}');

      // 处理响应数据
      if (response.data == null) {
        scraperDebug('[MiguScraper] Response data is null');
        return MusicScraperSearchResult.empty(type);
      }

      Map<String, dynamic> data;

      // 如果 Dio 已自动解析为 Map，直接使用
      if (response.data is Map<String, dynamic>) {
        data = response.data as Map<String, dynamic>;
        scraperDebug(
          '[MiguScraper] Response is Map, keys: ${data.keys.take(5).join(', ')}...',
        );
      } else if (response.data is String) {
        final responseStr = response.data as String;
        // 打印前200字符用于调试
        scraperDebug(
          '[MiguScraper] Response preview: ${responseStr.substring(0, responseStr.length > 200 ? 200 : responseStr.length)}',
        );

        try {
          data = json.decode(responseStr) as Map<String, dynamic>;
        } on FormatException catch (e) {
          scraperDebug('[MiguScraper] Failed to parse JSON: $e');
          return MusicScraperSearchResult.empty(type);
        }
      } else {
        scraperDebug(
          '[MiguScraper] Invalid response type: ${response.data.runtimeType}',
        );
        return MusicScraperSearchResult.empty(type);
      }

      final success = data['success'] as bool? ?? false;
      if (!success) {
        scraperDebug('[MiguScraper] API returned error');
        return MusicScraperSearchResult.empty(type);
      }

      final songs =
          (data['musics'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .toList() ??
          [];
      final total = int.tryParse(data['pgt']?.toString() ?? '0') ?? 0;

      scraperDebug(
        '[MiguScraper] Found ${songs.length} songs, totalPages: $total',
      );

      final items = songs.map(_parseSong).toList();

      return MusicScraperSearchResult(
        items: items,
        source: type,
        page: page,
        totalPages: total,
        totalResults: total * limit,
      );
    } on DioException catch (e) {
      scraperDebug(
        '[MiguScraper] DioException: ${e.type}, message: ${e.message}',
      );
      throw _handleDioError(e);
    } on Exception catch (e, st) {
      scraperDebug('[MiguScraper] Exception: $e');
      scraperDebug('[MiguScraper] StackTrace: $st');
      rethrow;
    }
  }

  @override
  Future<MusicScraperDetail?> getDetail(String externalId) async {
    // externalId 格式: copyrightId|songName|artist|albumName|albumId|cover|duration
    final parts = externalId.split('|');
    if (parts.length < 6) return null;

    // parts[0] 是 copyrightId，用于歌词查询
    // parts[4] 是 albumId，暂未使用
    final songName = parts[1];
    final artistName = parts[2];
    final albumName = parts[3];
    final cover = parts[5];
    final durationSec = parts.length > 6 ? int.tryParse(parts[6]) ?? 0 : 0;

    return MusicScraperDetail(
      externalId: externalId,
      source: type,
      title: songName,
      artist: artistName.isEmpty ? null : artistName,
      album: albumName.isEmpty ? null : albumName,
      durationMs: durationSec > 0 ? durationSec * 1000 : null,
      coverUrl: cover.isNotEmpty ? cover : null,
    );
  }

  @override
  Future<List<CoverScraperResult>> getCoverArt(String externalId) async {
    final parts = externalId.split('|');
    if (parts.length < 6) return [];

    final cover = parts[5];
    if (cover.isEmpty) return [];

    // 替换为高清图片
    final hdUrl = cover
        .replaceAll('_120', '_500')
        .replaceAll('/120/', '/500/')
        .replaceAll('_400', '_800')
        .replaceAll('/400/', '/800/');

    return [
      CoverScraperResult(
        source: type,
        coverUrl: hdUrl,
        thumbnailUrl: cover,
        type: CoverType.front,
      ),
    ];
  }

  @override
  Future<LyricScraperResult?> getLyrics(String externalId) async {
    try {
      final parts = externalId.split('|');
      if (parts.isEmpty) return null;

      final copyrightId = parts[0];
      final songName = parts.length > 1 ? parts[1] : '';
      final artistName = parts.length > 2 ? parts[2] : '';

      scraperDebug('[MiguScraper] getLyrics: copyrightId=$copyrightId');

      final response = await _rateLimitedRequest(
        () => _dio.get<dynamic>(
          _lyricUrl,
          queryParameters: {'copyrightId': copyrightId},
        ),
      );

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

      final returnCode = data['returnCode'] as String?;
      if (returnCode != '000000') {
        scraperDebug('[MiguScraper] Lyrics API error: returnCode=$returnCode');
        return null;
      }

      final lyric = data['lyric'] as String?;
      if (lyric == null || lyric.isEmpty) {
        return null;
      }

      return LyricScraperResult(
        source: type,
        lrcContent: lyric,
        title: songName,
        artist: artistName,
      );
    } on DioException catch (e) {
      scraperDebug('[MiguScraper] getLyrics DioException: ${e.message}');
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
    final copyrightId = data['copyrightId'] as String? ?? '';
    final songName =
        data['songName'] as String? ?? data['title'] as String? ?? '';
    final artistName =
        data['singerName'] as String? ?? data['artist'] as String? ?? '';
    final albumName = data['albumName'] as String? ?? '';
    final albumId = data['albumId'] as String? ?? '';
    final cover =
        data['cover'] as String? ?? data['albumPicM'] as String? ?? '';

    // 时长：咪咕返回秒数（兼容 int 和 String 类型）
    var duration = 0;
    final durationValue = data['duration'] ?? data['length'];
    if (durationValue is int) {
      duration = durationValue;
    } else if (durationValue != null) {
      duration = int.tryParse(durationValue.toString()) ?? 0;
    }

    // 构建 externalId: copyrightId|songName|artist|albumName|albumId|cover|duration
    final externalId =
        '$copyrightId|$songName|$artistName|$albumName|$albumId|$cover|$duration';

    return MusicScraperItem(
      externalId: externalId,
      source: type,
      title: songName,
      artist: artistName.isEmpty ? null : artistName,
      album: albumName.isEmpty ? null : albumName,
      durationMs: duration > 0 ? duration * 1000 : null,
      coverUrl: cover.isNotEmpty ? cover : null,
    );
  }

  /// 处理 Dio 错误
  MusicScraperException _handleDioError(DioException e) {
    final statusCode = e.response?.statusCode;

    scraperDebug('[MiguScraper] DioException: ${e.type}');
    scraperDebug('[MiguScraper] Status: $statusCode');
    scraperDebug('[MiguScraper] Error: ${e.error}');

    if (statusCode == 429) {
      return MusicScraperRateLimitException(
        appL10n.musicScraperMiguRateLimitError,
        source: type,
        cause: e,
      );
    }

    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return MusicScraperNetworkException(
        appL10n.musicScraperMiguNetworkError(e.type.name),
        source: type,
        cause: e,
      );
    }

    return MusicScraperException(
      e.message ?? appL10n.musicScraperMiguUnknownError,
      source: type,
      cause: e,
    );
  }
}
