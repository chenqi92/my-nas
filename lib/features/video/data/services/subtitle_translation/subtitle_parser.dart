import 'package:my_nas/features/video/data/services/subtitle_translation/subtitle_format.dart';

/// 解析 SRT/ASS/VTT 字幕文本 → [ParsedSubtitle]。
class SubtitleParser {
  SubtitleParser._();

  static ParsedSubtitle parse(String content, SubtitleFormat format) {
    switch (format) {
      case SubtitleFormat.srt:
        return _parseSrt(content);
      case SubtitleFormat.vtt:
        return _parseVtt(content);
      case SubtitleFormat.ass:
        return _parseAss(content);
    }
  }

  // ---------- SRT ----------

  static final _srtTimeRe = RegExp(
    r'(\d+):(\d{2}):(\d{2})[,.](\d{1,3})\s*-->\s*(\d+):(\d{2}):(\d{2})[,.](\d{1,3})',
  );

  static ParsedSubtitle _parseSrt(String content) {
    final cues = <SubtitleCue>[];
    final blocks = content.replaceAll('\r\n', '\n').split(RegExp(r'\n\s*\n'));
    var idx = 0;
    for (final raw in blocks) {
      final block = raw.trim();
      if (block.isEmpty) continue;
      final lines = block.split('\n');
      var timeLineIdx = 0;
      if (lines.isNotEmpty && int.tryParse(lines.first.trim()) != null) {
        timeLineIdx = 1;
      }
      if (timeLineIdx >= lines.length) continue;
      final m = _srtTimeRe.firstMatch(lines[timeLineIdx]);
      if (m == null) continue;
      final start = _toDuration(m.group(1)!, m.group(2)!, m.group(3)!, m.group(4)!);
      final end = _toDuration(m.group(5)!, m.group(6)!, m.group(7)!, m.group(8)!);
      final text = lines.skip(timeLineIdx + 1).join('\n').trim();
      if (text.isEmpty) continue;
      cues.add(SubtitleCue(
        index: idx++,
        start: start,
        end: end,
        originalText: text,
      ));
    }
    return ParsedSubtitle(format: SubtitleFormat.srt, cues: cues);
  }

  // ---------- VTT ----------

  static final _vttTimeRe = RegExp(
    r'(\d+):(\d{2}):(\d{2})\.(\d{1,3})\s*-->\s*(\d+):(\d{2}):(\d{2})\.(\d{1,3})',
  );
  static final _vttTimeShortRe = RegExp(
    r'(\d{2}):(\d{2})\.(\d{1,3})\s*-->\s*(\d{2}):(\d{2})\.(\d{1,3})',
  );

  static ParsedSubtitle _parseVtt(String content) {
    final normalized = content.replaceAll('\r\n', '\n');
    final blocks = normalized.split(RegExp(r'\n\s*\n'));
    final cues = <SubtitleCue>[];
    var idx = 0;
    var headerCaptured = false;
    var header = 'WEBVTT';
    for (final raw in blocks) {
      final block = raw.trim();
      if (block.isEmpty) continue;
      if (!headerCaptured) {
        if (block.startsWith('WEBVTT')) {
          header = block;
          headerCaptured = true;
          continue;
        }
        headerCaptured = true;
      }
      final lines = block.split('\n');
      var timeLineIdx = 0;
      if (!lines[0].contains('-->')) {
        timeLineIdx = 1;
      }
      if (timeLineIdx >= lines.length) continue;
      final line = lines[timeLineIdx];
      Duration? start;
      Duration? end;
      final m = _vttTimeRe.firstMatch(line);
      if (m != null) {
        start = _toDuration(m.group(1)!, m.group(2)!, m.group(3)!, m.group(4)!);
        end = _toDuration(m.group(5)!, m.group(6)!, m.group(7)!, m.group(8)!);
      } else {
        final m2 = _vttTimeShortRe.firstMatch(line);
        if (m2 != null) {
          start = _toDuration('0', m2.group(1)!, m2.group(2)!, m2.group(3)!);
          end = _toDuration('0', m2.group(4)!, m2.group(5)!, m2.group(6)!);
        }
      }
      if (start == null || end == null) continue;
      final text = lines.skip(timeLineIdx + 1).join('\n').trim();
      if (text.isEmpty) continue;
      cues.add(SubtitleCue(
        index: idx++,
        start: start,
        end: end,
        originalText: text,
      ));
    }
    return ParsedSubtitle(format: SubtitleFormat.vtt, cues: cues, header: header);
  }

