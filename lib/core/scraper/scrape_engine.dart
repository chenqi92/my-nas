import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/network/dio_client.dart';
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
/// - **HTTPS 信任**：系统证书失败时走应用级按端点证书确认、固定和自动重试。
class ScrapeEngine {
  ScrapeEngine._();
  static final ScrapeEngine instance = ScrapeEngine._();

  /// 同时保活的 JS 运行时上限。超出后按最近最少使用淘汰并释放。
  static const _maxRuntimes = 4;

  Dio? _dio;
  final Map<String, DateTime> _lastCallAt = {};

  /// 按 source.id 隔离的 JS 运行时。
  ///
  /// 不能共用单个全局运行时：用户导入的脚本运行在同一个 global 上时，
  /// 一个恶意源可以覆写 `JSON.stringify`（引擎正是用它穿透返回值）
  /// 或在 global 上留驻函数，从而篡改后续任意源的解析结果、读取其它
  /// 源写入 global 的数据。按源隔离把污染限制在该源自身。
  final Map<String, JavascriptRuntime> _runtimes = {};

  /// 运行时访问顺序，末尾为最近使用。
  final List<String> _runtimeLru = [];

  Dio get _http => _dio ??= DioClient.createTlsAware(
    options: BaseOptions(
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

  /// 取得 [sourceId] 专属的运行时，必要时创建并淘汰最旧的。
  JavascriptRuntime _jsFor(String sourceId) {
    _runtimeLru
      ..remove(sourceId)
      ..add(sourceId);

    final existing = _runtimes[sourceId];
    if (existing != null) return existing;

    while (_runtimeLru.length > _maxRuntimes) {
      final evicted = _runtimeLru.removeAt(0);
      _disposeRuntime(evicted);
    }

    final runtime = getJavascriptRuntime();
    _bootstrap(runtime);
    _runtimes[sourceId] = runtime;
    return runtime;
  }

  /// 在运行时里固定一份 `JSON.stringify` 引用。
  ///
  /// 引擎依赖 `JSON.stringify` 把脚本返回值穿透回 Dart，脚本自身可以
  /// 覆写它。用 `writable: false, configurable: false` 定义副本，使脚本
  /// 既不能重新赋值也不能 delete，保证返回值编码始终走原生实现。
  void _bootstrap(JavascriptRuntime runtime) {
    final result = runtime.evaluate('''
Object.defineProperty(globalThis, '__mynasStringify', {
  value: JSON.stringify,
  writable: false,
  configurable: false,
  enumerable: false
});
true
''');
    if (result.isError) {
      logger.w('scrape: js bootstrap failed: ${result.stringResult}');
    }
  }

  void _disposeRuntime(String sourceId) {
    final runtime = _runtimes.remove(sourceId);
    if (runtime == null) return;
    try {
      runtime.dispose();
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'JS 运行时释放失败，已从缓存移除');
    }
  }

  /// 释放某个源的运行时。源被删除或脚本被编辑后调用，
  /// 避免旧脚本留在 global 上的状态影响新脚本。
  void invalidateSource(String sourceId) {
    _runtimeLru.remove(sourceId);
    _disposeRuntime(sourceId);
  }

  /// 释放全部运行时。
  void disposeAll() {
    for (final id in _runtimes.keys.toList()) {
      _disposeRuntime(id);
    }
    _runtimeLru.clear();
  }

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
      'title': ?title,
      'artist': ?artist,
      'album': ?album,
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
    final result = await _runEndpoint(config, endpoint, {
      'id': id,
    }, action: 'cover');
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
      'id': ?id,
      'title': ?title,
      'artist': ?artist,
      'album': ?album,
    };
    final result = await _runEndpoint(config, endpoint, args, action: 'lyrics');
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
      return _runScript(
        config.id,
        endpoint.script,
        responseText,
        args,
        config.secrets,
      );
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
    final headers = <String, String>{...?config.headers, ...?endpoint.headers};
    if (config.cookie != null && config.cookie!.isNotEmpty) {
      headers['Cookie'] = config.cookie!;
    }
    headers.updateAll((_, v) => _interpolate(v, args, secrets, encode: false));

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
      final merged = Map<String, String>.from(uri.queryParameters)
        ..addAll(params);
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
    return template.replaceAllMapped(RegExp(r'\{\{([a-zA-Z0-9_]+)\}\}'), (m) {
      final key = m.group(1)!;
      final v = args[key] ?? secrets[key];
      if (v == null) return m.group(0)!;
      final s = v.toString();
      return encode ? Uri.encodeQueryComponent(s) : s;
    });
  }

  /// 把用户脚本包成函数体并执行；用固定的 `JSON.stringify` 副本做返回值穿透。
  ///
  /// [sourceId] 决定用哪个隔离运行时执行，见 [_jsFor]。
  dynamic _runScript(
    String sourceId,
    String script,
    String response,
    Map<String, dynamic> args,
    Map<String, String>? secrets,
  ) {
    if (script.trim().isEmpty) return null;
    final wrapped =
        '''
__mynasStringify((function(response, args, secrets) {
$script
})(${jsonEncode(response)}, ${jsonEncode(args)}, ${jsonEncode(secrets ?? const {})}))
''';
    final result = _jsFor(sourceId).evaluate(wrapped);
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
