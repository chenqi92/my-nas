import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/shared/providers/language_preference_provider.dart';

/// OpenSubtitles API 基础 URL
const _baseUrl = 'https://api.opensubtitles.com/api/v1';

/// 用户代理字符串
const _userAgent = 'MyNas v1.0';

/// 内置默认 API Key（用作公共兜底）
/// 用户可在「源管理 → OpenSubtitles」中填写自己的 API Key 覆盖此默认值，
/// 以获得独立配额、避免共享 key 限流。
const _defaultApiKey = 'eBSGArWsmT2iiGX0Et8CAqOBsKZCPYjM';

/// OpenSubtitles 字幕搜索结果
class OpenSubtitleResult {
  const OpenSubtitleResult({
    required this.id,
    required this.fileId,
    required this.fileName,
    required this.language,
    required this.languageCode,
    required this.downloadCount,
    this.hearingImpaired = false,
    this.aiTranslated = false,
    this.machineTranslated = false,
    this.release,
    this.uploadDate,
    this.fps,
    this.votes,
    this.ratings,
  });

  factory OpenSubtitleResult.fromJson(Map<String, dynamic> json) {
    final attributes = json['attributes'] as Map<String, dynamic>? ?? {};
    final files =
        (attributes['files'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final firstFile = files.isNotEmpty ? files.first : <String, dynamic>{};

    return OpenSubtitleResult(
      id: json['id']?.toString() ?? '',
      fileId: firstFile['file_id'] as int? ?? 0,
      fileName: firstFile['file_name'] as String? ?? '',
      language: attributes['language'] as String? ?? '',
      languageCode: _parseLanguageCode(attributes['language'] as String?),
      downloadCount: attributes['download_count'] as int? ?? 0,
      hearingImpaired: attributes['hearing_impaired'] as bool? ?? false,
      aiTranslated: attributes['ai_translated'] as bool? ?? false,
      machineTranslated: attributes['machine_translated'] as bool? ?? false,
      release: attributes['release'] as String?,
      uploadDate: attributes['upload_date'] as String?,
      fps: (attributes['fps'] as num?)?.toDouble(),
      votes: attributes['votes'] as int?,
      ratings: (attributes['ratings'] as num?)?.toDouble(),
    );
  }

  /// 字幕 ID
  final String id;

  /// 文件 ID（用于下载）
  final int fileId;

  /// 文件名
  final String fileName;

  /// 语言名称
  final String language;

  /// 语言代码
  final String languageCode;

  /// 下载次数
  final int downloadCount;

  /// 是否为 SDH 字幕（听障人士字幕）
  final bool hearingImpaired;

  /// 是否为 AI 翻译
  final bool aiTranslated;

  /// 是否为机器翻译
  final bool machineTranslated;

  /// 发布组信息
  final String? release;

  /// 上传日期
  final String? uploadDate;

  /// 帧率
  final double? fps;

  /// 投票数
  final int? votes;

  /// 评分
  final double? ratings;

  /// 获取语言显示名称
  String get displayLanguage =>
      _getLanguageDisplayNames()[languageCode] ?? language;

  /// 获取字幕质量标签
  List<String> get qualityTags {
    final tags = <String>[];
    if (hearingImpaired) {
      tags.add('SDH');
    }
    if (aiTranslated) {
      tags.add('AI');
    }
    if (machineTranslated) {
      tags.add(appL10n.videoOpensubtitlesMachineTranslated);
    }
    return tags;
  }

  static String _parseLanguageCode(String? language) {
    if (language == null) return '';
    // OpenSubtitles 返回的语言是 ISO 639-2B 格式，如 "Chinese (simplified)"
    final lower = language.toLowerCase();
    if (lower.contains('chinese') && lower.contains('simplified')) {
      return 'zh-cn';
    }
    if (lower.contains('chinese') && lower.contains('traditional')) {
      return 'zh-tw';
    }
    if (lower.contains('chinese')) return 'zh';
    if (lower.contains('english')) return 'en';
    if (lower.contains('japanese')) return 'ja';
    if (lower.contains('korean')) return 'ko';
    if (lower.contains('french')) return 'fr';
    if (lower.contains('german')) return 'de';
    if (lower.contains('spanish')) return 'es';
    if (lower.contains('portuguese')) return 'pt';
    if (lower.contains('russian')) return 'ru';
    if (lower.contains('italian')) return 'it';
    if (lower.contains('thai')) return 'th';
    if (lower.contains('vietnamese')) return 'vi';
    return language;
  }

  static Map<String, String> _getLanguageDisplayNames() => <String, String>{
    'zh-cn': appL10n.videoOpensubtitlesLanguageZhCn,
    'zh-tw': appL10n.videoOpensubtitlesLanguageZhTw,
    'zh': appL10n.videoOpensubtitlesLanguageZh,
    'en': 'English',
    'ja': appL10n.videoOpensubtitlesLanguageJa,
    'ko': appL10n.videoOpensubtitlesLanguageKo,
    'fr': 'Français',
    'de': 'Deutsch',
    'es': 'Español',
    'pt': 'Português',
    'ru': 'Русский',
    'it': 'Italiano',
    'th': 'ไทย',
    'vi': 'Tiếng Việt',
  };
}

/// OpenSubtitles 下载结果
class OpenSubtitleDownloadResult {
  const OpenSubtitleDownloadResult({
    required this.link,
    required this.fileName,
    required this.remaining,
    this.resetTime,
  });

  factory OpenSubtitleDownloadResult.fromJson(Map<String, dynamic> json) =>
      OpenSubtitleDownloadResult(
        link: json['link'] as String? ?? '',
        fileName: json['file_name'] as String? ?? '',
        remaining: json['remaining'] as int? ?? 0,
        resetTime: json['reset_time'] as String?,
      );

  /// 下载链接
  final String link;

  /// 文件名
  final String fileName;

  /// 剩余下载次数
  final int remaining;

  /// 配额重置时间
  final String? resetTime;
}

/// OpenSubtitles 用户信息
class OpenSubtitleUserInfo {
  const OpenSubtitleUserInfo({
    required this.userId,
    required this.level,
    required this.allowedDownloads,
    required this.remainingDownloads,
    this.vip = false,
  });

  factory OpenSubtitleUserInfo.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>? ?? {};
    return OpenSubtitleUserInfo(
      userId: user['user_id'] as int? ?? 0,
      level: user['level'] as String? ?? 'Unknown',
      allowedDownloads: user['allowed_downloads'] as int? ?? 0,
      remainingDownloads: user['remaining_downloads'] as int? ?? 0,
      vip: user['vip'] as bool? ?? false,
    );
  }

  final int userId;
  final String level;
  final int allowedDownloads;
  final int remainingDownloads;
  final bool vip;
}

/// OpenSubtitles 搜索参数
class OpenSubtitleSearchParams {
  const OpenSubtitleSearchParams({
    this.tmdbId,
    this.imdbId,
    this.query,
    this.seasonNumber,
    this.episodeNumber,
    this.languages,
    this.type,
    this.excludeAiTranslated = false,
    this.excludeMachineTranslated = false,
    this.hearingImpaired,
    this.orderBy = 'download_count',
    this.orderDirection = 'desc',
  });

