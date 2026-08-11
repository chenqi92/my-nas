import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/utils/tv_capabilities.dart';
import 'package:my_nas/core/widgets/tv_focus/tv_focusable.dart';
import 'package:my_nas/features/video/domain/entities/video_item.dart';
import 'package:my_nas/features/video/presentation/providers/video_player_provider.dart';
import 'package:my_nas/features/video/presentation/widgets/aspect_ratio_selector.dart';
import 'package:my_nas/features/video/presentation/widgets/cast/cast_button.dart';
import 'package:my_nas/features/video/presentation/widgets/infuse_settings_panel.dart';
import 'package:my_nas/features/video/presentation/widgets/playlist_sheet.dart';
import 'package:my_nas/features/video/presentation/widgets/quality/quality_button.dart';
import 'package:my_nas/shared/utils/form_l10n.dart';

class VideoControls extends ConsumerWidget {
  const VideoControls({
    required this.video,
    required this.state,
    required this.onPlayPause,
    required this.onSeek,
    required this.onSeekForward,
    required this.onSeekBackward,
    required this.onVolumeChange,
    required this.onSpeedChange,
    required this.onToggleFullscreen,
    required this.onBack,
    this.seekInterval = 10,
    this.hasSubtitles = false,
    this.hasPlaylist = false,
    this.hasPrevious = false,
    this.hasNext = false,
    this.onPlayPrevious,
    this.onPlayNext,
    this.onShowBookmarks,
    this.onTogglePip,
    this.isPipSupported = false,
    this.tmdbId,
    this.isMovie = true,
    this.seasonNumber,
    this.episodeNumber,
    super.key,
  });

  final VideoItem video;
  final VideoPlayerState state;
  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onSeekForward;
  final VoidCallback onSeekBackward;
  final ValueChanged<double> onVolumeChange;
  final ValueChanged<double> onSpeedChange;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onBack;
  final int seekInterval;
  final bool hasSubtitles;
  final bool hasPlaylist;
  final bool hasPrevious;
  final bool hasNext;
  final VoidCallback? onPlayPrevious;
  final VoidCallback? onPlayNext;
  final VoidCallback? onShowBookmarks;
  final VoidCallback? onTogglePip;
  final bool isPipSupported;
  final int? tmdbId;
  final bool isMovie;
  final int? seasonNumber;
  final int? episodeNumber;

  /// 根据秒数获取快退图标
  /// 对于自定义秒数，使用 replay_10 作为基础图标（会用数字覆盖）
  IconData _getReplayIcon() => switch (seekInterval) {
        5 => Icons.replay_5,
        10 => Icons.replay_10,
        30 => Icons.replay_30,
        _ => Icons.replay_10, // 使用 replay_10 作为基础图标
      };

  /// 根据秒数获取快进图标
  /// 对于自定义秒数，使用 forward_10 作为基础图标（会用数字覆盖）
  IconData _getForwardIcon() => switch (seekInterval) {
        5 => Icons.forward_5,
        10 => Icons.forward_10,
        30 => Icons.forward_30,
        _ => Icons.forward_10, // 使用 forward_10 作为基础图标
      };

  /// 是否需要显示秒数标签（当没有对应的内置图标时）
  bool get _needsSeekLabel => seekInterval != 5 && seekInterval != 10 && seekInterval != 30;

