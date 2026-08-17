import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/file_name_sanitizer.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// 下载任务状态
enum DownloadStatus {
  pending,
  downloading,
  paused,
  completed,
  failed,
  cancelled,
}

/// 打开文件 / 目录的操作结果
///
/// 由 [DownloadService.openFile] 和 [DownloadService.openDownloadDirectory] 返回，
/// 让调用方决定是否给用户弹 toast。
class DownloadOpenResult {
  const DownloadOpenResult({required this.success, this.message});

  final bool success;
  final String? message;
}

class _ContentRange {
  const _ContentRange({
    required this.start,
    required this.end,
    required this.total,
  });

  final int start;
  final int end;
  final int? total;
}

/// 下载任务
class DownloadTask {
  DownloadTask({
    required this.id,
    required this.url,
    required this.fileName,
    required this.savePath,
    this.totalBytes = 0,
    this.downloadedBytes = 0,
    this.status = DownloadStatus.pending,
    this.errorMessage,
  });

  final String id;
  final String url;
  final String fileName;
  final String savePath;

  /// 下载中的私有临时文件。最终文件只在完整校验后发布，取消/重试不会误删
  /// 同名的既有成品。
  String get partialPath => '$savePath.part.$id';
  int totalBytes;
  int downloadedBytes;
  DownloadStatus status;
  String? errorMessage;

  double get progress => totalBytes > 0 ? downloadedBytes / totalBytes : 0;

  String get progressText {
    if (totalBytes == 0) return '0%';
    return '${(progress * 100).toStringAsFixed(1)}%';
  }

  String get sizeText {
    if (totalBytes == 0) return appL10n.downloadServiceUnknownSize;
    return '${_formatBytes(downloadedBytes)} / ${_formatBytes(totalBytes)}';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  DownloadTask copyWith({
    int? totalBytes,
    int? downloadedBytes,
    DownloadStatus? status,
    String? errorMessage,
  }) => DownloadTask(
    id: id,
    url: url,
    fileName: fileName,
    savePath: savePath,
    totalBytes: totalBytes ?? this.totalBytes,
    downloadedBytes: downloadedBytes ?? this.downloadedBytes,
    status: status ?? this.status,
    errorMessage: errorMessage,
  );
}

/// 下载服务
class DownloadService {
  factory DownloadService() => _instance ??= DownloadService._();
  DownloadService._() {
    // 立即发送初始状态，避免 StreamProvider 一直显示 loading
    _notifyListeners();
  }

  static DownloadService? _instance;

  final Dio _dio = Dio();
  final Map<String, DownloadTask> _tasks = {};
  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, Completer<void>> _downloadCompletions = {};
  final Map<String, int> _taskEpochs = {};
  final Set<String> _pendingSavePaths = {};

  final _tasksController = StreamController<List<DownloadTask>>.broadcast();

  /// 获取任务流，首先发送当前状态
  Stream<List<DownloadTask>> get tasksStream async* {
    // 立即发送当前状态
    yield tasks;
    // 然后监听后续变化
    yield* _tasksController.stream;
  }

  List<DownloadTask> get tasks => _tasks.values.toList();

  /// 获取下载目录
  Future<String> get downloadDirectory async {
    if (Platform.isAndroid) {
      // Android 使用外部存储
      final dir = await getExternalStorageDirectory();
      return dir?.path ?? (await getApplicationDocumentsDirectory()).path;
    } else if (Platform.isIOS) {
      return (await getApplicationDocumentsDirectory()).path;
    } else {
      // macOS/Windows 使用下载目录
      final dir = await getDownloadsDirectory();
      return dir?.path ?? (await getApplicationDocumentsDirectory()).path;
    }
  }

  /// 添加下载任务
  Future<DownloadTask> addTask({
    required String url,
    required String fileName,
    String? customPath,
  }) async {
    final id = const Uuid().v4();
    final reservation = await _reserveSavePath(
      fileName: fileName,
      customPath: customPath,
    );
    try {
      final task = DownloadTask(
        id: id,
        url: url,
        fileName: fileName,
        savePath: reservation.savePath,
      );

      _tasks[id] = task;
      _notifyListeners();
      return task;
    } finally {
      _pendingSavePaths.remove(reservation.key);
    }
  }

