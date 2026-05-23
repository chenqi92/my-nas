import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/translation/translation_provider.dart';
import 'package:my_nas/core/translation/translation_providers.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/data/services/subtitle_translation/subtitle_format.dart';
import 'package:my_nas/features/video/data/services/subtitle_translation/subtitle_parser.dart';
import 'package:my_nas/features/video/data/services/subtitle_translation/subtitle_serializer.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 一次字幕翻译会话的进度快照。
class SubtitleTranslationProgress {
  const SubtitleTranslationProgress({
    required this.total,
    required this.done,
    required this.failed,
    required this.completed,
  });

  final int total;
  final int done;
  final int failed;
  final bool completed;

  double get ratio => total == 0 ? 1.0 : done / total;
}

/// 服务对外回调：每次有新译文产出 / 全量完成时触发。
typedef SubtitleTranslationListener = void Function(
  SubtitleTranslationSession session,
  SubtitleTranslationProgress progress,
);

/// 单次翻译会话：解析、按优先级翻译、增量序列化。
class SubtitleTranslationSession {
  SubtitleTranslationSession({
    required this.sessionId,
    required this.parsed,
    required this.providerId,
    required this.targetLang,
    required this.bilingual,
    required this.cacheKey,
  });

  final String sessionId;
  final ParsedSubtitle parsed;
  final String providerId;
  final String targetLang;
  final bool bilingual;
  final String cacheKey;

  /// index → 译文。
  /// - key 不存在：未尝试翻译
  /// - value 为 null：已尝试但失败（不再重试）
  /// - value 非空字符串：翻译成功
  final Map<int, String?> translations = {};

  bool cancelled = false;

  Duration anchor = Duration.zero;

  int get total => parsed.cues.length;
  int get done => translations.values.where((v) => v != null && v.isNotEmpty).length;
  int get failed => translations.values.where((v) => v == null).length;

  SubtitleTranslationProgress snapshot({required bool completed}) =>
      SubtitleTranslationProgress(
        total: total,
        done: done,
        failed: failed,
        completed: completed,
      );

  /// 当前序列化的字幕内容（未翻译段 fallback 原文）。
  String currentContent() => SubtitleSerializer.serialize(
        parsed,
        translations: translations,
        bilingual: bilingual,
      );

  void updateAnchor(Duration position) {
    anchor = position;
  }
}

/// 视频字幕翻译服务：单例。
class SubtitleTranslationService {
  SubtitleTranslationService._();
  static final SubtitleTranslationService instance = SubtitleTranslationService._();

  /// 优先翻译当前位置 ±[priorityWindow]
  static const Duration priorityWindow = Duration(seconds: 60);

  final Dio _dio = Dio();
  final _listeners = <SubtitleTranslationListener>[];

  SubtitleTranslationSession? _active;

  SubtitleTranslationSession? get active => _active;

  void addListener(SubtitleTranslationListener l) => _listeners.add(l);
  void removeListener(SubtitleTranslationListener l) => _listeners.remove(l);

  void _emit(SubtitleTranslationSession s, {required bool completed}) {
    final progress = s.snapshot(completed: completed);
    for (final l in List.of(_listeners)) {
      l(s, progress);
    }
  }

  /// 创建并启动一个翻译会话。
  ///
  /// - 先尝试命中磁盘缓存，命中则立刻返回 session（进度=完成）
  /// - 否则后台启动翻译循环，每写入一段后触发 listener
  ///
  /// [initialAnchor] 把当前播放位置传进来，让首批 cue 就按优先级排序。
  Future<SubtitleTranslationSession?> start({
    required String subtitleContent,
    required SubtitleFormat format,
    required String targetLang,
    required bool bilingual,
    bool useCache = true,
    String? providerId,
    TranslationProvider? provider,
    Duration initialAnchor = Duration.zero,
  }) async {
    cancelActive();

    final resolvedProvider = provider ?? TranslationProviders.byId(providerId);
    final parsed = SubtitleParser.parse(subtitleContent, format);
    if (parsed.cues.isEmpty) {
      logger.w('SubtitleTranslation: 字幕没有可翻译的 cue');
      return null;
    }

    final cacheKey = _cacheKey(
      content: subtitleContent,
      providerId: resolvedProvider.id,
      targetLang: targetLang,
      bilingual: bilingual,
    );

    final session = SubtitleTranslationSession(
      sessionId: cacheKey,
      parsed: parsed,
      providerId: resolvedProvider.id,
      targetLang: targetLang,
      bilingual: bilingual,
      cacheKey: cacheKey,
    )..anchor = initialAnchor;
    _active = session;

    // 1. 尝试 cache
    if (useCache) {
      final cached = await _loadCache(cacheKey);
      if (cached != null && cached.length == parsed.cues.length) {
        for (var i = 0; i < parsed.cues.length; i++) {
          session.translations[parsed.cues[i].index] = cached[i];
        }
        logger.i('SubtitleTranslation: 命中缓存 ($cacheKey, ${cached.length} cues)');
        _emit(session, completed: true);
        return session;
      }
    }

    // 2. 后台翻译
    AppError.fireAndForget(
      _runSession(session, resolvedProvider, useCache: useCache),
      action: 'subtitleTranslation.run',
    );

    return session;
  }

