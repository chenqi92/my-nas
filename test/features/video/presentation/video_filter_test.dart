import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/features/video/presentation/pages/video_list_desktop_page.dart';

VideoMetadata _meta({
  bool watched = false,
  String? genres,
  String sourceId = 's1',
}) => VideoMetadata.fromMap({
  'filePath': '/movies/a.mkv',
  'sourceId': sourceId,
  'fileName': 'a.mkv',
  'isWatched': watched,
  'genres': genres,
});

void main() {
  group('videoMatchesFilter', () {
    test('watched=all passes regardless of watch state', () {
      expect(
        videoMatchesFilter(_meta(watched: true), watched: 'all', genres: {}),
        isTrue,
      );
      expect(videoMatchesFilter(_meta(), watched: 'all', genres: {}), isTrue);
    });

    test('watched=watched only passes watched items', () {
      expect(
        videoMatchesFilter(
          _meta(watched: true),
          watched: 'watched',
          genres: {},
        ),
        isTrue,
      );
      expect(
        videoMatchesFilter(_meta(), watched: 'watched', genres: {}),
        isFalse,
      );
    });

    test('watched=unwatched only passes unwatched items', () {
      expect(
        videoMatchesFilter(_meta(), watched: 'unwatched', genres: {}),
        isTrue,
      );
      expect(
        videoMatchesFilter(
          _meta(watched: true),
          watched: 'unwatched',
          genres: {},
        ),
        isFalse,
      );
    });

    test('empty genre set does not restrict', () {
      expect(
        videoMatchesFilter(
          _meta(genres: 'Action'),
          watched: 'all',
          genres: {},
        ),
        isTrue,
      );
    });

    test('genre filter passes when any genre matches', () {
      final m = _meta(genres: 'Action / Drama');
      expect(videoMatchesFilter(m, watched: 'all', genres: {'Drama'}), isTrue);
      expect(
        videoMatchesFilter(m, watched: 'all', genres: {'Comedy'}),
        isFalse,
      );
      expect(
        videoMatchesFilter(m, watched: 'all', genres: {'Comedy', 'Action'}),
        isTrue,
      );
    });

    test('item without genres fails a non-empty genre filter', () {
      expect(
        videoMatchesFilter(_meta(), watched: 'all', genres: {'Action'}),
        isFalse,
      );
    });

    test('empty source set does not restrict', () {
      expect(
        videoMatchesFilter(
          _meta(sourceId: 's1'),
          watched: 'all',
          genres: {},
        ),
        isTrue,
      );
    });

    test('source filter keeps only selected sources', () {
      expect(
        videoMatchesFilter(
          _meta(sourceId: 's1'),
          watched: 'all',
          genres: {},
          sources: {'s1'},
        ),
        isTrue,
      );
      expect(
        videoMatchesFilter(
          _meta(sourceId: 's2'),
          watched: 'all',
          genres: {},
          sources: {'s1'},
        ),
        isFalse,
      );
    });

    test('watch and genre conditions compose (AND)', () {
      final m = _meta(watched: true, genres: 'Action / Drama');
      expect(
        videoMatchesFilter(m, watched: 'watched', genres: {'Action'}),
        isTrue,
      );
      // genre matches but watch state does not -> fails
      expect(
        videoMatchesFilter(m, watched: 'unwatched', genres: {'Action'}),
        isFalse,
      );
    });
  });
}
