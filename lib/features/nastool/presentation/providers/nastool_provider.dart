import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/service_adapters/base/service_adapter.dart';
import 'package:my_nas/service_adapters/nastool/models/models.dart';
import 'package:my_nas/service_adapters/nastool/nastool_adapter.dart';

/// NASTool 连接状态
enum NasToolConnectionStatus { disconnected, connecting, connected, error }

/// NASTool 连接信息
class NasToolConnection {
  const NasToolConnection({
    required this.source,
    required this.adapter,
    this.status = NasToolConnectionStatus.disconnected,
    this.errorMessage,
  });

  final SourceEntity source;
  final NasToolAdapter adapter;
  final NasToolConnectionStatus status;
  final String? errorMessage;

  NasToolConnection copyWith({
    SourceEntity? source,
    NasToolAdapter? adapter,
    NasToolConnectionStatus? status,
    String? errorMessage,
  }) => NasToolConnection(
    source: source ?? this.source,
    adapter: adapter ?? this.adapter,
    status: status ?? this.status,
    errorMessage: errorMessage,
  );
}

/// NASTool 连接管理 Provider
final nastoolConnectionProvider =
    StateNotifierProvider.family<
      NasToolConnectionNotifier,
      NasToolConnection?,
      String
    >((ref, sourceId) => NasToolConnectionNotifier(sourceId));

class NasToolConnectionNotifier extends StateNotifier<NasToolConnection?> {
  NasToolConnectionNotifier(this.sourceId) : super(null);

  final String sourceId;

  /// 连接到 NASTool
  Future<NasToolConnection> connect(SourceEntity source) async {
    logger.i('NasToolProvider: 连接到 ${source.name}');

    final adapter = NasToolAdapter();

    state = NasToolConnection(
      source: source,
      adapter: adapter,
      status: NasToolConnectionStatus.connecting,
    );

    // 从 extraConfig 中获取密码（添加源时存储在 extraConfig['password'] 中）
    final password = source.extraConfig?['password'] as String?;
    final config = ServiceConnectionConfig.fromSource(
      source,
      password: password,
    );
    logger.d(
      'NasToolProvider: 连接配置 - username: ${config.username}, password: ${config.password != null ? '***' : 'null'}, extraConfig: ${config.extraConfig?.keys}',
    );

    try {
      final result = await adapter.connect(config);

      final connection = result.when(
        success: (_) => NasToolConnection(
          source: source,
          adapter: adapter,
          status: NasToolConnectionStatus.connected,
        ),
        failure: (error) => NasToolConnection(
          source: source,
          adapter: adapter,
          status: NasToolConnectionStatus.error,
          errorMessage: error,
        ),
      );

      state = connection;
      return connection;
    } on Exception catch (e) {
      final connection = NasToolConnection(
        source: source,
        adapter: adapter,
        status: NasToolConnectionStatus.error,
        errorMessage: e.toString(),
      );
      state = connection;
      return connection;
    }
  }

  /// 断开连接
  Future<void> disconnect() async {
    final connection = state;
    if (connection != null) {
      await connection.adapter.disconnect();
      state = null;
      logger.i('NasToolProvider: 断开连接 $sourceId');
    }
  }

  /// 获取适配器
  NasToolAdapter? get adapter => state?.adapter;
}

/// NASTool 综合统计 Provider
final nastoolStatsProvider = FutureProvider.family
    .autoDispose<NasToolOverviewStats?, String>((ref, sourceId) async {
      final connection = ref.watch(nastoolConnectionProvider(sourceId));
      if (connection == null ||
          connection.status != NasToolConnectionStatus.connected) {
        return null;
      }

      try {
        final adapter = connection.adapter;

        // 并行获取各项数据
        final results = await Future.wait([
          adapter.getLibraryStatistics().catchError(
            (_) => const NtLibraryStatistics(movieCount: 0, tvCount: 0),
          ),
          adapter.getAllSubscribes().catchError((_) => <NtSubscribe>[]),
          adapter.getDownloadTasks().catchError((_) => <NtDownloadTask>[]),
        ]);

        final stats = results[0] as NtLibraryStatistics;
        final subscribes = results[1] as List<NtSubscribe>;
        final downloads = results[2] as List<NtDownloadTask>;

        final activeDownloads = downloads.where((t) => !t.isCompleted).length;
        final completedDownloads = downloads.where((t) => t.isCompleted).length;

        return NasToolOverviewStats(
          movieCount: stats.movieCount,
          tvCount: stats.tvCount,
          animeCount: stats.animeCount ?? 0,
          subscribeCount: subscribes.length,
          activeDownloads: activeDownloads,
          completedDownloads: completedDownloads,
        );
      } on Exception catch (e) {
        logger.e('NasToolProvider: 获取统计失败', e);
        return null;
      }
    });

