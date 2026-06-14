import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/services/media_scan_progress_service.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart'
    show MediaType;
import 'package:my_nas/features/transfer/domain/entities/transfer_task.dart';
import 'package:my_nas/features/transfer/presentation/providers/transfer_provider.dart';
import 'package:my_nas/features/video/data/services/video_scanner_service.dart';
import 'package:my_nas/l10n/app_localizations.dart';

/// 活动中心一条聚合项。来源可能是传输 / 直链下载 / 媒体扫描 / 视频刮削 /
/// 音乐刮削 / 人脸识别 / 云同步。
class ActivityItem {
  const ActivityItem({
    required this.id,
    required this.group,
    required this.icon,
    required this.label,
    required this.detail,
    this.progress,
  });

  final String id;
  final String group;
  final IconData icon;
  final String label;
  final String detail;

  /// 0..1，null 表示未知 / 不展示进度条。
  final double? progress;
}

/// 视频扫描 / 刮削进度（订阅 [VideoScannerService.progressStream]）。
final videoScanActivityProvider = StreamProvider<VideoScanProgress?>((ref) {
  return VideoScannerService().progressStream;
});

/// 媒体扫描（音乐 / 照片 / 漫画 / 图书）进度。
final mediaScanActivityProvider = StreamProvider<MediaScanProgress?>((ref) {
  return MediaScanProgressService().progressStream;
});

/// 进行中的活动项计数（仅判空 / 角标用，不构造本地化文案，故无需 context）。
/// 顶栏通知红点 watch 此 provider，避免为了拿数量而依赖 [AppLocalizations]。
final activeActivityCountProvider = Provider<int>((ref) {
  var n = 0;

  final transfers = ref.watch(transferTasksProvider).tasks;
  n += transfers
      .where((t) =>
          t.status != TransferStatus.completed &&
          t.status != TransferStatus.cancelled)
      .length;

  final videoScan = ref.watch(videoScanActivityProvider).valueOrNull;
  if (videoScan != null &&
      videoScan.phase != VideoScanPhase.completed &&
      videoScan.phase != VideoScanPhase.error) {
    n++;
  }

  final mediaScan = ref.watch(mediaScanActivityProvider).valueOrNull;
  if (mediaScan != null &&
      mediaScan.phase != MediaScanPhase.completed &&
      mediaScan.phase != MediaScanPhase.error &&
      mediaScan.phase != MediaScanPhase.idle) {
    n++;
  }

  return n;
});

/// 聚合所有活动项：传输队列 + 视频扫描 + 媒体扫描。
///
/// 文案需本地化，故做成普通函数由抽屉 widget 在 build 内调用（传入 [ref] 用于
/// watch、[l] 用于取本地化文案）；直链下载 / 人脸识别 / 音乐刮削 / 云同步 暂未接入。
List<ActivityItem> buildActivityItems(WidgetRef ref, AppLocalizations l) {
  final items = <ActivityItem>[];

  // 1) 传输队列（上传 / 下载 / 缓存）
  final transfers = ref.watch(transferTasksProvider).tasks;
  for (final task in transfers) {
    if (task.status == TransferStatus.completed ||
        task.status == TransferStatus.cancelled) {
      continue;
    }
    items.add(ActivityItem(
      id: 'xfer.${task.id}',
      group: switch (task.type) {
        TransferType.upload => l.actAggGroupUpload,
        TransferType.download => l.actAggGroupDownload,
        TransferType.cache => l.actAggGroupCache,
      },
      icon: switch (task.type) {
        TransferType.upload => Icons.upload_rounded,
        TransferType.download => Icons.download_rounded,
        TransferType.cache => Icons.inventory_2_outlined,
      },
      label: task.fileName,
      detail: _xferStatus(l, task.status),
    ));
  }

  // 2) 视频扫描 / 刮削
  final videoScan = ref.watch(videoScanActivityProvider).valueOrNull;
  if (videoScan != null &&
      videoScan.phase != VideoScanPhase.completed &&
      videoScan.phase != VideoScanPhase.error) {
    items.add(ActivityItem(
      id: 'video.scan',
      group: videoScan.phase == VideoScanPhase.scraping
          ? l.actAggGroupScrape
          : l.actAggGroupScan,
      icon: videoScan.phase == VideoScanPhase.scraping
          ? Icons.auto_fix_high_rounded
          : Icons.image_search_rounded,
      label: l.actAggVideoLibraryLabel(videoScan.description),
      detail: videoScan.currentFile ?? videoScan.currentPath ?? '',
      progress: videoScan.progress > 0 ? videoScan.progress : null,
    ));
  }

  // 3) 媒体扫描（音乐 / 照片 / 漫画 / 图书）
  final mediaScan = ref.watch(mediaScanActivityProvider).valueOrNull;
  if (mediaScan != null &&
      mediaScan.phase != MediaScanPhase.completed &&
      mediaScan.phase != MediaScanPhase.error &&
      mediaScan.phase != MediaScanPhase.idle) {
    final mediaLabel = switch (mediaScan.mediaType) {
      MediaType.music => l.actAggMediaMusic,
      MediaType.photo => l.actAggMediaPhoto,
      MediaType.comic => l.actAggMediaComic,
      MediaType.book => l.actAggMediaBook,
      _ => l.actAggMediaGeneric,
    };
    items.add(ActivityItem(
      id: 'media.scan.${mediaScan.mediaType.name}',
      group: l.actAggGroupScan,
      icon: switch (mediaScan.mediaType) {
        MediaType.music => Icons.library_music_outlined,
        MediaType.photo => Icons.photo_library_outlined,
        MediaType.comic => Icons.collections_bookmark_outlined,
        MediaType.book => Icons.menu_book_outlined,
        _ => Icons.image_search_rounded,
      },
      label: l.actAggMediaLibraryLabel(
        mediaLabel,
        mediaScan.scannedCount,
        mediaScan.totalCount,
      ),
      detail: mediaScan.currentFile ?? mediaScan.currentPath ?? '',
      progress: mediaScan.totalCount > 0
          ? mediaScan.scannedCount / mediaScan.totalCount
          : null,
    ));
  }

  return items;
}

String _xferStatus(AppLocalizations l, TransferStatus s) => switch (s) {
      TransferStatus.transferring => l.actAggStatusTransferring,
      TransferStatus.queued => l.actAggStatusQueued,
      TransferStatus.paused => l.actAggStatusPaused,
      TransferStatus.pending => l.actAggStatusPending,
      TransferStatus.failed => l.actAggStatusFailed,
      TransferStatus.completed => l.actAggStatusCompleted,
      TransferStatus.cancelled => l.actAggStatusCancelled,
    };
