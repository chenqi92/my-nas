import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/service_adapters/base/service_adapter.dart';
import 'package:my_nas/service_adapters/nastool/api/nastool_api.dart';
import 'package:my_nas/service_adapters/nastool/models/models.dart';

/// NASTool 服务适配器
///
/// 使用用户名密码进行会话认证
class NasToolAdapter implements ServiceAdapter {
  NasToolAdapter();

  NasToolApi? _api;
  ServiceConnectionConfig? _connection;
  NtSystemVersion? _systemVersion;

  @override
  ServiceAdapterInfo get info => ServiceAdapterInfo(
        name: 'NASTool',
        type: SourceType.nastool,
        version: _systemVersion?.version,
        description: appL10n.nastoolAdapterDescription,
      );

  @override
  bool get isConnected => _api?.isAuthenticated ?? false;

  @override
  ServiceConnectionConfig? get connection => _connection;

  /// 获取 API 客户端
  NasToolApi? get api => _api;

  /// 获取系统版本
  NtSystemVersion? get systemVersion => _systemVersion;

  /// 当前用户名
  String? get username => _api?.username;

  @override
  Future<ServiceConnectionResult> connect(ServiceConnectionConfig config) async {
    try {
      _api = NasToolApi(baseUrl: config.baseUrl);

      // 检查认证类型
      final authType = config.extraConfig?['authType'] as String? ?? appL10n.nastoolAuthTypeDefault;

      if (authType == 'API Token') {
        // API Token 认证
        final apiToken = config.apiKey ?? config.extraConfig?['apiToken'] as String?;

        if (apiToken == null || apiToken.isEmpty) {
          return ServiceConnectionFailure(appL10n.nastoolErrorMissingApiToken);
        }

        final valid = await _api!.validateApiToken(apiToken);

        if (!valid) {
          _api?.dispose();
          _api = null;
          return ServiceConnectionFailure(appL10n.nastoolErrorInvalidApiToken);
        }
      } else {
        // 用户名密码认证
        final username = config.username ?? config.extraConfig?['username'] as String?;
        final password = config.password ?? config.extraConfig?['password'] as String?;

        // Debug logging
        AppError.ignore(
          Exception('Debug: username=$username, password=${password != null ? '***' : 'null'}, config.password=${config.password != null}, extraConfig.password=${config.extraConfig?['password'] != null}'),
          StackTrace.current,
          appL10n.nastoolDebugConnectionInfo,
        );

        if (username == null || username.isEmpty) {
          return ServiceConnectionFailure(appL10n.nastoolErrorMissingUsername);
        }

        if (password == null || password.isEmpty) {
          return ServiceConnectionFailure(appL10n.nastoolErrorMissingPassword);
        }

        // 登录认证
        final loginResult = await _api!.login(username, password);

        final failureMessage = loginResult.when(
          success: (_, _) => null,
          failure: (message) => message,
        );

        if (failureMessage != null) {
          _api?.dispose();
          _api = null;
          return ServiceConnectionFailure(failureMessage);
        }
      }

      // 获取系统版本
      try {
        _systemVersion = await _api!.getSystemVersion();
      } on Exception catch (e, st) {
        AppError.ignore(e, st, appL10n.nastoolIgnoreSystemVersionFailed);
      }

      _connection = config;
      return ServiceConnectionSuccess(this);
    } on NasToolApiException catch (e) {
      _api?.dispose();
      _api = null;
      return ServiceConnectionFailure(e.message);
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'connectToNasTool');
      _api?.dispose();
      _api = null;
      return ServiceConnectionFailure(appL10n.nastoolErrorConnectionFailed(e));
    }
  }

  @override
  Future<void> disconnect() async {
    await _api?.logout();
    _api?.dispose();
    _api = null;
    _connection = null;
    _systemVersion = null;
  }

  @override
  Future<void> dispose() async {
    await disconnect();
  }

  // === 媒体库方法 ===

  /// 获取媒体库统计
  Future<NtLibraryStatistics> getLibraryStatistics() async {
    _ensureConnected();
    return _api!.getLibraryStatistics();
  }

  /// 获取媒体库空间
  Future<NtLibrarySpace> getLibrarySpace() async {
    _ensureConnected();
    return _api!.getLibrarySpace();
  }

  // === 订阅方法 ===

  /// 获取所有订阅
  Future<List<NtSubscribe>> getAllSubscribes() async {
    _ensureConnected();
    return _api!.getAllSubscribes();
  }

  /// 添加订阅
  Future<void> addSubscribe({
    required String name,
    required String type,
    String? year,
    String? mediaId,
    int? season,
    String? keyword,
  }) async {
    _ensureConnected();
    await _api!.addSubscribe(
      name: name,
      type: type,
      year: year,
      mediaId: mediaId,
      season: season,
      keyword: keyword,
    );
  }

  /// 删除订阅
  Future<void> deleteSubscribe(int subscribeId, String type) async {
    _ensureConnected();
    await _api!.deleteSubscribe(rssId: subscribeId, type: type);
  }

  // === 搜索方法 ===

  /// 搜索资源
  Future<List<NtSearchResult>> searchResources(String keyword) async {
    _ensureConnected();
    await _api!.searchKeyword(searchWord: keyword);
    // 等待搜索完成
    await Future<void>.delayed(const Duration(seconds: 2));
    return _api!.getSearchResult();
  }

  /// 搜索资源（返回分组结果）
  Future<List<NtMediaSearchResult>> searchMediaResources(String keyword) async {
    _ensureConnected();
    await _api!.searchKeyword(searchWord: keyword);
    // 等待搜索完成
    await Future<void>.delayed(const Duration(seconds: 2));
    return _api!.getMediaSearchResults();
  }

  /// 获取当前搜索结果（分组格式）
  Future<List<NtMediaSearchResult>> getMediaSearchResults() async {
    _ensureConnected();
    return _api!.getMediaSearchResults();
  }

  // === 下载方法 ===

  /// 下载资源
  Future<void> downloadResource({
    required String enclosure,
    required String title,
    String? dlDir,
  }) async {
    _ensureConnected();
    await _api!.downloadItem(enclosure: enclosure, title: title, dlDir: dlDir);
  }

  /// 获取下载任务列表
  Future<List<NtDownloadTask>> getDownloadTasks() async {
    _ensureConnected();
    return _api!.getDownloading();
  }

  // === 转移历史方法 ===

  /// 获取转移历史
  Future<List<NtTransferHistory>> getTransferHistory({int page = 1, int pageNum = 20}) async {
    _ensureConnected();
    return _api!.getTransferHistory(page: page, pageNum: pageNum);
  }

  // === 站点方法 ===

  /// 获取站点列表
  Future<List<NtSite>> getSites() async {
    _ensureConnected();
    return _api!.listSites();
  }

  /// 获取站点统计
  Future<List<NtSiteStatistics>> getSiteStatistics() async {
    _ensureConnected();
    return _api!.getSiteStatistics();
  }

  // === 媒体方法 ===

  /// 搜索媒体
  Future<List<NtMediaDetail>> searchMedia(String keyword) async {
    _ensureConnected();
    return _api!.searchMedia(keyword);
  }

  /// 获取推荐列表
  Future<List<NtMediaDetail>> getRecommendList({
    required String type,
    required String subtype,
    int page = 1,
  }) async {
    _ensureConnected();
    return _api!.getRecommendList(type: type, subtype: subtype, page: page);
  }

  // === 系统方法 ===

  /// 刷新媒体库
  Future<void> refreshLibrary() async {
    _ensureConnected();
    await _api!.startLibrarySync();
  }

  /// 获取系统版本
  Future<NtSystemVersion> getSystemVersion() async {
    _ensureConnected();
    return _api!.getSystemVersion();
  }

  /// 重启系统
  Future<void> restartSystem() async {
    _ensureConnected();
    await _api!.restartSystem();
  }

  /// 检查更新
  Future<bool> checkUpdate() async {
    _ensureConnected();
    final version = await _api!.getSystemVersion();
    return version.hasUpdate ?? false;
  }

  // === 下载历史方法 ===

  /// 获取下载历史
  Future<List<NtDownloadHistory>> getDownloadHistory({int page = 1}) async {
    _ensureConnected();
    return _api!.getDownloadHistory(page);
  }

  /// 开始下载任务
  Future<void> startDownload(String id) async {
    _ensureConnected();
    await _api!.startDownload(id);
  }

  /// 停止下载任务
  Future<void> stopDownload(String id) async {
    _ensureConnected();
    await _api!.stopDownload(id);
  }

  /// 删除下载任务
  Future<void> removeDownload(String id) async {
    _ensureConnected();
    await _api!.removeDownload(id);
  }

  // === 订阅搜索方法 ===

  /// 搜索订阅资源
  Future<void> searchSubscribe(int rssId, String type) async {
    _ensureConnected();
    await _api!.searchSubscribe(rssId, type);
  }

  // === 刷流任务方法 ===

  /// 获取刷流任务列表
  Future<List<NtBrushTask>> getBrushTasks() async {
    _ensureConnected();
    return _api!.listBrushTasks();
  }

  /// 运行刷流任务
  Future<void> runBrushTask(int id) async {
    _ensureConnected();
    await _api!.runBrushTask(id);
  }

  /// 获取刷流任务种子列表
  Future<List<NtBrushTorrent>> getBrushTaskTorrents(String id) async {
    _ensureConnected();
    return _api!.getBrushTaskTorrents(id);
  }

  // === RSS 方法 ===

  /// 获取 RSS 任务列表
  Future<List<NtRssTask>> getRssTasks() async {
    _ensureConnected();
    return _api!.listRssTasks();
  }

  /// 获取 RSS 解析器列表
  Future<List<NtRssParser>> getRssParsers() async {
    _ensureConnected();
    return _api!.listRssParsers();
  }

  /// 预览 RSS 任务
  Future<List<NtRssArticle>> previewRssTask(int id) async {
    _ensureConnected();
    return _api!.previewRssTask(id);
  }

  // === 插件方法 ===

  /// 获取已安装插件列表
  Future<List<NtPlugin>> getPlugins() async {
    _ensureConnected();
    return _api!.listPlugins();
  }

  /// 获取插件市场列表
  Future<List<NtPluginApp>> getPluginApps() async {
    _ensureConnected();
    return _api!.getPluginApps();
  }

  /// 安装插件
  Future<void> installPlugin(int id) async {
    _ensureConnected();
    await _api!.installPlugin(id);
  }

  /// 卸载插件
  Future<void> uninstallPlugin(int id) async {
    _ensureConnected();
    await _api!.uninstallPlugin(id);
  }

  // === 同步目录方法 ===

  /// 获取同步目录列表
  Future<List<NtSyncDirectory>> getSyncDirectories() async {
    _ensureConnected();
    return _api!.listSyncDirectories();
  }

  /// 运行同步目录
  Future<void> runSyncDirectory(int id) async {
    _ensureConnected();
    // NASTool API 没有直接运行同步目录的方法，使用 runService
    await _api!.runService('sync');
  }

  // === 站点测试方法 ===

  /// 测试站点连接
  Future<bool> testSite(int id) async {
    _ensureConnected();
    return _api!.testSite(id);
  }

  void _ensureConnected() {
    if (!isConnected) {
      throw NasToolApiException(appL10n.nastoolErrorNotConnected);
    }
  }
}

/// 综合统计信息
class NasToolOverviewStats {
  const NasToolOverviewStats({
    required this.movieCount,
    required this.tvCount,
    this.animeCount = 0,
    required this.subscribeCount,
    required this.activeDownloads,
    required this.completedDownloads,
  });

  final int movieCount;
  final int tvCount;
  final int animeCount;
  final int subscribeCount;
  final int activeDownloads;
  final int completedDownloads;

  int get totalMediaCount => movieCount + tvCount + animeCount;
}
