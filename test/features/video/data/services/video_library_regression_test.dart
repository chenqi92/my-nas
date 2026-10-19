import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/features/video/data/services/video_database_service.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/features/video/domain/utils/episode_catalog.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final database = VideoDatabaseService();
  late Directory directory;
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    directory = await Directory.systemTemp.createTemp('video_library_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (_) async => directory.path);
    await database.init();
  });
  tearDownAll(() async {
    await database.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await directory.delete(recursive: true);
  });
  setUp(() async => database.clearAll());

  VideoMetadata episode(int number, {String source = 'nas-a'}) {
    final file =
        '熟女强人.Iron.Ladies.S01E${number.toString().padLeft(2, '0')}.'
        '2020.1080p.Hami.WEB-DL.AAC.H264-ZeroTV.mkv';
    return VideoMetadata(
      sourceId: source,
      filePath: '/tv/Iron Ladies/$file',
      fileName: file,
      category: MediaCategory.tvShow,
      tmdbId: 123,
      showDirectory: '/tv/Iron Ladies',
    );
  }

  test(
    'all twenty named episodes survive missing cached season numbers',
    () async {
      await database.upsertBatch(List.generate(20, (i) => episode(i + 1)));
      final episodes = await database.getEpisodesByTmdbId(123);
      expect(episodes[1]!.keys, containsAll(List.generate(20, (i) => i + 1)));
      expect(episodes[1], hasLength(20));
      final visible = mergedEpisodeNumbers(
        List.generate(19, (i) => i + 1),
        episodes[1]!.keys,
      );
      expect(visible, hasLength(20));
      expect(visible.last, 20);
    },
  );

  test(
    'versions preserve identical paths on different sources and ignore movies',
    () async {
      final original = episode(1);
      await database.upsertBatch([
        original,
        episode(1, source: 'nas-b'),
        episode(2),
        episode(
          1,
          source: 'movie-source',
        ).copyWith(category: MediaCategory.movie),
      ]);
      final versions = await database.getEpisodeVersions(original);
      expect(
        versions.map((v) => v.sourceId),
        unorderedEquals(['nas-a', 'nas-b']),
      );
      final files = await database.getShowFiles(tmdbId: 123);
      final selected = episodeRepresentatives(
        files,
        preferredSourceId: 'nas-b',
      );
      expect(selected[1]![1]!.sourceId, 'nas-b');
      expect(selected[1]![2]!.sourceId, 'nas-a');
      final scoped = await database.getShowFiles(
        showDirectory: '/tv/Iron Ladies',
        sourceId: 'nas-b',
      );
      expect(scoped, hasLength(1));
    },
  );

  test('a failed scrape does not hide a local episode from its show', () async {
    final missing = episode(20)..tmdbId = null;
    final foreign = episode(21, source: 'unrelated')..tmdbId = null;
    final mismatch = episode(22)..tmdbId = 999;
    await database.upsertBatch([
      ...List.generate(19, (i) => episode(i + 1)),
      missing,
      foreign,
      mismatch,
    ]);
    final episodes = await database.getEpisodesByTmdbId(123);
    expect(episodes[1], hasLength(20));
    expect(episodes[1]![20]!.filePath, missing.filePath);
    expect(episodes[1]!.containsKey(21), isFalse);
    expect(episodes[1]!.containsKey(22), isFalse);
  });

  test(
    'manual classification persists and removes incompatible TV identifiers',
    () async {
      final original = episode(1).copyWith(seasonNumber: 1, episodeNumber: 1);
      await database.upsert(original);
      await database.changeCategory(original, MediaCategory.movie);
      final saved = (await database.get(original.sourceId, original.filePath))!;
      expect(saved.category, MediaCategory.movie);
      expect(saved.tmdbId, isNull);
      expect(saved.seasonNumber, isNull);
      expect(saved.episodeNumber, isNull);
      expect(saved.showDirectory, isNull);
      expect(saved.scrapeStatus, ScrapeStatus.skipped);
      expect(await database.getEpisodesByTmdbId(123), isEmpty);
      expect(original.category, MediaCategory.tvShow);
    },
  );

  test('explicit season/episode wins over an earlier bracketed number', () {
    final parsed = VideoFileNameParser.parse(
      '[01].Iron.Ladies.S02E20.1080p.mkv',
    );
    expect(parsed.season, 2);
    expect(parsed.episode, 20);
  });

  test(
    'incremental scan can distinguish missing and existing local artwork',
    () async {
      final first = episode(
        1,
      ).copyWith(localPosterUrl: '/tv/Iron Ladies/poster.jpg');
      final second = episode(2);
      await database.upsertBatch([first, second]);
      final files = await database.getVideoFilesInDirectory(
        'nas-a',
        '/tv/Iron Ladies',
      );
      expect(files[first.filePath]!.localPosterUrl, first.localPosterUrl);
      expect(files[second.filePath]!.localPosterUrl, isNull);
    },
  );
}
