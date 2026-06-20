import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/services/media_scan_progress_service.dart';
import 'package:my_nas/core/sync/cloud_sync_service.dart';
import 'package:my_nas/features/music/data/services/music_scrape_service.dart';
import 'package:my_nas/features/photo/data/services/face_recognition_service.dart';
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

/// 把活动项 [ActivityItem.id] 映射到桌面分支路由，供活动中心点击跳转。
/// 返回 null 表示该项无对应目标页（点击不响应）。
String? activityItemRoute(String id) {
  if (id.startsWith('xfer.')) return '/transfer';
  if (id == 'video.scan') return '/video';
  if (id.startsWith('media.scan.')) {
    final type = id.substring('media.scan.'.length);
    return switch (type) {
      'music' => '/music',
      'photo' => '/photo',
      'comic' || 'book' => '/reading',
      _ => null,
    };
  }
  if (id == 'face.recognition') return '/photo';
  if (id.startsWith('music.scrape.')) return '/music';
  if (id == 'cloud.sync') return '/mine';
  return null;
}

/// 视频扫描 / 刮削进度（订阅 [VideoScannerService.progressStream]）。
final videoScanActivityProvider = StreamProvider<VideoScanProgress?>(
  (ref) => VideoScannerService().progressStream,
);

/// 媒体扫描（音乐 / 照片 / 漫画 / 图书）进度。
final mediaScanActivityProvider = StreamProvider<MediaScanProgress?>(
  (ref) => MediaScanProgressService().progressStream,
);

/// 人脸识别进度（订阅 [FaceRecognitionService.progressStream]）。
final faceRecognitionActivityProvider = StreamProvider<FaceProcessProgress?>(
  (ref) => FaceRecognitionService().progressStream,
);

/// 音乐刮削进度（订阅 [MusicScrapeService.progressStream]）。
final musicScrapeActivityProvider = StreamProvider<MusicScrapeProgress?>(
  (ref) => MusicScrapeService().progressStream,
);

/// 云同步进度（订阅 [CloudSyncService.progressStream]）。
final cloudSyncActivityProvider = StreamProvider<CloudSyncProgress?>(
  (ref) => CloudSyncService.instance.progressStream,
);

/// 进行中的活动项计数（仅判空 / 角标用，不构造本地化文案，故无需 context）。
/// 顶栏通知红点 watch 此 provider，避免为了拿数量而依赖 [AppLocalizations]。
final activeActivityCountProvider = Provider<int>((ref) {
  var n = 0;

  final transfers = ref.watch(transferTasksProvider).tasks;
  n += transfers
      .where(
        (t) =>
            t.status != TransferStatus.completed &&
            t.status != TransferStatus.cancelled,
      )
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

  final face = ref.watch(faceRecognitionActivityProvider).valueOrNull;
  if (face != null && face.status == FaceProcessStatus.processing) {
    n++;
  }

  final musicScrape = ref.watch(musicScrapeActivityProvider).valueOrNull;
  if (musicScrape != null &&
      (musicScrape.phase == MusicScrapePhase.preparing ||
          musicScrape.phase == MusicScrapePhase.scraping)) {
    n++;
  }

  final cloudSync = ref.watch(cloudSyncActivityProvider).valueOrNull;
  if (cloudSync != null &&
      (cloudSync.phase == CloudSyncPhase.preparing ||
          cloudSync.phase == CloudSyncPhase.syncing)) {
    n++;
  }

  return n;
});

