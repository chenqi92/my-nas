import 'dart:async';
import 'dart:io';

import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

typedef MediaProxyFileSystemResolver =
    Future<NasFileSystem?> Function(String sourceId);

/// 媒体代理服务器
///
/// 为不支持直接 URL 访问的协议（如 SMB）提供 HTTP 代理
/// 将 SMB 等协议的文件流转换为 HTTP 流供播放器使用
class MediaProxyServer {
  factory MediaProxyServer() => _instance ??= MediaProxyServer._();
  MediaProxyServer._() : _fileSystemResolver = _resolveDefaultFileSystem;

  /// 独立实例，仅用于回归测试，不会替换应用级单例。
  MediaProxyServer.forTesting({
    required MediaProxyFileSystemResolver fileSystemResolver,
  }) : _fileSystemResolver = fileSystemResolver;

  static MediaProxyServer? _instance;

  final MediaProxyFileSystemResolver _fileSystemResolver;

  HttpServer? _server;
  int _port = 0;

  /// 递增 ID 计数器（避免并发注册时的碰撞）
  int _nextId = 0;

  /// 当前代理的文件信息
  final Map<String, _ProxyFileInfo> _proxyFiles = {};

  /// 正在传输的后端流。播放器 seek/退出时必须及时取消，否则 SMB 专用连接会残留。
  final Map<String, Set<_ProxyTransfer>> _activeTransfers = {};

  /// 服务器是否正在运行
  bool get isRunning => _server != null;

  /// 获取代理服务器端口
  int get port => _port;

  /// 启动代理服务器
  Future<void> start() async {
    if (_server != null) {
      logger.d('MediaProxyServer: 服务器已在运行，端口 $_port');
      return;
    }

    try {
      // 绑定到本地随机端口
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _port = _server!.port;
      logger.i('MediaProxyServer: 启动成功，端口 $_port');

      // 处理请求
      _server!.listen(
        _handleRequest,
        onError: (Object error, StackTrace st) {
          AppError.handle(error, st, 'MediaProxyServer.listen');
        },
      );
    } catch (e, st) {
      AppError.handle(e, st, 'MediaProxyServer.start');
      rethrow;
    }
  }

