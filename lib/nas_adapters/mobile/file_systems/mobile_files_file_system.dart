import 'dart:io';
import 'dart:typed_data';

import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 移动端文件App文件系统
///
/// 访问手机文件 App 中的文档和书籍
/// - iOS: 访问应用沙盒 Documents 目录（可在 Files App 的"我的 iPhone"中看到）
/// - Android: 访问 Documents 和 Downloads 目录
///
/// 虚拟目录结构：
/// - /documents/         - 应用文档目录
/// - /documents/Books/   - 书籍目录（由 FileImportService 创建）
/// - /documents/Comics/  - 漫画目录（由 FileImportService 创建）
/// - /downloads/         - 下载目录
///
/// 注意：会自动排除缓存目录（包含 cache 的目录），避免扫描到应用缓存文件
class MobileFilesFileSystem implements NasFileSystem {
  MobileFilesFileSystem();

  String? _documentsPath;
  String? _downloadsPath;

  /// 需要排除的目录名（缓存目录等）
  static const _excludedDirNames = {
    'cache',
    'caches',
    'Cache',
    'Caches',
    'media_cache',
    'music_audio_cache',
    'book_cache',
    '.cache',
    'tmp',
    'temp',
    'logs',
    '.Trash',
  };

  /// 初始化文件系统
  Future<void> initialize() async {
    final docDir = await getApplicationDocumentsDirectory();
    _documentsPath = docDir.path;

    final downloadDir = await getDownloadsDirectory();
    _downloadsPath = downloadDir?.path;

    logger..i('MobileFilesFileSystem: 初始化完成')
    ..d('  Documents: $_documentsPath')
    ..d('  Downloads: $_downloadsPath');
  }

  /// 检查是否是应该排除的目录
  bool _isExcludedDir(String path) {
    final name = p.basename(path);
    // 检查目录名是否在排除列表中
    if (_excludedDirNames.contains(name)) return true;
    // 检查目录名是否包含 cache（不区分大小写）
    if (name.toLowerCase().contains('cache')) return true;
    return false;
  }

  @override
  Future<List<FileItem>> listDirectory(String path) async {
    logger.d('MobileFilesFileSystem: listDirectory - $path');

    // 根目录
    if (path == '/' || path.isEmpty) {
      return _listRoot();
    }

    // 文档目录
    if (path == '/documents' || path == '/documents/') {
      return _listPath(_documentsPath!, '/documents');
    }

    // 下载目录
    if (path == '/downloads' || path == '/downloads/') {
      if (_downloadsPath == null) return [];
      return _listPath(_downloadsPath!, '/downloads');
    }

    // 子目录
    final realPath = _toRealPath(path);
    if (realPath == null) return [];

    return _listPath(realPath, path);
  }

  /// 列出根目录
  Future<List<FileItem>> _listRoot() async {
    final items = <FileItem>[
      const FileItem(
        name: 'documents',
        path: '/documents',
        isDirectory: true,
        size: 0,
      ),
    ];

    if (_downloadsPath != null) {
      items.add(
        const FileItem(
          name: 'downloads',
          path: '/downloads',
          isDirectory: true,
          size: 0,
        ),
      );
    }

    return items;
  }

  /// 列出真实目录内容
  Future<List<FileItem>> _listPath(String realPath, String virtualPath) async {
    final dir = Directory(realPath);
    if (!await dir.exists()) return [];

    final items = <FileItem>[];

    await for (final entity in dir.list()) {
      try {
        final name = p.basename(entity.path);
        final isHidden = name.startsWith('.');

        // 跳过隐藏文件和缓存目录
        if (isHidden) continue;
        if (entity is Directory && _isExcludedDir(entity.path)) {
          logger.d('MobileFilesFileSystem: 跳过缓存目录 ${entity.path}');
          continue;
        }

        final stat = await entity.stat();

        items.add(
          FileItem(
            name: name,
            path: '$virtualPath/$name',
            isDirectory: entity is Directory,
            size: stat.size,
            modifiedTime: stat.modified,
            createdTime: stat.accessed,
            extension: entity is File ? p.extension(entity.path) : null,
            isHidden: isHidden,
          ),
        );
      } on Exception catch (e) {
        logger.w('MobileFilesFileSystem: 无法获取文件信息 ${entity.path}', e);
      }
    }

    // 排序：文件夹在前，然后按名称排序
    items.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return items;
  }

