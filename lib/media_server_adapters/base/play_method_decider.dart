import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/media_server_adapters/base/media_server_entities.dart';

/// 设备播放能力
class DevicePlaybackCapabilities {
  const DevicePlaybackCapabilities({
    required this.supportedVideoCodecs,
    required this.supportedAudioCodecs,
    required this.supportedContainers,
    this.maxBitrate,
    this.supportsHdr = false,
    this.supportsDolbyVision = false,
    this.supportsHdr10Plus = false,
    this.maxResolutionWidth,
    this.maxResolutionHeight,
  });

  /// 默认能力配置
  factory DevicePlaybackCapabilities.defaults() {
    // 根据平台返回默认能力
    if (Platform.isIOS) {
      return const DevicePlaybackCapabilities(
        supportedVideoCodecs: ['h264', 'hevc', 'vp9'],
        supportedAudioCodecs: ['aac', 'ac3', 'eac3', 'flac', 'mp3'],
        supportedContainers: ['mp4', 'mov', 'm4v', 'mkv'],
        supportsHdr: true,
        supportsDolbyVision: true,
        supportsHdr10Plus: false,
        maxResolutionWidth: 3840,
        maxResolutionHeight: 2160,
      );
    } else if (Platform.isAndroid) {
      return const DevicePlaybackCapabilities(
        supportedVideoCodecs: ['h264', 'hevc', 'vp9', 'av1'],
        supportedAudioCodecs: ['aac', 'ac3', 'eac3', 'dts', 'flac', 'mp3', 'opus'],
        supportedContainers: ['mp4', 'mkv', 'webm', 'ts'],
        supportsHdr: true,
        supportsDolbyVision: true,
        supportsHdr10Plus: true,
        maxResolutionWidth: 3840,
        maxResolutionHeight: 2160,
      );
    } else if (Platform.isMacOS) {
      return const DevicePlaybackCapabilities(
        supportedVideoCodecs: ['h264', 'hevc', 'vp9', 'av1'],
        supportedAudioCodecs: ['aac', 'ac3', 'eac3', 'flac', 'mp3', 'alac'],
        supportedContainers: ['mp4', 'mov', 'm4v', 'mkv', 'webm'],
        supportsHdr: true,
        supportsDolbyVision: true,
        supportsHdr10Plus: false,
        maxResolutionWidth: 7680,
        maxResolutionHeight: 4320,
      );
    } else {
      // Windows / Linux
      return const DevicePlaybackCapabilities(
        supportedVideoCodecs: ['h264', 'hevc', 'vp9', 'av1'],
        supportedAudioCodecs: ['aac', 'ac3', 'eac3', 'dts', 'flac', 'mp3', 'opus'],
        supportedContainers: ['mp4', 'mkv', 'webm', 'avi', 'ts'],
        supportsHdr: true,
        supportsDolbyVision: false,
        supportsHdr10Plus: true,
        maxResolutionWidth: 7680,
        maxResolutionHeight: 4320,
      );
    }
  }

  final List<String> supportedVideoCodecs;
  final List<String> supportedAudioCodecs;
  final List<String> supportedContainers;
  final int? maxBitrate;
  final bool supportsHdr;
  final bool supportsDolbyVision;
  final bool supportsHdr10Plus;
  final int? maxResolutionWidth;
  final int? maxResolutionHeight;

  /// 检查是否支持指定视频编码
  bool supportsVideoCodec(String? codec) {
    if (codec == null) return true;
    final normalized = _normalizeCodec(codec);
    return supportedVideoCodecs.any(
      (c) => _normalizeCodec(c) == normalized,
    );
  }

  /// 检查是否支持指定音频编码
  bool supportsAudioCodec(String? codec) {
    if (codec == null) return true;
    final normalized = _normalizeCodec(codec);
    return supportedAudioCodecs.any(
      (c) => _normalizeCodec(c) == normalized,
    );
  }

  /// 检查是否支持指定容器格式
  bool supportsContainer(String? container) {
    if (container == null) return true;
    final normalized = container.toLowerCase();
    return supportedContainers.any((c) => c.toLowerCase() == normalized);
  }