  // ---------- ASS / SSA ----------

  static ParsedSubtitle _parseAss(String content) {
    final normalized = content.replaceAll('\r\n', '\n');
    final lines = normalized.split('\n');
    final headerLines = <String>[];
    final cues = <SubtitleCue>[];
    List<String>? eventFormat;
    var inEvents = false;
    var idx = 0;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.toLowerCase().startsWith('[events]')) {
        inEvents = true;
        headerLines.add(line);
        continue;
      }
      if (inEvents && trimmed.startsWith('[')) {
        inEvents = false;
        headerLines.add(line);
        continue;
      }
      if (inEvents) {
        if (trimmed.toLowerCase().startsWith('format:')) {
          eventFormat = trimmed
              .substring(7)
              .split(',')
              .map((s) => s.trim())
              .toList();
          headerLines.add(line);
          continue;
        }
        if (trimmed.toLowerCase().startsWith('dialogue:') && eventFormat != null) {
          final cue = _parseAssDialogue(line, eventFormat, idx);
          if (cue != null) {
            cues.add(cue);
            idx++;
            continue;
          }
        }
        headerLines.add(line);
      } else {
        headerLines.add(line);
      }
    }
    return ParsedSubtitle(
      format: SubtitleFormat.ass,
      cues: cues,
      header: headerLines.join('\n'),
      eventFormat: eventFormat,
    );
  }

  static SubtitleCue? _parseAssDialogue(
    String rawLine,
    List<String> format,
    int idx,
  ) {
    // "Dialogue: <fields>" — 最后一个字段 Text 可能包含逗号
    final prefixIdx = rawLine.indexOf(':');
    if (prefixIdx < 0) return null;
    final body = rawLine.substring(prefixIdx + 1).trimLeft();
    final fieldCount = format.length;
    final fields = <String>[];
    var start = 0;
    var found = 0;
    for (var i = 0; i < body.length && found < fieldCount - 1; i++) {
      if (body[i] == ',') {
        fields.add(body.substring(start, i));
        start = i + 1;
        found++;
      }
    }
    fields.add(body.substring(start));
    if (fields.length != fieldCount) return null;
    final fmtMap = <String, String>{
      for (var i = 0; i < fieldCount; i++) format[i].toLowerCase(): fields[i]
    };
    final startStr = fmtMap['start'];
    final endStr = fmtMap['end'];
    final text = fmtMap['text'] ?? '';
    if (startStr == null || endStr == null) return null;
    final s = _parseAssTime(startStr.trim());
    final e = _parseAssTime(endStr.trim());
    if (s == null || e == null) return null;
    final extra = Map<String, String>.from(fmtMap)..remove('text');
    return SubtitleCue(
      index: idx,
      start: s,
      end: e,
      originalText: text,
      extra: extra,
    );
  }

  static Duration? _parseAssTime(String t) {
    // h:mm:ss.cs（cs = 百分秒）
    final parts = t.split(':');
    if (parts.length != 3) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final secParts = parts[2].split('.');
    final s = int.tryParse(secParts[0]);
    final cs = secParts.length > 1 ? int.tryParse(secParts[1]) ?? 0 : 0;
    if (h == null || m == null || s == null) return null;
    return Duration(hours: h, minutes: m, seconds: s, milliseconds: cs * 10);
  }

  static Duration _toDuration(String h, String m, String s, String ms) {
    final hi = int.parse(h);
    final mi = int.parse(m);
    final si = int.parse(s);
    var msi = int.parse(ms);
    if (ms.length == 1) {
      msi *= 100;
    } else if (ms.length == 2) {
      msi *= 10;
    }
    return Duration(hours: hi, minutes: mi, seconds: si, milliseconds: msi);
  }
}
