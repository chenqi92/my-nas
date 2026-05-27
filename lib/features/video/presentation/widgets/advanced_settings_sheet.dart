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
                    '高级功能',
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
                    title: '显示设置',
                    icon: Icons.display_settings_rounded,
                    color: AppColors.downloadColor,
                  ),

                  // 字幕样式
                  ListTile(
                    leading: _buildIcon(Icons.text_format_rounded, AppColors.downloadColor),
                    title: const Text('字幕样式'),
                    subtitle: const Text('调整字幕字体、颜色、位置等'),
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
                    title: const Text('画面比例'),
                    subtitle: const Text('调整视频显示比例'),
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
                    title: '播放设置',
                    icon: Icons.play_circle_outline_rounded,
                    color: AppColors.success,
                  ),

                  // 自动播放下一个
                  SwitchListTile(
                    secondary: _buildIcon(Icons.skip_next_rounded, AppColors.success),
                    title: const Text('自动播放下一个'),
                    subtitle: const Text('播放完成后自动播放列表中的下一个视频'),
                    value: settings.autoPlayNext,
                    onChanged: (value) {
                      notifier.setAutoPlayNext(enabled: value);
                    },
                    contentPadding: EdgeInsets.zero,
                  ),

                  SwitchListTile(
                    secondary: _buildIcon(Icons.history_rounded, AppColors.warning),
                    title: const Text('记住播放位置'),
                    subtitle: const Text('下次打开时从上次位置继续播放'),
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
                    title: '控制设置',
                    icon: Icons.touch_app_rounded,
                    color: AppColors.musicColor,
                  ),

                  // 快进快退秒数
                  _buildSection(
                    context,
                    icon: Icons.fast_forward_rounded,
                    iconColor: AppColors.musicColor,
                    title: '快进/快退秒数',
                    subtitle: '双击或点击按钮时跳过的秒数',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: availableSeekIntervals.map((s) {
                        final isSelected = s == settings.seekInterval;
                        return ChoiceChip(
                          label: Text('$s秒'),
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
                    title: '默认设置',
                    icon: Icons.settings_suggest_rounded,
                    color: AppColors.controlColor,
                  ),

                  // 默认音量
                  _buildSection(
                    context,
                    icon: Icons.volume_up_rounded,
                    iconColor: AppColors.controlColor,
                    title: '默认音量',
                    subtitle: '新视频的初始音量',
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
                    title: '数据管理',
                    icon: Icons.storage_rounded,
                    color: AppColors.error,
                  ),

                  // 清除播放记录
                  ListTile(
                    leading: _buildIcon(Icons.delete_sweep_rounded, AppColors.error),
                    title: const Text('清除播放位置记录'),
                    subtitle: const Text('删除所有视频的播放进度'),
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
