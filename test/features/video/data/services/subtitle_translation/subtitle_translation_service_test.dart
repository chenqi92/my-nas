import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/core/translation/translation_provider.dart';
import 'package:my_nas/features/video/data/services/subtitle_translation/subtitle_format.dart';
import 'package:my_nas/features/video/data/services/subtitle_translation/subtitle_translation_service.dart';

/// 测试用 provider：记录每次 translate 收到的批次，并按需阻塞 / 失败。
class _RecordingProvider implements TranslationProvider {
  _RecordingProvider({this.failAll = false, this.gate});

  @override
  String get id => 'fake';
  @override
  String get displayName => 'Fake';

  /// 每次 translate 收到的 texts 顺序快照
  final List<List<String>> batches = [];

  /// 设为 true 时，所有翻译都返回 null（模拟全部失败）
  final bool failAll;

  /// 如果非空，每次 translate 在返回前等这个 Future（用来精确控制时序）
  final Future<void>? gate;

  @override
  Future<List<String?>> translate({
    required List<String> texts,
    required String targetLangBcp47,
    String? sourceLangBcp47,
  }) async {
    batches.add(List.of(texts));
    if (gate != null) await gate!;
    if (failAll) return List<String?>.filled(texts.length, null);
    return texts.map<String?>((t) => '[$targetLangBcp47]$t').toList();
  }
}

/// 构造一个 SRT，cues 在 0s, 10s, 20s, ..., (n-1)*10s 处，每条文本是 line-{i}。
String _buildSrt(int n) {
  final buf = StringBuffer();
  for (var i = 0; i < n; i++) {
    final start = Duration(seconds: i * 10);
    final end = Duration(seconds: i * 10 + 5);
    buf
      ..writeln(i + 1)
      ..writeln('${_fmt(start)} --> ${_fmt(end)}')
      ..writeln('line-$i')
      ..writeln();
  }
  return buf.toString();
}

String _fmt(Duration d) {
  final h = d.inHours.toString().padLeft(2, '0');
  final m = (d.inMinutes % 60).toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  final ms = (d.inMilliseconds % 1000).toString().padLeft(3, '0');
  return '$h:$m:$s,$ms';
}

/// 先注册 listener，再 start session，等 completed=true。
/// 必须先 addListener 再 start —— `_runSession` 的 emit 在 microtask 队列里，
/// start 返回之前可能已经跑完。
Future<(SubtitleTranslationSession, SubtitleTranslationProgress)> _drive(
  SubtitleTranslationService service,
  Future<SubtitleTranslationSession?> Function() startFn,
) async {
  final completer = Completer<SubtitleTranslationProgress>();
  void listener(SubtitleTranslationSession s, SubtitleTranslationProgress p) {
    if (p.completed && !completer.isCompleted) completer.complete(p);
  }

  service.addListener(listener);
  try {
    final session = await startFn();
    if (session == null) {
      throw StateError('start() returned null');
    }
    final progress = await completer.future.timeout(const Duration(seconds: 5));
    return (session, progress);
  } finally {
    service.removeListener(listener);
  }
}

void main() {
  setUp(SubtitleTranslationService.instance.cancelActive);

  group('SubtitleTranslationService.start', () {
    test('能够把全部 cue 都翻译完成并写入 session.translations', () async {
      final provider = _RecordingProvider();
      final service = SubtitleTranslationService.instance;
      final (session, progress) = await _drive(
        service,
        () => service.start(
          subtitleContent: _buildSrt(5),
          format: SubtitleFormat.srt,
          targetLang: 'zh-CN',
          bilingual: false,
          useCache: false,
          provider: provider,
        ),
      );
      expect(progress.completed, isTrue);
      expect(progress.done, equals(5));
      expect(progress.failed, equals(0));
      for (var i = 0; i < 5; i++) {
        expect(session.translations[i], equals('[zh-CN]line-$i'));
      }
    });

    test('cue 数为 0 时返回 null', () async {
      final provider = _RecordingProvider();
      final session = await SubtitleTranslationService.instance.start(
        subtitleContent: 'WEBVTT\n\n',
        format: SubtitleFormat.vtt,
        targetLang: 'zh-CN',
        bilingual: false,
        useCache: false,
        provider: provider,
      );
      expect(session, isNull);
    });
  });

  group('优先级排序', () {
    test('initialAnchor → 第一批是 anchor 附近的 cue', () async {
      // 12 个 cue，每 10s 一个。anchor=50s。priorityWindow=60s。
      // batchSize=8，首批应包含 cue index 5, 4, 6, 3, 7, 2, 8, 1。
      final provider = _RecordingProvider();
      final service = SubtitleTranslationService.instance;
      await _drive(
        service,
        () => service.start(
          subtitleContent: _buildSrt(12),
          format: SubtitleFormat.srt,
          targetLang: 'zh-CN',
          bilingual: false,
          useCache: false,
          provider: provider,
          initialAnchor: const Duration(seconds: 50),
        ),
      );

      expect(provider.batches, isNotEmpty);
      final first = provider.batches.first;
      expect(first, contains('line-5'));
      expect(first, isNot(contains('line-0')));
      expect(first, isNot(contains('line-11')));
    });

    test('cancelActive 之后不再翻译剩余 batch', () async {
      final gate = Completer<void>();
      final provider = _RecordingProvider(gate: gate.future);
      final service = SubtitleTranslationService.instance;
      final session = await service.start(
        subtitleContent: _buildSrt(20),
        format: SubtitleFormat.srt,
        targetLang: 'zh-CN',
        bilingual: false,
        useCache: false,
        provider: provider,
      );
      expect(session, isNotNull);
      // 让第一批进入 provider 后再 cancel
      await Future<void>.delayed(const Duration(milliseconds: 50));
      service.cancelActive();
      gate.complete();
      // 给后台一些时间确认 cancel 生效
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(session!.cancelled, isTrue);
      // 至多只跑过一批（cancel 时正在跑的那一批）
      expect(provider.batches.length, lessThanOrEqualTo(1));
      // 已 cancel 的 batch 不应该写入 translations
      expect(session.done, equals(0));
    });
  });

  group('失败处理', () {
    test('全部失败时仍能完成会话，failed 计数正确', () async {
      final provider = _RecordingProvider(failAll: true);
      final service = SubtitleTranslationService.instance;
      final (_, progress) = await _drive(
        service,
        () => service.start(
          subtitleContent: _buildSrt(3),
          format: SubtitleFormat.srt,
          targetLang: 'zh-CN',
          bilingual: false,
          useCache: false,
          provider: provider,
        ),
      );
      expect(progress.completed, isTrue);
      expect(progress.done, equals(0));
      expect(progress.failed, equals(3));
    });
  });

  group('snapshot / currentContent', () {
    test('未翻译段 fallback 原文，完成后输出译文', () async {
      final provider = _RecordingProvider();
      final service = SubtitleTranslationService.instance;
      final (session, _) = await _drive(
        service,
        () => service.start(
          subtitleContent: _buildSrt(3),
          format: SubtitleFormat.srt,
          targetLang: 'zh-CN',
          bilingual: false,
          useCache: false,
          provider: provider,
        ),
      );
      final after = session.currentContent();
      expect(after, contains('[zh-CN]line-0'));
      expect(after, contains('00:00:00,000 --> 00:00:05,000'));
      expect(after, isNot(contains('\nline-0\n')));
    });
  });
}
