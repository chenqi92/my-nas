import 'package:my_nas/core/translation/google_free_translation_provider.dart';
import 'package:my_nas/core/translation/translation_provider.dart';

/// 注册中心：列出 app 支持的全部翻译 provider，按 id 查表。
class TranslationProviders {
  TranslationProviders._();

  static final Map<String, TranslationProvider> _byId = {
    'google_free': GoogleFreeTranslationProvider(),
  };

  static List<TranslationProvider> get all => _byId.values.toList(growable: false);

  static TranslationProvider get defaultProvider => _byId['google_free']!;

  static TranslationProvider byId(String? id) {
    if (id == null) return defaultProvider;
    return _byId[id] ?? defaultProvider;
  }
}
