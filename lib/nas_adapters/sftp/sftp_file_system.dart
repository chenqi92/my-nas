import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:path/path.dart' as p;

/// SFTP 文件系统实现
///
/// 基于 dartssh2 的 SftpClient。SFTP 是 SSH 的子协议，每个文件操作都是
/// 独立的子操作，天然支持并发和流式 I/O，比 FTP 控制连接更适合一般用途。
class SftpFileSystem implements NasFileSystem {
  SftpFileSystem({required SftpClient sftp}) : _sftp = sftp;

  final SftpClient _sftp;

  String _normalize(String path) =>
      path.isEmpty ? '/' : (path.startsWith('/') ? path : '/$path');

  @override
  Future<List<FileItem>> listDirectory(String path) async {
    try {
      final normalized = _normalize(path);
      final entries = await _sftp.listdir(normalized);
      return entries
          .where((e) => e.filename != '.' && e.filename != '..')
          .map((e) {
        final isDir = e.attr.isDirectory;
        final fullPath = normalized.endsWith('/')
            ? '$normalized${e.filename}'
            : '$normalized/${e.filename}';
        return FileItem(
          name: e.filename,
          path: fullPath,
          isDirectory: isDir,
          size: e.attr.size ?? 0,
          modifiedTime: e.attr.modifyTime != null
              ? DateTime.fromMillisecondsSinceEpoch(e.attr.modifyTime! * 1000)
              : null,
          extension: isDir ? null : p.extension(e.filename),
        );
      }).toList();
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'SftpFileSystem.listDirectory');
      rethrow;
    }
  }

  @override
  Future<FileItem> getFileInfo(String path) async {
    try {
      final normalized = _normalize(path);
      final attr = await _sftp.stat(normalized);
      return FileItem(
        name: p.basename(normalized),
        path: normalized,
        isDirectory: attr.isDirectory,
        size: attr.size ?? 0,
        modifiedTime: attr.modifyTime != null
            ? DateTime.fromMillisecondsSinceEpoch(attr.modifyTime! * 1000)
            : null,
        extension: attr.isDirectory ? null : p.extension(normalized),
      );
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'SftpFileSystem.getFileInfo');
      rethrow;
    }
  }

  @override
  Future<Stream<List<int>>> getFileStream(
    String path,
    {FileRange? range,}
  ) async {
    try {
      final normalized = _normalize(path);
      final file = await _sftp.open(normalized);
      // SftpFile.read() 返回 Stream<Uint8List>
      if (range == null) {
        return file.read().cast<List<int>>();
      }
      final endPos = range.end ?? (await file.stat()).size ?? 0;
      final length = endPos - range.start;
      return file.read(offset: range.start, length: length).cast<List<int>>();
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'SftpFileSystem.getFileStream');
      rethrow;
    }
  }

  @override
  Future<Stream<List<int>>> getUrlStream(String url) =>
      throw UnimplementedError('SFTP 不支持通过 URL 获取数据流');

  /// SFTP 没有可分享的 HTTP URL；返回 sftp:// 形式作占位
  @override
  Future<String> getFileUrl(String path, {Duration? expiry}) async =>
      'sftp://local${_normalize(path)}';

  @override
  Future<void> createDirectory(String path) async {
    try {
      await _sftp.mkdir(_normalize(path));
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'SftpFileSystem.createDirectory');
      rethrow;
    }
  }

  @override
  Future<void> delete(String path) async {
    try {
      final normalized = _normalize(path);
      try {
        await _sftp.remove(normalized);
      } on Exception {
        // 文件删除失败时尝试当目录删
        await _sftp.rmdir(normalized);
      }
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'SftpFileSystem.delete');
      rethrow;
    }
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {
    try {
      await _sftp.rename(_normalize(oldPath), _normalize(newPath));
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'SftpFileSystem.rename');
      rethrow;
    }
  }

  @override
  Future<void> copy(String sourcePath, String destPath) =>
      throw UnimplementedError('SFTP 协议不支持服务端拷贝');

  @override
  Future<void> move(String sourcePath, String destPath) =>
      rename(sourcePath, destPath);

  @override
  Future<void> upload(
    String localPath,
    String remotePath, {
    String? fileName,
    void Function(int sent, int total)? onProgress,
  }) async {
    try {
      final name = fileName ?? p.basename(localPath);
      final destPath = remotePath.endsWith('/')
          ? '$remotePath$name'
          : '$remotePath/$name';
      final remoteFile = await _sftp.open(
        _normalize(destPath),
        mode: SftpFileOpenMode.create |
            SftpFileOpenMode.write |
            SftpFileOpenMode.truncate,
      );
      try {
        // 用 dart:io 流式读取本地文件
        final stream = File(localPath).openRead().map(Uint8List.fromList);
        await remoteFile.write(stream);
      } finally {
        await remoteFile.close();
      }
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'SftpFileSystem.upload');
      rethrow;
    }
  }

  @override
  Future<void> writeFile(String remotePath, List<int> data) async {
    try {
      final file = await _sftp.open(
        _normalize(remotePath),
        mode: SftpFileOpenMode.create |
            SftpFileOpenMode.write |
            SftpFileOpenMode.truncate,
      );
      try {
        await file.write(Stream.value(Uint8List.fromList(data)));
      } finally {
        await file.close();
      }
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'SftpFileSystem.writeFile');
      rethrow;
    }
  }

  /// SFTP 没有递归搜索 API；后续可实现"deep listdir"客户端搜索
  @override
  Future<List<FileItem>> search(String query, {String? path}) async => [];

  @override
  Future<String?> getThumbnailUrl(String path, {ThumbnailSize? size}) async =>
      null;

  @override
  Future<Uint8List?> getThumbnailData(String path, {ThumbnailSize? size}) async =>
      null;

  /// 释放 SFTP 子会话；上层 [SftpAdapter] 还会关闭 SSH 客户端
  Future<void> dispose() async {
    try {
      _sftp.close();
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'SftpFileSystem.dispose');
    }
    logger.d('SftpFileSystem: 已释放 SFTP 子会话');
  }
}
