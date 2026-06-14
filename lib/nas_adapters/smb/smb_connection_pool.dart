import 'dart:async';

import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:smb_connect/smb_connect.dart';

/// 心跳配置
class HeartbeatConfig {
  const HeartbeatConfig({
    this.enabled = true,
    this.interval = const Duration(seconds: 30), // 更频繁的心跳，防止连接超时
    this.timeout = const Duration(seconds: 10),
  });

  /// 是否启用心跳
  final bool enabled;

  /// 心跳间隔（默认 30 秒，确保连接保持活跃）
  final Duration interval;

  /// 心跳超时时间
  final Duration timeout;
}

/// 专用连接（带心跳支持）
///
/// 用于流传输等长时间操作，内置心跳保活机制
class DedicatedConnection {
  DedicatedConnection._({
    required this.client,
    required this.heartbeatConfig,
    required Future<void> Function() onRelease,
    void Function()? onDisconnect,
  })  : _onRelease = onRelease,
        _onDisconnect = onDisconnect;

  final SmbConnect client;
  final HeartbeatConfig heartbeatConfig;
  final Future<void> Function() _onRelease;
  final void Function()? _onDisconnect;

  Timer? _heartbeatTimer;
  bool _closed = false;
  bool _heartbeatInProgress = false;

  /// 连接是否已关闭
  bool get isClosed => _closed;

  /// 启动心跳（在连接空闲时调用，如视频暂停）
  void startHeartbeat() {
    if (_closed || !heartbeatConfig.enabled) return;
    stopHeartbeat(); // 确保没有重复的定时器

    _heartbeatTimer = Timer.periodic(heartbeatConfig.interval, (_) async {
      if (_closed || _heartbeatInProgress) return;
      _heartbeatInProgress = true;

      try {
        final isHealthy = await client.echo().timeout(
          heartbeatConfig.timeout,
          onTimeout: () => false,
        );

        if (!isHealthy && !_closed) {
          logger.w('SMB DedicatedConnection: 心跳检测失败，标记连接为已断开');
          _closed = true; // 标记为已关闭，防止继续使用
          stopHeartbeat();
          _onDisconnect?.call();
        }
      // ignore: avoid_catches_without_on_clauses
      } catch (e) {
        if (!_closed) {
          logger.w('SMB DedicatedConnection: 心跳异常 $e');
          _closed = true;
          stopHeartbeat();
          _onDisconnect?.call();
        }
      } finally {
        _heartbeatInProgress = false;
      }
    });
  }

  /// 停止心跳（在连接活跃时调用，如视频播放中）
  void stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// 关闭连接并释放资源
  Future<void> close() async {
    if (_closed) return;
    _closed = true;

    stopHeartbeat();

    try {
      await client.close();
    // ignore: avoid_catches_without_on_clauses
    } catch (e, st) {
      logger.w('SMB DedicatedConnection: 关闭连接失败', e, st);
    }

    await _onRelease();
  }
}

/// SMB 连接类型
enum SmbConnectionType {
  /// 通用操作（目录列表、文件信息等短操作）
  general,

  /// 流式传输（视频播放、文件下载等长操作）
  streaming,

  /// 后台任务（刮削、扫描等批量操作）
  background,
}

/// 连接池中的连接包装
class _PooledConnection {
  _PooledConnection({
    required this.client,
    required this.type,
  }) : createdAt = DateTime.now();

  final SmbConnect client;
  final SmbConnectionType type;
  final DateTime createdAt;

  bool _inUse = false;
  DateTime? _lastUsedAt;

  bool get inUse => _inUse;
  DateTime? get lastUsedAt => _lastUsedAt;

  /// 连接空闲时间
  Duration get idleTime =>
      DateTime.now().difference(_lastUsedAt ?? createdAt);

  /// 标记为使用中
  void acquire() {
    _inUse = true;
    _lastUsedAt = DateTime.now();
  }

  /// 释放连接
  void release() {
    _inUse = false;
    _lastUsedAt = DateTime.now();
  }

  /// 检查连接是否健康（使用 echo 命令）
  Future<bool> isHealthy({Duration timeout = const Duration(seconds: 10)}) async {
    try {
      return await client.echo().timeout(
        timeout,
        onTimeout: () => false,
      );
    // ignore: avoid_catches_without_on_clauses
    } catch (e, st) {
      logger.w('SMB 连接健康检查失败', e, st);
      return false;
    }
  }
}

