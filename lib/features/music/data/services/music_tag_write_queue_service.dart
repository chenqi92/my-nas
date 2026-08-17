import 'dart:async';
import 'dart:typed_data';

import 'package:hive_ce/hive.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/music/data/services/music_tag_writer_service.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// 写入任务状态
enum WriteTaskStatus { pending, processing, completed, failed }

/// 写入任务
class WriteTask {
  WriteTask({
    required this.id,
    required this.musicPath,
    required this.sourceId,
    required this.tagData,
    this.coverData,
    this.coverMimeType,
    this.status = WriteTaskStatus.pending,
    this.retryCount = 0,
    this.errorMessage,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String musicPath;
  final String? sourceId;
  final MusicTagData tagData;
  final Uint8List? coverData;
  final String? coverMimeType;
  WriteTaskStatus status;
  int retryCount;
  String? errorMessage;
  final DateTime createdAt;

  static const int maxRetries = 3;

  bool get canRetry => retryCount < maxRetries;

  WriteTask copyWith({
    WriteTaskStatus? status,
    int? retryCount,
    String? errorMessage,
  }) => WriteTask(
    id: id,
    musicPath: musicPath,
    sourceId: sourceId,
    tagData: tagData,
    coverData: coverData,
    coverMimeType: coverMimeType,
    status: status ?? this.status,
    retryCount: retryCount ?? this.retryCount,
    errorMessage: errorMessage ?? this.errorMessage,
    createdAt: createdAt,
  );
}

/// 队列状态更新
class QueueStatusUpdate {
  const QueueStatusUpdate({
    required this.pendingCount,
    required this.processingCount,
    required this.failedCount,
    this.lastCompletedTaskId,
    this.lastError,
  });

  final int pendingCount;
  final int processingCount;
  final int failedCount;
  final String? lastCompletedTaskId;
  final String? lastError;

  bool get hasWork => pendingCount > 0 || processingCount > 0;
  bool get hasFailed => failedCount > 0;
}

/// 音乐标签后台写入队列服务
///
/// 将文件写入任务加入队列，后台异步执行，
/// 避免阻塞 UI 和会话超时问题
class MusicTagWriteQueueService {
  MusicTagWriteQueueService({required MusicTagWriterService tagWriter})
    : _tagWriter = tagWriter;

  final MusicTagWriterService _tagWriter;

  // 任务队列
  final List<WriteTask> _queue = [];

  // 是否正在处理
  bool _isProcessing = false;

  // 文件系统获取回调
  NasFileSystem? Function(String? sourceId)? _fileSystemProvider;

  // 状态流
  final _statusController = StreamController<QueueStatusUpdate>.broadcast();
  Stream<QueueStatusUpdate> get statusStream => _statusController.stream;

  // Hive box 用于持久化
  Box<Map<dynamic, dynamic>>? _box;
  static const String _boxName = 'music_tag_write_queue';

  /// 初始化服务
  Future<void> init() async {
    await _tagWriter.init();

    // 打开 Hive box
    try {
      final appDir = await getApplicationDocumentsDirectory();
      Hive.init(appDir.path);
      _box = await Hive.openBox<Map<dynamic, dynamic>>(_boxName);

      // 恢复未完成的任务
      await _restorePendingTasks();
    } on Exception catch (e, st) {
      AppError.ignore(e, st, appL10n.musicTagWriteQueueInitFailure);
    }

    logger.i('MusicTagWriteQueueService: 初始化完成');
  }

  /// 设置文件系统提供者
  void setFileSystemProvider(
    NasFileSystem? Function(String? sourceId) provider,
  ) {
    _fileSystemProvider = provider;
  }

  /// 添加写入任务到队列
  String addTask({
    required String musicPath,
    String? sourceId,
    required MusicTagData tagData,
    Uint8List? coverData,
    String? coverMimeType,
  }) {
    final taskId = const Uuid().v4();

    final task = WriteTask(
      id: taskId,
      musicPath: musicPath,
      sourceId: sourceId,
      tagData: tagData,
      coverData: coverData,
      coverMimeType: coverMimeType,
    );

    _queue.add(task);
    _persistTask(task);
    _notifyStatus();

    logger.d('MusicTagWriteQueueService: 任务已加入队列 - $musicPath');

    // 自动开始处理
    _processQueue();

    return taskId;
  }

  /// 获取任务状态
  WriteTask? getTask(String taskId) =>
      _queue.where((t) => t.id == taskId).firstOrNull;

  /// 获取队列状态
  QueueStatusUpdate getStatus() => QueueStatusUpdate(
    pendingCount: _queue
        .where((t) => t.status == WriteTaskStatus.pending)
        .length,
    processingCount: _queue
        .where((t) => t.status == WriteTaskStatus.processing)
        .length,
    failedCount: _queue.where((t) => t.status == WriteTaskStatus.failed).length,
  );

  /// 重试所有失败的任务
  void retryFailedTasks() {
    for (final task in _queue) {
      if (task.status == WriteTaskStatus.failed && task.canRetry) {
        task.status = WriteTaskStatus.pending;
        _persistTask(task);
      }
    }
    _notifyStatus();
    _processQueue();
  }

  /// 清除已完成的任务
  void clearCompletedTasks() {
    _queue.removeWhere((t) => t.status == WriteTaskStatus.completed);
    _cleanupPersistence();
    _notifyStatus();
  }

  /// 处理队列
  Future<void> _processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      while (true) {
        // 找到下一个待处理的任务
        final task = _queue
            .where((t) => t.status == WriteTaskStatus.pending)
            .firstOrNull;

        if (task == null) break;

        await _processTask(task);
      }
    } finally {
      _isProcessing = false;
    }
  }

