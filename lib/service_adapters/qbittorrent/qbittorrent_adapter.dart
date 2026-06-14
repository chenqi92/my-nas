import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/service_adapters/base/service_adapter.dart';
import 'package:my_nas/service_adapters/qbittorrent/api/qbittorrent_api.dart';

/// qBittorrent 服务适配器
///
/// 提供 qBittorrent 下载客户端的连接和管理功能
class QBittorrentAdapter implements ServiceAdapter {
  QBittorrentAdapter();

  QBittorrentApi? _api;
  ServiceConnectionConfig? _connection;
  String? _appVersion;
  String? _apiVersion;

  @override
  ServiceAdapterInfo get info => ServiceAdapterInfo(
    name: 'qBittorrent',
    type: SourceType.qbittorrent,
    version: _appVersion != null && _apiVersion != null
        ? '$_appVersion (API: $_apiVersion)'
        : _appVersion,
    description: '开源远程下载客户端',
  );

  @override
  bool get isConnected => _api?.isAuthenticated ?? false;

  @override
  ServiceConnectionConfig? get connection => _connection;

  /// 获取 API 客户端
  QBittorrentApi? get api => _api;

  @override
  Future<ServiceConnectionResult> connect(
    ServiceConnectionConfig config,
  ) async {
    try {
      _api = QBittorrentApi(
        baseUrl: config.baseUrl,
        username: config.username,
        password: config.password,
        apiKey: config.apiKey,
      );

      // 尝试登录
      final success = await _api!.login();
      if (!success) {
        _api?.dispose();
        _api = null;
        return const ServiceConnectionFailure('登录失败');
      }

      // 获取版本信息
      try {
        _appVersion = await _api!.getAppVersion();
        _apiVersion = await _api!.getApiVersion();
      } on Exception catch (e, st) {
        AppError.ignore(e, st, '版本信息获取失败不影响连接');
      }

      _connection = config;
      return ServiceConnectionSuccess(this);
    } on QBittorrentApiException catch (e) {
      _api?.dispose();
      _api = null;
      return ServiceConnectionFailure(e.message);
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'connectToQBittorrent');
      _api?.dispose();
      _api = null;
      return ServiceConnectionFailure('连接失败: $e');
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      await _api?.logout();
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '登出失败，忽略错误');
    }
    _api?.dispose();
    _api = null;
    _connection = null;
    _appVersion = null;
    _apiVersion = null;
  }

  @override
  Future<void> dispose() async {
    await disconnect();
  }

  // === Torrent 管理方法 ===

  /// 获取所有 Torrent 列表
  Future<List<QBTorrent>> getTorrents({
    TorrentFilter? filter,
    String? category,
    String? tag,
    TorrentSort? sort,
    bool? reverse,
    int? limit,
    int? offset,
  }) async {
    _ensureConnected();
    return _api!.getTorrents(
      filter: filter?.value,
      category: category,
      tag: tag,
      sort: sort?.value,
      reverse: reverse,
      limit: limit,
      offset: offset,
    );
  }

  /// 获取 Torrent 详细属性
  Future<QBTorrentProperties> getTorrentProperties(String hash) async {
    _ensureConnected();
    return _api!.getTorrentProperties(hash);
  }

  /// 获取 Torrent 文件列表
  Future<List<QBTorrentFile>> getTorrentFiles(String hash) async {
    _ensureConnected();
    return _api!.getTorrentFiles(hash);
  }

  /// 添加 Torrent（通过 URL 或 Magnet 链接）
  Future<void> addTorrent(
    String url, {
    String? savePath,
    String? category,
    List<String>? tags,
    bool paused = false,
  }) async {
    _ensureConnected();
    await _api!.addTorrentByUrl(
      url,
      savePath: savePath,
      category: category,
      tags: tags,
      paused: paused,
    );
  }

  /// 暂停 Torrent
  Future<void> pauseTorrents(List<String> hashes) async {
    _ensureConnected();
    await _api!.pauseTorrents(hashes);
  }

  /// 暂停所有 Torrent
  Future<void> pauseAllTorrents() async {
    _ensureConnected();
    await _api!.pauseTorrents(['all']);
  }

  /// 恢复 Torrent
  Future<void> resumeTorrents(List<String> hashes) async {
    _ensureConnected();
    await _api!.resumeTorrents(hashes);
  }

  /// 恢复所有 Torrent
  Future<void> resumeAllTorrents() async {
    _ensureConnected();
    await _api!.resumeTorrents(['all']);
  }

  /// 删除 Torrent
  Future<void> deleteTorrents(
    List<String> hashes, {
    bool deleteFiles = false,
  }) async {
    _ensureConnected();
    await _api!.deleteTorrents(hashes, deleteFiles: deleteFiles);
  }

  /// 获取全局传输信息
  Future<QBTransferInfo> getTransferInfo() async {
    _ensureConnected();
    return _api!.getTransferInfo();
  }

  /// 获取下载统计
  Future<QBDownloadStats> getDownloadStats() async {
    _ensureConnected();

    final torrents = await _api!.getTorrents();
    final transferInfo = await _api!.getTransferInfo();

    var downloading = 0;
    var seeding = 0;
    var paused = 0;
    var completed = 0;
    var error = 0;

    for (final torrent in torrents) {
      if (torrent.hasError) {
        error++;
      } else if (torrent.isPaused) {
        paused++;
      } else if (torrent.isCompleted) {
        if (torrent.isUploading) {
          seeding++;
        }
        completed++;
      } else if (torrent.isDownloading) {
        downloading++;
      }
    }

    return QBDownloadStats(
      totalTorrents: torrents.length,
      downloading: downloading,
      seeding: seeding,
      paused: paused,
      completed: completed,
      error: error,
      downloadSpeed: transferInfo.dlInfoSpeed,
      uploadSpeed: transferInfo.upInfoSpeed,
      totalDownloaded: transferInfo.dlInfoData,
      totalUploaded: transferInfo.upInfoData,
    );
  }

  // === 分类管理 ===

  /// 获取所有分类
  Future<Map<String, QBCategory>> getCategories() async {
    _ensureConnected();
    return _api!.getCategories();
  }

  /// 创建分类
  Future<void> createCategory(String category, {String? savePath}) async {
    _ensureConnected();
    await _api!.createCategory(category, savePath: savePath);
  }

  /// 设置 Torrent 分类
  Future<void> setTorrentCategory(List<String> hashes, String category) async {
    _ensureConnected();
    await _api!.setTorrentCategory(hashes, category);
  }

  // === 标签管理 ===

  /// 获取所有标签
  Future<List<String>> getTags() async {
    _ensureConnected();
    return _api!.getTags();
  }

  /// 创建标签
  Future<void> createTags(List<String> tags) async {
    _ensureConnected();
    await _api!.createTags(tags);
  }

  /// 添加标签到 Torrent
  Future<void> addTorrentTags(List<String> hashes, List<String> tags) async {
    _ensureConnected();
    await _api!.addTorrentTags(hashes, tags);
  }

  /// 从 Torrent 移除标签
  Future<void> removeTorrentTags(List<String> hashes, List<String> tags) async {
    _ensureConnected();
    await _api!.removeTorrentTags(hashes, tags);
  }

  // === Torrent 管理 ===

  /// 重命名 Torrent
  Future<void> renameTorrent(String hash, String name) async {
    _ensureConnected();
    await _api!.renameTorrent(hash, name);
  }

  /// 设置 Torrent 保存位置
  Future<void> setTorrentLocation(List<String> hashes, String location) async {
    _ensureConnected();
    await _api!.setTorrentLocation(hashes, location);
  }

  // === 速度限制 ===

  /// 获取备用速度限制状态
  Future<bool> getAlternativeSpeedLimitsEnabled() async {
    _ensureConnected();
    return _api!.getAlternativeSpeedLimitsEnabled();
  }

  /// 切换备用速度限制
  Future<void> toggleAlternativeSpeedLimits() async {
    _ensureConnected();
    await _api!.toggleAlternativeSpeedLimits();
  }

  /// 获取应用偏好设置
  Future<QBPreferences> getPreferences() async {
    _ensureConnected();
    return _api!.getPreferences();
  }

  /// 设置全局限速
  Future<void> setGlobalSpeedLimits({int? dlLimit, int? upLimit}) async {
    _ensureConnected();
    final prefs = <String, dynamic>{};
    if (dlLimit != null) prefs['dl_limit'] = dlLimit;
    if (upLimit != null) prefs['up_limit'] = upLimit;
    if (prefs.isNotEmpty) {
      await _api!.setPreferences(prefs);
    }
  }

  /// 设置备用速度限速
  Future<void> setAlternativeSpeedLimits({int? dlLimit, int? upLimit}) async {
    _ensureConnected();
    final prefs = <String, dynamic>{};
    if (dlLimit != null) prefs['alt_dl_limit'] = dlLimit;
    if (upLimit != null) prefs['alt_up_limit'] = upLimit;
    if (prefs.isNotEmpty) {
      await _api!.setPreferences(prefs);
    }
  }

  void _ensureConnected() {
    if (!isConnected) {
      throw const QBittorrentApiException('未连接到 qBittorrent');
    }
  }
}