/// SMB 连接池
///
/// 管理多个 SMB 连接，支持并发操作：
/// - 短操作（目录浏览）共享 general 连接
/// - 长操作（视频流）使用独占的 streaming 连接
/// - 后台任务（刮削）使用独立的 background 连接
class SmbConnectionPool {
  SmbConnectionPool({
    required this.host,
    required this.username,
    required this.password,
    this.domain = '',
    this.maxConnections = 5,
    this.maxDedicatedConnections = 8,
    this.maxIdleTime = const Duration(minutes: 5),
    this.heartbeatConfig = const HeartbeatConfig(),
  }) {
    _startHeartbeat();
  }

  final String host;
  final String username;
  final String password;
  final String domain;
  final int maxConnections;
  final int maxDedicatedConnections;
  final Duration maxIdleTime;
  final HeartbeatConfig heartbeatConfig;

  final List<_PooledConnection> _connections = [];
  final _lock = _AsyncLock();
  bool _disposed = false;
  Timer? _heartbeatTimer;

  /// 当前专用连接数
  int _dedicatedConnectionCount = 0;
  final _dedicatedLock = _AsyncLock();

  /// 当前连接数
  int get connectionCount => _connections.length;

  /// 活跃连接数
  int get activeConnectionCount => _connections.where((c) => c.inUse).length;

  /// 获取连接
  ///
  /// [type] 连接类型，用于区分不同用途的连接
  /// [exclusive] 是否需要独占连接（用于长操作）
  Future<SmbConnect> acquire({
    SmbConnectionType type = SmbConnectionType.general,
    bool exclusive = false,
  }) async {
    if (_disposed) {
      throw StateError('连接池已关闭');
    }

    // 先尝试在锁内快速获取或创建连接
    final result = await _lock.synchronized(() async {
      // 1. 尝试复用现有空闲连接（非独占模式）
      if (!exclusive) {
        final idle = _connections.where(
          (c) => !c.inUse && c.type == type,
        ).toList();

        for (final conn in idle) {
          // 检查连接是否过期
          if (conn.idleTime > maxIdleTime) {
            await _removeConnection(conn);
            continue;
          }

          conn.acquire();
          // logger.d('SMB Pool: 复用 $type 连接 (活跃: $activeConnectionCount/$connectionCount)');
          return conn.client;
        }
      }

      // 2. 创建新连接（如果未达上限）
      if (_connections.length < maxConnections) {
        final newConn = await _createConnection(type);
        newConn.acquire();
        logger.i('SMB Pool: 创建新 $type 连接 (活跃: $activeConnectionCount/$connectionCount)');
        return newConn.client;
      }

      // 返回 null 表示需要等待
      return null;
    });

    if (result != null) {
      return result;
    }

    // 3. 等待空闲连接（在锁外执行，避免死锁）
    logger.d('SMB Pool: 等待空闲连接...');
    return _waitForConnection(type, exclusive);
  }

  /// 释放连接
  void release(SmbConnect client) {
    final conn = _connections.cast<_PooledConnection?>().firstWhere(
          (c) => c?.client == client,
          orElse: () => null,
        );
    if (conn != null) {
      conn.release();
    } else {
      // 连接可能已被心跳检查移除，静默处理
      logger.d('SMB Pool: 释放连接时未找到匹配项（可能已被心跳清理）');
    }
  }

  /// 使用连接执行操作
  ///
  /// 自动获取和释放连接，确保连接正确归还
  Future<T> withConnection<T>(
    Future<T> Function(SmbConnect client) operation, {
    SmbConnectionType type = SmbConnectionType.general,
    bool exclusive = false,
  }) async {
    final client = await acquire(type: type, exclusive: exclusive);
    try {
      return await operation(client);
    } finally {
      release(client);
    }
  }

  /// 创建新连接
  Future<_PooledConnection> _createConnection(SmbConnectionType type) async {
    final client = await SmbConnect.connectAuth(
      host: host,
      domain: domain,
      username: username,
      password: password,
    ).timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw TimeoutException('SMB 连接超时'),
    );

