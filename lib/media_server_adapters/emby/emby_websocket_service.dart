import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

typedef EmbyWebSocketChannelFactory = WebSocketChannel Function(Uri uri);

/// Emby WebSocket 消息类型
enum EmbyMessageType {
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

  /// 播放命令
  play('Play'),

  /// 播放状态命令
  playstate('Playstate'),

  /// 浏览命令
  browse('Browse'),

  /// 消息命令
  messageCommand('MessageCommand'),

  /// 系统命令
  systemCommand('SystemCommand'),

  /// 通知添加
  notificationAdded('NotificationAdded'),

  /// 通知更新
  notificationUpdated('NotificationUpdated'),

  /// 通知标记已读
  notificationMarkedRead('NotificationMarkedRead'),

  /// 活动日志
  activityLogEntry('ActivityLogEntry'),

  /// 未知类型
  unknown('Unknown');

  const EmbyMessageType(this.value);
  final String value;

  static EmbyMessageType fromString(String? value) =>
      EmbyMessageType.values.firstWhere(
        (e) => e.value == value,
        orElse: () => EmbyMessageType.unknown,
      );
}

/// Emby WebSocket 事件
class EmbyWebSocketEvent {
  const EmbyWebSocketEvent({required this.type, this.data});

  factory EmbyWebSocketEvent.fromJson(Map<String, dynamic> json) =>
      EmbyWebSocketEvent(
        type: EmbyMessageType.fromString(json['MessageType'] as String?),
        data: json['Data'],
      );

  final EmbyMessageType type;
  final dynamic data;
}

/// 库变更事件数据
class EmbyLibraryChangedData {
  const EmbyLibraryChangedData({
    this.itemsAdded = const [],
    this.itemsRemoved = const [],
    this.itemsUpdated = const [],
    this.foldersAddedTo = const [],
    this.foldersRemovedFrom = const [],
  });

  factory EmbyLibraryChangedData.fromJson(Map<String, dynamic> json) =>
      EmbyLibraryChangedData(
        itemsAdded: (json['ItemsAdded'] as List?)?.cast<String>() ?? [],
        itemsRemoved: (json['ItemsRemoved'] as List?)?.cast<String>() ?? [],
        itemsUpdated: (json['ItemsUpdated'] as List?)?.cast<String>() ?? [],
        foldersAddedTo: (json['FoldersAddedTo'] as List?)?.cast<String>() ?? [],
        foldersRemovedFrom:
            (json['FoldersRemovedFrom'] as List?)?.cast<String>() ?? [],
      );

  final List<String> itemsAdded;
  final List<String> itemsRemoved;
  final List<String> itemsUpdated;
  final List<String> foldersAddedTo;
  final List<String> foldersRemovedFrom;

  bool get hasChanges =>
      itemsAdded.isNotEmpty ||
      itemsRemoved.isNotEmpty ||
      itemsUpdated.isNotEmpty;
}

/// 用户数据变更事件
class EmbyUserDataChangedData {
  const EmbyUserDataChangedData({
    required this.userId,
    this.userDataList = const [],
  });

  factory EmbyUserDataChangedData.fromJson(Map<String, dynamic> json) =>
      EmbyUserDataChangedData(
        userId: json['UserId'] as String? ?? '',
        userDataList:
            (json['UserDataList'] as List?)
                ?.map(
                  (e) => EmbyUserDataItem.fromJson(e as Map<String, dynamic>),
                )
                .toList() ??
            [],
      );

  final String userId;
  final List<EmbyUserDataItem> userDataList;
}

/// 用户数据项
class EmbyUserDataItem {
  const EmbyUserDataItem({
    required this.itemId,
    this.played = false,
    this.playbackPositionTicks,
    this.isFavorite = false,
    this.playCount,
    this.lastPlayedDate,
  });

  factory EmbyUserDataItem.fromJson(Map<String, dynamic> json) =>
      EmbyUserDataItem(
        itemId: json['ItemId'] as String? ?? '',
        played: json['Played'] as bool? ?? false,
        playbackPositionTicks: json['PlaybackPositionTicks'] as int?,
        isFavorite: json['IsFavorite'] as bool? ?? false,
        playCount: json['PlayCount'] as int?,
        lastPlayedDate: json['LastPlayedDate'] as String?,
      );

  final String itemId;
  final bool played;
  final int? playbackPositionTicks;
  final bool isFavorite;
  final int? playCount;
  final String? lastPlayedDate;
}

/// 活动日志条目
class EmbyActivityLogEntry {
  const EmbyActivityLogEntry({
    required this.id,
    required this.name,
    required this.type,
    this.overview,
    this.userId,
    this.itemId,
    this.date,
    this.severity,
  });

  factory EmbyActivityLogEntry.fromJson(Map<String, dynamic> json) =>
      EmbyActivityLogEntry(
        id: json['Id'] as int? ?? 0,
        name: json['Name'] as String? ?? '',
        type: json['Type'] as String? ?? '',
        overview: json['Overview'] as String?,
        userId: json['UserId'] as String?,
        itemId: json['ItemId'] as String?,
        date: json['Date'] as String?,
        severity: json['Severity'] as String?,
      );

