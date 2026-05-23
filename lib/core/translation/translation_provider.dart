/// 翻译相关共享抽象：被歌词翻译、视频字幕翻译复用。
library;

/// 翻译目标语言（BCP-47）。
enum TranslationLang {
  zhHans('zh-CN', '简体中文'),
  zhHant('zh-TW', '繁体中文'),
  en('en', 'English'),
  ja('ja', '日本語'),
  ko('ko', '한국어'),
  fr('fr', 'Français'),
  de('de', 'Deutsch'),
  es('es', 'Español'),
  ru('ru', 'Русский');

  const TranslationLang(this.bcp47, this.displayName);

  final String bcp47;
  final String displayName;

  static TranslationLang fromBcp47(String code) {
    for (final v in values) {
      if (v.bcp47 == code) return v;
    }
    return TranslationLang.zhHans;
  }
}

/// 翻译 provider 抽象。新增 provider（DeepL / OpenAI / Gemini）实现这个接口即可。
abstract class TranslationProvider {
  String get id;
  String get displayName;

  /// 批量翻译。返回值数组与输入 [texts] 一一对应；失败的项返回 null。
  /// [sourceLangBcp47] 为 null 表示自动检测。
  Future<List<String?>> translate({
    required List<String> texts,
    required String targetLangBcp47,
    String? sourceLangBcp47,
  });
}