  /// 停止代理服务器
  Future<void> stop() async {
    if (_server == null) return;

    try {
      await _cancelAllTransfers();
      await _server!.close(force: true);
      _server = null;
      _port = 0;
      _proxyFiles.clear();
      logger.i('MediaProxyServer: 已停止');
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'MediaProxyServer.stop');
    }
  }

  /// 注册一个文件用于代理
  ///
  /// 返回可通过 HTTP 访问的代理 URL
  Future<String> registerFile({
    required String sourceId,
    required String filePath,
    required int fileSize,
  }) async {
    // 确保服务器已启动
    if (!isRunning) {
      await start();
    }

    // 生成唯一标识
    final id = (_nextId++).toString();

    _proxyFiles[id] = _ProxyFileInfo(
      sourceId: sourceId,
      filePath: filePath,
      fileSize: fileSize,
    );

    final proxyUrl = 'http://127.0.0.1:$_port/media/$id';
    logger.d('MediaProxyServer: 注册文件 $filePath => $proxyUrl');

    return proxyUrl;
  }

  /// 取消注册文件
  void unregisterFile(String id) {
    _proxyFiles.remove(id);
    unawaited(_cancelTransfers(id));
    logger.d('MediaProxyServer: 取消注册文件 $id');
  }

  /// 处理 HTTP 请求
  Future<void> _handleRequest(HttpRequest request) async {
    final path = request.uri.path;
    logger.d('MediaProxyServer: 收到请求 ${request.method} $path');

    // 解析路径: /media/{id}
    if (!path.startsWith('/media/')) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final id = path.substring('/media/'.length);
    final fileInfo = _proxyFiles[id];

    if (fileInfo == null) {
      logger.w('MediaProxyServer: 文件未注册 $id');
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    if (request.method != 'GET' && request.method != 'HEAD') {
      request.response
        ..statusCode = HttpStatus.methodNotAllowed
        ..headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
      await request.response.close();
      return;
    }

    try {
      await _streamFile(request, id, fileInfo);
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'MediaProxyServer._handleRequest', {
        'path': fileInfo.filePath,
        'sourceId': fileInfo.sourceId,
      });
      try {
        // 只有在还没发送响应头时才能设置状态码
        request.response.statusCode = HttpStatus.internalServerError;
        // ignore: avoid_catches_without_on_clauses
      } catch (_) {
        // 响应头可能已经发送
      }
      try {
        await request.response.close();
        // ignore: avoid_catches_without_on_clauses
      } catch (_) {
        // 响应可能已经关闭
      }
    }
  }

  /// 流式传输文件
  Future<void> _streamFile(
    HttpRequest request,
    String id,
    _ProxyFileInfo fileInfo,
  ) async {
    // Range 请求不能在每次 seek 前做额外健康探测，否则探测本身就可能阻塞
    // 本地 HTTP 响应。仅在连接状态明确不可用时由默认 resolver 尝试重连。
    final fileSystem = await _fileSystemResolver(fileInfo.sourceId);
    if (fileSystem == null) {
      logger.e('MediaProxyServer: 源连接失败 ${fileInfo.sourceId}');
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
      return;
    }

    final fileSize = await fileInfo.resolveFileSize(fileSystem);
    if (fileSize < 0) {
      throw FileSystemException(
        'Invalid media size: $fileSize',
        fileInfo.filePath,
      );
    }

    // 解析 Range 头
    FileRange? range;
    var contentLength = fileSize;
    var statusCode = HttpStatus.ok;

    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    if (rangeHeader != null) {
      range = _parseRangeHeader(rangeHeader, fileSize);
      if (range == null) {
        request.response
          ..statusCode = HttpStatus.requestedRangeNotSatisfiable
          ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
          ..headers.set(HttpHeaders.contentRangeHeader, 'bytes */$fileSize');
        await request.response.close();
        return;
      }
      contentLength = range.end! - range.start;
      statusCode = HttpStatus.partialContent;
      logger.d('MediaProxyServer: Range 请求 ${range.start}-${range.end}');
    }

    // 设置响应头
    request.response.statusCode = statusCode;
    request.response.headers.set(
      HttpHeaders.contentTypeHeader,
      _getMimeType(fileInfo.filePath),
    );
    request.response.headers.set(
      HttpHeaders.contentLengthHeader,
      contentLength,
    );
    request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');

    if (range != null) {
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes ${range.start}-${range.end! - 1}/$fileSize',
      );
    }

    // 对于 HEAD 请求只返回头信息
    if (request.method == 'HEAD') {
      await request.response.close();
      return;
    }

    // 单个本地播放 URL 同一时间只保留一个 GET 数据流。播放器 seek 会立即发来
    // 新 Range；主动取消旧流比等待 socket 断开更可靠，也能处理后端正阻塞读取、
    // 暂时无法通过 response.done 感知断开的情况。
    await _cancelTransfers(id);

    // 使用 StreamIterator 持有可显式取消的订阅。客户端在 seek 时会关闭旧的
    // HTTP 请求；response.done 随即取消 iterator，触发 SMB stream.onCancel，
    // 从而立即关闭 RandomAccessFile 与专用连接。
    _ProxyTransfer? transfer;
    try {
      final stream = await fileSystem.getFileStream(
        fileInfo.filePath,
        range: range,
      );
      final iterator = StreamIterator<List<int>>(stream);
      transfer = _ProxyTransfer(iterator, request.response);
      _activeTransfers.putIfAbsent(id, () => <_ProxyTransfer>{}).add(transfer);

      unawaited(
        request.response.done.then<void>(
          (_) => transfer?.cancel(),
          onError: (Object error, StackTrace st) async {
            AppError.ignore(error, st, 'MediaProxyServer: 客户端已断开，取消后端流');
            await transfer?.cancel();
          },
        ),
      );

      while (!transfer.isCancelled && await iterator.moveNext()) {
        request.response.add(iterator.current);
        // flush 提供背压并让客户端断开尽快反馈到本地代理。
        await request.response.flush();
      }

      if (!transfer.isCancelled) {
        await request.response.close();
      }
    } on HttpException catch (e, st) {
      AppError.ignore(e, st, 'MediaProxyServer: HTTP 客户端中断传输');
    } on SocketException catch (e, st) {
      AppError.ignore(e, st, 'MediaProxyServer: HTTP 客户端断开连接');
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'MediaProxyServer.streamTransfer', {
        'path': fileInfo.filePath,
        'sourceId': fileInfo.sourceId,
        'rangeStart': range?.start,
        'rangeEnd': range?.end,
      });
    } finally {
      if (transfer != null) {
        _activeTransfers[id]?.remove(transfer);
        if (_activeTransfers[id]?.isEmpty ?? false) {
          _activeTransfers.remove(id);
        }
        await transfer.cancel();
      }
      try {
        await request.response.close();
        // ignore: avoid_catches_without_on_clauses
      } catch (_) {
        // 响应可能已经关闭
      }
    }
  }

  /// 解析 Range 头
  FileRange? _parseRangeHeader(String rangeHeader, int fileSize) {
    if (fileSize <= 0 || rangeHeader.contains(',')) return null;

    // 支持 bytes=start-end、bytes=start- 以及 suffix range bytes=-length。
    final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(rangeHeader.trim());
    if (match == null) return null;

    final startText = match.group(1)!;
    final endText = match.group(2)!;
    if (startText.isEmpty && endText.isEmpty) return null;

    if (startText.isEmpty) {
      final suffixLength = int.tryParse(endText);
      if (suffixLength == null || suffixLength <= 0) return null;
      final start = suffixLength >= fileSize ? 0 : fileSize - suffixLength;
      return FileRange(start: start, end: fileSize);
    }

    final start = int.tryParse(startText);
    if (start == null || start < 0 || start >= fileSize) return null;

    var end = fileSize;
    if (endText.isNotEmpty) {
      final inclusiveEnd = int.tryParse(endText);
      if (inclusiveEnd == null || inclusiveEnd < start) return null;
      end = inclusiveEnd >= fileSize - 1 ? fileSize : inclusiveEnd + 1;
    }

    return FileRange(start: start, end: end);
  }

  static Future<NasFileSystem?> _resolveDefaultFileSystem(
    String sourceId,
  ) async {
    final manager = SourceManagerService();
    var conn = manager.getConnection(sourceId);
    if (conn == null || conn.status != SourceStatus.connected) {
      logger.w('MediaProxyServer: 源未连接，尝试重连 $sourceId');
      if (!await manager.ensureConnectionHealthy(sourceId)) return null;
      conn = manager.getConnection(sourceId);
    }
    return conn?.status == SourceStatus.connected
        ? conn!.adapter.fileSystem
        : null;
  }

  Future<void> _cancelTransfers(String id) async {
    final transfers = _activeTransfers.remove(id);
    if (transfers == null) return;
    await Future.wait(transfers.map((transfer) => transfer.cancel()));
  }

  Future<void> _cancelAllTransfers() async {
    final ids = _activeTransfers.keys.toList(growable: false);
    await Future.wait(ids.map(_cancelTransfers));
  }

  /// 根据文件扩展名获取 MIME 类型
  String _getMimeType(String filePath) {
    final ext = filePath.split('.').last.toLowerCase();
    return switch (ext) {
      'mp4' => 'video/mp4',
      'mkv' => 'video/x-matroska',
      'avi' => 'video/x-msvideo',
      'mov' => 'video/quicktime',
      'wmv' => 'video/x-ms-wmv',
      'flv' => 'video/x-flv',
      'webm' => 'video/webm',
      'ts' => 'video/mp2t',
      'm4v' => 'video/x-m4v',
      'mp3' => 'audio/mpeg',
      'flac' => 'audio/flac',
      'm4a' => 'audio/mp4',
      'aac' => 'audio/aac',
      'wav' => 'audio/wav',
      'ogg' => 'audio/ogg',
      'wma' => 'audio/x-ms-wma',
      _ => 'application/octet-stream',
    };
  }
}

