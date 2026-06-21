import 'dart:async';
import 'dart:io';

import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/transfer/data/services/media_cache_service.dart';
import 'package:my_nas/features/transfer/data/services/transfer_database_service.dart';
import 'package:my_nas/features/transfer/data/services/uploaded_mark_service.dart';
import 'package:my_nas/features/transfer/domain/entities/transfer_task.dart';
import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart' as pm;
import 'package:uuid/uuid.dart';

/// 统一传输服务
///
/// 管理上传、下载、缓存任务的队列和执行
class TransferService {
  factory TransferService() => _instance ??= TransferService._();
  TransferService._();

  static TransferService? _instance;

  final _db = TransferDatabaseService();
  final _uploadedMarkService = UploadedMarkService();
  final _cacheService = MediaCacheService();

  /// 任务列表（内存缓存）
  final _tasks = <TransferTask>[];

  /// 任务流控制器
  final _taskController = StreamController<TransferTask>.broadcast();

  /// 任务列表变化流控制器
  final _tasksController = StreamController<List<TransferTask>>.broadcast();

  /// 当前连接映射（由外部设置）
  Map<String, SourceConnection> _connections = {};

  /// 最大并发传输数（运行时可调，1-3）。
  ///
  /// 由 `transferConcurrencyProvider` 持久化并在启动 / 改值时同步写入，
  /// [_processQueue] 运行时读取，改值即生效。
  static int maxConcurrentTransfers = 3;

  /// 启动时是否恢复未完成任务（默认 true，与现状一致）。
  ///
  /// 由 `resumeOnStartupProvider` 持久化并在启动时同步写入。关闭后 [init]
  /// 不再把数据库里未完成的任务读回内存队列（任务保留在 DB，不丢失）。
  static bool resumeOnStartup = true;

  /// 窗口最小化 / 隐藏后是否继续传输（默认 true，与现状一致）。
  ///
  /// 由 `backgroundTransferProvider` 持久化并在启动时同步写入。关闭后窗口监听器
  /// 调用 [pauseActiveForBackground] / [resumeFromBackground] 在隐藏时暂停、
  /// 恢复时续传。开态时这两个方法为 no-op，保持纯 Future 持续传输的现状。
  static bool backgroundTransfer = true;

  /// 当前正在传输的任务数
  int _activeTransfers = 0;

  /// 因「后台传输」关闭而被自动暂停的任务 id（仅恢复这批，不动用户手动暂停的）。
  final _backgroundPaused = <String>{};

  /// 是否已初始化
  bool _initialized = false;

  /// 任务变化流（单个任务更新）
  Stream<TransferTask> get taskStream => _taskController.stream;

  /// 任务列表变化流
  Stream<List<TransferTask>> get tasksStream => _tasksController.stream;

  /// 所有任务
  List<TransferTask> get allTasks => List.unmodifiable(_tasks);

  /// 上传任务
  List<TransferTask> get uploadTasks =>
      _tasks.where((t) => t.type == TransferType.upload).toList();

  /// 下载任务
  List<TransferTask> get downloadTasks =>
      _tasks.where((t) => t.type == TransferType.download).toList();

  /// 缓存任务
  List<TransferTask> get cacheTasks =>
      _tasks.where((t) => t.type == TransferType.cache).toList();

  /// 正在进行的上传任务数
  int get uploadingCount => uploadTasks
      .where((t) =>
          t.status == TransferStatus.transferring ||
          t.status == TransferStatus.queued)
      .length;

  /// 正在进行的下载任务数
  int get downloadingCount => downloadTasks
      .where((t) =>
          t.status == TransferStatus.transferring ||
          t.status == TransferStatus.queued)
      .length;

  /// 正在进行的缓存任务数
  int get cachingCount => cacheTasks
      .where((t) =>
          t.status == TransferStatus.transferring ||
          t.status == TransferStatus.queued)
      .length;

  /// 初始化服务
  Future<void> init() async {
    if (_initialized) return;

    try {
      await _db.init();
      await _uploadedMarkService.init();
      await _cacheService.init();

      // 从数据库加载未完成的任务（「启动恢复」关闭时跳过，任务仍保留在 DB）。
      if (resumeOnStartup) {
        final tasks = await _db.getActiveTasks();
        _tasks.addAll(tasks);

        // 重置正在传输的任务状态为暂停
        for (final task in _tasks) {
          if (task.status == TransferStatus.transferring) {
            task.status = TransferStatus.paused;
            await _db.updateTask(task);
          }
        }
      }

      _initialized = true;
      logger.i('TransferService: 初始化完成，加载 ${_tasks.length} 个任务');
    } catch (e, st) {
      AppError.handle(e, st, 'TransferService.init');
    }
  }