  /// 处理单个任务
  Future<void> _processTask(WriteTask task) async {
    task.status = WriteTaskStatus.processing;
    await _persistTask(task);
    _notifyStatus();

    try {
      // 获取文件系统
      final fileSystem = _fileSystemProvider?.call(task.sourceId);
      if (fileSystem == null) {
        throw Exception(
          appL10n.musicTagWriteQueueFileSystemNotAvailable(task.sourceId ?? ''),
        );
      }

      // 构建标签数据（包含封面）
      final tagDataWithCover = MusicTagData(
        title: task.tagData.title,
        artist: task.tagData.artist,
        album: task.tagData.album,
        albumArtist: task.tagData.albumArtist,
        year: task.tagData.year,
        trackNumber: task.tagData.trackNumber,
        discNumber: task.tagData.discNumber,
        genre: task.tagData.genre,
        lyrics: task.tagData.lyrics,
        coverData: task.coverData,
        coverMimeType: task.coverMimeType,
      );

      // 执行写入
      final result = await _tagWriter.writeToNasFile(
        fileSystem,
        task.musicPath,
        tagDataWithCover,
        sourceId: task.sourceId,
      );

      if (!result.success) {
        throw Exception(result.error ?? appL10n.musicTagWriteQueueWriteError);
      }

      // 成功
      task
        ..status = WriteTaskStatus.completed
        ..errorMessage = null;
      await _persistTask(task);
      _notifyStatus(lastCompletedTaskId: task.id);

      logger.i('MusicTagWriteQueueService: 写入成功 - ${task.musicPath}');
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '后台写入任务失败');

      task.retryCount++;
      task.errorMessage = e.toString();

      if (task.canRetry) {
        // 可以重试，标记为待处理
        task.status = WriteTaskStatus.pending;
        logger.w(
          'MusicTagWriteQueueService: 写入失败，将重试 (${task.retryCount}/${WriteTask.maxRetries}) - ${task.musicPath}',
        );

        // 延迟一段时间后重试（指数退避）
        await Future<void>.delayed(Duration(seconds: task.retryCount * 2));
      } else {
        // 无法重试，标记为失败
        task.status = WriteTaskStatus.failed;
        logger.e(
          'MusicTagWriteQueueService: 写入失败，已达最大重试次数 - ${task.musicPath}',
        );
      }

      await _persistTask(task);
      _notifyStatus(lastError: task.errorMessage);
    }
  }

  /// 通知状态更新
  void _notifyStatus({String? lastCompletedTaskId, String? lastError}) {
    final status = QueueStatusUpdate(
      pendingCount: _queue
          .where((t) => t.status == WriteTaskStatus.pending)
          .length,
      processingCount: _queue
          .where((t) => t.status == WriteTaskStatus.processing)
          .length,
      failedCount: _queue
          .where((t) => t.status == WriteTaskStatus.failed)
          .length,
      lastCompletedTaskId: lastCompletedTaskId,
      lastError: lastError,
    );
    _statusController.add(status);
  }

  /// 持久化任务（简化版，只保存必要信息）
  Future<void> _persistTask(WriteTask task) async {
    if (_box == null) return;

    try {
      // 只持久化未完成的任务（不包含大的 coverData）
      if (task.status == WriteTaskStatus.completed) {
        await _box!.delete(task.id);
      } else {
        await _box!.put(task.id, {
          'id': task.id,
          'musicPath': task.musicPath,
          'sourceId': task.sourceId,
          'status': task.status.index,
          'retryCount': task.retryCount,
          'errorMessage': task.errorMessage,
          'createdAt': task.createdAt.millisecondsSinceEpoch,
          // 注意：不保存 tagData 和 coverData，重启后需要重新刮削
        });
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '持久化写入任务失败');
    }
  }

  /// 恢复待处理的任务
  Future<void> _restorePendingTasks() async {
    if (_box == null) return;

    // 简化处理：重启后清除失败的任务（因为没有保存完整数据）
    // 实际上需要用户重新刮削
    final keysToDelete = <dynamic>[];
    for (final key in _box!.keys) {
      final data = _box!.get(key);
      if (data != null) {
        final status = WriteTaskStatus.values[data['status'] as int? ?? 0];
        if (status != WriteTaskStatus.completed) {
          logger.w(
            'MusicTagWriteQueueService: 清除未完成的任务 - ${data['musicPath']}',
          );
          keysToDelete.add(key);
        }
      }
    }

    for (final key in keysToDelete) {
      await _box!.delete(key);
    }
  }

  /// 清理持久化
  Future<void> _cleanupPersistence() async {
    if (_box == null) return;

    final completedIds = _queue
        .where((t) => t.status == WriteTaskStatus.completed)
        .map((t) => t.id)
        .toSet();

    for (final key in _box!.keys.toList()) {
      if (completedIds.contains(key)) {
        await _box!.delete(key);
      }
    }
  }

  /// 释放资源
  void dispose() {
    _statusController.close();
  }
}
