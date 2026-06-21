import 'dart:async';
import 'package:my_nas/core/i18n/app_l10n.dart';

import 'package:my_nas/features/sources/domain/entities/media_library.dart';

/// 媒体扫描进度
///
/// 统一的扫描进度模型，支持所有媒体类型
class MediaScanProgress {
  const MediaScanProgress({
    required this.mediaType,
    required this.phase,
    this.sourceId,
    this.pathPrefix,
    this.currentPath,
    this.scannedCount = 0,
    this.totalCount = 0,
    this.currentFile,
  });

  /// 媒体类型
  final MediaType mediaType;

  /// 扫描阶段
  final MediaScanPhase phase;

  /// 源ID（用于区分不同目录的进度）
  final String? sourceId;

  /// 目录路径前缀（用于区分不同目录的进度）
  final String? pathPrefix;

  /// 当前扫描的路径
  final String? currentPath;

  /// 已扫描数量
  final int scannedCount;

  /// 总数量
  final int totalCount;

  /// 当前处理的文件名
  final String? currentFile;

  /// 计算进度百分比
  double get progress {
    if (totalCount == 0) return 0;
    return scannedCount / totalCount;
  }

  /// 进度描述
  String get description {
    switch (phase) {
      case MediaScanPhase.idle:
        return appL10n.mediaScanProgressPhaseIdleDesc;
      case MediaScanPhase.scanning:
        return currentPath ?? appL10n.mediaScanProgressPhaseScanningDesc;
      case MediaScanPhase.processing:
        if (currentFile != null) {
          return appL10n.mediaScanProgressPhaseProcessingDescWithFile(currentFile ?? '', scannedCount, totalCount);
        }
        return appL10n.mediaScanProgressPhaseProcessingDesc(scannedCount, totalCount);
      case MediaScanPhase.saving:
        return appL10n.mediaScanProgressPhaseSavingDesc(scannedCount, totalCount);
      case MediaScanPhase.completed:
        return appL10n.mediaScanProgressPhaseCompletedDesc(scannedCount);
      case MediaScanPhase.error:
        return appL10n.mediaScanProgressPhaseErrorDesc;
    }
  }

  /// 检查进度是否属于指定目录
  bool belongsTo(String sourceId, String pathPrefix) => this.sourceId == sourceId && this.pathPrefix == pathPrefix;
}

/// 扫描阶段
enum MediaScanPhase {
  /// 空闲
  idle,

  /// 扫描文件系统
  scanning,

  /// 处理中（提取元数据等）
  processing,

  /// 保存到数据库
  saving,

  /// 完成
  completed,

  /// 错误
  error,
}

/// 媒体扫描进度服务
///
/// 统一管理所有媒体类型的扫描进度，提供：
/// 1. 按目录独立的进度追踪
/// 2. 广播流供 UI 监听
/// 3. 当前扫描状态查询
class MediaScanProgressService {
  factory MediaScanProgressService() => _instance ??= MediaScanProgressService._();

  MediaScanProgressService._();

  static MediaScanProgressService? _instance;

  /// 扫描进度流
  final _progressController = StreamController<MediaScanProgress>.broadcast();

  Stream<MediaScanProgress> get progressStream => _progressController.stream;

  /// 当前正在扫描的目录集合 {mediaType: {sourceId:pathPrefix}}
  final Map<MediaType, Set<String>> _scanningPaths = {};

  /// 检查指定目录是否正在扫描
  bool isScanning(MediaType mediaType, String sourceId, String pathPrefix) {
    final key = '$sourceId:$pathPrefix';
    return _scanningPaths[mediaType]?.contains(key) ?? false;
  }

  /// 检查指定媒体类型是否有任何目录正在扫描
  bool isAnyScanning(MediaType mediaType) => _scanningPaths[mediaType]?.isNotEmpty ?? false;

  /// 开始扫描（标记目录为扫描中）
  void startScan(MediaType mediaType, String sourceId, String pathPrefix) {
    final key = '$sourceId:$pathPrefix';
    _scanningPaths.putIfAbsent(mediaType, () => {});
    _scanningPaths[mediaType]!.add(key);

    emitProgress(MediaScanProgress(
      mediaType: mediaType,
      phase: MediaScanPhase.scanning,
      sourceId: sourceId,
      pathPrefix: pathPrefix,
    ));
  }

  /// 结束扫描（移除目录的扫描标记）
  void endScan(MediaType mediaType, String sourceId, String pathPrefix, {bool success = true}) {
    final key = '$sourceId:$pathPrefix';
    _scanningPaths[mediaType]?.remove(key);

    emitProgress(MediaScanProgress(
      mediaType: mediaType,
      phase: success ? MediaScanPhase.completed : MediaScanPhase.error,
      sourceId: sourceId,
      pathPrefix: pathPrefix,
    ));
  }

  /// 发送进度更新
  void emitProgress(MediaScanProgress progress) {
    _progressController.add(progress);
  }

  /// 释放资源
  void dispose() {
    _progressController.close();
  }
}
