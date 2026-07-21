import 'dart:typed_data';

import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/nas_adapters/fnos/api/fnos_api.dart';
import 'package:path/path.dart' as p;

/// 飞牛 NAS 文件系统实现
class FnOSFileSystem implements NasFileSystem {
  FnOSFileSystem({required this.api});

  final FnOSApi api;

  /// 缓存的共享文件夹列表
  List<FnOSFileInfo>? _cachedShares;

  @override
  bool get supportsWriteOperations => true;

  @override
  bool get supportsServerSideCopy => true;

  @override
  bool get supportsDirectFileUrl => true;

  @override
  Future<List<FileItem>> listDirectory(String path) async {
    logger.d('FnOSFileSystem: listDirectory => $path');

    // 根目录显示共享文件夹列表
    if (path == '/' || path.isEmpty) {
      return listShares();
    }

    final files = await api.listDirectory(path);

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

  /// 列出共享文件夹
  Future<List<FileItem>> listShares() async {
    logger.d('FnOSFileSystem: 获取共享文件夹列表');

    if (_cachedShares != null && _cachedShares!.isNotEmpty) {
      logger.d('FnOSFileSystem: 使用缓存的共享列表');
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

    final shares = await api.listShares();
    _cachedShares = shares;

    logger.i('FnOSFileSystem: 获取到 ${shares.length} 个共享文件夹');

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
    final parentPath = path.substring(0, path.lastIndexOf('/'));
    final fileName = path.substring(path.lastIndexOf('/') + 1);

    final files = await listDirectory(parentPath.isEmpty ? '/' : parentPath);
    final file = files.firstWhere(
      (f) => f.name == fileName,
      orElse: () => throw Exception(appL10n.fnosFileNotFound(path)),
    );
    return file;
  }

  @override
  Future<Stream<List<int>>> getFileStream(
    String path, {
    FileRange? range,
  }) async => api.getUrlStream(await api.getFileUrl(path), range: range);

  @override
  Future<Stream<List<int>>> getUrlStream(String url) => api.getUrlStream(url);

  @override
  Future<String> getFileUrl(String path, {Duration? expiry}) async =>
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
      AppError.ignore(e, st, '飞牛 NAS 服务端复制失败，回退到客户端流式复制');
    }

    // 客户端 fallback
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
      AppError.ignore(e, st, '飞牛 NAS 服务端搜索失败，回退到客户端递归遍历');
    }

    return _clientSideSearch(query, root: path ?? '/');
  }

  /// 客户端递归搜索（深度优先，限深度和数量）
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
