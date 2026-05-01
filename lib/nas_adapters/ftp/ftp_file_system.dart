import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:ftpconnect/ftpconnect.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:synchronized/synchronized.dart';

/// FTP 文件系统实现
///
/// FTP 协议是有状态会话——一个连接一次只能处理一个命令/数据流。本实现：
/// - 用 [Lock] 串行化所有 FTP 调用，避免并发命令撞 FTP 控制连接
/// - getFileStream 走"先 downloadFile 到临时文件再 openRead"的妥协路径，
///   因为 ftpconnect 不暴露原生流式下载；调用方应注意大文件会占用本地存储
/// - search / 缩略图等不支持，直接返回空
class FtpFileSystem implements NasFileSystem {
  FtpFileSystem({required FTPConnect ftp}) : _ftp = ftp;

  final FTPConnect _ftp;

  /// 串行化所有 FTP 调用——FTP 控制连接是单线程
  final _lock = Lock();

  /// 临时下载文件计数（避免命名冲突）
  int _tempCounter = 0;

  /// 关闭可能残留的临时文件
  final List<File> _pendingTempFiles = [];

  Future<T> _withLock<T>(
    String action,
    Future<T> Function() body,
  ) =>
      _lock.synchronized(() async {
        try {
          return await body();
        } on Exception catch (e, st) {
          AppError.handle(e, st, 'FtpFileSystem.$action');
          rethrow;
        }
      });

  String _normalize(String path) =>
      path.isEmpty ? '/' : (path.startsWith('/') ? path : '/$path');

  @override
  Future<List<FileItem>> listDirectory(String path) =>
      _withLock('listDirectory', () async {
        final normalized = _normalize(path);
        await _ftp.changeDirectory(normalized);
        final entries = await _ftp.listDirectoryContent();
        return entries.map((e) {
          final isDir = e.type == FTPEntryType.dir;
          final entryName = e.name;
          final fullPath =
              normalized.endsWith('/') ? '$normalized$entryName' : '$normalized/$entryName';
          return FileItem(
            name: entryName,
            path: fullPath,
            isDirectory: isDir,
            size: e.size ?? 0,
            modifiedTime: e.modifyTime,
            extension: isDir ? null : p.extension(entryName),
          );
        }).toList();
      });

  @override
  Future<FileItem> getFileInfo(String path) async {
    final normalized = _normalize(path);
    final dir = p.posix.dirname(normalized);
    final name = p.posix.basename(normalized);
    final entries = await listDirectory(dir);
    return entries.firstWhere(
      (f) => f.name == name,
      orElse: () => throw Exception('文件不存在: $path'),
    );
  }

  @override
  Future<Stream<List<int>>> getFileStream(
    String path, {
    FileRange? range,
  }) =>
      _withLock('getFileStream', () async {
        final tempDir = await getTemporaryDirectory();
        _tempCounter++;
        final tempFile = File(p.join(
          tempDir.path,
          'ftp_stream_${DateTime.now().millisecondsSinceEpoch}_$_tempCounter',
        ));
        _pendingTempFiles.add(tempFile);

        final ok = await _ftp.downloadFile(_normalize(path), tempFile);
        if (!ok || !tempFile.existsSync()) {
          throw Exception('FTP 下载失败: $path');
        }

        Stream<List<int>> stream;
        if (range != null) {
          // 范围读取：跳过前 N 字节
          final raf = await tempFile.open();
          await raf.setPosition(range.start);
          final length = (range.end ?? await tempFile.length()) - range.start;
          final bytes = await raf.read(length);
          await raf.close();
          stream = Stream.value(bytes);
        } else {
          stream = tempFile.openRead();
        }

        // 等流被消费完后清理临时文件
        return stream.transform(StreamTransformer.fromHandlers(
          handleDone: (sink) async {
            sink.close();
            _scheduleCleanup(tempFile);
          },
          handleError: (error, st, sink) {
            sink.addError(error, st);
            _scheduleCleanup(tempFile);
          },
        ));
      });

