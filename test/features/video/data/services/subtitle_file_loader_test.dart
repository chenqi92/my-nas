import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:my_nas/features/video/data/services/subtitle_file_loader.dart';
import 'package:my_nas/features/video/data/services/subtitle_service.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

class _FileSystem extends Mock implements NasFileSystem {}

void main() {
  late Directory directory;
  setUp(
    () async =>
        directory = await Directory.systemTemp.createTemp('subtitle_test_'),
  );
  tearDown(() async => directory.delete(recursive: true));

  test(
    'virtual NAS subtitles become readable files without losing Chinese text',
    () async {
      final fs = _FileSystem();
      const text = '1\n00:00:01,000 --> 00:00:04,000\n中文字幕\n';
      when(
        () => fs.getFileStream('/movie.zh.srt'),
      ).thenAnswer((_) async => Stream.value(utf8.encode(text)));
      const subtitle = SubtitleItem(
        name: 'movie.zh.srt',
        path: '/movie.zh.srt',
        url: 'smb://smb-local/movie.zh.srt',
        format: 'srt',
      );
      final first = await loadSubtitleFile(
        subtitle,
        sourceId: 'nas-a',
        fileSystem: fs,
        directory: directory,
      );
      final second = await loadSubtitleFile(
        subtitle,
        sourceId: 'nas-b',
        fileSystem: fs,
        directory: directory,
      );
      expect(await File.fromUri(Uri.parse(first)).readAsString(), text);
      expect(first, isNot(second));
      expect(first, endsWith('.srt'));
    },
  );

  test(
    'bitmap subtitle codecs require native rendering while text stays customizable',
    () {
      expect(isBitmapSubtitleCodec('hdmv_pgs_subtitle'), isTrue);
      expect(isBitmapSubtitleCodec('dvd_subtitle'), isTrue);
      expect(isBitmapSubtitleCodec('ass'), isFalse);
      expect(isBitmapSubtitleCodec('subrip'), isFalse);
    },
  );
}
