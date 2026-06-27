import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:path/path.dart' as p;
import 'package:webdav_client/webdav_client.dart' as webdav;

/// WebDAV 文件系统实现
class WebDavFileSystem implements NasFileSystem {
  WebDavFileSystem({
    required webdav.Client client,
    required String baseUrl,
    required String username,
    required String password,
  }) : _client = client,
       _baseUrl = baseUrl,
       _authHeader =
           'Basic ${base64Encode(utf8.encode('$username:$password'))}' {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
        headers: {'Authorization': _authHeader},
      ),
    );
  }

  final webdav.Client _client;
  // ignore: unused_field
  final String _baseUrl; // 保留以备将来使用
  final String _authHeader;
  late final Dio _dio;

  @override
  bool get supportsWriteOperations => true;

  @override
  bool get supportsServerSideCopy => true;

  @override
  bool get supportsDirectFileUrl => true;

  /// 关闭 Dio 实例
  void dispose() {
    _dio.close();
  }

  /// 带重试的操作执行
  Future<T> _withRetry<T>(
    Future<T> Function() operation, {
    int maxRetries = 2,
    String? action,
  }) async {
    Object? lastError;
    StackTrace? lastStackTrace;

    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        return await operation();
      } catch (e, st) {
        lastError = e;
        lastStackTrace = st;

        // 判断是否可重试的错误
        if (!_isRetryableError(e)) {
          rethrow;
        }

        if (attempt < maxRetries) {
          logger.w(
            'WebDavFileSystem: ${action ?? "操作"}失败，重试 ($attempt/$maxRetries)',
          );
          await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
        }
      }
    }

    // 上报错误
    if (action != null && lastError != null) {
      AppError.handle(
        lastError,
        lastStackTrace ?? StackTrace.current,
        'WebDavFileSystem.$action',
      );
    }
    throw lastError!;
  }

  /// 判断是否可重试的错误
  bool _isRetryableError(Object e) {
    if (e is DioException) {
      return e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError;
    }
    final msg = e.toString().toLowerCase();
    return msg.contains('connection') ||
        msg.contains('timeout') ||
        msg.contains('socket');
  }

  @override
  Future<List<FileItem>> listDirectory(String path) async {
    final normalizedPath = path.isEmpty ? '/' : path;

    return _withRetry(() async {
      final files = await _client.readDir(normalizedPath);
      return files.map((f) {
        final fileName = p.basename(f.path ?? '');
        return FileItem(
          name: fileName.isEmpty ? f.name ?? '' : fileName,
          path: f.path ?? '',
          isDirectory: f.isDir ?? false,
          size: f.size ?? 0,
          modifiedTime: f.mTime,
          createdTime: f.cTime,
          extension: f.isDir ?? false ? null : p.extension(f.name ?? ''),
        );
      }).toList();
    }, action: 'listDirectory');
  }

  @override
  Future<FileItem> getFileInfo(String path) async {
    // 根目录没有"父目录"可遍历，直接返回合成的目录条目，避免 firstWhere 抛 StateError。
    if (path.isEmpty || path == '/') {
      return FileItem(name: '', path: '/', isDirectory: true, size: 0);
    }
    return _withRetry(() async {
      final files = await _client.readDir(p.dirname(path));
      final fileName = p.basename(path);
      // 忽略 name 头尾斜杠差异
      String norm(String? s) => (s ?? '').replaceAll('/', '').trim();
      final target = norm(fileName);
      webdav.File? match;
      for (final f in files) {
        if (norm(f.name) == target) {
          match = f;
          break;
        }
      }
      if (match == null) {
        // 抛 Exception 而非 StateError，让上层 try-on Exception 能捕获
        throw _WebDavFileNotFound(path);
      }
      return FileItem(
        name: match.name ?? fileName,
        path: match.path ?? path,
        isDirectory: match.isDir ?? false,
        size: match.size ?? 0,
        modifiedTime: match.mTime,
        createdTime: match.cTime,
        extension: match.isDir ?? false ? null : p.extension(match.name ?? ''),
      );
    }, action: 'getFileInfo');
  }

  @override
  Future<Stream<List<int>>> getFileStream(
    String path, {
    FileRange? range,
  }) async {
    logger.d('WebDavFileSystem: getFileStream path=$path, range=$range');

    return _withRetry(() async {
      // 使用 Dio 进行流式读取，支持 Range 请求
      final headers = <String, dynamic>{};
      if (range != null) {
        final rangeStart = range.start;
        // FileRange.end 为排他边界，HTTP Range 为闭区间，需 -1
        final rangeEnd = range.end != null ? '${range.end! - 1}' : '';
        headers['Range'] = 'bytes=$rangeStart-$rangeEnd';
        logger.d('WebDavFileSystem: 使用 Range 请求: bytes=$rangeStart-$rangeEnd');
      }

      try {
        final response = await _dio.get<ResponseBody>(
          path,
          options: Options(
            responseType: ResponseType.stream,
            headers: headers,
            validateStatus: (status) => status != null && status < 400,
          ),
        );

        final stream = response.data?.stream;
        if (stream == null) {
          throw Exception(appL10n.webdavFileStreamNotAvailable);
        }

        return stream;
      } on DioException catch (e) {
        AppError.handle(
          e,
          StackTrace.current,
          'WebDavFileSystem.getFileStream',
          {'path': path, 'range': range?.toString()},
        );

        // 降级到原有方式：一次性读取
        logger.w('WebDavFileSystem: 降级到一次性读取模式');
        final bytes = await _client.read(path);
        if (range != null) {
          final end = range.end ?? bytes.length;
          return Stream.value(bytes.sublist(range.start, end));
        }
        return Stream.value(bytes);
      }
    }, action: 'getFileStream');
  }

  @override
  Future<Stream<List<int>>> getUrlStream(String url) async {
    // WebDAV 使用 Dio 获取 URL 数据流
    final response = await _dio.get<ResponseBody>(
      url,
      options: Options(
        responseType: ResponseType.stream,
        validateStatus: (status) => status != null && status < 400,
      ),
    );

    final stream = response.data?.stream;
    if (stream == null) {
      throw Exception(appL10n.webdavUrlStreamNotAvailable);
    }

    return stream;
  }

  @override
  Future<String> getFileUrl(String path, {Duration? expiry}) async =>
      // WebDAV 返回特殊的 webdav:// URI 格式
      // 应用层需要使用 getFileStream 进行实际访问
      'webdav://local$path';

  @override
  Future<void> createDirectory(String path) async {
    await _client.mkdir(path);
  }

  @override
  Future<void> delete(String path) async {
    await _client.remove(path);
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {
    await _client.rename(oldPath, newPath, true);
  }

  @override
  Future<void> copy(String sourcePath, String destPath) async {
    await _client.copy(sourcePath, destPath, true);
  }

  @override
  Future<void> move(String sourcePath, String destPath) async {
    await _client.rename(sourcePath, destPath, true);
  }

  @override
  Future<void> upload(
    String localPath,
    String remotePath, {
    String? fileName,
    void Function(int sent, int total)? onProgress,
  }) async {
    final name = fileName ?? p.basename(localPath);
    final destPath = remotePath.endsWith('/')
        ? '$remotePath$name'
        : '$remotePath/$name';

    await _client.writeFromFile(
      localPath,
      destPath,
      onProgress: (count, total) {
        onProgress?.call(count, total);
      },
    );
  }

  @override
  Future<void> writeFile(String remotePath, List<int> data) async {
    await _client.write(remotePath, Uint8List.fromList(data));
  }

  @override
  Future<List<FileItem>> search(String query, {String? path}) async => [];

  @override
  Future<String?> getThumbnailUrl(String path, {ThumbnailSize? size}) async =>
      null;

  @override
  Future<Uint8List?> getThumbnailData(
    String path, {
    ThumbnailSize? size,
  }) async => null;
}

class _WebDavFileNotFound implements Exception {
  const _WebDavFileNotFound(this.path);
  final String path;
  @override
  String toString() => 'WebDAV file not found: $path';
}