  void _scheduleCleanup(File f) {
    Future<void>.delayed(const Duration(seconds: 5), () async {
      try {
        if (f.existsSync()) await f.delete();
      } on Exception catch (e, st) {
        AppError.ignore(e, st, 'FtpFileSystem 清理临时文件失败');
      }
      _pendingTempFiles.remove(f);
    });
  }

  @override
  Future<Stream<List<int>>> getUrlStream(String url) =>
      throw UnimplementedError('FTP 不支持通过 URL 获取数据流');

  /// FTP 没有可分享的 HTTP URL 概念；返回 ftp:// 形式作占位，
  /// 应用层应优先调用 getFileStream。
  @override
  Future<String> getFileUrl(String path, {Duration? expiry}) async =>
      'ftp://local${_normalize(path)}';

  @override
  Future<void> createDirectory(String path) =>
      _withLock('createDirectory', () async {
        await _ftp.makeDirectory(_normalize(path));
      });

  @override
  Future<void> delete(String path) => _withLock('delete', () async {
        final normalized = _normalize(path);
        // 先尝试删文件，不行再尝试删目录
        try {
          await _ftp.deleteFile(normalized);
        } on Exception {
          await _ftp.deleteEmptyDirectory(normalized);
        }
      });

  @override
  Future<void> rename(String oldPath, String newPath) =>
      _withLock('rename', () async {
        await _ftp.rename(_normalize(oldPath), _normalize(newPath));
      });

  @override
  Future<void> copy(String sourcePath, String destPath) =>
      throw UnimplementedError('FTP 协议本身不支持服务端拷贝');

  @override
  Future<void> move(String sourcePath, String destPath) =>
      rename(sourcePath, destPath);

  @override
  Future<void> upload(
    String localPath,
    String remotePath, {
    String? fileName,
    void Function(int sent, int total)? onProgress,
  }) =>
      _withLock('upload', () async {
        final name = fileName ?? p.basename(localPath);
        final dir = remotePath.endsWith('/')
            ? remotePath.substring(0, remotePath.length - 1)
            : remotePath;
        await _ftp.changeDirectory(_normalize(dir));
        final ok = await _ftp.uploadFile(File(localPath), sRemoteName: name);
        if (!ok) {
          throw Exception('FTP 上传失败: $localPath -> $remotePath/$name');
        }
      });

  @override
  Future<void> writeFile(String remotePath, List<int> data) =>
      _withLock('writeFile', () async {
        final tempDir = await getTemporaryDirectory();
        final tempFile = File(p.join(
          tempDir.path,
          'ftp_write_${DateTime.now().millisecondsSinceEpoch}',
        ));
        await tempFile.writeAsBytes(data);
        try {
          final dir = p.posix.dirname(_normalize(remotePath));
          final name = p.posix.basename(remotePath);
          await _ftp.changeDirectory(dir);
          final ok = await _ftp.uploadFile(tempFile, sRemoteName: name);
          if (!ok) {
            throw Exception('FTP 写入失败: $remotePath');
          }
        } finally {
          if (tempFile.existsSync()) {
            try {
              await tempFile.delete();
            } on Exception catch (e, st) {
              AppError.ignore(e, st, 'FtpFileSystem.writeFile 清理临时文件失败');
            }
          }
        }
      });

  /// FTP 没有递归搜索 API，留作后续可改成"deep listDirectory"实现
  @override
  Future<List<FileItem>> search(String query, {String? path}) async => [];

  @override
  Future<String?> getThumbnailUrl(String path, {ThumbnailSize? size}) async =>
      null;

  @override
  Future<Uint8List?> getThumbnailData(String path, {ThumbnailSize? size}) async =>
      null;

  /// 释放剩余的临时文件
  Future<void> dispose() async {
    for (final f in List<File>.from(_pendingTempFiles)) {
      try {
        if (f.existsSync()) await f.delete();
      } on Exception catch (e, st) {
        AppError.ignore(e, st, 'FtpFileSystem.dispose 清理临时文件失败');
      }
    }
    _pendingTempFiles.clear();
    logger.d('FtpFileSystem: 已释放临时资源');
  }
}
