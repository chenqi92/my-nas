import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/aria2/presentation/providers/aria2_provider.dart';
import 'package:my_nas/features/qbittorrent/presentation/providers/qbittorrent_provider.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/transmission/presentation/providers/transmission_provider.dart';
import 'package:my_nas/l10n/app_localizations.dart';

/// 跨 aria2 / qBittorrent / Transmission 的统一任务抽象。三客户端各有各的
/// 模型（Aria2Download / QBTorrent / TransmissionTorrent），这里归一化成一个
/// 给桌面「下载器」表 + 运维总览吞吐 + 下载详情浮层共用的视图模型。
enum UnifiedDownloadStatus { downloading, seeding, paused, completed, waiting, error }

extension UnifiedDownloadStatusX on UnifiedDownloadStatus {
  String label(AppLocalizations l) => switch (this) {
        UnifiedDownloadStatus.downloading => l.downloadStatusDownloading,
        UnifiedDownloadStatus.seeding => l.downloadStatusSeeding,
        UnifiedDownloadStatus.paused => l.downloadStatusPaused,
        UnifiedDownloadStatus.completed => l.downloadStatusCompleted,
        UnifiedDownloadStatus.waiting => l.downloadStatusWaiting,
        UnifiedDownloadStatus.error => l.downloadStatusError,
      };
}

/// 桌面下载器顶部状态筛选 chip（与设计稿对齐）。枚举值与显示标签解耦：
/// [label] 取本地化文案，[matches] 是纯逻辑匹配，互不影响。
enum DownloadStatusFilter { all, downloading, seeding, paused, completed }

extension DownloadStatusFilterX on DownloadStatusFilter {
  String label(AppLocalizations l) => switch (this) {
        DownloadStatusFilter.all => l.downloadFilterAll,
        DownloadStatusFilter.downloading => l.downloadStatusDownloading,
        DownloadStatusFilter.seeding => l.downloadStatusSeeding,
        DownloadStatusFilter.paused => l.downloadStatusPaused,
        DownloadStatusFilter.completed => l.downloadStatusCompleted,
      };

  bool matches(UnifiedDownloadStatus status) => switch (this) {
        DownloadStatusFilter.all => true,
        DownloadStatusFilter.downloading =>
          status == UnifiedDownloadStatus.downloading ||
              status == UnifiedDownloadStatus.waiting,
        DownloadStatusFilter.seeding => status == UnifiedDownloadStatus.seeding,
        DownloadStatusFilter.paused => status == UnifiedDownloadStatus.paused,
        DownloadStatusFilter.completed =>
          status == UnifiedDownloadStatus.completed,
      };
}

class UnifiedDownloadTask {
  const UnifiedDownloadTask({
    required this.sourceId,
    required this.sourceName,
    required this.sourceType,
    required this.taskId,
    required this.name,
    required this.totalBytes,
    required this.completedBytes,
    required this.downloadSpeed,
    required this.uploadSpeed,
    required this.status,
    this.etaSeconds,
    this.savePath,
    this.ratio,
  });

  /// 来源 source 的 id（即各 family provider 的 key）。
  final String sourceId;
  final String sourceName;
  final SourceType sourceType;

  /// 客户端内部 id：aria2 gid / qB hash / Transmission id（字符串化）。
  final String taskId;
  final String name;
  final int totalBytes;
  final int completedBytes;
  final int downloadSpeed;
  final int uploadSpeed;
  final UnifiedDownloadStatus status;
  final int? etaSeconds;
  final String? savePath;
  final double? ratio;

  double get progress {
    if (totalBytes > 0) return (completedBytes / totalBytes).clamp(0.0, 1.0);
    return status == UnifiedDownloadStatus.completed ? 1.0 : 0.0;
  }

  /// 唯一 key（跨客户端拼 sourceId）。
  String get uniqueKey => '${sourceId}_$taskId';
}

/// 单个下载客户端的实时概况（运维总览 3 客户端卡片用）。
class DownloaderClient {
  const DownloaderClient({
    required this.source,
    required this.connected,
    required this.downloadSpeed,
    required this.uploadSpeed,
    required this.taskCount,
  });

  final SourceEntity source;
  final bool connected;
  final int downloadSpeed;
  final int uploadSpeed;
  final int taskCount;
}

/// 聚合吞吐：下行/上行速度合计 + 活动/总任务数 + 在线客户端数。
class DownloaderThroughput {
  const DownloaderThroughput({
    required this.downloadSpeed,
    required this.uploadSpeed,
    required this.activeCount,
    required this.totalCount,
    required this.connectedClients,
    required this.totalClients,
  });

  final int downloadSpeed;
  final int uploadSpeed;
  final int activeCount;
  final int totalCount;
  final int connectedClients;
  final int totalClients;

