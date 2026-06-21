import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/video/presentation/providers/playback_settings_provider.dart';
import 'package:my_nas/features/video/presentation/widgets/aspect_ratio_selector.dart';
import 'package:my_nas/features/video/presentation/widgets/subtitle_style_sheet.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';
import 'package:my_nas/shared/widgets/sheet_drag_handle.dart';

/// 显示高级设置面板
void showAdvancedSettingsSheet(BuildContext context) {
  showAdaptiveModalSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => const AdvancedSettingsSheet(),
  );
}

/// 高级设置面板
///
/// 包含所有高级播放设置：
/// - 字幕样式
/// - 画面比例
/// - 自动播放设置
/// - 记住播放位置
/// - 快进/快退秒数
/// - 默认音量
/// - 默认播放速度
/// - 清除播放记录
class AdvancedSettingsSheet extends ConsumerWidget {
  const AdvancedSettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = ref.watch(playbackSettingsProvider);
    final notifier = ref.read(playbackSettingsProvider.notifier);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      builder: (context, scrollController) => DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // 拖拽指示器
            const SheetDragHandle(bottomPadding: 0),

            // 标题栏
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.musicColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.tune_rounded,
                      color: AppColors.musicColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    context.l10n.videoAdvancedSettingsTitle,
                    style: context.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // 设置列表
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                children: [
                  _SectionHeader(
                    title: context.l10n.videoAdvancedDisplaySection,
                    icon: Icons.display_settings_rounded,
                    color: AppColors.downloadColor,
                  ),

                  // 字幕样式
                  ListTile(
                    leading: _buildIcon(Icons.text_format_rounded, AppColors.downloadColor),
                    title: Text(context.l10n.videoAdvancedSubtitleStyleTitle),
                    subtitle: Text(context.l10n.videoAdvancedSubtitleStyleSubtitle),
                    trailing: const Icon(Icons.chevron_right),
                    contentPadding: EdgeInsets.zero,
                    onTap: () {
                      Navigator.pop(context);
                      showSubtitleStyleSheet(context);
                    },
                  ),

                  // 画面比例
                  ListTile(
                    leading: _buildIcon(Icons.aspect_ratio_rounded, AppColors.aiColor),
                    title: Text(context.l10n.videoAdvancedAspectRatioTitle),
                    subtitle: Text(context.l10n.videoAdvancedAspectRatioSubtitle),
                    trailing: const Icon(Icons.chevron_right),
                    contentPadding: EdgeInsets.zero,
                    onTap: () {
                      Navigator.pop(context);
                      showAspectRatioSelector(context);
                    },
                  ),

                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),

                  _SectionHeader(
                    title: context.l10n.videoAdvancedPlaybackSection,
                    icon: Icons.play_circle_outline_rounded,
                    color: AppColors.success,
                  ),

                  // 自动播放下一个
                  SwitchListTile(
                    secondary: _buildIcon(Icons.skip_next_rounded, AppColors.success),
                    title: Text(context.l10n.videoAdvancedAutoPlayNextTitle),
                    subtitle: Text(context.l10n.videoAdvancedAutoPlayNextSubtitle),
                    value: settings.autoPlayNext,
                    onChanged: (value) {
                      notifier.setAutoPlayNext(enabled: value);
                    },
                    contentPadding: EdgeInsets.zero,
                  ),

