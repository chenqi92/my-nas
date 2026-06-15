import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/utils/hive_utils.dart';

/// 「界面语言」设置：手动指定应用界面语言，或跟随系统。
///
/// 状态为 [Locale]?，`null` 表示跟随系统语言。受支持语言仅 `en` / `zh`
/// （对齐 `AppLocalizations.supportedLocales`）。持久化于 settings box，
/// key 存语言码（`zh` / `en`），空串或缺失表示跟随系统。
final interfaceLocaleProvider =
    StateNotifierProvider<InterfaceLocaleNotifier, Locale?>(
  (ref) => InterfaceLocaleNotifier(),
);

class InterfaceLocaleNotifier extends StateNotifier<Locale?> {
  InterfaceLocaleNotifier() : super(null) {
    _load();
  }

  static const _key = 'interface_locale';

  /// 受支持的界面语言码（对齐 AppLocalizations.supportedLocales）。
  static const _supported = {'en', 'zh'};

  Future<void> _load() async {
    try {
      final box = await HiveUtils.getSettingsBox();
      final code = box.get(_key) as String?;
      if (code != null && _supported.contains(code)) {
        state = Locale(code);
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '加载界面语言设置失败，使用跟随系统');
    }
  }

  /// 设置界面语言。传 `null` 表示跟随系统（持久化为空串）。
  Future<void> setLocale(Locale? locale) async {
    final next = (locale != null && _supported.contains(locale.languageCode))
        ? Locale(locale.languageCode)
        : null;
    state = next;
    try {
      final box = await HiveUtils.getSettingsBox();
      await box.put(_key, next?.languageCode ?? '');
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '保存界面语言设置失败');
    }
  }
}