  Future<({String savePath, String key})> _reserveSavePath({
    required String fileName,
    required String? customPath,
  }) async {
    if (customPath != null) {
      final key = _localPathKey(customPath);
      if (await _isSavePathTaken(customPath, key)) {
        throw StateError('目标文件已存在或已被其他下载任务占用: $customPath');
      }
      // 再检查一次内存占用，封住 File.exists await 期间的并发 addTask。
      if (_isSavePathReserved(key)) {
        throw StateError('目标文件已被其他下载任务占用: $customPath');
      }
      _pendingSavePaths.add(key);
      return (savePath: customPath, key: key);
    }

    final directory = await downloadDirectory;
    for (var sequence = 1; ; sequence++) {
      final candidate = path.join(
        directory,
        appendFileNameSequence(fileName, sequence),
      );
      final key = _localPathKey(candidate);
      if (await _isSavePathTaken(candidate, key)) continue;
      if (_isSavePathReserved(key)) continue;
      _pendingSavePaths.add(key);
      return (savePath: candidate, key: key);
    }
  }

  Future<bool> _isSavePathTaken(String candidate, String key) async {
    if (_isSavePathReserved(key)) return true;
    if (await File(candidate).exists()) return true;
    return Directory(candidate).exists();
  }

  bool _isSavePathReserved(String key) =>
      _pendingSavePaths.contains(key) ||
      _tasks.values.any((task) => _localPathKey(task.savePath) == key);