  void cancelActive() {
    final s = _active;
    if (s != null) {
      s.cancelled = true;
      _active = null;
      logger.i('SubtitleTranslation: 取消会话 ${s.sessionId}');
    }
  }

  void updateAnchor(Duration position) {
    final s = _active;
    if (s != null && !s.cancelled) {
      s.updateAnchor(position);
    }
  }

  Future<void> _runSession(
    SubtitleTranslationSession session,
    TranslationProvider provider, {
    required bool useCache,
  }) async {
    const batchSize = 8;
    while (!session.cancelled) {
      final pending = _pickBatch(session, batchSize);
      if (pending.isEmpty) break;
      final indices = pending.map((c) => c.index).toList();
      final texts = pending.map((c) => c.originalText).toList();
      List<String?> results;
      try {
        results = await provider.translate(
          texts: texts,
          targetLangBcp47: session.targetLang,
        );
      } catch (e, st) {
        AppError.handle(e, st, 'subtitleTranslation.batch');
        results = List<String?>.filled(texts.length, null);
      }
      if (session.cancelled) break;
      for (var i = 0; i < indices.length; i++) {
        session.translations[indices[i]] = results[i];
      }
      _emit(session, completed: false);
    }

    if (session.cancelled) return;

    final completed = session.done + session.failed >= session.total;
    if (completed) {
      _emit(session, completed: true);
      if (useCache && session.failed == 0) {
        await _saveCache(session);
      }
    }
  }

  /// 按"距 anchor 的时间距离"挑下一批 cue。
  /// 用 [Map.containsKey] 区分"已尝试但失败"和"未尝试"，避免失败 cue 反复重试导致死循环。
  List<SubtitleCue> _pickBatch(SubtitleTranslationSession session, int n) {
    final anchorMs = session.anchor.inMilliseconds;
    final priorityMs = priorityWindow.inMilliseconds;
    final remaining = <SubtitleCue>[];
    for (final cue in session.parsed.cues) {
      if (session.translations.containsKey(cue.index)) continue;
      remaining.add(cue);
    }
    if (remaining.isEmpty) return const [];
    remaining.sort((a, b) {
      final da = _distanceMs(a, anchorMs);
      final db = _distanceMs(b, anchorMs);
      final aIn = da <= priorityMs;
      final bIn = db <= priorityMs;
      if (aIn && !bIn) return -1;
      if (!aIn && bIn) return 1;
      if (da != db) return da.compareTo(db);
      return a.index.compareTo(b.index);
    });
    return remaining.take(n).toList();
  }

  int _distanceMs(SubtitleCue cue, int anchorMs) {
    final s = cue.start.inMilliseconds;
    final e = cue.end.inMilliseconds;
    if (anchorMs >= s && anchorMs <= e) return 0;
    if (anchorMs < s) return s - anchorMs;
    return anchorMs - e;
  }

  /// 从订阅过的字幕 URL 拉原始内容。供 UI 调用，让它能脱离 NAS 文件系统。
  Future<String?> fetchContent(String url) async {
    try {
      final resp = await _dio.get<dynamic>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
      final data = resp.data;
      if (data is List<int>) {
        return _decodeBytes(data);
      }
      if (data is String) return data;
    } catch (e, st) {
      AppError.handle(e, st, 'subtitleTranslation.fetchContent');
    }
    return null;
  }

  String _decodeBytes(List<int> bytes) {
    try {
      if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
        return utf8.decode(bytes.sublist(3));
      }
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes);
    }
  }

  // ---------- cache ----------

  String _cacheKey({
    required String content,
    required String providerId,
    required String targetLang,
    required bool bilingual,
  }) {
    final raw = utf8.encode('$providerId|$targetLang|${bilingual ? 'bi' : 'mono'}|$content');
    return sha1.convert(raw).toString();
  }

  Future<Directory> _cacheDir() async {
    final base = await getApplicationCacheDirectory();
    final dir = Directory(p.join(base.path, 'subtitle_translations'));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<List<String?>?> _loadCache(String key) async {
    try {
      final dir = await _cacheDir();
      final file = File(p.join(dir.path, '$key.json'));
      if (!file.existsSync()) return null;
      final raw = await file.readAsString();
      final data = jsonDecode(raw);
      if (data is! List) return null;
      return data.map((e) => e as String?).toList();
    } catch (e, st) {
      AppError.ignore(e, st, 'SubtitleTranslation: 读取缓存失败');
      return null;
    }
  }

  Future<void> _saveCache(SubtitleTranslationSession session) async {
    try {
      final dir = await _cacheDir();
      final file = File(p.join(dir.path, '${session.cacheKey}.json'));
      final list = session.parsed.cues
          .map((c) => session.translations[c.index])
          .toList();
      await file.writeAsString(jsonEncode(list));
      logger.d('SubtitleTranslation: 缓存已写入 ${file.path}');
    } catch (e, st) {
      AppError.ignore(e, st, 'SubtitleTranslation: 写入缓存失败');
    }
  }

  /// 清空翻译缓存（供设置页"清除缓存"用）。
  Future<void> clearCache() async {
    try {
      final dir = await _cacheDir();
      if (dir.existsSync()) {
        await dir.delete(recursive: true);
      }
    } catch (e, st) {
      AppError.ignore(e, st, 'SubtitleTranslation: 清空缓存失败');
    }
  }
}
