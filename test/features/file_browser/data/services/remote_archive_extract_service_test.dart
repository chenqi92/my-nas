import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:my_nas/features/file_browser/data/services/remote_archive_extract_service.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

class _MockFileSystem extends Mock implements NasFileSystem {}

void main() {
  test('extracts a remote ZIP safely and uploads its directory tree', () async {
    final temp = await Directory.systemTemp.createTemp('mynas_extract_test_');
    addTearDown(() => temp.delete(recursive: true));
    final encoded = ZipEncoder().encode(
      Archive()
        ..addFile(ArchiveFile.bytes('folder/a.txt', [1, 2, 3]))
        ..addFile(ArchiveFile.bytes('../escape.txt', [9])),
    );
    final fileSystem = _MockFileSystem();
    when(() => fileSystem.supportsWriteOperations).thenReturn(true);
    when(
      () => fileSystem.getFileStream('/downloads/bundle.zip'),
    ).thenAnswer((_) async => Stream.value(encoded));
    when(() => fileSystem.listDirectory('/downloads')).thenAnswer(
      (_) async => const [
        FileItem(
          name: 'bundle',
          path: '/downloads/bundle',
          isDirectory: true,
          size: 0,
        ),
      ],
    );
    final created = <String>[];
    when(() => fileSystem.createDirectory(any())).thenAnswer((
      invocation,
    ) async {
      created.add(invocation.positionalArguments.single as String);
    });
    final uploaded = <({String destination, String name, List<int> bytes})>[];
    when(
      () => fileSystem.upload(any(), any(), fileName: any(named: 'fileName')),
    ).thenAnswer((invocation) async {
      final localPath = invocation.positionalArguments[0] as String;
      uploaded.add((
        destination: invocation.positionalArguments[1] as String,
        name: invocation.namedArguments[#fileName] as String,
        bytes: await File(localPath).readAsBytes(),
      ));
    });

    final result = await RemoteArchiveExtractService(workingRoot: temp).extract(
      fileSystem: fileSystem,
      archive: const FileItem(
        name: 'bundle.zip',
        path: '/downloads/bundle.zip',
        isDirectory: false,
        size: 100,
      ),
      destinationDirectory: '/downloads',
    );

    expect(result.destinationPath, '/downloads/bundle (2)');
    expect(result.fileCount, 1);
    expect(created, contains('/downloads/bundle (2)/folder'));
    expect(uploaded, hasLength(1));
    expect(uploaded.single.destination, '/downloads/bundle (2)/folder');
    expect(uploaded.single.name, 'a.txt');
    expect(uploaded.single.bytes, [1, 2, 3]);
  });

  test('rejects traversal, absolute, and drive-prefixed archive paths', () {
    expect(safeArchiveRelativePath('../secret'), isNull);
    expect(safeArchiveRelativePath('/etc/passwd'), isNull);
    expect(safeArchiveRelativePath(r'C:\secret.txt'), isNull);
    expect(safeArchiveRelativePath(r'folder\ok.txt'), 'folder/ok.txt');
  });

  test('sanitizes archive entry segments illegal on Windows', () {
    // 首段的 `x:` 会先被盘符检查拒绝（返回 null），冒号清洗只对非首段生效。
    expect(safeArchiveRelativePath('a:b.txt'), isNull);
    expect(safeArchiveRelativePath('dir/a:b.txt'), 'dir/a_b.txt');
    expect(safeArchiveRelativePath('dir/re*port?.txt'), 'dir/re_port_.txt');
    expect(safeArchiveRelativePath('CON.txt'), '_CON.txt');
    expect(safeArchiveRelativePath('trailing. '), 'trailing');
  });

  test('recognizes supported archive names and output base names', () {
    expect(remoteArchiveKindForName('photos.ZIP'), RemoteArchiveKind.zip);
    expect(
      remoteArchiveKindForName('backup.tar.gz'),
      RemoteArchiveKind.tarGzip,
    );
    expect(remoteArchiveKindForName('legacy.rar'), isNull);
    expect(archiveBaseName('backup.tar.gz'), 'backup');
    expect(remotePathJoin('/', 'backup'), '/backup');
  });
}
