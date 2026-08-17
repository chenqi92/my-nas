import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/shared/providers/interface_locale_provider.dart';
import 'package:my_nas/shared/providers/language_preference_provider.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';
import 'package:my_nas/shared/widgets/atoms/app_button.dart';
import 'package:my_nas/shared/widgets/atoms/app_segmented.dart';
import 'package:my_nas/shared/widgets/atoms/settings_atoms.dart';

/// 桌面「设置 · 语言与地区」详情 pane。
///
/// 对齐设计稿 `settings.jsx` 的 `PaneLanguage`：界面语言分段 + 元数据 / 音轨 /
/// 字幕三组可拖拽语言优先级。
///
/// - 优先级三组接 [languagePreferenceProvider]，可拖拽排序 / 添加 / 移除，
///   实时写回 Hive 并同步 TMDB / 字幕 / 音轨服务。
/// - 界面语言接 [interfaceLocaleProvider]，简体中文 / English / 跟随系统三选，
///   实时生效并持久化于 Hive。
class LanguagePane extends ConsumerWidget {
  const LanguagePane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final pref = ref.watch(languagePreferenceProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SetHead(
          icon: Icons.language_rounded,
          title: l.paneLanguageHeadTitle,
          subtitle: l.paneLanguageHeadSubtitle,
        ),

        // 界面语言（简体中文 / English / 跟随系统）。
        SetSection(
          title: l.paneLanguageInterfaceSection,
          hint: 'language_preference',
          children: [
            SetRow(
              title: l.paneLanguageInterfaceRowTitle,
              desc: l.paneLanguageInterfaceRowDesc,
              last: true,
              trailing: const _InterfaceLanguageControl(),
            ),
          ],
        ),

        // 元数据语言优先级（全宽）。
        _PrioritySection(
          title: l.paneLanguageMetadataSection,
          name: l.paneLanguageMetadataName,
          hint: l.paneLanguageMetadataHint,
          type: LanguageType.metadata,
          languages: pref.metadataLanguages,
          options: LanguageOption.metadataLanguages,
        ),

        // 音频 + 字幕优先级（设计稿为两列，桌面外壳宽度有限故纵向堆叠）。
        _PrioritySection(
          title: l.paneLanguageAudioSection,
          name: l.paneLanguageAudioName,
          hint: l.paneLanguageAudioHint,
          type: LanguageType.audio,
          languages: pref.audioLanguages,
          options: LanguageOption.audioSubtitleLanguages,
        ),
        _PrioritySection(
          title: l.paneLanguageSubtitleSection,
          name: l.paneLanguageSubtitleName,
          hint: l.paneLanguageSubtitleHint,
          type: LanguageType.subtitle,
          languages: pref.subtitleLanguages,
          options: LanguageOption.audioSubtitleLanguages,
        ),

        const _PriorityNote(),
      ],
    );
  }
}

/// 界面语言：简体中文 / English / 跟随系统三选，实时生效并持久化。
class _InterfaceLanguageControl extends ConsumerWidget {
  const _InterfaceLanguageControl();

  static const _system = 'system';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final locale = ref.watch(interfaceLocaleProvider);
    final current = locale?.languageCode ?? _system;

    return AppSegmented<String>(
      options: [
        AppSegmentedOption(value: 'zh', label: l.paneLanguageOptionZh),
        AppSegmentedOption(value: 'en', label: l.paneLanguageOptionEn),
        AppSegmentedOption(value: _system, label: l.paneLanguageFollowSystem),
      ],
      value: current,
      onChanged: (code) {
        ref.read(interfaceLocaleProvider.notifier).setLocale(
              code == _system ? null : Locale(code),
            );
      },
    );
  }
}

/// 一组语言优先级：分组卡片内含可拖拽列表 + 「添加语言」按钮。
class _PrioritySection extends ConsumerWidget {
  const _PrioritySection({
    required this.title,
    required this.name,
    required this.hint,
    required this.type,
    required this.languages,
    required this.options,
  });

  final String title;
  final String name;
  final String hint;
  final LanguageType type;
  final List<LanguageOption> languages;
  final List<LanguageOption> options;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    final notifier = ref.read(languagePreferenceProvider.notifier);
    final canRemove = languages.length > 1;
    final remaining =
        options.where((o) => !languages.contains(o)).toList(growable: false);

    return SetSection(
      title: title,
      hint: hint,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: languages.length,
            onReorder: (oldIndex, newIndex) =>
                notifier.reorderLanguages(type, oldIndex, newIndex),
            proxyDecorator: (child, index, animation) => Material(
              color: Colors.transparent,
              child: child,
            ),
            itemBuilder: (context, index) {
              final lang = languages[index];
              return _LanguageTile(
                key: ValueKey('${type.name}-${lang.code}'),
                index: index,
                language: lang,
                priority: index + 1,
                canRemove: canRemove,
                onRemove: () => notifier.removeLanguage(type, lang),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 14),
          child: Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              label: l.paneLanguageAddButton,
              icon: Icons.add_rounded,
              dense: true,
              onPressed: remaining.isEmpty
                  ? null
                  : () async {
                      final picked = await _pickLanguage(context, t, remaining);
                      if (picked != null) {
                        await notifier.addLanguage(type, picked);
                      }
                    },
            ),
          ),
        ),
      ],
    );
  }

  Future<LanguageOption?> _pickLanguage(
    BuildContext context,
    DesignTokens t,
    List<LanguageOption> remaining,
  ) {
    final l = AppLocalizations.of(context);
    return showAdaptiveModalSheet<LanguageOption>(
        context: context,
        backgroundColor: t.cardBg,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Text(
                      l.paneLanguageAddSheetTitle(name),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: t.text0,
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final o in remaining)
                      ListTile(
                        title: Text(
                          o.displayName,
                          style: TextStyle(color: t.text0, fontSize: 14),
                        ),
                        subtitle: Text(
                          o.nativeName,
                          style: TextStyle(color: t.text2, fontSize: 12),
                        ),
                        onTap: () => Navigator.of(context).pop(o),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
  }
}

/// 优先级列表中的一行：拖拽手柄 + 序号徽标 + 语言名 + 移除。
class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.index,
    required this.language,
    required this.priority,
    required this.canRemove,
    required this.onRemove,
    super.key,
  });

  final int index;
  final LanguageOption language;
  final int priority;
  final bool canRemove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: t.insetBg,
          borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
          border: Border.all(color: t.hairline, width: 0.5),
        ),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: Icon(Icons.drag_indicator_rounded,
                    size: 18, color: t.text3),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: t.chipBgActive,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$priority',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: t.accentBright,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                children: [
                  Text(
                    language.displayName,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: t.text0,
                    ),
                  ),
                  if (language.nativeName != language.displayName) ...[
                    const SizedBox(width: 8),
                    Text(
                      language.nativeName,
                      style: TextStyle(fontSize: 12, color: t.text2),
                    ),
                  ],
                ],
              ),
            ),
            if (canRemove)
              IconButton(
                visualDensity: VisualDensity.compact,
                splashRadius: 18,
                tooltip: l.paneLanguageRemoveTooltip,
                icon: Icon(Icons.close_rounded, size: 16, color: t.text3),
                onPressed: onRemove,
              ),
          ],
        ),
      ),
    );
  }
}

/// 设计稿底部 Note：解释拖拽排序与回退行为。
class _PriorityNote extends StatelessWidget {
  const _PriorityNote();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        l.paneLanguagePriorityNote,
        style: TextStyle(fontSize: 12, height: 1.5, color: t.text3),
      ),
    );
  }
}
