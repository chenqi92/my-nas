import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ftpconnect/ftpconnect.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
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
  FtpFileSystem({
    required FTPConnect ftp,
    String? host,
    int port = 21,
    String? user,
    String? pass,
    bool enableRestRange = true,
  }) : _ftp = ftp,
       _host = host,
       _port = port,
       _user = user,
       _pass = pass,
       _enableRestRange = enableRestRange;

  final FTPConnect _ftp;

  /// 原生 FTP REST 流式下载所需的连接参数（用于 range 读取，避免整文件下载）。
  /// _host 为空时 range 读取回退到「整文件下载后本地 seek」。仅支持明文 FTP。
  final String? _host;
  final int _port;
  final String? _user;
  final String? _pass;
  final bool _enableRestRange;

  /// 串行化所有 FTP 调用——FTP 控制连接是单线程
  final _lock = Lock();

  @override
  bool get supportsWriteOperations => true;

  @override
  bool get supportsServerSideCopy => false;

  @override
  bool get supportsDirectFileUrl => false;

  /// 临时下载文件计数（避免命名冲突）
  int _tempCounter = 0;

  /// 关闭可能残留的临时文件
  final List<File> _pendingTempFiles = [];

  Future<T> _withLock<T>(String action, Future<T> Function() body) =>
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
          final fullPath = normalized.endsWith('/')
              ? '$normalized$entryName'
              : '$normalized/$entryName';
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
      orElse: () => throw Exception(appL10n.ftpFileSystemFileNotFound(path)),
    );
  }

  @override
  Future<Stream<List<int>>> getFileStream(
    String path, {
    FileRange? range,
  }) async {
    final normalized = _normalize(path);
    // 优先用原生 FTP RETR/REST 流式读取，避免默认整文件下载到临时目录。
    if (_host != null && _enableRestRange) {
      final restStream = await _tryRestRangeStream(
        normalized,
        range?.start ?? 0,
        range?.end,
      );
      if (restStream != null) return restStream;
    }
    // 回退：整文件下载到临时文件后本地读取（妥协路径，零破坏）
    return _withLock(
      'getFileStream',
      () => _downloadWholeFileStream(normalized, range),
    );
  }

  /// 回退路径：整文件下载后本地 seek（ftpconnect 不支持 REST 时）。
  Future<Stream<List<int>>> _downloadWholeFileStream(
    String normalizedPath,
    FileRange? range,
  ) async {
    final tempDir = await getTemporaryDirectory();
    _tempCounter++;
    final tempFile = File(
      p.join(
        tempDir.path,
        'ftp_stream_${DateTime.now().millisecondsSinceEpoch}_$_tempCounter',
      ),
    );
    _pendingTempFiles.add(tempFile);

    final ok = await _ftp.downloadFile(normalizedPath, tempFile);
    if (!ok || !tempFile.existsSync()) {
      throw Exception(appL10n.ftpFileSystemDownloadFailed(normalizedPath));
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
    return stream.transform(
      StreamTransformer.fromHandlers(
        handleDone: (sink) async {
          sink.close();
          _scheduleCleanup(tempFile);
        },
        handleError: (error, st, sink) {
          sink.addError(error, st);
          _scheduleCleanup(tempFile);
        },
      ),
    );
  }

  /// 用原生 FTP RETR/REST 实现流式读取（不整文件下载）。
  ///
  /// 仅支持明文 FTP（与当前 ftpconnect 配置一致）。流程：另开一条控制连接
  /// 登录 → TYPE I → PASV → REST start → RETR path，从被动数据连接读取
  /// `[start, end)`。任何步骤失败都返回 null 以回退到整文件路径（零破坏）。
  Future<Stream<List<int>>?> _tryRestRangeStream(
    String path,
    int start,
    int? end,
  ) async {
    final host = _host;
    if (host == null) return null;
    const timeout = Duration(seconds: 15);
    Socket? control;
    Socket? data;
    _FtpControlReader? reader;

    Future<Stream<List<int>>?> fail() async {
      data?.destroy();
      control?.destroy();
      reader?.dispose();
      return null;
    }

    try {
      control = await Socket.connect(host, _port, timeout: timeout);
      reader = _FtpControlReader(control);

      if ((await reader.readReply(timeout)).code != 220) return fail();

      control.add(utf8.encode('USER ${_user ?? 'anonymous'}\r\n'));
      final userReply = await reader.readReply(timeout);
      if (userReply.code == 331) {
        control.add(utf8.encode('PASS ${_pass ?? ''}\r\n'));
        if ((await reader.readReply(timeout)).code != 230) return fail();
      } else if (userReply.code != 230) {
        return fail();
      }

      control.add(utf8.encode('TYPE I\r\n'));
      if ((await reader.readReply(timeout)).code != 200) return fail();

      control.add(utf8.encode('PASV\r\n'));
      final pasv = await reader.readReply(timeout);
      if (pasv.code != 227) return fail();
      final endpoint = _parsePasv(pasv.text);
      if (endpoint == null) return fail();

      data = await Socket.connect(endpoint.$1, endpoint.$2, timeout: timeout);

      if (start > 0) {
        control.add(utf8.encode('REST $start\r\n'));
        if ((await reader.readReply(timeout)).code != 350) return fail();
      }

      control.add(utf8.encode('RETR $path\r\n'));
      final retr = await reader.readReply(timeout);
      if (retr.code != 150 && retr.code != 125) return fail();

      final limit = end != null ? end - start : null;
      return _dataStreamWithCleanup(data, control, reader, limit);
    } on Object catch (e, st) {
      AppError.ignore(e, st, 'FtpFileSystem REST 流式失败，回退整文件');
      return fail();
    }
  }

  /// 从被动数据连接读取字节（可选限制为 [limit] 字节），结束时清理控制/数据连接。
  Stream<List<int>> _dataStreamWithCleanup(
    Socket data,
    Socket control,
    _FtpControlReader reader,
    int? limit,
  ) async* {
    var sent = 0;
    try {
      await for (final chunk in data) {
        if (limit == null) {
          yield chunk;
          continue;
        }
        if (sent >= limit) break;
        final remaining = limit - sent;
        if (chunk.length <= remaining) {
          sent += chunk.length;
          yield chunk;
        } else {
          sent += remaining;
          yield chunk.sublist(0, remaining);
          break;
        }
      }
    } finally {
      data.destroy();
      // 尽力读取 226 完成响应并退出，忽略超时/异常
      try {
        await reader.readReply(const Duration(seconds: 5));
        control.add(utf8.encode('QUIT\r\n'));
      } on Object {
        // ignore
      }
      control.destroy();
      reader.dispose();
    }
  }

  /// 解析 PASV 应答 "227 ... (h1,h2,h3,h4,p1,p2)" 为 (host, port)。
  (String, int)? _parsePasv(String text) {
    final m = RegExp(r'(\d+),(\d+),(\d+),(\d+),(\d+),(\d+)').firstMatch(text);
    if (m == null) return null;
    final host = '${m[1]}.${m[2]}.${m[3]}.${m[4]}';
    final port = (int.parse(m[5]!) << 8) + int.parse(m[6]!);
    return (host, port);
  }

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
      throw UnimplementedError(appL10n.ftpFileSystemUrlNotSupported);

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
      throw UnimplementedError(appL10n.ftpFileSystemServerSideCopyNotSupported);

  @override
  Future<void> move(String sourcePath, String destPath) =>
      rename(sourcePath, destPath);

  @override
  Future<void> upload(
    String localPath,
    String remotePath, {
    String? fileName,
    void Function(int sent, int total)? onProgress,
  }) => _withLock('upload', () async {
    final name = fileName ?? p.basename(localPath);
    final dir = remotePath.endsWith('/')
        ? remotePath.substring(0, remotePath.length - 1)
        : remotePath;
    await _ftp.changeDirectory(_normalize(dir));
    final ok = await _ftp.uploadFile(File(localPath), sRemoteName: name);
    if (!ok) {
      throw Exception(
        appL10n.ftpFileSystemUploadFailed(localPath, remotePath, name),
      );
    }
  });

  @override
  Future<void> writeFile(String remotePath, List<int> data) =>
      _withLock('writeFile', () async {
        final tempDir = await getTemporaryDirectory();
        final tempFile = File(
          p.join(
            tempDir.path,
            'ftp_write_${DateTime.now().millisecondsSinceEpoch}',
          ),
        );
        await tempFile.writeAsBytes(data);
        try {
          final dir = p.posix.dirname(_normalize(remotePath));
          final name = p.posix.basename(remotePath);
          await _ftp.changeDirectory(dir);
          final ok = await _ftp.uploadFile(tempFile, sRemoteName: name);
          if (!ok) {
            throw Exception(appL10n.ftpFileSystemWriteFailed(remotePath));
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
  Future<Uint8List?> getThumbnailData(
    String path, {
    ThumbnailSize? size,
  }) async => null;

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

/// 一条 FTP 控制应答（三位状态码 + 文本）。
class _FtpReply {
  _FtpReply(this.code, this.text);
  final int code;
  final String text;
}

/// 按需读取 FTP 控制连接应答（处理多行应答，以 "NNN " 行结束）。
class _FtpControlReader {
  _FtpControlReader(Socket socket) {
    _sub = socket.listen(
      (data) {
        _buffer += String.fromCharCodes(data);
        _tryComplete();
      },
      onError: _failAll,
      onDone: () => _failAll(const SocketException('FTP control closed')),
      cancelOnError: false,
    );
  }

  late final StreamSubscription<Uint8List> _sub;
  String _buffer = '';
  Completer<_FtpReply>? _pending;

  /// 读取下一条完整应答（带超时）。
  Future<_FtpReply> readReply(Duration timeout) {
    final completer = Completer<_FtpReply>();
    _pending = completer;
    _tryComplete();
    return completer.future.timeout(timeout);
  }

  void _tryComplete() {
    final pending = _pending;
    if (pending == null || pending.isCompleted) return;
    final reply = _extractReply();
    if (reply != null) {
      _pending = null;
      pending.complete(reply);
    }
  }

  _FtpReply? _extractReply() {
    final lines = _buffer.split('\n');
    final collected = <String>[];
    // 最后一段是未完成行（无结尾 \n），只遍历已完成的行
    for (var i = 0; i < lines.length - 1; i++) {
      final line = lines[i].replaceAll('\r', '');
      collected.add(line);
      final match = RegExp(r'^(\d{3}) ').firstMatch(line);
      if (match != null) {
        _buffer = lines.sublist(i + 1).join('\n');
        return _FtpReply(int.parse(match.group(1)!), collected.join('\n'));
      }
    }
    return null;
  }

  void _failAll(Object error) {
    final pending = _pending;
    if (pending != null && !pending.isCompleted) {
      _pending = null;
      pending.completeError(error);
    }
  }

  void dispose() {
    _sub.cancel();
  }
}
