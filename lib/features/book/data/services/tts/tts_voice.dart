import 'package:flutter/foundation.dart';

/// 音色性别
enum VoiceGender {
  male('男声'),
  female('女声'),
  neutral('中性');

  const VoiceGender(this.label);
  final String label;
}

/// TTS 音色
@immutable
class TTSVoice {
  const TTSVoice({
    required this.id,
    required this.name,
    required this.displayName,
    required this.gender,
    required this.language,
    this.locale,
  });

  /// 从系统音色数据创建
  factory TTSVoice.fromSystemVoice(Map<dynamic, dynamic> voice) {
    final name = voice['name'] as String? ?? '';
    final locale = voice['locale'] as String? ?? 'zh-CN';

    // 根据名称推断性别
    var gender = VoiceGender.neutral;
    final nameLower = name.toLowerCase();
    if (nameLower.contains('female') ||
        nameLower.contains('女') ||
        nameLower.contains('xiaoxiao') ||
        nameLower.contains('xiaoyi') ||
        nameLower.contains('tingting')) {
      gender = VoiceGender.female;
    } else if (nameLower.contains('male') ||
        nameLower.contains('男') ||
        nameLower.contains('yunxi') ||
        nameLower.contains('kangkang')) {
      gender = VoiceGender.male;
    }

    // 生成友好显示名称
    var displayName = name;
    if (name.isEmpty) {
      displayName = locale.contains('zh') ? '默认中文' : '默认音色';
    } else {
      // 简化显示名称
      displayName = _simplifyVoiceName(name, locale);
    }

    return TTSVoice(
      id: name.isNotEmpty ? name : locale,
      name: name,
      displayName: displayName,
      gender: gender,
      language: locale.split('-').first,
      locale: locale,
    );
  }

  final String id;
  final String name;
  final String displayName;
  final VoiceGender gender;
  final String language;
  final String? locale;

  /// 转换为 flutter_tts 需要的格式
  Map<String, String> toFlutterTtsVoice() => {
        'name': name,
        'locale': locale ?? 'zh-CN',
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TTSVoice && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  /// 简化音色名称
  static String _simplifyVoiceName(String name, String locale) {
    // iOS 音色名称格式: com.apple.voice.compact.zh-CN.Tingting
    if (name.startsWith('com.apple')) {
      final parts = name.split('.');
      if (parts.isNotEmpty) {
        return parts.last;
      }
    }

    // Android 音色名称格式: zh-CN-language 或类似
    if (name.contains('-')) {
      final parts = name.split('-');
      // 返回最后一个有意义的部分
      for (var i = parts.length - 1; i >= 0; i--) {
        if (parts[i].length > 2 && !RegExp(r'^\d+$').hasMatch(parts[i])) {
          return parts[i];
        }
      }
    }

    return name;
  }
}

/// 预设中文音色 (当无法获取系统音色时使用)
class VoicePresets {
  static const TTSVoice defaultChinese = TTSVoice(
    id: 'zh-CN-default',
    name: '',
    displayName: '系统默认',
    gender: VoiceGender.neutral,
    language: 'zh',
    locale: 'zh-CN',
  );

  /// 获取中文音色的显示图标
  static String getVoiceIcon(VoiceGender gender) {
    switch (gender) {
      case VoiceGender.male:
        return '👨';
      case VoiceGender.female:
        return '👩';
      case VoiceGender.neutral:
        return '🎤';
    }
  }
}
