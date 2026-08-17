import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:my_nas/core/constants/app_constants.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/storage/secure_storage_options.dart';
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
/// - 支持密码和 PEM 私钥认证
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
  static final Map<String, String> _memoryHostKeyPins = {};

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
    logger
      ..i('SftpAdapter: 开始连接')
      ..i('SftpAdapter: 目标地址 => ${config.host}:${config.port}')
      ..i('SftpAdapter: 用户名 => ${config.username}');

    _config = config;

    try {
      _socket = await SSHSocket.connect(
        config.host,
        config.port == 0 ? 22 : config.port,
        timeout: const Duration(seconds: 30),
      );

      final authMethod = config.extraConfig?['authMethod']?.toString();
      final privateKey = config.extraConfig?['privateKey']?.toString();
      final passphrase = config.extraConfig?['privateKeyPassphrase']
          ?.toString();
      final usePrivateKey =
          authMethod == 'SSH 密钥' ||
          authMethod == 'key' ||
          (privateKey != null && privateKey.trim().isNotEmpty);
      final identities = usePrivateKey
          ? SSHKeyPair.fromPem(
              privateKey?.trim() ?? '',
              (passphrase?.isEmpty ?? false) ? null : passphrase,
            )
          : null;

      _client = SSHClient(
        _socket!,
        username: config.username,
        identities: identities,
        onPasswordRequest: usePrivateKey ? null : () => config.password,
        onVerifyHostKey: (type, fingerprint) => _verifyHostKey(
          config.host,
          config.port == 0 ? 22 : config.port,
          type,
          fingerprint,
        ),
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

  Future<bool> _verifyHostKey(
    String host,
    int port,
    String type,
    List<int> fingerprint,
  ) async {
    final normalizedHost = host.trim().toLowerCase();
    final storageKey = 'sftp_hostkey_v1.$normalizedHost:$port';
    final value =
        '$type:${fingerprint.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':')}';
    try {
      final pinned = await defaultSecureStorage.read(key: storageKey);
      if (pinned == null) {
        await writeSecureValueVerified(
          defaultSecureStorage,
          key: storageKey,
          value: value,
        );
        logger.i('SftpAdapter: 首次连接，已固定服务器主机密钥 $normalizedHost:$port');
        return true;
      }
      if (pinned != value) {
        logger.e('SftpAdapter: 服务器主机密钥发生变化，已阻止连接 $normalizedHost:$port');
        return false;
      }
      return true;
    } on Exception catch (e) {
      // 测试环境或系统安全存储不可用时，至少在当前进程内保持 TOFU 校验。
      logger.w('SftpAdapter: 无法持久化主机密钥，使用进程内固定', e);
      final pinned = _memoryHostKeyPins[storageKey];
      if (pinned == null) {
        _memoryHostKeyPins[storageKey] = value;
        return true;
      }
      return pinned == value;
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
      await _fileSystem!
          .listDirectory('/')
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () =>
                throw Exception(appL10n.sftpAdapterHealthCheckTimeoutError),
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
      throw StateError(appL10n.sftpAdapterNotConnectedError);
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
