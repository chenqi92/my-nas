import 'package:flutter/material.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';
import 'package:my_nas/features/music/presentation/widgets/music_queue_sheet.dart';

class MusicPlayerControls extends StatelessWidget {
  const MusicPlayerControls({
    required this.state,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrevious,
    required this.onSeek,
    required this.onVolumeChange,
    required this.onTogglePlayMode,
    this.onShowQueue,
    super.key,
  });

  final MusicPlayerState state;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<double> onVolumeChange;
  final VoidCallback onTogglePlayMode;
  final VoidCallback? onShowQueue;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 进度条
          _buildProgressBar(context),
          const SizedBox(height: 16),
          // 控制按钮
          _buildControlButtons(context),
          const SizedBox(height: 16),
          // 额外控制
          _buildExtraControls(context),
        ],
      );

  Widget _buildProgressBar(BuildContext context) => Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: state.progress.clamp(0.0, 1.0),
              onChanged: (value) {
                final position = Duration(
                  milliseconds: (value * state.duration.inMilliseconds).toInt(),
                );
                onSeek(position);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  state.positionText,
                  style: context.textTheme.labelSmall?.copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  state.durationText,
                  style: context.textTheme.labelSmall?.copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _buildControlButtons(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 上一曲
          IconButton(
            onPressed: onPrevious,
            iconSize: 40,
            icon: const Icon(Icons.skip_previous_rounded),
          ),
          const SizedBox(width: 24),
          // 播放/暂停
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.colorScheme.primary,
            ),
            child: IconButton(
              onPressed: onPlayPause,
              iconSize: 48,
              color: context.colorScheme.onPrimary,
              icon: Icon(
                state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              ),
            ),
          ),
          const SizedBox(width: 24),
          // 下一曲
          IconButton(
            onPressed: onNext,
            iconSize: 40,
            icon: const Icon(Icons.skip_next_rounded),
          ),
        ],
      );

  Widget _buildExtraControls(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // 播放模式
          IconButton(
            onPressed: onTogglePlayMode,
            icon: Icon(_getPlayModeIcon()),
            tooltip: _getPlayModeTooltip(context),
          ),
          // 音量
          _VolumeControl(
            volume: state.volume,
            onVolumeChange: onVolumeChange,
          ),
          // 播放列表
          IconButton(
            onPressed: onShowQueue ?? () => showMusicQueueSheet(context),
            icon: const Icon(Icons.queue_music),
            tooltip: context.l10n.musicPlayerControlsPlaylist,
          ),
        ],
      );

  IconData _getPlayModeIcon() => switch (state.playMode) {
        PlayMode.loop => Icons.repeat,
        PlayMode.repeatOne => Icons.repeat_one,
        PlayMode.shuffle => Icons.shuffle,
      };

  String _getPlayModeTooltip(BuildContext context) => switch (state.playMode) {
        PlayMode.loop => context.l10n.musicPlayerControlsLoopMode,
        PlayMode.repeatOne => context.l10n.musicPlayerControlsRepeatOneMode,
        PlayMode.shuffle => context.l10n.musicPlayerControlsShuffleMode,
      };
}

class _VolumeControl extends StatefulWidget {
  const _VolumeControl({
    required this.volume,
    required this.onVolumeChange,
  });

  final double volume;
  final ValueChanged<double> onVolumeChange;

  @override
  State<_VolumeControl> createState() => _VolumeControlState();
}

class _VolumeControlState extends State<_VolumeControl> {
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
            ),
            tooltip: context.l10n.musicPlayerControlsVolume,
          ),
          if (_showSlider)
            SizedBox(
              width: 100,
              child: Slider(
                value: widget.volume,
                onChanged: widget.onVolumeChange,
              ),
            ),
        ],
      );
}