  String _localPathKey(String value) =>
      path.canonicalize(value).replaceAll(r'\', '/').toLowerCase();

  /// 开始下载
  Future<void> startDownload(String taskId) async {
    final task = _tasks[taskId];
    if (task == null ||
        task.status == DownloadStatus.completed ||
        task.status == DownloadStatus.cancelled ||
        task.status == DownloadStatus.downloading ||
        _cancelTokens.containsKey(taskId)) {
      return;
    }

    final cancelToken = CancelToken();
    final completion = Completer<void>();
    final epoch = (_taskEpochs[taskId] ?? 0) + 1;
    _taskEpochs[taskId] = epoch;
    _cancelTokens[taskId] = cancelToken;
    _downloadCompletions[taskId] = completion;

    _updateTask(taskId, status: DownloadStatus.downloading);

    try {
      // 检查是否支持断点续传
      var startBytes = 0;
      final file = File(task.partialPath);
      final finalFile = File(task.savePath);
      if (await finalFile.exists() || await Directory(task.savePath).exists()) {
        throw StateError('目标文件已存在，下载不会覆盖: ${task.savePath}');
      }
      await file.parent.create(recursive: true);
      if (await file.exists()) {
        startBytes = await file.length();
      }

      if (task.totalBytes > 0 && startBytes > task.totalBytes) {
        // 本地残片不可能属于当前版本，避免发送越界 Range 后陷入 416。
        await file.delete();
        startBytes = 0;
      } else if (startBytes > 0 && startBytes == task.totalBytes) {
        // 暂停可能发生在完整下载后的发布阶段。恢复时直接重新发布残片，
        // 不发送 bytes=<EOF>-（多数服务器会返回 416）。
        await _publishCompletedFile(
          partialFile: file,
          finalFile: finalFile,
          expectedLength: startBytes,
          isActive: () => _isActiveDownload(taskId, cancelToken, epoch),
        );
        if (!_isActiveDownload(taskId, cancelToken, epoch)) {
          await _deletePublishedAfterCancellation(finalFile);
          return;
        }
        _updateTask(
          taskId,
          status: DownloadStatus.completed,
          downloadedBytes: startBytes,
          totalBytes: startBytes,
        );
        return;
      }

      final response = await _dio.get<ResponseBody>(
        task.url,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          headers: startBytes > 0 ? {'Range': 'bytes=$startBytes-'} : null,
        ),
      );

      final responseBody = response.data;
      if (!_isActiveDownload(taskId, cancelToken, epoch)) {
        if (responseBody != null) await _cancelResponseStream(responseBody);
        return;
      }
      final statusCode = response.statusCode ?? 0;
      if (statusCode != 200 && statusCode != 206) {
        if (responseBody != null) await _cancelResponseStream(responseBody);
        _updateTask(
          taskId,
          status: DownloadStatus.failed,
          errorMessage: appL10n.downloadServiceDownloadFailed(statusCode),
        );
        return;
      }

      if (responseBody == null) {
        throw Exception('Empty download response');
      }

      final contentRangeValue = response.headers.value('content-range');
      final contentRange = _parseContentRange(contentRangeValue);
      if (statusCode == 206) {
        if (contentRange == null ||
            contentRange.total == null ||
            contentRange.start != startBytes) {
          await _cancelResponseStream(responseBody);
          throw FormatException(
            'Invalid Content-Range for offset $startBytes: $contentRangeValue',
          );
        }
        final expectedResponseLength =
            contentRange.end - contentRange.start + 1;
        if (responseBody.contentLength > 0 &&
            responseBody.contentLength != expectedResponseLength) {
          await _cancelResponseStream(responseBody);
          throw FormatException(
            'Content-Length does not match Content-Range: '
            '${responseBody.contentLength}/$expectedResponseLength',
          );
        }
      } else if (startBytes > 0) {
        // 服务器忽略 Range 时必须从头覆盖，不能把完整响应追加到旧文件。
        startBytes = 0;
      }

      final isAppending = startBytes > 0 && statusCode == 206;
      final contentLength = responseBody.contentLength;
      final totalBytes = _resolveDownloadTotalBytes(
        contentRange,
        contentLength,
        isAppending ? startBytes : 0,
      );
      if (totalBytes > 0) {
        _updateTask(
          taskId,
          downloadedBytes: startBytes,
          totalBytes: totalBytes,
        );
      }

      if (!_isActiveDownload(taskId, cancelToken, epoch)) {
        await _cancelResponseStream(responseBody);
        return;
      }
      final sink = file.openWrite(
        mode: isAppending ? FileMode.append : FileMode.write,
      );
      var received = 0;
      try {
        await for (final chunk in responseBody.stream) {
          if (!_isActiveDownload(taskId, cancelToken, epoch)) return;
          sink.add(chunk);
          received += chunk.length;
          _updateTask(
            taskId,
            downloadedBytes: startBytes + received,
            totalBytes: totalBytes,
          );
        }
      } finally {
        await sink.close();
      }

      if (!_isActiveDownload(taskId, cancelToken, epoch)) return;
      final finalLength = await file.length();
      if (!_isActiveDownload(taskId, cancelToken, epoch)) return;
      if (totalBytes > 0 && finalLength != totalBytes) {
        throw Exception(
          'Download length mismatch: $finalLength/$totalBytes bytes',
        );
      }

      await _publishCompletedFile(
        partialFile: file,
        finalFile: finalFile,
        expectedLength: finalLength,
        isActive: () => _isActiveDownload(taskId, cancelToken, epoch),
      );
      if (!_isActiveDownload(taskId, cancelToken, epoch)) {
        await _deletePublishedAfterCancellation(finalFile);
        return;
      }

      _updateTask(
        taskId,
        status: DownloadStatus.completed,
        downloadedBytes: finalLength,
        totalBytes: totalBytes > 0 ? totalBytes : finalLength,
      );
    } on DioException catch (e, st) {
      if (e.type == DioExceptionType.cancel ||
          !_isActiveDownload(taskId, cancelToken, epoch)) {
        // 用户取消操作，不需要上报
        AppError.ignore(e, st, 'User cancelled download');
        return;
      }
      AppError.handle(e, st, 'startDownload', {
        'taskId': taskId,
        'url': task.url,
      });
      _updateTask(
        taskId,
        status: DownloadStatus.failed,
        errorMessage: appL10n.downloadServiceDownloadFailedGeneric,
      );
    } on Object catch (e, st) {
      if (!_isActiveDownload(taskId, cancelToken, epoch)) return;
      AppError.handle(e, st, 'startDownload', {
        'taskId': taskId,
        'url': task.url,
      });
      _updateTask(
        taskId,
        status: DownloadStatus.failed,
        errorMessage: e.toString(),
      );
    } finally {
      if (identical(_cancelTokens[taskId], cancelToken)) {
        _cancelTokens.remove(taskId);
      }
      if (identical(_downloadCompletions[taskId], completion)) {
        _downloadCompletions.remove(taskId);
      }
      if (!completion.isCompleted) completion.complete();
    }
  }

