import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/services/media_scan_progress_service.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart'
    show MediaType;
import 'package:my_nas/features/transfer/domain/entities/transfer_task.dart';
import 'package:my_nas/features/transfer/presentation/providers/transfer_provider.dart';
import 'package:my_nas/features/video/data/services/video_scanner_service.dart';

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

/// 聚合所有活动项：传输队列 + 视频扫描 + 媒体扫描。
///
/// 直链下载 / 人脸识别 / 音乐刮削 / 云同步 暂未接入（保留 TODO 等后续补）。
final activityItemsProvider = Provider<List<ActivityItem>>((ref) {
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
        TransferType.upload => '上传',
        TransferType.download => '下载',
        TransferType.cache => '缓存',
      },
      icon: switch (task.type) {
        TransferType.upload => Icons.upload_rounded,
        TransferType.download => Icons.download_rounded,
        TransferType.cache => Icons.inventory_2_outlined,
      },
      label: task.fileName,
      detail: _xferStatus(task.status),
    ));
  }

  // 2) 视频扫描 / 刮削
  final videoScan = ref.watch(videoScanActivityProvider).valueOrNull;
  if (videoScan != null &&
      videoScan.phase != VideoScanPhase.completed &&
      videoScan.phase != VideoScanPhase.error) {
    items.add(ActivityItem(
      id: 'video.scan',
      group: videoScan.phase == VideoScanPhase.scraping ? '刮削' : '扫描',
      icon: videoScan.phase == VideoScanPhase.scraping
          ? Icons.auto_fix_high_rounded
          : Icons.image_search_rounded,
      label: '影视库 · ${videoScan.description}',
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
      MediaType.music => '音乐',
      MediaType.photo => '照片',
      MediaType.comic => '漫画',
      MediaType.book => '图书',
      _ => '媒体',
    };
    items.add(ActivityItem(
      id: 'media.scan.${mediaScan.mediaType.name}',
      group: '扫描',
      icon: switch (mediaScan.mediaType) {
        MediaType.music => Icons.library_music_outlined,
        MediaType.photo => Icons.photo_library_outlined,
        MediaType.comic => Icons.collections_bookmark_outlined,
        MediaType.book => Icons.menu_book_outlined,
        _ => Icons.image_search_rounded,
      },
      label: '$mediaLabel 库 · ${mediaScan.scannedCount}/${mediaScan.totalCount}',
      detail: mediaScan.currentFile ?? mediaScan.currentPath ?? '',
      progress: mediaScan.totalCount > 0
          ? mediaScan.scannedCount / mediaScan.totalCount
          : null,
    ));
  }

  return items;
});

String _xferStatus(TransferStatus s) => switch (s) {
      TransferStatus.transferring => '传输中',
      TransferStatus.queued => '排队',
      TransferStatus.paused => '已暂停',
      TransferStatus.pending => '等待',
      TransferStatus.failed => '失败',
      TransferStatus.completed => '已完成',
      TransferStatus.cancelled => '已取消',
    };
