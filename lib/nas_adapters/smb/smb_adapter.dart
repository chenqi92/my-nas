import 'dart:io';

import 'package:my_nas/core/constants/app_constants.dart';
import 'package:my_nas/core/errors/errors.dart' hide ConnectionFailure;
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_adapter.dart';
import 'package:my_nas/nas_adapters/base/nas_connection.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/nas_adapters/smb/smb_connection_pool.dart';
import 'package:my_nas/nas_adapters/smb/smb_file_system.dart';
import 'package:my_nas/nas_adapters/smb/smb_pool_config.dart';

/// SMB/CIFS NAS 适配器
///
/// 使用 smb_connect 库实现 SMB 协议连接
/// 支持 SMB 1.0, CIFS, SMB 2.x, SMB 3.x (包括 3.1.1)
///
/// 特性：
/// - 连接池管理：支持多连接并发，避免操作争用
/// - 自动重连：连接断开时自动重新建立
/// - 任务隔离：视频播放使用独立连接，不影响其他操作
class SmbAdapter implements NasAdapter {
  SmbAdapter() {
    logger.i('SmbAdapter: 初始化适配器');
  }

  SmbConnectionPool? _connectionPool;
  SmbFileSystem? _fileSystem;
  ConnectionConfig? _config;
  bool _connected = false;

  @override
  NasAdapterInfo get info => NasAdapterInfo(
        type: NasAdapterType.smb,
        name: 'SMB/CIFS',
        version: AppConstants.appVersion,
      );

  @override
  bool get isConnected => _connected;

  @override
  ConnectionConfig? get connection => _config;

  @override
  Future<ConnectionResult> connect(ConnectionConfig config) async {
    logger
      ..i('SmbAdapter: 开始连接')
      ..i('SmbAdapter: 目标地址 => ${config.host}:${config.port}')
      ..i('SmbAdapter: 用户名 => ${config.username}');

    _config = config;

    // 清理主机地址
    final host = _cleanupHost(config.host);
    logger.i('SmbAdapter: 清理后的主机地址 => $host');

    // 预解析 DNS，解决 mDNS (.local) 首次解析慢的问题
    final resolvedHost = await _resolveDns(host);
    logger.i('SmbAdapter: 解析后的地址 => $resolvedHost');

    // 使用重试机制连接
    return _connectWithRetry(
      host: resolvedHost,
      originalHost: host,
      username: config.username,
      password: config.password,
      maxRetries: 2,
    );
  }

  /// 清理主机地址
  String _cleanupHost(String rawHost) {
    var host = rawHost.trim();

    // 移除协议前缀
    if (host.startsWith('http://')) {
      host = host.substring(7);
      logger.w('SmbAdapter: 移除 http:// 前缀');
    }
    if (host.startsWith('https://')) {
      host = host.substring(8);
      logger.w('SmbAdapter: 移除 https:// 前缀');
    }
    if (host.startsWith('smb://')) {
      host = host.substring(6);
      logger.w('SmbAdapter: 移除 smb:// 前缀');
    }

    // 移除尾部的斜杠和端口
    if (host.contains('/')) {
      host = host.split('/').first;
    }
    if (host.contains(':')) {
      host = host.split(':').first;
    }

    // 移除末尾的点（FQDN 格式可能导致 mDNS 解析问题）
    while (host.endsWith('.')) {
      host = host.substring(0, host.length - 1);
      logger.w('SmbAdapter: 移除末尾的点');
    }

    return host;
  }

  /// 预解析 DNS 地址
  ///
  /// 对于 .local 域名（mDNS），首次解析可能较慢，
  /// 预解析可以避免在 SMB 连接过程中超时
  Future<String> _resolveDns(String host) async {
    // 如果已经是 IP 地址，直接返回
    if (_isIpAddress(host)) {
      logger.d('SmbAdapter: 已经是 IP 地址，跳过 DNS 解析');
      return host;
    }

    try {
      logger.d('SmbAdapter: 开始 DNS 解析 $host');
      final stopwatch = Stopwatch()..start();

      final addresses = await InternetAddress.lookup(host).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          logger.w('SmbAdapter: DNS 解析超时，使用原始主机名');
          return <InternetAddress>[];
        },
      );

      stopwatch.stop();
      logger.d('SmbAdapter: DNS 解析耗时 ${stopwatch.elapsedMilliseconds}ms');

