import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/color_scheme_preset.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/app/theme/ui_style.dart';
import 'package:my_nas/shared/providers/dynamic_ambient_provider.dart';
import 'package:my_nas/shared/providers/glass_material_provider.dart';
import 'package:my_nas/shared/providers/theme_provider.dart';
import 'package:my_nas/shared/providers/ui_style_provider.dart';
import 'package:my_nas/shared/widgets/atoms/app_segmented.dart';
import 'package:my_nas/shared/widgets/atoms/app_switch.dart';
import 'package:my_nas/shared/widgets/atoms/settings_atoms.dart';

/// 桌面「设置 · 外观」详情 pane。
///
/// 主题、配色、UI 风格与玻璃材质参数。Glass / Classic 为实时全局开关。
/// 外壳负责滚动与 padding + maxWidth 居中，这里只返回内容 Column。
class AppearancePane extends ConsumerWidget {
  const AppearancePane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DesignTokens.of(context);
    final themeMode = ref.watch(themeModeProvider);
    final uiStyle = ref.watch(uiStyleProvider);
    final colorPreset = ref.watch(colorSchemePresetProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SetHead(
          icon: Icons.palette_outlined,
          title: '外观',
          subtitle: '主题、配色与 UI 风格。Glass / Classic 为实时全局开关。',
        ),
        SetSection(
          title: '主题与配色',
          hint: 'theme_mode · color_scheme_preset',
          children: [
            SetRow(
              title: '主题模式',
              desc: '浅色 / 深色 / 跟随系统',
              trailing: AppSegmented<ThemeMode>(
                value: themeMode,
                onChanged: ref.read(themeModeProvider.notifier).setThemeMode,
                options: const [
                  AppSegmentedOption(value: ThemeMode.light, label: '浅色'),
                  AppSegmentedOption(value: ThemeMode.dark, label: '深色'),
                  AppSegmentedOption(value: ThemeMode.system, label: '系统'),
                ],
              ),
            ),
            SetRow(
              title: 'UI 风格',
              desc: '玻璃材质 / 经典卡片 — 实时切换',
              trailing: AppSegmented<UIStyle>(
                value: uiStyle,
                onChanged: ref.read(uiStyleProvider.notifier).setStyle,
                options: [
                  for (final style in UIStyle.values)
                    AppSegmentedOption(
                      value: style,
                      label: style.isGlass ? 'Glass' : 'Classic',
                    ),
                ],
              ),
            ),
            SetRow(
              title: '强调色',
              desc: '预设方案，可被封面动态取色临时覆盖',
              trailing: Wrap(
                spacing: 9,
                runSpacing: 9,
                children: [
                  for (final preset in ColorSchemePresets.all)
                    _AccentDot(
                      preset: preset,
                      current: colorPreset,
                    ),
                ],
              ),
            ),
            SetRow(
              title: '动态取色氛围光',
              desc: '播放时外壳氛围光随封面 / 台标取色',
              last: true,
              trailing: AppSwitch(
                value: ref.watch(dynamicAmbientProvider),
                onChanged: (v) => ref
                    .read(dynamicAmbientProvider.notifier)
                    .setEnabled(enabled: v),
              ),
            ),
          ],
        ),
        _buildGlassSection(ref, t, uiStyle),
      ],
    );
  }

  // ─── 玻璃材质参数（仅 Glass 风格可调）──────────────────────

  Widget _buildGlassSection(WidgetRef ref, DesignTokens t, UIStyle uiStyle) {
    if (!uiStyle.isGlass) {
      return const SetSection(
        title: '玻璃材质参数',
        hint: 'glass_blur_scale · glass_opacity_scale · glass_blur_enabled',
        bottomMargin: false,
        children: [
          SetRow(
            title: '已停用',
            desc: 'Classic 风格下玻璃参数已停用，切换到 Glass 风格后可调。',
            last: true,
          ),
        ],
      );
    }

    final blurScale = ref.watch(glassBlurScaleProvider);
    final opacityScale = ref.watch(glassOpacityScaleProvider);
    final blurEnabled = ref.watch(glassBlurEnabledProvider);

    return SetSection(
      title: '玻璃材质参数',
      hint: 'glass_blur_scale · glass_opacity_scale · glass_blur_enabled',
      bottomMargin: false,
      children: [
        SetRow(
          title: '模糊强度',
          desc: '玻璃面板高斯模糊半径缩放（${blurScale.toStringAsFixed(2)}×）',
          trailing: _GlassSlider(
            value: blurScale,
            enabled: blurEnabled,
            onChanged: (v) =>
                ref.read(glassBlurScaleProvider.notifier).setValue(v),
          ),
        ),
        SetRow(
          title: '材质不透明度',
          desc: '玻璃面板背景不透明度缩放（${opacityScale.toStringAsFixed(2)}×）',
          trailing: _GlassSlider(
            value: opacityScale,
            onChanged: (v) =>
                ref.read(glassOpacityScaleProvider.notifier).setValue(v),
          ),
        ),
        SetRow(
          title: '平台玻璃优化',
          desc: '关闭后玻璃面板不再做模糊，仅保留半透明材质',
          last: true,
          trailing: AppSwitch(
            value: blurEnabled,
            onChanged: (v) => ref
                .read(glassBlurEnabledProvider.notifier)
                .setEnabled(enabled: v),
          ),
        ),
      ],
    );
  }
}

/// 玻璃材质缩放滑块（0.5×–1.5×）。
class _GlassSlider extends StatelessWidget {
  const _GlassSlider({
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return SizedBox(
      width: 140,
      child: SliderTheme(
        data: SliderThemeData(
          trackHeight: 3,
          activeTrackColor: enabled ? t.accent : t.text3,
          inactiveTrackColor: t.insetBg,
          thumbColor: enabled ? t.accentBright : t.text3,
          overlayColor: t.accent.withValues(alpha: 0.12),
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        ),
        child: Slider(
          value: value,
          min: 0.5,
          max: 1.5,
          divisions: 10,
          onChanged: enabled ? onChanged : null,
        ),
      ),
    );
  }
}

/// 强调色预设色点（选中时描边 text0）。
class _AccentDot extends ConsumerWidget {
  const _AccentDot({
    required this.preset,
    required this.current,
  });

  final ColorSchemePreset preset;
  final ColorSchemePreset current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DesignTokens.of(context);
    final isSelected = preset.id == current.id;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () =>
          ref.read(colorSchemePresetProvider.notifier).setPreset(preset),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: preset.primary,
          borderRadius: BorderRadius.circular(8),
          border: isSelected ? Border.all(color: t.text0, width: 2) : null,
        ),
      ),
    );
  }
}
