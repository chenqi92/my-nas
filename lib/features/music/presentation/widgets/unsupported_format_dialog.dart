import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/music/data/services/music_audio_handler_interface.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';
import 'package:my_nas/features/music/presentation/providers/music_settings_provider.dart';
import 'package:my_nas/l10n/app_localizations.dart';

/// iOS 不支持音频格式时的引擎切换提示对话框
///
/// 当使用 just_audio 引擎（原生 AVFoundation）播放 FLAC 等不支持的格式时显示
class UnsupportedFormatDialog extends ConsumerWidget {
  const UnsupportedFormatDialog({
    required this.formatName,
    super.key,
  });

  /// 不支持的格式名称（如 "FLAC"、"APE"、"DSD" 等）
  final String formatName;

  /// 显示对话框的静态方法
  ///
  /// 如果用户选择切换引擎，返回 true
  /// 如果用户选择取消或忽略，返回 false
  static Future<bool?> show(BuildContext context, String formatName) {
    if (!Platform.isIOS) return Future.value(null);

    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) => UnsupportedFormatDialog(formatName: formatName),
    );
  }

  /// 仅用于一次性提示（后台检测到格式不支持时）
  /// 在用户首次遇到该格式时显示，避免重复提醒
  static final Set<String> _shownFormats = {};

  /// 显示一次性提示（同一格式只显示一次）
  /// 返回值表示是否成功显示了对话框
  static Future<bool> showOnce(BuildContext context, String formatName) async {
    if (!Platform.isIOS) return false;
    if (_shownFormats.contains(formatName)) return false;

    _shownFormats.add(formatName);
    final result = await show(context, formatName);
    return result ?? false;
  }

  /// 重置已显示的格式记录（用于测试或用户切换引擎后）
  static void resetShownFormats() {
    _shownFormats.clear();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(musicSettingsProvider);
    final currentEngine = settings.playerEngine;

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: theme.colorScheme.error,
            size: 24,
          ),
          const SizedBox(width: 12),
          const Text('格式不支持'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: TextSpan(
              style: theme.textTheme.bodyMedium,
              children: [
                const TextSpan(text: 'iOS 原生解码器不支持 '),
                TextSpan(
                  text: formatName,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const TextSpan(text: ' 格式。'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '建议切换到 FFmpeg 解码器（MediaKit 引擎）以支持更多音频格式。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (currentEngine == MusicPlayerEngine.justAudio) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '切换引擎需要重启应用生效',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('暂不切换'),
        ),
        FilledButton(
          onPressed: () async {
            // 切换到 MediaKit 引擎
            await ref.read(musicSettingsProvider.notifier).setPlayerEngine(
              MusicPlayerEngine.mediaKit,
            );
            logger.i('UnsupportedFormatDialog: 用户选择切换到 MediaKit 引擎');

            if (context.mounted) {
              Navigator.of(context).pop(true);

              // 显示重启提示
              final l = AppLocalizations.of(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l.musicEngineDecoderSwitched),
                  action: SnackBarAction(
                    label: l.musicEngineConfirmed,
                    onPressed: () {},
                  ),
                  duration: const Duration(seconds: 5),
                ),
              );
            }
          },
          child: const Text('切换引擎'),
        ),
      ],
    );
  }
}

/// 扩展 MusicPlayerNotifier 以提供格式检测的便捷方法
extension UnsupportedFormatDetection on MusicPlayerNotifier {
  /// 设置格式不支持时的 UI 回调
  ///
  /// 调用方式：
  /// ```dart
  /// ref.read(musicPlayerControllerProvider.notifier)
  ///   .setupUnsupportedFormatCallback(context);
  /// ```
  void setupUnsupportedFormatCallback(BuildContext context) {
    onUnsupportedFormatDetected = (formatName) {
      // 使用 addPostFrameCallback 确保在当前帧结束后显示对话框
      // 避免在 build 过程中显示对话框
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          UnsupportedFormatDialog.showOnce(context, formatName);
        }
      });
    };
  }

  /// 移除格式不支持的回调
  void removeUnsupportedFormatCallback() {
    onUnsupportedFormatDetected = null;
  }
}