  /// 将虚拟路径转换为真实路径
  String? _toRealPath(String virtualPath) {
    if (virtualPath.startsWith('/documents')) {
      return virtualPath.replaceFirst('/documents', _documentsPath!);
    }
    if (virtualPath.startsWith('/downloads') && _downloadsPath != null) {
      return virtualPath.replaceFirst('/downloads', _downloadsPath!);
    }
    return null;
  }

  /// 将真实路径转换为虚拟路径
  String? _toVirtualPath(String realPath) {
    if (realPath.startsWith(_documentsPath!)) {
      return realPath.replaceFirst(_documentsPath!, '/documents');
    }
    if (_downloadsPath != null && realPath.startsWith(_downloadsPath!)) {
      return realPath.replaceFirst(_downloadsPath!, '/downloads');
    }
    return null;
  }

  @override
  Future<FileItem> getFileInfo(String path) async {
    final realPath = _toRealPath(path);
    if (realPath == null) {
      throw Exception(appL10n.mobileFilesErrorInvalidPath(path));
    }

    final type = FileSystemEntity.typeSync(realPath);
    if (type == FileSystemEntityType.notFound) {
      throw Exception(appL10n.mobileFilesErrorFileNotFound(path));
    }

    final isDir = type == FileSystemEntityType.directory;
    final FileStat stat;

    if (isDir) {
      stat = await Directory(realPath).stat();
    } else {
      stat = await File(realPath).stat();
    }

    final name = p.basename(realPath);

    return FileItem(
      name: name,
      path: path,
      isDirectory: isDir,
      size: stat.size,
      modifiedTime: stat.modified,
      createdTime: stat.accessed,
      extension: isDir ? null : p.extension(realPath),
      isHidden: name.startsWith('.'),
    );
  }

  @override
  Future<Stream<List<int>>> getFileStream(
    String path, {
    FileRange? range,
  }) async {
    final realPath = _toRealPath(path);
    if (realPath == null) {
      throw Exception(appL10n.mobileFilesErrorInvalidPath(path));
    }

    final file = File(realPath);
    if (!await file.exists()) {
      throw Exception(appL10n.mobileFilesErrorFileNotFound(path));
    }

    if (range != null) {
      final length = await file.length();
      // FileRange.end 为排他边界（同 openRead 的 end），null 表示读到文件结尾
      final end = range.end ?? length;
      return file.openRead(range.start, end);
    }

    return file.openRead();
  }

  @override
  Future<String> getFileUrl(String path, {Duration? expiry}) async {
    final realPath = _toRealPath(path);
    if (realPath == null) {
      throw Exception(appL10n.mobileFilesErrorInvalidPath(path));
    }

    return File(realPath).uri.toString();
  }

  @override
  Future<String?> getThumbnailUrl(String path, {ThumbnailSize? size}) async =>
      // 本地文件不支持缩略图 URL
      null;

  @override
  Future<Uint8List?> getThumbnailData(String path, {ThumbnailSize? size}) async => null;

  @override
  Future<Stream<List<int>>> getUrlStream(String url) {
    throw UnimplementedError(appL10n.mobileFilesErrorUrlStreamNotSupported);
  }

  @override
  Future<void> createDirectory(String path) async {
    final realPath = _toRealPath(path);
    if (realPath == null) {
      throw Exception(appL10n.mobileFilesErrorInvalidPath(path));
    }

    final dir = Directory(realPath);
    await dir.create(recursive: true);
  }

