import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;

/// 一次读取到的 JSON 与同一 HTTP 响应中的实体版本。
///
/// [revision] 当前为 WebDAV ETag，必须原样用于 `If-Match`，不能在读取数据后
/// 再单独 PROPFIND，否则两次请求之间的远端更新仍可能被覆盖。
class CloudSyncDocument {
  const CloudSyncDocument({required this.data, required this.revision});

  final Map<String, dynamic> data;
  final String? revision;
}

class CloudSyncConflict implements Exception {
  const CloudSyncConflict(this.message);

  final String message;

  @override
  String toString() => 'CloudSyncConflict: $message';
}

/// 云同步后端抽象。当前默认实现为 WebDAV，未来可加 Supabase / Firebase 等。
abstract class CloudSyncBackend {
  /// 后端可读时返回 true。失败 = 凭证错或网络不通。
  Future<bool> healthCheck();

  /// 读取 manifest 与其实体版本。404 视为首次同步，返回 null。
  Future<CloudSyncDocument?> readManifestDocument();

  /// 仅当远端仍与 [expected] 相同才写入。冲突返回 false，不覆盖。
  Future<bool> writeManifestIfUnchanged(
    Map<String, dynamic> manifest, {
    required CloudSyncDocument? expected,
  });

  /// 读取模块与其实体版本。404 返回 null。
  Future<CloudSyncDocument?> readModuleDocument(String key);

  /// 仅当远端模块仍与 [expected] 相同才写入。冲突返回 false，不覆盖。
  Future<bool> writeModuleIfUnchanged(
    String key,
    Map<String, dynamic> data, {
    required CloudSyncDocument? expected,
  });

  /// 删除模块文件（用于完整 reset 同步）
  Future<void> deleteModule(String key);

  Future<Map<String, dynamic>> readManifest() async =>
      (await readManifestDocument())?.data ?? <String, dynamic>{};

  Future<Map<String, dynamic>?> readModule(String key) async =>
      (await readModuleDocument(key))?.data;

  Future<void> writeManifest(Map<String, dynamic> manifest) async {
    final expected = await readManifestDocument();
    if (!await writeManifestIfUnchanged(manifest, expected: expected)) {
      throw const CloudSyncConflict('manifest changed before it was written');
    }
  }

  Future<void> writeModule(String key, Map<String, dynamic> data) async {
    final expected = await readModuleDocument(key);
    if (!await writeModuleIfUnchanged(key, data, expected: expected)) {
      throw CloudSyncConflict('$key changed before it was written');
    }
  }
}

/// WebDAV 实现。文件结构：
/// ```
/// /<rootPath>/manifest.json
/// /<rootPath>/<module-key>.json
/// ```
class WebDavCloudSyncBackend extends CloudSyncBackend {
  WebDavCloudSyncBackend({
    required this.endpoint,
    required this.username,
    required this.password,
    this.rootPath = '/my-nas-sync',
  });

  final String endpoint;
  final String username;
  final String password;
  final String rootPath;

  webdav.Client? _client;

  webdav.Client _ensureClient() {
    final c = _client ??= webdav.newClient(
      endpoint,
      user: username,
      password: password,
    );
    return c;
  }

  String _path(String name) {
    final base = rootPath.endsWith('/') ? rootPath : '$rootPath/';
    return '$base$name';
  }

  @override
  Future<bool> healthCheck() async {
    try {
      final c = _ensureClient();
      await c.ping();
      await _ensureRootExists();
      return true;
    } on Object catch (e, st) {
      AppError.handle(e, st, 'webDavCloudSync.healthCheck', {
        'endpoint': endpoint,
      });
      return false;
    }
  }

  @override
  Future<CloudSyncDocument?> readManifestDocument() =>
      _readJsonDocument('manifest.json');

  @override
  Future<bool> writeManifestIfUnchanged(
    Map<String, dynamic> manifest, {
    required CloudSyncDocument? expected,
  }) => _writeJsonIfUnchanged('manifest.json', manifest, expected: expected);

  @override
  Future<CloudSyncDocument?> readModuleDocument(String key) =>
      _readJsonDocument('$key.json');

  @override
  Future<bool> writeModuleIfUnchanged(
    String key,
    Map<String, dynamic> data, {
    required CloudSyncDocument? expected,
  }) => _writeJsonIfUnchanged('$key.json', data, expected: expected);

