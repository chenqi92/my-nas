import 'dart:typed_data';

import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/nas_adapters/ugreen/api/ugreen_api.dart';
import 'package:path/path.dart' as p;

/// 绿联 NAS 文件系统实现
///
/// UGOS 使用共享文件夹的概念，根目录 `/` 应该显示共享文件夹列表
class UGreenFileSystem implements NasFileSystem {
  UGreenFileSystem({required this.api});

  final UGreenApi api;

  /// 缓存的共享文件夹列表
  List<UGreenFileInfo>? _cachedShares;

  @override
  bool get supportsWriteOperations => true;

  @override
  bool get supportsServerSideCopy => true;

  @override
  bool get supportsDirectFileUrl => true;

  @override
  Future<List<FileItem>> listDirectory(String path) async {
    logger.d('UGreenFileSystem: listDirectory => $path');

    // 根目录显示共享文件夹列表
    if (path == '/' || path.isEmpty) {
      return listShares();
    }

    // 非根目录，使用 API 列出目录内容
    final files = await api.listDirectory(path);

    // 如果 API 返回空且路径看起来像共享文件夹，尝试用共享路径
    if (files.isEmpty && !path.contains('/') == false) {
      logger.d('UGreenFileSystem: API 返回空，检查是否为共享文件夹');
    }

    return files
        .map(
          (file) => FileItem(
            name: file.name,
            path: file.path,
            isDirectory: file.isDir,
            size: file.size ?? 0,
            modifiedTime: file.modified,
            createdTime: file.created,
            mimeType: file.mimeType,
            extension: _getExtension(file.name),
          ),
        )
        .toList();
  }

  /// 列出共享文件夹 (根目录内容)
  ///
  /// UGOS 使用共享文件夹的概念，这里会缓存共享列表以提高性能
  Future<List<FileItem>> listShares() async {
    logger.d('UGreenFileSystem: 获取共享文件夹列表');

    // 如果有缓存，直接返回
    if (_cachedShares != null && _cachedShares!.isNotEmpty) {
      logger.d('UGreenFileSystem: 使用缓存的共享列表 (${_cachedShares!.length} 项)');
      return _cachedShares!
          .map(
            (share) => FileItem(
              name: share.name,
              path: share.path,
              isDirectory: true,
              size: 0,
            ),
          )
          .toList();
    }

    // 获取共享列表
    final shares = await api.listShares();
    _cachedShares = shares;

    logger.i('UGreenFileSystem: 获取到 ${shares.length} 个共享文件夹');

    return shares
        .map(
          (share) => FileItem(
            name: share.name,
            path: share.path,
            isDirectory: true,
            size: 0,
          ),
        )
        .toList();
  }

  /// 清除共享文件夹缓存
  void clearSharesCache() {
    _cachedShares = null;
  }

  String? _getExtension(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == fileName.length - 1) return null;
    return fileName.substring(dotIndex + 1);
  }

  @override
  Future<FileItem> getFileInfo(String path) async {
    // 通过列出父目录并查找指定文件来获取文件信息
    final parentPath = path.substring(0, path.lastIndexOf('/'));
    final fileName = path.substring(path.lastIndexOf('/') + 1);

    final files = await listDirectory(parentPath.isEmpty ? '/' : parentPath);
    final file = files.firstWhere(
      (f) => f.name == fileName,
      orElse: () => throw Exception(appL10n.ugreenFileSystemFileNotFound(path)),
    );
    return file;
  }

  @override
  Future<Stream<List<int>>> getFileStream(
    String path, {
    FileRange? range,
  }) async {
    final url = await api.getFileUrl(path);
    return api.getUrlStream(url);
  }

  @override
  Future<Stream<List<int>>> getUrlStream(String url) => api.getUrlStream(url);

  @override
  Future<String> getFileUrl(String path, {Duration? expiry}) =>
      api.getFileUrl(path);

  @override
  Future<void> createDirectory(String path) async {
    await api.createDirectory(path);
  }

  @override
  Future<void> delete(String path) async {
    await api.delete(path);
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {
    await api.rename(oldPath, newPath);
  }

  @override
  Future<void> copy(String sourcePath, String destPath) async {
    try {
      await api.copy(sourcePath, destPath);
      return;
    } on Exception catch (e, st) {
      // 服务端复制可能因端点差异/权限失败，回退到客户端流式复制
      AppError.ignore(e, st, 'UGOS 服务端复制失败，回退到客户端流式复制');
    }

    final stream = await getFileStream(sourcePath);
    final chunks = <int>[];
    await for (final chunk in stream) {
      chunks.addAll(chunk);
    }
    await writeFile(destPath, chunks);
  }

  @override
  Future<void> move(String sourcePath, String destPath) async {
    await api.rename(sourcePath, destPath);
  }

  @override
  Future<void> upload(
    String localPath,
    String remotePath, {
    String? fileName,
    void Function(int sent, int total)? onProgress,
  }) async {
    final name = fileName ?? p.basename(localPath);
    await api.uploadFile(
      localPath: localPath,
      remoteDir: remotePath,
      fileName: name,
      onProgress: onProgress,
    );
  }

  @override
  Future<void> writeFile(String remotePath, List<int> data) async {
    final lastSlash = remotePath.lastIndexOf('/');
    final remoteDir = lastSlash > 0 ? remotePath.substring(0, lastSlash) : '/';
    final fileName = lastSlash >= 0
        ? remotePath.substring(lastSlash + 1)
        : remotePath;

    await api.uploadBytes(remoteDir: remoteDir, fileName: fileName, data: data);
  }

  @override
  Future<List<FileItem>> search(String query, {String? path}) async {
    if (query.trim().isEmpty) return const [];

    // 优先尝试服务端搜索
    try {
      final results = await api.search(query, path: path);
      return results
          .map(
            (file) => FileItem(
              name: file.name,
              path: file.path,
              isDirectory: file.isDir,
              size: file.size ?? 0,
              modifiedTime: file.modified,
              createdTime: file.created,
              mimeType: file.mimeType,
              extension: _getExtension(file.name),
            ),
          )
          .toList();
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'UGOS 服务端搜索失败，回退到客户端递归遍历');
    }

    // 回退：客户端 BFS，限制深度和数量避免遍历过深
    return _clientSideSearch(query, root: path ?? '/');
  }

  /// 客户端递归搜索（深度优先有限制）
  Future<List<FileItem>> _clientSideSearch(
    String query, {
    required String root,
    int maxDepth = 4,
    int maxResults = 200,
  }) async {
    final lower = query.toLowerCase();
    final results = <FileItem>[];
    final queue = <({String path, int depth})>[(path: root, depth: 0)];

    while (queue.isNotEmpty && results.length < maxResults) {
      final entry = queue.removeAt(0);
      try {
        final children = await listDirectory(entry.path);
        for (final child in children) {
          if (child.name.toLowerCase().contains(lower)) {
            results.add(child);
            if (results.length >= maxResults) break;
          }
          if (child.isDirectory && entry.depth < maxDepth) {
            queue.add((path: child.path, depth: entry.depth + 1));
          }
        }
      } on Exception catch (e, st) {
        AppError.ignore(e, st, '客户端搜索：跳过无法访问的目录 ${entry.path}');
      }
    }
    return results;
  }

  @override
  Future<String?> getThumbnailUrl(String path, {ThumbnailSize? size}) async =>
      api.getThumbnailUrl(path, size: size);

  @override
  Future<Uint8List?> getThumbnailData(
    String path, {
    ThumbnailSize? size,
  }) async => null;
}
