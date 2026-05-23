import 'package:media_kit/media_kit.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/data/services/capability/audio_output_capability_service.dart';
import 'package:my_nas/features/video/data/services/capability/display_capability_service.dart';
import 'package:my_nas/features/video/domain/entities/audio_capability.dart';
import 'package:my_nas/features/video/domain/entities/hdr_capability.dart';
import 'package:my_nas/features/video/domain/entities/playback_configuration.dart';

/// 用户的 HDR/音频设置
class HdrAudioSettings {
  const HdrAudioSettings({
    this.hdrMode = HdrMode.auto,
    this.toneMappingMode = ToneMappingMode.auto,
    this.audioPassthroughMode = AudioPassthroughMode.auto,
    this.enabledPassthroughCodecs,
  });

  /// 从 Map 创建
  factory HdrAudioSettings.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return const HdrAudioSettings();

    return HdrAudioSettings(
      hdrMode: HdrMode.values[map['hdrMode'] as int? ?? 0],
      toneMappingMode: ToneMappingMode.values[map['toneMappingMode'] as int? ?? 0],
      audioPassthroughMode:
          AudioPassthroughMode.values[map['audioPassthroughMode'] as int? ?? 0],
      enabledPassthroughCodecs: (map['enabledPassthroughCodecs'] as List<dynamic>?)
          ?.map((e) => AudioCodec.values[e as int])
          .toList(),
    );
  }

  /// HDR 模式
  final HdrMode hdrMode;

  /// 色调映射算法
  final ToneMappingMode toneMappingMode;

  /// 音频直通模式
  final AudioPassthroughMode audioPassthroughMode;

  /// 用户启用的直通编码（null 表示使用设备支持的全部）
  final List<AudioCodec>? enabledPassthroughCodecs;

  /// 转为 Map
  Map<String, dynamic> toMap() => {
        'hdrMode': hdrMode.index,
        'toneMappingMode': toneMappingMode.index,
        'audioPassthroughMode': audioPassthroughMode.index,
        'enabledPassthroughCodecs':
            enabledPassthroughCodecs?.map((e) => e.index).toList(),
      };

  /// 复制
  HdrAudioSettings copyWith({
    HdrMode? hdrMode,
    ToneMappingMode? toneMappingMode,
    AudioPassthroughMode? audioPassthroughMode,
    List<AudioCodec>? enabledPassthroughCodecs,
  }) =>
      HdrAudioSettings(
        hdrMode: hdrMode ?? this.hdrMode,
        toneMappingMode: toneMappingMode ?? this.toneMappingMode,
        audioPassthroughMode: audioPassthroughMode ?? this.audioPassthroughMode,
        enabledPassthroughCodecs:
            enabledPassthroughCodecs ?? this.enabledPassthroughCodecs,
      );
}

/// 播放能力服务
///
/// 统一管理 HDR 和音频能力检测，生成最优播放配置
class PlaybackCapabilityService {
  factory PlaybackCapabilityService() =>
      _instance ??= PlaybackCapabilityService._();
  PlaybackCapabilityService._();

  static PlaybackCapabilityService? _instance;

  final _displayService = DisplayCapabilityService();
  final _audioService = AudioOutputCapabilityService();

  /// 获取设备 HDR 能力
  Future<HdrCapability> getHdrCapability({bool forceRefresh = false}) =>
      _displayService.detectHdrCapability(forceRefresh: forceRefresh);

  /// 获取音频直通能力
  Future<AudioPassthroughCapability> getAudioCapability({
    bool forceRefresh = false,
  }) =>
      _audioService.detectPassthroughCapability(forceRefresh: forceRefresh);

  /// 生成最优播放配置
  ///
  /// 根据视频信息、设备能力和用户设置，生成最优的播放配置
  Future<PlaybackConfiguration> getOptimalConfiguration({
    required VideoMediaInfo videoInfo,
    required HdrAudioSettings userSettings,
  }) async {
    final hdrCap = await _displayService.detectHdrCapability();
    final audioCap = await _audioService.detectPassthroughCapability();

    return generateConfiguration(
      videoInfo: videoInfo,
      hdrCapability: hdrCap,
      audioCapability: audioCap,
      userSettings: userSettings,
    );
  }

  /// 生成播放配置（不重新检测能力）
  PlaybackConfiguration generateConfiguration({
    required VideoMediaInfo videoInfo,
    required HdrCapability hdrCapability,
    required AudioPassthroughCapability audioCapability,
    required HdrAudioSettings userSettings,
  }) {
    // 确定 HDR 模式
    var effectiveHdrMode = userSettings.hdrMode;

    if (userSettings.hdrMode == HdrMode.auto) {
      if (videoInfo.isHdr) {
        // 视频是 HDR，检查设备是否支持
        if (_displayService.shouldUseHdrPassthrough(
          videoInfo.hdrType,
          hdrCapability,
        )) {
          effectiveHdrMode = HdrMode.passthrough;
        } else {
          // 设备不支持该 HDR 类型，使用色调映射
          effectiveHdrMode = HdrMode.tonemapping;
        }
      } else {
        // 视频不是 HDR，禁用 HDR 处理
        effectiveHdrMode = HdrMode.disabled;
      }
    }

    // 确定音频直通模式
    var effectiveAudioMode = userSettings.audioPassthroughMode;
    var passthroughCodecs = <AudioCodec>[];

    if (userSettings.audioPassthroughMode == AudioPassthroughMode.auto) {
      if (videoInfo.needsAudioPassthrough &&
          videoInfo.audioCodec != null &&
          _audioService.shouldUseAudioPassthrough(
            videoInfo.audioCodec!,
            audioCapability,
          )) {
        effectiveAudioMode = AudioPassthroughMode.enabled;
        passthroughCodecs = [videoInfo.audioCodec!];
      } else {
        effectiveAudioMode = AudioPassthroughMode.disabled;
      }
    } else if (userSettings.audioPassthroughMode ==
        AudioPassthroughMode.enabled) {
      // 用户强制启用直通
      if (userSettings.enabledPassthroughCodecs != null) {
        // 使用用户指定的编码
        passthroughCodecs = userSettings.enabledPassthroughCodecs!
            .where((c) => audioCapability.supportedCodecs.contains(c))
            .toList();
      } else {
        // 使用设备支持的所有编码
        passthroughCodecs = audioCapability.supportedCodecs;
      }
    }

    return PlaybackConfiguration(
      hdrMode: effectiveHdrMode,
      toneMappingMode: userSettings.toneMappingMode,
      audioPassthroughMode: effectiveAudioMode,
      passthroughCodecs: passthroughCodecs,
    );
  }

  /// 应用配置到播放器
  ///
  /// 通过 NativePlayer.setProperty() 设置 MPV 属性
  Future<void> applyConfiguration(
    Player player,
    PlaybackConfiguration config,
  ) async {
    try {
      final nativePlayer = player.platform! as NativePlayer;
      final properties = config.toMpvProperties();

      for (final entry in properties.entries) {
        await nativePlayer.setProperty(entry.key, entry.value);
        logger.d('PlaybackCapabilityService: 设置 MPV 属性 ${entry.key}=${entry.value}');
      }

      logger.i('PlaybackCapabilityService: 已应用播放配置 - $config');
    } catch (e, st) {
      AppError.handle(e, st, 'applyPlaybackConfiguration');
    }
  }

  /// 清除所有缓存
  void clearCache() {
    _displayService.clearCache();
    _audioService.clearCache();
  }
}
