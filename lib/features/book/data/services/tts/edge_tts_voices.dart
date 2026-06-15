/// Edge TTS 预设音色
///
/// 微软 Edge TTS 神经网络中文音色列表
library;

import 'package:my_nas/features/book/data/services/tts/tts_voice.dart';

/// Edge TTS 中文音色
class EdgeTTSVoices {
  EdgeTTSVoices._();

  /// 所有可用的中文音色
  static const List<EdgeVoice> chineseVoices = [
    // 普通话 - 女声
    EdgeVoice(
      id: 'zh-CN-XiaoxiaoNeural',
      name: '晓晓',
      gender: VoiceGender.female,
      locale: 'zh-CN',
      description: '温柔自然，适合小说朗读',
    ),
    EdgeVoice(
      id: 'zh-CN-XiaoyiNeural',
      name: '晓伊',
      gender: VoiceGender.female,
      locale: 'zh-CN',
      description: '活泼可爱，适合轻松内容',
    ),
    EdgeVoice(
      id: 'zh-CN-XiaohanNeural',
      name: '晓涵',
      gender: VoiceGender.female,
      locale: 'zh-CN',
      description: '知性优雅',
    ),
    EdgeVoice(
      id: 'zh-CN-XiaomengNeural',
      name: '晓梦',
      gender: VoiceGender.female,
      locale: 'zh-CN',
      description: '甜美童声',
    ),
    EdgeVoice(
      id: 'zh-CN-XiaomoNeural',
      name: '晓墨',
      gender: VoiceGender.female,
      locale: 'zh-CN',
      description: '新闻播报风格',
    ),
    EdgeVoice(
      id: 'zh-CN-XiaoruiNeural',
      name: '晓睿',
      gender: VoiceGender.female,
      locale: 'zh-CN',
      description: '成熟稳重',
    ),
    EdgeVoice(
      id: 'zh-CN-XiaoshuangNeural',
      name: '晓双',
      gender: VoiceGender.female,
      locale: 'zh-CN',
      description: '儿童声音',
    ),
    EdgeVoice(
      id: 'zh-CN-XiaoxuanNeural',
      name: '晓萱',
      gender: VoiceGender.female,
      locale: 'zh-CN',
      description: '情感丰富',
    ),
    EdgeVoice(
      id: 'zh-CN-XiaoyanNeural',
      name: '晓颜',
      gender: VoiceGender.female,
      locale: 'zh-CN',
      description: '标准播音',
    ),
    EdgeVoice(
      id: 'zh-CN-XiaozhenNeural',
      name: '晓甄',
      gender: VoiceGender.female,
      locale: 'zh-CN',
      description: '亲切自然',
    ),
    // 普通话 - 男声
    EdgeVoice(
      id: 'zh-CN-YunxiNeural',
      name: '云希',
      gender: VoiceGender.male,
      locale: 'zh-CN',
      description: '年轻活力，推荐',
    ),
    EdgeVoice(
      id: 'zh-CN-YunjianNeural',
      name: '云健',
      gender: VoiceGender.male,
      locale: 'zh-CN',
      description: '成熟稳重',
    ),
    EdgeVoice(
      id: 'zh-CN-YunyangNeural',
      name: '云扬',
      gender: VoiceGender.male,
      locale: 'zh-CN',
      description: '新闻播音风格',
    ),
    EdgeVoice(
      id: 'zh-CN-YunxiaNeural',
      name: '云夏',
      gender: VoiceGender.male,
      locale: 'zh-CN',
      description: '少年声音',
    ),
    EdgeVoice(
      id: 'zh-CN-YunzeNeural',
      name: '云泽',
      gender: VoiceGender.male,
      locale: 'zh-CN',
      description: '情感叙述',
    ),
    // 粤语
    EdgeVoice(
      id: 'zh-HK-HiuMaanNeural',
      name: '曉曼',
      gender: VoiceGender.female,
      locale: 'zh-HK',
      description: '粤语女声',
    ),
    EdgeVoice(
      id: 'zh-HK-WanLungNeural',
      name: '雲龍',
      gender: VoiceGender.male,
      locale: 'zh-HK',
      description: '粤语男声',
    ),
    // 台湾普通话
    EdgeVoice(
      id: 'zh-TW-HsiaoChenNeural',
      name: '曉臻',
      gender: VoiceGender.female,
      locale: 'zh-TW',
      description: '台湾女声',
    ),
    EdgeVoice(
      id: 'zh-TW-YunJheNeural',
      name: '雲哲',
      gender: VoiceGender.male,
      locale: 'zh-TW',
      description: '台湾男声',
    ),
  ];

  /// 默认音色
  static const EdgeVoice defaultVoice = EdgeVoice(
    id: 'zh-CN-XiaoxiaoNeural',
    name: '晓晓',
    gender: VoiceGender.female,
    locale: 'zh-CN',
    description: '温柔自然，适合小说朗读',
  );

  /// 根据 ID 获取音色
  static EdgeVoice? getVoiceById(String id) {
    try {
      return chineseVoices.firstWhere((v) => v.id == id);
      // firstWhere 在无匹配时抛 StateError，用于表示“未找到”
      // ignore: avoid_catching_errors
    } on StateError {
      return null;
    }
  }
}

/// Edge TTS 音色
class EdgeVoice {
  const EdgeVoice({
    required this.id,
    required this.name,
    required this.gender,
    required this.locale,
    required this.description,
  });

  /// 音色 ID（如 zh-CN-XiaoxiaoNeural）
  final String id;

  /// 显示名称
  final String name;

  /// 性别
  final VoiceGender gender;

  /// 语言区域
  final String locale;

  /// 描述
  final String description;

  /// 转换为 TTSVoice（用于统一接口）
  TTSVoice toTTSVoice() => TTSVoice(
        id: id,
        name: id,
        displayName: name,
        gender: gender,
        language: locale.split('-').first,
        locale: locale,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EdgeVoice && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
