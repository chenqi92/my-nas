import 'package:my_nas/features/video/data/services/subtitle_translation/subtitle_format.dart';

/// 把翻译后的字幕重新序列化回原格式。
class SubtitleSerializer {
  SubtitleSerializer._();

  /// 重新生成字幕全文。
  /// - [translations] index → 译文。缺失/为 null 的项使用原文
  /// - [bilingual] = true 时同时输出两行（译文在上、原文在下）
  static String serialize(
    ParsedSubtitle parsed, {
    required Map<int, String?> translations,
    bool bilingual = false,
  }) {
    switch (parsed.format) {
      case SubtitleFormat.srt:
        return _serializeSrt(parsed, translations, bilingual: bilingual);
      case SubtitleFormat.vtt:
        return _serializeVtt(parsed, translations, bilingual: bilingual);
      case SubtitleFormat.ass:
        return _serializeAss(parsed, translations, bilingual: bilingual);
    }
  }

  static String _serializeSrt(
    ParsedSubtitle parsed,
    Map<int, String?> translations, {
    required bool bilingual,
  }) {
    final buf = StringBuffer();
    for (var i = 0; i < parsed.cues.length; i++) {
      final cue = parsed.cues[i];
      final translated = translations[cue.index];
      final text = _pickText(cue.originalText, translated, bilingual: bilingual);
      buf
        ..writeln(i + 1)
        ..writeln('${_srtTime(cue.start)} --> ${_srtTime(cue.end)}')
        ..writeln(text)
        ..writeln();
    }
    return buf.toString();
  }

  static String _serializeVtt(
    ParsedSubtitle parsed,
    Map<int, String?> translations, {
    required bool bilingual,
  }) {
    final buf = StringBuffer();
    final header = parsed.header.isEmpty ? 'WEBVTT' : parsed.header;
    buf
      ..writeln(header)
      ..writeln();
    for (final cue in parsed.cues) {
      final translated = translations[cue.index];
      final text = _pickText(cue.originalText, translated, bilingual: bilingual);
      buf
        ..writeln('${_vttTime(cue.start)} --> ${_vttTime(cue.end)}')
        ..writeln(text)
        ..writeln();
    }
    return buf.toString();
  }

  static String _serializeAss(
    ParsedSubtitle parsed,
    Map<int, String?> translations, {
    required bool bilingual,
  }) {
    final buf = StringBuffer()..writeln(parsed.header.trimRight());
    if (!parsed.header.toLowerCase().contains('[events]')) {
      buf
        ..writeln('[Events]')
        ..writeln('Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text');
    }
    final eventFormat = parsed.eventFormat ??
        ['Layer', 'Start', 'End', 'Style', 'Name', 'MarginL', 'MarginR', 'MarginV', 'Effect', 'Text'];
    for (final cue in parsed.cues) {
      final translated = translations[cue.index];
      final text = _pickText(cue.originalText, translated, bilingual: bilingual);
      final parts = <String>[];
      for (final field in eventFormat) {
        final key = field.toLowerCase();
        if (key == 'start') {
          parts.add(_assTime(cue.start));
        } else if (key == 'end') {
          parts.add(_assTime(cue.end));
        } else if (key == 'text') {
          parts.add(text.replaceAll('\n', r'\N'));
        } else {
          parts.add(cue.extra?[key] ?? '');
        }
      }
      buf.writeln('Dialogue: ${parts.join(',')}');
    }
    return buf.toString();
  }

  static String _pickText(
    String original,
    String? translated, {
    required bool bilingual,
  }) {
    if (translated == null || translated.trim().isEmpty) return original;
    if (!bilingual) return translated;
    return '$translated\n$original';
  }

  static String _srtTime(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    final ms = (d.inMilliseconds % 1000).toString().padLeft(3, '0');
    return '$h:$m:$s,$ms';
  }

  static String _vttTime(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    final ms = (d.inMilliseconds % 1000).toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }

  static String _assTime(Duration d) {
    final h = d.inHours;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    final cs = ((d.inMilliseconds % 1000) ~/ 10).toString().padLeft(2, '0');
    return '$h:$m:$s.$cs';
  }
}
