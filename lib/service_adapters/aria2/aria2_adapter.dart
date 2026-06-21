import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/service_adapters/aria2/api/aria2_api.dart';
import 'package:my_nas/service_adapters/base/service_adapter.dart';

/// Aria2 服务适配器
///
/// 提供 Aria2 下载工具的连接和管理功能
class Aria2Adapter implements ServiceAdapter {
  Aria2Adapter();

  Aria2Api? _api;
  ServiceConnectionConfig? _connection;

  @override
  ServiceAdapterInfo get info => ServiceAdapterInfo(
        name: 'Aria2',
        type: SourceType.aria2,
        version: _api?.version,
        description: appL10n.sourceTypeDescAria2,
      );

  @override
  bool get isConnected => _api?.isConnected ?? false;

  @override
  ServiceConnectionConfig? get connection => _connection;

  /// 获取 API 客户端
  Aria2Api? get api => _api;

  @override
  Future<ServiceConnectionResult> connect(ServiceConnectionConfig config) async {
    try {
      // 从 extraConfig 中获取 rpcSecret
      final rpcSecret = config.extraConfig?['rpcSecret'] as String?;

      _api = Aria2Api(
        baseUrl: config.baseUrl,
        rpcSecret: rpcSecret,
      );

      // 尝试连接
      final success = await _api!.connect();
      if (!success) {
        _api?.dispose();
        _api = null;
        return ServiceConnectionFailure(appL10n.aria2AdapterConnectionFailed);
      }

      _connection = config;
      return ServiceConnectionSuccess(this);
    } on Aria2ApiException catch (e) {
      _api?.dispose();
      _api = null;
      return ServiceConnectionFailure(e.message);
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'connectToAria2');
      _api?.dispose();
      _api = null;
      return ServiceConnectionFailure(appL10n.aria2AdapterConnectionFailedWithError(e.toString()));
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

  // === 下载管理方法 ===

  /// 获取所有下载列表
  Future<List<Aria2Download>> getDownloads() async {
    _ensureConnected();

    final active = await _api!.tellActive();
    final waiting = await _api!.tellWaiting(0, 100);
    final stopped = await _api!.tellStopped(0, 100);

    return [...active, ...waiting, ...stopped];
  }

  /// 获取活动下载列表
  Future<List<Aria2Download>> getActiveDownloads() async {
    _ensureConnected();
    return _api!.tellActive();
  }

  /// 获取下载状态
  Future<Aria2Download> getDownloadStatus(String gid) async {
    _ensureConnected();
    return _api!.tellStatus(gid);
  }

  /// 添加 URI 下载
  Future<String> addUri(
    List<String> uris, {
    String? dir,
    String? filename,
  }) async {
    _ensureConnected();

    final options = <String, dynamic>{};
    if (dir != null) options['dir'] = dir;
    if (filename != null) options['out'] = filename;

    return _api!.addUri(uris, options: options.isNotEmpty ? options : null);
  }

  /// 添加种子下载
  Future<String> addTorrent(String torrentBase64, {String? dir}) async {
    _ensureConnected();

    final options = <String, dynamic>{};
    if (dir != null) options['dir'] = dir;

    return _api!.addTorrent(
      torrentBase64,
      options: options.isNotEmpty ? options : null,
    );
  }

  /// 暂停下载
  Future<void> pauseDownload(String gid) async {
    _ensureConnected();
    await _api!.pause(gid);
  }

  /// 暂停所有下载
  Future<void> pauseAllDownloads() async {
    _ensureConnected();
    await _api!.pauseAll();
  }

  /// 恢复下载
  Future<void> resumeDownload(String gid) async {
    _ensureConnected();
    await _api!.unpause(gid);
  }

  /// 恢复所有下载
  Future<void> resumeAllDownloads() async {
    _ensureConnected();
    await _api!.unpauseAll();
  }

  /// 删除下载
  Future<void> removeDownload(String gid) async {
    _ensureConnected();
    await _api!.remove(gid);
  }

  /// 删除下载结果（从已完成列表中移除）
  Future<void> removeDownloadResult(String gid) async {
    _ensureConnected();
    await _api!.removeDownloadResult(gid);
  }

  /// 清除所有已完成/错误的下载
  Future<void> purgeDownloadResults() async {
    _ensureConnected();
    await _api!.purgeDownloadResult();
  }

  /// 获取全局统计信息
  Future<Aria2GlobalStat> getGlobalStat() async {
    _ensureConnected();
    return _api!.getGlobalStat();
  }

  /// 获取下载统计
  Future<Aria2DownloadStats> getDownloadStats() async {
    _ensureConnected();

    final globalStat = await _api!.getGlobalStat();

    return Aria2DownloadStats(
      numActive: globalStat.numActive,
      numWaiting: globalStat.numWaiting,
      numStopped: globalStat.numStopped,
      downloadSpeed: globalStat.downloadSpeed,
      uploadSpeed: globalStat.uploadSpeed,
    );
  }

  void _ensureConnected() {
    if (!isConnected) {
      throw Aria2ApiException(appL10n.aria2AdapterNotConnected);
    }
  }
}

/// 下载统计信息
class Aria2DownloadStats {
  const Aria2DownloadStats({
    required this.numActive,
    required this.numWaiting,
    required this.numStopped,
    required this.downloadSpeed,
    required this.uploadSpeed,
  });

  final int numActive;
  final int numWaiting;
  final int numStopped;
  final int downloadSpeed;
  final int uploadSpeed;

  int get totalDownloads => numActive + numWaiting + numStopped;
}