/// Torrent 过滤器
enum TorrentFilter {
  all('all'),
  downloading('downloading'),
  seeding('seeding'),
  completed('completed'),
  paused('paused'),
  active('active'),
  inactive('inactive'),
  resumed('resumed'),
  stalled('stalled'),
  stalledUploading('stalled_uploading'),
  stalledDownloading('stalled_downloading'),
  errored('errored');

  const TorrentFilter(this.value);

  final String value;
}

/// Torrent 排序方式
enum TorrentSort {
  name('name'),
  size('size'),
  progress('progress'),
  dlspeed('dlspeed'),
  upspeed('upspeed'),
  priority('priority'),
  numSeeds('num_seeds'),
  numLeechs('num_leechs'),
  ratio('ratio'),
  eta('eta'),
  state('state'),
  category('category'),
  tags('tags'),
  addedOn('added_on'),
  completionOn('completion_on');

  const TorrentSort(this.value);

  final String value;
}

/// 下载统计信息
class QBDownloadStats {
  const QBDownloadStats({
    required this.totalTorrents,
    required this.downloading,
    required this.seeding,
    required this.paused,
    required this.completed,
    required this.error,
    required this.downloadSpeed,
    required this.uploadSpeed,
    required this.totalDownloaded,
    required this.totalUploaded,
  });

  final int totalTorrents;
  final int downloading;
  final int seeding;
  final int paused;
  final int completed;
  final int error;
  final int downloadSpeed;
  final int uploadSpeed;
  final int totalDownloaded;
  final int totalUploaded;
}
