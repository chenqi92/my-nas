import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/services/nas_file_system_registry.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/book/data/services/book_database_service.dart';
import 'package:my_nas/features/book/data/services/book_library_cache_service.dart';
import 'package:my_nas/features/comic/data/services/comic_library_cache_service.dart';
import 'package:my_nas/features/music/data/services/music_database_service.dart';
import 'package:my_nas/features/music/data/services/music_library_cache_service.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';
import 'package:my_nas/features/music/presentation/providers/music_settings_provider.dart';
import 'package:my_nas/features/photo/data/services/photo_database_service.dart';
import 'package:my_nas/features/photo/data/services/photo_library_cache_service.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/sources/domain/entities/source_category.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/video/data/services/video_database_service.dart';
import 'package:my_nas/features/video/data/services/video_library_cache_service.dart';
import 'package:my_nas/media_server_adapters/base/media_server_event_handler.dart';
import 'package:my_nas/media_server_adapters/base/media_server_sync_service.dart';

/// 源管理服务 Provider
final sourceManagerProvider = Provider<SourceManagerService>(
  (ref) => SourceManagerService(),
);

/// 所有源列表 Provider
final sourcesProvider =
    StateNotifierProvider<SourcesNotifier, AsyncValue<List<SourceEntity>>>(
      SourcesNotifier.new,
    );

/// 活跃连接 Provider
final activeConnectionsProvider =
    StateNotifierProvider<
      ActiveConnectionsNotifier,
      Map<String, SourceConnection>
    >(ActiveConnectionsNotifier.new);

/// 活跃媒体服务器连接 Provider
final activeMediaServerConnectionsProvider =
    StateNotifierProvider<
      ActiveMediaServerConnectionsNotifier,
      Map<String, MediaServerConnection>
    >(ActiveMediaServerConnectionsNotifier.new);

/// 媒体库配置 Provider
final mediaLibraryConfigProvider =
    StateNotifierProvider<
      MediaLibraryConfigNotifier,
      AsyncValue<MediaLibraryConfig>
    >(MediaLibraryConfigNotifier.new);

/// 源列表管理
class SourcesNotifier extends StateNotifier<AsyncValue<List<SourceEntity>>> {
  SourcesNotifier(this._ref) : super(const AsyncValue.loading()) {
    _load();
  }

  final Ref _ref;