/// NASTool 订阅列表 Provider
final nastoolSubscribesProvider = FutureProvider.family
    .autoDispose<List<NtSubscribe>, String>((ref, sourceId) async {
      final connection = ref.watch(nastoolConnectionProvider(sourceId));
      if (connection == null ||
          connection.status != NasToolConnectionStatus.connected) {
        return [];
      }

      try {
        return await connection.adapter.getAllSubscribes();
      } on Exception catch (e) {
        logger.e('NasToolProvider: 获取订阅列表失败', e);
        return [];
      }
    });

/// NASTool 下载任务 Provider
final nastoolDownloadsProvider = FutureProvider.family
    .autoDispose<List<NtDownloadTask>, String>((ref, sourceId) async {
      final connection = ref.watch(nastoolConnectionProvider(sourceId));
      if (connection == null ||
          connection.status != NasToolConnectionStatus.connected) {
        return [];
      }

      try {
        return await connection.adapter.getDownloadTasks();
      } on Exception catch (e) {
        logger.e('NasToolProvider: 获取下载任务失败', e);
        return [];
      }
    });

/// NASTool 站点列表 Provider
final nastoolSitesProvider = FutureProvider.family
    .autoDispose<List<NtSite>, String>((ref, sourceId) async {
      final connection = ref.watch(nastoolConnectionProvider(sourceId));
      if (connection == null ||
          connection.status != NasToolConnectionStatus.connected) {
        return [];
      }

      try {
        return await connection.adapter.getSites();
      } on Exception catch (e) {
        logger.e('NasToolProvider: 获取站点列表失败', e);
        return [];
      }
    });

/// NASTool 转移历史 Provider
final nastoolTransferHistoryProvider = FutureProvider.family
    .autoDispose<List<NtTransferHistory>, String>((ref, sourceId) async {
      final connection = ref.watch(nastoolConnectionProvider(sourceId));
      if (connection == null ||
          connection.status != NasToolConnectionStatus.connected) {
        return [];
      }

      try {
        return await connection.adapter.getTransferHistory();
      } on Exception catch (e) {
        logger.e('NasToolProvider: 获取转移历史失败', e);
        return [];
      }
    });

/// NASTool 站点统计 Provider
final nastoolSiteStatisticsProvider = FutureProvider.family
    .autoDispose<List<NtSiteStatistics>, String>((ref, sourceId) async {
      final connection = ref.watch(nastoolConnectionProvider(sourceId));
      if (connection == null ||
          connection.status != NasToolConnectionStatus.connected) {
        return [];
      }

      try {
        return await connection.adapter.getSiteStatistics();
      } on Exception catch (e) {
        logger.e('NasToolProvider: 获取站点统计失败', e);
        return [];
      }
    });

/// NASTool 下载历史 Provider
final nastoolDownloadHistoryProvider = FutureProvider.family
    .autoDispose<List<NtDownloadHistory>, String>((ref, sourceId) async {
      final connection = ref.watch(nastoolConnectionProvider(sourceId));
      if (connection == null ||
          connection.status != NasToolConnectionStatus.connected) {
        return [];
      }

      try {
        return await connection.adapter.getDownloadHistory();
      } on Exception catch (e) {
        logger.e('NasToolProvider: 获取下载历史失败', e);
        return [];
      }
    });

/// NASTool 刷流任务 Provider
final nastoolBrushTasksProvider = FutureProvider.family
    .autoDispose<List<NtBrushTask>, String>((ref, sourceId) async {
      final connection = ref.watch(nastoolConnectionProvider(sourceId));
      if (connection == null ||
          connection.status != NasToolConnectionStatus.connected) {
        return [];
      }

      try {
        return await connection.adapter.getBrushTasks();
      } on Exception catch (e) {
        logger.e('NasToolProvider: 获取刷流任务失败', e);
        return [];
      }
    });

/// NASTool RSS 任务 Provider
final nastoolRssTasksProvider = FutureProvider.family
    .autoDispose<List<NtRssTask>, String>((ref, sourceId) async {
      final connection = ref.watch(nastoolConnectionProvider(sourceId));
      if (connection == null ||
          connection.status != NasToolConnectionStatus.connected) {
        return [];
      }

      try {
        return await connection.adapter.getRssTasks();
      } on Exception catch (e) {
        logger.e('NasToolProvider: 获取RSS任务失败', e);
        return [];
      }
    });

/// NASTool RSS 解析器 Provider
final nastoolRssParsersProvider = FutureProvider.family
    .autoDispose<List<NtRssParser>, String>((ref, sourceId) async {
      final connection = ref.watch(nastoolConnectionProvider(sourceId));
      if (connection == null ||
          connection.status != NasToolConnectionStatus.connected) {
        return [];
      }

      try {
        return await connection.adapter.getRssParsers();
      } on Exception catch (e) {
        logger.e('NasToolProvider: 获取RSS解析器失败', e);
        return [];
      }
    });

