import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/video/presentation/providers/playback_settings_provider.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';
import 'package:my_nas/shared/widgets/sheet_drag_handle.dart';

/// 显示播放设置
void showPlaybackSettingsSheet(BuildContext context) {
  showAdaptiveModalSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => const PlaybackSettingsSheet(),
  );
}

class PlaybackSettingsSheet extends ConsumerWidget {
  const PlaybackSettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = ref.watch(playbackSettingsProvider);
    final notifier = ref.read(playbackSettingsProvider.notifier);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.8,
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
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.settings_rounded,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    context.l10n.videoPlaybackSettingsTitle,
                    style: context.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
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
                  // 自动播放下一个
                  SwitchListTile(
                    title: Text(context.l10n.videoAutoPlayNextTitle),
                    subtitle: Text(context.l10n.videoAutoPlayNextSubtitle),
                    value: settings.autoPlayNext,
                    onChanged: (value) {
                      notifier.setAutoPlayNext(enabled: value);
                    },
                    contentPadding: EdgeInsets.zero,
                  ),

                  const Divider(),

                  // 记住播放位置
                  SwitchListTile(
                    title: Text(context.l10n.videoRememberPositionTitle),
                    subtitle: Text(context.l10n.videoRememberPositionSubtitle),
                    value: settings.rememberPosition,
                    onChanged: (value) {
                      notifier.setRememberPosition(enabled: value); // 这里的名字要和你定义的一样
                    },
                    contentPadding: EdgeInsets.zero,
                  ),

                  const Divider(),

                  // 快进快退秒数
                  _buildSection(
                    context,
                    title: context.l10n.videoSeekIntervalTitle,
                    subtitle: context.l10n.videoSeekIntervalSubtitle,
                    child: SegmentedButton<int>(
                      segments: availableSeekIntervals
                          .map(
                            (s) => ButtonSegment(
                              value: s,
                              label: Text(context.l10n.videoSeekIntervalSeconds(s)),
                            ),
                          )
                          .toList(),
                      selected: {settings.seekInterval},
                      onSelectionChanged: (selected) {
                        notifier.setSeekInterval(selected.first);
                      },
                    ),
                  ),

                  const Divider(),

                  // 默认音量
                  _buildSection(
                    context,
                    title: context.l10n.videoDefaultVolumeTitle,
                    subtitle: context.l10n.videoDefaultVolumeSubtitle,
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
                            context.l10n.videoVolumePercent((settings.volume * 100).round()),
                            textAlign: TextAlign.center,
                            style: context.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Divider(),

                  // 默认播放速度
                  _buildSection(
                    context,
                    title: context.l10n.videoDefaultPlaybackSpeedTitle,
                    subtitle: context.l10n.videoDefaultPlaybackSpeedSubtitle,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: availableSpeeds.map((s) {
                        final isSelected = s == settings.speed;
                        return ChoiceChip(
                          label: Text(context.l10n.videoPlaybackSpeedRate(s.toString())),
                          selected: isSelected,
                          onSelected: (_) => notifier.setSpeed(s),
                        );
                      }).toList(),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 清除播放记录
                  ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.delete_sweep_rounded,
                        color: AppColors.error,
                        size: 22,
                      ),
                    ),
                    title: Text(context.l10n.videoClearPlaybackHistoryTitle),
                    subtitle: Text(context.l10n.videoClearPlaybackHistorySubtitle),
                    onTap: () => _showClearConfirmation(context, ref),
                    contentPadding: EdgeInsets.zero,
                  ),

                  SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required Widget child, String? subtitle,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
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
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: context.textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? AppColors.darkOnSurfaceVariant
                      : AppColors.lightOnSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            child,
          ],
        ),
      );

  void _showClearConfirmation(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.videoClearConfirmTitle),
        content: Text(context.l10n.videoClearConfirmContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.videoClearConfirmCancel),
          ),
          FilledButton(
            onPressed: () {
              ref.read(playbackSettingsProvider.notifier).clearAllPositions();
              Navigator.pop(context);
              context.showSuccessToast(context.l10n.videoClearSuccessToast);
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            child: Text(context.l10n.videoClearConfirmAction),
          ),
        ],
      ),
    );
  }
}