  @override
  Future<void> delete(String path) async {
    final realPath = _toRealPath(path);
    if (realPath == null) {
      throw Exception(appL10n.mobileFilesErrorInvalidPath(path));
    }

    final type = await FileSystemEntity.type(realPath);
    if (type == FileSystemEntityType.directory) {
      await Directory(realPath).delete(recursive: true);
    } else if (type == FileSystemEntityType.file) {
      await File(realPath).delete();
    }
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {
    final oldRealPath = _toRealPath(oldPath);
    final newRealPath = _toRealPath(newPath);

    if (oldRealPath == null || newRealPath == null) {
      throw Exception(appL10n.mobileFilesErrorInvalidPathNoArg);
    }

    final type = await FileSystemEntity.type(oldRealPath);
    if (type == FileSystemEntityType.directory) {
      await Directory(oldRealPath).rename(newRealPath);
    } else if (type == FileSystemEntityType.file) {
      await File(oldRealPath).rename(newRealPath);
    }
  }

  @override
  Future<void> copy(String sourcePath, String destPath) async {
    final sourceRealPath = _toRealPath(sourcePath);
    final destRealPath = _toRealPath(destPath);

    if (sourceRealPath == null || destRealPath == null) {
      throw Exception(appL10n.mobileFilesErrorInvalidPathNoArg);
    }

    final type = await FileSystemEntity.type(sourceRealPath);
    if (type == FileSystemEntityType.file) {
      await File(sourceRealPath).copy(destRealPath);
    } else if (type == FileSystemEntityType.directory) {
      await _copyDirectory(Directory(sourceRealPath), Directory(destRealPath));
    }
  }

  Future<void> _copyDirectory(Directory source, Directory dest) async {
    await dest.create(recursive: true);

    await for (final entity in source.list()) {
      final newPath = p.join(dest.path, p.basename(entity.path));

      if (entity is File) {
        await entity.copy(newPath);
      } else if (entity is Directory) {
        await _copyDirectory(entity, Directory(newPath));
      }
    }
  }

  @override
  Future<void> move(String sourcePath, String destPath) async {
    final sourceRealPath = _toRealPath(sourcePath);
    final destRealPath = _toRealPath(destPath);

    if (sourceRealPath == null || destRealPath == null) {
      throw Exception(appL10n.mobileFilesErrorInvalidPathNoArg);
    }

    final type = await FileSystemEntity.type(sourceRealPath);
    if (type == FileSystemEntityType.file) {
      await File(sourceRealPath).rename(destRealPath);
    } else if (type == FileSystemEntityType.directory) {
      await Directory(sourceRealPath).rename(destRealPath);
    }
  }

  @override
  Future<void> upload(
    String localPath,
    String remotePath, {
    String? fileName,
    void Function(int sent, int total)? onProgress,
  }) async {
    final destRealPath = _toRealPath(remotePath);
    if (destRealPath == null) {
      throw Exception(appL10n.mobileFilesErrorInvalidPath(remotePath));
    }

    final sourceFile = File(localPath);
    final destFileName = fileName ?? p.basename(localPath);
    final destFile = File(p.join(destRealPath, destFileName));

    await sourceFile.copy(destFile.path);
  }

  @override
  Future<void> writeFile(String remotePath, List<int> data) async {
    final realPath = _toRealPath(remotePath);
    if (realPath == null) {
      throw Exception(appL10n.mobileFilesErrorInvalidPath(remotePath));
    }

    final file = File(realPath);
    await file.writeAsBytes(data);
  }

  @override
  Future<List<FileItem>> search(String query, {String? path}) async {
    final searchPath = path != null ? _toRealPath(path) : _documentsPath;
    if (searchPath == null) return [];

    final results = <FileItem>[];
    final queryLower = query.toLowerCase();
    final dir = Directory(searchPath);

    try {
      await for (final entity in dir.list(recursive: true)) {
        final name = p.basename(entity.path);
        final nameLower = name.toLowerCase();

        // 跳过隐藏文件
        if (name.startsWith('.')) continue;

        // 跳过缓存目录中的文件
        if (_isInExcludedDir(entity.path)) continue;

        if (nameLower.contains(queryLower)) {
          final stat = await entity.stat();
          final virtualPath = _toVirtualPath(entity.path);
          if (virtualPath != null) {
            results.add(
              FileItem(
                name: name,
                path: virtualPath,
                isDirectory: entity is Directory,
                size: stat.size,
                modifiedTime: stat.modified,
                extension: entity is File ? p.extension(entity.path) : null,
                isHidden: false,
              ),
            );
          }
        }
      }
    } on Exception catch (e) {
      logger.e('MobileFilesFileSystem: 搜索失败', e);
    }

    return results;
  }

  /// 检查路径是否在排除目录中
  bool _isInExcludedDir(String path) {
    final parts = path.split(Platform.pathSeparator);
    for (final part in parts) {
      if (_excludedDirNames.contains(part) ||
          part.toLowerCase().contains('cache')) {
        return true;
      }
    }
    return false;
  }
}