  Future<void> _load() async {
    try {
      final manager = _ref.read(sourceManagerProvider);
      await manager.init();
      var sources = await manager.getSources();

      // 清理旧的移动端媒体源（已废弃）
      final oldMobileTypes = ['mobile_gallery', 'mobile_music', 'mobile_files'];
      final oldSources = sources
          .where((s) => oldMobileTypes.contains(s.type.id))
          .toList();
      for (final oldSource in oldSources) {
        await manager.removeSource(oldSource.id);
        // 清理关联的媒体库路径
        await _ref
            .read(mediaLibraryConfigProvider.notifier)
            .removePathsForSource(oldSource.id);
      }
      if (oldSources.isNotEmpty) {
        sources = await manager.getSources();
      }

      // 确保存在唯一的本机源
      final localSources = sources
          .where((s) => s.type == SourceType.local)
          .toList();
      if (localSources.isEmpty) {
        // 创建本机源
        final localSource = SourceEntity(
          name: '本机',
          type: SourceType.local,
          host: 'localhost',
          username: 'local',
          autoConnect: true,
        );
        await manager.addSource(localSource);
        sources = await manager.getSources();
      } else if (localSources.length > 1) {
        // 删除多余的本机源，只保留第一个
        for (var i = 1; i < localSources.length; i++) {
          await manager.removeSource(localSources[i].id);
        }
        sources = await manager.getSources();
      }

      // 按 sortOrder 排序
      sources.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      // Provider 可能在异步初始化期间被销毁（例如应用退出、测试卸载根
      // Widget）。此时继续写入 StateNotifier 会触发 dispose 后更新异常。
      if (mounted) {
        state = AsyncValue.data(sources);
      }
    } on Exception catch (e, st) {
      // 销毁后的异步任务无需再发布结果；同时避免错误分支再次写入已释放状态。
      if (mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    await _load();
  }

  Future<void> addSource(SourceEntity source) async {
    final manager = _ref.read(sourceManagerProvider);
    await manager.addSource(source);
    await _load();
  }

  Future<void> updateSource(SourceEntity source) async {
    final manager = _ref.read(sourceManagerProvider);
    await manager.updateSource(source);
    await _load();
  }

  Future<void> removeSource(String sourceId) async {
    final manager = _ref.read(sourceManagerProvider);
    await manager.removeSource(sourceId);

    // 删除该源的所有媒体数据（包括 SQLite 数据库和 Hive 缓存）
    await Future.wait([
      VideoDatabaseService().deleteBySourceId(sourceId),
      VideoLibraryCacheService().deleteBySourceId(sourceId),
      MusicDatabaseService().deleteBySourceId(sourceId),
      PhotoDatabaseService().deleteBySourceId(sourceId),
      BookDatabaseService().deleteBySourceId(sourceId),
      ComicLibraryCacheService().deleteBySourceId(sourceId),
    ]);

    // 同时刷新连接状态
    _ref.read(activeConnectionsProvider.notifier).refresh();
    _ref.read(activeMediaServerConnectionsProvider.notifier).refresh();
    await _load();
  }

  /// 重新排序源列表
  Future<void> reorderSources(int oldIndex, int newIndex) async {
    final sources = state.valueOrNull;
    if (sources == null) return;

    // 创建可变副本
    final mutableSources = List<SourceEntity>.from(sources);

    // 移动元素
    final item = mutableSources.removeAt(oldIndex);
    mutableSources.insert(newIndex, item);

    // 更新排序顺序
    final updatedSources = <SourceEntity>[];
    for (var i = 0; i < mutableSources.length; i++) {
      updatedSources.add(mutableSources[i].copyWith(sortOrder: i));
    }

    // 保存到存储
    final manager = _ref.read(sourceManagerProvider);
    for (final source in updatedSources) {
      await manager.updateSource(source);
    }

    // 立即更新状态（不需要等待 _load）
    state = AsyncValue.data(updatedSources);
  }
}

/// 活跃连接管理
class ActiveConnectionsNotifier
    extends StateNotifier<Map<String, SourceConnection>> {
  ActiveConnectionsNotifier(this._ref) : super({}) {
    // 初始化时自动连接所有源
    _initAutoConnect();
  }

  final Ref _ref;
  bool _hasInitialized = false;
  bool _isAutoConnecting = false;

  /// 已触发过初始自动连接
  bool _hasAutoConnectedOnce = false;

  /// 是否正在自动连接中
  bool get isAutoConnecting => _isAutoConnecting;

  /// 初始化自动连接
  Future<void> _initAutoConnect() async {
    if (_hasInitialized) return;
    _hasInitialized = true;

    // 等待 sourcesProvider 初始化完成
    // 只在应用启动时触发一次自动连接，而不是每次源列表变化都触发
    // 这样可以避免新建源时触发重复连接
    _ref.listen<AsyncValue<List<SourceEntity>>>(sourcesProvider, (
      previous,
      next,
    ) {
      if (next.hasValue && !_isAutoConnecting && !_hasAutoConnectedOnce) {
        // 数据已准备好，只在首次启动时自动连接（使用 microtask 避免在 listen 回调中直接调用）
        _hasAutoConnectedOnce = true;
        Future.microtask(autoConnectAll);
      }
    }, fireImmediately: true);
  }

  void refresh() {
    final manager = _ref.read(sourceManagerProvider);
    final connections = <String, SourceConnection>{};
    final sources = _ref.read(sourcesProvider).valueOrNull ?? <SourceEntity>[];
    for (final source in sources) {
      final conn = manager.getConnection(source.id);
      if (conn != null) {
        connections[source.id] = conn;
        // 注册 fileSystem 到全局 Registry
        if (conn.status == SourceStatus.connected) {
          NasFileSystemRegistry.instance.register(
            source.id,
            conn.adapter.fileSystem,
          );
        }
      }
    }
    state = connections;
  }

  Future<SourceConnection> connect(
    SourceEntity source, {
    required String password,
    bool saveCredential = true,
  }) async {
    final manager = _ref.read(sourceManagerProvider);
    final connection = await manager.connect(
      source,
      password: password,
      saveCredential: saveCredential,
    );
    state = {...state, source.id: connection};
    // 注册 fileSystem 到全局 Registry
    if (connection.status == SourceStatus.connected) {
      NasFileSystemRegistry.instance.register(
        source.id,
        connection.adapter.fileSystem,
      );
    }
    return connection;
  }

  /// 测试连接（不保存凭证，用于新建源时先验证连接）
  Future<SourceConnection> connectNew(
    SourceEntity source, {
    required String password,
  }) async {
    final manager = _ref.read(sourceManagerProvider);
    final connection = await manager.connect(
      source,
      password: password,
      saveCredential: false,
    );
    state = {...state, source.id: connection};
    return connection;
  }

  Future<SourceConnection> verify2FA(
    String sourceId,
    String otpCode, {
    bool rememberDevice = false,
    String? password,
  }) async {
    final manager = _ref.read(sourceManagerProvider);
    final connection = await manager.verify2FA(
      sourceId,
      otpCode,
      rememberDevice: rememberDevice,
      password: password,
    );
    state = {...state, sourceId: connection};
    return connection;
  }

  Future<void> disconnect(String sourceId) async {
    final manager = _ref.read(sourceManagerProvider);
    await manager.disconnect(sourceId);
    // 从全局 Registry 注销 fileSystem
    NasFileSystemRegistry.instance.unregister(sourceId);
    state = Map.from(state)..remove(sourceId);
  }

  Future<void> disconnectAll() async {
    final manager = _ref.read(sourceManagerProvider);
    await manager.disconnectAll();
    // 清空全局 Registry
    NasFileSystemRegistry.instance.clear();
    state = {};
  }

  Future<void> autoConnectAll() async {
    if (_isAutoConnecting) return; // 防止重复调用
    _isAutoConnecting = true;
    try {
      final manager = _ref.read(sourceManagerProvider);
      await manager.autoConnectAll();
      refresh();

      // 检查是否有连接成功的源，并检查自动播放设置
      final hasConnected = state.values.any(
        (c) => c.status == SourceStatus.connected,
      );
      if (hasConnected) {
        final settings = _ref.read(musicSettingsProvider);
        if (settings.autoPlayOnConnect) {
          logger.i('SourceProvider: 检测到连接成功且启用了自动播放，尝试恢复播放状态');
          // 延迟一点执行，确保所有连接都已稳定
          Future.delayed(const Duration(milliseconds: 500), () {
            _ref
                .read(musicPlayerControllerProvider.notifier)
                .restoreLastPlayedState();
          });
        }
      }
    } finally {
      _isAutoConnecting = false;
    }
  }

  /// 获取指定源的文件系统
  SourceConnection? getConnection(String sourceId) => state[sourceId];

  /// 检查连接健康状态
  Future<bool> checkConnectionHealth(String sourceId) async {
    final manager = _ref.read(sourceManagerProvider);
    return manager.checkConnectionHealth(sourceId);
  }

  /// 重新连接
  Future<SourceConnection?> reconnect(String sourceId) async {
    final manager = _ref.read(sourceManagerProvider);
    final connection = await manager.reconnect(sourceId);

    if (connection != null) {
      // 更新状态
      state = {...state, sourceId: connection};
      // 如果连接成功，注册到全局 Registry
      if (connection.status == SourceStatus.connected) {
        NasFileSystemRegistry.instance.register(
          sourceId,
          connection.adapter.fileSystem,
        );
      }
    }

    return connection;
  }

  /// 确保连接健康，如果不健康则自动重连
  ///
  /// 返回连接是否健康（原本健康或重连成功）
  Future<bool> ensureConnectionHealthy(String sourceId) async {
    // 先检查连接是否健康
    final isHealthy = await checkConnectionHealth(sourceId);
    if (isHealthy) {
      return true;
    }

    // 尝试重连
    final newConnection = await reconnect(sourceId);
    return newConnection?.status == SourceStatus.connected;
  }
}

/// 活跃媒体服务器连接管理
class ActiveMediaServerConnectionsNotifier
    extends StateNotifier<Map<String, MediaServerConnection>> {
  ActiveMediaServerConnectionsNotifier(this._ref) : super({}) {
    _ref.listen<AsyncValue<List<SourceEntity>>>(sourcesProvider, (
      previous,
      next,
    ) {
      if (next.hasValue && !_hasAutoConnectedOnce) {
        _hasAutoConnectedOnce = true;
        Future.microtask(autoConnectAll);
      }
    }, fireImmediately: true);
  }

  final Ref _ref;
  bool _hasAutoConnectedOnce = false;
  bool _isAutoConnecting = false;

  void refresh() {
    final manager = _ref.read(sourceManagerProvider);
    final connections = <String, MediaServerConnection>{};
    final sources = _ref.read(sourcesProvider).valueOrNull ?? <SourceEntity>[];
    for (final source in sources) {
      final conn = manager.getMediaServerConnection(source.id);
      if (conn != null) {
        connections[source.id] = conn;
        // 注册虚拟文件系统到全局 Registry
        if (conn.status == SourceStatus.connected) {
          NasFileSystemRegistry.instance.register(
            source.id,
            conn.adapter.virtualFileSystem,
          );
        }
      }
    }
    state = connections;
  }

  Future<MediaServerConnection> connect(
    SourceEntity source, {
    String? password,
    String? apiKey,
    bool saveCredential = true,
  }) async {
    final manager = _ref.read(sourceManagerProvider);
    final connection = await manager.connectMediaServer(
      source,
      password: password,
      apiKey: apiKey,
      saveCredential: saveCredential,
    );
    state = {...state, source.id: connection};
    // 注册虚拟文件系统到全局 Registry
    if (connection.status == SourceStatus.connected) {
      NasFileSystemRegistry.instance.register(
        source.id,
        connection.adapter.virtualFileSystem,
      );

      // 处理连接模式
      await _handleConnectionMode(source, connection);
    }
    return connection;
  }

  /// 使用安全存储中的凭证重新连接媒体服务器。
  ///
  /// 媒体服务器不能走 [ActiveConnectionsNotifier.reconnect]，后者只会创建
  /// 普通 NAS/服务连接。桌面端和移动端统一从这里进入 Jellyfin / Emby /
  /// Plex 的专用连接链路。
  Future<MediaServerConnection?> reconnect(SourceEntity source) async {
    final manager = _ref.read(sourceManagerProvider);
    final credential = await manager.getCredential(source.id);
    final password = credential?.password;
    final apiKey = credential?.apiKey ?? source.apiKey;
    final hasReusableAuthentication =
        (password?.isNotEmpty ?? false) ||
        (apiKey?.isNotEmpty ?? false) ||
        (source.accessToken?.isNotEmpty ?? false);
    if (!hasReusableAuthentication) return null;

    await disconnect(source.id);
    return connect(
      source,
      password: password,
      apiKey: apiKey,
      saveCredential: false,
    );
  }

  /// 自动连接启用了自动连接的媒体服务器。
  Future<void> autoConnectAll() async {
    if (_isAutoConnecting) return;
    _isAutoConnecting = true;
    try {
      final manager = _ref.read(sourceManagerProvider);
      final sources = _ref.read(sourcesProvider).valueOrNull ?? const [];
      final mediaServers = sources.where(
        (source) =>
            source.autoConnect &&
            source.type.category == SourceCategory.mediaServers,
      );

      await Future.wait(
        mediaServers.map((source) async {
          final credential = await manager.getCredential(source.id);
          final hasReusableAuthentication =
              (credential?.password.isNotEmpty ?? false) ||
              (credential?.apiKey?.isNotEmpty ?? false) ||
              (source.apiKey?.isNotEmpty ?? false) ||
              (source.accessToken?.isNotEmpty ?? false);
          if (!hasReusableAuthentication) {
            logger.w('MediaServerConnection: ${source.name} 缺少可复用凭证，跳过自动连接');
            return;
          }

          await connect(
            source,
            password: credential?.password,
            apiKey: credential?.apiKey ?? source.apiKey,
            saveCredential: false,
          );
        }),
      );
    } finally {
      _isAutoConnecting = false;
    }
  }

  /// 处理连接模式（直连模式/库模式）
  Future<void> _handleConnectionMode(
    SourceEntity source,
    MediaServerConnection connection,
  ) async {
    // 获取连接模式配置
    final connectionMode = source.extraConfig?['connectionMode'] as String?;
    final isLibraryMode =
        connectionMode == '库模式' || connectionMode == 'library';

    logger.i('MediaServerConnection: 连接模式 = ${isLibraryMode ? "库模式" : "直连模式"}');

    if (isLibraryMode) {
      // 库模式：启动自动同步
      final syncService = _ref.read(mediaServerSyncServiceProvider);
      final syncInterval = source.extraConfig?['syncInterval'] as String?;
      final interval = _parseSyncInterval(syncInterval);

      if (interval != null) {
        syncService.startAutoSync(interval: interval);
        logger.i('MediaServerConnection: 已启动自动同步，间隔 = $interval');
      }

      // 执行初始增量同步
      await syncService.incrementalSync(source.id, connection.adapter);
    }

    // 连接 WebSocket 事件处理器
    await _connectEventHandler(source, connection);
  }

  /// 连接 WebSocket 事件处理器
  Future<void> _connectEventHandler(
    SourceEntity source,
    MediaServerConnection connection,
  ) async {
    // 只有 Jellyfin 和 Emby 支持 WebSocket
    if (source.type != SourceType.jellyfin && source.type != SourceType.emby) {
      return;
    }

    // 获取 accessToken
    final accessToken =
        source.accessToken ??
        source.extraConfig?['accessToken'] as String? ??
        connection.adapter.connection?.extraConfig?['accessToken'] as String?;

    if (accessToken == null) {
      logger.w('MediaServerConnection: 无法获取 accessToken，跳过 WebSocket 连接');
      return;
    }

    final factory = _ref.read(mediaServerEventHandlerFactoryProvider);
    final handler = factory.getOrCreate(
      sourceId: source.id,
      sourceType: source.type,
      serverUrl: source.baseUrl,
      accessToken: accessToken,
    );

    await handler.connect();

    // 监听库变更事件
    handler.libraryChanges.listen((event) {
      logger.i('MediaServerConnection: 收到库变更事件，${event.addedItems.length} 新增');
      // 触发增量同步
      _ref
          .read(mediaServerSyncServiceProvider)
          .incrementalSync(source.id, connection.adapter);
    });
  }

  /// 解析同步间隔配置
  Duration? _parseSyncInterval(String? interval) => switch (interval) {
    '每小时' || 'hourly' => const Duration(hours: 1),
    '每天' || 'daily' => const Duration(days: 1),
    '每周' || 'weekly' => const Duration(days: 7),
    _ => null, // 手动同步
  };

  Future<void> disconnect(String sourceId) async {
    final manager = _ref.read(sourceManagerProvider);
    await manager.disconnect(sourceId);
    // 从全局 Registry 注销
    NasFileSystemRegistry.instance.unregister(sourceId);
    // 清理事件处理器
    _ref.read(mediaServerEventHandlerFactoryProvider).remove(sourceId);
    state = Map.from(state)..remove(sourceId);
  }

  Future<void> disconnectAll() async {
    for (final sourceId in state.keys.toList()) {
      await disconnect(sourceId);
    }
  }

  /// 获取指定源的媒体服务器连接
  MediaServerConnection? getConnection(String sourceId) => state[sourceId];
}

/// 媒体库配置管理
class MediaLibraryConfigNotifier
    extends StateNotifier<AsyncValue<MediaLibraryConfig>> {
  MediaLibraryConfigNotifier(this._ref) : super(const AsyncValue.loading()) {
    _load();
  }

  final Ref _ref;

  Future<void> _load() async {
    try {
      final manager = _ref.read(sourceManagerProvider);
      await manager.init();
      final config = await manager.getMediaLibraryConfig();
      state = AsyncValue.data(config);
    } on Exception catch (e, st) {
      // 捕获所有错误，包括 TypeError
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    await _load();
  }

  Future<void> addPath(MediaType type, MediaLibraryPath path) async {
    final current = state.valueOrNull ?? const MediaLibraryConfig();
    final newConfig = current.addPath(type, path);
    await _save(newConfig);
  }

  Future<void> removePath(MediaType type, String pathId) async {
    final current = state.valueOrNull ?? const MediaLibraryConfig();

    // 获取要删除的路径信息（用于清理数据）
    final paths = current.getPathsForType(type);
    final pathToRemove = paths.where((p) => p.id == pathId).firstOrNull;

    // 根据媒体类型删除对应的数据
    if (pathToRemove != null) {
      final sourceId = pathToRemove.sourceId;
      final path = pathToRemove.path;

      // 处理本机文件路径的兼容性（旧格式 /documents/xxx 和新格式 /files/documents/xxx）
      // MobileCompositeFileSystem 会将 /documents/xxx 映射为 /files/documents/xxx
      // 所以需要同时尝试删除两种格式
      final pathsToDelete = <String>[path];
      if (path.startsWith('/documents') || path.startsWith('/downloads')) {
        // 旧格式路径，添加新格式
        pathsToDelete.add('/files$path');
      } else if (path.startsWith('/files/documents') ||
          path.startsWith('/files/downloads')) {
        // 新格式路径，添加旧格式
        pathsToDelete.add(path.replaceFirst('/files', ''));
      }

      switch (type) {
        case MediaType.video:
          // 同时删除 SQLite 数据库和 Hive 缓存
          await Future.wait([
            for (final p in pathsToDelete) ...[
              VideoDatabaseService().deleteByPath(sourceId, p),
              VideoLibraryCacheService().deleteByPath(sourceId, p),
            ],
          ]);
        case MediaType.music:
          // 同时删除 SQLite 数据库和 Hive 缓存
          await Future.wait([
            for (final p in pathsToDelete) ...[
              MusicDatabaseService().deleteByPath(sourceId, p),
              MusicLibraryCacheService().deleteByPath(sourceId, p),
            ],
          ]);
        case MediaType.photo:
          // 同时删除 SQLite 数据库和 Hive 缓存
          await Future.wait([
            for (final p in pathsToDelete) ...[
              PhotoDatabaseService().deleteByPath(sourceId, p),
              PhotoLibraryCacheService().deleteByPath(sourceId, p),
            ],
          ]);
        case MediaType.book:
          // 同时删除 SQLite 数据库和 Hive 缓存
          await Future.wait([
            for (final p in pathsToDelete) ...[
              BookDatabaseService().deleteByPath(sourceId, p),
              BookLibraryCacheService().deleteByPath(sourceId, p),
            ],
          ]);
        case MediaType.comic:
          await Future.wait([
            for (final p in pathsToDelete)
              ComicLibraryCacheService().deleteByPath(sourceId, p),
          ]);
        case MediaType.note:
          // 笔记暂不处理
          break;
      }
    }

    final newConfig = current.removePath(type, pathId);
    await _save(newConfig);
  }

  Future<void> togglePath(
    MediaType type,
    String pathId, {
    required bool enabled,
  }) async {
    final current = state.valueOrNull ?? const MediaLibraryConfig();
    final paths = current.getPathsForType(type);
    final updatedPaths = paths.map((p) {
      if (p.id == pathId) {
        return p.copyWith(isEnabled: enabled);
      }
      return p;
    }).toList();

    final newConfig = switch (type) {
      MediaType.video => current.copyWith(videoPaths: updatedPaths),
      MediaType.music => current.copyWith(musicPaths: updatedPaths),
      MediaType.photo => current.copyWith(photoPaths: updatedPaths),
      MediaType.comic => current.copyWith(comicPaths: updatedPaths),
      MediaType.book => current.copyWith(bookPaths: updatedPaths),
      MediaType.note => current.copyWith(notePaths: updatedPaths),
    };

    await _save(newConfig);
  }

  /// 移除指定源的所有路径（用于清理已删除的源）
  Future<void> removePathsForSource(String sourceId) async {
    final current = state.valueOrNull ?? const MediaLibraryConfig();
    final newConfig = current.removePathsForSource(sourceId);
    await _save(newConfig);
  }

  Future<void> _save(MediaLibraryConfig config) async {
    final manager = _ref.read(sourceManagerProvider);
    await manager.saveMediaLibraryConfig(config);
    state = AsyncValue.data(config);
  }
}

/// 获取指定媒体类型的可用路径（带源连接状态）
final mediaPathsWithSourceProvider =
    Provider.family<List<(MediaLibraryPath, SourceConnection?)>, MediaType>((
      ref,
      type,
    ) {
      final config = ref.watch(mediaLibraryConfigProvider).valueOrNull;
      final connections = ref.watch(activeConnectionsProvider);

      if (config == null) return [];

      final paths = config.getEnabledPathsForType(type);
      return paths.map((p) => (p, connections[p.sourceId])).toList();
    });

/// 存储类源列表（用于连接源页面）
final storageSourcesProvider = Provider<List<SourceEntity>>((ref) {
  final sources = ref.watch(sourcesProvider).valueOrNull ?? [];
  return sources.where((s) => s.type.category.isStorageCategory).toList();
});

/// 下载工具源列表
final downloadToolSourcesProvider = Provider<List<SourceEntity>>((ref) {
  final sources = ref.watch(sourcesProvider).valueOrNull ?? [];
  return sources
      .where((s) => s.type.category == SourceCategory.downloadTools)
      .toList();
});

/// 媒体追踪源列表
final mediaTrackingSourcesProvider = Provider<List<SourceEntity>>((ref) {
  final sources = ref.watch(sourcesProvider).valueOrNull ?? [];
  return sources
      .where((s) => s.type.category == SourceCategory.mediaTracking)
      .toList();
});

/// 媒体管理源列表
final mediaManagementSourcesProvider = Provider<List<SourceEntity>>((ref) {
  final sources = ref.watch(sourcesProvider).valueOrNull ?? [];
  return sources
      .where((s) => s.type.category == SourceCategory.mediaManagement)
      .toList();
});

/// PT 站点源列表
final ptSitesSourcesProvider = Provider<List<SourceEntity>>((ref) {
  final sources = ref.watch(sourcesProvider).valueOrNull ?? [];
  return sources
      .where((s) => s.type.category == SourceCategory.ptSites)
      .toList();
});

/// 字幕源列表
final subtitleSourcesProvider = Provider<List<SourceEntity>>((ref) {
  final sources = ref.watch(sourcesProvider).valueOrNull ?? [];
  return sources
      .where((s) => s.type.category == SourceCategory.subtitleSites)
      .toList();
});

/// NASTool 源列表
final nastoolSourcesProvider = Provider<List<SourceEntity>>((ref) {
  final sources = ref.watch(sourcesProvider).valueOrNull ?? [];
  return sources.where((s) => s.type == SourceType.nastool).toList();
});

/// 媒体服务器源列表（Jellyfin、Emby、Plex）
final mediaServerSourcesProvider = Provider<List<SourceEntity>>((ref) {
  final sources = ref.watch(sourcesProvider).valueOrNull ?? [];
  return sources
      .where((s) => s.type.category == SourceCategory.mediaServers)
      .toList();
});
