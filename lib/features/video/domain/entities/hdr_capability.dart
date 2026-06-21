import 'package:my_nas/core/i18n/app_l10n.dart';
/// HDR 类型
enum HdrType {
  /// 无 HDR
  none('none', '无'),

  /// HDR10
  hdr10('hdr10', 'HDR10'),

  /// HDR10+
  hdr10Plus('hdr10+', 'HDR10+'),

  /// HLG (Hybrid Log-Gamma)
  hlg('hlg', 'HLG'),

  /// Dolby Vision
  dolbyVision('dolbyVision', 'Dolby Vision');

  const HdrType(this.id, this.displayName);

  final String id;
  final String displayName;

  static HdrType fromId(String id) =>
      HdrType.values.firstWhere((e) => e.id == id, orElse: () => HdrType.none);
}

/// HDR 模式
enum HdrMode {
  /// 自动（根据设备和视频自动选择）
  auto('自动'),

  /// 直通（HDR 内容直接输出到支持的显示器）
  passthrough('直通'),

  /// 色调映射（HDR 转换为 SDR）
  tonemapping('色调映射'),

  /// 禁用（不进行任何 HDR 处理）
  disabled('禁用');

  const HdrMode(this.displayName);

  final String displayName;
}

/// 色调映射算法
enum ToneMappingMode {
  /// 自动选择
  auto('auto', '自动'),

  /// Mobius（平滑过渡，推荐）
  mobius('mobius', 'Mobius（推荐）'),

  /// Reinhard（经典算法）
  reinhard('reinhard', 'Reinhard'),

  /// Hable（电影风格）
  hable('hable', 'Hable'),

  /// BT.2390（ITU 标准）
  bt2390('bt.2390', 'BT.2390'),

  /// Clip（简单裁剪）
  clip('clip', 'Clip');

  const ToneMappingMode(this.mpvValue, this.displayName);

  final String mpvValue;
  final String displayName;
}

/// HDR 能力
class HdrCapability {
  const HdrCapability({
    required this.isSupported,
    this.supportedTypes = const [],
    this.maxLuminance = 0,
    this.colorGamut,
  });

  /// 从 Map 创建
  factory HdrCapability.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) {
      return const HdrCapability(isSupported: false);
    }

    final typesList = (map['supportedTypes'] as List<dynamic>?)
            ?.map((e) => HdrType.fromId(e.toString()))
            .where((e) => e != HdrType.none)
            .toList() ??
        [];

    return HdrCapability(
      isSupported: map['isSupported'] as bool? ?? false,
      supportedTypes: typesList,
      maxLuminance: (map['maxLuminance'] as num?)?.toDouble() ?? 0,
      colorGamut: map['colorGamut'] as String?,
    );
  }

  /// 是否支持 HDR
  final bool isSupported;

  /// 支持的 HDR 类型
  final List<HdrType> supportedTypes;

  /// 最大亮度 (nits)
  final double maxLuminance;

  /// 色域 (sRGB, DCI-P3, Rec.2020)
  final String? colorGamut;

  /// 是否支持 Dolby Vision
  bool get supportsDolbyVision => supportedTypes.contains(HdrType.dolbyVision);

  /// 是否支持 HDR10
  bool get supportsHdr10 => supportedTypes.contains(HdrType.hdr10);

  /// 是否支持 HDR10+
  bool get supportsHdr10Plus => supportedTypes.contains(HdrType.hdr10Plus);

  /// 是否支持 HLG
  bool get supportsHlg => supportedTypes.contains(HdrType.hlg);

  /// 转为 Map
  Map<String, dynamic> toMap() => {
        'isSupported': isSupported,
        'supportedTypes': supportedTypes.map((e) => e.id).toList(),
        'maxLuminance': maxLuminance,
        'colorGamut': colorGamut,
      };

  /// 获取能力描述文本
  String get description {
    if (!isSupported) return appL10n.hdrCapabilityNotSupported;

    final types = supportedTypes.map((e) => e.displayName).join(', ');
    if (maxLuminance > 0) {
      return '$types (${maxLuminance.toInt()} nits)';
    }
    return types;
  }

  @override
  String toString() =>
      'HdrCapability(isSupported: $isSupported, types: $supportedTypes, luminance: $maxLuminance)';
}