  Future<void> _publishCompletedFile({
    required File partialFile,
    required File finalFile,
    required int expectedLength,
    required bool Function() isActive,
  }) async {
    var createdFinal = false;
    RandomAccessFile? output;
    try {
      // exclusive: true 保证即使外部程序在下载期间创建了同名文件，也绝不覆盖。
      await finalFile.create(exclusive: true);
      createdFinal = true;
      output = await finalFile.open(mode: FileMode.writeOnly);
      await for (final chunk in partialFile.openRead()) {
        if (!isActive()) throw const _DownloadPublishCancelled();
        await output.writeFrom(chunk);
      }
      if (!isActive()) throw const _DownloadPublishCancelled();
      await output.flush();
      await output.close();
      output = null;
      final publishedLength = await finalFile.length();
      if (publishedLength != expectedLength) {
        throw StateError(
          'Published download length mismatch: '
          '$publishedLength/$expectedLength bytes',
        );
      }
      if (!isActive()) throw const _DownloadPublishCancelled();
      await partialFile.delete();
    } on Object catch (e, st) {
      if (e is _DownloadPublishCancelled) {
        AppError.ignore(e, st, '下载在发布成品期间被用户暂停或取消');
      } else {
        AppError.handle(e, st, 'downloadService.publishCompletedFile', {
          'savePath': finalFile.path,
        });
      }
      if (createdFinal) {
        try {
          await output?.close();
          if (await finalFile.exists()) await finalFile.delete();
        } on Object catch (cleanupError, cleanupStack) {
          AppError.ignore(cleanupError, cleanupStack, '发布下载失败后清理不完整成品失败');
        }
      }
      rethrow;
    }
  }

  Future<void> _deletePublishedAfterCancellation(File finalFile) async {
    try {
      if (await finalFile.exists()) await finalFile.delete();
    } on Object catch (e, st) {
      AppError.ignore(e, st, '下载取消后清理刚发布的成品失败');
    }
  }

  bool _isActiveDownload(String taskId, CancelToken token, int epoch) =>
      !token.isCancelled &&
      identical(_cancelTokens[taskId], token) &&
      _taskEpochs[taskId] == epoch &&
      _tasks[taskId]?.status == DownloadStatus.downloading;

  Future<void> _cancelResponseStream(ResponseBody responseBody) async {
    try {
      final subscription = responseBody.stream.listen((_) {});
      await subscription.cancel();
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'Failed to cancel rejected download response');
    }
  }

  int _resolveDownloadTotalBytes(
    _ContentRange? contentRange,
    int contentLength,
    int alreadyDownloaded,
  ) {
    if (contentRange?.total != null) return contentRange!.total!;
    if (contentLength > 0) return alreadyDownloaded + contentLength;
    return 0;
  }

  _ContentRange? _parseContentRange(String? value) {
    if (value == null) return null;
    final match = RegExp(
      r'^bytes\s+(\d+)-(\d+)/(\d+|\*)$',
      caseSensitive: false,
    ).firstMatch(value.trim());
    if (match == null) return null;

    final start = int.tryParse(match.group(1)!);
    final end = int.tryParse(match.group(2)!);
    final totalText = match.group(3)!;
    final total = totalText == '*' ? null : int.tryParse(totalText);
    if (start == null || end == null || end < start) return null;
    if (total != null && (total <= end || start >= total)) return null;
    return _ContentRange(start: start, end: end, total: total);
  }

  /// 暂停下载
  void pauseDownload(String taskId) {
    final cancelToken = _cancelTokens[taskId];
    if (cancelToken != null && !cancelToken.isCancelled) {
      _taskEpochs[taskId] = (_taskEpochs[taskId] ?? 0) + 1;
      cancelToken.cancel('paused');
      _updateTask(taskId, status: DownloadStatus.paused);
    }
  }

  /// 恢复下载
  Future<void> resumeDownload(String taskId) async {
    final task = _tasks[taskId];
    if (task == null || task.status != DownloadStatus.paused) return;

    await _downloadCompletions[taskId]?.future;
    if (_tasks[taskId]?.status != DownloadStatus.paused) return;
    await startDownload(taskId);
  }

  /// 取消下载
  void cancelDownload(String taskId) {
    final task = _tasks[taskId];
    if (task == null || task.status == DownloadStatus.completed) return;

    final cancelToken = _cancelTokens[taskId];
    final completion = _downloadCompletions[taskId]?.future;
    final cancelEpoch = (_taskEpochs[taskId] ?? 0) + 1;
    _taskEpochs[taskId] = cancelEpoch;
    if (cancelToken != null && !cancelToken.isCancelled) {
      cancelToken.cancel('cancelled');
    }
    _updateTask(taskId, status: DownloadStatus.cancelled);

    // 等待正在写入的 sink 关闭后再删除，避免取消状态被写协程覆盖或 Windows 删除失败。
    AppError.fireAndForget(
      _deleteCancelledFile(
        taskId: taskId,
        partialPath: task.partialPath,
        cancelEpoch: cancelEpoch,
        activeDownload: completion,
      ),
      action: 'downloadService.deleteCancelledFile',
    );
  }

