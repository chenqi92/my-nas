import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/media_server_adapters/emby/emby_websocket_service.dart';
import 'package:my_nas/media_server_adapters/jellyfin/jellyfin_websocket_service.dart';

/// 库变更事件
class LibraryChangeEvent {
  const LibraryChangeEvent({
    required this.sourceId,
    required this.sourceType,
    this.addedItems = const [],
    this.removedItems = const [],
    this.updatedItems = const [],
  });

  final String sourceId;
  final SourceType sourceType;
  final List<String> addedItems;
  final List<String> removedItems;
  final List<String> updatedItems;

  bool get hasChanges =>
      addedItems.isNotEmpty ||
      removedItems.isNotEmpty ||
      updatedItems.isNotEmpty;
}

/// 用户数据变更事件（观看状态、收藏等）
class UserDataChangeEvent {
  const UserDataChangeEvent({
    required this.sourceId,
    required this.sourceType,
    required this.userId,
    required this.items,
  });

  final String sourceId;
  final SourceType sourceType;
  final String userId;
  final List<UserDataChangeItem> items;
}

/// 用户数据变更项
class UserDataChangeItem {
  const UserDataChangeItem({
    required this.itemId,
    this.played = false,
    this.playbackPositionTicks,
    this.isFavorite = false,
    this.playCount,
    this.lastPlayedDate,
  });

  final String itemId;
  final bool played;
  final int? playbackPositionTicks;
  final bool isFavorite;
  final int? playCount;
  final String? lastPlayedDate;
}

/// 服务器状态事件
class ServerStatusEvent {
  const ServerStatusEvent({
    required this.sourceId,
    required this.sourceType,
    required this.status,
    this.message,
  });

  final String sourceId;
  final SourceType sourceType;
  final ServerStatus status;
  final String? message;
}

/// 服务器状态
enum ServerStatus {
  connected,
  disconnected,
  shuttingDown,
  restarting,
}

/// 媒体服务器事件处理器
///
/// 统一处理 Jellyfin/Emby WebSocket 事件，提供标准化的事件流
class MediaServerEventHandler {
  MediaServerEventHandler({
    required this.sourceId,
    required this.sourceType,
    required this.serverUrl,
    required this.accessToken,
    this.deviceId,
  });

  final String sourceId;
  final SourceType sourceType;
  final String serverUrl;
  final String accessToken;
  final String? deviceId;

  JellyfinWebSocketService? _jellyfinWs;
  EmbyWebSocketService? _embyWs;

  StreamSubscription<dynamic>? _eventSubscription;
  bool _isConnected = false;

  final _libraryChangeController = StreamController<LibraryChangeEvent>.broadcast();
  final _userDataChangeController = StreamController<UserDataChangeEvent>.broadcast();
  final _serverStatusController = StreamController<ServerStatusEvent>.broadcast();

  /// 库变更事件流
  Stream<LibraryChangeEvent> get libraryChanges => _libraryChangeController.stream;

  /// 用户数据变更事件流
  Stream<UserDataChangeEvent> get userDataChanges => _userDataChangeController.stream;

  /// 服务器状态事件流
  Stream<ServerStatusEvent> get serverStatus => _serverStatusController.stream;

  /// 是否已连接
  bool get isConnected => _isConnected;

  /// 连接到 WebSocket 服务
  Future<void> connect() async {
    if (_isConnected) return;

    try {
      switch (sourceType) {
        case SourceType.jellyfin:
          await _connectJellyfin();
        case SourceType.emby:
          await _connectEmby();
        default:
          logger.w('MediaServerEventHandler: 不支持的服务器类型 $sourceType');
          return;
      }

      _isConnected = true;
      _serverStatusController.add(ServerStatusEvent(
        sourceId: sourceId,
        sourceType: sourceType,
        status: ServerStatus.connected,
      ));

      logger.i('MediaServerEventHandler: 已连接到 $sourceType 事件服务');
    } on Exception catch (e) {
      logger.e('MediaServerEventHandler: 连接失败', e);
    }
  }

