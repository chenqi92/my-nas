import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:my_nas/core/translation/translation_provider.dart';

/// 视频字幕翻译相关设置（持久化到 Hive，沿用 video_settings box）。
class SubtitleTranslationSettings {
  const SubtitleTranslationSettings({
    this.providerId = 'google_free',
    this.targetLang = 'zh-CN',
    this.useCache = true,
    this.bilingual = false,
  });

  factory SubtitleTranslationSettings.fromMap(Map<dynamic, dynamic> map) =>
      SubtitleTranslationSettings(
        providerId: map['providerId'] as String? ?? 'google_free',
        targetLang: map['targetLang'] as String? ?? 'zh-CN',
        useCache: map['useCache'] as bool? ?? true,
        bilingual: map['bilingual'] as bool? ?? false,
      );

  final String providerId;
  final String targetLang;
  final bool useCache;
  final bool bilingual;

  TranslationLang get targetLangEnum => TranslationLang.fromBcp47(targetLang);

  SubtitleTranslationSettings copyWith({
    String? providerId,
    String? targetLang,
    bool? useCache,
    bool? bilingual,
  }) =>
      SubtitleTranslationSettings(
        providerId: providerId ?? this.providerId,
        targetLang: targetLang ?? this.targetLang,
        useCache: useCache ?? this.useCache,
        bilingual: bilingual ?? this.bilingual,
      );

  Map<String, dynamic> toMap() => {
        'providerId': providerId,
        'targetLang': targetLang,
        'useCache': useCache,
        'bilingual': bilingual,
      };
}

class SubtitleTranslationSettingsNotifier
    extends StateNotifier<SubtitleTranslationSettings> {
  SubtitleTranslationSettingsNotifier() : super(const SubtitleTranslationSettings()) {
    _load();
  }

  static const _boxName = 'video_settings';
  static const _key = 'subtitle_translation';

  Future<void> _load() async {
    try {
      final box = await Hive.openBox<Map<dynamic, dynamic>>(_boxName);
      final data = box.get(_key);
      if (data != null) {
        state = SubtitleTranslationSettings.fromMap(data);
      }
    } on Exception catch (_) {
      // 使用默认值
    }
  }

  Future<void> _save() async {
    try {
      final box = await Hive.openBox<Map<dynamic, dynamic>>(_boxName);
      await box.put(_key, state.toMap());
    } on Exception catch (_) {
      // 忽略保存错误
    }
  }

  void setProvider(String id) {
    state = state.copyWith(providerId: id);
    _save();
  }

  void setTargetLang(String bcp47) {
    state = state.copyWith(targetLang: bcp47);
    _save();
  }

  void setUseCache({required bool value}) {
    state = state.copyWith(useCache: value);
    _save();
  }

  void setBilingual({required bool value}) {
    state = state.copyWith(bilingual: value);
    _save();
  }
}

final subtitleTranslationSettingsProvider = StateNotifierProvider<
    SubtitleTranslationSettingsNotifier, SubtitleTranslationSettings>(
  (ref) => SubtitleTranslationSettingsNotifier(),
);
