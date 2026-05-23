import 'package:my_nas/features/video/domain/entities/audio_capability.dart';
import 'package:my_nas/features/video/domain/entities/hdr_capability.dart';

/// 播放配置
///
/// 包含 HDR 和音频直通的配置，可以生成对应的 MPV 属性
class PlaybackConfiguration {
  const PlaybackConfiguration({
    this.hdrMode = HdrMode.auto,
    this.toneMappingMode = ToneMappingMode.auto,
    this.audioPassthroughMode = AudioPassthroughMode.auto,
    this.passthroughCodecs = const [],
    this.hdrComputePeak = true,
    this.targetPeak = 0,
  });

  /// HDR 模式
  final HdrMode hdrMode;

  /// 色调映射算法
  final ToneMappingMode toneMappingMode;

  /// 音频直通模式
  final AudioPassthroughMode audioPassthroughMode;

  /// 允许直通的编码格式
  final List<AudioCodec> passthroughCodecs;

  /// 是否动态计算 HDR 峰值亮度
  final bool hdrComputePeak;

  /// 目标峰值亮度 (nits)，0 表示自动
  final int targetPeak;

  /// 生成 MPV 属性
  Map<String, String> toMpvProperties() {
    final props = <String, String>{};

    // HDR 设置
    switch (hdrMode) {
      case HdrMode.passthrough:
        // 启用 HDR 直通，通知显示器切换色彩空间
        props['target-colorspace-hint'] = 'yes';

      case HdrMode.tonemapping:
        // 禁用直通，进行色调映射
        props['target-colorspace-hint'] = 'no';

        // 设置色调映射算法
        if (toneMappingMode != ToneMappingMode.auto) {
          props['tone-mapping'] = toneMappingMode.mpvValue;
        }

        // 动态计算峰值亮度
        if (hdrComputePeak) {
          props['hdr-compute-peak'] = 'yes';
        }

        // 设置目标峰值
        if (targetPeak > 0) {
          props['target-peak'] = targetPeak.toString();
        }

      case HdrMode.disabled:
        // 禁用所有 HDR 处理
        props['target-colorspace-hint'] = 'no';

      case HdrMode.auto:
        // 自动模式不设置任何属性，使用 MPV 默认行为
        break;
    }

    // 音频直通设置
    switch (audioPassthroughMode) {
      case AudioPassthroughMode.enabled:
        if (passthroughCodecs.isNotEmpty) {
          final codecs = passthroughCodecs.map((c) => c.mpvName).join(',');
          props['audio-spdif'] = codecs;
        }

      case AudioPassthroughMode.disabled:
        // 禁用直通，清空 audio-spdif
        props['audio-spdif'] = '';

      case AudioPassthroughMode.auto:
        // 自动模式不设置任何属性
        break;
    }

    return props;
  }

  /// 复制
  PlaybackConfiguration copyWith({
    HdrMode? hdrMode,
    ToneMappingMode? toneMappingMode,
    AudioPassthroughMode? audioPassthroughMode,
    List<AudioCodec>? passthroughCodecs,
    bool? hdrComputePeak,
    int? targetPeak,
  }) =>
      PlaybackConfiguration(
        hdrMode: hdrMode ?? this.hdrMode,
        toneMappingMode: toneMappingMode ?? this.toneMappingMode,
        audioPassthroughMode: audioPassthroughMode ?? this.audioPassthroughMode,
        passthroughCodecs: passthroughCodecs ?? this.passthroughCodecs,
        hdrComputePeak: hdrComputePeak ?? this.hdrComputePeak,
        targetPeak: targetPeak ?? this.targetPeak,
      );

  @override
  String toString() =>
      'PlaybackConfiguration(hdr: $hdrMode, toneMapping: $toneMappingMode, audio: $audioPassthroughMode)';
}

/// 视频媒体信息（用于判断是否需要 HDR/音频直通）
class VideoMediaInfo {
  const VideoMediaInfo({
    this.isHdr = false,
    this.hdrType = HdrType.none,
    this.dolbyVisionProfile,
    this.audioCodec,
    this.audioChannels = 2,
  });

  /// 是否是 HDR 内容
  final bool isHdr;

  /// HDR 类型
  final HdrType hdrType;

  /// Dolby Vision Profile（如果是 DV 内容）
  final int? dolbyVisionProfile;

  /// 音频编码格式
  final AudioCodec? audioCodec;

  /// 音频声道数
  final int audioChannels;

  /// 是否是 Dolby Vision 内容
  bool get isDolbyVision => hdrType == HdrType.dolbyVision;

  /// 是否需要音频直通（高级音频格式）
  bool get needsAudioPassthrough =>
      audioCodec != null && audioCodec!.supportsPassthrough;

  @override
  String toString() =>
      'VideoMediaInfo(isHdr: $isHdr, type: $hdrType, audioCodec: $audioCodec)';
}
