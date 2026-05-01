// ignore_for_file: unused_element

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/features/video/data/services/opensubtitles_service.dart';
import 'package:my_nas/features/video/presentation/providers/playback_settings_provider.dart';
import 'package:my_nas/features/video/presentation/providers/video_player_provider.dart'
    hide availableSpeeds;
import 'package:my_nas/features/video/presentation/widgets/aspect_ratio_selector.dart';
import 'package:my_nas/features/video/presentation/widgets/audio_track_selector.dart';
import 'package:my_nas/features/video/presentation/widgets/subtitle_download_dialog.dart';
import 'package:my_nas/features/video/presentation/widgets/subtitle_selector.dart';
import 'package:my_nas/features/video/presentation/widgets/subtitle_style_sheet.dart';

/// Infuse 风格的设置面板
///
/// 采用右侧浮动面板设计，支持:
/// - 字幕/音轨快速切换
/// - 播放速度调节
/// - 快进快退秒数设置
/// - 画面比例切换
class InfuseSettingsPanel extends ConsumerStatefulWidget {
  const InfuseSettingsPanel({
    required this.onClose,
    this.videoPath,
    this.videoName,
    this.tmdbId,
    this.isMovie = true,
    this.seasonNumber,
    this.episodeNumber,
    super.key,
  });

  final VoidCallback onClose;
  final String? videoPath;
  final String? videoName;
  final int? tmdbId;
  final bool isMovie;
  final int? seasonNumber;
  final int? episodeNumber;

  @override
  ConsumerState<InfuseSettingsPanel> createState() => _InfuseSettingsPanelState();
}