  static const empty = DownloaderThroughput(
    downloadSpeed: 0,
    uploadSpeed: 0,
    activeCount: 0,
    totalCount: 0,
    connectedClients: 0,
    totalClients: 0,
  );
}

/// 用存储凭据自动连接所有「下载工具」源。各页面只需 watch 一次，连接建立后
/// 三客户端各自的 auto-refresh provider 才会真正拉到数据（它们要求已连接）。
final downloaderBootstrapProvider =
    FutureProvider.autoDispose<void>((ref) async {
  final sources = ref.watch(downloadToolSourcesProvider);
  final manager = ref.read(sourceManagerProvider);

  for (final s in sources) {
    try {
      switch (s.type) {
        case SourceType.aria2:
          final conn = ref.read(aria2ConnectionProvider(s.id));
          if (conn?.status != Aria2ConnectionStatus.connected) {
            final secret = s.extraConfig?['rpcSecret'] as String?;
            await ref
                .read(aria2ConnectionProvider(s.id).notifier)
                .connect(s, rpcSecret: secret);
          }
        case SourceType.qbittorrent:
          final conn = ref.read(qbittorrentConnectionProvider(s.id));
          if (conn?.status != QBConnectionStatus.connected) {
            final cred = await manager.getCredential(s.id);
            await ref
                .read(qbittorrentConnectionProvider(s.id).notifier)
                .connect(s, password: cred?.password);
          }
        case SourceType.transmission:
          final conn = ref.read(transmissionConnectionProvider(s.id));
          if (conn?.status != TransmissionConnectionStatus.connected) {
            final cred = await manager.getCredential(s.id);
            await ref
                .read(transmissionConnectionProvider(s.id).notifier)
                .connect(s, password: cred?.password);
          }
        default:
          break;
      }
    } on Object {
      // 单个客户端连接失败不影响其它客户端；UI 通过连接状态自行降级。
    }
  }
});

/// 聚合三客户端任务为统一列表。watch 此 provider 会触发 bootstrap 连接。
final aggregatedDownloadTasksProvider =
    Provider.autoDispose<List<UnifiedDownloadTask>>((ref) {
  // 触发连接（忽略其 AsyncValue，仅借 watch 启动副作用）。
  ref.watch(downloaderBootstrapProvider);
  final sources = ref.watch(downloadToolSourcesProvider);

  final tasks = <UnifiedDownloadTask>[];
  for (final s in sources) {
    switch (s.type) {
      case SourceType.aria2:
        final list = ref.watch(aria2AutoRefreshProvider(s.id));
        for (final d in list) {
          tasks.add(UnifiedDownloadTask(
            sourceId: s.id,
            sourceName: s.displayName,
            sourceType: s.type,
            taskId: d.gid,
            name: d.name,
            totalBytes: d.totalLength,
            completedBytes: d.completedLength,
            downloadSpeed: d.downloadSpeed,
            uploadSpeed: d.uploadSpeed,
            status: _aria2Status(d.status, d.progress),
            savePath: d.dir,
          ));
        }
      case SourceType.qbittorrent:
        final list = ref.watch(qbittorrentAutoRefreshProvider(s.id));
        for (final t in list) {
          tasks.add(UnifiedDownloadTask(
            sourceId: s.id,
            sourceName: s.displayName,
            sourceType: s.type,
            taskId: t.hash,
            name: t.name,
            totalBytes: t.size,
            completedBytes: (t.size * t.progress).round(),
            downloadSpeed: t.dlSpeed,
            uploadSpeed: t.upSpeed,
            status: _qbStatus(t.state, t.progress),
            etaSeconds: t.eta,
            savePath: t.savePath,
            ratio: t.ratio,
          ));
        }
      case SourceType.transmission:
        final list = ref.watch(transmissionAutoRefreshProvider(s.id));
        for (final t in list) {
          tasks.add(UnifiedDownloadTask(
            sourceId: s.id,
            sourceName: s.displayName,
            sourceType: s.type,
            taskId: '${t.id}',
            name: t.name,
            totalBytes: t.totalSize,
            completedBytes: (t.totalSize * t.percentDone).round(),
            downloadSpeed: t.rateDownload,
            uploadSpeed: t.rateUpload,
            status: _transmissionStatus(t.status, t.percentDone),
            etaSeconds: t.eta,
            savePath: t.downloadDir,
          ));
        }
      default:
        break;
    }
  }
  return tasks;
});

