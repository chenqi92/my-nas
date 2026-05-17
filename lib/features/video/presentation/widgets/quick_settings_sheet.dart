import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/video/data/services/opensubtitles_service.dart';
import 'package:my_nas/features/video/presentation/providers/playback_settings_provider.dart'
    show availableSpeeds;
import 'package:my_nas/features/video/presentation/providers/video_player_provider.dart'
    hide availableSpeeds;
import 'package:my_nas/features/video/presentation/widgets/advanced_settings_sheet.dart';
import 'package:my_nas/features/video/presentation/widgets/audio_track_selector.dart';
import 'package:my_nas/features/video/presentation/widgets/subtitle_download_dialog.dart';
import 'package:my_nas/features/video/presentation/widgets/subtitle_selector.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';

/// 显示快速设置面板
void showQuickSettingsSheet(
  BuildContext context, {
  String? videoPath,
  String? videoName,
  int? tmdbId,
  bool isMovie = true,
  int? seasonNumber,
  int? episodeNumber,
}) {
  showAdaptiveModalSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => QuickSettingsSheet(
      videoPath: videoPath,
      videoName: videoName,
      tmdbId: tmdbId,
      isMovie: isMovie,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
    ),
  );
}

/// 快速设置面板
///
/// 提供常用设置的快速访问：
/// - 高级功能（第一个选项）
/// - 字幕切换
/// - 音轨切换
/// - 播放速度
/// - 声音增强
/// - 在线搜索字幕
class QuickSettingsSheet extends ConsumerWidget {
  const QuickSettingsSheet({
    super.key,
    this.videoPath,
    this.videoName,
    this.tmdbId,
    this.isMovie = true,
    this.seasonNumber,
    this.episodeNumber,
  });

  final String? videoPath;
  final String? videoName;
  final int? tmdbId;
  final bool isMovie;
  final int? seasonNumber;
  final int? episodeNumber;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final playerNotifier = ref.read(videoPlayerControllerProvider.notifier);
    final playerState = ref.watch(videoPlayerControllerProvider);
    final subtitles = ref.watch(availableSubtitlesProvider);
    final currentSubtitle = ref.watch(currentSubtitleProvider);
    final currentEmbeddedId = ref.watch(currentEmbeddedSubtitleIdProvider);
    final hasSubtitleConfig = ref.watch(hasOpenSubtitlesConfigProvider);

    // 获取当前音轨信息
    final audioTracks = playerNotifier.audioTracks;
    final currentAudioTrack = playerNotifier.currentAudioTrack;
    final embeddedSubtitles = playerNotifier.embeddedSubtitles
        .where((s) => s.id != 'no' && s.id != 'auto')
        .toList();

    // 判断是否有字幕
    final hasSubtitles =
        subtitles.isNotEmpty || embeddedSubtitles.isNotEmpty || currentSubtitle != null;

    // 当前字幕名称
    var currentSubtitleName = '关闭';
    if (currentSubtitle != null) {
      currentSubtitleName = currentSubtitle.language ?? currentSubtitle.name;
    } else if (currentEmbeddedId != null) {
      final track = embeddedSubtitles.where((s) => s.id == currentEmbeddedId).firstOrNull;
      if (track != null) {
        currentSubtitleName = track.title ?? track.language ?? '轨道 ${track.id}';
      }
    }

