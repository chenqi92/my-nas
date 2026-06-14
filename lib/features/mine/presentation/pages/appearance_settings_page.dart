import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/app/theme/color_scheme_preset.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/app/theme/ui_style.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/shared/mixins/tab_bar_visibility_mixin.dart';
import 'package:my_nas/shared/providers/theme_provider.dart';
import 'package:my_nas/shared/providers/ui_style_provider.dart';
import 'package:my_nas/shared/widgets/atoms/app_segmented.dart';
import 'package:my_nas/shared/widgets/atoms/settings_atoms.dart';
import 'package:my_nas/shared/widgets/rounded_back_button.dart';

/// 外观设置页面
class AppearanceSettingsPage extends ConsumerStatefulWidget {
  const AppearanceSettingsPage({super.key});

  @override
  ConsumerState<AppearanceSettingsPage> createState() => _AppearanceSettingsPageState();
}

class _AppearanceSettingsPageState extends ConsumerState<AppearanceSettingsPage>
    with ConsumerTabBarVisibilityMixin {
  @override
  void initState() {
    super.initState();
    hideTabBar();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeMode = ref.watch(themeModeProvider);
    final colorPreset = ref.watch(colorSchemePresetProvider);
    final uiStyle = ref.watch(uiStyleProvider);

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : null,
      appBar: AppBar(
        leading: const RoundedBackButton(),
        backgroundColor: isDark ? AppColors.darkSurface : null,
        title: Text(
          '外观设置',
          style: TextStyle(
            color: isDark ? AppColors.darkOnSurface : null,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: IconThemeData(
          color: isDark ? AppColors.darkOnSurface : null,
        ),
      ),
      body: context.isDesktopLayout
          ? _buildDesktopBody(context, themeMode, uiStyle, colorPreset)
          : ListView(
              padding: AppSpacing.paddingMd,
              children: [
                // 主题模式
                _buildSectionHeader(context, '主题模式', Icons.brightness_6_rounded, isDark),
                const SizedBox(height: AppSpacing.sm),
                _buildSettingsCard(
                  context,
                  isDark,
                  children: [
                    for (var i = 0; i < ThemeMode.values.length; i++) ...[
                      if (i > 0) _buildDivider(isDark),
                      _buildThemeOption(context, ThemeMode.values[i], themeMode, isDark),
                    ],
                  ],
                ),

                const SizedBox(height: AppSpacing.xl),

                // UI 风格
                _buildSectionHeader(context, 'UI 风格', Icons.dashboard_customize_rounded, isDark),
                const SizedBox(height: AppSpacing.sm),
                _buildSettingsCard(
                  context,
                  isDark,
                  children: [
                    for (var i = 0; i < UIStyle.values.length; i++) ...[
                      if (i > 0) _buildDivider(isDark),
                      _buildUIStyleOption(context, UIStyle.values[i], uiStyle, isDark),
                    ],
                  ],
                ),

                const SizedBox(height: AppSpacing.xl),

                // 配色方案
                _buildSectionHeader(context, '配色方案', Icons.color_lens_rounded, isDark),
                const SizedBox(height: AppSpacing.sm),
                _buildColorSchemeGrid(context, colorPreset, isDark),

                const SizedBox(height: AppSpacing.xxxl),
              ],
            ),
    );
  }

  // ─── 桌面端设计语言分支 ───────────────────────────────────

  Widget _buildDesktopBody(
    BuildContext context,
    ThemeMode themeMode,
    UIStyle uiStyle,
    ColorSchemePreset colorPreset,
  ) {
    final t = DesignTokens.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(38, 32, 38, 96),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: Column(
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
                    last: true,
                    trailing: Wrap(
                      spacing: 9,
                      runSpacing: 9,
                      children: [
                        for (final preset in ColorSchemePresets.all)
                          _buildDesktopAccentDot(t, preset, colorPreset),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopAccentDot(
    DesignTokens t,
    ColorSchemePreset preset,
    ColorSchemePreset current,
  ) {
    final isSelected = preset.id == current.id;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => ref.read(colorSchemePresetProvider.notifier).setPreset(preset),
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

  // ─── Section Header ──────────────────────────────────────

  Widget _buildSectionHeader(
    BuildContext context,
    String title,
    IconData icon,
    bool isDark,
  ) =>
      Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 16,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: context.textTheme.titleSmall?.copyWith(
              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      );

  // ─── Settings Card ───────────────────────────────────────

  Widget _buildSettingsCard(
    BuildContext context,
    bool isDark, {
    required List<Widget> children,
  }) =>
      DecoratedBox(
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.darkSurfaceVariant.withValues(alpha: 0.3)
              : AppColors.lightSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark
                ? AppColors.darkOutline.withValues(alpha: 0.2)
                : AppColors.lightOutline.withValues(alpha: 0.3),
          ),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(children: children),
        ),
      );

  Widget _buildDivider(bool isDark) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Divider(
          height: 1,
          color: isDark
              ? AppColors.darkOutline.withValues(alpha: 0.2)
              : AppColors.lightOutline.withValues(alpha: 0.3),
        ),
      );

  // ─── Theme Mode ──────────────────────────────────────────

  String _getThemeModeText(ThemeMode mode) => switch (mode) {
        ThemeMode.system => '跟随系统',
        ThemeMode.light => '浅色模式',
        ThemeMode.dark => '深色模式',
      };

  IconData _getThemeModeIcon(ThemeMode mode) => switch (mode) {
        ThemeMode.system => Icons.brightness_auto_rounded,
        ThemeMode.light => Icons.light_mode_rounded,
        ThemeMode.dark => Icons.dark_mode_rounded,
      };

  Widget _buildThemeOption(
    BuildContext context,
    ThemeMode mode,
    ThemeMode currentMode,
    bool isDark,
  ) {
    final isSelected = mode == currentMode;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => ref.read(themeModeProvider.notifier).setThemeMode(mode),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Container(
                width: context.isDesktopLayout ? 32 : 40,
                height: context.isDesktopLayout ? 32 : 40,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary.withValues(alpha: 0.15)
                      : (isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant)
                          .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(context.isDesktopLayout ? 8 : 12),
                ),
                child: Icon(
                  _getThemeModeIcon(mode),
                  color: isSelected
                      ? AppColors.primary
                      : (isDark
                          ? AppColors.darkOnSurfaceVariant
                          : AppColors.lightOnSurfaceVariant),
                  size: context.isDesktopLayout ? 18 : 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  _getThemeModeText(mode),
                  style: context.textTheme.bodyLarge?.copyWith(
                    color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              if (isSelected)
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.primaryGradient,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── UI Style ────────────────────────────────────────────

  Widget _buildUIStyleOption(
    BuildContext context,
    UIStyle style,
    UIStyle currentStyle,
    bool isDark,
  ) {
    final isSelected = style == currentStyle;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => ref.read(uiStyleProvider.notifier).setStyle(style),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary.withValues(alpha: 0.15)
                      : (isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant)
                          .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  style.icon,
                  color: isSelected
                      ? AppColors.primary
                      : (isDark
                          ? AppColors.darkOnSurfaceVariant
                          : AppColors.lightOnSurfaceVariant),
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  style.label,
                  style: context.textTheme.bodyLarge?.copyWith(
                    color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              if (isSelected)
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.primaryGradient,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Color Scheme ────────────────────────────────────────

  Widget _buildColorSchemeGrid(
    BuildContext context,
    ColorSchemePreset currentPreset,
    bool isDark,
  ) => GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.3,
        crossAxisSpacing: AppSpacing.md,
        mainAxisSpacing: AppSpacing.md,
      ),
      itemCount: ColorSchemePresets.all.length,
      itemBuilder: (context, index) {
        final preset = ColorSchemePresets.all[index];
        final isSelected = currentPreset.id == preset.id;
        return _buildColorSchemeCard(context, preset, isSelected, isDark);
      },
    );

  Widget _buildColorSchemeCard(
    BuildContext context,
    ColorSchemePreset preset,
    bool isSelected,
    bool isDark,
  ) =>
      Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => ref.read(colorSchemePresetProvider.notifier).setPreset(preset),
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkSurfaceVariant.withValues(alpha: 0.5)
                  : AppColors.lightSurfaceVariant.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? preset.primary : Colors.transparent,
                width: 2,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 颜色预览圆点
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildColorDot(preset.primary, 20),
                    const SizedBox(width: 6),
                    _buildColorDot(preset.secondary, 16),
                    const SizedBox(width: 6),
                    _buildColorDot(preset.accent, 14),
                    const SizedBox(width: 6),
                    _buildColorDot(preset.darkBackground, 12),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  preset.name,
                  style: context.textTheme.titleSmall?.copyWith(
                    color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                  child: Text(
                    preset.description,
                    style: context.textTheme.bodySmall?.copyWith(
                      color: isDark
                          ? AppColors.darkOnSurfaceVariant
                          : AppColors.lightOnSurfaceVariant,
                      fontSize: 10,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isSelected) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: preset.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_rounded, size: 12, color: preset.primary),
                        const SizedBox(width: 2),
                        Text(
                          '当前',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: preset.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );

  Widget _buildColorDot(Color color, double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
      );
}
