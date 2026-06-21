import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/reading/data/services/reader_settings_service.dart';
import 'package:my_nas/features/reading/presentation/providers/reader_settings_provider.dart';
import 'package:my_nas/shared/mixins/tab_bar_visibility_mixin.dart';
import 'package:my_nas/shared/providers/ui_style_provider.dart';
import 'package:my_nas/shared/widgets/adaptive_glass_container.dart';
import 'package:my_nas/shared/widgets/rounded_back_button.dart';

/// 图书设置页面
///
/// 提供图书阅读相关的设置选项：
/// - 阅读器引擎选择（原生/WebView）
/// - 其他图书相关设置
class BookSettingsPage extends ConsumerWidget {
  const BookSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final uiStyle = ref.watch(uiStyleProvider);
    final settings = ref.watch(bookReaderSettingsProvider);

    return HideBottomNavWrapper(
      child: Scaffold(
        backgroundColor: isDark ? AppColors.darkBackground : null,
        appBar: AppBar(
          leading: const RoundedBackButton(),
          title: Text(context.l10n.bookSettingsPageTitle),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: ListView(
        padding: AppSpacing.paddingMd,
        children: [
          // 阅读器设置
          _buildSectionHeader(context, context.l10n.bookSettingsReaderSectionTitle, Icons.auto_stories_rounded, isDark),
          const SizedBox(height: AppSpacing.sm),
          AdaptiveGlassContainer(
            uiStyle: uiStyle,
            isDark: isDark,
            cornerRadius: 20,
            child: Column(
              children: [
                _buildEngineTile(context, ref, settings, isDark),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          // 引擎说明
          AdaptiveGlassContainer(
            uiStyle: uiStyle,
            isDark: isDark,
            cornerRadius: 16,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 18,
                        color: AppColors.info,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        context.l10n.bookSettingsEngineInfoTitle,
                        style: context.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildEngineInfo(
                    context,
                    isDark,
                    title: context.l10n.bookSettingsNativeEngineTitle,
                    description: context.l10n.bookSettingsNativeEngineDesc,
                    icon: Icons.speed_rounded,
                  ),
                  const SizedBox(height: 8),
                  _buildEngineInfo(
                    context,
                    isDark,
                    title: context.l10n.bookSettingsWebViewEngineTitle,
                    description: context.l10n.bookSettingsWebViewEngineDesc,
                    icon: Icons.web_rounded,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, IconData icon, bool isDark) =>
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

  Widget _buildEngineTile(
    BuildContext context,
    WidgetRef ref,
    BookReaderSettings settings,
    bool isDark,
  ) {
    final isNative = settings.epubEngine == EpubReaderEngine.native;

    return Padding(
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
              color: AppColors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.memory_rounded,
              color: AppColors.accent,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.bookSettingsRenderEngineLabel,
                  style: context.textTheme.bodyLarge?.copyWith(
                    color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isNative ? context.l10n.bookSettingsNativeEngineFast : context.l10n.bookSettingsWebViewEngineStable,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: isDark
                        ? AppColors.darkOnSurfaceVariant
                        : AppColors.lightOnSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          // 切换开关
          _buildEngineSwitch(context, ref, settings, isDark),
        ],
      ),
    );
  }

  Widget _buildEngineSwitch(
    BuildContext context,
    WidgetRef ref,
    BookReaderSettings settings,
    bool isDark,
  ) {
    final isNative = settings.epubEngine == EpubReaderEngine.native;

    // 内层胶囊半径 = 外层 - padding，保证选中态胶囊不会突出底层背景
    const outerRadius = 18.0;
    const innerPadding = 3.0;
    const innerRadius = outerRadius - innerPadding;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurfaceVariant.withValues(alpha: 0.5)
            : AppColors.lightSurfaceVariant.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(outerRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(innerPadding),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildEngineOption(
              context,
              ref,
              label: context.l10n.bookSettingsEngineOptionNative,
              isSelected: isNative,
              isDark: isDark,
              radius: innerRadius,
              onTap: () => ref.read(bookReaderSettingsProvider.notifier)
                  .setEpubEngine(EpubReaderEngine.native),
            ),
            _buildEngineOption(
              context,
              ref,
              label: context.l10n.bookSettingsEngineOptionWebView,
              isSelected: !isNative,
              isDark: isDark,
              radius: innerRadius,
              onTap: () => ref.read(bookReaderSettingsProvider.notifier)
                  .setEpubEngine(EpubReaderEngine.foliate),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEngineOption(
    BuildContext context,
    WidgetRef ref, {
    required String label,
    required bool isSelected,
    required bool isDark,
    required double radius,
    required VoidCallback onTap,
  }) => GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary
              : Colors.transparent,
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected
                ? Colors.white
                : (isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant),
          ),
        ),
      ),
    );

  Widget _buildEngineInfo(
    BuildContext context,
    bool isDark, {
    required String title,
    required String description,
    required IconData icon,
  }) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 16,
          color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: context.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                ),
              ),
              Text(
                description,
                style: context.textTheme.bodySmall?.copyWith(
                  color: isDark
                      ? AppColors.darkOnSurfaceVariant
                      : AppColors.lightOnSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
}