  /// 设置当前连接
  void setConnections(Map<String, SourceConnection> connections) {
    _connections = connections;
  }

  /// 添加上传任务
  Future<TransferTask?> addUploadTask({
    required String localPath,
    required String targetSourceId,
    required String targetPath,
    required MediaType mediaType,
    required int fileSize,
    String? assetId,
    int? songId,
    String? thumbnailPath,
  }) async {
    if (!_initialized) await init();

    try {
      final fileName = p.basename(localPath);
      final task = TransferTask(
        id: const Uuid().v4(),
        type: TransferType.upload,
        mediaType: mediaType,
        sourceId: 'local', // 上传任务的 sourceId 是本机
        sourcePath: localPath,
        fileName: fileName,
        fileSize: fileSize,
        targetSourceId: targetSourceId,
        targetPath: p.join(targetPath, fileName),
        createdAt: DateTime.now(),
        assetId: assetId,
        songId: songId,
        thumbnailPath: thumbnailPath,
      );

      _tasks.add(task);
      await _db.insertTask(task);
      _notifyTasksChanged();

      logger.i('TransferService: 添加上传任务 ${task.fileName}');

      // 尝试开始传输
      _processQueue();

      return task;
    } catch (e, st) {
      AppError.handle(e, st, 'TransferService.addUploadTask');
      return null;
    }
  }

  /// 添加下载任务
  Future<TransferTask?> addDownloadTask({
    required String sourceId,
    required String sourcePath,
    required String targetPath,
    required MediaType mediaType,
    required int fileSize,
    String? thumbnailPath,
  }) async {
    if (!_initialized) await init();

    try {
      final fileName = p.basename(sourcePath);
      final task = TransferTask(
        id: const Uuid().v4(),
        type: TransferType.download,
        mediaType: mediaType,
        sourceId: sourceId,
        sourcePath: sourcePath,
        fileName: fileName,
        fileSize: fileSize,
        targetPath: p.join(targetPath, fileName),
        createdAt: DateTime.now(),
        thumbnailPath: thumbnailPath,
      );

      _tasks.add(task);
      await _db.insertTask(task);
      _notifyTasksChanged();

      logger.i('TransferService: 添加下载任务 ${task.fileName}');

      _processQueue();

      return task;
    } catch (e, st) {
      AppError.handle(e, st, 'TransferService.addDownloadTask');
      return null;
    }
  }

  /// 添加缓存任务
  Future<TransferTask?> addCacheTask({
    required String sourceId,
    required String sourcePath,
    required MediaType mediaType,
    required int fileSize,
    String? thumbnailPath,
  }) async {
    if (!_initialized) await init();

    // 检查是否已缓存
    if (await _cacheService.isCached(sourceId, sourcePath)) {
      logger.i('TransferService: 文件已缓存，跳过 $sourcePath');
      return null;
    }

    try {
      final fileName = p.basename(sourcePath);
      final cachePath = await _cacheService.getCacheFilePath(sourceId, sourcePath, mediaType);

      final task = TransferTask(
        id: const Uuid().v4(),
        type: TransferType.cache,
        mediaType: mediaType,
        sourceId: sourceId,
        sourcePath: sourcePath,
        fileName: fileName,
        fileSize: fileSize,
        targetPath: cachePath,
        createdAt: DateTime.now(),
        thumbnailPath: thumbnailPath,
      );

      _tasks.add(task);
      await _db.insertTask(task);
      _notifyTasksChanged();

      logger.i('TransferService: 添加缓存任务 ${task.fileName}');

      _processQueue();

      return task;
    } catch (e, st) {
      AppError.handle(e, st, 'TransferService.addCacheTask');
      return null;
    }
  }

  /// 暂停任务
  Future<void> pauseTask(String taskId) async {
    final task = _tasks.firstWhere(
      (t) => t.id == taskId,
      orElse: () => throw StateError('Task not found: $taskId'),
    );

    if (!task.canPause) return;

    task.status = TransferStatus.paused;
    await _db.updateTask(task);
    _notifyTaskChanged(task);

    logger.i('TransferService: 暂停任务 ${task.fileName}');
  }