class _InfuseSettingsPanelState extends ConsumerState<InfuseSettingsPanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    await _controller.reverse();
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final playerNotifier = ref.read(videoPlayerControllerProvider.notifier);
    final playerState = ref.watch(videoPlayerControllerProvider);
    final settings = ref.watch(playbackSettingsProvider);
    final settingsNotifier = ref.read(playbackSettingsProvider.notifier);
    final subtitles = ref.watch(availableSubtitlesProvider);
    final currentSubtitle = ref.watch(currentSubtitleProvider);
    final currentEmbeddedId = ref.watch(currentEmbeddedSubtitleIdProvider);
    final hasSubtitleConfig = ref.watch(hasOpenSubtitlesConfigProvider);

    final audioTracks = playerNotifier.audioTracks;
    final embeddedSubtitles = playerNotifier.embeddedSubtitles
        .where((s) => s.id != 'no' && s.id != 'auto')
        .toList();
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

    return GestureDetector(
      onTap: _close,
      behavior: HitTestBehavior.opaque,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: ColoredBox(
          color: Colors.black38,
          child: Row(
            children: [
              // 左侧点击区域关闭
              const Expanded(child: SizedBox.expand()),

              // 右侧设置面板
              SlideTransition(
                position: _slideAnimation,
                child: GestureDetector(
                  onTap: () {}, // 阻止点击穿透
                  child: Container(
                    width: 320,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.85),
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(16),
                      ),
                    ),
                    child: SafeArea(
                      left: false,
                      child: Column(
                        children: [
                          // 标题栏
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.tune_rounded,
                                  color: Colors.white70,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  '播放设置',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  onPressed: _close,
                                  icon: const Icon(Icons.close, color: Colors.white70),
                                ),
                              ],
                            ),
                          ),

                          const Divider(color: Colors.white24, height: 1),

                          // 设置内容
                          Expanded(
                            child: ListView(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              children: [
                                // === 字幕 ===
                                _SettingItem(
                                  icon: Icons.closed_caption_rounded,
                                  title: '字幕',
                                  value: currentSubtitleName,
                                  onTap: () {
                                    _close();
                                    showSubtitleSelector(
                                      context,
                                      videoPath: widget.videoPath,
                                      title: widget.videoName,
                                      tmdbId: widget.tmdbId,
                                      isMovie: widget.isMovie,
                                      seasonNumber: widget.seasonNumber,
                                      episodeNumber: widget.episodeNumber,
                                    );
                                  },
                                ),

                                // 在线搜索字幕
                                if (hasSubtitleConfig && widget.videoPath != null)
                                  _SettingItem(
                                    icon: Icons.search_rounded,
                                    title: '搜索字幕',
                                    onTap: () {
                                      _close();
                                      _showSubtitleDownloadDialog();
                                    },
                                  ),

                                // 字幕样式
                                if (hasSubtitles || currentSubtitle != null)
                                  _SettingItem(
                                    icon: Icons.text_format_rounded,
                                    title: '字幕样式',
                                    onTap: () {
                                      _close();
                                      showSubtitleStyleSheet(context);
                                    },
                                  ),

                                const _Divider(),

                                // === 音轨 ===（画面比例已在主界面控制）
                                if (audioTracks.isNotEmpty)
                                  _SettingItem(
                                    icon: Icons.audiotrack_rounded,
                                    title: '音轨',
                                    value: '${audioTracks.length} 个可用',
                                    onTap: () {
                                      _close();
                                      showAudioTrackSelector(context);
                                    },
                                  ),

                                const _Divider(),

                                // === 播放速度 ===
                                _SpeedSection(
                                  currentSpeed: playerState.speed,
                                  onSpeedChange: playerNotifier.setSpeed,
                                ),

                                const _Divider(),

                                // === 快进快退秒数 ===
                                _SeekIntervalSection(
                                  currentInterval: settings.seekInterval,
                                  onIntervalChange: settingsNotifier.setSeekInterval,
                                ),

                                const SizedBox(height: 16),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSubtitleDownloadDialog() {
    if (widget.videoPath == null) return;

    final lastSlash = widget.videoPath!.lastIndexOf('/');
    final savePath = lastSlash > 0 ? widget.videoPath!.substring(0, lastSlash) : widget.videoPath!;

    SubtitleDownloadDialog.show(
      context: context,
      tmdbId: widget.tmdbId,
      title: widget.videoName,
      seasonNumber: widget.seasonNumber,
      episodeNumber: widget.episodeNumber,
      isMovie: widget.isMovie,
      savePath: savePath,
    );
  }

  void _showAspectRatioPicker(BuildContext context, WidgetRef ref) {
    final currentMode = ref.read(aspectRatioModeProvider);

    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black87,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.aspect_ratio_rounded, color: Colors.white70, size: 20),
                  SizedBox(width: 8),
                  Text(
                    '画面比例',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: AspectRatioMode.values.map((mode) {
                  final isSelected = mode == currentMode;
                  return _AspectRatioChip(
                    mode: mode,
                    isSelected: isSelected,
                    onTap: () {
                      ref.read(aspectRatioModeProvider.notifier).state = mode;
                      Navigator.pop(context);
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 设置项
class _SettingItem extends StatelessWidget {
  const _SettingItem({
    required this.icon,
    required this.title,
    this.value,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Icon(icon, color: Colors.white60, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (value != null)
                  Text(
                    value!,
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 13,
                    ),
                  ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, color: Colors.white38, size: 18),
              ],
            ),
          ),
        ),
      );
}

/// 分隔线
class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        child: Divider(color: Colors.white12, height: 1),
      );
}

/// 播放速度选择
class _SpeedSection extends StatelessWidget {
  const _SpeedSection({
    required this.currentSpeed,
    required this.onSpeedChange,
  });

  final double currentSpeed;
  final ValueChanged<double> onSpeedChange;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.speed_rounded, color: Colors.white60, size: 20),
                const SizedBox(width: 12),
                const Text(
                  '播放速度',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    decoration: TextDecoration.none,
                  ),
                ),
                const Spacer(),
                Text(
                  '${currentSpeed}x',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: availableSpeeds.map((speed) {
                  final isSelected = speed == currentSpeed;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _ChipButton(
                      label: '${speed}x',
                      isSelected: isSelected,
                      onTap: () => onSpeedChange(speed),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      );
}

/// 快进快退秒数选择
class _SeekIntervalSection extends StatelessWidget {
  const _SeekIntervalSection({
    required this.currentInterval,
    required this.onIntervalChange,
  });

  final int currentInterval;
  final ValueChanged<int> onIntervalChange;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.fast_forward_rounded, color: Colors.white60, size: 20),
                const SizedBox(width: 12),
                const Text(
                  '快进快退',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    decoration: TextDecoration.none,
                  ),
                ),
                const Spacer(),
                Text(
                  '$currentInterval 秒',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: availableSeekIntervals.map((interval) {
                  final isSelected = interval == currentInterval;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _ChipButton(
                      label: '$interval秒',
                      isSelected: isSelected,
                      onTap: () => onIntervalChange(interval),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      );
}

/// 统一的选择按钮样式
class _ChipButton extends StatelessWidget {
  const _ChipButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: isSelected ? AppColors.primary : Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ),
      );
}

/// 画面比例选择按钮
class _AspectRatioChip extends StatelessWidget {
  const _AspectRatioChip({
    required this.mode,
    required this.isSelected,
    required this.onTap,
  });

  final AspectRatioMode mode;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: isSelected ? AppColors.primary : Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(
              mode.label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ),
      );
}

/// 显示 Infuse 风格设置面板
void showInfuseSettingsPanel(
  BuildContext context, {
  String? videoPath,
  String? videoName,
  int? tmdbId,
  bool isMovie = true,
  int? seasonNumber,
  int? episodeNumber,
}) {
  late OverlayEntry overlayEntry;

  overlayEntry = OverlayEntry(
    builder: (context) => InfuseSettingsPanel(
      onClose: () => overlayEntry.remove(),
      videoPath: videoPath,
      videoName: videoName,
      tmdbId: tmdbId,
      isMovie: isMovie,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
    ),
  );

  Overlay.of(context).insert(overlayEntry);
}