  @override
  Widget build(BuildContext context, WidgetRef ref) => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black54,
              Colors.transparent,
              Colors.transparent,
              Colors.black54,
            ],
            stops: [0.0, 0.2, 0.8, 1.0],
          ),
        ),
        child: SafeArea(
          child: _withTvFocusTheme(
            context,
            Column(
              children: [
                // 顶部栏
                _buildTopBar(context, ref),

                // 中间区域
                const Spacer(),
                _buildCenterControls(context),
                const Spacer(),

                // 底部控制栏
                _buildBottomBar(context),
              ],
            ),
          ),
        ),
      );

  /// TV：给顶部/底部栏的原生按钮补一个「隔着几米也看得见」的焦点样式。
  ///
  /// 这些按钮（[IconButton] / [PopupMenuButton] / [Slider]）本身就有焦点语义，
  /// 不需要也不应该套 [TvFocusable]，方向键能直接遍历到。问题只在于 Material
  /// 默认的聚焦高亮是一层很淡的 overlay —— 压在视频画面上基本看不出来。
  /// 这里统一改成实心底色 + 白描边。
  Widget _withTvFocusTheme(BuildContext context, Widget child) {
    if (!TvCapabilities.isTvMode) return child;

    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        iconButtonTheme: IconButtonThemeData(
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.focused)
                  ? Colors.white24
                  : Colors.transparent,
            ),
            side: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.focused)
                  ? const BorderSide(color: Colors.white, width: 2)
                  : BorderSide.none,
            ),
          ),
        ),
      ),
      child: child,
    );
  }

  Widget _buildTopBar(BuildContext context, WidgetRef ref) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            ),
            Expanded(
              child: Text(
                video.name,
                style: context.textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // 书签按钮
            if (onShowBookmarks != null)
              IconButton(
                onPressed: onShowBookmarks,
                icon: const Icon(Icons.bookmark_outline_rounded, color: Colors.white),
                tooltip: context.l10n.videoControlsBookmarkTooltip,
              ),
            // 倍速（移到右上角）
            _SpeedButton(
              speed: state.speed,
              onSpeedChange: onSpeedChange,
            ),
          ],
        ),
      );

  Widget _buildCenterControls(BuildContext context) {
    final isTvMode = TvCapabilities.isTvMode;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 上一个（播放列表）
        if (hasPlaylist)
          if (isTvMode)
            TvFocusable(
              onPressed: hasPrevious ? onPlayPrevious! : () {},
              child: _buildButton(
                Icons.skip_previous_rounded,
                36,
                hasPrevious ? Colors.white : Colors.white38,
              ),
            )
          else
            IconButton(
              onPressed: hasPrevious ? onPlayPrevious : null,
              iconSize: 36,
              icon: Icon(
                Icons.skip_previous_rounded,
                color: hasPrevious ? Colors.white : Colors.white38,
              ),
            ),
        // 快退
        if (isTvMode)
          TvFocusable(
            onPressed: onSeekBackward,
            child: _SeekButton(
              onPressed: onSeekBackward,
              icon: _getReplayIcon(),
              seekInterval: seekInterval,
              needsLabel: _needsSeekLabel,
              focusable: false,
            ),
          )
        else
          _SeekButton(
            onPressed: onSeekBackward,
            icon: _getReplayIcon(),
            seekInterval: seekInterval,
            needsLabel: _needsSeekLabel,
          ),
        const SizedBox(width: 24),
        // 播放/暂停
        if (isTvMode)
          TvFocusable(
            autofocus: true,
            onPressed: onPlayPause,
            child: _buildButton(
              state.isPlaying ? Icons.pause_circle_rounded : Icons.play_circle_rounded,
              64,
              Colors.white,
            ),
          )
        else
          IconButton(
            onPressed: onPlayPause,
            iconSize: 64,
            icon: Icon(
              state.isPlaying ? Icons.pause_circle_rounded : Icons.play_circle_rounded,
              color: Colors.white,
            ),
          ),
        const SizedBox(width: 24),
        // 快进
        if (isTvMode)
          TvFocusable(
            onPressed: onSeekForward,
            child: _SeekButton(
              onPressed: onSeekForward,
              icon: _getForwardIcon(),
              seekInterval: seekInterval,
              needsLabel: _needsSeekLabel,
              focusable: false,
            ),
          )
        else
          _SeekButton(
            onPressed: onSeekForward,
            icon: _getForwardIcon(),
            seekInterval: seekInterval,
            needsLabel: _needsSeekLabel,
          ),
        // 下一个（播放列表）
        if (hasPlaylist)
          if (isTvMode)
            TvFocusable(
              onPressed: hasNext ? onPlayNext! : () {},
              child: _buildButton(
                Icons.skip_next_rounded,
                36,
                hasNext ? Colors.white : Colors.white38,
              ),
            )
          else
            IconButton(
              onPressed: hasNext ? onPlayNext : null,
              iconSize: 36,
              icon: Icon(
                Icons.skip_next_rounded,
                color: hasNext ? Colors.white : Colors.white38,
              ),
            ),
      ],
    );
  }

  Widget _buildButton(IconData icon, double size, Color color) => Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, size: size, color: color),
      );

  Widget _buildBottomBar(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 进度条
            Row(
              children: [
                Text(
                  state.positionText,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 12),
                      activeTrackColor: Colors.white,
                      inactiveTrackColor: Colors.white30,
                      thumbColor: Colors.white,
                      overlayColor: Colors.white24,
                    ),
                    child: VideoSeekSlider(
                      progress: state.progress,
                      duration: state.duration,
                      onSeek: onSeek,
                    ),
                  ),
                ),
                Text(
                  state.durationText,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),

            // 控制按钮
            Row(
              children: [
                // 音量
                _VolumeButton(
                  volume: state.volume,
                  onVolumeChange: onVolumeChange,
                ),
                const Spacer(),
                // 播放列表按钮
                if (hasPlaylist)
                  IconButton(
                    onPressed: () => showPlaylistSheet(context),
                    icon: const Icon(
                      Icons.playlist_play_rounded,
                      color: Colors.white,
                    ),
                    tooltip: context.l10n.videoControlsPlaylistTooltip,
                  ),
                // 画中画（移到原倍速位置）
                if (isPipSupported)
                  IconButton(
                    onPressed: onTogglePip,
                    icon: Icon(
                      state.isPictureInPicture
                          ? Icons.picture_in_picture_alt
                          : Icons.picture_in_picture,
                      color: Colors.white,
                    ),
                    tooltip: state.isPictureInPicture ? context.l10n.videoControlsPipExitTooltip : context.l10n.videoControlsPipTooltip,
                  ),
                // 投屏按钮
                const CastButton(),
                // 清晰度按钮
                const QualityButton(),
                // 画面比例快捷按钮
                _AspectRatioButton(),
                // 设置按钮
                IconButton(
                  onPressed: () => showInfuseSettingsPanel(
                    context,
                    videoPath: video.path,
                    videoName: video.name,
                    tmdbId: tmdbId,
                    isMovie: isMovie,
                    seasonNumber: seasonNumber,
                    episodeNumber: episodeNumber,
                  ),
                  icon: const Icon(
                    Icons.tune_rounded,
                    color: Colors.white,
                  ),
                  tooltip: context.l10n.videoControlsSettingsTooltip,
                ),
                // 全屏
                IconButton(
                  onPressed: onToggleFullscreen,
                  icon: Icon(
                    state.isFullscreen
                        ? Icons.fullscreen_exit_rounded
                        : Icons.fullscreen_rounded,
                    color: Colors.white,
                  ),
                  tooltip: state.isFullscreen ? context.l10n.videoControlsFullscreenExitTooltip : context.l10n.videoControlsFullscreenTooltip,
                ),
              ],
            ),
          ],
        ),
      );
}

