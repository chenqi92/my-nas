import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/features/music/data/services/music_scrape_matcher.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_result.dart';
import 'package:my_nas/features/music/domain/entities/music_scraper_source.dart';

void main() {
  MusicScraperItem item(
    String id,
    String title, {
    String? artist,
    String? album,
    int? durationMs,
    double? score,
  }) => MusicScraperItem(
    externalId: id,
    source: MusicScraperType.musicBrainz,
    title: title,
    artist: artist,
    album: album,
    durationMs: durationMs,
    score: score,
  );

  group('MusicScrapeMatcher', () {
    test('rejects a same-title recording from a different known artist', () {
      final result = MusicScrapeMatcher.bestMatch(
        [
          item('wrong', '青丝', artist: 'Music Gate', score: 1),
          item('right', '青丝', artist: '等什么君', score: 0.8),
        ],
        title: '青丝',
        artist: '等什么君',
      );

      expect(result?.externalId, 'right');
    });

    test('uses duration to rank title-compatible candidates', () {
      final result = MusicScrapeMatcher.bestMatch(
        [
          item('far', 'Hello (Live)', durationMs: 180000, score: 1),
          item('near', 'Hello', durationMs: 241500, score: 0.5),
        ],
        title: 'Hello',
        durationMs: 242000,
      );

      expect(result?.externalId, 'near');
    });

    test('normalizes edition brackets and separators', () {
      expect(
        MusicScrapeMatcher.normalize('  Song Title（Live） - Remastered  '),
        'songtitleremastered',
      );
    });

    test('returns null when no title is compatible', () {
      final result = MusicScrapeMatcher.bestMatch(
        [item('wrong', 'Completely Different', artist: 'Artist')],
        title: 'Expected Song',
        artist: 'Artist',
      );

      expect(result, isNull);
    });
  });
}