  /// 检查是否支持指定分辨率
  bool supportsResolution(int? width, int? height) {
    if (width == null || height == null) return true;
    if (maxResolutionWidth != null && width > maxResolutionWidth!) return false;
    if (maxResolutionHeight != null && height > maxResolutionHeight!) {
      return false;
    }
    return true;
  }

  /// 检查是否支持指定码率
  bool supportsBitrate(int? bitrate) {
    if (bitrate == null || maxBitrate == null) return true;
    return bitrate <= maxBitrate!;
  }

  String _normalizeCodec(String codec) {
    final lower = codec.toLowerCase();
    // 视频编码规范化
    if (lower.contains('h264') || lower.contains('avc')) return 'h264';
    if (lower.contains('h265') || lower.contains('hevc')) return 'hevc';
    if (lower.contains('vp9')) return 'vp9';
    if (lower.contains('av1')) return 'av1';
    // 音频编码规范化
    if (lower.contains('aac')) return 'aac';
    if (lower.contains('ac3') || lower.contains('ac-3')) return 'ac3';
    if (lower.contains('eac3') || lower.contains('e-ac-3')) return 'eac3';
    if (lower.contains('dts')) return 'dts';
    if (lower.contains('flac')) return 'flac';
    if (lower.contains('opus')) return 'opus';
    if (lower.contains('mp3')) return 'mp3';
    return lower;
  }
}

/// 播放方式决策结果
class PlayMethodDecision {
  const PlayMethodDecision({
    required this.playMethod,
    this.reason,
    this.transcodingNeeded = false,
    this.videoTranscoding = false,
    this.audioTranscoding = false,
    this.containerConversion = false,
  });

  final MediaPlayMethod playMethod;
  final String? reason;
  final bool transcodingNeeded;
  final bool videoTranscoding;
  final bool audioTranscoding;
  final bool containerConversion;

  bool get isDirectPlay => playMethod == MediaPlayMethod.directPlay;
  bool get isDirectStream => playMethod == MediaPlayMethod.directStream;
  bool get isTranscode => playMethod == MediaPlayMethod.transcode;
}

/// 播放方式决策器
///
/// 根据媒体信息和设备能力决定最佳播放方式
class PlayMethodDecider {
  const PlayMethodDecider({
    DevicePlaybackCapabilities? capabilities,
    this.preferDirectPlay = true,
    this.maxTranscodingBitrate,
  }) : capabilities = capabilities ?? const DevicePlaybackCapabilities(
         supportedVideoCodecs: [],
         supportedAudioCodecs: [],
         supportedContainers: [],
       );

  final DevicePlaybackCapabilities capabilities;
  final bool preferDirectPlay;
  final int? maxTranscodingBitrate;

  /// 决定播放方式
  PlayMethodDecision decide({
    required List<MediaStream> mediaStreams,
    String? container,
    int? bitrate,
  }) {
    // 获取视频和音频流
    final videoStream = mediaStreams.firstWhere(
      (s) => s.type == MediaStreamType.video,
      orElse: () => const MediaStream(type: MediaStreamType.video, index: 0),
    );
    final audioStream = mediaStreams.firstWhere(
      (s) => s.type == MediaStreamType.audio && s.isDefault,
      orElse: () => mediaStreams.firstWhere(
        (s) => s.type == MediaStreamType.audio,
        orElse: () => const MediaStream(type: MediaStreamType.audio, index: 0),
      ),
    );

    // 检查视频兼容性
    final videoCompatible = capabilities.supportsVideoCodec(videoStream.codec);
    final resolutionCompatible = capabilities.supportsResolution(
      videoStream.width,
      videoStream.height,
    );
    final bitrateCompatible = capabilities.supportsBitrate(bitrate);

    // 检查音频兼容性
    final audioCompatible = capabilities.supportsAudioCodec(audioStream.codec);

    // 检查容器兼容性
    final containerCompatible = capabilities.supportsContainer(container);

    // 完全兼容 -> 直接播放
    if (videoCompatible &&
        audioCompatible &&
        containerCompatible &&
        resolutionCompatible &&
        bitrateCompatible) {
      return const PlayMethodDecision(
        playMethod: MediaPlayMethod.directPlay,
        reason: '设备完全支持，直接播放',
      );
    }

    // 视频和音频兼容，只是容器不兼容 -> 直接流
    if (videoCompatible && audioCompatible && resolutionCompatible) {
      if (!containerCompatible) {
        return const PlayMethodDecision(
          playMethod: MediaPlayMethod.directStream,
          reason: '需要重封装容器',
          containerConversion: true,
        );
      }
      if (!bitrateCompatible) {
        return const PlayMethodDecision(
          playMethod: MediaPlayMethod.directStream,
          reason: '码率超出设备限制，需要限速',
        );
      }
    }

    // 需要转码
    final reasons = <String>[];
    if (!videoCompatible) {
      reasons.add('视频编码 ${videoStream.codec} 不支持');
    }
    if (!audioCompatible) {
      reasons.add('音频编码 ${audioStream.codec} 不支持');
    }
    if (!resolutionCompatible) {
      reasons.add(
        '分辨率 ${videoStream.width}x${videoStream.height} 超出设备限制',
      );
    }
    if (!containerCompatible) reasons.add('容器格式 $container 不支持');

    return PlayMethodDecision(
      playMethod: MediaPlayMethod.transcode,
      reason: reasons.join('；'),
      transcodingNeeded: true,
      videoTranscoding: !videoCompatible || !resolutionCompatible,
      audioTranscoding: !audioCompatible,
      containerConversion: !containerCompatible,
    );
  }

