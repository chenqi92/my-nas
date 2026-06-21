import 'dart:async';

import 'package:dio/dio.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_result.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_source.dart';
import 'package:my_nas/features/music/domain/interfaces/music_scraper.dart';

/// MusicBrainz 刮削器
///
/// 使用 MusicBrainz JSON Web Service 2 API
/// 封面通过 Cover Art Archive 获取
/// 文档: https://musicbrainz.org/doc/MusicBrainz_API
class MusicBrainzScraper implements MusicScraper {
  MusicBrainzScraper({
    String? userAgent,
  }) : _userAgent = userAgent ?? 'MyNAS/1.0 (https://github.com/my-nas)' {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'Accept': 'application/json',
        'User-Agent': _userAgent,
      },
    ));

    _coverArtDio = Dio(BaseOptions(
      baseUrl: _coverArtBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'Accept': 'application/json',
        'User-Agent': _userAgent,
      },
    ));
  }

  static const String _baseUrl = 'https://musicbrainz.org/ws/2';
  static const String _coverArtBaseUrl = 'https://coverartarchive.org';

  final String _userAgent;
  late final Dio _dio;
  late final Dio _coverArtDio;

  /// 上次请求时间（用于速率限制）
  DateTime? _lastRequestTime;

  /// 最小请求间隔（1秒）
  static const Duration _minInterval = Duration(seconds: 1);

  @override
  MusicScraperType get type => MusicScraperType.musicBrainz;

  @override
  bool get isConfigured => true; // MusicBrainz 无需认证

  @override
  Future<bool> testConnection() async {
    try {
      await _rateLimitedRequest(() => _dio.get<dynamic>(
            '/recording',
            queryParameters: {
              'query': 'test',
              'limit': 1,
              'fmt': 'json',
            },
          ));
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
      // 构建 Lucene 查询
      final queryParts = <String>[query];
      if (artist != null && artist.isNotEmpty) {
        queryParts.add('artist:"$artist"');
      }
      if (album != null && album.isNotEmpty) {
        queryParts.add('release:"$album"');
      }

      final luceneQuery = queryParts.join(' AND ');
      final offset = (page - 1) * limit;

      final response = await _rateLimitedRequest(() => _dio.get<dynamic>(
            '/recording',
            queryParameters: {
              'query': luceneQuery,
              'limit': limit,
              'offset': offset,
              'fmt': 'json',
            },
          ));

      // 检查返回数据类型
      if (response.data is! Map<String, dynamic>) {
        logger.w('MusicBrainzScraper: search 返回非 JSON 数据: ${response.data.runtimeType}');
        return MusicScraperSearchResult.empty(type);
      }

      final data = response.data as Map<String, dynamic>;
      final recordings = (data['recordings'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final count = data['count'] as int? ?? 0;

      final items = recordings.map(_parseRecording).toList();

      return MusicScraperSearchResult(
        items: items,
        source: type,
        page: page,
        totalPages: (count / limit).ceil(),
        totalResults: count,
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  @override
  Future<MusicScraperDetail?> getDetail(String externalId) async {
    try {
      final response = await _rateLimitedRequest(() => _dio.get<dynamic>(
            '/recording/$externalId',
            queryParameters: {
              'inc': 'artists+releases+genres+isrcs+artist-credits',
              'fmt': 'json',
            },
          ));

      // 检查返回数据类型
      if (response.data is! Map<String, dynamic>) {
        logger.w('MusicBrainzScraper: getDetail 返回非 JSON 数据: ${response.data.runtimeType}');
        return null;
      }

      final data = response.data as Map<String, dynamic>;
      return _parseRecordingDetail(data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null;
      }
      throw _handleDioError(e);
    }
  }
  /// 通过 Cover Art Archive 获取封面
  /// externalId 可以是 recording ID 或 release ID
  @override
  Future<List<CoverScraperResult>> getCoverArt(String externalId) async {
    try {
      // 首先尝试作为 release ID 获取封面
      var releaseId = externalId;

      // 如果是 recording ID，需要先获取关联的 release ID
      try {
        final response = await _rateLimitedRequest(() => _dio.get<dynamic>(
              '/recording/$externalId',
              queryParameters: {
                'inc': 'releases',
                'fmt': 'json',
              },
            ));

        if (response.data is Map<String, dynamic>) {
          final data = response.data as Map<String, dynamic>;
          final releases =
              (data['releases'] as List?)?.cast<Map<String, dynamic>>();
          if (releases != null && releases.isNotEmpty) {
            final firstReleaseId = releases.first['id'] as String?;
            if (firstReleaseId != null && firstReleaseId.isNotEmpty) {
              releaseId = firstReleaseId;
            }
          }
        }
      } on DioException {
        // 如果获取失败，假设 externalId 就是 release ID
      }

      // 从 Cover Art Archive 获取封面
      final response = await _coverArtDio.get<dynamic>('/release/$releaseId');

      // 检查返回数据类型
      if (response.data is! Map<String, dynamic>) {
        logger.w('MusicBrainzScraper: getCoverArt 返回非 JSON 数据: ${response.data.runtimeType}');
        return [];
      }

      final data = response.data as Map<String, dynamic>;
      final images =
          (data['images'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      if (images.isEmpty) return [];

      final results = <CoverScraperResult>[];
      for (final image in images) {
        final imageUrl = image['image'] as String?;
        final thumbnails = image['thumbnails'] as Map<String, dynamic>?;
        final thumbnailUrl = thumbnails?['500'] as String? ??
            thumbnails?['250'] as String? ??
            thumbnails?['small'] as String?;

        // 确定封面类型
        final types = (image['types'] as List?)?.cast<String>() ?? [];
        var coverType = CoverType.other;
        if (types.contains('Front')) {
          coverType = CoverType.front;
        } else if (types.contains('Back')) {
          coverType = CoverType.back;
        } else if (types.contains('Booklet')) {
          coverType = CoverType.booklet;
        } else if (types.contains('Medium')) {
          coverType = CoverType.medium;
        }

        if (imageUrl != null) {
          results.add(CoverScraperResult(
            source: type,
            coverUrl: imageUrl,
            thumbnailUrl: thumbnailUrl,
            type: coverType,
          ));
        }
      }

      return results;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return [];
      }
      throw _handleDioError(e);
    }
  }

  /// MusicBrainz 不提供歌词
  @override
  Future<LyricScraperResult?> getLyrics(String externalId) async => null;

  @override
  void dispose() {
    _dio.close();
    _coverArtDio.close();
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

  /// 解析 Recording 搜索结果
  MusicScraperItem _parseRecording(Map<String, dynamic> data) {
    final id = data['id'] as String? ?? '';
    final title = data['title'] as String? ?? '';

    // 艺术家
    String? artist;
    final artistCredit = (data['artist-credit'] as List?)?.cast<Map<String, dynamic>>();
    if (artistCredit != null && artistCredit.isNotEmpty) {
      artist = artistCredit.map((ac) {
        final artistData = ac['artist'] as Map<String, dynamic>?;
        final name = ac['name'] as String? ?? artistData?['name'] as String? ?? '';
        final joinPhrase = ac['joinphrase'] as String? ?? '';
        return '$name$joinPhrase';
      }).join();
    }

    // 专辑（第一个 release）
    String? album;
    int? year;
    final releases = (data['releases'] as List?)?.cast<Map<String, dynamic>>();
    if (releases != null && releases.isNotEmpty) {
      final firstRelease = releases.first;
      album = firstRelease['title'] as String?;
      final date = firstRelease['date'] as String?;
      if (date != null && date.length >= 4) {
        year = int.tryParse(date.substring(0, 4));
      }
    }

    // 时长
    final lengthMs = data['length'] as int?;

    // 匹配分数
    final score = data['score'] as int?;

    return MusicScraperItem(
      externalId: id,
      source: type,
      title: title,
      artist: artist,
      album: album,
      year: year,
      durationMs: lengthMs,
      score: score != null ? score / 100 : null,
    );
  }

  /// 解析 Recording 详情
  MusicScraperDetail _parseRecordingDetail(Map<String, dynamic> data) {
    final id = data['id'] as String? ?? '';
    final title = data['title'] as String? ?? '';

    // 艺术家
    String? artist;
    final artistCredit = (data['artist-credit'] as List?)?.cast<Map<String, dynamic>>();
    if (artistCredit != null && artistCredit.isNotEmpty) {
      artist = artistCredit.map((ac) {
        final artistData = ac['artist'] as Map<String, dynamic>?;
        final name = ac['name'] as String? ?? artistData?['name'] as String? ?? '';
        final joinPhrase = ac['joinphrase'] as String? ?? '';
        return '$name$joinPhrase';
      }).join();
    }

    // 专辑信息
    String? album;
    String? albumArtist;
    int? year;
    int? trackNumber;
    int? discNumber;
    String? releaseDate;
    String? label;

    final releases = (data['releases'] as List?)?.cast<Map<String, dynamic>>();
    if (releases != null && releases.isNotEmpty) {
      final firstRelease = releases.first;
      album = firstRelease['title'] as String?;

      final date = firstRelease['date'] as String?;
      releaseDate = date;
      if (date != null && date.length >= 4) {
        year = int.tryParse(date.substring(0, 4));
      }

      // 唱片公司
      final labelInfo = (firstRelease['label-info'] as List?)?.cast<Map<String, dynamic>>();
      if (labelInfo != null && labelInfo.isNotEmpty) {
        final labelData = labelInfo.first['label'] as Map<String, dynamic>?;
        label = labelData?['name'] as String?;
      }

      // 音轨信息
      final media = (firstRelease['media'] as List?)?.cast<Map<String, dynamic>>();
      if (media != null && media.isNotEmpty) {
        for (var i = 0; i < media.length; i++) {
          final disc = media[i];
          final tracks = (disc['tracks'] as List?)?.cast<Map<String, dynamic>>();
          if (tracks != null) {
            for (final track in tracks) {
              final recording = track['recording'] as Map<String, dynamic>?;
              if (recording?['id'] == id) {
                trackNumber = track['position'] as int?;
                discNumber = i + 1;
                break;
              }
            }
          }
        }
      }

      // 专辑艺术家
      final releaseArtistCredit = (firstRelease['artist-credit'] as List?)?.cast<Map<String, dynamic>>();
      if (releaseArtistCredit != null && releaseArtistCredit.isNotEmpty) {
        albumArtist = releaseArtistCredit.map((ac) {
          final artistData = ac['artist'] as Map<String, dynamic>?;
          final name = ac['name'] as String? ?? artistData?['name'] as String? ?? '';
          final joinPhrase = ac['joinphrase'] as String? ?? '';
          return '$name$joinPhrase';
        }).join();
      }
    }

    // 时长
    final lengthMs = data['length'] as int?;

    // 流派
    final genres = (data['genres'] as List?)?.cast<Map<String, dynamic>>()
        .map((g) => g['name'] as String?)
        .where((name) => name != null && name.isNotEmpty)
        .cast<String>()
        .toList();

    // ISRC
    String? isrc;
    final isrcs = data['isrcs'] as List?;
    if (isrcs != null && isrcs.isNotEmpty) {
      isrc = isrcs.first as String?;
    }

    return MusicScraperDetail(
      externalId: id,
      source: type,
      title: title,
      artist: artist,
      albumArtist: albumArtist,
      album: album,
      year: year,
      trackNumber: trackNumber,
      discNumber: discNumber,
      durationMs: lengthMs,
      genres: genres,
      mbid: id,
      isrc: isrc,
      releaseDate: releaseDate,
      label: label,
    );
  }

  /// 处理 Dio 错误
  MusicScraperException _handleDioError(DioException e) {
    if (e.response?.statusCode == 401) {
      return MusicScraperAuthException(
        appL10n.musicBrainzAuthError,
        source: type,
        cause: e,
      );
    }
    if (e.response?.statusCode == 429) {
      final retryAfter = int.tryParse(
        e.response?.headers.value('retry-after') ?? '',
      );
      return MusicScraperRateLimitException(
        appL10n.musicBrainzRateLimitError,
        source: type,
        cause: e,
        retryAfter: retryAfter,
      );
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return MusicScraperNetworkException(
        appL10n.musicBrainzNetworkError,
        source: type,
        cause: e,
      );
    }
    return MusicScraperException(
      e.message ?? appL10n.musicBrainzGenericError,
      source: type,
      cause: e,
    );
  }
}
