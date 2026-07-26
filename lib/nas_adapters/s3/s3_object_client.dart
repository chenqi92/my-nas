import 'dart:io';
import 'dart:typed_data';

import 'package:minio/io.dart';
import 'package:minio/minio.dart';

class S3ObjectInfo {
  const S3ObjectInfo({
    required this.key,
    required this.size,
    this.lastModified,
    this.etag,
  });

  final String key;
  final int size;
  final DateTime? lastModified;
  final String? etag;
}

class S3ListPage {
  const S3ListPage({required this.objects, required this.prefixes});

  final List<S3ObjectInfo> objects;
  final List<String> prefixes;
}

/// Narrow MinIO facade so the file-system semantics can be tested without a
/// live object-storage account.
abstract class S3ObjectClient {
  Future<bool> bucketExists(String bucket);

  Stream<S3ListPage> listObjects(
    String bucket, {
    String prefix = '',
    bool recursive = false,
  });

  Future<S3ObjectInfo> statObject(String bucket, String object);

  Future<Stream<List<int>>> getObject(
    String bucket,
    String object, {
    int? offset,
    int? length,
  });

  Future<String> presignedGetObject(
    String bucket,
    String object, {
    required int expires,
  });

  Future<void> putObject(
    String bucket,
    String object,
    Stream<Uint8List> data, {
    required int size,
    void Function(int sent)? onProgress,
  });

  Future<void> putFile(
    String bucket,
    String object,
    String localPath, {
    void Function(int sent)? onProgress,
  });

  Future<void> copyObject(String bucket, String object, String sourceObject);

  Future<void> removeObject(String bucket, String object);

  Future<void> removeObjects(String bucket, List<String> objects);
}

class MinioS3ObjectClient implements S3ObjectClient {
  MinioS3ObjectClient(this._client);

  final Minio _client;

  @override
  Future<bool> bucketExists(String bucket) => _client.bucketExists(bucket);

  @override
  Stream<S3ListPage> listObjects(
    String bucket, {
    String prefix = '',
    bool recursive = false,
  }) async* {
    await for (final page in _client.listObjects(
      bucket,
      prefix: prefix,
      recursive: recursive,
    )) {
      yield S3ListPage(
        prefixes: page.prefixes,
        objects: [
          for (final object in page.objects)
            if (object.key != null)
              S3ObjectInfo(
                key: object.key!,
                size: object.size ?? 0,
                lastModified: object.lastModified,
                etag: object.eTag,
              ),
        ],
      );
    }
  }

  @override
  Future<S3ObjectInfo> statObject(String bucket, String object) async {
    final stat = await _client.statObject(bucket, object, retrieveAcls: false);
    return S3ObjectInfo(
      key: object,
      size: stat.size ?? 0,
      lastModified: stat.lastModified,
      etag: stat.etag,
    );
  }

  @override
  Future<Stream<List<int>>> getObject(
    String bucket,
    String object, {
    int? offset,
    int? length,
  }) async {
    if (offset != null || length != null) {
      return _client.getPartialObject(bucket, object, offset, length);
    }
    return _client.getObject(bucket, object);
  }

  @override
  Future<String> presignedGetObject(
    String bucket,
    String object, {
    required int expires,
  }) => _client.presignedGetObject(bucket, object, expires: expires);

  @override
  Future<void> putObject(
    String bucket,
    String object,
    Stream<Uint8List> data, {
    required int size,
    void Function(int sent)? onProgress,
  }) async {
    await _client.putObject(
      bucket,
      object,
      data,
      size: size,
      onProgress: onProgress,
    );
  }

  @override
  Future<void> putFile(
    String bucket,
    String object,
    String localPath, {
    void Function(int sent)? onProgress,
  }) async {
    if (!await File(localPath).exists()) {
      throw FileSystemException('Upload source does not exist', localPath);
    }
    await _client.fPutObject(bucket, object, localPath, onProgress: onProgress);
  }

  @override
  Future<void> copyObject(
    String bucket,
    String object,
    String sourceObject,
  ) async {
    await _client.copyObject(bucket, object, '$bucket/$sourceObject');
  }

  @override
  Future<void> removeObject(String bucket, String object) =>
      _client.removeObject(bucket, object);

  @override
  Future<void> removeObjects(String bucket, List<String> objects) =>
      _client.removeObjects(bucket, objects);
}