  /// TMDB ID
  final int? tmdbId;

  /// IMDB ID
  final String? imdbId;

  /// 搜索关键词
  final String? query;

  /// 季号（电视剧）
  final int? seasonNumber;

  /// 集号（电视剧）
  final int? episodeNumber;

  /// 语言列表（ISO 639-1/2 代码）
  final List<String>? languages;

  /// 类型：movie 或 episode
  final String? type;

  /// 排除 AI 翻译
  final bool excludeAiTranslated;

  /// 排除机器翻译
  final bool excludeMachineTranslated;

  /// 听障字幕偏好：include, exclude, only
  final String? hearingImpaired;

  /// 排序字段
  final String orderBy;

  /// 排序方向
  final String orderDirection;

  Map<String, String> toQueryParams() {
    final params = <String, String>{};

    if (tmdbId != null) {
      params['tmdb_id'] = tmdbId.toString();
    }
    if (imdbId != null) {
      params['imdb_id'] = imdbId!;
    }
    if (query != null && query!.isNotEmpty) {
      params['query'] = query!;
    }
    if (seasonNumber != null) {
      params['season_number'] = seasonNumber.toString();
    }
    if (episodeNumber != null) {
      params['episode_number'] = episodeNumber.toString();
    }
    if (languages != null && languages!.isNotEmpty) {
      params['languages'] = languages!.join(',');
    }
    if (type != null) {
      params['type'] = type!;
    }
    if (excludeAiTranslated) {
      params['ai_translated'] = 'exclude';
    }
    if (excludeMachineTranslated) {
      params['machine_translated'] = 'exclude';
    }
    if (hearingImpaired != null) {
      params['hearing_impaired'] = hearingImpaired!;
    }
    params['order_by'] = orderBy;
    params['order_direction'] = orderDirection;

    return params;
  }
}

/// OpenSubtitles API 服务
class OpenSubtitlesService {
  OpenSubtitlesService({required this.apiKey, this.username, this.password});

  static String get defaultApiKey => _defaultApiKey;

  final String apiKey;
  final String? username;
  final String? password;

  String? _jwtToken;
  DateTime? _tokenExpiry;

