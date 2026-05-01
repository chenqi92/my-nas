import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:my_nas/core/constants/app_constants.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_adapter.dart';
import 'package:my_nas/nas_adapters/base/nas_connection.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/nas_adapters/sftp/sftp_file_system.dart';

/// SFTP NAS 适配器
///
/// 基于 [dartssh2] 的 SSHClient + SftpClient。SFTP 是 SSH 的子协议，
/// 文件操作通过 SSH 加密通道传输——比 FTP 安全且支持流式 I/O。
///
/// 实现限制：
/// - 仅支持密码认证（password-based）；公钥认证留作后续扩展
/// - 媒体服务 / 工具服务返回 null
/// - getStorageInfo 返回 null（SFTP 没有标准存储信息查询命令）
/// - 不支持 2FA
class SftpAdapter implements NasAdapter {
  SftpAdapter() {
    logger.i('SftpAdapter: 初始化适配器');
  }

  SSHSocket? _socket;
  SSHClient? _client;
  SftpFileSystem? _fileSystem;
  ConnectionConfig? _config;
  bool _connected = false;

  @override
  NasAdapterInfo get info => NasAdapterInfo(
        type: NasAdapterType.sftp,
        name: 'SFTP',
        version: AppConstants.appVersion,
      );

  @override
  bool get isConnected => _connected;

  @override
  ConnectionConfig? get connection => _config;

  @override
  Future<ConnectionResult> connect(ConnectionConfig config) async {
    logger..i('SftpAdapter: 开始连接')
    ..i('SftpAdapter: 目标地址 => ${config.host}:${config.port}')
    ..i('SftpAdapter: 用户名 => ${config.username}');

    _config = config;

    try {
      _socket = await SSHSocket.connect(
        config.host,
        config.port == 0 ? 22 : config.port,
        timeout: const Duration(seconds: 30),
      );

      _client = SSHClient(
        _socket!,
        username: config.username,
        onPasswordRequest: () => config.password,
      );

      // 等待认证完成 / 检测密码错误
      await _client!.authenticated;

      final sftp = await _client!.sftp();
      _fileSystem = SftpFileSystem(sftp: sftp);
      _connected = true;

      logger.i('SftpAdapter: 连接成功');

      return ConnectionSuccess(
        sessionId: 'sftp-${DateTime.now().millisecondsSinceEpoch}',
        serverInfo: ServerInfo(
          hostname: config.host,
          model: 'SFTP / SSH Server',
        ),
      );
    } on Exception catch (e) {
      logger.e('SftpAdapter: 连接失败', e);
      _connected = false;
      // 清理已建立的连接
      await _cleanup();
      return ConnectionFailure(error: e.toString());
    }
  }

  Future<void> _cleanup() async {
    try {
      await _fileSystem?.dispose();
    } on Exception catch (e) {
      logger.w('SftpAdapter: dispose fileSystem 出错', e);
    }
    try {
      _client?.close();
    } on Exception catch (e) {
      logger.w('SftpAdapter: close client 出错', e);
    }
    try {
      // SSHSocket.close() 返回 Future
      await _socket?.close();
    } on Exception catch (e) {
      logger.w('SftpAdapter: close socket 出错', e);
    }
    _fileSystem = null;
    _client = null;
    _socket = null;
  }

  @override
  Future<void> disconnect() async {
    if (!_connected) return;
    await _cleanup();
    _connected = false;
    _config = null;
    logger.i('SftpAdapter: 已断开连接');
  }

  @override
  Future<bool> checkConnectionHealth() async {
    if (!_connected || _client == null || _fileSystem == null) {
      return false;
    }
    try {
      // listdir('/') 是最轻的探活——失败说明会话已挂
      await _fileSystem!.listDirectory('/').timeout(
            const Duration(seconds: 5),
            onTimeout: () => throw Exception('健康检查超时'),
          );
      return true;
    } on Exception catch (e) {
      logger.w('SftpAdapter: 连接健康检查失败', e);
      _connected = false;
      return false;
    }
  }

  @override
  NasFileSystem get fileSystem {
    if (!_connected || _fileSystem == null) {
      throw StateError('未连接到 SFTP 服务器');
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
