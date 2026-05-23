import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/features/video/data/services/subtitle_translation/subtitle_format.dart';
import 'package:my_nas/features/video/data/services/subtitle_translation/subtitle_parser.dart';

void main() {
  group('SubtitleParser.srt', () {
    test('解析标准 SRT', () {
      const content = '''1
00:00:01,000 --> 00:00:03,500
Hello world

2
00:00:04,000 --> 00:00:05,000
Multi
line
''';
      final parsed = SubtitleParser.parse(content, SubtitleFormat.srt);
      expect(parsed.cues, hasLength(2));
      expect(parsed.cues[0].start, equals(const Duration(seconds: 1)));
      expect(
        parsed.cues[0].end,
        equals(const Duration(seconds: 3, milliseconds: 500)),
      );
      expect(parsed.cues[0].originalText, equals('Hello world'));
      expect(parsed.cues[1].originalText, equals('Multi\nline'));
    });

    test('SRT 缺少编号行也能解析', () {
      const content = '''00:00:01,000 --> 00:00:02,000
No index line
''';
      final parsed = SubtitleParser.parse(content, SubtitleFormat.srt);
      expect(parsed.cues, hasLength(1));
      expect(parsed.cues[0].originalText, equals('No index line'));
    });

    test('SRT 时间码同时支持 . 和 , 分隔毫秒', () {
      const content = '''1
00:00:01.000 --> 00:00:02.500
Dot separator
''';
      final parsed = SubtitleParser.parse(content, SubtitleFormat.srt);
      expect(parsed.cues, hasLength(1));
      expect(
        parsed.cues[0].end,
        equals(const Duration(seconds: 2, milliseconds: 500)),
      );
    });
  });

  group('SubtitleParser.vtt', () {
    test('解析标准 VTT', () {
      const content = '''WEBVTT

00:00:01.000 --> 00:00:02.500
Subtitle one

00:00:03.000 --> 00:00:04.000
Subtitle two
''';
      final parsed = SubtitleParser.parse(content, SubtitleFormat.vtt);
      expect(parsed.header, equals('WEBVTT'));
      expect(parsed.cues, hasLength(2));
      expect(parsed.cues[0].originalText, equals('Subtitle one'));
    });

    test('VTT 允许 cue identifier', () {
      const content = '''WEBVTT

cue-1
00:00:01.000 --> 00:00:02.000
Has identifier
''';
      final parsed = SubtitleParser.parse(content, SubtitleFormat.vtt);
      expect(parsed.cues, hasLength(1));
      expect(parsed.cues[0].originalText, equals('Has identifier'));
    });
  });

  group('SubtitleParser.ass', () {
    const sample = '''[Script Info]
Title: Sample
ScriptType: v4.00+

[V4+ Styles]
Format: Name, Fontname, Fontsize
Style: Default,Arial,20

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:01.00,0:00:03.50,Default,,0,0,0,,Hello, world
Dialogue: 0,0:00:04.00,0:00:05.00,Default,,0,0,0,,{\\b1}Bold{\\b0} text, with comma
''';

    test('保留 header / Format 行', () {
      final parsed = SubtitleParser.parse(sample, SubtitleFormat.ass);
      expect(parsed.header, contains('[Script Info]'));
      expect(parsed.header, contains('[V4+ Styles]'));
      expect(parsed.header, contains('[Events]'));
      expect(parsed.eventFormat, contains('Text'));
      expect(parsed.eventFormat!.length, equals(10));
    });

    test('正确识别 Dialogue 时间与文本（Text 字段允许含逗号）', () {
      final parsed = SubtitleParser.parse(sample, SubtitleFormat.ass);
      expect(parsed.cues, hasLength(2));
      final c0 = parsed.cues[0];
      expect(c0.start, equals(const Duration(seconds: 1)));
      expect(
        c0.end,
        equals(const Duration(seconds: 3, milliseconds: 500)),
      );
      expect(c0.originalText, equals('Hello, world'));

      final c1 = parsed.cues[1];
      expect(c1.originalText, contains('Bold'));
      expect(c1.originalText, contains('with comma'));
      expect(c1.extra?['style'], equals('Default'));
      expect(c1.extra?['layer'], equals('0'));
    });
  });
}