  Future<void> _deleteCancelledFile({
    required String taskId,
    required String partialPath,
    required int cancelEpoch,
    Future<void>? activeDownload,
  }) async {
    if (activeDownload != null) await activeDownload;
    if (_taskEpochs[taskId] != cancelEpoch) return;
    final file = File(partialPath);
    try {
      if (await file.exists()) await file.delete();
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'Failed to delete cancelled download file');
    }
  }

  /// 删除任务
  void removeTask(String taskId) {
    if (_tasks[taskId]?.status != DownloadStatus.completed) {
      cancelDownload(taskId);
    }
    _tasks.remove(taskId);
    _notifyListeners();
  }

  /// 重试下载
  Future<void> retryDownload(String taskId) async {
    final task = _tasks[taskId];
    if (task == null || task.status == DownloadStatus.downloading) return;

    await _downloadCompletions[taskId]?.future;

    // 只删除该任务自己的临时文件，绝不触碰同名既有成品。
    final file = File(task.partialPath);
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'Error deleting failed download file');
    }

    _updateTask(
      taskId,
      status: DownloadStatus.pending,
      downloadedBytes: 0,
      totalBytes: 0,
    );
    await startDownload(taskId);
  }

  /// 打开下载的文件
  ///
  /// 桌面端：调用系统默认应用打开文件
  /// iOS：尝试用 [OpenFilex] 唤起对应的查看器；某些类型可能受沙盒限制
  /// Android：通过 FileProvider intent 打开（已在 manifest 中配置）
  Future<DownloadOpenResult> openFile(String taskId) async {
    final task = _tasks[taskId];
    if (task == null) {
      return DownloadOpenResult(
        success: false,
        message: appL10n.downloadServiceTaskNotFound,
      );
    }
    if (task.status != DownloadStatus.completed) {
      return DownloadOpenResult(
        success: false,
        message: appL10n.downloadServiceFileNotCompleted,
      );
    }

    final file = File(task.savePath);
    if (!file.existsSync()) {
      return DownloadOpenResult(
        success: false,
        message: appL10n.downloadServiceFileNotFound,
      );
    }

    try {
      final result = await OpenFilex.open(task.savePath);
      return DownloadOpenResult(
        success: result.type == ResultType.done,
        message: result.message,
      );
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'Failed to open download file');
      return DownloadOpenResult(success: false, message: e.toString());
    }
  }

  /// 打开下载目录
  ///
  /// 桌面端：调用系统文件管理器（Finder / Explorer / xdg-open）
  /// 移动端：返回失败 + 提示——iOS / Android 没有"打开任意目录"的语义
  Future<DownloadOpenResult> openDownloadDirectory() async {
    try {
      final dir = await downloadDirectory;
      final directory = Directory(dir);
      if (!directory.existsSync()) {
        return DownloadOpenResult(
          success: false,
          message: appL10n.downloadServiceDirectoryNotFound,
        );
      }

      if (Platform.isMacOS) {
        await Process.run('open', [dir]);
        return const DownloadOpenResult(success: true);
      }
      if (Platform.isWindows) {
        await Process.run('explorer', [dir]);
        return const DownloadOpenResult(success: true);
      }
      if (Platform.isLinux) {
        await Process.run('xdg-open', [dir]);
        return const DownloadOpenResult(success: true);
      }
      // 移动端：OpenFilex 在 iOS 不能打开目录，Android 通常需要 SAF；
      // 提示用户从系统文件 App 自行进入即可。
      return DownloadOpenResult(
        success: false,
        message: appL10n.downloadServiceMobileNotSupported,
      );
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'Failed to open download directory');
      return DownloadOpenResult(success: false, message: e.toString());
    }
  }

  void _updateTask(
    String taskId, {
    int? totalBytes,
    int? downloadedBytes,
    DownloadStatus? status,
    String? errorMessage,
  }) {
    final task = _tasks[taskId];
    if (task == null) return;

    _tasks[taskId] = task.copyWith(
      totalBytes: totalBytes,
      downloadedBytes: downloadedBytes,
      status: status,
      errorMessage: errorMessage,
    );
    _notifyListeners();
  }

  void _notifyListeners() {
    if (!_tasksController.isClosed) _tasksController.add(tasks);
  }

  void dispose() {
    _tasksController.close();
    for (final token in _cancelTokens.values) {
      if (!token.isCancelled) {
        token.cancel();
      }
    }
  }
}

/// 全局下载服务实例
final downloadService = DownloadService();

class _DownloadPublishCancelled implements Exception {
  const _DownloadPublishCancelled();
}