  /// 继续任务
  Future<void> resumeTask(String taskId) async {
    final task = _tasks.firstWhere(
      (t) => t.id == taskId,
      orElse: () => throw StateError('Task not found: $taskId'),
    );

    if (!task.canResume) return;

    task.status = TransferStatus.pending;
    await _db.updateTask(task);
    _notifyTaskChanged(task);

    logger.i('TransferService: 继续任务 ${task.fileName}');

    _processQueue();
  }

  /// 取消任务
  Future<void> cancelTask(String taskId) async {
    final task = _tasks.firstWhere(
      (t) => t.id == taskId,
      orElse: () => throw StateError('Task not found: $taskId'),
    );

    if (!task.canCancel) return;

    task.status = TransferStatus.cancelled;
    await _db.updateTask(task);
    _notifyTaskChanged(task);

    logger.i('TransferService: 取消任务 ${task.fileName}');
  }

  /// 重试任务
  Future<void> retryTask(String taskId) async {
    final task = _tasks.firstWhere(
      (t) => t.id == taskId,
      orElse: () => throw StateError('Task not found: $taskId'),
    );

    if (!task.canRetry) return;

    task..status = TransferStatus.pending
    ..error = null
    ..transferredBytes = 0;
    await _db.updateTask(task);
    _notifyTaskChanged(task);

    logger.i('TransferService: 重试任务 ${task.fileName}');

    _processQueue();
  }

  /// 删除任务
  Future<void> deleteTask(String taskId) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return;

    final task = _tasks[index];
    _tasks.removeAt(index);
    await _db.deleteTask(taskId);
    _notifyTasksChanged();