/// 聚合所有活动项：传输队列 + 视频扫描 + 媒体扫描 + 人脸识别 + 音乐刮削 + 云同步。
///
/// 文案需本地化，故做成普通函数由抽屉 widget 在 build 内调用（传入 [ref] 用于
/// watch、[l] 用于取本地化文案）。直链下载暂无独立服务（HTTP 直链下载功能尚未实现，
/// 现有下载聚合仅覆盖 aria2 / qBittorrent / Transmission，归在下载器页而非此处）。
List<ActivityItem> buildActivityItems(WidgetRef ref, AppLocalizations l) {
  final items = <ActivityItem>[];

  // 1) 传输队列（上传 / 下载 / 缓存）
  final transfers = ref.watch(transferTasksProvider).tasks;
  for (final task in transfers) {
    if (task.status == TransferStatus.completed ||
        task.status == TransferStatus.cancelled) {
      continue;
    }
    items.add(
      ActivityItem(
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
      ),
    );
  }

  // 2) 视频扫描 / 刮削
  final videoScan = ref.watch(videoScanActivityProvider).valueOrNull;
  if (videoScan != null &&
      videoScan.phase != VideoScanPhase.completed &&
      videoScan.phase != VideoScanPhase.error) {
    final isScraping = videoScan.phase == VideoScanPhase.scraping;
    // videoScan.description 是后端中文文案，直接展示会破坏 i18n；改用
    // 本地化的「进度计数 / 阶段名」拼到 actAggVideoLibraryLabel 模板。
    final scanDesc = videoScan.totalCount > 0
        ? '${videoScan.scannedCount}/${videoScan.totalCount}'
        : (isScraping ? l.actAggGroupScrape : l.actAggGroupScan);
    items.add(
      ActivityItem(
        id: 'video.scan',
        group: isScraping ? l.actAggGroupScrape : l.actAggGroupScan,
        icon: isScraping
            ? Icons.auto_fix_high_rounded
            : Icons.image_search_rounded,
        label: l.actAggVideoLibraryLabel(scanDesc),
        detail: videoScan.currentFile ?? videoScan.currentPath ?? '',
        progress: videoScan.progress > 0 ? videoScan.progress : null,
      ),
    );
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
    items.add(
      ActivityItem(
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
        progress: mediaScan.totalCount > 0 && mediaScan.scannedCount > 0
            ? mediaScan.scannedCount / mediaScan.totalCount
            : null,
      ),
    );
  }

  // 4) 人脸识别
  final face = ref.watch(faceRecognitionActivityProvider).valueOrNull;
  if (face != null && face.status == FaceProcessStatus.processing) {
    items.add(
      ActivityItem(
        id: 'face.recognition',
        group: l.actAggGroupFaceRecognition,
        icon: Icons.face_retouching_natural_rounded,
        label: l.actAggFaceLabel(face.processed, face.total),
        detail: face.currentFile ?? '',
        progress: face.progress > 0 ? face.progress : null,
      ),
    );
  }

  // 5) 音乐刮削
  final musicScrape = ref.watch(musicScrapeActivityProvider).valueOrNull;
  if (musicScrape != null &&
      (musicScrape.phase == MusicScrapePhase.preparing ||
          musicScrape.phase == MusicScrapePhase.scraping)) {
    items.add(
      ActivityItem(
        id: 'music.scrape.${musicScrape.sourceId}',
        group: l.actAggGroupScrape,
        icon: Icons.album_rounded,
        label: l.actAggMusicScrapeLabel(
          musicScrape.processedCount,
          musicScrape.totalCount,
        ),
        detail: musicScrape.currentTrack ?? musicScrape.pathPrefix,
        progress: musicScrape.progress > 0 ? musicScrape.progress : null,
      ),
    );
  }

  // 6) 云同步
  final cloudSync = ref.watch(cloudSyncActivityProvider).valueOrNull;
  if (cloudSync != null &&
      (cloudSync.phase == CloudSyncPhase.preparing ||
          cloudSync.phase == CloudSyncPhase.syncing)) {
    items.add(
      ActivityItem(
        id: 'cloud.sync',
        group: l.actAggGroupCloudSync,
        icon: Icons.cloud_sync_rounded,
        label: cloudSync.total > 0
            ? l.actAggCloudSyncLabel(cloudSync.processed, cloudSync.total)
            : l.actAggCloudSyncPreparing,
        detail: cloudSync.currentModule ?? '',
        progress: cloudSync.progress > 0 ? cloudSync.progress : null,
      ),
    );
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
