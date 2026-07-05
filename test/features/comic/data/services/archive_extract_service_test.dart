import 'dart:io';

import 'package:archive/archive.dart' as archive_lib;
import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/features/comic/data/services/archive_extract_service.dart';
import 'package:path/path.dart' as path;

void main() {
  test(
    'extractImagesToDirectory writes image files without path traversal',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'mynas_archive_extract_test_',
      );

      try {
        final archive = archive_lib.Archive()
          ..addFile(archive_lib.ArchiveFile.bytes('page-002.jpg', [2]))
          ..addFile(archive_lib.ArchiveFile.bytes('folder/page-001.png', [1]))
          ..addFile(archive_lib.ArchiveFile.bytes('notes.txt', [9]))
          ..addFile(archive_lib.ArchiveFile.bytes('../evil.jpg', [6]));

        final zipBytes = archive_lib.ZipEncoder().encode(archive);

        final archiveFile = File(path.join(tempDir.path, 'comic.cbz'));
        await archiveFile.writeAsBytes(zipBytes);

        final outputDir = Directory(path.join(tempDir.path, 'pages'));
        final result = await ArchiveExtractService().extractImagesToDirectory(
          archiveFile: archiveFile,
          archiveType: ArchiveType.zip,
          outputDir: outputDir,
        );

        expect(result.success, isTrue);
        expect(result.files.map((file) => file.name), [
          'folder/page-001.png',
          'page-002.jpg',
        ]);
        expect(
          await File(path.join(tempDir.path, 'evil.jpg')).exists(),
          isFalse,
        );
        expect(await File(result.files.first.path).readAsBytes(), [1]);
      } finally {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    },
  );
}