  /// 获取请求头
  Map<String, String> _getHeaders({bool requireAuth = false}) {
    final headers = <String, String>{
      'Api-Key': apiKey,
      'Content-Type': 'application/json',
      'User-Agent': _userAgent,
    };

    if (requireAuth && _jwtToken != null) {
      headers['Authorization'] = 'Bearer $_jwtToken';
    }

    return headers;
  }

  /// 验证 API Key / 可选账号是否可用。
  ///
  /// 未配置账号时，用轻量搜索验证 API Key；配置账号时走登录接口，确保
  /// 后续下载配额与 JWT 流程真实可用。
  Future<bool> validateConnection() async {
    if (apiKey.trim().isEmpty) return false;

    final hasUsername = username?.trim().isNotEmpty ?? false;
    final hasPassword = password?.isNotEmpty ?? false;
    if (hasUsername || hasPassword) {
      if (!hasUsername || !hasPassword) return false;
      return await login() != null;
    }

    try {
      final uri = Uri.parse('$_baseUrl/subtitles').replace(
        queryParameters: const {
          'query': 'test',
          'languages': 'en',
          'page': '1',
        },
      );
      final response = await http.get(uri, headers: _getHeaders());
      if (response.statusCode == 200) return true;
      if (response.statusCode == 429) {
        logger.w('OpenSubtitles: 验证遇到频率限制，视为 API 可达');
        return true;
      }
      logger.w('OpenSubtitles: 验证失败，状态码: ${response.statusCode}');
      return false;
    } catch (e, st) {
      AppError.handle(e, st, 'opensubtitles_validate');
      return false;
    }
  }

  /// 登录获取 JWT Token
  Future<OpenSubtitleUserInfo?> login() async {
    if (username == null || password == null) {
      return null;
    }

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/login'),
        headers: _getHeaders(),
        body: jsonEncode({'username': username, 'password': password}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _jwtToken = data['token'] as String?;
        // Token 有效期通常是 24 小时
        _tokenExpiry = DateTime.now().add(const Duration(hours: 23));
        logger.i('OpenSubtitles: 登录成功');
        return OpenSubtitleUserInfo.fromJson(data);
      } else if (response.statusCode == 401) {
        logger.w('OpenSubtitles: 登录失败，用户名或密码错误');
        return null;
      } else {
        logger.w('OpenSubtitles: 登录失败，状态码: ${response.statusCode}');
        return null;
      }
    } catch (e, st) {
      AppError.handle(e, st, 'opensubtitles_login');
      return null;
    }
  }

  /// 确保已登录（如果配置了账号）
  Future<void> _ensureLoggedIn() async {
    if (username != null && password != null) {
      if (_jwtToken == null ||
          _tokenExpiry == null ||
          DateTime.now().isAfter(_tokenExpiry!)) {
        await login();
      }
    }
  }

  /// 搜索字幕
  Future<List<OpenSubtitleResult>> search(
    OpenSubtitleSearchParams params,
  ) async {
    try {
      await _ensureLoggedIn();

      final uri = Uri.parse(
        '$_baseUrl/subtitles',
      ).replace(queryParameters: params.toQueryParams());

      final response = await http.get(
        uri,
        headers: _getHeaders(requireAuth: _jwtToken != null),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final dataList = data['data'] as List? ?? [];
        return dataList
            .cast<Map<String, dynamic>>()
            .map(OpenSubtitleResult.fromJson)
            .where((s) => s.fileId > 0) // 过滤无效结果
            .toList();
      } else if (response.statusCode == 429) {
        logger.w('OpenSubtitles: 请求频率限制');
        throw Exception(appL10n.videoOpensubtitlesRateLimitError);
      } else {
        logger.w('OpenSubtitles: 搜索失败，状态码: ${response.statusCode}');
        return [];
      }
    } catch (e, st) {
      AppError.handle(e, st, 'opensubtitles_search');
      rethrow;
    }
  }