    // 当前音轨名称
    var currentAudioName = '默认';
    if (currentAudioTrack != null) {
      currentAudioName = currentAudioTrack.title ?? '音轨 ${currentAudioTrack.id}';
    }

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
                  '设置',
                  style: context.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // 设置选项列表
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              children: [
                // 1. 高级功能（第一个选项）
                _SettingsTile(
                  icon: Icons.tune_rounded,
                  iconColor: AppColors.musicColor,
                  title: '高级功能',
                  subtitle: '更多播放设置选项',
                  onTap: () {
                    Navigator.pop(context);
                    showAdvancedSettingsSheet(context);
                  },
                ),

                const Divider(indent: 56, endIndent: 16),

                // 2. 字幕
                _SettingsTile(
                  icon: hasSubtitles ? Icons.closed_caption : Icons.closed_caption_off,
                  iconColor: AppColors.downloadColor,
                  title: '字幕',
                  subtitle: currentSubtitleName,
                  trailing: hasSubtitles
                      ? null
                      : const Text(
                          '无可用字幕',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                  onTap: () {
                    Navigator.pop(context);
                    showSubtitleSelector(
                      context,
                      videoPath: videoPath,
                      title: videoName,
                      tmdbId: tmdbId,
                      isMovie: isMovie,
                      seasonNumber: seasonNumber,
                      episodeNumber: episodeNumber,
                    );
                  },
                ),

                // 3. 在线搜索字幕
                if (hasSubtitleConfig && videoPath != null)
                  _SettingsTile(
                    icon: Icons.search_rounded,
                    iconColor: AppColors.controlColor,
                    title: '在线搜索字幕',
                    subtitle: '从 OpenSubtitles 搜索',
                    onTap: () {
                      Navigator.pop(context);
                      _showSubtitleDownloadDialog(context, ref);
                    },
                  ),

                const Divider(indent: 56, endIndent: 16),

                _SettingsTile(
                  icon: Icons.audiotrack_rounded,
                  iconColor: AppColors.warning,
                  title: '音轨',
                  subtitle: currentAudioName,
                  trailing: audioTracks.length > 1
                      ? Text(
                          '${audioTracks.length} 个可用',
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        )
                      : null,
                  onTap: audioTracks.isNotEmpty
                      ? () {
                          Navigator.pop(context);
                          showAudioTrackSelector(context);
                        }
                      : null,
                ),

                const Divider(indent: 56, endIndent: 16),

                // 5. 播放速度
                _SpeedSelector(
                  currentSpeed: playerState.speed,
                  onSpeedChange: playerNotifier.setSpeed,
                ),

                const Divider(indent: 56, endIndent: 16),

                // 6. 声音增强
                _VolumeBoostSelector(
                  currentVolume: playerState.volume,
                  onVolumeChange: playerNotifier.setVolume,
                ),

                SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showSubtitleDownloadDialog(BuildContext context, WidgetRef ref) {
    if (videoPath == null) return;

    // 获取视频目录
    final lastSlash = videoPath!.lastIndexOf('/');
    final savePath = lastSlash > 0 ? videoPath!.substring(0, lastSlash) : videoPath!;

    SubtitleDownloadDialog.show(
      context: context,
      tmdbId: tmdbId,
      title: videoName,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      isMovie: isMovie,
      savePath: savePath,
    );
  }
}

/// 设置项组件
class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          color: iconColor,
          size: 20,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: onTap == null
              ? (isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant)
              : null,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: context.textTheme.bodySmall?.copyWith(
          color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
        ),
      ),
      trailing: trailing ??
          Icon(
            Icons.chevron_right,
            color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
          ),
      onTap: onTap,
    );
  }
}

/// 播放速度选择器
class _SpeedSelector extends StatelessWidget {
  const _SpeedSelector({
    required this.currentSpeed,
    required this.onSpeedChange,
  });

  final double currentSpeed;
  final ValueChanged<double> onSpeedChange;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.speed_rounded,
                  color: AppColors.success,
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '播放速度',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  Text(
                    '当前: ${currentSpeed}x',
                    style: context.textTheme.bodySmall?.copyWith(
                      color: isDark
                          ? AppColors.darkOnSurfaceVariant
                          : AppColors.lightOnSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 56),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: availableSpeeds.map((speed) {
                final isSelected = speed == currentSpeed;
                return ChoiceChip(
                  label: Text('${speed}x'),
                  selected: isSelected,
                  onSelected: (_) => onSpeedChange(speed),
                  showCheckmark: false,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

/// 声音增强选择器
class _VolumeBoostSelector extends StatelessWidget {
  const _VolumeBoostSelector({
    required this.currentVolume,
    required this.onVolumeChange,
  });

  final double currentVolume;
  final ValueChanged<double> onVolumeChange;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 声音增强等级
    const boostLevels = [
      (value: 1.0, label: '正常'),
      (value: 1.25, label: '125%'),
      (value: 1.5, label: '150%'),
      (value: 2.0, label: '200%'),
    ];

    // 找到当前最接近的等级
    final currentLevel = boostLevels.reduce((a, b) =>
        (a.value - currentVolume).abs() < (b.value - currentVolume).abs() ? a : b);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  currentVolume > 1.0 ? Icons.volume_up_rounded : Icons.volume_up_outlined,
                  color: AppColors.error,
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '声音增强',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  Text(
                    '当前: ${currentLevel.label}',
                    style: context.textTheme.bodySmall?.copyWith(
                      color: isDark
                          ? AppColors.darkOnSurfaceVariant
                          : AppColors.lightOnSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 56),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: boostLevels.map((level) {
                final isSelected = level.value == currentLevel.value;
                return ChoiceChip(
                  label: Text(level.label),
                  selected: isSelected,
                  onSelected: (_) => onVolumeChange(level.value),
                  showCheckmark: false,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
