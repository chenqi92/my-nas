import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

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
  const DownloadOpenResult({
    required this.success,
    this.message,
  });

  final bool success;
  final String? message;
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
  int totalBytes;
  int downloadedBytes;
  DownloadStatus status;
  String? errorMessage;

  double get progress =>
      totalBytes > 0 ? downloadedBytes / totalBytes : 0;

  String get progressText {
    if (totalBytes == 0) return '0%';
    return '${(progress * 100).toStringAsFixed(1)}%';
  }

  String get sizeText {
    if (totalBytes == 0) return '未知大小';
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
  }) =>
      DownloadTask(
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
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final savePath = customPath ?? path.join(await downloadDirectory, fileName);

    final task = DownloadTask(
      id: id,
      url: url,
      fileName: fileName,
      savePath: savePath,
    );

    _tasks[id] = task;
    _notifyListeners();

    return task;
  }

  /// 开始下载
  Future<void> startDownload(String taskId) async {
    final task = _tasks[taskId];
    if (task == null) return;

    final cancelToken = CancelToken();
    _cancelTokens[taskId] = cancelToken;

    _updateTask(taskId, status: DownloadStatus.downloading);

    try {
      // 检查是否支持断点续传
      var startBytes = 0;
      final file = File(task.savePath);
      if (await file.exists()) {
        startBytes = await file.length();
      }

      final response = await _dio.download(
        task.url,
        task.savePath,
        cancelToken: cancelToken,
        deleteOnError: false,
        options: Options(
          headers: startBytes > 0 ? {'Range': 'bytes=$startBytes-'} : null,
        ),
        onReceiveProgress: (received, total) {
          if (total != -1) {
            _updateTask(
              taskId,
              downloadedBytes: startBytes + received,
              totalBytes: startBytes + total,
            );
          }
        },
      );

      if (response.statusCode == 200 || response.statusCode == 206) {
        _updateTask(taskId, status: DownloadStatus.completed);
      } else {
        _updateTask(
          taskId,
          status: DownloadStatus.failed,
          errorMessage: '下载失败: ${response.statusCode}',
        );
      }
    } on DioException catch (e, st) {
      if (e.type == DioExceptionType.cancel) {
        // 用户取消操作，不需要上报
        AppError.ignore(e, st, '用户取消下载');
        return;
      }
      AppError.handle(e, st, 'startDownload', {'taskId': taskId, 'url': task.url});
      _updateTask(
        taskId,
        status: DownloadStatus.failed,
        errorMessage: e.message ?? '下载失败',
      );
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'startDownload', {'taskId': taskId, 'url': task.url});
      _updateTask(
        taskId,
        status: DownloadStatus.failed,
        errorMessage: e.toString(),
      );
    } finally {
      _cancelTokens.remove(taskId);
    }
  }

  /// 暂停下载
  void pauseDownload(String taskId) {
    final cancelToken = _cancelTokens[taskId];
    if (cancelToken != null && !cancelToken.isCancelled) {
      cancelToken.cancel('paused');
      _updateTask(taskId, status: DownloadStatus.paused);
    }
  }

  /// 恢复下载
  Future<void> resumeDownload(String taskId) async {
    final task = _tasks[taskId];
    if (task == null || task.status != DownloadStatus.paused) return;

    await startDownload(taskId);
  }

  /// 取消下载
  void cancelDownload(String taskId) {
    final cancelToken = _cancelTokens[taskId];
    if (cancelToken != null && !cancelToken.isCancelled) {
      cancelToken.cancel('cancelled');
    }
    _updateTask(taskId, status: DownloadStatus.cancelled);

    // 删除未完成的文件
    final task = _tasks[taskId];
    if (task != null) {
      final file = File(task.savePath);
      try {
        if (file.existsSync()) {
          file.deleteSync();
        }
      } on Exception catch (e, st) {
        AppError.ignore(e, st, '删除取消的下载文件失败');
      }
    }
  }

  /// 删除任务
  void removeTask(String taskId) {
    cancelDownload(taskId);
    _tasks.remove(taskId);
    _notifyListeners();
  }

  /// 重试下载
  Future<void> retryDownload(String taskId) async {
    final task = _tasks[taskId];
    if (task == null) return;

    // 删除失败的文件
    final file = File(task.savePath);
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '删除失败的下载文件时出错');
    }

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
      return const DownloadOpenResult(success: false, message: '任务不存在');
    }
    if (task.status != DownloadStatus.completed) {
      return const DownloadOpenResult(success: false, message: '文件尚未下载完成');
    }

    final file = File(task.savePath);
    if (!file.existsSync()) {
      return const DownloadOpenResult(success: false, message: '文件已被移除或路径无效');
    }

    try {
      final result = await OpenFilex.open(task.savePath);
      return DownloadOpenResult(
        success: result.type == ResultType.done,
        message: result.message,
      );
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '打开下载文件失败');
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
        return const DownloadOpenResult(success: false, message: '下载目录不存在');
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
      return const DownloadOpenResult(
        success: false,
        message: '当前平台不支持直接打开目录，请通过系统文件 App 访问',
      );
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '打开下载目录失败');
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
    _tasksController.add(tasks);
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
