import 'dart:async';
import 'dart:collection';

import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/smb/smb_pool_config.dart';

/// 后台任务池
///
/// 用于限制后台任务的并发数量，防止同时执行过多任务导致：
/// - CPU 占用过高（手机发热）
/// - 内存占用过高
/// - 网络请求过多被限流
///
/// 支持性能模式：
/// - 普通模式：保守配置，适合后台运行
/// - 性能模式：激进配置，最大化利用硬件资源
///
/// 使用示例：
/// ```dart
/// final pool = BackgroundTaskPool.media; // 媒体处理任务池
/// await pool.add(() => downloadPoster(url));
/// ```
class BackgroundTaskPool {
  BackgroundTaskPool({
    required this.name,
    required int Function() concurrencyGetter,
  }) : _concurrencyGetter = concurrencyGetter;

  /// 媒体处理任务池（海报下载、缩略图生成等）
  ///
  /// 使用 SmbPoolConfig 根据平台和性能模式动态配置
  static final media = BackgroundTaskPool(
    name: 'media',
    concurrencyGetter: () => SmbPoolConfig.maxBackgroundTasks,
  );

  /// 网络请求任务池（API 调用等）
  ///
  /// 网络请求可以比后台任务多一些并发
  /// 性能模式下翻倍
  static final network = BackgroundTaskPool(
    name: 'network',
    concurrencyGetter: () {
      final base = SmbPoolConfig.isDesktop ? 8 : 4;
      return SmbPoolConfig.isPerformanceMode ? base * 2 : base;
    },
  );

  /// 刮削任务池
  ///
  /// 使用 SmbPoolConfig 根据平台和性能模式动态配置
  static final scrape = BackgroundTaskPool(
    name: 'scrape',
    concurrencyGetter: () => SmbPoolConfig.maxBackgroundTasks,
  );

  final String name;
  final int Function() _concurrencyGetter;

  /// 获取当前最大并发数（动态计算，支持性能模式切换）
  int get maxConcurrency => _concurrencyGetter();

  final _queue = Queue<_QueuedTask<dynamic>>();
  int _running = 0;
  bool _disposed = false;

  /// 当前正在运行的任务数
  int get runningCount => _running;

  /// 队列中等待的任务数
  int get queuedCount => _queue.length;

  /// 是否已满（达到最大并发）
  bool get isFull => _running >= maxConcurrency;

  /// 添加任务到池中
  ///
  /// 如果当前运行的任务数小于 maxConcurrency，立即执行
  /// 否则加入队列等待
  ///
  /// 返回任务完成的 Future
  Future<T> add<T>(Future<T> Function() task, {String? taskName}) async {
    if (_disposed) {
      throw StateError(appL10n.backgroundTaskPoolDisposed(name));
    }

    final completer = Completer<T>();
    final queuedTask = _QueuedTask<T>(
      task: task,
      completer: completer,
      name: taskName,
    );

    final currentMax = maxConcurrency;
    if (_running < currentMax) {
      // 首次添加任务时打印当前并发配置（每 10 个任务打印一次）
      if (_running == 0 || (_running + _queue.length) % 10 == 0) {
        logger.d(
          'BackgroundTaskPool[$name]: maxConcurrency=$currentMax, '
          'running=$_running, queued=${_queue.length}',
        );
      }
      // ignore: unawaited_futures - 故意不等待，由 completer 处理结果
      _executeTask(queuedTask);
    } else {
      _queue.add(queuedTask);
      // 队列满时打印警告
      if (_queue.length == 1) {
        logger.d(
          'BackgroundTaskPool[$name]: 达到并发上限 $currentMax，任务入队',
        );
      }
    }

    return completer.future;
  }

  /// 添加任务但不等待结果（fire and forget）
  ///
  /// 任务仍然受并发限制，但调用者不需要等待完成
  void addFireAndForget(Future<void> Function() task, {String? taskName}) {
    add(task, taskName: taskName).catchError((Object e) {
      // 错误已在 _executeTask 中处理，这里只是防止 unhandled exception
    });
  }

  Future<void> _executeTask<T>(_QueuedTask<T> queuedTask) async {
    _running++;

    try {
      final result = await queuedTask.task();
      queuedTask.completer.complete(result);
    } catch (e, st) {
      queuedTask.completer.completeError(e, st);
      logger.w(
        'BackgroundTaskPool[$name]: 任务失败 ${queuedTask.name ?? ""}',
        e,
      );
    } finally {
      _running--;
      _processQueue();
    }
  }

  void _processQueue() {
    if (_disposed) return;

    while (_running < maxConcurrency && _queue.isNotEmpty) {
      final task = _queue.removeFirst();
      _executeTask(task);
    }
  }

  /// 等待所有当前任务完成
  ///
  /// 注意：这不会阻止新任务的添加
  Future<void> drain() async {
    while (_running > 0 || _queue.isNotEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  /// 清空队列中等待的任务
  ///
  /// 正在运行的任务不受影响
  void clearQueue() {
    for (final task in _queue) {
      task.completer.completeError(
        StateError(appL10n.backgroundTaskPoolQueuedTaskCancelled),
      );
    }
    _queue.clear();
    logger.i('BackgroundTaskPool[$name]: 队列已清空');
  }

  /// 释放资源
  void dispose() {
    _disposed = true;
    clearQueue();
  }

  /// 获取状态信息（用于调试）
  Map<String, dynamic> get status => {
        'name': name,
        'maxConcurrency': maxConcurrency,
        'running': _running,
        'queued': _queue.length,
        'disposed': _disposed,
      };
}

class _QueuedTask<T> {
  _QueuedTask({
    required this.task,
    required this.completer,
    this.name,
  });

  final Future<T> Function() task;
  final Completer<T> completer;
  final String? name;
}