/// 拖动时仅更新本地预览，松手后只发出一次 seek。
///
/// media_kit 的每次 seek 都可能重新发起 HTTP Range 请求；直接在 Slider 的
/// onChanged 中调用会在一次拖动内制造几十个并发请求，最终耗尽 SMB 流连接。
class VideoSeekSlider extends StatefulWidget {
  const VideoSeekSlider({
    required this.progress,
    required this.duration,
    required this.onSeek,
    super.key,
  });

  final double progress;
  final Duration duration;
  final ValueChanged<Duration> onSeek;

  @override
  State<VideoSeekSlider> createState() => _VideoSeekSliderState();
}

class _VideoSeekSliderState extends State<VideoSeekSlider> {
  double? _dragProgress;

  @override
  Widget build(BuildContext context) {
    final value = (_dragProgress ?? widget.progress).clamp(0.0, 1.0);
    return Slider(
      value: value,
      onChangeStart: widget.duration > Duration.zero
          ? (value) => setState(() => _dragProgress = value)
          : null,
      onChanged: widget.duration > Duration.zero
          ? (value) => setState(() => _dragProgress = value)
          : null,
      onChangeEnd: widget.duration > Duration.zero
          ? (value) {
              final target = Duration(
                milliseconds: (value * widget.duration.inMilliseconds).round(),
              );
              setState(() => _dragProgress = null);
              widget.onSeek(target);
            }
          : null,
    );
  }
}

class _VolumeButton extends StatefulWidget {
  const _VolumeButton({
    required this.volume,
    required this.onVolumeChange,
  });

  final double volume;
  final ValueChanged<double> onVolumeChange;

  @override
  State<_VolumeButton> createState() => _VolumeButtonState();
}

class _VolumeButtonState extends State<_VolumeButton> {
  bool _showSlider = false;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: () => setState(() => _showSlider = !_showSlider),
            icon: Icon(
              widget.volume == 0
                  ? Icons.volume_off_rounded
                  : widget.volume < 0.5
                      ? Icons.volume_down_rounded
                      : Icons.volume_up_rounded,
              color: Colors.white,
            ),
          ),
          if (_showSlider)
            SizedBox(
              width: 100,
              child: Slider(
                value: widget.volume,
                onChanged: widget.onVolumeChange,
                activeColor: Colors.white,
                inactiveColor: Colors.white30,
              ),
            ),
        ],
      );
}

class _SpeedButton extends StatelessWidget {
  const _SpeedButton({
    required this.speed,
    required this.onSpeedChange,
  });

  final double speed;
  final ValueChanged<double> onSpeedChange;

