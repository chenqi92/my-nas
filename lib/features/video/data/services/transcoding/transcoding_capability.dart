import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/video/domain/entities/video_quality.dart';

/// 转码能力枚举
enum TranscodingCapability {
  /// 服务端转码（NAS设备如 Synology、QNAP 等）
  serverSide,

  /// 客户端 FFmpeg 转码
  clientSide,

  /// 不支持转码（只能播放原画）
  none,
}

/// 转码能力检测服务
class TranscodingCapabilityService {
  /// 检测源类型的转码能力
  TranscodingCapability getCapability(SourceType sourceType) =>
      switch (sourceType) {
        // NAS 设备支持服务端转码
        SourceType.synology => TranscodingCapability.serverSide,
        SourceType.qnap => TranscodingCapability.serverSide,
        // 绿联(UGOS)和飞牛(fnOS) NAS：原生转码能力封装在各自的影视中心/飞牛影视
        // 闭源应用内部，未公开可调用的服务端转码/转封装 HTTP 接口（现有适配器仅覆盖
        // 文件管理类端点，且均为逆向试探得到）。在缺乏可靠公开转码 API 前，统一降级为
        // 客户端 FFmpeg 转码以保证可播放。若官方/社区给出确切转码端点，可新增对应
        // serverSide 转码服务并改回 serverSide。
        SourceType.ugreen => TranscodingCapability.clientSide,
        SourceType.fnos => TranscodingCapability.clientSide,
        // 媒体服务器支持服务端转码
        SourceType.jellyfin => TranscodingCapability.serverSide,
        SourceType.emby => TranscodingCapability.serverSide,
        SourceType.plex => TranscodingCapability.serverSide,
        // 通用协议使用客户端转码
        SourceType.smb => TranscodingCapability.clientSide,
        SourceType.ftp => TranscodingCapability.clientSide,
        SourceType.sftp => TranscodingCapability.clientSide,
        SourceType.s3 => TranscodingCapability.clientSide,
        SourceType.webdav => TranscodingCapability.clientSide,
        SourceType.nfs => TranscodingCapability.none,
        SourceType.local => TranscodingCapability.clientSide,
        // UPnP/DLNA 设备通常自己处理转码，客户端不需要
        SourceType.upnp => TranscodingCapability.none,
        // 下载工具和媒体管理服务不涉及视频转码
        SourceType.qbittorrent => TranscodingCapability.none,
        SourceType.transmission => TranscodingCapability.none,
        SourceType.aria2 => TranscodingCapability.none,
        SourceType.trakt => TranscodingCapability.none,
        SourceType.nastool => TranscodingCapability.none,
        SourceType.moviepilot => TranscodingCapability.none,
        // PT 站点和字幕站点不涉及视频转码
        SourceType.ptSite => TranscodingCapability.none,
        SourceType.opensubtitles => TranscodingCapability.none,
      };

  /// 检测是否支持清晰度切换
  bool supportsQualitySwitch(SourceType sourceType) {
    final capability = getCapability(sourceType);
    return capability != TranscodingCapability.none;
  }

  /// 获取转码能力描述
  String getCapabilityDescription(
    TranscodingCapability capability,
  ) => switch (capability) {
    TranscodingCapability.serverSide => appL10n.transcodingCapabilityServerSide,
    TranscodingCapability.clientSide => appL10n.transcodingCapabilityClientSide,
    TranscodingCapability.none => appL10n.transcodingCapabilityNone,
  };

  /// 获取不支持转码时的提示信息
  String getUnsupportedMessage(SourceType sourceType) =>
      appL10n.transcodingUnsupportedMessage(sourceType.displayName);
}

/// 转码配置
class TranscodingProfile {
  const TranscodingProfile({
    required this.quality,
    this.videoCodec = 'h264',
    this.audioCodec = 'aac',
    this.container = 'mp4',
    this.subtitlePath,
    this.burnSubtitle = false,
  });

  /// 目标清晰度
  final VideoQuality quality;

  /// 视频编码
  final String videoCodec;

  /// 音频编码
  final String audioCodec;

  /// 容器格式
  final String container;

  /// 字幕文件路径（用于烧录）
  final String? subtitlePath;

  /// 是否烧录字幕
  final bool burnSubtitle;

  /// 获取 FFmpeg 视频滤镜参数
  String? get videoFilter {
    final filters = <String>[];

    // 缩放滤镜
    if (!quality.isOriginal &&
        quality.maxWidth != null &&
        quality.maxHeight != null) {
      filters.add(
        'scale=${quality.maxWidth}:${quality.maxHeight}:force_original_aspect_ratio=decrease',
      );
    }

    // 字幕烧录滤镜
    if (burnSubtitle && subtitlePath != null) {
      // 转义路径中的特殊字符
      final escapedPath = subtitlePath!
          .replaceAll(':', r'\:')
          .replaceAll("'", r"\'");
      filters.add("subtitles='$escapedPath'");
    }

    return filters.isNotEmpty ? filters.join(',') : null;
  }

  /// 获取估算的目标码率
  int? get targetBitrate => quality.estimatedBitrate;

  TranscodingProfile copyWith({
    VideoQuality? quality,
    String? videoCodec,
    String? audioCodec,
    String? container,
    String? subtitlePath,
    bool? burnSubtitle,
  }) => TranscodingProfile(
    quality: quality ?? this.quality,
    videoCodec: videoCodec ?? this.videoCodec,
    audioCodec: audioCodec ?? this.audioCodec,
    container: container ?? this.container,
    subtitlePath: subtitlePath ?? this.subtitlePath,
    burnSubtitle: burnSubtitle ?? this.burnSubtitle,
  );
}

/// 转码状态
enum TranscodingStatus {
  /// 空闲
  idle,

  /// 准备中
  preparing,

  /// 转码中
  transcoding,

  /// 完成
  completed,

  /// 错误
  error,
}

/// 转码进度信息
class TranscodingProgress {
  const TranscodingProgress({
    required this.status,
    this.progress = 0.0,
    this.speed,
    this.eta,
    this.errorMessage,
  });

  /// 状态
  final TranscodingStatus status;

  /// 进度 (0.0 - 1.0)
  final double progress;

  /// 转码速度 (例如 "2.5x")
  final String? speed;

  /// 预计剩余时间
  final Duration? eta;

  /// 错误信息
  final String? errorMessage;

  /// 是否正在转码
  bool get isTranscoding => status == TranscodingStatus.transcoding;

  /// 是否已完成
  bool get isCompleted => status == TranscodingStatus.completed;

  /// 是否有错误
  bool get hasError => status == TranscodingStatus.error;

  TranscodingProgress copyWith({
    TranscodingStatus? status,
    double? progress,
    String? speed,
    Duration? eta,
    String? errorMessage,
  }) => TranscodingProgress(
    status: status ?? this.status,
    progress: progress ?? this.progress,
    speed: speed ?? this.speed,
    eta: eta ?? this.eta,
    errorMessage: errorMessage ?? this.errorMessage,
  );
}