  final int id;
  final String name;
  final String type;
  final String? overview;
  final String? userId;
  final String? itemId;
  final String? date;
  final String? severity;
}

/// Emby WebSocket 服务
class EmbyWebSocketService {
  EmbyWebSocketService({
    required this.serverUrl,
    required this.accessToken,
    this.deviceId,
    this.connectionTimeout = const Duration(seconds: 15),
    EmbyWebSocketChannelFactory? channelFactory,
  }) : _channelFactory = channelFactory ?? WebSocketChannel.connect;

  final String serverUrl;
  final String accessToken;
  final String? deviceId;
  final Duration connectionTimeout;
  final EmbyWebSocketChannelFactory _channelFactory;

  WebSocketChannel? _channel;
  WebSocketChannel? _connectingChannel;
  StreamSubscription<dynamic>? _channelSubscription;
  Timer? _keepAliveTimer;
  Timer? _reconnectTimer;
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isDisposed = false;
  bool _shouldReconnect = false;
  int _connectionGeneration = 0;
  int _reconnectAttempts = 0;
  static const _maxReconnectAttempts = 5;
  static const _reconnectDelay = Duration(seconds: 5);

  final _eventController = StreamController<EmbyWebSocketEvent>.broadcast();
  final Map<String, dynamic> _requestedSubscriptions = {};

  /// 事件流
  Stream<EmbyWebSocketEvent> get events => _eventController.stream;

  /// 库变更事件流
  Stream<EmbyLibraryChangedData> get libraryChanges => events
      .where((e) => e.type == EmbyMessageType.libraryChanged)
      .map(
        (e) => EmbyLibraryChangedData.fromJson(e.data as Map<String, dynamic>),
      );

  /// 用户数据变更事件流
  Stream<EmbyUserDataChangedData> get userDataChanges => events
      .where((e) => e.type == EmbyMessageType.userDataChanged)
      .map(
        (e) => EmbyUserDataChangedData.fromJson(e.data as Map<String, dynamic>),
      );

  /// 活动日志事件流
  Stream<EmbyActivityLogEntry> get activityLogs => events
      .where((e) => e.type == EmbyMessageType.activityLogEntry)
      .map(
        (e) => EmbyActivityLogEntry.fromJson(e.data as Map<String, dynamic>),
      );

  /// 是否已连接
  bool get isConnected => _isConnected;

  /// 连接到 WebSocket
  Future<void> connect() async {
    if (_isDisposed || _isConnected || _isConnecting) return;
    _shouldReconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _isConnecting = true;
    final generation = ++_connectionGeneration;
    WebSocketChannel? channel;

    try {
      final wsUrl = _buildWebSocketUrl();
      logger.d('EmbyWebSocket: 连接到 $wsUrl');

      channel = _channelFactory(Uri.parse(wsUrl));
      _connectingChannel = channel;

      // 等待连接建立
      await channel.ready.timeout(connectionTimeout);
      if (_isDisposed ||
          !_shouldReconnect ||
          generation != _connectionGeneration) {
        await _closeChannel(channel);
        return;
      }

      if (identical(_connectingChannel, channel)) {
        _connectingChannel = null;
      }

      await _channelSubscription?.cancel();
      _channelSubscription = null;
      final previousChannel = _channel;
      _channel = channel;

      _isConnected = true;
      _reconnectAttempts = 0;

      // 监听消息
      _channelSubscription = channel.stream.listen(
        _handleMessage,
        onError: (Object error) => _handleError(error, generation),
        onDone: () => _handleDone(generation),
      );
      if (previousChannel != null && !identical(previousChannel, channel)) {
        AppError.fireAndForget(
          previousChannel.sink.close(),
          action: 'embyWebSocketClosePreviousConnection',
        );
      }

      // 启动保活
      _startKeepAlive();

      // 发送身份验证
      _sendIdentify();
      _restoreSubscriptions();

      logger.i('EmbyWebSocket: 连接成功');
    } on Exception catch (e, st) {
      if (channel != null) {
        await _closeChannel(channel);
      }
      if (generation != _connectionGeneration || _isDisposed) return;
      logger.e('EmbyWebSocket: 连接失败', e);
      AppError.ignore(e, st, 'EmbyWebSocket 连接失败');
      _isConnected = false;
      _scheduleReconnect();
    } finally {
      if (identical(_connectingChannel, channel)) {
        _connectingChannel = null;
      }
      if (generation == _connectionGeneration) {
        _isConnecting = false;
      }
    }
  }

  /// 断开连接
  Future<void> disconnect() async {
    _shouldReconnect = false;
    _connectionGeneration++;
    _isConnecting = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    _isConnected = false;

    final connectingChannel = _connectingChannel;
    _connectingChannel = null;

    final subscription = _channelSubscription;
    _channelSubscription = null;
    await subscription?.cancel();

    final channel = _channel;
    _channel = null;
    await Future.wait<void>([
      if (connectingChannel != null) _closeChannel(connectingChannel),
      if (channel != null && !identical(channel, connectingChannel))
        _closeChannel(channel),
    ]);

    logger.i('EmbyWebSocket: 已断开连接');
  }