  @override
  Widget build(BuildContext context) => PopupMenuButton<double>(
        onSelected: onSpeedChange,
        offset: const Offset(0, -200),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white54),
            borderRadius: AppRadius.borderRadiusSm,
          ),
          child: Text(
            '${speed}x',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
        itemBuilder: (context) => availableSpeeds
            .map(
              (s) => PopupMenuItem(
                value: s,
                child: Row(
                  children: [
                    if (s == speed) const Icon(Icons.check_rounded, size: 18),
                    if (s != speed) const SizedBox(width: 18),
                    const SizedBox(width: 8),
                    Text('${s}x'),
                  ],
                ),
              ),
            )
            .toList(),
      );
}

/// 快进/快退按钮，支持自定义秒数显示
class _SeekButton extends StatelessWidget {
  const _SeekButton({
    required this.onPressed,
    required this.icon,
    required this.seekInterval,
    required this.needsLabel,
    this.focusable = true,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final int seekInterval;
  final bool needsLabel;

  /// 是否自带焦点语义（内部使用 [IconButton]）。
  ///
  /// TV 上传 false：外层由 [TvFocusable] 提供焦点框和 SELECT 激活，
  /// 内部再套一个 [IconButton] 会变成两个焦点节点（D-pad 要按两次才过得去）。
  final bool focusable;

  @override
  Widget build(BuildContext context) {
    if (needsLabel) {
      if (!focusable) {
        return SizedBox(
          width: 48,
          height: 48,
          child: _buildLabeledIcon(),
        );
      }
      // 对于没有内置图标的秒数，使用 replay_10/forward_10 作为基础图标
      // 用黑色背景完全遮盖原图标中的 "10"，然后叠加自定义数字
      return SizedBox(
        width: 48,
        height: 48,
        child: IconButton(
          onPressed: onPressed,
          iconSize: 48,
          padding: EdgeInsets.zero,
          icon: _buildLabeledIcon(),
        ),
      );
    }

    // 对于有内置图标的秒数（5, 10, 30），直接显示图标
    if (!focusable) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, color: Colors.white, size: 48),
      );
    }

    return IconButton(
      onPressed: onPressed,
      iconSize: 48,
      icon: Icon(icon, color: Colors.white),
    );
  }

  /// 自定义秒数的叠加图标（基础图标 + 遮盖块 + 数字）。
  Widget _buildLabeledIcon() => Stack(
        alignment: Alignment.center,
        children: [
          // 基础图标 (replay_10 或 forward_10)
          Icon(icon, color: Colors.white, size: 48),
          // 用黑色背景完全遮盖原图标中心的 "10" 数字
          Container(
            width: 18,
            height: 14,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 在遮盖区域上叠加自定义数字
          Text(
            '$seekInterval',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              height: 1,
            ),
          ),
        ],
      );
}

/// 画面比例快捷按钮
class _AspectRatioButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aspectRatio = ref.watch(aspectRatioModeProvider);

    return PopupMenuButton<AspectRatioMode>(
      onSelected: (mode) {
        ref.read(aspectRatioModeProvider.notifier).state = mode;
      },
      offset: const Offset(0, -280),
      color: Colors.black87,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      tooltip: context.l10n.videoControlsAspectRatioTooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.aspect_ratio, color: Colors.white, size: 20),
            const SizedBox(width: 4),
            Text(
              aspectRatio.label,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
      ),
      itemBuilder: (context) => AspectRatioMode.values
          .map(
            (mode) => PopupMenuItem<AspectRatioMode>(
              value: mode,
              child: Row(
                children: [
                  Icon(
                    _getAspectRatioIcon(mode),
                    size: 18,
                    color: mode == aspectRatio ? Colors.white : Colors.white70,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      localizeFormText(context, mode.label),
                      style: TextStyle(
                        color: mode == aspectRatio ? Colors.white : Colors.white70,
                        fontWeight:
                            mode == aspectRatio ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (mode == aspectRatio)
                    const Icon(Icons.check_rounded, size: 18, color: Colors.white),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  IconData _getAspectRatioIcon(AspectRatioMode mode) => switch (mode) {
        AspectRatioMode.auto => Icons.auto_fix_high,
        AspectRatioMode.fill => Icons.fullscreen_rounded,
        AspectRatioMode.contain => Icons.fit_screen,
        AspectRatioMode.cover => Icons.crop_free,
        AspectRatioMode.r16x9 => Icons.rectangle_outlined,
        AspectRatioMode.r4x3 => Icons.crop_3_2,
        AspectRatioMode.r21x9 => Icons.panorama_wide_angle_outlined,
        AspectRatioMode.r1x1 => Icons.crop_square,
      };
}
