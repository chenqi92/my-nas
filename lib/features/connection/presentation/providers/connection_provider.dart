import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/storage/auth_storage_service.dart';
import 'package:my_nas/core/storage/storage_service.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/connection/domain/entities/connection_entity.dart';
import 'package:my_nas/nas_adapters/base/nas_adapter.dart';
import 'package:my_nas/nas_adapters/base/nas_connection.dart';
import 'package:my_nas/nas_adapters/fnos/fnos_adapter.dart';
import 'package:my_nas/nas_adapters/ftp/ftp_adapter.dart';
import 'package:my_nas/nas_adapters/local/local_adapter.dart';
import 'package:my_nas/nas_adapters/qnap/qnap_adapter.dart';
import 'package:my_nas/nas_adapters/sftp/sftp_adapter.dart';
import 'package:my_nas/nas_adapters/smb/smb_adapter.dart';
import 'package:my_nas/nas_adapters/synology/synology_adapter.dart';
import 'package:my_nas/nas_adapters/ugreen/ugreen_adapter.dart';
import 'package:my_nas/nas_adapters/webdav/webdav_adapter.dart';

/// 当前活跃的 NAS 适配器
final activeAdapterProvider = StateProvider<NasAdapter?>((ref) => null);

/// 认证存储服务
final authStorageProvider = Provider<AuthStorageService>((ref) => AuthStorageService());

/// 当前连接状态
final connectionStateProvider =
    StateNotifierProvider<ConnectionStateNotifier, NasConnectionState>(ConnectionStateNotifier.new);

/// 保存的连接列表
final savedConnectionsProvider =
    StateNotifierProvider<SavedConnectionsNotifier, List<ConnectionEntity>>(
        (ref) => SavedConnectionsNotifier());

/// 连接状态
sealed class NasConnectionState {
  const NasConnectionState();
}

class ConnectionIdle extends NasConnectionState {
  const ConnectionIdle();
}

class ConnectionLoading extends NasConnectionState {
  const ConnectionLoading({this.message});
  final String? message;
}

class ConnectionConnected extends NasConnectionState {
  const ConnectionConnected({
    required this.adapter,
    this.serverInfo,
  });
  final NasAdapter adapter;
  final ServerInfo? serverInfo;
}

class ConnectionRequires2FAState extends NasConnectionState {
  const ConnectionRequires2FAState({
    required this.adapter,
    this.rememberDevice = false,
  });
  final NasAdapter adapter;
  final bool rememberDevice;
}

class ConnectionError extends NasConnectionState {
  const ConnectionError({required this.message});
  final String message;
}

/// 连接状态管理
class ConnectionStateNotifier extends StateNotifier<NasConnectionState> {
  ConnectionStateNotifier(this._ref) : super(const ConnectionIdle());

  final Ref _ref;

  // 当前连接的相关信息
  String? _currentConnectionId;
  bool _rememberLogin = false;
  bool _rememberDevice = false;

  Future<void> connect({
    required NasAdapterType type,
    required String host,
    required int port,
    required String username,
    required String password,
    bool useSsl = true,
    bool verifySSL = true,
    bool rememberLogin = false,
    bool rememberDevice = false,
    String? connectionId,
  }) async {
    state = const ConnectionLoading(message: '正在连接...');

    // 保存记住设置
    _rememberLogin = rememberLogin;
    _rememberDevice = rememberDevice;
    _currentConnectionId = connectionId ?? '${host}_${port}_$username';

    final authStorage = _ref.read(authStorageProvider);

    NasAdapter? adapter;
    try {
      adapter = _createAdapter(type);

      // 获取已保存的设备ID（用于跳过2FA）
      String? deviceId;
      if (rememberDevice) {
        deviceId = await authStorage.getDeviceId(_currentConnectionId!);
        logger.d('ConnectionStateNotifier: 已保存的设备ID => ${deviceId != null ? "有" : "无"}');
      }

      final config = ConnectionConfig(
        type: type,
        host: host,
        port: port,
        username: username,
        password: password,
        useSsl: useSsl,
        verifySSL: verifySSL,
        deviceId: deviceId,
        deviceName: rememberDevice ? authStorage.deviceName : null,
        enableDeviceToken: rememberDevice,
      );

      final result = await adapter.connect(config);

      state = switch (result) {
        ConnectionSuccess(:final serverInfo, :final deviceId) => () {
            _ref.read(activeAdapterProvider.notifier).state = adapter;

            // 保存凭证和设备ID
            _handleLoginSuccess(
              connectionId: _currentConnectionId!,
              username: username,
              password: password,
              deviceId: deviceId,
            );

            return ConnectionConnected(
              adapter: adapter!,
              serverInfo: serverInfo,
            );
          }(),
        ConnectionFailure(:final error) => () {
            adapter?.dispose();
            return ConnectionError(message: error);
          }(),
        ConnectionRequires2FA() => ConnectionRequires2FAState(
            adapter: adapter,
            rememberDevice: rememberDevice,
          ),
      };
    } on Exception catch (e, st) {
      await adapter?.dispose();
      AppError.handle(e, st, 'NasConnection.connect', {
        'host': host,
        'port': port,
        'type': type.name,
      });
      state = ConnectionError(message: '连接失败: ${_getErrorMessage(e)}');
    }
  }

