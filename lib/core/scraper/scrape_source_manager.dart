import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:hive_ce/hive.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/scraper/scrape_source.dart';
import 'package:my_nas/core/utils/logger.dart';

/// 用户导入的音乐元数据源管理。
///
/// **本应用不内嵌任何源**。启动时只读 Hive 中用户主动导入的源；assets/ 下不放
/// 任何 *.json scrape 模板。导入页必须显示免责声明。
class ScrapeSourceManager {
  ScrapeSourceManager._();
  static final ScrapeSourceManager instance = ScrapeSourceManager._();

  static const _boxName = 'js_scrape_sources';

  Box<String>? _box;
  bool _initialized = false;
  List<ScraperConfig>? _cache;

  final _events = StreamController<void>.broadcast();
  Stream<void> get events => _events.stream;

  Future<void> init() async {
    if (_initialized) return;
    _box = Hive.isBoxOpen(_boxName)
        ? Hive.box<String>(_boxName)
        : await Hive.openBox<String>(_boxName);
    await _reload();
    _initialized = true;
    logger.i('ScrapeSourceManager: init ${_cache?.length ?? 0} sources');
  }

  Future<void> _reload() async {
    final list = <ScraperConfig>[];
    for (final key in _box!.keys) {
      final raw = _box!.get(key);
      if (raw == null) continue;
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        list.add(ScraperConfig.fromJson(json));
      } on Exception catch (e, st) {
        AppError.handle(e, st, 'scrapeSource.parse', {'key': key});
      }
    }
    list.sort((a, b) => a.customOrder.compareTo(b.customOrder));
    _cache = list;
  }

  Future<List<ScraperConfig>> getAll() async {
    if (!_initialized) await init();
    return List.unmodifiable(_cache ?? const []);
  }

  /// 按 capability 过滤启用的源。
  Future<List<ScraperConfig>> getByCapability(String cap) async {
    final all = await getAll();
    return all
        .where((s) => s.enabled && s.hasCapability(cap) && s.isDeleted != true)
        .toList();
  }

  Future<ScraperConfig?> getById(String id) async {
    final all = await getAll();
    for (final s in all) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<void> addOrUpdate(ScraperConfig source) async {
    if (!_initialized) await init();
    final updated = source.copyWith(modifiedAt: DateTime.now());
    await _box!.put(updated.id, jsonEncode(updated.toJson()));
    await _reload();
    _events.add(null);
  }

  Future<int> addMany(List<ScraperConfig> sources) async {
    if (!_initialized) await init();
    var added = 0;
    final now = DateTime.now();
    var nextOrder = _cache?.fold<int>(
          0,
          (m, s) => s.customOrder > m ? s.customOrder : m,
        ) ??
        0;
    for (final s in sources) {
      try {
        nextOrder++;
        final entry = s.copyWith(
          customOrder: nextOrder,
          modifiedAt: now,
        );
        await _box!.put(entry.id, jsonEncode(entry.toJson()));
        added++;
      } on Exception catch (e, st) {
        AppError.handle(e, st, 'scrapeSource.addMany', {'name': s.name});
      }
    }
    if (added > 0) {
      await _reload();
      _events.add(null);
    }
    return added;
  }

  Future<void> remove(String id) async {
    if (!_initialized) await init();
    await _box!.delete(id);
    await _reload();
    _events.add(null);
  }

  Future<void> setEnabled(String id, {required bool enabled}) async {
    final s = await getById(id);
    if (s == null) return;
    await addOrUpdate(s.copyWith(enabled: enabled));
  }

  // ============ 导入 / 导出 ============

  /// 远端拉取并解析（与 [parseImport] 同样支持 4 种形态）。
  static Future<List<ScraperConfig>> fetchFromUrl(String url) async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      headers: const {'Accept': 'application/json, text/plain, */*'},
    ));
    final resp = await dio.getUri<String>(
      Uri.parse(url),
      options: Options(responseType: ResponseType.plain),
    );
    final body = resp.data ?? '';
    if (body.isEmpty) return const [];
    return parseImport(body);
  }

  /// 解析用户提供的 JSON 文本。支持 4 种形态：
  ///
  /// 1. 单对象 `{...}`
  /// 2. 数组 `[{...}, {...}]`
  /// 3. 包裹 `{ "schema": N, "sources": [...] }`
  /// 4. 多对象拼接 `{...}\n{...}` 或 `{...} {...}`
  static List<ScraperConfig> parseImport(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return const [];

    // 数组
    if (text.startsWith('[')) {
      final decoded = jsonDecode(text);
      if (decoded is List) {
        return [
          for (final e in decoded)
            if (e is Map) ScraperConfig.fromJson(Map<String, dynamic>.from(e)),
        ];
      }
      return const [];
    }

    if (text.startsWith('{')) {
      // 先尝试当包裹对象解析
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map) {
          final m = Map<String, dynamic>.from(decoded);
          if (m['sources'] is List) {
            // 包裹形态
            final list = m['sources'] as List;
            return [
              for (final e in list)
                if (e is Map)
                  ScraperConfig.fromJson(Map<String, dynamic>.from(e)),
            ];
          }
          // 单对象
          return [ScraperConfig.fromJson(m)];
        }
      } on FormatException {
        // 不是合法的单 JSON → 按多对象拼接处理
        return _parseConcatenated(text);
      }
    }

    return const [];
  }

  /// 处理 `{...}{...}` / `{...}\n{...}` 形式。逐字符扫描花括号配平。
  static List<ScraperConfig> _parseConcatenated(String text) {
    final list = <ScraperConfig>[];
    var depth = 0;
    var start = -1;
    var inStr = false;
    var escape = false;
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (inStr) {
        if (escape) {
          escape = false;
        } else if (c == r'\') {
          escape = true;
        } else if (c == '"') {
          inStr = false;
        }
        continue;
      }
      if (c == '"') {
        inStr = true;
        continue;
      }
      if (c == '{') {
        if (depth == 0) start = i;
        depth++;
      } else if (c == '}') {
        depth--;
        if (depth == 0 && start >= 0) {
          final chunk = text.substring(start, i + 1);
          try {
            final m = jsonDecode(chunk);
            if (m is Map) {
              list.add(ScraperConfig.fromJson(Map<String, dynamic>.from(m)));
            }
          } on FormatException catch (_) {
            // 该 chunk 不是合法 JSON，跳过
          }
          start = -1;
        }
      }
    }
    return list;
  }

  /// 整体导出（用于备份 / 跨设备迁移）。包裹成 `{schema:1, sources:[...]}`。
  String exportAll(List<ScraperConfig> sources, {bool includeSecrets = false}) =>
      jsonEncode({
        'schema': 1,
        'sources': [
          for (final s in sources) s.toJson(includeSecrets: includeSecrets),
        ],
      });
}