  /// 获取字幕下载链接
  Future<OpenSubtitleDownloadResult?> getDownloadLink(int fileId) async {
    try {
      await _ensureLoggedIn();

      final response = await http.post(
        Uri.parse('$_baseUrl/download'),
        headers: _getHeaders(requireAuth: true),
        body: jsonEncode({'file_id': fileId}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return OpenSubtitleDownloadResult.fromJson(data);
      } else if (response.statusCode == 406) {
        logger.w('OpenSubtitles: 下载配额用尽');
        throw Exception(appL10n.videoOpensubtitlesQuotaExhaustedError);
      } else if (response.statusCode == 429) {
        logger.w('OpenSubtitles: 请求频率限制');
        throw Exception(appL10n.videoOpensubtitlesRateLimitError);
      } else {
        logger.w('OpenSubtitles: 获取下载链接失败，状态码: ${response.statusCode}');
        return null;
      }
    } catch (e, st) {
      if (e is Exception) rethrow;
      AppError.handle(e, st, 'opensubtitles_download_link');
      rethrow;
    }
  }

  /// 下载字幕文件
  Future<String?> downloadSubtitle({
    required int fileId,
    required String savePath,
  }) async {
    try {
      final downloadResult = await getDownloadLink(fileId);
      if (downloadResult == null || downloadResult.link.isEmpty) {
        return null;
      }

      // 下载文件
      final response = await http.get(Uri.parse(downloadResult.link));
      if (response.statusCode == 200) {
        // 确定最终文件名
        var fileName = downloadResult.fileName;
        if (fileName.isEmpty) {
          fileName = 'subtitle.srt';
        }

        // 确保文件扩展名
        if (!fileName.toLowerCase().endsWith('.srt') &&
            !fileName.toLowerCase().endsWith('.ass') &&
            !fileName.toLowerCase().endsWith('.vtt')) {
          fileName = '$fileName.srt';
        }

        // 构建完整路径
        final fullPath = savePath.endsWith('/')
            ? '$savePath$fileName'
            : '$savePath/$fileName';

        // 保存文件
        final file = File(fullPath);
        await file.writeAsBytes(response.bodyBytes);

        logger.i('OpenSubtitles: 字幕下载成功: $fullPath');
        return fullPath;
      } else {
        logger.w('OpenSubtitles: 下载字幕失败，状态码: ${response.statusCode}');
        return null;
      }
    } catch (e, st) {
      AppError.handle(e, st, 'opensubtitles_download');
      return null;
    }
  }

  /// 测试连接
  Future<bool> testConnection() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/infos/user'),
        headers: _getHeaders(),
      );
      return response.statusCode == 200 || response.statusCode == 401;
    } catch (e) {
      return false;
    }
  }
}

/// OpenSubtitles 服务 Provider
final openSubtitlesServiceProvider = FutureProvider<OpenSubtitlesService?>((
  ref,
) async {
  // 获取已配置的 OpenSubtitles 源
  final sourcesAsync = ref.watch(sourcesProvider);
  final sources = sourcesAsync.valueOrNull ?? [];
  final openSubtitlesSources = sources
      .where((s) => s.type == SourceType.opensubtitles)
      .toList();

  if (openSubtitlesSources.isEmpty) {
    return null;
  }

  final source = openSubtitlesSources.first;
  final sourceManager = ref.read(sourceManagerProvider);
  final credential = await sourceManager.getCredential(source.id);
  // 优先使用用户自定义的 API Key，否则使用内置默认 Key
  final customApiKey =
      source.apiKey ?? source.extraConfig?['apiKey'] as String?;
  final apiKey = (customApiKey?.isNotEmpty ?? false)
      ? customApiKey!
      : _defaultApiKey;

  return OpenSubtitlesService(
    apiKey: apiKey,
    username: source.username.isNotEmpty ? source.username : null,
    password: credential?.password,
  );
});

/// 是否已配置 OpenSubtitles
final hasOpenSubtitlesConfigProvider = Provider<bool>((ref) {
  final sources = ref.watch(sourcesProvider).valueOrNull ?? [];
  return sources.any((s) => s.type == SourceType.opensubtitles);
});

/// 根据语言偏好获取语言代码列表
List<String> getPreferredLanguageCodes(LanguagePreference? preference) {
  if (preference == null) {
    return ['zh', 'en']; // 默认中英文
  }

  final codes = <String>[];
  for (final lang in preference.subtitleLanguages) {
    switch (lang) {
      case LanguageOption.auto:
        // 自动模式返回默认列表
        return ['zh', 'en', 'ja'];
      case LanguageOption.original:
        continue;
      case LanguageOption.zhCN:
        codes.add('zh');
      case LanguageOption.zhTW:
        codes.add('zh');
      case LanguageOption.en:
        codes.add('en');
      case LanguageOption.ja:
        codes.add('ja');
      case LanguageOption.ko:
        codes.add('ko');
      case LanguageOption.fr:
        codes.add('fr');
      case LanguageOption.de:
        codes.add('de');
      case LanguageOption.es:
        codes.add('es');
      case LanguageOption.pt:
        codes.add('pt');
      case LanguageOption.ru:
        codes.add('ru');
      case LanguageOption.it:
        codes.add('it');
      case LanguageOption.th:
        codes.add('th');
      case LanguageOption.vi:
        codes.add('vi');
    }
  }

  return codes.isNotEmpty ? codes.toSet().toList() : ['zh', 'en'];
}
