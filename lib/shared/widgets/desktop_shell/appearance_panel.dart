import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/color_scheme_preset.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/app/theme/ui_style.dart';
import 'package:my_nas/shared/providers/dynamic_ambient_provider.dart';
import 'package:my_nas/shared/providers/theme_provider.dart';
import 'package:my_nas/shared/providers/ui_style_provider.dart';
import 'package:my_nas/shared/widgets/atoms/app_segmented.dart';
import 'package:my_nas/shared/widgets/atoms/app_switch.dart';

/// 设计稿 `.appearance-menu`：topbar palette 按钮唤起的悬浮设置 popover。
/// 包含：主题模式 / UI 风格 / 强调色 / 动态取色氛围光。
class AppearancePanel extends ConsumerWidget {
  const AppearancePanel({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DesignTokens.of(context);
    final themeMode = ref.watch(themeModeProvider);
    final uiStyle = ref.watch(uiStyleProvider);
    final preset = ref.watch(colorSchemePresetProvider);

    return SizedBox(
      width: 288,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Row(
            label: '主题',
            control: AppSegmented<ThemeMode>(
              value: themeMode,
              onChanged: ref.read(themeModeProvider.notifier).setThemeMode,
              dense: true,
              options: const [
                AppSegmentedOption(value: ThemeMode.light, label: '浅色'),
                AppSegmentedOption(value: ThemeMode.dark, label: '深色'),
                AppSegmentedOption(value: ThemeMode.system, label: '系统'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Row(
            label: 'UI 风格',
            control: AppSegmented<UIStyle>(
              value: uiStyle,
              onChanged: ref.read(uiStyleProvider.notifier).setStyle,
              dense: true,
              options: const [
                AppSegmentedOption(value: UIStyle.glass, label: 'Glass'),
                AppSegmentedOption(value: UIStyle.classic, label: 'Classic'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Row(
            label: '强调色',
            control: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final p in ColorSchemePresets.all)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: _AccentSwatch(
                      preset: p,
                      selected: p.id == preset.id,
                      onTap: () => ref
                          .read(colorSchemePresetProvider.notifier)
                          .setPreset(p),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: t.hairline),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  '动态取色氛围光',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: t.text1,
                  ),
                ),
              ),
              AppSwitch(
                value: ref.watch(dynamicAmbientProvider),
                onChanged: (v) => ref
                    .read(dynamicAmbientProvider.notifier)
                    .setEnabled(enabled: v),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.control});
  final String label;
  final Widget control;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: t.text1,
          ),
        ),
        const Spacer(),
        control,
      ],
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final ColorSchemePreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: preset.primary,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: selected
                    ? DesignTokens.of(context).text0
                    : Colors.transparent,
                width: 2,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: preset.primary.withValues(alpha: 0.6),
                        blurRadius: 8,
                      ),
                    ]
                  : null,
            ),
          ),
        ),
      );
}
