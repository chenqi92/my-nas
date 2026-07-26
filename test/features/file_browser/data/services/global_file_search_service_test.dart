import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:my_nas/features/file_browser/data/services/global_file_search_service.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

class _MockFileSystem extends Mock implements NasFileSystem {}

void main() {
  group('searchConnectedFileSystems', () {
    test('uses adapter search and keeps source identity', () async {
      final fileSystem = _MockFileSystem();
      when(() => fileSystem.search('movie', path: '/media')).thenAnswer(
        (_) async => const [
          FileItem(
            name: 'movie.mkv',
            path: '/media/movie.mkv',
            isDirectory: false,
            size: 10,
          ),
        ],
      );

      final hits = await searchConnectedFileSystems([
        GlobalFileSearchSource(
          id: 'nas-1',
          name: '客厅 NAS',
          rootPath: '/media',
          fileSystem: fileSystem,
        ),
      ], ' movie ');

      expect(hits, hasLength(1));
      expect(hits.single.sourceId, 'nas-1');
      expect(hits.single.sourceName, '客厅 NAS');
      expect(hits.single.file.path, '/media/movie.mkv');
    });

    test(
      'falls back to recursive traversal when native search is empty',
      () async {
        final fileSystem = _MockFileSystem();
        when(
          () => fileSystem.search('report', path: '/'),
        ).thenAnswer((_) async => const []);
        when(() => fileSystem.listDirectory('/')).thenAnswer(
          (_) async => const [
            FileItem(
              name: 'documents',
              path: '/documents',
              isDirectory: true,
              size: 0,
            ),
          ],
        );
        when(() => fileSystem.listDirectory('/documents')).thenAnswer(
          (_) async => const [
            FileItem(
              name: 'annual-report.pdf',
              path: '/documents/annual-report.pdf',
              isDirectory: false,
              size: 100,
            ),
          ],
        );

        final hits = await searchConnectedFileSystems([
          GlobalFileSearchSource(
            id: 'nas-2',
            name: '资料库',
            fileSystem: fileSystem,
          ),
        ], 'report');

        expect(hits.single.file.path, '/documents/annual-report.pdf');
        verify(() => fileSystem.listDirectory('/documents')).called(1);
      },
    );
  });

  test('parentDirectoryOf handles root and Windows separators', () {
    expect(parentDirectoryOf('/movie.mkv'), '/');
    expect(parentDirectoryOf('/media/movie.mkv'), '/media');
    expect(parentDirectoryOf(r'C:\media\movie.mkv'), 'C:/media');
  });
}