    logger.i('TransferService: 删除任务 ${task.fileName}');
  }

  /// 清除已完成的任务
  Future<void> clearCompletedTasks({TransferType? type}) async {
    final toRemove = _tasks.where((t) {
      if (t.status != TransferStatus.completed) return false;
      if (type != null && t.type != type) return false;
      // 缓存任务完成后不自动清除
      if (t.type == TransferType.cache) return false;
      return true;
    }).toList();

    for (final task in toRemove) {
      _tasks.remove(task);
      await _db.deleteTask(task.id);
    }

    _notifyTasksChanged();
    logger.i('TransferService: 清除 ${toRemove.length} 个已完成任务');
  }

  /// 窗口隐藏 / 最小化时暂停正在进行的任务（仅当「后台传输」关闭时生效）。
  ///
  /// 只暂停 transferring / queued / pending 的任务，并记录在 [_backgroundPaused]，
  /// 以便窗口恢复时只续传这批、不影响用户手动暂停的任务。开态时直接 no-op。
  Future<void> pauseActiveForBackground() async {
    if (backgroundTransfer) return;
    if (!_initialized) return;

    final toPause = _tasks
        .where((t) =>
            t.status == TransferStatus.transferring ||
            t.status == TransferStatus.queued ||
            t.status == TransferStatus.pending)
        .toList();

    for (final task in toPause) {
      if (!task.canPause &&
          task.status != TransferStatus.queued &&
          task.status != TransferStatus.pending) {
        continue;
      }
      _backgroundPaused.add(task.id);
      task.status = TransferStatus.paused;
      await _db.updateTask(task);
      _notifyTaskChanged(task);
    }

    if (toPause.isNotEmpty) {
      logger.i('TransferService: 后台传输关闭，暂停 ${_backgroundPaused.length} 个任务');
    }
  }

  /// 窗口恢复时续传此前因后台暂停的任务（仅恢复 [_backgroundPaused] 这批）。
  Future<void> resumeFromBackground() async {
    if (_backgroundPaused.isEmpty) return;
    if (!_initialized) return;

    final ids = _backgroundPaused.toList();
    _backgroundPaused.clear();

    for (final id in ids) {
      final index = _tasks.indexWhere((t) => t.id == id);
      if (index == -1) continue;
      final task = _tasks[index];
      // 仅当仍处于暂停态才恢复（用户可能期间已手动取消 / 删除）。
      if (task.status != TransferStatus.paused) continue;
      task.status = TransferStatus.pending;
      await _db.updateTask(task);
      _notifyTaskChanged(task);
    }

    logger.i('TransferService: 窗口恢复，续传 ${ids.length} 个后台暂停的任务');
    _processQueue();
  }

  /// 处理任务队列
  void _processQueue() {
    if (_activeTransfers >= maxConcurrentTransfers) return;

    // 获取待处理任务
    final pendingTasks = _tasks
        .where((t) =>
            t.status == TransferStatus.pending ||
            t.status == TransferStatus.queued)
        .toList();

    for (final task in pendingTasks) {
      if (_activeTransfers >= maxConcurrentTransfers) break;

      // 开始执行任务
      _executeTask(task);
    }
  }

  /// 执行任务
  /// 任务是否已被用户暂停/取消（传输循环据此中断）。
  bool _isInterrupted(TransferTask task) =>
      task.status == TransferStatus.paused ||
      task.status == TransferStatus.cancelled;

  /// 取消时清理未完成的本地文件（上传写在远端，不在此清理）。
  Future<void> _cleanupPartialFile(TransferTask task) async {
    if (task.type == TransferType.upload) return;
    try {
      final f = File(task.targetPath);
      if (await f.exists()) await f.delete();
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'cleanup partial transfer file');
    }
  }

  Future<void> _executeTask(TransferTask task) async {
    _activeTransfers++;
    task.status = TransferStatus.transferring;
    await _db.updateTask(task);
    _notifyTaskChanged(task);

    try {
      switch (task.type) {
        case TransferType.upload:
          await _executeUpload(task);
        case TransferType.download:
          await _executeDownload(task);
        case TransferType.cache:
          await _executeCache(task);
      }

      // 仅当传输自然结束才置完成；若期间被暂停/取消会在下方分支处理，
      // 不再无条件覆盖用户刚设置的 paused/cancelled 状态。
      task..status = TransferStatus.completed
      ..completedAt = DateTime.now();

      // 上传完成后标记
      if (task.type == TransferType.upload && task.targetSourceId != null) {
        await _uploadedMarkService.markUploaded(
          task.sourcePath,
          task.targetSourceId!,
          task.targetPath,
        );
      }

      // 缓存完成后记录
      if (task.type == TransferType.cache) {
        await _cacheService.recordCache(
          sourceId: task.sourceId,
          sourcePath: task.sourcePath,
          mediaType: task.mediaType,
          fileName: task.fileName,
          fileSize: task.fileSize,
          cachePath: task.targetPath,
        );
      }

      logger.i('TransferService: 任务完成 ${task.fileName}');
    } on _TransferInterrupted {
      // 用户暂停/取消：status 已由 pauseTask/cancelTask 设置，不覆盖。
      // 取消的下载/缓存清理未完成文件，便于重试时从头开始。
      if (task.status == TransferStatus.cancelled) {
        await _cleanupPartialFile(task);
      }
      logger.i(
          'TransferService: 任务中断 ${task.fileName} -> ${task.status.name}');
    } catch (e, st) {
      task..status = TransferStatus.failed
      ..error = e.toString();
      AppError.handle(e, st, 'TransferService._executeTask');
      logger.e('TransferService: 任务失败 ${task.fileName}', e, st);
    } finally {
      _activeTransfers--;
      await _db.updateTask(task);
      _notifyTaskChanged(task);

      // 继续处理队列
      _processQueue();
    }
  }

  /// 执行上传
  Future<void> _executeUpload(TransferTask task) async {
    final connection = _connections[task.targetSourceId];
    if (connection == null) {
      throw StateError(appL10n.transferServiceTargetConnectionUnavailable(task.targetSourceId ?? ''));
    }

    final fs = connection.adapter.fileSystem;

    // 获取本地文件
    File localFile;
    if (task.assetId != null) {
      // 从相册获取文件
      final asset = await pm.AssetEntity.fromId(task.assetId!);
      if (asset == null) {
        throw StateError(appL10n.transferServiceAlbumAssetNotFound(task.assetId!));
      }
      final file = await asset.file;
      if (file == null) {
        throw StateError(appL10n.transferServiceAlbumFileUnavailable(task.assetId!));
      }
      localFile = file;
    } else {
      localFile = File(task.sourcePath);
    }

    if (!await localFile.exists()) {
      throw StateError(appL10n.transferServiceLocalFileNotFound(task.sourcePath));
    }

    // 上传文件
    var lastBytes = 0;
    var lastTime = DateTime.now();
    await fs.upload(
      localFile.path,
      p.dirname(task.targetPath),
      fileName: task.fileName,
      onProgress: (sent, total) {
        if (_isInterrupted(task)) throw const _TransferInterrupted();
        task.transferredBytes = sent;
        final now = DateTime.now();
        final dtMs = now.difference(lastTime).inMilliseconds;
        if (dtMs >= 500) {
          task.speed = ((sent - lastBytes) * 1000 / dtMs).round();
          lastBytes = sent;
          lastTime = now;
        }
        _notifyTaskChanged(task);
      },
    );
    task.speed = 0;
  }

  /// 执行下载
  Future<void> _executeDownload(TransferTask task) async {
    final connection = _connections[task.sourceId];
    if (connection == null) {
      throw StateError(appL10n.transferServiceSourceConnectionUnavailable(task.sourceId));
    }

    final fs = connection.adapter.fileSystem;

    // 确保目标目录存在
    final targetDir = Directory(p.dirname(task.targetPath));
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    // 下载文件
    final stream = await fs.getFileStream(task.sourcePath);
    final file = File(task.targetPath);
    final sink = file.openWrite();

    var downloaded = 0;
    var lastBytes = 0;
    var lastTime = DateTime.now();
    await for (final chunk in stream) {
      if (_isInterrupted(task)) {
        await sink.close();
        throw const _TransferInterrupted();
      }
      sink.add(chunk);
      downloaded += chunk.length;
      task.transferredBytes = downloaded;
      // 每 ~500ms 采样一次瞬时速度（字节/秒）。
      final now = DateTime.now();
      final dtMs = now.difference(lastTime).inMilliseconds;
      if (dtMs >= 500) {
        task.speed = ((downloaded - lastBytes) * 1000 / dtMs).round();
        lastBytes = downloaded;
        lastTime = now;
      }
      _notifyTaskChanged(task);
    }

    task.speed = 0;
    await sink.close();

    // 如果是照片，保存到相册
    if (task.mediaType == MediaType.photo && Platform.isIOS || Platform.isAndroid) {
      await _savePhotoToGallery(task.targetPath);
      // 删除临时文件
      await file.delete();
    }
  }

  /// 执行缓存
  Future<void> _executeCache(TransferTask task) async {
    final connection = _connections[task.sourceId];
    if (connection == null) {
      throw StateError(appL10n.transferServiceSourceConnectionUnavailable(task.sourceId));
    }

    final fs = connection.adapter.fileSystem;

    // 确保缓存目录存在
    final cacheDir = Directory(p.dirname(task.targetPath));
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }

    // 下载到缓存
    final stream = await fs.getFileStream(task.sourcePath);
    final file = File(task.targetPath);
    final sink = file.openWrite();

    var downloaded = 0;
    var lastBytes = 0;
    var lastTime = DateTime.now();
    await for (final chunk in stream) {
      if (_isInterrupted(task)) {
        await sink.close();
        throw const _TransferInterrupted();
      }
      sink.add(chunk);
      downloaded += chunk.length;
      task.transferredBytes = downloaded;
      // 每 ~500ms 采样一次瞬时速度（字节/秒）。
      final now = DateTime.now();
      final dtMs = now.difference(lastTime).inMilliseconds;
      if (dtMs >= 500) {
        task.speed = ((downloaded - lastBytes) * 1000 / dtMs).round();
        lastBytes = downloaded;
        lastTime = now;
      }
      _notifyTaskChanged(task);
    }

    task.speed = 0;
    await sink.close();
  }

  /// 保存照片到相册
  Future<void> _savePhotoToGallery(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return;

      final bytes = await file.readAsBytes();
      await pm.PhotoManager.editor.saveImage(
        bytes,
        filename: p.basename(filePath),
      );

      logger.i('TransferService: 照片已保存到相册 $filePath');
    } catch (e, st) {
      AppError.handle(e, st, 'TransferService._savePhotoToGallery');
    }
  }

  /// 通知单个任务变化
  void _notifyTaskChanged(TransferTask task) {
    _taskController.add(task);
    _notifyTasksChanged();
  }

  /// 通知任务列表变化
  void _notifyTasksChanged() {
    _tasksController.add(List.unmodifiable(_tasks));
  }

  /// 获取已上传标记服务
  UploadedMarkService get uploadedMarkService => _uploadedMarkService;

  /// 获取缓存服务
  MediaCacheService get cacheService => _cacheService;

  /// 释放资源
  Future<void> dispose() async {
    await _taskController.close();
    await _tasksController.close();
  }
}

/// 内部哨兵异常：传输循环检测到任务被用户暂停/取消时抛出，
/// 让 [_executeTask] 区分「用户中断」与「真实失败」。
class _TransferInterrupted implements Exception {
  const _TransferInterrupted();
}
