import 'dart:async';
import 'dart:io';

import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/file_name_sanitizer.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/core/utils/nas_path.dart';
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

  /// 每个任务当前唯一的一次执行。暂停/取消后必须等旧执行退出，才能恢复或重试，
  /// 否则两个流会同时写入同一个临时文件。
  final Map<String, Completer<void>> _activeRuns = {};

  /// [addDownloadTask] 在文件系统检查与写入任务列表之间的并发路径预留。
  final Set<String> _pendingDownloadTargets = {};

  /// 防止同一远端文件的两个并发缓存请求都在异步查库后创建任务。
  final Set<String> _pendingCacheSources = {};

  /// 因「后台传输」关闭而被自动暂停的任务 id（仅恢复这批，不动用户手动暂停的）。
  final _backgroundPaused = <String>{};

  /// 是否已初始化
  bool _initialized = false;
  Future<void>? _initializing;

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
      .where(
        (t) =>
            t.status == TransferStatus.transferring ||
            t.status == TransferStatus.queued,
      )
      .length;

  /// 正在进行的下载任务数
  int get downloadingCount => downloadTasks
      .where(
        (t) =>
            t.status == TransferStatus.transferring ||
            t.status == TransferStatus.queued,
      )
      .length;

  /// 正在进行的缓存任务数
  int get cachingCount => cacheTasks
      .where(
        (t) =>
            t.status == TransferStatus.transferring ||
            t.status == TransferStatus.queued,
      )
      .length;

  /// 初始化服务
  Future<void> init() async {
    if (_initialized) return;
    final active = _initializing;
    if (active != null) return active;

    final future = _initialize();
    _initializing = future;
    try {
      await future;
    } finally {
      if (identical(_initializing, future)) _initializing = null;
    }
  }

  Future<void> _initialize() async {
    try {
      await _db.init();
      await _uploadedMarkService.init();
      await _cacheService.init();

      // 从数据库加载未完成的任务（「启动恢复」关闭时跳过，任务仍保留在 DB）。
      if (resumeOnStartup) {
        final tasks = await _db.getActiveTasks();
        final knownIds = _tasks.map((task) => task.id).toSet();
        _tasks.addAll(tasks.where((task) => knownIds.add(task.id)));

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
    } on Object catch (e, st) {
      AppError.handle(e, st, 'TransferService.init');
      rethrow;
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
      final remoteTargetPath = nasPathJoin(targetPath, fileName);
      final remoteTargetKey = _remotePathKey(remoteTargetPath);
      if (_tasks.any(
        (task) =>
            task.type == TransferType.upload &&
            task.status != TransferStatus.completed &&
            task.targetSourceId == targetSourceId &&
            _remotePathKey(task.targetPath) == remoteTargetKey,
      )) {
        // 重复入队是用户重复点击/批量重试的预期结果，不是异常：抛 StateError
        // 会被 AppError 归入 fatal 分类刷 logger.f，这里按跳过处理。
        logger.i('TransferService: 同一 NAS 目标已有未完成的上传任务，跳过 $remoteTargetPath');
        return null;
      }
      final task = TransferTask(
        id: const Uuid().v4(),
        type: TransferType.upload,
        mediaType: mediaType,
        sourceId: 'local', // 上传任务的 sourceId 是本机
        sourcePath: localPath,
        fileName: fileName,
        fileSize: fileSize,
        targetSourceId: targetSourceId,
        // 上传目标是远端 NAS 路径，用 / 拼接（Windows 宿主上 p.join 会混入 \）
        targetPath: remoteTargetPath,
        createdAt: DateTime.now(),
        assetId: assetId,
        songId: songId,
        thumbnailPath: thumbnailPath,
      );

      await _addAndPersistTask(task);
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

    ({String path, String key})? reservation;
    try {
      // sourcePath 是远端路径，取名用 POSIX 风格；targetPath 是本机目录，用平台风格
      final fileName = sanitizeFileName(nasPathBasename(sourcePath));
      reservation = await _reserveDownloadTarget(targetPath, fileName);
      final task = TransferTask(
        id: const Uuid().v4(),
        type: TransferType.download,
        mediaType: mediaType,
        sourceId: sourceId,
        sourcePath: sourcePath,
        fileName: fileName,
        fileSize: fileSize,
        targetPath: reservation.path,
        createdAt: DateTime.now(),
        thumbnailPath: thumbnailPath,
      );

      await _addAndPersistTask(task);
      _notifyTasksChanged();

      logger.i('TransferService: 添加下载任务 ${task.fileName}');

      _processQueue();

      return task;
    } catch (e, st) {
      AppError.handle(e, st, 'TransferService.addDownloadTask');
      return null;
    } finally {
      final key = reservation?.key;
      if (key != null) _pendingDownloadTargets.remove(key);
    }
  }

  Future<({String path, String key})> _reserveDownloadTarget(
    String directory,
    String fileName,
  ) async {
    for (var sequence = 1; ; sequence++) {
      final candidate = p.join(
        directory,
        appendFileNameSequence(fileName, sequence),
      );
      if (await FileSystemEntity.type(candidate) !=
          FileSystemEntityType.notFound) {
        continue;
      }
      final key = _localPathKey(candidate);
      if (_pendingDownloadTargets.contains(key) ||
          _tasks.any(
            (task) =>
                task.type != TransferType.upload &&
                _localPathKey(task.targetPath) == key,
          )) {
        continue;
      }
      _pendingDownloadTargets.add(key);
      return (path: candidate, key: key);
    }
  }

  String _localPathKey(String value) =>
      p.canonicalize(value).replaceAll(r'\', '/').toLowerCase();

  String _remotePathKey(String value) =>
      value.replaceAll(r'\', '/').replaceAll(RegExp('/+'), '/').toLowerCase();

  Future<void> _addAndPersistTask(TransferTask task) async {
    _tasks.add(task);
    var persisted = false;
    try {
      await _db.insertTask(task);
      persisted = true;
    } finally {
      if (!persisted) {
        // 数据库写入失败时回滚内存状态，避免向 UI 暴露无法在重启后恢复的幽灵任务。
        _tasks.remove(task);
      }
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

    final cacheKey = '$sourceId\u0000$sourcePath';
    if (!_pendingCacheSources.add(cacheKey)) return null;

    try {
      // 同时检查已完成缓存和内存中的未完成任务。集合预留覆盖两个 await
      // 之间的竞态窗口，确保同一源文件最多只有一个缓存写入者。
      if (await _cacheService.isCached(sourceId, sourcePath) ||
          _tasks.any(
            (task) =>
                task.type == TransferType.cache &&
                task.sourceId == sourceId &&
                task.sourcePath == sourcePath,
          )) {
        logger.i('TransferService: 文件已缓存或已有缓存任务，跳过 $sourcePath');
        return null;
      }

      final fileName = sanitizeFileName(nasPathBasename(sourcePath));
      final cachePath = await _cacheService.getCacheFilePath(
        sourceId,
        sourcePath,
        mediaType,
      );

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

      await _addAndPersistTask(task);
      _notifyTasksChanged();

      logger.i('TransferService: 添加缓存任务 ${task.fileName}');

      _processQueue();

      return task;
    } catch (e, st) {
      AppError.handle(e, st, 'TransferService.addCacheTask');
      return null;
    } finally {
      _pendingCacheSources.remove(cacheKey);
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

    // pauseTask 只改变状态；旧下载流会在下一个数据块处退出。必须等它关闭
    // sink 后再启动新执行，避免两个执行同时写同一个 .part 文件。
    await _activeRuns[taskId]?.future;
    if (!_tasks.contains(task) || !task.canResume) return;

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

    if (!_activeRuns.containsKey(taskId)) {
      await _cleanupPartialFile(task);
    }

    logger.i('TransferService: 取消任务 ${task.fileName}');
  }

  /// 重试任务
  Future<void> retryTask(String taskId) async {
    final task = _tasks.firstWhere(
      (t) => t.id == taskId,
      orElse: () => throw StateError('Task not found: $taskId'),
    );

    if (!task.canRetry) return;

    await _activeRuns[taskId]?.future;
    if (!_tasks.contains(task) || !task.canRetry) return;
    await _cleanupPartialFile(task);

    task
      ..status = TransferStatus.pending
      ..error = null
      ..transferredBytes = 0;
    await _db.updateTask(task);
    _notifyTaskChanged(task);

    logger.i('TransferService: 重试任务 ${task.fileName}');

    _processQueue();
  }

  /// 删除任务
  Future<void> deleteTask(String taskId) async {
    var index = _tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return;

    final task = _tasks[index];
    if (task.canCancel) {
      await cancelTask(taskId);
    }
    await _activeRuns[taskId]?.future;
    await _cleanupPartialFile(task);

    // 等待执行退出期间列表可能已被另一处更新，删除前重新定位。
    index = _tasks.indexWhere((candidate) => candidate.id == taskId);
    if (index == -1) return;
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
        .where(
          (t) =>
              t.status == TransferStatus.transferring ||
              t.status == TransferStatus.queued ||
              t.status == TransferStatus.pending,
        )
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
    var resumed = 0;

    for (final id in ids) {
      final index = _tasks.indexWhere((t) => t.id == id);
      if (index == -1) {
        _backgroundPaused.remove(id);
        continue;
      }
      final task = _tasks[index];
      // 仅当仍处于暂停态才恢复（用户可能期间已手动取消 / 删除）。
      if (task.status != TransferStatus.paused) {
        _backgroundPaused.remove(id);
        continue;
      }
      await _activeRuns[id]?.future;
      if (!_tasks.contains(task) || task.status != TransferStatus.paused) {
        _backgroundPaused.remove(id);
        continue;
      }
      task.status = TransferStatus.pending;
      await _db.updateTask(task);
      _notifyTaskChanged(task);
      _backgroundPaused.remove(id);
      resumed++;
    }

    logger.i('TransferService: 窗口恢复，续传 $resumed 个后台暂停的任务');
    _processQueue();
  }

  /// 处理任务队列
  void _processQueue() {
    if (_activeTransfers >= maxConcurrentTransfers) return;

    // 获取待处理任务
    final pendingTasks = _tasks
        .where(
          (t) =>
              !_activeRuns.containsKey(t.id) &&
              (t.status == TransferStatus.pending ||
                  t.status == TransferStatus.queued),
        )
        .toList();

    for (final task in pendingTasks) {
      if (_activeTransfers >= maxConcurrentTransfers) break;

      // 开始执行任务
      AppError.fireAndForget(
        _executeTask(task),
        action: 'transferService.execute.${task.id}',
      );
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
      final f = File(_partialPath(task));
      if (await f.exists()) await f.delete();
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'cleanup partial transfer file');
    }
  }

  Future<void> _cleanupCancelledOutput(TransferTask task) async {
    await _cleanupPartialFile(task);
    if (task.type == TransferType.upload) return;
    if (task.type == TransferType.cache) {
      await _cacheService.deleteCache(task.sourceId, task.sourcePath);
      // recordCache 可能在写数据库前失败；此时 deleteCache 查不到路径，仍需
      // 按任务持有的目标路径补一次清理。
    }
    try {
      final published = File(task.targetPath);
      if (await published.exists()) await published.delete();
    } on Object catch (e, st) {
      AppError.ignore(e, st, '取消传输后清理已发布的本地成品失败');
    }
  }

  String _partialPath(TransferTask task) =>
      '${task.targetPath}.part.${task.id}';

  Future<void> _executeTask(TransferTask task) async {
    if (_activeRuns.containsKey(task.id)) return;
    if (task.status != TransferStatus.pending &&
        task.status != TransferStatus.queued) {
      return;
    }
    final completion = Completer<void>();
    _activeRuns[task.id] = completion;
    _activeTransfers++;

    try {
      task.status = TransferStatus.transferring;
      await _db.updateTask(task);
      _notifyTaskChanged(task);

      switch (task.type) {
        case TransferType.upload:
          await _executeUpload(task);
        case TransferType.download:
          await _executeDownload(task);
        case TransferType.cache:
          await _executeCache(task);
      }

      // 操作返回表示文件已经完整发布。此后收到取消仍要删除本地成品；暂停
      // 则不能留下“成品存在、残片已删、恢复必失败”的状态，按已完成收口。
      if (task.status == TransferStatus.cancelled) {
        throw const _TransferInterrupted();
      }

      // 上传完成后标记
      if (task.type == TransferType.upload && task.targetSourceId != null) {
        try {
          await _uploadedMarkService.markUploaded(
            task.sourcePath,
            task.targetSourceId!,
            task.targetPath,
          );
        } on Object catch (e, st) {
          // 远端上传已经不可逆地完成。仅标记失败时重试会再次上传同一文件，
          // 因此记录错误但保持传输成功。
          AppError.handle(e, st, 'TransferService.markUploadedAfterSuccess', {
            'targetPath': task.targetPath,
          });
        }
      }

      // 缓存完成后记录
      if (task.type == TransferType.cache) {
        try {
          await _cacheService.recordCache(
            sourceId: task.sourceId,
            sourcePath: task.sourcePath,
            mediaType: task.mediaType,
            fileName: task.fileName,
            fileSize: task.fileSize,
            cachePath: task.targetPath,
          );
        } on Object catch (e, st) {
          // 缓存索引失败时删除刚发布的文件，让 failed 任务可以安全重试，
          // 避免“磁盘有文件但索引没有、重试又因 exclusive 失败”的死状态。
          try {
            final published = File(task.targetPath);
            if (await published.exists()) await published.delete();
          } on Object catch (cleanupError, cleanupStack) {
            AppError.ignore(cleanupError, cleanupStack, '缓存索引失败后清理未登记成品失败');
          }
          Error.throwWithStackTrace(e, st);
        }
      }

      if (task.status == TransferStatus.cancelled) {
        throw const _TransferInterrupted();
      }

      // 仅当传输及必要的本地登记都完成后才置完成；若期间被暂停/取消会在
      // 下方分支处理，不覆盖用户刚设置的 paused/cancelled 状态。
      task
        ..status = TransferStatus.completed
        ..completedAt = DateTime.now();

      logger.i('TransferService: 任务完成 ${task.fileName}');
    } on _TransferInterrupted {
      // 用户暂停/取消：status 已由 pauseTask/cancelTask 设置，不覆盖。
      // 取消的下载/缓存清理未完成文件，便于重试时从头开始。
      if (task.status == TransferStatus.cancelled) {
        await _cleanupCancelledOutput(task);
      }
      logger.i('TransferService: 任务中断 ${task.fileName} -> ${task.status.name}');
    } catch (e, st) {
      task
        ..status = TransferStatus.failed
        ..error = e.toString();
      AppError.handle(e, st, 'TransferService._executeTask');
      logger.e('TransferService: 任务失败 ${task.fileName}', e, st);
    } finally {
      _activeTransfers--;
      try {
        await _db.updateTask(task);
        _notifyTaskChanged(task);
      } finally {
        if (identical(_activeRuns[task.id], completion)) {
          _activeRuns.remove(task.id);
        }
        if (!completion.isCompleted) completion.complete();

        // 继续处理队列
        _processQueue();
      }
    }
  }

  /// 执行上传
  Future<void> _executeUpload(TransferTask task) async {
    final connection = _connections[task.targetSourceId];
    if (connection == null) {
      throw StateError(
        appL10n.transferServiceTargetConnectionUnavailable(
          task.targetSourceId ?? '',
        ),
      );
    }

    final fs = connection.adapter.fileSystem;

    // 获取本地文件
    File localFile;
    if (task.assetId != null) {
      // 从相册获取文件
      final asset = await pm.AssetEntity.fromId(task.assetId!);
      if (asset == null) {
        throw StateError(
          appL10n.transferServiceAlbumAssetNotFound(task.assetId!),
        );
      }
      final file = await asset.file;
      if (file == null) {
        throw StateError(
          appL10n.transferServiceAlbumFileUnavailable(task.assetId!),
        );
      }
      localFile = file;
    } else {
      localFile = File(task.sourcePath);
    }

    if (!await localFile.exists()) {
      throw StateError(
        appL10n.transferServiceLocalFileNotFound(task.sourcePath),
      );
    }

    // 上传文件
    var lastBytes = 0;
    var lastTime = DateTime.now();
    await fs.upload(
      localFile.path,
      nasPathDirname(task.targetPath),
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
      throw StateError(
        appL10n.transferServiceSourceConnectionUnavailable(task.sourceId),
      );
    }

    final fs = connection.adapter.fileSystem;

    // 确保目标目录存在
    final targetDir = Directory(p.dirname(task.targetPath));
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    // 下载到任务私有临时文件，校验完成后再以“不覆盖”方式发布成品。
    final stream = await fs.getFileStream(task.sourcePath);
    final file = File(_partialPath(task));
    final sink = file.openWrite(mode: FileMode.write);

    var downloaded = 0;
    task.transferredBytes = 0;
    var lastBytes = 0;
    var lastTime = DateTime.now();
    try {
      await for (final chunk in stream) {
        if (_isInterrupted(task)) throw const _TransferInterrupted();
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
    } finally {
      await sink.close();
    }

    task.speed = 0;
    await _verifyAndPublish(task, file);

    // 如果是照片，保存到相册
    if (task.mediaType == MediaType.photo &&
        (Platform.isIOS || Platform.isAndroid)) {
      final saved = await _savePhotoToGallery(task.targetPath);
      if (saved) {
        try {
          await File(task.targetPath).delete();
        } on Object catch (e, st) {
          // 相册已经保存成功，本地副本清理失败不应把任务反转成失败。
          AppError.ignore(e, st, '照片保存到相册后清理本地下载副本失败');
        }
      }
    }
  }

  /// 执行缓存
  Future<void> _executeCache(TransferTask task) async {
    final connection = _connections[task.sourceId];
    if (connection == null) {
      throw StateError(
        appL10n.transferServiceSourceConnectionUnavailable(task.sourceId),
      );
    }

    final fs = connection.adapter.fileSystem;

    // 确保缓存目录存在
    final cacheDir = Directory(p.dirname(task.targetPath));
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }

    // 下载到缓存
    final stream = await fs.getFileStream(task.sourcePath);
    final file = File(_partialPath(task));
    final sink = file.openWrite(mode: FileMode.write);

    var downloaded = 0;
    task.transferredBytes = 0;
    var lastBytes = 0;
    var lastTime = DateTime.now();
    try {
      await for (final chunk in stream) {
        if (_isInterrupted(task)) throw const _TransferInterrupted();
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
    } finally {
      await sink.close();
    }

    task.speed = 0;
    await _verifyAndPublish(task, file);
  }

  Future<void> _verifyAndPublish(TransferTask task, File partialFile) async {
    final actualLength = await partialFile.length();
    if (task.fileSize > 0 && actualLength != task.fileSize) {
      throw StateError(
        'Transfer length mismatch: $actualLength/${task.fileSize} bytes',
      );
    }

    final target = File(task.targetPath);
    var createdTarget = false;
    RandomAccessFile? output;
    try {
      await target.create(exclusive: true);
      createdTarget = true;
      output = await target.open(mode: FileMode.writeOnly);
      await for (final chunk in partialFile.openRead()) {
        await output.writeFrom(chunk);
      }
      await output.flush();
      await output.close();
      output = null;
      if (await target.length() != actualLength) {
        throw StateError('Published transfer length mismatch');
      }
      if (_isInterrupted(task)) throw const _TransferInterrupted();
      await partialFile.delete();
    } on Object catch (e, st) {
      if (e is _TransferInterrupted) {
        AppError.ignore(e, st, '传输在发布成品期间被用户暂停或取消');
      } else {
        AppError.handle(e, st, 'TransferService.publishCompletedFile', {
          'targetPath': task.targetPath,
        });
      }
      try {
        await output?.close();
        if (createdTarget && await target.exists()) await target.delete();
      } on Object catch (cleanupError, cleanupStack) {
        AppError.ignore(cleanupError, cleanupStack, '传输成品发布失败后清理不完整目标文件失败');
      }
      rethrow;
    }
  }

  /// 保存照片到相册
  Future<bool> _savePhotoToGallery(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return false;

      final bytes = await file.readAsBytes();
      await pm.PhotoManager.editor.saveImage(
        bytes,
        filename: p.basename(filePath),
      );

      logger.i('TransferService: 照片已保存到相册 $filePath');
      return true;
    } on Object catch (e, st) {
      AppError.handle(e, st, 'TransferService._savePhotoToGallery');
      return false;
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
    // 服务销毁属于进程/Provider 生命周期结束，不等同于用户取消。持久化为
    // paused 可在下次启动恢复，并让正在运行的流尽快退出。
    final resumable = _tasks.where((task) => task.canCancel).toList();
    for (final task in resumable) {
      task.status = TransferStatus.paused;
      await _db.updateTask(task);
    }
    await Future.wait(_activeRuns.values.map((run) => run.future));
    await _taskController.close();
    await _tasksController.close();
  }
}

/// 内部哨兵异常：传输循环检测到任务被用户暂停/取消时抛出，
/// 让 [_executeTask] 区分「用户中断」与「真实失败」。
class _TransferInterrupted implements Exception {
  const _TransferInterrupted();
}
