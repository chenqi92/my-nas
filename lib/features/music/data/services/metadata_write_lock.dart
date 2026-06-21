import 'dart:async';
import 'package:my_nas/core/i18n/app_l10n.dart';

/// 元数据写入锁管理器
///
/// 防止同一文件被并发写入导致的数据损坏
/// 使用路径作为锁的 key
class MetadataWriteLock {
  factory MetadataWriteLock() => _instance;
  MetadataWriteLock._();

  static final MetadataWriteLock _instance = MetadataWriteLock._();

  /// 正在写入的文件路径 -> Completer
  final Map<String, Completer<void>> _locks = {};

  /// 等待队列数量
  final Map<String, int> _waitingCount = {};

  /// 获取锁并执行操作
  ///
  /// [filePath] 文件路径（作为锁的 key）
  /// [action] 要执行的操作
  /// [timeout] 等待锁的超时时间，默认 30 秒
  ///
  /// 如果超时，将抛出 [TimeoutException]
  Future<T> withLock<T>(
    String filePath,
    Future<T> Function() action, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final normalizedPath = _normalizePath(filePath);

    // 等待获取锁
    await _acquireLock(normalizedPath, timeout);

    try {
      return await action();
    } finally {
      _releaseLock(normalizedPath);
    }
  }

  /// 尝试获取锁（非阻塞）
  ///
  /// 返回是否成功获取锁
  /// 如果返回 true，调用者必须在完成后调用 [releaseLock]
  bool tryAcquireLock(String filePath) {
    final normalizedPath = _normalizePath(filePath);

    if (_locks.containsKey(normalizedPath)) {
      return false;
    }

    _locks[normalizedPath] = Completer<void>();
    return true;
  }

  /// 释放锁（配合 tryAcquireLock 使用）
  void releaseLock(String filePath) {
    final normalizedPath = _normalizePath(filePath);
    _releaseLock(normalizedPath);
  }

  /// 检查文件是否被锁定
  bool isLocked(String filePath) {
    final normalizedPath = _normalizePath(filePath);
    return _locks.containsKey(normalizedPath);
  }

  /// 获取等待该文件锁的数量
  int getWaitingCount(String filePath) {
    final normalizedPath = _normalizePath(filePath);
    return _waitingCount[normalizedPath] ?? 0;
  }

  /// 内部：获取锁
  Future<void> _acquireLock(String path, Duration timeout) async {
    // 如果没有锁，直接创建
    if (!_locks.containsKey(path)) {
      _locks[path] = Completer<void>();
      return;
    }

    // 已有锁，等待释放
    _waitingCount[path] = (_waitingCount[path] ?? 0) + 1;

    try {
      final existingLock = _locks[path]!;

      // 等待现有锁释放
      await existingLock.future.timeout(
        timeout,
        onTimeout: () {
          throw TimeoutException(appL10n.metadataWriteLockTimeoutError(path), timeout);
        },
      );

      // 递归等待，因为可能有其他等待者先获取了锁
      await _acquireLock(path, timeout);
    } finally {
      _waitingCount[path] = (_waitingCount[path] ?? 1) - 1;
      if (_waitingCount[path] == 0) {
        _waitingCount.remove(path);
      }
    }
  }

  /// 内部：释放锁
  void _releaseLock(String path) {
    final completer = _locks.remove(path);
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  /// 标准化路径（统一分隔符，转小写）
  String _normalizePath(String path) =>
      path.replaceAll(r'\', '/').toLowerCase();

  /// 清除所有锁（仅用于测试）
  void clearAllLocks() {
    for (final completer in _locks.values) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
    _locks.clear();
    _waitingCount.clear();
  }
}

/// 全局锁实例
final metadataWriteLock = MetadataWriteLock();
