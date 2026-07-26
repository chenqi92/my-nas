import 'package:minio/minio.dart';
import 'package:my_nas/core/constants/app_constants.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_adapter.dart';
import 'package:my_nas/nas_adapters/base/nas_connection.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/nas_adapters/s3/s3_file_system.dart';
import 'package:my_nas/nas_adapters/s3/s3_object_client.dart';

typedef S3ObjectClientFactory =
    S3ObjectClient Function(ConnectionConfig config);

class S3Adapter implements NasAdapter {
  S3Adapter({S3ObjectClientFactory? clientFactory})
    : _clientFactory = clientFactory ?? _defaultClientFactory;

  final S3ObjectClientFactory _clientFactory;
  S3ObjectClient? _client;
  S3FileSystem? _fileSystem;
  ConnectionConfig? _config;
  bool _connected = false;

  @override
  NasAdapterInfo get info => const NasAdapterInfo(
    type: NasAdapterType.s3,
    name: 'S3 Compatible Storage',
    version: AppConstants.appVersion,
  );

  @override
  bool get isConnected => _connected;

  @override
  ConnectionConfig? get connection => _config;

  @override
  Future<ConnectionResult> connect(ConnectionConfig config) async {
    final bucket = _extraString(config, 'bucket');
    if (config.host.trim().isEmpty ||
        config.username.trim().isEmpty ||
        config.password.isEmpty ||
        bucket == null) {
      return const ConnectionFailure(
        error: 'S3 endpoint, access key, secret key, and bucket are required.',
      );
    }

    await disconnect();
    try {
      final client = _clientFactory(config);
      if (!await client.bucketExists(bucket)) {
        return ConnectionFailure(
          error: 'S3 bucket "$bucket" does not exist or is not accessible.',
        );
      }
      _client = client;
      _config = config;
      _fileSystem = S3FileSystem(
        client: client,
        bucket: bucket,
        rootPrefix: _extraString(config, 'rootPrefix') ?? '',
      );
      _connected = true;
      return ConnectionSuccess(
        sessionId: 's3-${DateTime.now().millisecondsSinceEpoch}',
        serverInfo: ServerInfo(hostname: config.host, model: 'S3 / $bucket'),
      );
    } on Exception catch (e, st) {
      logger.e('S3Adapter: connection failed', e, st);
      await disconnect();
      return ConnectionFailure(error: e.toString());
    }
  }

  @override
  Future<void> disconnect() async {
    _fileSystem?.dispose();
    _fileSystem = null;
    _client = null;
    _config = null;
    _connected = false;
  }

  @override
  Future<bool> checkConnectionHealth() async {
    final client = _client;
    final config = _config;
    final bucket = config == null ? null : _extraString(config, 'bucket');
    if (!_connected || client == null || bucket == null) return false;
    try {
      final healthy = await client.bucketExists(bucket);
      if (!healthy) _connected = false;
      return healthy;
    } on Exception catch (e, st) {
      logger.w('S3Adapter: health check failed', e, st);
      _connected = false;
      return false;
    }
  }

  @override
  NasFileSystem get fileSystem {
    final fileSystem = _fileSystem;
    if (!_connected || fileSystem == null) {
      throw StateError('S3 adapter is not connected.');
    }
    return fileSystem;
  }

  @override
  MediaService? get mediaService => null;

  @override
  ToolsService? get toolsService => null;

  @override
  Future<StorageInfo?> getStorageInfo() async => null;

  @override
  Future<void> dispose() => disconnect();

  static S3ObjectClient _defaultClientFactory(ConnectionConfig config) {
    final region = _extraString(config, 'region') ?? 'us-east-1';
    final sessionToken = _extraString(config, 'sessionToken');
    final pathStyle = _extraBool(config, 'pathStyle', fallback: true);
    return MinioS3ObjectClient(
      Minio(
        endPoint: config.host.trim(),
        port: config.port,
        useSSL: config.useSsl,
        accessKey: config.username,
        secretKey: config.password,
        sessionToken: sessionToken,
        region: region,
        pathStyle: pathStyle,
      ),
    );
  }

  static String? _extraString(ConnectionConfig config, String key) {
    final value = config.extraConfig?[key]?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }

  static bool _extraBool(
    ConnectionConfig config,
    String key, {
    required bool fallback,
  }) {
    final value = config.extraConfig?[key];
    if (value is bool) return value;
    if (value is String) {
      if (value.toLowerCase() == 'true') return true;
      if (value.toLowerCase() == 'false') return false;
    }
    return fallback;
  }
}