/// NASTool 插件列表 Provider
final nastoolPluginsProvider = FutureProvider.family
    .autoDispose<List<NtPlugin>, String>((ref, sourceId) async {
      final connection = ref.watch(nastoolConnectionProvider(sourceId));
      if (connection == null ||
          connection.status != NasToolConnectionStatus.connected) {
        return [];
      }

      try {
        return await connection.adapter.getPlugins();
      } on Exception catch (e) {
        logger.e('NasToolProvider: 获取插件列表失败', e);
        return [];
      }
    });

/// NASTool 插件商店 Provider
final nastoolPluginAppsProvider = FutureProvider.family
    .autoDispose<List<NtPluginApp>, String>((ref, sourceId) async {
      final connection = ref.watch(nastoolConnectionProvider(sourceId));
      if (connection == null ||
          connection.status != NasToolConnectionStatus.connected) {
        return [];
      }

      try {
        return await connection.adapter.getPluginApps();
      } on Exception catch (e) {
        logger.e('NasToolProvider: 获取插件商店失败', e);
        return [];
      }
    });

/// NASTool 同步目录 Provider
final nastoolSyncDirsProvider = FutureProvider.family
    .autoDispose<List<NtSyncDir>, String>((ref, sourceId) async {
      final connection = ref.watch(nastoolConnectionProvider(sourceId));
      if (connection == null ||
          connection.status != NasToolConnectionStatus.connected) {
        return [];
      }

      try {
        final dirs = await connection.adapter.getSyncDirectories();
        return dirs
            .map(
              (d) => NtSyncDir(
                id: d.id,
                name: d.from,
                from: d.from,
                to: d.to,
                mode: d.syncMode,
                state: d.enabled,
              ),
            )
            .toList();
      } on Exception catch (e) {
        logger.e('NasToolProvider: 获取同步目录失败', e);
        return [];
      }
    });

/// NASTool 系统信息 Provider
final nastoolSystemInfoProvider = FutureProvider.family
    .autoDispose<NtSystemInfo, String>((ref, sourceId) async {
      final connection = ref.watch(nastoolConnectionProvider(sourceId));
      if (connection == null ||
          connection.status != NasToolConnectionStatus.connected) {
        return const NtSystemInfo();
      }

      try {
        final version = await connection.adapter.getSystemVersion();
        final space = await connection.adapter.getLibrarySpace();
        return NtSystemInfo(
          version: version.version,
          latestVersion: version.latestVersion,
          totalSpace: space.total,
          freeSpace: space.free,
        );
      } on Exception catch (e) {
        logger.e('NasToolProvider: 获取系统信息失败', e);
        return const NtSystemInfo();
      }
    });

/// NASTool 服务列表 Provider
final nastoolServicesProvider = FutureProvider.family
    .autoDispose<List<NtService>, String>((ref, sourceId) async => []);

/// NASTool 进程列表 Provider
final nastoolProcessesProvider = FutureProvider.family
    .autoDispose<List<NtProcess>, String>((ref, sourceId) async => []);

/// NASTool 操作 Provider
final nastoolActionsProvider = Provider.family<NasToolActions, String>(
  NasToolActions.new,
);

class NasToolActions {
  NasToolActions(this._ref, this._sourceId);

  final Ref _ref;
  final String _sourceId;

  NasToolAdapter? get _adapter =>
      _ref.read(nastoolConnectionProvider(_sourceId))?.adapter;

  NasToolAdapter _requireAdapter() {
    final adapter = _adapter;
    if (adapter == null) {
      throw Exception(appL10n.nastoolErrorNotConnected);
    }
    return adapter;
  }

  void _invalidateAll() {
    _ref
      ..invalidate(nastoolStatsProvider(_sourceId))
      ..invalidate(nastoolSubscribesProvider(_sourceId))
      ..invalidate(nastoolDownloadsProvider(_sourceId))
      ..invalidate(nastoolSitesProvider(_sourceId))
      ..invalidate(nastoolTransferHistoryProvider(_sourceId));
  }

  // === 订阅操作 ===

  /// 添加订阅
  Future<void> addSubscribe({
    required String name,
    required String type,
    String? year,
    String? mediaId,
    int? season,
  }) async {
    final adapter = _requireAdapter();

    await adapter.addSubscribe(
      name: name,
      type: type,
      year: year,
      mediaId: mediaId,
      season: season,
    );
    _ref.invalidate(nastoolSubscribesProvider(_sourceId));
  }

  /// 删除订阅
  Future<void> deleteSubscribe(int id, String type) async {
    final adapter = _requireAdapter();

    await adapter.deleteSubscribe(id, type);
    _ref.invalidate(nastoolSubscribesProvider(_sourceId));
  }

