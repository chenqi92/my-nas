import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/scraper/scrape_source.dart';
import 'package:my_nas/core/utils/logger.dart';

/// 用户导入的音乐元数据源执行引擎。
///
/// 设计要点：
/// - **不内嵌任何源**：所有源都来自用户导入，启动时不加载任何 assets。
/// - **每个 endpoint 一段 JS** 作为响应解析器。引擎按以下骨架包裹用户脚本：
///   ```
///   (function(response, args, secrets) {
///     <用户 script>
///   })(<resp>, <args>, <secrets>)
///   ```
///   脚本内可以直接 `return` 解析后的对象 / 数组。
/// - **URL / body / params / headers 模板**：`{{name}}` 占位符按 args 与
///   secrets 替换；URL 中的占位符自动 URL-encode。
/// - **rateLimit**：按 source.id 维度的最小请求间隔（毫秒）。
/// - **不做 SSL 信任域名**：sslTrustDomains 字段保留供未来扩展，目前 Dio
///   走系统默认证书校验。
class ScrapeEngine {
  ScrapeEngine._();
  static final ScrapeEngine instance = ScrapeEngine._();

  Dio? _dio;
  final Map<String, DateTime> _lastCallAt = {};
  JavascriptRuntime? _runtime;

  Dio get _http => _dio ??= Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 20),
          followRedirects: true,
          validateStatus: (s) => s != null && s < 500,
          headers: const {
            'User-Agent':
                'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36',
            'Accept': '*/*',
          },
        ),
      );

  JavascriptRuntime get _js => _runtime ??= getJavascriptRuntime();

  // ============ 公开调用 ============

  /// 关键词搜索。返回的数组每项形如 `{id, title, artist, album, durationMs, coverUrl, ...}`。
  Future<List<Map<String, dynamic>>> search(
    ScraperConfig config, {
    required String query,
    int limit = 20,
  }) async {
    final endpoint = config.search;
    if (endpoint == null) return const [];
    final args = {'query': query, 'limit': limit};
    final result = await _runEndpoint(config, endpoint, args, action: 'search');
    if (result is List) {
      return [
        for (final e in result)
          if (e is Map) Map<String, dynamic>.from(e),
      ];
    }
    return const [];
  }

  /// 详情。返回 `{title, artist, album, year, genres, coverUrl, ...}`。
  Future<Map<String, dynamic>?> detail(
    ScraperConfig config, {
    required String id,
    String? title,
    String? artist,
    String? album,
  }) async {
    final endpoint = config.detail;
    if (endpoint == null) return null;
    final args = <String, dynamic>{
      'id': id,
      if (title != null) 'title': title,
      if (artist != null) 'artist': artist,
      if (album != null) 'album': album,
    };
    final result = await _runEndpoint(config, endpoint, args, action: 'detail');
    if (result is Map) return Map<String, dynamic>.from(result);
    return null;
  }

  /// 封面。可能返回多个候选 `[{coverUrl, thumbnailUrl}, ...]`。
  Future<List<Map<String, dynamic>>> cover(
    ScraperConfig config, {
    required String id,
  }) async {
    final endpoint = config.cover;
    if (endpoint == null) return const [];
    final result = await _runEndpoint(config, endpoint, {'id': id},
        action: 'cover');
    if (result is List) {
      return [
        for (final e in result)
          if (e is Map) Map<String, dynamic>.from(e),
      ];
    }
    if (result is Map) {
      return [Map<String, dynamic>.from(result)];
    }
    return const [];
  }

  /// 歌词。返回 `{lrcContent, wordLevelLrc?}` 或纯字符串。
  Future<Map<String, dynamic>?> lyrics(
    ScraperConfig config, {
    String? id,
    String? title,
    String? artist,
    String? album,
  }) async {
    final endpoint = config.lyrics;
    if (endpoint == null) return null;
    final args = <String, dynamic>{
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (artist != null) 'artist': artist,
      if (album != null) 'album': album,
    };
    final result = await _runEndpoint(config, endpoint, args,
        action: 'lyrics');
    if (result is Map) return Map<String, dynamic>.from(result);
    if (result is String) return {'lrcContent': result};
    return null;
  }

  // ============ 私有：执行单个 endpoint ============

  Future<dynamic> _runEndpoint(
    ScraperConfig config,
    EndpointConfig endpoint,
    Map<String, dynamic> args, {
    required String action,
  }) async {
    try {
      await _respectRateLimit(config);
      final responseText = await _fetch(config, endpoint, args);
      if (responseText == null) return null;
      return _runScript(endpoint.script, responseText, args, config.secrets);
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'scrape.$action', {
        'source': config.id,
        'name': config.name,
      });
      return null;
    }
  }

  Future<void> _respectRateLimit(ScraperConfig config) async {
    final ms = config.rateLimit;
    if (ms == null || ms <= 0) return;
    final last = _lastCallAt[config.id];
    if (last != null) {
      final elapsed = DateTime.now().difference(last).inMilliseconds;
      if (elapsed < ms) {
        await Future<void>.delayed(Duration(milliseconds: ms - elapsed));
      }
    }
    _lastCallAt[config.id] = DateTime.now();
  }

  Future<String?> _fetch(
    ScraperConfig config,
    EndpointConfig endpoint,
    Map<String, dynamic> args,
  ) async {
    final secrets = config.secrets ?? const <String, String>{};
    final url = _interpolate(endpoint.url, args, secrets, encode: true);

    // 合并 headers：全局 < endpoint < cookie
    final headers = <String, String>{
      ...?config.headers,
      ...?endpoint.headers,
    };
    if (config.cookie != null && config.cookie!.isNotEmpty) {
      headers['Cookie'] = config.cookie!;
    }
    headers.updateAll(
      (_, v) => _interpolate(v, args, secrets, encode: false),
    );

    // params：拼到查询字符串里（占位符替换后做 url-encode）
    final params = endpoint.params?.map(
      (k, v) => MapEntry(k, _interpolate(v, args, secrets, encode: false)),
    );

    // body：bodyTemplate 经占位符替换
    String? body;
    if (endpoint.bodyTemplate != null) {
      body = _interpolate(endpoint.bodyTemplate!, args, secrets, encode: false);
    }

    final method = endpoint.method.toUpperCase();
    final options = Options(
      method: method,
      headers: headers,
      contentType: body != null && body.trimLeft().startsWith('{')
          ? 'application/json'
          : (body != null ? 'application/x-www-form-urlencoded' : null),
      responseType: ResponseType.plain,
    );

    // 合并 endpoint.params 到 URL query
    var uri = Uri.parse(url);
    if (params != null && params.isNotEmpty) {
      final merged = Map<String, String>.from(uri.queryParameters)..addAll(params);
      uri = uri.replace(queryParameters: merged);
    }

    final resp = await _http.requestUri<String>(
      uri,
      data: body,
      options: options,
    );
    if (resp.statusCode == null || resp.statusCode! >= 400) {
      logger.w('scrape: HTTP ${resp.statusCode} $url');
      return null;
    }
    return resp.data;
  }

  /// 把 `{{var}}` 在文本里替换成 args / secrets 的值。
  String _interpolate(
    String template,
    Map<String, dynamic> args,
    Map<String, String> secrets, {
    required bool encode,
  }) {
    if (template.isEmpty) return template;
    return template.replaceAllMapped(
      RegExp(r'\{\{([a-zA-Z0-9_]+)\}\}'),
      (m) {
        final key = m.group(1)!;
        final v = args[key] ?? secrets[key];
        if (v == null) return m.group(0)!;
        final s = v.toString();
        return encode ? Uri.encodeQueryComponent(s) : s;
      },
    );
  }

  /// 把用户脚本包成函数体并执行；用 `JSON.stringify` 做返回值穿透。
  dynamic _runScript(
    String script,
    String response,
    Map<String, dynamic> args,
    Map<String, String>? secrets,
  ) {
    if (script.trim().isEmpty) return null;
    final wrapped = '''
JSON.stringify((function(response, args, secrets) {
$script
})(${jsonEncode(response)}, ${jsonEncode(args)}, ${jsonEncode(secrets ?? const {})}))
''';
    final result = _js.evaluate(wrapped);
    if (result.isError) {
      logger.w('scrape: js error: ${result.stringResult}');
      return null;
    }
    final raw = result.stringResult;
    if (raw.isEmpty || raw == 'undefined' || raw == 'null') return null;
    try {
      return jsonDecode(raw);
    } on FormatException {
      // 脚本返回的是裸字符串（非 JSON），直接返回
      return raw;
    }
  }
}
