import 'dart:io';
import 'dart:typed_data';

import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/nas_adapters/s3/s3_object_client.dart';
import 'package:path/path.dart' as p;

class S3FileSystem implements NasFileSystem {
  S3FileSystem({
    required S3ObjectClient client,
    required String bucket,
    String rootPrefix = '',
  }) : _client = client,
       _bucket = bucket,
       _rootPrefix = _normalizeKey(rootPrefix);

  final S3ObjectClient _client;
  final String _bucket;
  final String _rootPrefix;
  final HttpClient _httpClient = HttpClient();

  static const int _maxSearchResults = 200;

  @override
  bool get supportsWriteOperations => true;

  @override
  bool get supportsServerSideCopy => true;

  @override
  bool get supportsDirectFileUrl => true;

  void dispose() => _httpClient.close(force: true);

  @override
  Future<List<FileItem>> listDirectory(String path) async {
    final prefix = _directoryPrefix(path);
    final entries = <String, FileItem>{};
    await for (final page in _client.listObjects(_bucket, prefix: prefix)) {
      for (final childPrefix in page.prefixes) {
        final key = childPrefix.endsWith('/')
            ? childPrefix.substring(0, childPrefix.length - 1)
            : childPrefix;
        final item = _directoryItem(key);
        entries[item.path] = item;
      }
      for (final object in page.objects) {
        if (object.key == prefix) continue;
        final relative = object.key.substring(prefix.length);
        if (relative.isEmpty) continue;
        if (relative.endsWith('/')) {
          final item = _directoryItem(
            object.key.substring(0, object.key.length - 1),
          );
          entries[item.path] = item;
        } else if (!relative.contains('/')) {
          final item = _fileItem(object);
          entries[item.path] = item;
        }
      }
    }
    final values = entries.values.toList()
      ..sort((a, b) {
        if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return values;
  }

  @override
  Future<FileItem> getFileInfo(String path) async {
    if (_isRoot(path)) {
      return const FileItem(name: '', path: '/', isDirectory: true, size: 0);
    }
    final key = _objectKey(path);
    try {
      return _fileItem(await _client.statObject(_bucket, key));
    } on Exception {
      final prefix = '$key/';
      await for (final page in _client.listObjects(_bucket, prefix: prefix)) {
        if (page.objects.isNotEmpty || page.prefixes.isNotEmpty) {
          return _directoryItem(key);
        }
      }
      throw S3PathNotFound(path);
    }
  }

  @override
  Future<Stream<List<int>>> getFileStream(String path, {FileRange? range}) {
    final length = range?.end == null ? null : range!.end! - range.start;
    if (length != null && length <= 0) {
      return Future.value(const Stream.empty());
    }
    return _client.getObject(
      _bucket,
      _objectKey(path),
      offset: range?.start,
      length: length,
    );
  }

  @override
  Future<Stream<List<int>>> getUrlStream(String url) async {
    final request = await _httpClient.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.drain<void>();
      throw HttpException(
        'S3 URL returned HTTP ${response.statusCode}',
        uri: Uri.parse(url),
      );
    }
    return response;
  }

  @override
  Future<String> getFileUrl(String path, {Duration? expiry}) {
    final seconds = (expiry ?? const Duration(hours: 1)).inSeconds.clamp(
      1,
      7 * 24 * 60 * 60,
    );
    return _client.presignedGetObject(
      _bucket,
      _objectKey(path),
      expires: seconds,
    );
  }

  @override
  Future<void> createDirectory(String path) async {
    if (_isRoot(path)) return;
    final marker = _directoryPrefix(path);
    await _client.putObject(
      _bucket,
      marker,
      Stream.value(Uint8List(0)),
      size: 0,
    );
  }

  @override
  Future<void> delete(String path) async {
    if (_isRoot(path)) {
      throw ArgumentError.value(path, 'path', 'Cannot delete the S3 root.');
    }
    final item = await getFileInfo(path);
    if (!item.isDirectory) {
      await _client.removeObject(_bucket, _objectKey(path));
      return;
    }
    final keys = <String>[];
    await for (final page in _client.listObjects(
      _bucket,
      prefix: _directoryPrefix(path),
      recursive: true,
    )) {
      keys.addAll(page.objects.map((object) => object.key));
    }
    if (keys.isNotEmpty) await _client.removeObjects(_bucket, keys);
  }

  @override
  Future<void> rename(String oldPath, String newPath) => move(oldPath, newPath);

  @override
  Future<void> copy(String sourcePath, String destPath) async {
    final source = await getFileInfo(sourcePath);
    if (!source.isDirectory) {
      await _client.copyObject(
        _bucket,
        _objectKey(destPath),
        _objectKey(sourcePath),
      );
      return;
    }

    final sourcePrefix = _directoryPrefix(sourcePath);
    final destinationPrefix = _directoryPrefix(destPath);
    var copied = false;
    await for (final page in _client.listObjects(
      _bucket,
      prefix: sourcePrefix,
      recursive: true,
    )) {
      for (final object in page.objects) {
        final suffix = object.key.substring(sourcePrefix.length);
        await _client.copyObject(
          _bucket,
          '$destinationPrefix$suffix',
          object.key,
        );
        copied = true;
      }
    }
    if (!copied) await createDirectory(destPath);
  }

  @override
  Future<void> move(String sourcePath, String destPath) async {
    await copy(sourcePath, destPath);
    await delete(sourcePath);
  }

  @override
  Future<void> upload(
    String localPath,
    String remotePath, {
    String? fileName,
    void Function(int sent, int total)? onProgress,
  }) async {
    final file = File(localPath);
    final stat = await file.stat();
    final name = fileName ?? p.basename(localPath);
    final key = _objectKey(_joinRemote(remotePath, name));
    await _client.putFile(
      _bucket,
      key,
      localPath,
      onProgress: (sent) => onProgress?.call(sent, stat.size),
    );
  }

  @override
  Future<void> writeFile(String remotePath, List<int> data) =>
      _client.putObject(
        _bucket,
        _objectKey(remotePath),
        Stream.value(Uint8List.fromList(data)),
        size: data.length,
      );

  @override
  Future<List<FileItem>> search(String query, {String? path}) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return const [];
    final results = <FileItem>[];
    await for (final page in _client.listObjects(
      _bucket,
      prefix: _directoryPrefix(path ?? '/'),
      recursive: true,
    )) {
      for (final object in page.objects) {
        if (object.key.endsWith('/')) continue;
        final displayPath = _displayPath(object.key);
        if (displayPath.toLowerCase().contains(normalized)) {
          results.add(_fileItem(object));
          if (results.length >= _maxSearchResults) return results;
        }
      }
    }
    return results;
  }