  /// 搜索订阅资源
  Future<void> searchSubscribe(int rssId, String type) async {
    final adapter = _requireAdapter();

    await adapter.searchSubscribe(rssId, type);
  }

  // === 搜索操作 ===

  /// 搜索资源
  Future<List<NtSearchResult>> searchResources(String keyword) async {
    final adapter = _requireAdapter();

    return adapter.searchResources(keyword);
  }

  /// 搜索资源（返回分组结果）
  Future<List<NtMediaSearchResult>> searchMediaResources(String keyword) async {
    final adapter = _requireAdapter();

    return adapter.searchMediaResources(keyword);
  }

  // === 下载操作 ===

  /// 下载资源
  Future<void> downloadResource({
    required String enclosure,
    required String title,
  }) async {
    final adapter = _requireAdapter();

    await adapter.downloadResource(enclosure: enclosure, title: title);
    _ref.invalidate(nastoolDownloadsProvider(_sourceId));
  }

  /// 开始下载任务
  Future<void> startDownload(String id) async {
    final adapter = _requireAdapter();

    await adapter.startDownload(id);
    _ref.invalidate(nastoolDownloadsProvider(_sourceId));
  }

  /// 停止下载任务
  Future<void> stopDownload(String id) async {
    final adapter = _requireAdapter();

    await adapter.stopDownload(id);
    _ref.invalidate(nastoolDownloadsProvider(_sourceId));
  }

  /// 删除下载任务
  Future<void> removeDownload(String id) async {
    final adapter = _requireAdapter();

    await adapter.removeDownload(id);
    _ref.invalidate(nastoolDownloadsProvider(_sourceId));
  }

  // === 站点操作 ===

  /// 测试站点连接
  Future<bool> testSite(int id) async {
    final adapter = _requireAdapter();

    return adapter.testSite(id);
  }

  // === 刷流操作 ===

  /// 运行刷流任务
  Future<void> runBrushTask(int id) async {
    final adapter = _requireAdapter();

    await adapter.runBrushTask(id);
  }

  /// 获取刷流任务种子列表
  Future<List<NtBrushTorrent>> getBrushTaskTorrents(String id) async {
    final adapter = _requireAdapter();

    return adapter.getBrushTaskTorrents(id);
  }

  // === RSS 操作 ===

  /// 预览 RSS 任务文章
  Future<List<NtRssArticle>> previewRssTask(int id) async {
    final adapter = _requireAdapter();

    return adapter.previewRssTask(id);
  }

  // === 插件操作 ===

  /// 安装插件
  Future<void> installPlugin(int id) async {
    final adapter = _requireAdapter();

    await adapter.installPlugin(id);
    _ref.invalidate(nastoolPluginsProvider(_sourceId));
  }

  /// 卸载插件
  Future<void> uninstallPlugin(int id) async {
    final adapter = _requireAdapter();

    await adapter.uninstallPlugin(id);
    _ref.invalidate(nastoolPluginsProvider(_sourceId));
  }

  // === 同步操作 ===

  /// 运行同步目录
  Future<void> runSyncDir(int id) async {
    final adapter = _requireAdapter();

    await adapter.runSyncDirectory(id);
  }

  /// 获取同步历史。
  ///
  /// NAStool 服务端 API 未提供该端点，按项目约定抛 [UnsupportedError]——而非
  /// 静默返回空列表被 UI 误读成「没有数据」。调用方应 catch 后隐藏入口或显示
  /// 「该 NAStool API 不支持」提示。
  Future<List<NtSyncHistory>> getSyncHistory(int dirId) async =>
      throw UnsupportedError('当前 NAStool API 不支持查询同步历史');

  // === 系统操作 ===

  /// 刷新媒体库
  Future<void> refreshLibrary() async {
    final adapter = _requireAdapter();

    await adapter.refreshLibrary();
  }

  /// 重启服务
  Future<void> restartService() async {
    final adapter = _requireAdapter();

    await adapter.restartSystem();
  }

  /// 检查更新
  Future<bool> checkUpdate() async {
    final adapter = _requireAdapter();

    return adapter.checkUpdate();
  }

  /// 获取系统日志。
  ///
  /// NAStool 服务端 API 未提供该端点，按项目约定抛 [UnsupportedError]——而非
  /// 静默返回空列表被 UI 误读成「没有数据」。调用方应 catch 后隐藏入口或显示
  /// 「该 NAStool API 不支持」提示。
  Future<List<NtLogEntry>> getLogs({String level = 'INFO'}) async =>
      throw UnsupportedError('当前 NAStool API 不支持查询日志');

  /// 刷新所有数据
  void refreshAll() {
    _invalidateAll();
  }
}
