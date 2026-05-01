import 'dart:async';

import 'package:ftpconnect/ftpconnect.dart';
import 'package:my_nas/core/constants/app_constants.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/nas_adapters/base/nas_adapter.dart';
import 'package:my_nas/nas_adapters/base/nas_connection.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/nas_adapters/ftp/ftp_file_system.dart';

/// FTP NAS 适配器
///
/// 基于 [ftpconnect] 包。FTP 是单向有状态协议，所有命令通过 [FtpFileSystem]
/// 内部的 Lock 串行化执行。
///
/// 实现限制：
/// - 不支持 2FA（FTP 协议本身不具备）
/// - 媒体服务 / 工具服务返回 null
/// - getStorageInfo 返回 null（FTP 没有标准存储信息查询命令）
/// - 流式读取走"先 downloadFile 到临时文件"的妥协，详见 [FtpFileSystem.getFileStream]
class FtpAdapter implements NasAdapter {
  FtpAdapter() {
    logger.i('FtpAdapter: 初始化适配器');
  }

  FTPConnect? _ftp;
  FtpFileSystem? _fileSystem;
  ConnectionConfig? _config;
  bool _connected = false;

  @override
  NasAdapterInfo get info => NasAdapterInfo(
        type: NasAdapterType.ftp,
        name: 'FTP',
        version: AppConstants.appVersion,
      );

  @override
  bool get isConnected => _connected;

  @override
  ConnectionConfig? get connection => _config;

  @override
  Future<ConnectionResult> connect(ConnectionConfig config) async {
    logger..i('FtpAdapter: 开始连接')
    ..i('FtpAdapter: 目标地址 => ${config.host}:${config.port}')
    ..i('FtpAdapter: 用户名 => ${config.username}');

    _config = config;

    try {
      _ftp = FTPConnect(
        config.host,
        port: config.port == 0 ? 21 : config.port,
        user: config.username.isEmpty ? 'anonymous' : config.username,
        pass: config.password,
        // 连接超时 30 秒
        timeout: 30,
      );

      final ok = await _ftp!.connect();
      if (!ok) {
        _connected = false;
        return const ConnectionFailure(error: 'FTP 连接失败：认证未通过或网络不可达');
      }

      _fileSystem = FtpFileSystem(ftp: _ftp!);
      _connected = true;

      logger.i('FtpAdapter: 连接成功');

      return ConnectionSuccess(
        sessionId: 'ftp-${DateTime.now().millisecondsSinceEpoch}',
        serverInfo: ServerInfo(
          hostname: config.host,
          model: 'FTP Server',
        ),
      );
    } on Exception catch (e) {
      logger.e('FtpAdapter: 连接失败', e);
      _connected = false;
      return ConnectionFailure(error: e.toString());
    }
  }

  @override
  Future<void> disconnect() async {
    if (!_connected) return;
    try {
      await _fileSystem?.dispose();
      await _ftp?.disconnect();
    } on Exception catch (e) {
      logger.w('FtpAdapter: 断开时出错', e);
    }
    _ftp = null;
    _fileSystem = null;
    _connected = false;
    _config = null;
    logger.i('FtpAdapter: 已断开连接');
  }

  @override
  Future<bool> checkConnectionHealth() async {
    if (!_connected || _ftp == null) {
      return false;
    }
    try {
      // 用 currentDirectory 作为最轻的探活命令
      await _ftp!.currentDirectory();
      return true;
    } on Exception catch (e) {
      logger.w('FtpAdapter: 连接健康检查失败', e);
      _connected = false;
      return false;
    }
  }

  @override
  NasFileSystem get fileSystem {
    if (!_connected || _fileSystem == null) {
      throw StateError('未连接到 FTP 服务器');
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