  /// 发送消息
  void send(String messageType, [dynamic data]) {
    if (_isDisposed || !_isConnected || _channel == null) return;

    final message = {'MessageType': messageType, 'Data': ?data};

    try {
      _channel!.sink.add(jsonEncode(message));
    } on Exception catch (e) {
      logger.w('EmbyWebSocket: 发送消息失败', e);
    }
  }

  /// 订阅库变更通知
  void subscribeLibraryChanges() {
    _requestSubscription('LibraryChanged');
  }

  /// 订阅用户数据变更
  void subscribeUserDataChanges() {
    _requestSubscription('UserDataChanged');
  }

  /// 订阅会话信息
  void subscribeSessions() {
    _requestSubscription('SessionsStart', '0,1500');
  }

  /// 订阅活动日志
  void subscribeActivityLog() {
    _requestSubscription('ActivityLogEntryStart', '0,1500');
  }

  void _requestSubscription(String messageType, [dynamic data]) {
    _requestedSubscriptions[messageType] = data;
    send(messageType, data);
  }

  void _restoreSubscriptions() {
    for (final entry in _requestedSubscriptions.entries) {
      send(entry.key, entry.value);
    }
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

    // Emby WebSocket 端点
    // 格式: ws://server/embywebsocket?api_key=xxx&deviceId=xxx
    final params = <String, String>{'api_key': accessToken};
    if (deviceId != null) {
      params['deviceId'] = deviceId!;
    }

    final queryString = params.entries
        .map((e) => '${e.key}=${e.value}')
        .join('&');

    return '$wsUrl/embywebsocket?$queryString';
  }

  void _sendIdentify() {
    // Emby 需要发送身份标识
    send(
      'Identity',
      jsonEncode({
        'Client': 'MyNas',
        'DeviceId': deviceId ?? 'mynas-device',
        'Device': 'MyNas App',
        'Version': '1.0.0',
      }),
    );
  }

  void _handleMessage(dynamic message) {
    try {
      final json = jsonDecode(message as String) as Map<String, dynamic>;
      final event = EmbyWebSocketEvent.fromJson(json);

      // 处理保活响应
      if (event.type == EmbyMessageType.forceKeepAlive) {
        _sendKeepAlive();
        return;
      }

      if (!_isDisposed && !_eventController.isClosed) {
        _eventController.add(event);
      }

      logger.d('EmbyWebSocket: 收到事件 ${event.type.value}');
    } on Exception catch (e) {
      logger.w('EmbyWebSocket: 解析消息失败', e);
    }
  }

  void _handleError(Object error, int generation) {
    if (_isDisposed || generation != _connectionGeneration) return;
    logger.e('EmbyWebSocket: 错误', error);
    _handleConnectionClosed(generation);
  }

  void _handleDone(int generation) {
    if (_isDisposed || generation != _connectionGeneration) return;
    logger.i('EmbyWebSocket: 连接关闭');
    _handleConnectionClosed(generation);
  }

  void _handleConnectionClosed(int generation) {
    if (generation != _connectionGeneration) return;
    _isConnected = false;
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    if (_shouldReconnect) _scheduleReconnect();
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

  Future<void> _closeChannel(WebSocketChannel channel) async {
    try {
      await channel.sink.close().timeout(const Duration(seconds: 2));
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'EmbyWebSocket 关闭连接失败');
    }
  }

  void _scheduleReconnect() {
    if (_isDisposed || !_shouldReconnect) return;
    if (_reconnectTimer?.isActive ?? false) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      logger.w('EmbyWebSocket: 已达最大重连次数');
      return;
    }

    _reconnectAttempts++;
    final delay = _reconnectDelay * _reconnectAttempts;

    logger.i(
      'EmbyWebSocket: ${delay.inSeconds}秒后尝试重连 '
      '($_reconnectAttempts/$_maxReconnectAttempts)',
    );

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      if (!_isDisposed && _shouldReconnect) {
        AppError.fireAndForget(connect(), action: 'embyWebSocketReconnect');
      }
    });
  }

  void dispose() {
    _isDisposed = true;
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    AppError.fireAndForget(
      disconnect(),
      action: 'embyWebSocketDisposeConnection',
    );
    if (!_eventController.isClosed) {
      _eventController.close();
    }
  }
}

/// Emby WebSocket 服务工厂 Provider
final embyWebSocketServiceFactoryProvider =
    Provider<EmbyWebSocketServiceFactory>(
      (ref) => EmbyWebSocketServiceFactory(),
    );

/// WebSocket 服务工厂
class EmbyWebSocketServiceFactory {
  final _instances = <String, EmbyWebSocketService>{};

  /// 获取或创建指定源的 WebSocket 服务
  EmbyWebSocketService getOrCreate({
    required String sourceId,
    required String serverUrl,
    required String accessToken,
    String? deviceId,
  }) {
    if (_instances.containsKey(sourceId)) {
      return _instances[sourceId]!;
    }

    final service = EmbyWebSocketService(
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