  @override
  Future<void> deleteModule(String key) async {
    try {
      final c = _ensureClient();
      await c.remove(_path('$key.json'));
    } on DioException catch (e, st) {
      if (_isMissing(e)) {
        AppError.ignore(e, st, '云同步模块已不存在，删除视为成功');
        return;
      }
      AppError.handle(e, st, 'webDavCloudSync.deleteModule', {'key': key});
      rethrow;
    } on Object catch (e, st) {
      AppError.handle(e, st, 'webDavCloudSync.deleteModule', {'key': key});
      rethrow;
    }
  }

  Future<CloudSyncDocument?> _readJsonDocument(String name) async {
    try {
      final c = _ensureClient();
      final response = await c.c.req<List<int>>(
        c,
        'GET',
        _path(name),
        optionsHandler: (options) => options.responseType = ResponseType.bytes,
      );
      final status = response.statusCode ?? 0;
      if (status == 404 || status == 410) return null;
      if (status != 200) throw _responseError(response);
      final bytes = response.data;
      if (bytes == null) {
        throw const FormatException('云同步 JSON 响应为空');
      }
      final str = utf8.decode(bytes);
      final decoded = jsonDecode(str);
      if (decoded is Map) {
        return CloudSyncDocument(
          data: Map<String, dynamic>.from(decoded),
          revision: response.headers.value('etag'),
        );
      }
      throw const FormatException('云同步 JSON 顶层必须是对象');
    } on DioException catch (e, st) {
      if (_isMissing(e)) {
        AppError.ignore(e, st, '云同步远端文件不存在，按首次同步处理');
        return null;
      }
      AppError.handle(e, st, 'webDavCloudSync.readJson', {'name': name});
      rethrow;
    } on Object catch (e, st) {
      AppError.handle(e, st, 'webDavCloudSync.readJson', {'name': name});
      rethrow;
    }
  }

  Future<bool> _writeJsonIfUnchanged(
    String name,
    Map<String, dynamic> data, {
    required CloudSyncDocument? expected,
  }) async {
    final c = _ensureClient();
    final str = const JsonEncoder.withIndent('  ').convert(data);
    final bytes = Uint8List.fromList(utf8.encode(str));
    await _ensureRootExists();

    final revision = expected?.revision;
    if (expected != null && (revision == null || revision.isEmpty)) {
      throw StateError('WebDAV 服务器未提供 ETag，无法安全覆盖 $name');
    }

    final response = await c.c.req<void>(
      c,
      'PUT',
      _path(name),
      // Dio 直接持有字节数组，Digest 认证重试时仍可重新发送请求体；一次性
      // Stream 在 401 challenge 后已被消费，会导致第二次 PUT 写入空内容。
      data: bytes,
      optionsHandler: (options) {
        options.headers?['content-type'] = 'application/json; charset=utf-8';
        options.headers?['content-length'] = bytes.length;
        if (expected == null) {
          options.headers?['if-none-match'] = '*';
        } else {
          options.headers?['if-match'] = revision;
        }
      },
    );
    final status = response.statusCode ?? 0;
    if (status == 409 || status == 412) return false;
    if (status == 200 || status == 201 || status == 204) return true;
    throw _responseError(response);
  }

  DioException _responseError(Response<dynamic> response) => DioException(
    requestOptions: response.requestOptions,
    response: response,
    type: DioExceptionType.badResponse,
    message: response.statusMessage,
  );

  Future<void> _ensureRootExists() async {
    final c = _ensureClient();
    try {
      await c.mkdir(rootPath);
    } on DioException catch (e, st) {
      if (_isAlreadyExists(e)) {
        AppError.ignore(e, st, '云同步根目录已存在，无需重复创建');
        return;
      }
      AppError.handle(e, st, 'webDavCloudSync.ensureRootExists', {
        'rootPath': rootPath,
      });
      rethrow;
    } on Object catch (e, st) {
      AppError.handle(e, st, 'webDavCloudSync.ensureRootExists', {
        'rootPath': rootPath,
      });
      rethrow;
    }
  }

  bool _isMissing(DioException error) => switch (error.response?.statusCode) {
    404 || 410 => true,
    _ => false,
  };

  bool _isAlreadyExists(DioException error) =>
      switch (error.response?.statusCode) {
        301 || 405 => true,
        _ => false,
      };
}
