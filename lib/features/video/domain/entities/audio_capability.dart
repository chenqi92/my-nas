import 'package:my_nas/core/i18n/app_l10n.dart';
/// 音频编码格式
enum AudioCodec {
  /// PCM（无压缩）
  pcm('pcm', 'PCM', false),

  /// AC3 (Dolby Digital)
  ac3('ac3', 'AC3', true),

  /// EAC3 (Dolby Digital Plus)
  eac3('eac3', 'DD+', true),

  /// TrueHD (Dolby TrueHD)
  truehd('truehd', 'TrueHD', true),

  /// DTS
  dts('dts', 'DTS', true),

  /// DTS-HD (DTS-HD MA)
  dtsHd('dts-hd', 'DTS-HD MA', true),

  /// Dolby Atmos（通常封装在 TrueHD 或 EAC3 中）
  atmos('atmos', 'Atmos', true),

  /// DTS:X（通常封装在 DTS-HD 中）
  dtsX('dts-x', 'DTS:X', true);

  const AudioCodec(this.mpvName, this.displayName, this.supportsPassthrough);

  /// MPV 中使用的名称
  final String mpvName;

  /// 显示名称
  final String displayName;

  /// 是否支持直通
  final bool supportsPassthrough;

  static AudioCodec? fromMpvName(String name) {
    for (final codec in AudioCodec.values) {
      if (codec.mpvName == name) return codec;
    }
    return null;
  }
}

/// 音频输出设备类型
enum AudioOutputDevice {
  /// HDMI
  hdmi('HDMI'),

  /// 光纤 (S/PDIF)
  spdif('光纤'),

  /// ARC/eARC
  arc('ARC'),

  /// 蓝牙
  bluetooth('蓝牙'),

  /// 耳机
  headphones('耳机'),

  /// 扬声器
  speaker('扬声器'),

  /// 未知
  unknown('未知');

  const AudioOutputDevice(this.displayName);

  final String displayName;

  static AudioOutputDevice fromId(String id) {
    switch (id.toLowerCase()) {
      case 'hdmi':
        return AudioOutputDevice.hdmi;
      case 'spdif':
      case 'optical':
        return AudioOutputDevice.spdif;
      case 'arc':
      case 'earc':
        return AudioOutputDevice.arc;
      case 'bluetooth':
        return AudioOutputDevice.bluetooth;
      case 'headphones':
        return AudioOutputDevice.headphones;
      case 'speaker':
        return AudioOutputDevice.speaker;
      default:
        return AudioOutputDevice.unknown;
    }
  }
}

/// 音频直通模式
enum AudioPassthroughMode {
  /// 自动（根据设备能力自动决定）
  auto('自动'),

  /// 启用（强制直通）
  enabled('启用'),

  /// 禁用（解码后输出）
  disabled('禁用');

  const AudioPassthroughMode(this.displayName);

  final String displayName;
}

/// 音频直通能力
class AudioPassthroughCapability {
  const AudioPassthroughCapability({
    required this.isSupported,
    this.supportedCodecs = const [],
    this.outputDevice = AudioOutputDevice.unknown,
    this.maxChannels = 2,
    this.deviceName,
  });

  /// 从 Map 创建
  factory AudioPassthroughCapability.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) {
      return const AudioPassthroughCapability(isSupported: false);
    }

    final codecsList = (map['supportedCodecs'] as List<dynamic>?)
            ?.map((e) => AudioCodec.fromMpvName(e.toString()))
            .whereType<AudioCodec>()
            .toList() ??
        [];

    return AudioPassthroughCapability(
      isSupported: map['isSupported'] as bool? ?? false,
      supportedCodecs: codecsList,
      outputDevice: AudioOutputDevice.fromId(
        map['outputDevice'] as String? ?? 'unknown',
      ),
      maxChannels: map['maxChannels'] as int? ?? 2,
      deviceName: map['deviceName'] as String?,
    );
  }

  /// 是否支持直通
  final bool isSupported;

  /// 支持直通的编码格式
  final List<AudioCodec> supportedCodecs;

  /// 当前输出设备类型
  final AudioOutputDevice outputDevice;

  /// 最大声道数
  final int maxChannels;

  /// 设备名称
  final String? deviceName;

  /// 是否支持 Dolby 直通
  bool get supportsDolby =>
      supportedCodecs.contains(AudioCodec.ac3) ||
      supportedCodecs.contains(AudioCodec.eac3) ||
      supportedCodecs.contains(AudioCodec.truehd);

  /// 是否支持 DTS 直通
  bool get supportsDts =>
      supportedCodecs.contains(AudioCodec.dts) ||
      supportedCodecs.contains(AudioCodec.dtsHd);

  /// 是否支持无损直通 (TrueHD/DTS-HD)
  bool get supportsLossless =>
      supportedCodecs.contains(AudioCodec.truehd) ||
      supportedCodecs.contains(AudioCodec.dtsHd);

  /// 转为 Map
  Map<String, dynamic> toMap() => {
        'isSupported': isSupported,
        'supportedCodecs': supportedCodecs.map((e) => e.mpvName).toList(),
        'outputDevice': outputDevice.name,
        'maxChannels': maxChannels,
        'deviceName': deviceName,
      };

  /// 获取直通编码的 MPV 格式字符串
  String get mpvSpdifCodecs =>
      supportedCodecs.map((c) => c.mpvName).join(',');

  /// 获取能力描述文本
  String get description {
    if (!isSupported) return appL10n.audioCapabilityPassthroughUnsupported;

    final codecs = supportedCodecs.map((e) => e.displayName).join(', ');
    return '${outputDevice.displayName}: $codecs';
  }

  @override
  String toString() =>
      'AudioPassthroughCapability(isSupported: $isSupported, codecs: $supportedCodecs, device: $outputDevice)';
}