/// 代理文件信息
class _ProxyFileInfo {
  _ProxyFileInfo({
    required this.sourceId,
    required this.filePath,
    required this.fileSize,
  });

  final String sourceId;
  final String filePath;
  final int fileSize;

  Future<int>? _resolvedFileSize;

  Future<int> resolveFileSize(NasFileSystem fileSystem) =>
      _resolvedFileSize ??= _loadFileSize(fileSystem);

  Future<int> _loadFileSize(NasFileSystem fileSystem) async {
    try {
      final actual = await fileSystem.getFileInfo(filePath);
      if (!actual.isDirectory && actual.size >= 0) return actual.size;
    } on Exception catch (e, st) {
      if (fileSize < 0) rethrow;
      AppError.ignore(e, st, 'MediaProxyServer: 获取真实文件大小失败，回退媒体库元数据');
    }
    return fileSize;
  }
}

class _ProxyTransfer {
  _ProxyTransfer(this._iterator, this._response);

  final StreamIterator<List<int>> _iterator;
  final HttpResponse _response;
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  Future<void> cancel() async {
    if (_isCancelled) return;
    _isCancelled = true;
    try {
      await _iterator.cancel();
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      // 底层连接可能已经被播放器关闭。
    }
    try {
      await _response.close();
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      // HTTP 客户端可能已经断开。
    }
  }
}
