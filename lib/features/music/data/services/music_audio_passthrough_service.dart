import 'package:media_kit/media_kit.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/video/data/services/capability/audio_output_capability_service.dart';
import 'package:my_nas/features/video/domain/entities/audio_capability.dart';

/// 音乐播放的音频直通服务
///
/// 检测设备是否支持音频直通，并配置 MPV 输出。
/// 复用视频模块的 AudioOutputCapabilityService 进行能力检测。
///
/// 使用场景：
/// - 通过 HDMI eARC 连接到功放/Soundbar
/// - 播放 AC3/DTS/TrueHD 等高级音频格式
/// - 需要将原始比特流直通到外部设备解码
class MusicAudioPassthroughService {
  factory MusicAudioPassthroughService() =>
      _instance ??= MusicAudioPassthroughService._();
  MusicAudioPassthroughService._();

  static MusicAudioPassthroughService? _instance;

  /// 复用视频模块的能力检测服务
  final AudioOutputCapabilityService _audioCapabilityService =
      AudioOutputCapabilityService();

  /// 用户配置
  AudioPassthroughConfig _userConfig = const AudioPassthroughConfig();

  // ==================== 能力检测 ====================

  /// 检测当前音频输出设备的直通能力
  ///
  /// [forceRefresh] 是否强制刷新（忽略缓存）
  Future<AudioPassthroughCapability> detectCapability({
    bool forceRefresh = false,
  }) async => _audioCapabilityService.detectPassthroughCapability(
      forceRefresh: forceRefresh,
    );

  /// 获取当前输出设备类型
  Future<AudioOutputDevice> getCurrentOutputDevice() async {
    final capability = await detectCapability();
    return capability.outputDevice;
  }

  /// 检查指定编码是否支持直通
  Future<bool> isCodecSupported(AudioCodec codec) async {
    final capability = await detectCapability();
    return capability.supportedCodecs.contains(codec);
  }

  // ==================== 直通配置 ====================

  /// 应用直通配置到 media_kit Player
  ///
  /// [player] media_kit Player 实例
  /// [config] 直通配置（如果为 null，使用用户配置）
  Future<void> applyToPlayer(Player player, [AudioPassthroughConfig? config]) async {
    final effectiveConfig = config ?? _userConfig;

    // 如果禁用直通，清除配置
    if (effectiveConfig.mode == AudioPassthroughMode.disabled) {
      await _clearPassthroughConfig(player);
      return;
    }

    // 获取设备能力
    final capability = await detectCapability();

    // 自动模式下，检查设备是否支持直通
    if (effectiveConfig.mode == AudioPassthroughMode.auto && !capability.isSupported) {
      logger.d('MusicAudioPassthroughService: 自动模式 - 设备不支持直通');
      return;
    }

    // 计算实际启用的编码
    final enabledCodecs = effectiveConfig.getEffectiveCodecs(capability);
    if (enabledCodecs.isEmpty) {
      logger.d('MusicAudioPassthroughService: 无可用的直通编码');
      return;
    }

    try {
      final nativePlayer = player.platform;
      if (nativePlayer is NativePlayer) {
        // 设置 SPDIF 直通编码
        final spdifValue = getMpvSpdifProperty(enabledCodecs);
        await nativePlayer.setProperty('audio-spdif', spdifValue);

        // 设置音频声道
        await nativePlayer.setProperty('audio-channels', 'auto-safe');

        // 独占模式（可选）
        if (effectiveConfig.exclusiveMode) {
          await nativePlayer.setProperty('audio-exclusive', 'yes');
        }

        // 尝试获取最优音频设备
        final device = await getOptimalAudioDevice();
        if (device != null) {
          await nativePlayer.setProperty('audio-device', device);
        }

        logger.i('MusicAudioPassthroughService: 直通配置已应用 - codecs=$spdifValue, '
            'exclusive=${effectiveConfig.exclusiveMode}, device=$device');
      }
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'applyPassthroughConfig');
    }
  }

  /// 清除直通配置
  Future<void> _clearPassthroughConfig(Player player) async {
    try {
      final nativePlayer = player.platform;
      if (nativePlayer is NativePlayer) {
        await nativePlayer.setProperty('audio-spdif', '');
        await nativePlayer.setProperty('audio-exclusive', 'no');
        logger.d('MusicAudioPassthroughService: 直通配置已清除');
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '清除直通配置失败');
    }
  }

  /// 生成 MPV audio-spdif 属性值
  ///
  /// [codecs] 要直通的编码列表
  String getMpvSpdifProperty(List<AudioCodec> codecs) => codecs.map((c) => c.mpvName).join(',');

  /// 获取最优音频设备名称
  ///
  /// 在多个输出设备可用时选择最优的（如优先 HDMI）
  // 目前使用 'auto' 让 MPV 自动选择
  // 未来可以根据设备能力返回特定设备
  Future<String?> getOptimalAudioDevice() async => null;

  // ==================== 用户设置 ====================

  /// 获取用户的直通设置
  AudioPassthroughConfig getUserConfig() => _userConfig;

  /// 设置用户的直通配置
  void setUserConfig(AudioPassthroughConfig config) {
    _userConfig = config;
    logger.d('MusicAudioPassthroughService: 用户配置已更新 - $config');
  }

  // ==================== 辅助方法 ====================

  /// 清除能力检测缓存
  void clearCache() {
    _audioCapabilityService.clearCache();
  }

  /// 判断是否应该使用音频直通
  ///
  /// [sourceCodec] 音频源的编码格式
  Future<bool> shouldUsePassthrough(AudioCodec sourceCodec) async {
    if (_userConfig.mode == AudioPassthroughMode.disabled) {
      return false;
    }

    final capability = await detectCapability();
    return _audioCapabilityService.shouldUseAudioPassthrough(
      sourceCodec,
      capability,
    );
  }

  /// 获取音频输出建议
  ///
  /// 根据当前设备和音频编码给出用户提示
  Future<AudioOutputAdvice> getOutputAdvice(AudioCodec? sourceCodec) async {
    final device = await getCurrentOutputDevice();
    final capability = await detectCapability();

    // AirPlay 输出
    if (device == AudioOutputDevice.unknown) {
      // 无法检测设备类型
      return AudioOutputAdvice(
        canPlayOriginal: false,
        degradedMode: false,
        message: appL10n.audioPassthroughDefaultOutput,
      );
    }

    // 蓝牙输出
    if (device == AudioOutputDevice.bluetooth) {
      return AudioOutputAdvice(
        canPlayOriginal: false,
        degradedMode: true,
        message: appL10n.audioPassthroughBluetoothStereo,
      );
    }

    // HDMI/eARC 输出
    if (device == AudioOutputDevice.hdmi || device == AudioOutputDevice.arc) {
      if (sourceCodec != null && capability.supportedCodecs.contains(sourceCodec)) {
        return AudioOutputAdvice(
          canPlayOriginal: true,
          degradedMode: false,
          message: appL10n.audioPassthroughEnabled,
        );
      } else if (sourceCodec != null) {
        return AudioOutputAdvice(
          canPlayOriginal: false,
          degradedMode: false,
          message: appL10n.audioPassthroughUnsupportedCodec(sourceCodec.displayName),
        );
      }
    }

    // 默认
    return AudioOutputAdvice(
      canPlayOriginal: false,
      degradedMode: false,
      message: appL10n.audioPassthroughDecode,
    );
  }
}

