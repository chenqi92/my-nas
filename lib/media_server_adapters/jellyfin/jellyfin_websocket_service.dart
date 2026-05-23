import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Jellyfin WebSocket 消息类型
enum JellyfinMessageType {
  /// 强制保持活动
  forceKeepAlive('ForceKeepAlive'),

  /// 通用命令
  generalCommand('GeneralCommand'),

  /// 用户数据变更
  userDataChanged('UserDataChanged'),

  /// 会话信息
  sessions('Sessions'),

  /// 播放状态
  playState('PlayState'),

  /// 服务器关闭
  serverShuttingDown('ServerShuttingDown'),

  /// 服务器重启
  serverRestarting('ServerRestarting'),

  /// 库变更
  libraryChanged('LibraryChanged'),

  /// 刷新进度
  refreshProgress('RefreshProgress'),

  /// 计划任务结束
  scheduledTaskEnded('ScheduledTaskEnded'),

  /// 包安装
  packageInstalling('PackageInstalling'),

  /// 包安装取消
  packageInstallationCancelled('PackageInstallationCancelled'),

  /// 包安装完成
  packageInstallationCompleted('PackageInstallationCompleted'),

  /// 包安装失败
  packageInstallationFailed('PackageInstallationFailed'),

  /// 同步播放命令
  syncPlayCommand('SyncPlayCommand'),

  /// 同步播放组更新
  syncPlayGroupUpdate('SyncPlayGroupUpdate'),

  /// 未知类型
  unknown('Unknown');

  const JellyfinMessageType(this.value);
  final String value;

  static JellyfinMessageType fromString(String? value) =>
      JellyfinMessageType.values.firstWhere(
        (e) => e.value == value,
        orElse: () => JellyfinMessageType.unknown,
      );
}

/// Jellyfin WebSocket 事件
class JellyfinWebSocketEvent {
  const JellyfinWebSocketEvent({
    required this.type,
    this.data,
  });

  factory JellyfinWebSocketEvent.fromJson(Map<String, dynamic> json) => JellyfinWebSocketEvent(
      type: JellyfinMessageType.fromString(json['MessageType'] as String?),
      data: json['Data'],
    );

  final JellyfinMessageType type;
  final dynamic data;
}

/// 库变更事件数据
class LibraryChangedData {
  const LibraryChangedData({
    this.itemsAdded = const [],
    this.itemsRemoved = const [],
    this.itemsUpdated = const [],
    this.collectionFolders = const [],
  });

  factory LibraryChangedData.fromJson(Map<String, dynamic> json) => LibraryChangedData(
      itemsAdded: (json['ItemsAdded'] as List?)?.cast<String>() ?? [],
      itemsRemoved: (json['ItemsRemoved'] as List?)?.cast<String>() ?? [],
      itemsUpdated: (json['ItemsUpdated'] as List?)?.cast<String>() ?? [],
      collectionFolders:
          (json['CollectionFolders'] as List?)?.cast<String>() ?? [],
    );

  final List<String> itemsAdded;
  final List<String> itemsRemoved;
  final List<String> itemsUpdated;
  final List<String> collectionFolders;

  bool get hasChanges =>
      itemsAdded.isNotEmpty ||
      itemsRemoved.isNotEmpty ||
      itemsUpdated.isNotEmpty;
}

/// 用户数据变更事件
class UserDataChangedData {
  const UserDataChangedData({
    required this.userId,
    this.userDataList = const [],
  });

  factory UserDataChangedData.fromJson(Map<String, dynamic> json) => UserDataChangedData(
      userId: json['UserId'] as String? ?? '',
      userDataList: (json['UserDataList'] as List?)
              ?.map((e) => UserDataItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );

  final String userId;
  final List<UserDataItem> userDataList;
}

/// 用户数据项
class UserDataItem {
  const UserDataItem({
    required this.itemId,
    this.played = false,
    this.playbackPositionTicks,
    this.isFavorite = false,
  });

  factory UserDataItem.fromJson(Map<String, dynamic> json) => UserDataItem(
      itemId: json['ItemId'] as String? ?? '',
      played: json['Played'] as bool? ?? false,
      playbackPositionTicks: json['PlaybackPositionTicks'] as int?,
      isFavorite: json['IsFavorite'] as bool? ?? false,
    );

  final String itemId;
  final bool played;
  final int? playbackPositionTicks;
  final bool isFavorite;
}

/// Jellyfin WebSocket 服务
class JellyfinWebSocketService {
  JellyfinWebSocketService({
    required this.serverUrl,
    required this.accessToken,
    this.deviceId,
  });

  final String serverUrl;
  final String accessToken;
  final String? deviceId;

  WebSocketChannel? _channel;
  Timer? _keepAliveTimer;
  bool _isConnected = false;
  int _reconnectAttempts = 0;
  static const _maxReconnectAttempts = 5;
  static const _reconnectDelay = Duration(seconds: 5);

  final _eventController =
      StreamController<JellyfinWebSocketEvent>.broadcast();

