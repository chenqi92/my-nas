import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/domain/entities/source_form_config.dart';
import 'package:my_nas/nas_adapters/base/nas_adapter.dart';
import 'package:my_nas/nas_adapters/base/nas_connection.dart';
import 'package:my_nas/nas_adapters/s3/s3_adapter.dart';
import 'package:my_nas/nas_adapters/s3/s3_object_client.dart';

void main() {
  test('S3 source is selectable, writable, and configured securely', () {
    expect(SourceType.s3.isSupported, isTrue);
    expect(SourceType.s3.supportsFileSystem, isTrue);
    expect(SourceType.s3.defaultUseSsl, isTrue);
    final fields = SourceFormConfig.forType(
      SourceType.s3,
    ).sections.expand((section) => section.fields).toList();
    expect(
      fields.map((field) => field.key),
      containsAll(['host', 'bucket', 'username', 'password', 'sessionToken']),
    );

    final source = SourceEntity(
      name: 'Object Storage',
      type: SourceType.s3,
      host: 's3.example.test',
      username: 'access-key',
      extraConfig: const {
        'bucket': 'media',
        'sessionToken': 'temporary-secret',
      },
    );
    final json = source.toJson(includeSecrets: false);
    expect(json['extraConfig'], {'bucket': 'media'});
  });

  test('adapter validates bucket access before exposing file system', () async {
    final client = _BucketClient();
    final adapter = S3Adapter(clientFactory: (_) => client);
    final config = ConnectionConfig(
      type: NasAdapterType.s3,
      host: 's3.example.test',
      port: 443,
      username: 'access',
      password: 'secret',
      extraConfig: const {'bucket': 'media', 'rootPrefix': 'library'},
    );

    final result = await adapter.connect(config);

    expect(result, isA<ConnectionSuccess>());
    expect(adapter.isConnected, isTrue);
    expect(await adapter.checkConnectionHealth(), isTrue);
    expect(adapter.fileSystem.supportsServerSideCopy, isTrue);
    await adapter.dispose();
    expect(adapter.isConnected, isFalse);
  });

  test('adapter reports inaccessible buckets without connecting', () async {
    final client = _BucketClient()..available = false;
    final adapter = S3Adapter(clientFactory: (_) => client);
    final result = await adapter.connect(
      const ConnectionConfig(
        type: NasAdapterType.s3,
        host: 's3.example.test',
        port: 443,
        username: 'access',
        password: 'secret',
        extraConfig: {'bucket': 'missing'},
      ),
    );

    expect(result, isA<ConnectionFailure>());
    expect(adapter.isConnected, isFalse);
  });

  test('failed health checks invalidate an established session', () async {
    final client = _BucketClient();
    final adapter = S3Adapter(clientFactory: (_) => client);
    final result = await adapter.connect(
      const ConnectionConfig(
        type: NasAdapterType.s3,
        host: 's3.example.test',
        port: 443,
        username: 'access',
        password: 'secret',
        extraConfig: {'bucket': 'media'},
      ),
    );
    expect(result, isA<ConnectionSuccess>());

    client.available = false;
    expect(await adapter.checkConnectionHealth(), isFalse);
    expect(adapter.isConnected, isFalse);
    expect(() => adapter.fileSystem, throwsStateError);
  });
}

class _BucketClient implements S3ObjectClient {
  bool available = true;

  @override
  Future<bool> bucketExists(String bucket) async => available;

  @override
  Future<void> copyObject(String bucket, String object, String sourceObject) =>
      throw UnimplementedError();

  @override
  Future<Stream<List<int>>> getObject(
    String bucket,
    String object, {
    int? offset,
    int? length,
  }) => throw UnimplementedError();

  @override
  Stream<S3ListPage> listObjects(
    String bucket, {
    String prefix = '',
    bool recursive = false,
  }) => const Stream.empty();

  @override
  Future<String> presignedGetObject(
    String bucket,
    String object, {
    required int expires,
  }) => throw UnimplementedError();

  @override
  Future<void> putFile(
    String bucket,
    String object,
    String localPath, {
    void Function(int sent)? onProgress,
  }) => throw UnimplementedError();

  @override
  Future<void> putObject(
    String bucket,
    String object,
    Stream<Uint8List> data, {
    required int size,
    void Function(int sent)? onProgress,
  }) => throw UnimplementedError();

  @override
  Future<void> removeObject(String bucket, String object) =>
      throw UnimplementedError();

  @override
  Future<void> removeObjects(String bucket, List<String> objects) =>
      throw UnimplementedError();

  @override
  Future<S3ObjectInfo> statObject(String bucket, String object) =>
      throw UnimplementedError();
}