    final conn = _PooledConnection(client: client, type: type);
    _connections.add(conn);
    return conn;
  }

  /// 移除连接
  Future<void> _removeConnection(_PooledConnection conn) async {
    _connections.remove(conn);
    try {
      await conn.client.close();
    // ignore: avoid_catches_without_on_clauses
    } catch (e, st) {
      logger.w('SMB Pool: 关闭连接失败', e, st);
    }
  }

  /// 等待空闲连接
  ///
  /// 注意：此方法应在 _lock 外部调用
  Future<SmbConnect> _waitForConnection(
    SmbConnectionType type,
    bool exclusive,
  ) async {
    const maxWait = Duration(seconds: 30);
    const checkInterval = Duration(milliseconds: 100);
    final deadline = DateTime.now().add(maxWait);

    while (DateTime.now().isBefore(deadline)) {
      // 在锁内检查并获取连接，避免竞态条件
      final client = await _lock.synchronized(() async {
        final idle = _connections.where((c) => !c.inUse).toList();
        if (idle.isNotEmpty) {
          final conn = idle.first..acquire();
          return conn.client;
        }
        return null;
      });

      if (client != null) {
        return client;
      }

      await Future<void>.delayed(checkInterval);
    }

    throw TimeoutException('等待 SMB 连接超时');
  }

  /// 清理空闲连接
  Future<void> cleanup() async {
    await _lock.synchronized(() async {
      final toRemove = _connections.where(
        (c) => !c.inUse && c.idleTime > maxIdleTime,
      ).toList();

      for (final conn in toRemove) {
        await _removeConnection(conn);
      }

      if (toRemove.isNotEmpty) {
        logger.i('SMB Pool: 清理了 ${toRemove.length} 个空闲连接');
      }
    });
  }

  /// 启动心跳定时器
  void _startHeartbeat() {
    if (!heartbeatConfig.enabled) return;

    _heartbeatTimer = Timer.periodic(heartbeatConfig.interval, (_) {
      _performHeartbeat();
    });
  }

  /// 停止心跳定时器
  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  bool _heartbeatInProgress = false;

  /// 执行心跳检查
  Future<void> _performHeartbeat() async {
    if (_disposed || _heartbeatInProgress) return;
    _heartbeatInProgress = true;

    try {
      // 1. 在锁内快速获取需要检查的连接列表
      final connectionsToCheck = await _lock.synchronized(() async {
        final idleConnections = _connections.where((c) => !c.inUse).toList();

        // 分离过期连接和需要心跳检查的连接
        final expiredConnections = idleConnections
            .where((c) => c.idleTime > maxIdleTime)
            .toList();
        final toCheck = idleConnections
            .where((c) => c.idleTime <= maxIdleTime)
            .toList();

        // 立即移除过期连接
        for (final conn in expiredConnections) {
          logger.d('SMB Pool: 移除过期连接 (空闲 ${conn.idleTime.inMinutes} 分钟)');
          await _removeConnection(conn);
        }

        return toCheck;
      });

      // 2. 在锁外并发执行心跳检查（不阻塞其他操作）
      final deadConnections = <_PooledConnection>[];

      await Future.wait(
        connectionsToCheck.map((conn) async {
          // 再次检查是否被使用（可能在等待期间被获取）
          if (conn.inUse) return;

          final isHealthy = await conn.isHealthy(
            timeout: heartbeatConfig.timeout,
          );

          if (!isHealthy) {
            deadConnections.add(conn);
          }
        }),
      );

      // 3. 在锁内移除死连接
      if (deadConnections.isNotEmpty) {
        await _lock.synchronized(() async {
          for (final conn in deadConnections) {
            // 再次检查是否仍在连接池中且未被使用
            if (_connections.contains(conn) && !conn.inUse) {
              logger.w('SMB Pool: 心跳检测失败，移除死连接');
              await _removeConnection(conn);
            }
          }
        });
      }
    } finally {
      _heartbeatInProgress = false;
    }
  }

  /// 获取一个专用连接（不放入池中，调用者负责关闭）
  ///
  /// 用于长时间运行的独占操作（如视频流传输）
  /// 会等待直到有可用的连接槽位
  ///
  /// 返回值包含连接和释放回调，调用者必须在完成后调用 releaseCallback
  @Deprecated('使用 createDedicatedConnectionWithHeartbeat 代替，支持心跳保活')
  Future<({SmbConnect client, Future<void> Function() releaseCallback})>
      createDedicatedConnection() async {
    // 等待连接槽位
    await _waitForDedicatedSlot();

    try {
      final client = await SmbConnect.connectAuth(
        host: host,
        domain: domain,
        username: username,
        password: password,
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw TimeoutException('SMB 专用连接超时 (30s)'),
      );

      return (client: client, releaseCallback: _releaseDedicatedSlot);
    // ignore: avoid_catches_without_on_clauses
    } catch (e, st) {
      // 创建失败，释放槽位并上报错误
      await _releaseDedicatedSlot();
      AppError.handle(e, st, 'SmbPool.createDedicatedConnection', {
        'host': host,
        'currentCount': _dedicatedConnectionCount,
        'maxCount': maxDedicatedConnections,
      });
      rethrow;
    }
  }

  /// 获取一个带心跳支持的专用连接
  ///
  /// 用于流传输等长时间操作（如视频播放）
  /// 内置心跳保活机制，防止连接因缓冲导致的空闲超时
  ///
  /// [onDisconnect] 当心跳检测到连接断开时的回调
  ///
  /// 使用示例：
  /// ```dart
  /// final conn = await pool.createDedicatedConnectionWithHeartbeat(
  ///   onDisconnect: () => print('连接断开'),
  /// );
  ///
  /// // 开始播放视频时，停止心跳（数据传输中不需要）
  /// conn.stopHeartbeat();
  ///
  /// // 视频暂停时，启动心跳保活
  /// conn.startHeartbeat();
  ///
  /// // 完成后关闭连接
  /// await conn.close();
  /// ```
  Future<DedicatedConnection> createDedicatedConnectionWithHeartbeat({
    void Function()? onDisconnect,
  }) async {
    // 等待连接槽位
    await _waitForDedicatedSlot();

    try {
      final client = await SmbConnect.connectAuth(
        host: host,
        domain: domain,
        username: username,
        password: password,
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw TimeoutException('SMB 专用连接超时 (30s)'),
      );

      final connection = DedicatedConnection._(
        client: client,
        heartbeatConfig: heartbeatConfig,
        onRelease: _releaseDedicatedSlot,
        onDisconnect: onDisconnect,
      )
        // 默认启动心跳（连接刚建立时处于空闲状态）
        ..startHeartbeat();

      return connection;
    // ignore: avoid_catches_without_on_clauses
    } catch (e, st) {
      // 创建失败，释放槽位并上报错误
      await _releaseDedicatedSlot();
      AppError.handle(e, st, 'SmbPool.createDedicatedConnectionWithHeartbeat', {
        'host': host,
        'currentCount': _dedicatedConnectionCount,
        'maxCount': maxDedicatedConnections,
      });
      rethrow;
    }
  }

  /// 等待专用连接槽位
  Future<void> _waitForDedicatedSlot() async {
    const maxWait = Duration(seconds: 60);
    const checkInterval = Duration(milliseconds: 100);
    final deadline = DateTime.now().add(maxWait);

    while (DateTime.now().isBefore(deadline)) {
      final acquired = await _dedicatedLock.synchronized(() async {
        if (_dedicatedConnectionCount < maxDedicatedConnections) {
          _dedicatedConnectionCount++;
          return true;
        }
        return false;
      });

      if (acquired) return;
      await Future<void>.delayed(checkInterval);
    }

    throw TimeoutException('等待专用连接槽位超时 ($_dedicatedConnectionCount/$maxDedicatedConnections)');
  }

  /// 释放专用连接槽位
  Future<void> _releaseDedicatedSlot() => _dedicatedLock.synchronized(() async {
      _dedicatedConnectionCount--;
      logger.d('SMB Pool: 释放专用连接槽位 ($_dedicatedConnectionCount/$maxDedicatedConnections)');
    });

  /// 关闭连接池
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    // 停止心跳定时器
    _stopHeartbeat();

    await _lock.synchronized(() async {
      for (final conn in _connections) {
        try {
          await conn.client.close();
        // ignore: avoid_catches_without_on_clauses
        } catch (e, st) {
          AppError.ignore(e, st, 'SMB Pool: 关闭连接失败');
        }
      }
      _connections.clear();
    });

    logger.i('SMB Pool: 连接池已关闭');
  }
}

/// 异步互斥锁
///
/// 使用链式排队保证互斥性：每个 synchronized 调用都等待前一个完成后再执行。
/// 解决了原实现中多个协程可能同时通过 while 检查进入临界区的竞态条件。
class _AsyncLock {
  Future<void> _chain = Future.value();

  Future<T> synchronized<T>(Future<T> Function() action) {
    final prev = _chain;
    final completer = Completer<void>();
    _chain = completer.future;
    return prev.then((_) => action()).whenComplete(completer.complete);
  }
}