  @override
  Future<String?> getThumbnailUrl(String path, {ThumbnailSize? size}) {
    if (FileType.fromExtension(p.posix.extension(path)) != FileType.image) {
      return Future.value();
    }
    return getFileUrl(path, expiry: const Duration(hours: 1));
  }

  @override
  Future<Uint8List?> getThumbnailData(String path, {ThumbnailSize? size}) =>
      Future.value();

  FileItem _directoryItem(String key) {
    final path = _displayPath(key);
    return FileItem(
      name: p.posix.basename(path),
      path: path,
      isDirectory: true,
      size: 0,
    );
  }

  FileItem _fileItem(S3ObjectInfo object) {
    final path = _displayPath(object.key);
    return FileItem(
      name: p.posix.basename(path),
      path: path,
      isDirectory: false,
      size: object.size,
      modifiedTime: object.lastModified,
      extension: p.posix.extension(path),
    );
  }

  String _directoryPrefix(String path) {
    final key = _objectKey(path);
    if (key.isEmpty) return '';
    return key.endsWith('/') ? key : '$key/';
  }

  String _objectKey(String path) {
    final relative = _normalizeKey(path);
    if (_rootPrefix.isEmpty) return relative;
    if (relative.isEmpty) return _rootPrefix;
    return '$_rootPrefix/$relative';
  }

  String _displayPath(String key) {
    var relative = _normalizeKey(key);
    if (_rootPrefix.isNotEmpty) {
      if (relative == _rootPrefix) return '/';
      final prefix = '$_rootPrefix/';
      if (relative.startsWith(prefix)) {
        relative = relative.substring(prefix.length);
      }
    }
    return relative.isEmpty ? '/' : '/$relative';
  }

  static String _joinRemote(String directory, String name) {
    final base = directory == '/'
        ? ''
        : directory.replaceAll(RegExp(r'/+$'), '');
    return '$base/$name';
  }

  static bool _isRoot(String path) => path.isEmpty || path == '/';

  static String _normalizeKey(String value) {
    final segments = value
        .replaceAll(r'\', '/')
        .split('/')
        .where((segment) => segment.isNotEmpty && segment != '.')
        .toList();
    if (segments.contains('..')) {
      throw ArgumentError.value(value, 'path', 'Parent traversal is invalid.');
    }
    return segments.join('/');
  }
}

class S3PathNotFound implements Exception {
  const S3PathNotFound(this.path);

  final String path;

  @override
  String toString() => 'S3 path not found: $path';
}