  Future<void> _handleLoginSuccess({
    required String connectionId,
    required String username,
    required String password,
    String? deviceId,
  }) async {
    final authStorage = _ref.read(authStorageProvider);

    // 保存凭证
    if (_rememberLogin) {
      await authStorage.saveCredentials(
        connectionId: connectionId,
        username: username,
        password: password,
      );
      await authStorage.setRememberLogin(value: true);
    }

    // 保存设备ID
    if (_rememberDevice && deviceId != null) {
      await authStorage.saveDeviceId(connectionId, deviceId);
      await authStorage.setRememberDevice(value: true);
    }
  }

  String _getErrorMessage(Object e) {
    final message = e.toString();
    if (message.contains('Operation not permitted')) {
      return '网络权限被拒绝，请检查系统设置';
    }
    if (message.contains('Connection refused')) {
      return '连接被拒绝，请检查地址和端口';
    }
    if (message.contains('Connection timed out')) {
      return '连接超时，请检查网络';
    }
    if (message.contains('SocketException')) {
      return '网络连接失败';
    }
    // Keychain 权限错误
    if (message.contains('-34018') || message.contains('entitlement')) {
      return '安全存储不可用，无法保存登录信息';
    }
    return message;
  }

  Future<void> verify2FA(String otpCode, {bool? rememberDevice}) async {
    final currentState = state;
    if (currentState is! ConnectionRequires2FAState) return;

    state = const ConnectionLoading(message: '正在验证...');

    // 使用传入的 rememberDevice 或者之前保存的设置
    final shouldRememberDevice = rememberDevice ?? _rememberDevice;
    final authStorage = _ref.read(authStorageProvider);

    final adapter = currentState.adapter;
    if (adapter is SynologyAdapter) {
      final result = await adapter.verify2FA(
        otpCode,
        rememberDevice: shouldRememberDevice,
        deviceName: shouldRememberDevice ? authStorage.deviceName : null,
      );

      state = switch (result) {
        ConnectionSuccess(:final serverInfo, :final deviceId) => () {
            _ref.read(activeAdapterProvider.notifier).state = adapter;

            // 保存设备ID（二次验证成功后）
            if (shouldRememberDevice &&
                deviceId != null &&
                _currentConnectionId != null) {
              authStorage..saveDeviceId(_currentConnectionId!, deviceId)
              ..setRememberDevice(value: true);
            }

            // 如果记住登录，也需要在 2FA 成功后保存凭证
            if (_rememberLogin && adapter.connection != null) {
              authStorage..saveCredentials(
                connectionId: _currentConnectionId!,
                username: adapter.connection!.username,
                password: adapter.connection!.password,
              )
              ..setRememberLogin(value: true);
            }

            return ConnectionConnected(
              adapter: adapter,
              serverInfo: serverInfo,
            );
          }(),
        ConnectionFailure(:final error) => ConnectionError(message: error),
        ConnectionRequires2FA() =>
          const ConnectionError(message: '二次验证失败'),
      };
    }
  }

  Future<void> disconnect() async {
    final adapter = _ref.read(activeAdapterProvider);
    if (adapter != null) {
      await adapter.disconnect();
      await adapter.dispose();
      _ref.read(activeAdapterProvider.notifier).state = null;
    }
    state = const ConnectionIdle();
  }

