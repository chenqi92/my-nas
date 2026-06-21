import 'dart:io';
import 'dart:typed_data';

import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/nas_adapters/local/api/local_file_api.dart';
import 'package:path/path.dart' as p;

/// 本地文件系统实现
class LocalFileSystem implements NasFileSystem {
  LocalFileSystem({required LocalFileApi api}) : _api = api;

  final LocalFileApi _api;

  @override
  Future<List<FileItem>> listDirectory(String path) async {
    // 根目录返回系统根目录列表
    if (path == '/' || path.isEmpty) {
      final roots = await _api.getRootDirectories();
      return roots
          .map(
            (r) => FileItem(
              name: r.name,
              path: r.path,
              isDirectory: true,
              size: 0,
            ),
          )
          .toList();
    }

    final files = await _api.listDirectory(path);
    return files
        .map(
          (f) => FileItem(
            name: f.name,
            path: f.path,
            isDirectory: f.isDirectory,
            size: f.size,
            modifiedTime: f.modifiedTime,
            extension: f.isDirectory ? null : p.extension(f.name),
            isHidden: f.isHidden,
            isReadOnly: f.isReadOnly,
          ),
        )
        .toList();
  }

  @override
  Future<FileItem> getFileInfo(String path) async {
    final file = await _api.getFileInfo(path);
    return FileItem(
      name: file.name,
      path: file.path,
      isDirectory: file.isDirectory,
      size: file.size,
      modifiedTime: file.modifiedTime,
      extension: file.isDirectory ? null : p.extension(file.name),
      isHidden: file.isHidden,
      isReadOnly: file.isReadOnly,
    );
  }

  @override
  Future<Stream<List<int>>> getFileStream(String path, {FileRange? range}) async {
    final file = File(path);

    if (range != null) {
      final length = await file.length();
      final end = range.end ?? length;
      return file.openRead(range.start, end);
    }

    return file.openRead();
  }

  @override
  Future<Stream<List<int>>> getUrlStream(String url) =>
      throw UnimplementedError(appL10n.localFileSystemUrlStreamUnsupported);

  @override
  Future<String> getFileUrl(String path, {Duration? expiry}) async =>
      // 本地文件直接返回 file:// URI
      _api.getFileUri(path);

  @override
  Future<void> createDirectory(String path) async {
    await _api.createDirectory(path);
  }

  @override
  Future<void> delete(String path) async {
    await _api.delete(path);
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {
    await _api.rename(oldPath, newPath);
  }

  @override
  Future<void> copy(String sourcePath, String destPath) async {
    // destPath 是目标目录，需要加上源文件名
    final fileName = p.basename(sourcePath);
    final fullDestPath = p.join(destPath, fileName);
    await _api.copyFile(sourcePath, fullDestPath);
  }

  @override
  Future<void> move(String sourcePath, String destPath) async {
    // destPath 是目标目录，需要加上源文件名
    final fileName = p.basename(sourcePath);
    final fullDestPath = p.join(destPath, fileName);
    await _api.moveFile(sourcePath, fullDestPath);
  }

  @override
  Future<void> upload(
    String localPath,
    String remotePath, {
    String? fileName,
    void Function(int sent, int total)? onProgress,
  }) async {
    // 本地存储的"上传"实际上就是复制
    final name = fileName ?? p.basename(localPath);
    final destPath = p.join(remotePath, name);
    await _api.copyFile(localPath, destPath);
  }

  @override
  Future<void> writeFile(String remotePath, List<int> data) async {
    final file = File(remotePath);
    await file.writeAsBytes(data);
  }

  @override
  Future<List<FileItem>> search(String query, {String? path}) async {
    final basePath = path ?? '/';
    final files = await _api.searchFiles(
      basePath: basePath,
      pattern: query,
    );

    return files
        .map(
          (f) => FileItem(
            name: f.name,
            path: f.path,
            isDirectory: f.isDirectory,
            size: f.size,
            modifiedTime: f.modifiedTime,
            extension: f.isDirectory ? null : p.extension(f.name),
            isHidden: f.isHidden,
          ),
        )
        .toList();
  }

  @override
  Future<String?> getThumbnailUrl(String path, {ThumbnailSize? size}) async => _api.getFileUri(path);

  @override
  Future<Uint8List?> getThumbnailData(String path, {ThumbnailSize? size}) async => null;
}