/// 各下载客户端的实时概况（含未连接的，便于 UI 展示离线状态）。
final downloaderClientsProvider =
    Provider.autoDispose<List<DownloaderClient>>((ref) {
  final sources = ref.watch(downloadToolSourcesProvider);
  final tasks = ref.watch(aggregatedDownloadTasksProvider);

  return [
    for (final s in sources)
      DownloaderClient(
        source: s,
        connected: _isConnected(ref, s),
        downloadSpeed: tasks
            .where((t) => t.sourceId == s.id)
            .fold(0, (a, t) => a + t.downloadSpeed),
        uploadSpeed: tasks
            .where((t) => t.sourceId == s.id)
            .fold(0, (a, t) => a + t.uploadSpeed),
        taskCount: tasks.where((t) => t.sourceId == s.id).length,
      ),
  ];
});

/// 聚合吞吐（运维总览 / 下载器汇总条）。
final downloaderThroughputProvider =
    Provider.autoDispose<DownloaderThroughput>((ref) {
  final clients = ref.watch(downloaderClientsProvider);
  final tasks = ref.watch(aggregatedDownloadTasksProvider);
  if (clients.isEmpty) return DownloaderThroughput.empty;

  return DownloaderThroughput(
    downloadSpeed: clients.fold(0, (a, c) => a + c.downloadSpeed),
    uploadSpeed: clients.fold(0, (a, c) => a + c.uploadSpeed),
    activeCount: tasks
        .where((t) => t.status == UnifiedDownloadStatus.downloading)
        .length,
    totalCount: tasks.length,
    connectedClients: clients.where((c) => c.connected).length,
    totalClients: clients.length,
  );
});

bool _isConnected(Ref ref, SourceEntity s) => switch (s.type) {
      SourceType.aria2 => ref.watch(aria2ConnectionProvider(s.id))?.status ==
          Aria2ConnectionStatus.connected,
      SourceType.qbittorrent =>
        ref.watch(qbittorrentConnectionProvider(s.id))?.status ==
            QBConnectionStatus.connected,
      SourceType.transmission =>
        ref.watch(transmissionConnectionProvider(s.id))?.status ==
            TransmissionConnectionStatus.connected,
      _ => false,
    };

UnifiedDownloadStatus _aria2Status(String status, double progress) =>
    switch (status) {
      'active' =>
        progress >= 1 ? UnifiedDownloadStatus.seeding : UnifiedDownloadStatus.downloading,
      'waiting' => UnifiedDownloadStatus.waiting,
      'paused' => UnifiedDownloadStatus.paused,
      'complete' => UnifiedDownloadStatus.completed,
      'error' || 'removed' => UnifiedDownloadStatus.error,
      _ => UnifiedDownloadStatus.waiting,
    };

UnifiedDownloadStatus _qbStatus(String state, double progress) {
  final s = state.toLowerCase();
  if (s.contains('paused') || s.contains('stopped')) {
    return UnifiedDownloadStatus.paused;
  }
  if (s.contains('error') || s.contains('missingfiles')) {
    return UnifiedDownloadStatus.error;
  }
  // 校验 / 搬运 / 分配等过渡态先归为等待，避免 checkingUP（校验做种文件）
  // 被下面的 'up' 子串误判为做种。
  if (s.startsWith('checking') ||
      s == 'moving' ||
      s == 'allocating' ||
      s == 'checkingresumedata') {
    return UnifiedDownloadStatus.waiting;
  }
  // 做种：uploading / stalledUP / queuedUP / forcedUP（UP 后缀）。
  if (s == 'uploading' || s.endsWith('up')) {
    return UnifiedDownloadStatus.seeding;
  }
  if (s.contains('queued')) return UnifiedDownloadStatus.waiting;
  if (s.contains('dl') || s.contains('downloading') || s.contains('meta')) {
    return UnifiedDownloadStatus.downloading;
  }
  return progress >= 1
      ? UnifiedDownloadStatus.completed
      : UnifiedDownloadStatus.downloading;
}

UnifiedDownloadStatus _transmissionStatus(int status, double percentDone) =>
    switch (status) {
      0 => percentDone >= 1
          ? UnifiedDownloadStatus.completed
          : UnifiedDownloadStatus.paused,
      1 || 3 || 5 => UnifiedDownloadStatus.waiting,
      2 || 4 => UnifiedDownloadStatus.downloading,
      6 => UnifiedDownloadStatus.seeding,
      _ => UnifiedDownloadStatus.waiting,
    };

// ---- 格式化工具（下载相关页面共用） ----

String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  return '${size.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
}

String formatSpeed(int bytesPerSec) =>
    bytesPerSec <= 0 ? '0 B/s' : '${formatBytes(bytesPerSec)}/s';

String formatEta(int? seconds) {
  if (seconds == null || seconds <= 0 || seconds >= 8640000) return '—';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  if (h > 0) return '${h}h${m}m';
  if (m > 0) return '${m}m${s}s';
  return '${s}s';
}
