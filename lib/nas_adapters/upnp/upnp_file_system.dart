import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/nas_adapters/upnp/upnp_content_directory_client.dart';

/// UPnP / DLNA MediaServer 文件系统（只读）
///
/// UPnP MediaServer 没有"路径"概念，其内容通过树形 ObjectID 组织：
/// - 根容器 ObjectID = "0"
/// - 子项 ID 由服务器生成（如 "0$1$videos"）
///
/// 本实现把 ObjectID 当作 path：
/// - listDirectory(path) → Browse(ObjectID=path)
/// - 根目录 path = "" 或 "/" → ObjectID "0"
///
/// 不支持的操作（多数 MediaServer 是只读）：
/// upload / writeFile / delete / rename / mkdir / copy / move
class UpnpFileSystem implements NasFileSystem {
  UpnpFileSystem({
    required UpnpContentDirectoryClient client,
    Dio? dio,
  })  : _client = client,
        _streamDio = dio ?? Dio();

  final UpnpContentDirectoryClient _client;

  /// 用于 getFileStream / getUrlStream 的独立 dio（避免和 SOAP 调用共享 baseUrl）
  final Dio _streamDio;

  /// 缓存最近一次 list 的 item，用于 path → contentUrl 映射
  /// key: ObjectID（== path）
  final Map<String, UpnpContentItem> _itemCache = {};

  /// 把 [NasFileSystem] 风格的 path 解析为 ObjectID
  String _toObjectId(String path) {
    if (path.isEmpty || path == '/') return '0';
    // 把开头的 "/" 去掉——UPnP 的 ObjectID 不带它
    return path.startsWith('/') ? path.substring(1) : path;
  }

  /// 把 ObjectID 包装成可作 path 的字符串（前缀 "/"）
  String _toPath(String objectId) =>
      objectId.startsWith('/') ? objectId : '/$objectId';

  @override
  Future<List<FileItem>> listDirectory(String path) async {
    try {
      final id = _toObjectId(path);
      final entries = await _client.browse(id);
      _itemCache.clear();
      return entries.map((e) {
        _itemCache[e.id] = e;
        return FileItem(
          name: e.title,
          path: _toPath(e.id),
          isDirectory: e.isContainer,
          size: e.size ?? 0,
          modifiedTime: e.modifiedTime,
          // UPnP item 没有"扩展名"概念；从 protocolInfo / contentUrl 推断
          extension: e.isContainer ? null : _inferExtension(e),
        );
      }).toList();
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'UpnpFileSystem.listDirectory');
      rethrow;
    }
  }

  String? _inferExtension(UpnpContentItem item) {
    // 1. 优先从 contentUrl 文件名取
    final url = item.contentUrl;
    if (url != null) {
      final uri = Uri.tryParse(url);
      if (uri != null && uri.path.isNotEmpty) {
        final last = uri.pathSegments.lastOrNull;
        if (last != null && last.contains('.')) {
          return '.${last.split('.').last}';
        }
      }
    }
    // 2. 从 protocolInfo 里的 mime 推断（http-get:*:video/mp4:* 等）
    final pi = item.protocolInfo;
    if (pi != null) {
      final parts = pi.split(':');
      if (parts.length >= 3) {
        final mime = parts[2]; // 如 video/mp4
        final slash = mime.lastIndexOf('/');
        if (slash >= 0 && slash < mime.length - 1) {
          return '.${mime.substring(slash + 1)}';
        }
      }
    }
    return null;
  }

  @override
  Future<FileItem> getFileInfo(String path) async {
    try {
      final id = _toObjectId(path);
      // 用 BrowseMetadata 拿对象自身
      final entries = await _client.browse(id, browseFlag: 'BrowseMetadata');
      if (entries.isEmpty) {
        throw Exception('对象不存在: $path');
      }
      final e = entries.first;
      _itemCache[e.id] = e;
      return FileItem(
        name: e.title,
        path: _toPath(e.id),
        isDirectory: e.isContainer,
        size: e.size ?? 0,
        modifiedTime: e.modifiedTime,
        extension: e.isContainer ? null : _inferExtension(e),
      );
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'UpnpFileSystem.getFileInfo');
      rethrow;
    }
  }

  @override
  Future<Stream<List<int>>> getFileStream(
    String path, {
    FileRange? range,
  }) async {
    final url = await getFileUrl(path);
    return _streamRequest(url, range: range);
  }

  @override
  Future<Stream<List<int>>> getUrlStream(String url) =>
      _streamRequest(url);

  Future<Stream<List<int>>> _streamRequest(
    String url, {
    FileRange? range,
  }) async {
    try {
      final headers = <String, dynamic>{};
      if (range != null) {
        final end = range.end != null ? '${range.end}' : '';
        headers['Range'] = 'bytes=${range.start}-$end';
      }
      final response = await _streamDio.get<ResponseBody>(
        url,
        options: Options(
          responseType: ResponseType.stream,
          headers: headers,
          validateStatus: (status) => status != null && status < 400,
        ),
      );
      final stream = response.data?.stream;
      if (stream == null) {
        throw Exception('无法获取数据流');
      }
      return stream;
    } on DioException catch (e, st) {
      AppError.handle(e, st, 'UpnpFileSystem._streamRequest');
      rethrow;
    }
  }

  @override
  Future<String> getFileUrl(String path, {Duration? expiry}) async {
    final id = _toObjectId(path);
    // 先尝试缓存
    var item = _itemCache[id];
    if (item == null || item.contentUrl == null) {
      // 用 BrowseMetadata 从服务器再问一次
      final entries = await _client.browse(id, browseFlag: 'BrowseMetadata');
      if (entries.isEmpty) {
        throw Exception('对象不存在: $path');
      }
      item = entries.first;
      _itemCache[id] = item;
    }
    final url = item.contentUrl;
    if (url == null || url.isEmpty) {
      throw UnsupportedError('该 UPnP 项目无可访问 URL（可能是容器或缺 res）');
    }
    return url;
  }

  // —— 写操作：UPnP MediaServer 默认只读，全部抛 UnimplementedError ——

  @override
  Future<void> createDirectory(String path) =>
      throw UnimplementedError('UPnP MediaServer 不支持创建目录');

  @override
  Future<void> delete(String path) =>
      throw UnimplementedError('UPnP MediaServer 不支持删除');

  @override
  Future<void> rename(String oldPath, String newPath) =>
      throw UnimplementedError('UPnP MediaServer 不支持重命名');

  @override
  Future<void> copy(String sourcePath, String destPath) =>
      throw UnimplementedError('UPnP MediaServer 不支持复制');

  @override
  Future<void> move(String sourcePath, String destPath) =>
      throw UnimplementedError('UPnP MediaServer 不支持移动');

  @override
  Future<void> upload(
    String localPath,
    String remotePath, {
    String? fileName,
    void Function(int sent, int total)? onProgress,
  }) =>
      throw UnimplementedError('UPnP MediaServer 不支持上传');

  @override
  Future<void> writeFile(String remotePath, List<int> data) =>
      throw UnimplementedError('UPnP MediaServer 不支持写入');

  @override
  Future<List<FileItem>> search(String query, {String? path}) async => [];

  @override
  Future<String?> getThumbnailUrl(String path, {ThumbnailSize? size}) async =>
      null;

  @override
  Future<Uint8List?> getThumbnailData(String path, {ThumbnailSize? size}) async =>
      null;

  Future<void> dispose() async {
    _streamDio.close();
    _client.dispose();
    _itemCache.clear();
  }
}