  /// 断开连接
  Future<void> disconnect() async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;

    await _jellyfinWs?.disconnect();
    await _embyWs?.disconnect();

    _isConnected = false;
    _serverStatusController.add(ServerStatusEvent(
      sourceId: sourceId,
      sourceType: sourceType,
      status: ServerStatus.disconnected,
    ));

    logger.i('MediaServerEventHandler: 已断开连接');
  }

  /// 释放资源
  void dispose() {
    disconnect();
    _jellyfinWs?.dispose();
    _embyWs?.dispose();
    _libraryChangeController.close();
    _userDataChangeController.close();
    _serverStatusController.close();
  }

  Future<void> _connectJellyfin() async {
    _jellyfinWs = JellyfinWebSocketService(
      serverUrl: serverUrl,
      accessToken: accessToken,
      deviceId: deviceId,
    );

    await _jellyfinWs!.connect();

    // 订阅事件
    _jellyfinWs!.subscribeLibraryChanges();
    _jellyfinWs!.subscribeUserDataChanges();

    // 监听事件
    _eventSubscription = _jellyfinWs!.events.listen(_handleJellyfinEvent);
  }

  Future<void> _connectEmby() async {
    _embyWs = EmbyWebSocketService(
      serverUrl: serverUrl,
      accessToken: accessToken,
      deviceId: deviceId,
    );

    await _embyWs!.connect();

    // 订阅事件
    _embyWs!.subscribeLibraryChanges();
    _embyWs!.subscribeUserDataChanges();

    // 监听事件
    _eventSubscription = _embyWs!.events.listen(_handleEmbyEvent);
  }

  void _handleJellyfinEvent(JellyfinWebSocketEvent event) {
    switch (event.type) {
      case JellyfinMessageType.libraryChanged:
        _handleJellyfinLibraryChanged(event.data);
      case JellyfinMessageType.userDataChanged:
        _handleJellyfinUserDataChanged(event.data);
      case JellyfinMessageType.serverShuttingDown:
        _serverStatusController.add(ServerStatusEvent(
          sourceId: sourceId,
          sourceType: sourceType,
          status: ServerStatus.shuttingDown,
          message: '服务器正在关闭',
        ));
      case JellyfinMessageType.serverRestarting:
        _serverStatusController.add(ServerStatusEvent(
          sourceId: sourceId,
          sourceType: sourceType,
          status: ServerStatus.restarting,
          message: '服务器正在重启',
        ));
      default:
        logger.d('MediaServerEventHandler: 未处理的 Jellyfin 事件 ${event.type}');
    }
  }

  void _handleEmbyEvent(EmbyWebSocketEvent event) {
    switch (event.type) {
      case EmbyMessageType.libraryChanged:
        _handleEmbyLibraryChanged(event.data);
      case EmbyMessageType.userDataChanged:
        _handleEmbyUserDataChanged(event.data);
      case EmbyMessageType.serverShuttingDown:
        _serverStatusController.add(ServerStatusEvent(
          sourceId: sourceId,
          sourceType: sourceType,
          status: ServerStatus.shuttingDown,
          message: '服务器正在关闭',
        ));
      case EmbyMessageType.serverRestarting:
        _serverStatusController.add(ServerStatusEvent(
          sourceId: sourceId,
          sourceType: sourceType,
          status: ServerStatus.restarting,
          message: '服务器正在重启',
        ));
      default:
        logger.d('MediaServerEventHandler: 未处理的 Emby 事件 ${event.type}');
    }
  }

  void _handleJellyfinLibraryChanged(dynamic data) {
    if (data == null) return;
    final libraryData = LibraryChangedData.fromJson(data as Map<String, dynamic>);
    if (!libraryData.hasChanges) return;

    _libraryChangeController.add(LibraryChangeEvent(
      sourceId: sourceId,
      sourceType: sourceType,
      addedItems: libraryData.itemsAdded,
      removedItems: libraryData.itemsRemoved,
      updatedItems: libraryData.itemsUpdated,
    ));

    logger.i(
      'MediaServerEventHandler: 库变更 - '
      '添加: ${libraryData.itemsAdded.length}, '
      '删除: ${libraryData.itemsRemoved.length}, '
      '更新: ${libraryData.itemsUpdated.length}',
    );
  }

  void _handleJellyfinUserDataChanged(dynamic data) {
    if (data == null) return;
    final userData = UserDataChangedData.fromJson(data as Map<String, dynamic>);
    if (userData.userDataList.isEmpty) return;

    _userDataChangeController.add(UserDataChangeEvent(
      sourceId: sourceId,
      sourceType: sourceType,
      userId: userData.userId,
      items: userData.userDataList
          .map((item) => UserDataChangeItem(
                itemId: item.itemId,
                played: item.played,
                playbackPositionTicks: item.playbackPositionTicks,
                isFavorite: item.isFavorite,
              ))
          .toList(),
    ));

    logger.i(
      'MediaServerEventHandler: 用户数据变更 - '
      '${userData.userDataList.length} 项',
    );
  }

  void _handleEmbyLibraryChanged(dynamic data) {
    if (data == null) return;
    final libraryData = EmbyLibraryChangedData.fromJson(data as Map<String, dynamic>);
    if (!libraryData.hasChanges) return;

    _libraryChangeController.add(LibraryChangeEvent(
      sourceId: sourceId,
      sourceType: sourceType,
      addedItems: libraryData.itemsAdded,
      removedItems: libraryData.itemsRemoved,
      updatedItems: libraryData.itemsUpdated,
    ));

    logger.i(
      'MediaServerEventHandler: 库变更 - '
      '添加: ${libraryData.itemsAdded.length}, '
      '删除: ${libraryData.itemsRemoved.length}, '
      '更新: ${libraryData.itemsUpdated.length}',
    );
  }

  void _handleEmbyUserDataChanged(dynamic data) {
    if (data == null) return;
    final userData = EmbyUserDataChangedData.fromJson(data as Map<String, dynamic>);
    if (userData.userDataList.isEmpty) return;

    _userDataChangeController.add(UserDataChangeEvent(
      sourceId: sourceId,
      sourceType: sourceType,
      userId: userData.userId,
      items: userData.userDataList
          .map((item) => UserDataChangeItem(
                itemId: item.itemId,
                played: item.played,
                playbackPositionTicks: item.playbackPositionTicks,
                isFavorite: item.isFavorite,
                playCount: item.playCount,
                lastPlayedDate: item.lastPlayedDate,
              ))
          .toList(),
    ));

    logger.i(
      'MediaServerEventHandler: 用户数据变更 - '
      '${userData.userDataList.length} 项',
    );
  }
}

