import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/video/presentation/providers/playback_settings_provider.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';

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
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.darkOutline.withValues(alpha: 0.3)
                    : AppColors.lightOutline.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

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
                    '播放设置',
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
                    title: const Text('自动播放下一个'),
                    subtitle: const Text('播放完成后自动播放列表中的下一个视频'),
                    value: settings.autoPlayNext,
                    onChanged: (value) {
                      notifier.setAutoPlayNext(enabled: value);
                    },
                    contentPadding: EdgeInsets.zero,
                  ),

                  const Divider(),

                  // 记住播放位置
                  SwitchListTile(
                    title: const Text('记住播放位置'),
                    subtitle: const Text('下次打开时从上次位置继续播放'),
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
                    title: '快进/快退秒数',
                    subtitle: '双击或点击按钮时跳过的秒数',
                    child: SegmentedButton<int>(
                      segments: availableSeekIntervals
                          .map(
                            (s) => ButtonSegment(
                              value: s,
                              label: Text('$s秒'),
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
                    title: '默认音量',
                    subtitle: '新视频的初始音量',
                    child: Row(
                      children: [
                        Icon(
                          settings.volume == 0
                              ? Icons.volume_off
                              : settings.volume < 0.5
                                  ? Icons.volume_down
                                  : Icons.volume_up,
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

                  const Divider(),

                  // 默认播放速度
                  _buildSection(
                    context,
                    title: '默认播放速度',
                    subtitle: '新视频的初始播放速度',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: availableSpeeds.map((s) {
                        final isSelected = s == settings.speed;
                        return ChoiceChip(
                          label: Text('${s}x'),
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
                    title: const Text('清除播放位置记录'),
                    subtitle: const Text('删除所有视频的播放进度'),
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
        title: const Text('清除播放记录'),
        content: const Text('确定要清除所有视频的播放位置记录吗？此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(playbackSettingsProvider.notifier).clearAllPositions();
              Navigator.pop(context);
              context.showSuccessToast('播放位置记录已清除');
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            child: const Text('清除'),
          ),
        ],
      ),
    );
  }
}
