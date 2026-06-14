import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/features/video/data/services/subtitle_translation/subtitle_format.dart';
import 'package:my_nas/features/video/data/services/subtitle_translation/subtitle_parser.dart';
import 'package:my_nas/features/video/data/services/subtitle_translation/subtitle_serializer.dart';

void main() {
  group('SubtitleSerializer.srt', () {
    const src = '''
1
00:00:01,000 --> 00:00:03,500
Hello world

2
00:00:04,000 --> 00:00:05,000
Second
''';

    test('未翻译段保留原文', () {
      final parsed = SubtitleParser.parse(src, SubtitleFormat.srt);
      final out = SubtitleSerializer.serialize(parsed, translations: {});
      expect(out, contains('Hello world'));
      expect(out, contains('Second'));
      expect(out, contains('00:00:01,000 --> 00:00:03,500'));
    });

    test('已翻译段使用译文', () {
      final parsed = SubtitleParser.parse(src, SubtitleFormat.srt);
      final out = SubtitleSerializer.serialize(
        parsed,
        translations: {0: '你好世界'},
      );
      expect(out, contains('你好世界'));
      expect(out, isNot(contains('Hello world')));
      expect(out, contains('Second'));
    });

    test('bilingual 同时输出译文和原文', () {
      final parsed = SubtitleParser.parse(src, SubtitleFormat.srt);
      final out = SubtitleSerializer.serialize(
        parsed,
        translations: {0: '你好世界'},
        bilingual: true,
      );
      expect(out, contains('你好世界'));
      expect(out, contains('Hello world'));
    });
  });

  group('SubtitleSerializer.ass', () {
    const src = '''
[Script Info]
Title: Sample

[V4+ Styles]
Format: Name, Fontname, Fontsize
Style: Default,Arial,20

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:01.00,0:00:03.50,Default,Actor,5,5,10,Effect1,Hello, world
''';

    test('保留 header 与样式行', () {
      final parsed = SubtitleParser.parse(src, SubtitleFormat.ass);
      final out = SubtitleSerializer.serialize(parsed, translations: {});
      expect(out, contains('[Script Info]'));
      expect(out, contains('[V4+ Styles]'));
      expect(out, contains('Style: Default,Arial,20'));
      expect(out, contains('Format: Layer, Start, End'));
    });

    test('Dialogue 字段按 Format 顺序还原，非 Text 字段保持原值', () {
      final parsed = SubtitleParser.parse(src, SubtitleFormat.ass);
      final out = SubtitleSerializer.serialize(
        parsed,
        translations: {0: '你好世界'},
      );
      expect(out, contains('你好世界'));
      expect(out, isNot(contains('Hello, world')));
      expect(out, contains('Default,Actor,5,5,10,Effect1'));
    });

    test(r'译文换行序列化为 \N', () {
      final parsed = SubtitleParser.parse(src, SubtitleFormat.ass);
      final out = SubtitleSerializer.serialize(
        parsed,
        translations: {0: '第一行\n第二行'},
      );
      expect(out, contains(r'第一行\N第二行'));
    });
  });

  group('SubtitleSerializer.vtt', () {
    const src = '''
WEBVTT

00:00:01.000 --> 00:00:02.000
Hello

00:00:03.000 --> 00:00:04.000
World
''';

    test('保留 WEBVTT 头', () {
      final parsed = SubtitleParser.parse(src, SubtitleFormat.vtt);
      final out = SubtitleSerializer.serialize(parsed, translations: {});
      expect(out, startsWith('WEBVTT'));
      expect(out, contains('00:00:01.000 --> 00:00:02.000'));
    });

    test('翻译后时间码不变', () {
      final parsed = SubtitleParser.parse(src, SubtitleFormat.vtt);
      final out = SubtitleSerializer.serialize(
        parsed,
        translations: {0: '你好', 1: '世界'},
      );
      expect(out, contains('00:00:01.000 --> 00:00:02.000'));
      expect(out, contains('00:00:03.000 --> 00:00:04.000'));
      expect(out, contains('你好'));
      expect(out, contains('世界'));
      expect(out, isNot(contains('Hello')));
      expect(out, isNot(contains('World')));
    });
  });

  group('Parser ↔ Serializer 往返', () {
    test('SRT: 全部翻译后能再次解析回相同 cue 数', () {
      const src = '''
1
00:00:01,000 --> 00:00:02,000
Foo

2
00:00:03,000 --> 00:00:04,000
Bar
''';
      final parsed = SubtitleParser.parse(src, SubtitleFormat.srt);
      final out = SubtitleSerializer.serialize(
        parsed,
        translations: {0: 'A', 1: 'B'},
      );
      final reparsed = SubtitleParser.parse(out, SubtitleFormat.srt);
      expect(reparsed.cues, hasLength(2));
      expect(reparsed.cues[0].originalText, equals('A'));
      expect(reparsed.cues[1].originalText, equals('B'));
      expect(reparsed.cues[0].start, equals(parsed.cues[0].start));
    });
  });
}
