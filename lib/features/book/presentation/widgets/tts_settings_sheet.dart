import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/book/data/services/tts/tts_settings.dart';
import 'package:my_nas/features/book/presentation/providers/tts_provider.dart';
import 'package:my_nas/shared/widgets/sheet_drag_handle.dart';

/// TTS 设置面板
class TTSSettingsSheet extends ConsumerWidget {
  const TTSSettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ttsState = ref.watch(ttsProvider);
    final ttsNotifier = ref.read(ttsProvider.notifier);
    final theme = Theme.of(context);
    final settings = ttsState.settings;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 拖动指示器
              const SheetDragHandle(topPadding: 0, bottomPadding: 0),

              const SizedBox(height: 16),

              // 标题
              Row(
                children: [
                  Icon(
                    Icons.settings_rounded,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '朗读设置',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // 引擎选择
              Text(
                '语音引擎',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _EngineCard(
                      title: '系统 TTS',
                      subtitle: '离线可用',
                      icon: Icons.smartphone,
                      isSelected: settings.engine == TTSEngine.system,
                      onTap: () => ttsNotifier.setEngine(TTSEngine.system),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _EngineCard(
                      title: 'Edge TTS',
                      subtitle: '在线高品质',
                      icon: Icons.cloud,
                      isSelected: settings.engine == TTSEngine.edge,
                      isRecommended: true,
                      onTap: () => ttsNotifier.setEngine(TTSEngine.edge),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // 语速
              _buildSliderSetting(
                context,
                label: '语速',
                value: settings.speechRate,
                min: 0.5,
                max: 2.0,
                divisions: 15,
                valueLabel: '${settings.speechRate.toStringAsFixed(1)}x',
                onChanged: ttsNotifier.setSpeechRate,
              ),

              const SizedBox(height: 16),

              // 音调
              _buildSliderSetting(
                context,
                label: '音调',
                value: settings.pitch,
                min: 0.5,
                max: 2.0,
                divisions: 15,
                valueLabel: settings.pitch.toStringAsFixed(1),
                onChanged: ttsNotifier.setPitch,
              ),

              const SizedBox(height: 16),

              // 音量
              _buildSliderSetting(
                context,
                label: '音量',
                value: settings.volume,
                min: 0.0,
                max: 1.0,
                divisions: 10,
                valueLabel: '${(settings.volume * 100).toInt()}%',
                onChanged: ttsNotifier.setVolume,
              ),

              const SizedBox(height: 24),

              // 开关选项
              _buildSwitchSetting(
                context,
                icon: Icons.format_line_spacing,
                label: '自动滚动跟随',
                subtitle: '朗读时自动滚动到当前段落',
                value: settings.autoScrollFollow,
                onChanged: (value) {
                  ttsNotifier.updateSettings(
                    settings.copyWith(autoScrollFollow: value),
                  );
                },
              ),

              _buildSwitchSetting(
                context,
                icon: Icons.highlight,
                label: '朗读高亮',
                subtitle: '高亮显示当前朗读位置',
                value: settings.highlightEnabled,
                onChanged: (value) {
                  ttsNotifier.updateSettings(
                    settings.copyWith(highlightEnabled: value),
                  );
                },
              ),

              _buildSwitchSetting(
                context,
                icon: Icons.skip_next_rounded,
                label: '自动播放下一章',
                subtitle: '当前章节结束后自动播放下一章',
                value: settings.autoPlayNextChapter,
                onChanged: (value) {
                  ttsNotifier.updateSettings(
                    settings.copyWith(autoPlayNextChapter: value),
                  );
                },
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSliderSetting(
    BuildContext context, {
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String valueLabel,
    required ValueChanged<double> onChanged,
  }) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                valueLabel,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildSwitchSetting(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            icon,
            size: 24,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// 引擎选择卡片
class _EngineCard extends StatelessWidget {
  const _EngineCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    this.isRecommended = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final bool isRecommended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Stack(
              children: [
                Icon(
                  icon,
                  size: 32,
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                if (isRecommended)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.tertiary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '推荐',
                        style: TextStyle(
                          fontSize: 8,
                          color: theme.colorScheme.onTertiary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: isSelected ? FontWeight.w600 : null,
                color: isSelected
                    ? theme.colorScheme.onPrimaryContainer
                    : null,
              ),
            ),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: isSelected
                    ? theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.7)
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
