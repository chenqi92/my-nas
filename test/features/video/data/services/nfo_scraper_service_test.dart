import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:my_nas/features/video/data/services/nfo_scraper_service.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

class _FileSystem extends Mock implements NasFileSystem {}

void main() {
  late _FileSystem fileSystem;
  late Map<String, String> files;
  setUp(() {
    files = {};
    fileSystem = _FileSystem();
    when(() => fileSystem.listDirectory(any())).thenAnswer((call) async {
      final directory = call.positionalArguments.first as String;
      return files.keys
          .where(
            (path) => path.substring(0, path.lastIndexOf('/')) == directory,
          )
          .map(
            (path) => FileItem(
              name: path.split('/').last,
              path: path,
              isDirectory: false,
              size: 0,
            ),
          )
          .toList();
    });
    when(() => fileSystem.getFileStream(any())).thenAnswer(
      (call) async =>
          Stream.value(utf8.encode(files[call.positionalArguments.first]!)),
    );
  });

  test('local artwork is returned without an NFO file', () async {
    files['/movies/Example/poster.jpg'] = '';
    files['/movies/Example/fanart.jpg'] = '';
    final result = await NfoScraperService().scrapeFromDirectory(
      fileSystem: fileSystem,
      videoPath: '/movies/Example/video.mkv',
      videoFileName: 'video.mkv',
    );
    expect(result!.posterPath, '/movies/Example/poster.jpg');
    expect(result.fanartPath, '/movies/Example/fanart.jpg');
    expect(result.hasData, isFalse);
  });

  test(
    'sidecar artwork wins over folder art and ignores other movies',
    () async {
      files['/movies/other-poster.jpg'] = '';
      files['/movies/poster.jpg'] = '';
      files['/movies/video-poster.png'] = '';
      final directoryItems = await fileSystem.listDirectory('/movies');
      final result = await NfoScraperService().quickParseFromDirectory(
        fileSystem: fileSystem,
        directoryItems: directoryItems,
        videoDir: '/movies',
        videoBaseName: 'video',
      );
      expect(result!.posterPath, '/movies/video-poster.png');
      expect(result.hasData, isFalse);
      expect(
        NfoScraperService.findLocalImages(
          directoryItems
              .where((file) => file.name == 'other-poster.jpg')
              .toList(),
          'video',
        )['poster'],
        isNull,
      );
      verifyNever(() => fileSystem.getFileStream(any()));
    },
  );

  test(
    'shared episode NFO never changes another file into the same episode',
    () async {
      files['/tv/Show/episode.nfo'] =
          '<episodedetails><title>First</title><season>1</season><episode>1</episode></episodedetails>';
      files['/tv/Show/tvshow.nfo'] =
          '<tvshow><title>Show</title><tmdbid>123</tmdbid></tvshow>';
      final result = await NfoScraperService().scrapeFromDirectory(
        fileSystem: fileSystem,
        videoPath: '/tv/Show/Show.S01E20.mkv',
        videoFileName: 'Show.S01E20.mkv',
      );
      expect(result!.seasonNumber, 1);
      expect(result.episodeNumber, 20);
      expect(result.tmdbId, 123);
    },
  );

  test('show-only NFO keeps the episode identity from the filename', () async {
    files['/tv/Show/tvshow.nfo'] =
        '<tvshow><title>Show</title><tmdbid>123</tmdbid></tvshow>';
    final result = await NfoScraperService().scrapeFromDirectory(
      fileSystem: fileSystem,
      videoPath: '/tv/Show/Season 1/Show.S01E19.mkv',
      videoFileName: 'Show.S01E19.mkv',
    );
    expect(result!.title, 'Show');
    expect(result.seasonNumber, 1);
    expect(result.episodeNumber, 19);
  });
}
