import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/network/dio_client.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_result.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_source.dart';
import 'package:my_nas/features/music/domain/interfaces/music_scraper.dart';

/// Music Tag Web 支持的音乐源
enum MusicTagWebSource {
  netease('netease', '网易云音乐'),
  migu('migu', '咪咕音乐'),
  qmusic('qmusic', 'QQ音乐'),
  kugou('kugou', '酷狗音乐'),
  kuwo('kuwo', '酷我音乐');

  const MusicTagWebSource(this.id, this.displayName);

  final String id;
  final String displayName;

  static MusicTagWebSource fromId(String id) => MusicTagWebSource.values
      .firstWhere((s) => s.id == id, orElse: () => MusicTagWebSource.netease);
}

/// Music Tag Web 刮削器
///
/// 连接自托管的 Music Tag Web 服务获取音乐元数据、封面和歌词
/// GitHub: https://github.com/xhongc/music-tag-web
class MusicTagWebScraper implements MusicScraper {
  MusicTagWebScraper({
    required this.serverUrl,
    this.username,
    this.password,
    this.preferredSource = MusicTagWebSource.netease,
  }) {
    _dio = DioClient.createTlsAware(
      options: BaseOptions(
        baseUrl: _normalizeServerUrl(serverUrl),
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          'User-Agent': 'MyNAS/1.0',
          'Content-Type': 'application/json',
        },
      ),
    );
  }

  final String serverUrl;
  final String? username;
  final String? password;
  final MusicTagWebSource preferredSource;

  late final Dio _dio;
  String? _jwtToken;

  /// 上次请求时间
  DateTime? _lastRequestTime;

  /// 最小请求间隔
  static const Duration _minInterval = Duration(milliseconds: 500);

  @override
  MusicScraperType get type => MusicScraperType.musicTagWeb;

  @override
  bool get isConfigured => serverUrl.isNotEmpty;

  /// 规范化服务器地址
  String _normalizeServerUrl(String url) {
    var normalized = url.trim();
    if (!normalized.startsWith('http://') &&
        !normalized.startsWith('https://')) {
      normalized = 'http://$normalized';
    }
    if (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  /// 获取 JWT Token（如果配置了用户名密码）
  Future<void> _ensureAuthenticated() async {
    if (_jwtToken != null) return;
    if (username == null || username!.isEmpty) return;

    try {
      final response = await _dio.post<dynamic>(
        '/api/token/',
        data: {'username': username, 'password': password ?? ''},
      );

      if (response.data != null && response.data is Map<String, dynamic>) {
        final data = response.data as Map<String, dynamic>;
        _jwtToken = data['token'] as String?;
        if (_jwtToken != null) {
          _dio.options.headers['Authorization'] = 'JWT $_jwtToken';
        }
      }
    } on DioException {
      // 认证失败，继续使用无认证模式
    }
  }

  @override
  Future<bool> testConnection() async {
    try {
      await _ensureAuthenticated();
      // 尝试搜索测试
      final response = await _rateLimitedRequest(
        () => _dio.post<dynamic>(
          '/api/fetch_id3_by_title/',
          data: {'resource': preferredSource.id, 'title': 'test'},
        ),
      );
      return response.statusCode == 200;
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
      await _ensureAuthenticated();

      // 构建搜索关键词
      var searchQuery = query;
      if (artist != null && artist.isNotEmpty) {
        searchQuery += ' $artist';
      }
      if (album != null && album.isNotEmpty) {
        searchQuery += ' $album';
      }

      final response = await _rateLimitedRequest(
        () => _dio.post<dynamic>(
          '/api/fetch_id3_by_title/',
          data: {'resource': preferredSource.id, 'title': searchQuery},
        ),
      );

      if (response.data == null) {
        return MusicScraperSearchResult.empty(type);
      }

      // Music Tag Web 返回的是列表
      List<dynamic> songs;
      var responseData = response.data;

      // 处理返回的是 JSON 字符串的情况
      if (responseData is String) {
        try {
          responseData = jsonDecode(responseData);
        } on FormatException {
          // 无法解析，返回空结果
          return MusicScraperSearchResult.empty(type);
        }
      }

      if (responseData is List) {
        songs = responseData;
      } else if (responseData is Map<String, dynamic>) {
        // 检查是否有 data 字段
        if (responseData['data'] is List) {
          songs = responseData['data'] as List;
        } else {
          songs = [];
        }
      } else {
        songs = [];
      }

      final items = songs
          .whereType<Map<String, dynamic>>()
          .take(limit)
          .map(_parseSong)
          .toList();

      return MusicScraperSearchResult(
        items: items,
        source: type,
        page: page,
        totalPages: 1, // Music Tag Web 不支持分页
        totalResults: items.length,
      );
    } on DioException catch (e) {
      throw _handleDioError(e);
    }
  }

  @override
  Future<MusicScraperDetail?> getDetail(String externalId) async {
    // Music Tag Web 的搜索结果已经包含了详情
    // externalId 格式: source:id (例如 netease:123456)
    final parts = externalId.split(':');
    if (parts.length < 2) return null;

    final source = parts[0];
    final songId = parts.sublist(1).join(':');

    try {
      await _ensureAuthenticated();

      // 搜索歌曲获取详情
      final response = await _rateLimitedRequest(
        () => _dio.post<dynamic>(
          '/api/fetch_id3_by_title/',
          data: {
            'resource': source,
            'title': songId, // 尝试用 ID 搜索
          },
        ),
      );

      if (response.data == null) return null;

      List<dynamic> songs;
      var responseData = response.data;

      // 处理返回的是 JSON 字符串的情况
      if (responseData is String) {
        try {
          responseData = jsonDecode(responseData);
        } on FormatException {
          return null;
        }
      }

      if (responseData is List) {
        songs = responseData;
      } else if (responseData is Map<String, dynamic>) {
        if (responseData['data'] is List) {
          songs = responseData['data'] as List;
        } else {
          songs = [];
        }
      } else {
        return null;
      }

      // 过滤出有效的 Map 类型数据
      final validSongs = songs.whereType<Map<String, dynamic>>().toList();
      if (validSongs.isEmpty) return null;

      // 查找匹配的歌曲
      final song = validSongs.firstWhere(
        (s) => s['id'].toString() == songId,
        orElse: () => validSongs.first,
      );

      return _parseSongDetail(song, source);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw _handleDioError(e);
    }
  }

  @override
  Future<List<CoverScraperResult>> getCoverArt(String externalId) async {
    final detail = await getDetail(externalId);
    if (detail?.coverUrl == null) return [];

    return [
      CoverScraperResult(
        source: type,
        coverUrl: detail!.coverUrl!,
        thumbnailUrl: detail.coverUrl,
        type: CoverType.front,
      ),
    ];
  }

  @override
  Future<LyricScraperResult?> getLyrics(String externalId) async {
    // externalId 格式: source:id
    final parts = externalId.split(':');
    if (parts.length < 2) return null;

    final source = parts[0];
    final songId = parts.sublist(1).join(':');

    try {
      await _ensureAuthenticated();

      final response = await _rateLimitedRequest(
        () => _dio.post<dynamic>(
          '/api/fetch_lyric/',
          data: {'resource': source, 'song_id': songId},
        ),
      );

      if (response.data == null) return null;

      String? lyricContent;
      if (response.data is String) {
        lyricContent = response.data as String;
      } else if (response.data is Map<String, dynamic>) {
        final data = response.data as Map<String, dynamic>;
        lyricContent = data['data'] as String? ?? data['lyric'] as String?;
      }

      if (lyricContent == null || lyricContent.isEmpty) return null;

      // 检查是否是 LRC 格式
      final isLrc = lyricContent.contains(RegExp(r'\[\d{2}:\d{2}'));

      return LyricScraperResult(
        source: type,
        lrcContent: isLrc ? lyricContent : null,
        plainText: isLrc ? null : lyricContent,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
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
    final id = data['id']?.toString() ?? '';
    final name = data['name'] as String? ?? '';
    final artist = data['artist'] as String? ?? '';
    final album = data['album'] as String? ?? '';
    final albumImg = data['album_img'] as String? ?? '';
    final year = data['year']?.toString();

    // 构建复合 ID: source:id
    final externalId = '${preferredSource.id}:$id';

    return MusicScraperItem(
      externalId: externalId,
      source: type,
      title: name,
      artist: artist.isEmpty ? null : artist,
      album: album.isEmpty ? null : album,
      coverUrl: albumImg.isEmpty ? null : albumImg,
      year: year != null && year.isNotEmpty ? int.tryParse(year) : null,
    );
  }

  /// 解析歌曲详情
  MusicScraperDetail _parseSongDetail(
    Map<String, dynamic> data,
    String source,
  ) {
    final id = data['id']?.toString() ?? '';
    final name = data['name'] as String? ?? '';
    final artist = data['artist'] as String? ?? '';
    final album = data['album'] as String? ?? '';
    final albumImg = data['album_img'] as String? ?? '';
    final year = data['year']?.toString();

    // 构建复合 ID: source:id
    final externalId = '$source:$id';

    return MusicScraperDetail(
      externalId: externalId,
      source: type,
      title: name,
      artist: artist.isEmpty ? null : artist,
      album: album.isEmpty ? null : album,
      coverUrl: albumImg.isEmpty ? null : albumImg,
      year: year != null && year.isNotEmpty ? int.tryParse(year) : null,
    );
  }

  /// 处理 Dio 错误
  MusicScraperException _handleDioError(DioException e) {
    if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
      return MusicScraperAuthException(
        appL10n.musicTagWebScraperAuthFailed,
        source: type,
        cause: e,
      );
    }
    if (e.response?.statusCode == 429) {
      return MusicScraperRateLimitException(
        appL10n.musicTagWebScraperRateLimited,
        source: type,
        cause: e,
      );
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return MusicScraperNetworkException(
        appL10n.musicTagWebScraperConnectionFailed(serverUrl),
        source: type,
        cause: e,
      );
    }
    return MusicScraperException(
      e.message ?? appL10n.musicTagWebScraperUnknownError,
      source: type,
      cause: e,
    );
  }
}
