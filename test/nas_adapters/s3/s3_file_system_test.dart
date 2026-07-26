import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/nas_adapters/s3/s3_file_system.dart';
import 'package:my_nas/nas_adapters/s3/s3_object_client.dart';

void main() {
  group('S3FileSystem', () {
    test('maps object prefixes to scoped file-system paths', () async {
      final client = _FakeS3Client({
        'library/movies/action.mkv': [1, 2, 3],
        'library/readme.txt': [4, 5],
      });
      final fileSystem = S3FileSystem(
        client: client,
        bucket: 'media',
        rootPrefix: 'library',
      );

      final root = await fileSystem.listDirectory('/');

      expect(root.map((item) => item.path), ['/movies', '/readme.txt']);
      expect(root.first.isDirectory, isTrue);
      expect(root.last.size, 2);
      expect(await fileSystem.getFileInfo('/movies'), isA<FileItem>());
      fileSystem.dispose();
    });

    test('supports range reads and presigned direct URLs', () async {
      final client = _FakeS3Client({
        'root/video.bin': [0, 1, 2, 3, 4, 5],
      });
      final fileSystem = S3FileSystem(
        client: client,
        bucket: 'media',
        rootPrefix: 'root',
      );

      final stream = await fileSystem.getFileStream(
        '/video.bin',
        range: const FileRange(start: 2, end: 5),
      );
      expect(await stream.expand((chunk) => chunk).toList(), [2, 3, 4]);
      expect(
        await fileSystem.getFileUrl('/video.bin'),
        'https://example.test/media/root/video.bin?expires=3600',
      );
      fileSystem.dispose();
    });

    test('copies, moves, and recursively deletes directory objects', () async {
      final client = _FakeS3Client({
        'scope/source/': const [],
        'scope/source/a.txt': [1],
        'scope/source/nested/b.txt': [2],
      });
      final fileSystem = S3FileSystem(
        client: client,
        bucket: 'bucket',
        rootPrefix: 'scope',
      );

      await fileSystem.copy('/source', '/copy');
      expect(client.objects, contains('scope/copy/a.txt'));
      expect(client.objects, contains('scope/copy/nested/b.txt'));

      await fileSystem.move('/copy', '/moved');
      expect(client.objects, contains('scope/moved/a.txt'));
      expect(client.objects.keys, isNot(contains('scope/copy/a.txt')));

      await fileSystem.delete('/source');
      expect(
        client.objects.keys.where((key) => key.startsWith('scope/source/')),
        isEmpty,
      );
      fileSystem.dispose();
    });

    test(
      'writes byte content and blocks root deletion and traversal',
      () async {
        final client = _FakeS3Client();
        final fileSystem = S3FileSystem(
          client: client,
          bucket: 'bucket',
          rootPrefix: 'safe',
        );

        await fileSystem.writeFile('/notes/test.md', [7, 8, 9]);
        expect(client.objects['safe/notes/test.md'], [7, 8, 9]);
        await expectLater(fileSystem.delete('/'), throwsArgumentError);
        expect(
          () => fileSystem.writeFile('../escape.txt', [1]),
          throwsArgumentError,
        );
        fileSystem.dispose();
      },
    );
  });
}

class _FakeS3Client implements S3ObjectClient {
  _FakeS3Client([Map<String, List<int>> initial = const {}])
    : objects = {
        for (final entry in initial.entries)
          entry.key: Uint8List.fromList(entry.value),
      };

  final Map<String, Uint8List> objects;
  bool bucketAvailable = true;

  @override
  Future<bool> bucketExists(String bucket) async => bucketAvailable;

  @override
  Future<void> copyObject(
    String bucket,
    String object,
    String sourceObject,
  ) async {
    final value = objects[sourceObject];
    if (value == null) throw StateError('missing $sourceObject');
    objects[object] = Uint8List.fromList(value);
  }

  @override
  Future<Stream<List<int>>> getObject(
    String bucket,
    String object, {
    int? offset,
    int? length,
  }) async {
    final value = objects[object];
    if (value == null) throw S3PathNotFound(object);
    final start = offset ?? 0;
    final end = length == null ? value.length : start + length;
    return Stream.value(value.sublist(start, end));
  }

  @override
  Stream<S3ListPage> listObjects(
    String bucket, {
    String prefix = '',
    bool recursive = false,
  }) async* {
    final foundObjects = <S3ObjectInfo>[];
    final prefixes = <String>{};
    for (final entry in objects.entries) {
      if (!entry.key.startsWith(prefix)) continue;
      final remainder = entry.key.substring(prefix.length);
      if (remainder.isEmpty) {
        foundObjects.add(_info(entry.key, entry.value));
        continue;
      }
      final slash = remainder.indexOf('/');
      if (!recursive && slash >= 0 && slash < remainder.length - 1) {
        prefixes.add('$prefix${remainder.substring(0, slash + 1)}');
      } else {
        foundObjects.add(_info(entry.key, entry.value));
      }
    }
    yield S3ListPage(objects: foundObjects, prefixes: prefixes.toList());
  }

  @override
  Future<String> presignedGetObject(
    String bucket,
    String object, {
    required int expires,
  }) async => 'https://example.test/$bucket/$object?expires=$expires';

  @override
  Future<void> putFile(
    String bucket,
    String object,
    String localPath, {
    void Function(int sent)? onProgress,
  }) async {
    final bytes = await File(localPath).readAsBytes();
    objects[object] = bytes;
    onProgress?.call(bytes.length);
  }

  @override
  Future<void> putObject(
    String bucket,
    String object,
    Stream<Uint8List> data, {
    required int size,
    void Function(int sent)? onProgress,
  }) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in data) {
      builder.add(chunk);
      onProgress?.call(builder.length);
    }
    objects[object] = builder.takeBytes();
  }

  @override
  Future<void> removeObject(String bucket, String object) async {
    objects.remove(object);
  }

  @override
  Future<void> removeObjects(String bucket, List<String> objectKeys) async {
    for (final key in objectKeys) {
      objects.remove(key);
    }
  }

  @override
  Future<S3ObjectInfo> statObject(String bucket, String object) async {
    final value = objects[object];
    if (value == null) throw S3PathNotFound(object);
    return _info(object, value);
  }

  S3ObjectInfo _info(String key, Uint8List value) => S3ObjectInfo(
    key: key,
    size: value.length,
    lastModified: DateTime.utc(2026, 1, 1),
  );
}