/// 媒体服务器事件处理器工厂 Provider
final mediaServerEventHandlerFactoryProvider =
    Provider<MediaServerEventHandlerFactory>((ref) => MediaServerEventHandlerFactory());

/// 媒体服务器事件处理器工厂
class MediaServerEventHandlerFactory {
  final _instances = <String, MediaServerEventHandler>{};

  /// 获取或创建指定源的事件处理器
  MediaServerEventHandler getOrCreate({
    required String sourceId,
    required SourceType sourceType,
    required String serverUrl,
    required String accessToken,
    String? deviceId,
  }) {
    if (_instances.containsKey(sourceId)) {
      return _instances[sourceId]!;
    }

    final handler = MediaServerEventHandler(
      sourceId: sourceId,
      sourceType: sourceType,
      serverUrl: serverUrl,
      accessToken: accessToken,
      deviceId: deviceId,
    );
    _instances[sourceId] = handler;
    return handler;
  }

  /// 移除指定源的事件处理器
  void remove(String sourceId) {
    _instances[sourceId]?.dispose();
    _instances.remove(sourceId);
  }

  /// 获取指定源的事件处理器（如果存在）
  MediaServerEventHandler? get(String sourceId) => _instances[sourceId];

  /// 释放所有资源
  void dispose() {
    for (final handler in _instances.values) {
      handler.dispose();
    }
    _instances.clear();
  }
}
