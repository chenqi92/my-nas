import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/features/book/data/services/tts/tts_service.dart';
import 'package:my_nas/features/book/presentation/providers/tts_provider.dart';
import 'package:my_nas/features/book/presentation/widgets/tts_settings_sheet.dart';
import 'package:my_nas/features/book/presentation/widgets/tts_voice_selector.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';

/// TTS 控制栏
///
/// 显示朗读控制按钮：上一段、播放/暂停、下一段、音色、设置
class TTSControlBar extends ConsumerWidget {
  const TTSControlBar({
    super.key,
    this.onClose,
    this.backgroundColor,
  });

  final VoidCallback? onClose;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ttsState = ref.watch(ttsProvider);
    final ttsNotifier = ref.read(ttsProvider.notifier);
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: backgroundColor ?? theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 进度指示器 (可选)
            if (ttsState.isPlaying) ...[
              _buildProgressIndicator(context, ttsState),
              const SizedBox(height: 12),
            ],

            // 控制按钮行
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // 关闭按钮
                _buildControlButton(
                  context,
                  icon: Icons.close_rounded,
                  label: '关闭',
                  onTap: () {
                    debugPrint('TTS Control: 关闭按钮点击');
                    ttsNotifier.stop();
                    onClose?.call();
                  },
                ),

                // 上一段
                _buildControlButton(
                  context,
                  icon: Icons.skip_previous_rounded,
                  label: '上一段',
                  onTap: () {
                    debugPrint('TTS Control: 上一段按钮点击');
                    ttsNotifier.previousParagraph();
                  },
                ),

                // 播放/暂停 (大按钮)
                _buildPlayPauseButton(context, ttsState, ttsNotifier),

                // 下一段
                _buildControlButton(
                  context,
                  icon: Icons.skip_next_rounded,
                  label: '下一段',
                  onTap: () {
                    debugPrint('TTS Control: 下一段按钮点击');
                    ttsNotifier.nextParagraph();
                  },
                ),

                // 音色选择
                _buildControlButton(
                  context,
                  icon: Icons.record_voice_over,
                  label: '音色',
                  onTap: () => _showVoiceSelector(context),
                ),

                // 设置
                _buildControlButton(
                  context,
                  icon: Icons.settings_rounded,
                  label: '设置',
                  onTap: () => _showSettings(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressIndicator(BuildContext context, TTSState state) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(
          '第 ${state.currentParagraphIndex + 1} 段',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: LinearProgressIndicator(
            value: null, // Indeterminate
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
          ),
        ),
        const SizedBox(width: 8),
        if (state.currentWord.isNotEmpty)
          Text(
            state.currentWord,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
      ],
    );
  }

  Widget _buildControlButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 24,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayPauseButton(
    BuildContext context,
    TTSState state,
    TTSNotifier notifier,
  ) {
    final theme = Theme.of(context);
    final isPlaying = state.playState == TTSPlayState.playing;

    return Material(
      color: theme.colorScheme.primary,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: () {
          if (isPlaying) {
            notifier.pause();
          } else if (state.isPaused) {
            notifier.resume();
          }
          // If idle, the parent should start playback
        },
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Icon(
            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 32,
            color: theme.colorScheme.onPrimary,
          ),
        ),
      ),
    );
  }

  void _showVoiceSelector(BuildContext context) {
    showAdaptiveModalSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const TTSVoiceSelector(),
    );
  }

  void _showSettings(BuildContext context) {
    showAdaptiveModalSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const TTSSettingsSheet(),
    );
  }
}

/// 迷你 TTS 控制栏 (用于阅读器顶部或底部栏)
class MiniTTSControlBar extends ConsumerWidget {
  const MiniTTSControlBar({
    super.key,
    this.onExpand,
  });

  final VoidCallback? onExpand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ttsState = ref.watch(ttsProvider);
    final ttsNotifier = ref.read(ttsProvider.notifier);
    final theme = Theme.of(context);

    if (ttsState.isIdle) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 播放/暂停
          InkWell(
            onTap: () {
              if (ttsState.isPlaying) {
                ttsNotifier.pause();
              } else {
                ttsNotifier.resume();
              }
            },
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                ttsState.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                size: 20,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),

          const SizedBox(width: 8),

          // 当前朗读指示
          Text(
            '朗读中...',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),

          const SizedBox(width: 8),

          // 展开按钮
          if (onExpand != null)
            InkWell(
              onTap: onExpand,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.expand_less_rounded,
                  size: 20,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),

          // 停止按钮
          InkWell(
            onTap: () => ttsNotifier.stop(),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.stop_rounded,
                size: 20,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