  /// 尝试自动登录
  ///
  /// 如果有保存的凭证且启用了记住登录，则自动进行登录
  Future<bool> tryAutoLogin() async {
    final authStorage = _ref.read(authStorageProvider);

    // 检查是否启用了记住登录
    final rememberLogin = await authStorage.getRememberLogin();
    if (!rememberLogin) {
      logger.d('ConnectionStateNotifier: 未启用记住登录');
      return false;
    }

    // 获取保存的凭证
    final credentials = await authStorage.getCredentials();
    if (credentials == null) {
      logger.d('ConnectionStateNotifier: 无保存的凭证');
      return false;
    }

    // 获取保存的连接信息
    final savedConnections = _ref.read(savedConnectionsProvider);
    final connection = savedConnections.firstWhere(
      (c) => c.id == credentials.connectionId,
      orElse: () => savedConnections.firstWhere(
        (c) =>
            c.username == credentials.username &&
            '${c.host}_${c.port}_${c.username}' == credentials.connectionId,
        orElse: () => throw StateError('未找到保存的连接'),
      ),
    );

    logger.i('ConnectionStateNotifier: 尝试自动登录 => ${connection.host}');

    // 获取记住设备设置
    final rememberDevice = await authStorage.getRememberDevice();

    // 执行连接
    await connect(
      type: connection.type,
      host: connection.host,
      port: connection.port,
      username: credentials.username,
      password: credentials.password,
      useSsl: connection.useSsl,
      verifySSL: false,
      rememberLogin: true,
      rememberDevice: rememberDevice,
      connectionId: credentials.connectionId,
    );

    return state is ConnectionConnected;
  }

  /// 清除自动登录数据
  Future<void> clearAutoLogin() async {
    final authStorage = _ref.read(authStorageProvider);
    await authStorage.clearAll();
    logger.i('ConnectionStateNotifier: 已清除自动登录数据');
  }

  /// 与 [SourceManagerService._createAdapter] 保持同步——任何新增的 NAS 协议
  /// 适配器都需要在此处也加上，否则 ConnectionStateNotifier.connect 走到这里时
  /// 会抛 UnsupportedError。
  NasAdapter _createAdapter(NasAdapterType type) => switch (type) {
        NasAdapterType.synology => SynologyAdapter(),
        NasAdapterType.ugreen => UGreenAdapter(),
        NasAdapterType.fnos => FnOSAdapter(),
        NasAdapterType.qnap => QnapAdapter(),
        NasAdapterType.webdav => WebDavAdapter(),
        NasAdapterType.smb => SmbAdapter(),
        NasAdapterType.ftp => FtpAdapter(),
        NasAdapterType.sftp => SftpAdapter(),
        NasAdapterType.local => LocalAdapter(),
      };
}

/// 保存的连接管理
class SavedConnectionsNotifier extends StateNotifier<List<ConnectionEntity>> {
  SavedConnectionsNotifier() : super([]) {
    _loadConnections();
  }

  late final HiveStorageService _storage;
  bool _initialized = false;

  Future<void> _loadConnections() async {
    _storage = HiveStorageService(boxName: 'connections');
    await _storage.init();
    _initialized = true;

    final saved = _storage.get<List<dynamic>>('list');
    if (saved != null) {
      state = saved
          .map((e) => ConnectionEntity.fromJson(e as Map<String, dynamic>))
          .toList();
    }
  }

  Future<void> addConnection(ConnectionEntity connection) async {
    if (!_initialized) return;

    // 检查是否已存在
    final exists = state.any((c) => c.id == connection.id);
    if (exists) {
      state = [
        for (final c in state)
          if (c.id == connection.id) connection else c,
      ];
    } else {
      state = [...state, connection];
    }

    await _saveConnections();
  }

  Future<void> removeConnection(String id) async {
    if (!_initialized) return;
    state = state.where((c) => c.id != id).toList();
    await _saveConnections();
  }

  Future<void> updateLastConnected(String id) async {
    if (!_initialized) return;
    state = [
      for (final c in state)
        if (c.id == id) c.copyWith(lastConnected: DateTime.now()) else c,
    ];
    await _saveConnections();
  }

  Future<void> _saveConnections() async {
    await _storage.put('list', state.map((c) => c.toJson()).toList());
  }
}