  /// 快速判断是否可以直接播放
  bool canDirectPlay({
    required List<MediaStream> mediaStreams,
    String? container,
    int? bitrate,
  }) {
    final decision = decide(
      mediaStreams: mediaStreams,
      container: container,
      bitrate: bitrate,
    );
    return decision.isDirectPlay;
  }

  /// 获取推荐的转码参数
  TranscodingParams getTranscodingParams({
    required List<MediaStream> mediaStreams,
    String? container,
    int? targetBitrate,
  }) {
    final decision = decide(
      mediaStreams: mediaStreams,
      container: container,
    );

    if (!decision.transcodingNeeded) {
      return const TranscodingParams();
    }

    // 推荐 H.264 作为转码目标（兼容性最好）
    String? videoCodec;
    if (decision.videoTranscoding) {
      videoCodec = capabilities.supportedVideoCodecs.contains('hevc')
          ? 'hevc'
          : 'h264';
    }

    // 推荐 AAC 作为音频转码目标
    String? audioCodec;
    if (decision.audioTranscoding) {
      audioCodec = 'aac';
    }

    // 推荐 MP4 容器
    String? targetContainer;
    if (decision.containerConversion) {
      targetContainer = 'mp4';
    }

    return TranscodingParams(
      videoCodec: videoCodec,
      audioCodec: audioCodec,
      container: targetContainer,
      maxBitrate: targetBitrate ?? maxTranscodingBitrate,
    );
  }
}

/// 转码参数
class TranscodingParams {
  const TranscodingParams({
    this.videoCodec,
    this.audioCodec,
    this.container,
    this.maxBitrate,
    this.maxWidth,
    this.maxHeight,
  });

  final String? videoCodec;
  final String? audioCodec;
  final String? container;
  final int? maxBitrate;
  final int? maxWidth;
  final int? maxHeight;

  bool get isEmpty =>
      videoCodec == null &&
      audioCodec == null &&
      container == null &&
      maxBitrate == null;

  Map<String, dynamic> toQueryParams() {
    final params = <String, dynamic>{};
    if (videoCodec != null) params['VideoCodec'] = videoCodec;
    if (audioCodec != null) params['AudioCodec'] = audioCodec;
    if (container != null) params['Container'] = container;
    if (maxBitrate != null) params['MaxStreamingBitrate'] = maxBitrate;
    if (maxWidth != null) params['MaxWidth'] = maxWidth;
    if (maxHeight != null) params['MaxHeight'] = maxHeight;
    return params;
  }
}

/// 设备播放能力 Provider
final devicePlaybackCapabilitiesProvider =
    Provider<DevicePlaybackCapabilities>((ref) => DevicePlaybackCapabilities.defaults());

/// 播放方式决策器 Provider
final playMethodDeciderProvider = Provider<PlayMethodDecider>((ref) {
  final capabilities = ref.watch(devicePlaybackCapabilitiesProvider);
  return PlayMethodDecider(capabilities: capabilities);
});