/// 音频直通配置
class AudioPassthroughConfig {
  const AudioPassthroughConfig({
    this.mode = AudioPassthroughMode.auto,
    this.enabledCodecs,
    this.exclusiveMode = false,
  });

  /// 从 Map 创建
  factory AudioPassthroughConfig.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return const AudioPassthroughConfig();

    return AudioPassthroughConfig(
      mode: AudioPassthroughMode.values[map['mode'] as int? ?? 0],
      enabledCodecs: (map['enabledCodecs'] as List<dynamic>?)
          ?.map((e) => AudioCodec.values[e as int])
          .toList(),
      exclusiveMode: map['exclusiveMode'] as bool? ?? false,
    );
  }

  /// 直通模式
  final AudioPassthroughMode mode;

  /// 用户启用的直通编码（null 表示使用设备支持的全部）
  final List<AudioCodec>? enabledCodecs;

  /// 是否使用独占模式（WASAPI Exclusive / CoreAudio Exclusive）
  final bool exclusiveMode;

  /// 转为 Map
  Map<String, dynamic> toMap() => {
        'mode': mode.index,
        'enabledCodecs': enabledCodecs?.map((e) => e.index).toList(),
        'exclusiveMode': exclusiveMode,
      };

  /// 获取实际启用的编码列表
  ///
  /// 如果用户指定了编码，返回与设备能力的交集
  /// 否则返回设备支持的全部编码
  List<AudioCodec> getEffectiveCodecs(AudioPassthroughCapability capability) {
    if (!capability.isSupported) return [];

    if (enabledCodecs != null && enabledCodecs!.isNotEmpty) {
      // 返回用户指定编码与设备能力的交集
      return enabledCodecs!
          .where((c) => capability.supportedCodecs.contains(c))
          .toList();
    }

    // 返回设备支持的全部编码
    return capability.supportedCodecs;
  }

  /// 复制
  AudioPassthroughConfig copyWith({
    AudioPassthroughMode? mode,
    List<AudioCodec>? enabledCodecs,
    bool? exclusiveMode,
  }) =>
      AudioPassthroughConfig(
        mode: mode ?? this.mode,
        enabledCodecs: enabledCodecs ?? this.enabledCodecs,
        exclusiveMode: exclusiveMode ?? this.exclusiveMode,
      );

  @override
  String toString() =>
      'AudioPassthroughConfig(mode: $mode, codecs: $enabledCodecs, exclusive: $exclusiveMode)';
}

/// 音频输出建议
class AudioOutputAdvice {
  const AudioOutputAdvice({
    required this.canPlayOriginal,
    required this.degradedMode,
    required this.message,
  });

  /// 是否可以播放原始格式
  final bool canPlayOriginal;

  /// 是否降级模式（如蓝牙只能立体声）
  final bool degradedMode;

  /// 用户提示消息
  final String message;
}