                  SwitchListTile(
                    secondary: _buildIcon(Icons.history_rounded, AppColors.warning),
                    title: Text(context.l10n.videoAdvancedRememberPositionTitle),
                    subtitle: Text(context.l10n.videoAdvancedRememberPositionSubtitle),
                    value: settings.rememberPosition,
                    onChanged: (value) {
                      notifier.setRememberPosition(enabled: value);
                    },
                    contentPadding: EdgeInsets.zero,
                  ),

                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),

                  _SectionHeader(
                    title: context.l10n.videoAdvancedControlSection,
                    icon: Icons.touch_app_rounded,
                    color: AppColors.musicColor,
                  ),

                  // 快进快退秒数
                  _buildSection(
                    context,
                    icon: Icons.fast_forward_rounded,
                    iconColor: AppColors.musicColor,
                    title: context.l10n.videoAdvancedSeekIntervalTitle,
                    subtitle: context.l10n.videoAdvancedSeekIntervalSubtitle,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: availableSeekIntervals.map((s) {
                        final isSelected = s == settings.seekInterval;
                        return ChoiceChip(
                          label: Text('$s${context.l10n.videoAdvancedSeekIntervalSuffix}'),
                          selected: isSelected,
                          onSelected: (_) => notifier.setSeekInterval(s),
                          showCheckmark: false,
                          labelStyle: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),

                  _SectionHeader(
                    title: context.l10n.videoAdvancedDefaultSection,
                    icon: Icons.settings_suggest_rounded,
                    color: AppColors.controlColor,
                  ),

                  // 默认音量
                  _buildSection(
                    context,
                    icon: Icons.volume_up_rounded,
                    iconColor: AppColors.controlColor,
                    title: context.l10n.videoAdvancedDefaultVolumeTitle,
                    subtitle: context.l10n.videoAdvancedDefaultVolumeSubtitle,
                    child: Row(
                      children: [
                        Icon(
                          settings.volume == 0
                              ? Icons.volume_off_rounded
                              : settings.volume < 0.5
                                  ? Icons.volume_down_rounded
                                  : Icons.volume_up_rounded,
                          color: isDark
                              ? AppColors.darkOnSurfaceVariant
                              : AppColors.lightOnSurfaceVariant,
                        ),
                        Expanded(
                          child: Slider(
                            value: settings.volume,
                            onChanged: notifier.setVolume,
                          ),
                        ),
                        SizedBox(
                          width: 48,
                          child: Text(
                            '${(settings.volume * 100).round()}%',
                            textAlign: TextAlign.center,
                            style: context.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),

                  _buildSection(
                    context,
                    icon: Icons.speed_rounded,
                    iconColor: AppColors.info,
                    title: context.l10n.videoAdvancedDefaultSpeedTitle,
                    subtitle: context.l10n.videoAdvancedDefaultSpeedSubtitle,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: availableSpeeds.map((s) {
                        final isSelected = s == settings.speed;
                        return ChoiceChip(
                          label: Text('$s${context.l10n.videoAdvancedDefaultSpeedSuffix}'),
                          selected: isSelected,
                          onSelected: (_) => notifier.setSpeed(s),
                          showCheckmark: false,
                          labelStyle: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),

                  _SectionHeader(
                    title: context.l10n.videoAdvancedDataSection,
                    icon: Icons.storage_rounded,
                    color: AppColors.error,
                  ),

                  // 清除播放记录
                  ListTile(
                    leading: _buildIcon(Icons.delete_sweep_rounded, AppColors.error),
                    title: Text(context.l10n.videoAdvancedClearPositionTitle),
                    subtitle: Text(context.l10n.videoAdvancedClearPositionSubtitle),
                    onTap: () => _showClearConfirmation(context, ref),
                    contentPadding: EdgeInsets.zero,
                  ),

                  SizedBox(height: MediaQuery.of(context).padding.bottom + 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIcon(IconData icon, Color color) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          color: color,
          size: 20,
        ),
      );

  Widget _buildSection(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required Widget child,
    String? subtitle,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildIcon(icon, iconColor),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: context.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: context.textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).brightness == Brightness.dark
                                ? AppColors.darkOnSurfaceVariant
                                : AppColors.lightOnSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(left: 56),
              child: child,
            ),
          ],
        ),
      );

  void _showClearConfirmation(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.videoAdvancedClearDialogTitle),
        content: Text(context.l10n.videoAdvancedClearDialogContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.videoAdvancedClearCancel),
          ),
          FilledButton(
            onPressed: () {
              ref.read(playbackSettingsProvider.notifier).clearAllPositions();
              Navigator.pop(context);
              Navigator.pop(context);
              context.showSuccessToast(context.l10n.videoAdvancedClearSuccess);
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            child: Text(context.l10n.videoAdvancedClearConfirm),
          ),
        ],
      ),
    );
  }
}

/// 分组标题
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.icon,
    required this.color,
  });

  final String title;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: context.textTheme.titleSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Divider(
              color: isDark
                  ? AppColors.darkOutline.withValues(alpha: 0.2)
                  : AppColors.lightOutline.withValues(alpha: 0.2),
            ),
          ),
        ],
      ),
    );
  }
}