      if (addresses.isNotEmpty) {
        // 优先使用 IPv4 地址，因为某些网络环境 IPv6 不稳定
        final ipv4 = addresses
            .where((addr) => addr.type == InternetAddressType.IPv4)
            .firstOrNull;
        final selectedAddr = ipv4 ?? addresses.first;
        final ip = selectedAddr.address;
        logger.i(
          'SmbAdapter: DNS 解析成功 $host -> $ip '
          '(共 ${addresses.length} 个地址, IPv4: ${ipv4 != null})',
        );
        return ip;
      }
    } catch (e) {
      logger.w('SmbAdapter: DNS 解析失败，使用原始主机名', e);
    }

    return host;
  }

  /// 检查是否为 IP 地址
  bool _isIpAddress(String host) {
    // IPv4 检查
    final ipv4Regex = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
    if (ipv4Regex.hasMatch(host)) {
      return true;
    }

    // IPv6 检查（简单判断）
    if (host.contains(':') && !host.contains('.')) {
      return true;
    }

    return false;
  }

  /// 带重试的连接方法
  Future<ConnectionResult> _connectWithRetry({
    required String host,
    required String originalHost,
    required String username,
    required String password,
    required int maxRetries,
  }) async {
    dynamic lastError;
    StackTrace? lastStackTrace;

    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        logger
          ..d('SmbAdapter: 连接尝试 $attempt/$maxRetries')
          // 创建连接池（统一管理所有连接）
          ..i('SmbAdapter: ${SmbPoolConfig.summary}');
        _connectionPool = SmbConnectionPool(
          host: host,
          username: username,
          password: password,
          maxConnections: SmbPoolConfig.maxConnections,
          maxDedicatedConnections: SmbPoolConfig.maxDedicatedConnections,
          maxIdleTime: SmbPoolConfig.maxIdleTime,
        );

        // 通过连接池获取连接并测试
        final shares = await _connectionPool!.withConnection(
          (client) async {
            logger.d('SmbAdapter: SMB 连接已建立，正在获取共享列表...');
            return client.listShares();
          },
          type: SmbConnectionType.general,
        ).timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            throw Exception('SMB 连接超时 (30秒)');
          },
        );

        logger.i('SmbAdapter: 连接成功，发现 ${shares.length} 个共享');

        for (final share in shares) {
          logger.d('SmbAdapter: 共享 => ${share.name} (${share.path})');
        }

        _fileSystem = SmbFileSystem(
          connectionPool: _connectionPool!,
        );
        _connected = true;

        return ConnectionSuccess(
          sessionId: 'smb-${DateTime.now().millisecondsSinceEpoch}',
          serverInfo: ServerInfo(
            hostname: originalHost,
            model: 'SMB/CIFS Server',
          ),
        );
      } catch (e, stackTrace) {
        lastError = e;
        lastStackTrace = stackTrace;
        logger.w('SmbAdapter: 连接尝试 $attempt 失败: $e');

        // 清理失败的连接池
        try {
          await _connectionPool?.dispose();
        } catch (e, st) {
          AppError.ignore(e, st, '连接池清理失败（连接已失败的清理路径）');
        }
        _connectionPool = null;

        // 如果不是最后一次尝试，等待后重试
        if (attempt < maxRetries) {
          final delay = Duration(milliseconds: 500 * attempt);
          logger.d('SmbAdapter: ${delay.inMilliseconds}ms 后重试');
          await Future<void>.delayed(delay);
        }
      }
    }

    // 所有重试都失败
    logger.e('SmbAdapter: 连接失败，已重试 $maxRetries 次', lastError, lastStackTrace);
    _connected = false;
    return ConnectionFailure(error: _parseErrorAny(lastError));
  }

  // ignore: unused_element
  String _parseError(Exception e) => _parseErrorAny(e);

  String _parseErrorAny(dynamic e) {
    // 优先处理 SmbAuthException - 认证失败
    if (e.runtimeType.toString() == 'SmbAuthException') {
      return 'SMB 认证失败\n用户名或密码错误';
    }

    final msg = e.toString().toLowerCase();
    logger.d('SmbAdapter: 解析错误消息 => $msg');

    // SmbAuthException 的字符串匹配（备用）
    if (msg.contains('smbauthexception')) {
      return 'SMB 认证失败\n用户名或密码错误';
    }

    // 连接相关错误
    if (msg.contains('connection refused')) {
      return 'SMB 连接被拒绝\n请检查：\n• SMB 服务是否启用\n• 端口 445 是否开放\n• 防火墙设置';
    }
    if (msg.contains('timeout') || msg.contains('timed out')) {
      return 'SMB 连接超时\n请检查：\n• 服务器地址是否正确\n• 网络是否连通\n• 服务器是否在线';
    }
    if (msg.contains('host not found') ||
        msg.contains('no address') ||
        msg.contains('getaddrinfo') ||
        msg.contains('nodename nor servname')) {
      return 'SMB 服务器地址无法解析\n请检查：\n• 服务器地址是否正确\n• DNS 设置是否正确';
    }
    if (msg.contains('network is unreachable') ||
        msg.contains('no route to host')) {
      return 'SMB 网络不可达\n请检查：\n• 网络连接是否正常\n• 是否在同一网络';
    }
    // 连接已关闭错误 (StreamSink closed)
    if (msg.contains('streamsink is closed') ||
        msg.contains('stream is closed') ||
        msg.contains('connection closed') ||
        msg.contains('socket closed')) {
      return 'SMB 连接已断开\n请检查网络连接后重试';
    }

    // 认证相关错误
    if (msg.contains('status_logon_failure') ||
        msg.contains('logon failure') ||
        msg.contains('authentication failed')) {
      return 'SMB 认证失败\n用户名或密码错误';
    }
    if (msg.contains('status_access_denied') ||
        msg.contains('access denied') ||
        msg.contains('permission denied')) {
      return 'SMB 访问被拒绝\n请检查用户权限';
    }
    if (msg.contains('status_account_disabled')) {
      return 'SMB 账户已禁用\n请联系管理员启用账户';
    }
    if (msg.contains('status_account_locked')) {
      return 'SMB 账户已锁定\n请稍后重试或联系管理员';
    }
    if (msg.contains('status_password_expired')) {
      return 'SMB 密码已过期\n请更新密码后重试';
    }

    // SMB 协议错误
    if (msg.contains("can't connect")) {
      return 'SMB 无法连接到服务器\n请检查服务器地址和网络';
    }
    if (msg.contains('invalid parameter') ||
        msg.contains('bad network name') ||
        msg.contains('status_bad_network_name')) {
      return 'SMB 网络名称无效\n请检查共享名称是否正确';
    }
    if (msg.contains('not supported') || msg.contains('status_not_supported')) {
      return 'SMB 协议版本不兼容\n请检查服务器 SMB 协议设置';
    }

    // 默认错误消息
    final originalMsg = e.toString();
    if (originalMsg.length > 100) {
      return 'SMB 连接失败\n${originalMsg.substring(0, 100)}...';
    }
    return 'SMB 连接失败\n$originalMsg';
  }

  @override
  Future<void> disconnect() async {
    if (!_connected) return;

    try {
      // 关闭连接池（会关闭所有连接）
      await _connectionPool?.dispose();
    // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      logger.w('SmbAdapter: 断开连接时出错', e);
    }

    _connectionPool = null;
    _fileSystem = null;
    _connected = false;
    _config = null;
    logger.i('SmbAdapter: 已断开连接');
  }

  @override
  Future<bool> checkConnectionHealth() async {
    if (!_connected || _connectionPool == null) {
      logger.d('SmbAdapter: 连接健康检查 - 未连接');
      return false;
    }

    try {
      // 使用 echo 命令检查连接健康状态（比 listShares 更轻量）
      final isHealthy = await _connectionPool!.withConnection(
        (client) => client.echo(),
        type: SmbConnectionType.general,
      ).timeout(
        const Duration(seconds: 5),
        onTimeout: () => false,
      );

      if (isHealthy) {
        logger.d('SmbAdapter: 连接健康检查 - 正常');
        return true;
      } else {
        logger.w('SmbAdapter: 连接健康检查 - echo 失败');
        _connected = false;
        return false;
      }
    // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      logger.w('SmbAdapter: 连接健康检查 - 失败', e);
      // 标记连接已断开
      _connected = false;
      return false;
    }
  }

  @override
  NasFileSystem get fileSystem {
    if (!_connected || _fileSystem == null) {
      throw StateError('未连接到 SMB 服务器');
    }
    return _fileSystem!;
  }

  @override
  MediaService? get mediaService => null;

  @override
  ToolsService? get toolsService => null;

  @override
  Future<StorageInfo?> getStorageInfo() async => null;

  @override
  Future<void> dispose() async {
    await disconnect();
  }
}
