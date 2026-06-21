import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/service_adapters/base/service_adapter.dart';
import 'package:my_nas/service_adapters/transmission/api/transmission_api.dart';

/// Transmission 服务适配器
///
/// 提供 Transmission 下载客户端的连接和管理功能
class TransmissionAdapter implements ServiceAdapter {
  TransmissionAdapter();

  TransmissionApi? _api;
  ServiceConnectionConfig? _connection;

  @override
  ServiceAdapterInfo get info => ServiceAdapterInfo(
        name: 'Transmission',
        type: SourceType.transmission,
        version: _api?.version != null && _api?.rpcVersion != null
            ? '${_api!.version} (RPC: ${_api!.rpcVersion})'
            : _api?.version,
        description: appL10n.transmissionAdapterDescription,
      );

  @override
  bool get isConnected => _api?.isConnected ?? false;

  @override
  ServiceConnectionConfig? get connection => _connection;

  /// 获取 API 客户端
  TransmissionApi? get api => _api;

  @override
  Future<ServiceConnectionResult> connect(ServiceConnectionConfig config) async {
    try {
      // 从 extraConfig 中获取 RPC 路径
      final rpcPath = config.extraConfig?['rpcPath'] as String? ?? '/transmission/rpc';

      _api = TransmissionApi(
        baseUrl: config.baseUrl,
        rpcPath: rpcPath,
        username: config.username,
        password: config.password,
      );

      // 尝试连接
      final success = await _api!.connect();
      if (!success) {
        _api?.dispose();
        _api = null;
        return ServiceConnectionFailure(appL10n.transmissionConnectionFailed);
      }

      _connection = config;
      return ServiceConnectionSuccess(this);
    } on TransmissionApiException catch (e) {
      _api?.dispose();
      _api = null;
      return ServiceConnectionFailure(e.message);
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'connectToTransmission');
      _api?.dispose();
      _api = null;
      return ServiceConnectionFailure(appL10n.transmissionConnectionFailedWithException(e));
    }
  }

  @override
  Future<void> disconnect() async {
    _api?.dispose();
    _api = null;
    _connection = null;
  }

  @override
  Future<void> dispose() async {
    await disconnect();
  }

  // === 种子管理方法 ===

  /// 获取所有种子列表
  Future<List<TransmissionTorrent>> getTorrents({List<int>? ids}) async {
    _ensureConnected();
    return _api!.torrentGet(ids: ids);
  }

  /// 添加种子（通过 URL 或 Magnet 链接）
  Future<TransmissionTorrentAdded> addTorrent(
    String url, {
    String? downloadDir,
    bool paused = false,
  }) async {
    _ensureConnected();
    return _api!.torrentAdd(
      filename: url,
      downloadDir: downloadDir,
      paused: paused,
    );
  }

  /// 添加种子文件（Base64 编码）
  Future<TransmissionTorrentAdded> addTorrentFile(
    String metainfo, {
    String? downloadDir,
    bool paused = false,
  }) async {
    _ensureConnected();
    return _api!.torrentAdd(
      metainfo: metainfo,
      downloadDir: downloadDir,
      paused: paused,
    );
  }

  /// 开始种子
  Future<void> startTorrents(List<int> ids) async {
    _ensureConnected();
    await _api!.torrentStart(ids);
  }

  /// 开始所有种子
  Future<void> startAllTorrents() async {
    _ensureConnected();
    await _api!.torrentStartAll();
  }

  /// 停止种子
  Future<void> stopTorrents(List<int> ids) async {
    _ensureConnected();
    await _api!.torrentStop(ids);
  }

  /// 停止所有种子
  Future<void> stopAllTorrents() async {
    _ensureConnected();
    await _api!.torrentStopAll();
  }

  /// 删除种子
  Future<void> removeTorrents(
    List<int> ids, {
    bool deleteFiles = false,
  }) async {
    _ensureConnected();
    await _api!.torrentRemove(ids, deleteLocalData: deleteFiles);
  }

  /// 验证种子数据
  Future<void> verifyTorrents(List<int> ids) async {
    _ensureConnected();
    await _api!.torrentVerify(ids);
  }

  /// 获取会话统计
  Future<TransmissionSessionStats> getSessionStats() async {
    _ensureConnected();
    return _api!.sessionStats();
  }

  /// 获取下载统计
  Future<TransmissionDownloadStats> getDownloadStats() async {
    _ensureConnected();

    final torrents = await _api!.torrentGet();
    final stats = await _api!.sessionStats();

    var downloading = 0;
    var seeding = 0;
    var stopped = 0;
    var completed = 0;
    var error = 0;

    for (final torrent in torrents) {
      if (torrent.hasError) {
        error++;
      } else if (torrent.isStopped) {
        stopped++;
      } else if (torrent.isSeeding) {
        seeding++;
        completed++;
      } else if (torrent.isDownloading) {
        downloading++;
      }

      if (torrent.isComplete && !torrent.isSeeding) {
        completed++;
      }
    }

    return TransmissionDownloadStats(
      totalTorrents: torrents.length,
      downloading: downloading,
      seeding: seeding,
      stopped: stopped,
      completed: completed,
      error: error,
      downloadSpeed: stats.downloadSpeed,
      uploadSpeed: stats.uploadSpeed,
    );
  }

  void _ensureConnected() {
    if (!isConnected) {
      throw TransmissionApiException(appL10n.transmissionAdapterNotConnected);
    }
  }
}

/// 下载统计信息
class TransmissionDownloadStats {
  const TransmissionDownloadStats({
    required this.totalTorrents,
    required this.downloading,
    required this.seeding,
    required this.stopped,
    required this.completed,
    required this.error,
    required this.downloadSpeed,
    required this.uploadSpeed,
  });

  final int totalTorrents;
  final int downloading;
  final int seeding;
  final int stopped;
  final int completed;
  final int error;
  final int downloadSpeed;
  final int uploadSpeed;
}