  /// 事件流
  Stream<JellyfinWebSocketEvent> get events => _eventController.stream;

  /// 是否已连接
  bool get isConnected => _isConnected;

  /// 连接到 WebSocket
  Future<void> connect() async {
    if (_isConnected) return;

    try {
      final wsUrl = _buildWebSocketUrl();
      logger.d('JellyfinWebSocket: 连接到 $wsUrl');

      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      // 等待连接建立
      await _channel!.ready;

      _isConnected = true;
      _reconnectAttempts = 0;

      // 监听消息
      _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDone,
      );

      // 启动保活
      _startKeepAlive();

      logger.i('JellyfinWebSocket: 连接成功');
    } on Exception catch (e) {
      logger.e('JellyfinWebSocket: 连接失败', e);
      _scheduleReconnect();
    }
  }

  /// 断开连接
  Future<void> disconnect() async {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    _isConnected = false;

    await _channel?.sink.close();
    _channel = null;

    logger.i('JellyfinWebSocket: 已断开连接');
  }

  /// 发送消息
  void send(String messageType, [Map<String, dynamic>? data]) {
    if (!_isConnected || _channel == null) return;

    final message = {
      'MessageType': messageType,
      'Data': ?data,
    };

    _channel!.sink.add(jsonEncode(message));
  }

  /// 订阅库变更通知
  void subscribeLibraryChanges() {
    send('LibraryChangedNotification');
  }

  /// 订阅用户数据变更
  void subscribeUserDataChanges() {
    send('UserDataChangedNotification');
  }

  /// 订阅会话信息
  void subscribeSessions() {
    send('SessionsStart', {'Data': '0,1500'});
  }

  String _buildWebSocketUrl() {
    // 将 http/https 转换为 ws/wss
    var wsUrl = serverUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');

    // 移除尾部斜杠
    if (wsUrl.endsWith('/')) {
      wsUrl = wsUrl.substring(0, wsUrl.length - 1);
    }

    // 构建完整 URL
    final params = <String, String>{
      'api_key': accessToken,
    };
    if (deviceId != null) {
      params['deviceId'] = deviceId!;
    }

    final queryString =
        params.entries.map((e) => '${e.key}=${e.value}').join('&');

    return '$wsUrl/socket?$queryString';
  }

  void _handleMessage(dynamic message) {
    try {
      final json = jsonDecode(message as String) as Map<String, dynamic>;
      final event = JellyfinWebSocketEvent.fromJson(json);

      // 处理保活响应
      if (event.type == JellyfinMessageType.forceKeepAlive) {
        _sendKeepAlive();
        return;
      }

      _eventController.add(event);

      logger.d('JellyfinWebSocket: 收到事件 ${event.type.value}');
    } on Exception catch (e) {
      logger.w('JellyfinWebSocket: 解析消息失败', e);
    }
  }

  void _handleError(Object error) {
    logger.e('JellyfinWebSocket: 错误', error);
    _isConnected = false;
    _scheduleReconnect();
  }

  void _handleDone() {
    logger.i('JellyfinWebSocket: 连接关闭');
    _isConnected = false;
    _keepAliveTimer?.cancel();
    _scheduleReconnect();
  }

  void _startKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _sendKeepAlive(),
    );
  }

  void _sendKeepAlive() {
    send('KeepAlive');
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      logger.w('JellyfinWebSocket: 已达最大重连次数');
      return;
    }

    _reconnectAttempts++;
    final delay = _reconnectDelay * _reconnectAttempts;

    logger.i(
      'JellyfinWebSocket: ${delay.inSeconds}秒后尝试重连 '
      '($_reconnectAttempts/$_maxReconnectAttempts)',
    );

    Future.delayed(delay, connect);
  }

  void dispose() {
    disconnect();
    _eventController.close();
  }
}

/// Jellyfin WebSocket 服务工厂 Provider
final jellyfinWebSocketServiceFactoryProvider =
    Provider<JellyfinWebSocketServiceFactory>((ref) => JellyfinWebSocketServiceFactory());

/// WebSocket 服务工厂
class JellyfinWebSocketServiceFactory {
  final _instances = <String, JellyfinWebSocketService>{};

  /// 获取或创建指定源的 WebSocket 服务
  JellyfinWebSocketService getOrCreate({
    required String sourceId,
    required String serverUrl,
    required String accessToken,
    String? deviceId,
  }) {
    if (_instances.containsKey(sourceId)) {
      return _instances[sourceId]!;
    }

    final service = JellyfinWebSocketService(
      serverUrl: serverUrl,
      accessToken: accessToken,
      deviceId: deviceId,
    );
    _instances[sourceId] = service;
    return service;
  }

  /// 移除指定源的 WebSocket 服务
  void remove(String sourceId) {
    _instances[sourceId]?.dispose();
    _instances.remove(sourceId);
  }

  /// 释放所有资源
  void dispose() {
    for (final service in _instances.values) {
      service.dispose();
    }
    _instances.clear();
  }
}
