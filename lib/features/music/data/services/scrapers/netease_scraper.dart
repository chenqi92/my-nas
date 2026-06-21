import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

// ignore: unused_import
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter/foundation.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_result.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_source.dart';
import 'package:my_nas/features/music/domain/interfaces/music_scraper.dart';

/// 网易云音乐刮削器
///
/// 使用网易云音乐 API 获取元数据、封面和歌词
class NeteaseScraper implements MusicScraper {
  NeteaseScraper({
    this.cookie,
  }) {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Referer': 'https://music.163.com/',
        'Origin': 'https://music.163.com',
        if (cookie != null && cookie!.isNotEmpty) 'Cookie': cookie,
      },
      contentType: 'application/x-www-form-urlencoded',
    ));

    // 网易云音乐可能使用 CDN，可能存在证书问题
    // 仅针对网易云音乐的请求跳过 SSL 验证
    // Web 平台使用浏览器的 HTTP 实现，不需要此配置
    if (!kIsWeb) {
      _dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient()
          ..badCertificateCallback = (cert, host, port) => host.endsWith('.163.com') ||
                host.endsWith('.netease.com') ||
                host == 'music.163.com';
          return client;
        },
      );
    }
  }

  static const String _baseUrl = 'https://music.163.com';

  final String? cookie;
  late final Dio _dio;

  /// 上次请求时间
  DateTime? _lastRequestTime;

  /// 最小请求间隔
  static const Duration _minInterval = Duration(milliseconds: 500);

  @override
  MusicScraperType get type => MusicScraperType.neteaseMusic;

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

      final offset = (page - 1) * limit;

      final params = {
        's': searchQuery,
        'type': 1, // 1: 单曲
        'limit': limit,
        'offset': offset,
      };

      debugPrint('[NeteaseScraper] search: query=$searchQuery, page=$page, limit=$limit');
      debugPrint('[NeteaseScraper] request URL: $_baseUrl/weapi/cloudsearch/get/web');

      final encryptedData = _encryptParams(params);
      debugPrint('[NeteaseScraper] encrypted params length: ${encryptedData.length}');
      debugPrint('[NeteaseScraper] encrypted params (first 200 chars): ${encryptedData.length > 200 ? encryptedData.substring(0, 200) : encryptedData}');

      final response = await _rateLimitedRequest(() => _dio.post<dynamic>(
            '$_baseUrl/weapi/cloudsearch/get/web',
            data: encryptedData,
          ));

      debugPrint('[NeteaseScraper] response status: ${response.statusCode}');
      debugPrint('[NeteaseScraper] response data type: ${response.data.runtimeType}');
      // 截断响应数据避免日志过长
      final dataStr = response.data.toString();
      debugPrint('[NeteaseScraper] response data (first 500 chars): ${dataStr.length > 500 ? dataStr.substring(0, 500) : dataStr}');

      // 处理响应数据 - 可能是 String 或 Map
      Map<String, dynamic> data;
      if (response.data == null) {
        debugPrint('[NeteaseScraper] Response data is null');
        return MusicScraperSearchResult.empty(type);
      } else if (response.data is String) {
        // 服务器可能返回 JSON 字符串，需要手动解析
        try {
          data = json.decode(response.data as String) as Map<String, dynamic>;
          debugPrint('[NeteaseScraper] Parsed JSON string to Map');
        } on FormatException catch (e) {
          debugPrint('[NeteaseScraper] Failed to parse JSON: $e');
          return MusicScraperSearchResult.empty(type);
        }
      } else if (response.data is Map<String, dynamic>) {
        data = response.data as Map<String, dynamic>;
      } else {
        debugPrint('[NeteaseScraper] Invalid response data format: ${response.data.runtimeType}');
        return MusicScraperSearchResult.empty(type);
      }

      // 检查返回码
      final code = data['code'] as int?;
      debugPrint('[NeteaseScraper] response code: $code');
      if (code != null && code != 200) {
        debugPrint('[NeteaseScraper] API returned error code: $code, message: ${data['message']}');
        // 如果加密 API 失败，尝试使用备用 API
        if (code == 50000005 || code == -460) {
          debugPrint('[NeteaseScraper] Trying fallback API...');
          return _searchWithFallbackApi(searchQuery, page: page, limit: limit);
        }
        return MusicScraperSearchResult.empty(type);
      }

      final result = data['result'] as Map<String, dynamic>?;
      if (result == null) {
        debugPrint('[NeteaseScraper] No result in response');
        return MusicScraperSearchResult.empty(type);
      }

      final songs = (result['songs'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? [];
      final songCount = result['songCount'] as int? ?? 0;

      debugPrint('[NeteaseScraper] Found ${songs.length} songs, total: $songCount');

      final items = songs.map(_parseSong).toList();

      return MusicScraperSearchResult(
        items: items,
        source: type,
        page: page,
        totalPages: (songCount / limit).ceil(),
        totalResults: songCount,
      );
    } on DioException catch (e) {
      debugPrint('[NeteaseScraper] DioException: ${e.type}, message: ${e.message}');
      debugPrint('[NeteaseScraper] Response: ${e.response?.data}');
      throw _handleDioError(e);
    } on Exception catch (e, st) {
      debugPrint('[NeteaseScraper] Exception: $e');
      debugPrint('[NeteaseScraper] StackTrace: $st');
      rethrow;
    }
  }

  @override
  Future<MusicScraperDetail?> getDetail(String externalId) async {
    try {
      final params = {
        'c': '[{"id":$externalId}]',
      };

      final response = await _rateLimitedRequest(() => _dio.post<dynamic>(
            '$_baseUrl/weapi/v3/song/detail',
            data: _encryptParams(params),
          ));

      // 检查响应数据是否有效
      if (response.data == null || response.data is! Map<String, dynamic>) {
        return null;
      }
      final data = response.data as Map<String, dynamic>;
      final songs = (data['songs'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? [];

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
          thumbnailUrl: '${detail.coverUrl}?param=300y300',
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
      final params = {
        'id': externalId,
        'lv': -1,
        'tv': -1,
        'kv': -1,
      };

      final response = await _rateLimitedRequest(() => _dio.post<dynamic>(
            '$_baseUrl/weapi/song/lyric',
            data: _encryptParams(params),
          ));

      // 检查响应数据是否有效
      if (response.data == null || response.data is! Map<String, dynamic>) {
        return null;
      }
      final data = response.data as Map<String, dynamic>;

      // 原文歌词
      final lrc = data['lrc'] as Map<String, dynamic>?;
      final lrcContent = lrc?['lyric'] as String?;

      // 翻译歌词
      final tlyric = data['tlyric'] as Map<String, dynamic>?;
      final translation = tlyric?['lyric'] as String?;

      if (lrcContent == null || lrcContent.isEmpty) {
        return null;
      }

      return LyricScraperResult(
        source: type,
        lrcContent: lrcContent,
        translation: translation,
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

  /// 备用搜索 API（不使用加密）
  Future<MusicScraperSearchResult> _searchWithFallbackApi(
    String query, {
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final offset = (page - 1) * limit;

      // 使用公开 API（无需加密）
      final response = await _rateLimitedRequest(() => _dio.get<dynamic>(
            '$_baseUrl/api/search/get',
            queryParameters: {
              's': query,
              'type': 1, // 1: 单曲
              'limit': limit,
              'offset': offset,
            },
          ));

      debugPrint('[NeteaseScraper] Fallback API response status: ${response.statusCode}');
      debugPrint('[NeteaseScraper] Fallback API response type: ${response.data.runtimeType}');

      // 处理响应数据
      Map<String, dynamic> data;
      if (response.data == null) {
        return MusicScraperSearchResult.empty(type);
      } else if (response.data is String) {
        try {
          data = json.decode(response.data as String) as Map<String, dynamic>;
        } on FormatException {
          return MusicScraperSearchResult.empty(type);
        }
      } else if (response.data is Map<String, dynamic>) {
        data = response.data as Map<String, dynamic>;
      } else {
        return MusicScraperSearchResult.empty(type);
      }

      final code = data['code'] as int?;
      debugPrint('[NeteaseScraper] Fallback API code: $code');

      if (code != null && code != 200) {
        return MusicScraperSearchResult.empty(type);
      }

      final result = data['result'] as Map<String, dynamic>?;
      if (result == null) {
        return MusicScraperSearchResult.empty(type);
      }

      final songs = (result['songs'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? [];
      final songCount = result['songCount'] as int? ?? 0;

      debugPrint('[NeteaseScraper] Fallback API found ${songs.length} songs');

      final items = songs.map(_parseSong).toList();

      return MusicScraperSearchResult(
        items: items,
        source: type,
        page: page,
        totalPages: (songCount / limit).ceil(),
        totalResults: songCount,
      );
    } on DioException catch (e) {
      debugPrint('[NeteaseScraper] Fallback API error: ${e.message}');
      throw _handleDioError(e);
    }
  }

  /// 解析歌曲搜索结果
  MusicScraperItem _parseSong(Map<String, dynamic> data) {
    final id = data['id'].toString();
    final name = data['name'] as String? ?? '';

    // 艺术家
    final artists = (data['ar'] as List?)?.cast<Map<String, dynamic>>() ??
        (data['artists'] as List?)?.cast<Map<String, dynamic>>() ??
        [];
    final artist = artists
        .map((a) => a['name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .join(' / ');

    // 专辑
    final album = data['al'] as Map<String, dynamic>? ??
        data['album'] as Map<String, dynamic>?;
    final albumName = album?['name'] as String?;
    final coverUrl = album?['picUrl'] as String?;

    // 时长
    final duration = data['dt'] as int? ?? data['duration'] as int?;

    return MusicScraperItem(
      externalId: id,
      source: type,
      title: name,
      artist: artist.isEmpty ? null : artist,
      album: albumName,
      durationMs: duration,
      coverUrl: coverUrl,
    );
  }

  /// 解析歌曲详情
  MusicScraperDetail _parseSongDetail(Map<String, dynamic> data) {
    final id = data['id'].toString();
    final name = data['name'] as String? ?? '';

    // 艺术家
    final artists = (data['ar'] as List?)?.cast<Map<String, dynamic>>() ??
        (data['artists'] as List?)?.cast<Map<String, dynamic>>() ??
        [];
    final artist = artists
        .map((a) => a['name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .join(' / ');

    // 专辑信息
    final album = data['al'] as Map<String, dynamic>? ??
        data['album'] as Map<String, dynamic>?;
    final albumName = album?['name'] as String?;
    final coverUrl = album?['picUrl'] as String?;

    // 时长
    final duration = data['dt'] as int? ?? data['duration'] as int?;

    // 音轨号
    final trackNumber = data['no'] as int?;

    // 碟号
    final discNumber = data['cd'] != null ? int.tryParse(data['cd'].toString()) : null;

    return MusicScraperDetail(
      externalId: id,
      source: type,
      title: name,
      artist: artist.isEmpty ? null : artist,
      album: albumName,
      durationMs: duration,
      coverUrl: coverUrl,
      trackNumber: trackNumber,
      discNumber: discNumber,
    );
  }

  /// 处理 Dio 错误
  MusicScraperException _handleDioError(DioException e) {
    if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
      return MusicScraperAuthException(
        appL10n.neteaseScraperAuthExpiredError,
        source: type,
        cause: e,
      );
    }
    if (e.response?.statusCode == 429) {
      return MusicScraperRateLimitException(
        appL10n.neteaseScraperRateLimitError,
        source: type,
        cause: e,
      );
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return MusicScraperNetworkException(
        appL10n.neteaseScraperNetworkError,
        source: type,
        cause: e,
      );
    }
    return MusicScraperException(
      (e.message?.isNotEmpty ?? false) ? e.message! : appL10n.neteaseScraperUnknownError,
      source: type,
      cause: e,
    );
  }

  // ===== 网易云 API 加密 =====

  static const String _secretKey = '0CoJUm6Qyw8W8jud';
  static const String _iv = '0102030405060708';
  static const String _pubKey =
      '010001';
  static const String _modulus =
      '00e0b509f6259df8642dbc35662901477df22677ec152b5ff68ace615bb7b725152b3ab17a876aea8a5aa76d2e417629ec4ee341f56135fccf695280104e0312ecbda92557c93870114af6c9d05c4f7f0c3685b7a46bee255932575cce10b424d813cfe4875d3e82047b97ddef52741d546b8e289dc6935b3ece0462db0a22b8e7';

  /// 加密请求参数
  String _encryptParams(Map<String, dynamic> params) {
    final text = json.encode(params);

    // 生成随机 16 位字符串
    final secKey = _createSecretKey(16);

    // 两次 AES 加密
    final encText = _aesEncrypt(_aesEncrypt(text, _secretKey), secKey);

    // RSA 加密 secKey
    final encSecKey = _rsaEncrypt(secKey.split('').reversed.join(), _pubKey, _modulus);

    return 'params=${Uri.encodeComponent(encText)}&encSecKey=$encSecKey';
  }

  /// AES 加密
  String _aesEncrypt(String text, String secKey) {
    final key = encrypt.Key.fromUtf8(secKey);
    final iv = encrypt.IV.fromUtf8(_iv);
    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));
    return encrypter.encrypt(text, iv: iv).base64;
  }

  /// RSA 加密（简化实现）
  String _rsaEncrypt(String text, String pubKey, String modulus) {
    final textBytes = utf8.encode(text);
    final textHex = textBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    // 使用 BigInt 进行模幂运算
    final base = BigInt.parse(textHex, radix: 16);
    final exp = BigInt.parse(pubKey, radix: 16);
    final mod = BigInt.parse(modulus, radix: 16);

    final result = base.modPow(exp, mod);
    return result.toRadixString(16).padLeft(256, '0');
  }

  /// 生成随机字符串
  String _createSecretKey(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return List.generate(length, (_) => chars[random.nextInt(chars.length)]).join();
  }
}
