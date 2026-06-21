import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/service_adapters/base/service_adapter.dart';
import 'package:my_nas/service_adapters/moviepilot/api/moviepilot_api.dart';

/// MoviePilot 服务适配器
///
/// 提供 MoviePilot 影视自动化管理服务的连接与管理能力。
/// 基于 [MoviePilotApi]（MoviePilot v2 API），使用 X-API-KEY 认证。
///
/// 仅暴露 [MoviePilotApi] 实际提供的能力：连接校验、系统信息、订阅、
/// 搜索、下载任务、转移历史。
class MoviePilotAdapter implements ServiceAdapter {
  MoviePilotAdapter();

  MoviePilotApi? _api;
  ServiceConnectionConfig? _connection;
  MoviePilotSystemInfo? _systemInfo;
  bool _connected = false;

  @override
  ServiceAdapterInfo get info => ServiceAdapterInfo(
        name: 'MoviePilot',
        type: SourceType.moviepilot,
        version: _systemInfo?.version,
        // 适配器无专属 l10n key，沿用源类型描述（影视自动化管理工具）。
        description: SourceType.moviepilot.description,
      );

  @override
  bool get isConnected => _connected && (_api?.isAuthenticated ?? false);

  @override
  ServiceConnectionConfig? get connection => _connection;

  /// 获取 API 客户端
  MoviePilotApi? get api => _api;

  /// 系统信息（连接成功后可用）
  MoviePilotSystemInfo? get systemInfo => _systemInfo;

  @override
  Future<ServiceConnectionResult> connect(
    ServiceConnectionConfig config,
  ) async {
    try {
      // API Token 存储在 extraConfig['apiToken']（添加源表单的非标准字段），
      // 兼容 apiKey 字段以增强健壮性。
      final apiToken = (config.extraConfig?['apiToken'] as String?) ??
          config.apiKey ??
          '';

      if (apiToken.isEmpty) {
        return ServiceConnectionFailure(appL10n.moviepilotApiAuthFailed);
      }

      _api = MoviePilotApi(
        baseUrl: config.baseUrl,
        apiToken: apiToken,
      );

      // 校验连接（GET /api/v1/system/env）。
      final ok = await _api!.validateConnection();
      if (!ok) {
        _api?.dispose();
        _api = null;
        return ServiceConnectionFailure(appL10n.moviepilotApiAuthFailed);
      }

      // 获取系统信息（失败不影响连接）。
      try {
        _systemInfo = await _api!.getSystemInfo();
      } on Exception catch (e, st) {
        AppError.ignore(e, st, '系统信息获取失败不影响连接');
      }

      _connected = true;
      _connection = config;
      return ServiceConnectionSuccess(this);
    } on MoviePilotApiException catch (e) {
      _api?.dispose();
      _api = null;
      _connected = false;
      return ServiceConnectionFailure(e.message);
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'connectToMoviePilot');
      _api?.dispose();
      _api = null;
      _connected = false;
      return ServiceConnectionFailure(
        appL10n.moviepilotApiConnectionError(e.toString()),
      );
    }
  }

  @override
  Future<void> disconnect() async {
    _api?.dispose();
    _api = null;
    _connection = null;
    _systemInfo = null;
    _connected = false;
  }

  @override
  Future<void> dispose() async {
    await disconnect();
  }

  // === 数据获取能力（以 MoviePilotApi 实际提供的方法为准） ===

  /// 获取系统信息
  Future<MoviePilotSystemInfo> getSystemInfo() async {
    _ensureConnected();
    return _api!.getSystemInfo();
  }

  /// 获取订阅列表
  Future<List<MoviePilotSubscribe>> getSubscribes() async {
    _ensureConnected();
    return _api!.getSubscribes();
  }

  /// 添加订阅
  Future<bool> addSubscribe({
    required String name,
    required String mediaType,
    int? tmdbId,
    int? season,
  }) async {
    _ensureConnected();
    return _api!.addSubscribe(
      name: name,
      mediaType: mediaType,
      tmdbId: tmdbId,
      season: season,
    );
  }

  /// 删除订阅
  Future<bool> deleteSubscribe(int subscribeId) async {
    _ensureConnected();
    return _api!.deleteSubscribe(subscribeId);
  }

  /// 搜索资源
  Future<List<MoviePilotSearchResult>> searchResources({
    required String keyword,
    String? mediaType,
    int page = 1,
  }) async {
    _ensureConnected();
    return _api!.searchResources(
      keyword: keyword,
      mediaType: mediaType,
      page: page,
    );
  }

  /// 获取下载任务列表
  Future<List<MoviePilotDownloadTask>> getDownloadTasks() async {
    _ensureConnected();
    return _api!.getDownloadTasks();
  }

  /// 获取转移历史
  Future<List<MoviePilotTransferHistory>> getTransferHistory({
    int page = 1,
    int count = 20,
  }) async {
    _ensureConnected();
    return _api!.getTransferHistory(page: page, count: count);
  }

  /// 综合概况统计（订阅数 / 活动下载 / 完成下载）。
  Future<MoviePilotOverviewStats> getOverviewStats() async {
    _ensureConnected();

    var subscribeCount = 0;
    var activeDownloads = 0;
    var completedDownloads = 0;

    try {
      subscribeCount = (await _api!.getSubscribes()).length;
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '订阅统计获取失败');
    }

    try {
      final downloads = await _api!.getDownloadTasks();
      for (final t in downloads) {
        final progress = t.progress ?? 0;
        if (progress >= 100) {
          completedDownloads++;
        } else {
          activeDownloads++;
        }
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '下载任务统计获取失败');
    }

    return MoviePilotOverviewStats(
      subscribeCount: subscribeCount,
      activeDownloads: activeDownloads,
      completedDownloads: completedDownloads,
    );
  }

  void _ensureConnected() {
    if (!isConnected) {
      throw const MoviePilotApiException('MoviePilot 未连接');
    }
  }
}

/// MoviePilot 概况统计
class MoviePilotOverviewStats {
  const MoviePilotOverviewStats({
    required this.subscribeCount,
    required this.activeDownloads,
    required this.completedDownloads,
  });

  final int subscribeCount;
  final int activeDownloads;
  final int completedDownloads;
}
