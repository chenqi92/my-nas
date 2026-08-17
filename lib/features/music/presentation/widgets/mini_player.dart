import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/utils/local_file_uri.dart';
import 'package:my_nas/features/music/presentation/pages/music_player_page.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';

/// 底部迷你播放器 - 现代化设计
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMusic = ref.watch(currentMusicProvider);
    final playerState = ref.watch(musicPlayerControllerProvider);
    final playerNotifier = ref.read(musicPlayerControllerProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (currentMusic == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () => MusicPlayerPage.open(context),
      onVerticalDragEnd: (details) {
        // 向上滑动打开全屏播放器
        if (details.primaryVelocity != null &&
            details.primaryVelocity! < -200) {
          MusicPlayerPage.open(context);
        }
      },
      child: Container(
        height: 68,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: isDark
                    ? Colors.black.withValues(alpha: 0.4)
                    : Colors.white.withValues(alpha: 0.65),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.white.withValues(alpha: 0.8),
                  width: 0.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // 内容
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                    child: Row(
                      children: [
                        // 封面
                        _buildCover(
                          currentMusic.coverData,
                          currentMusic.coverUrl,
                          isDark,
                        ),
                        const SizedBox(width: 12),
                        // 歌曲信息
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                currentMusic.displayTitle,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 3),
                              // 动态进度条
                              _AnimatedProgressBar(
                                progress: playerState.progress,
                                isPlaying: playerState.isPlaying,
                                isDark: isDark,
                              ),
                            ],
                          ),
                        ),
                        // 控制按钮
                        _buildControlButtons(
                          ref,
                          playerState,
                          playerNotifier,
                          isDark,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCover(List<int>? coverData, String? coverUrl, bool isDark) {
    Widget coverImage;

    if (coverData != null && coverData.isNotEmpty) {
      coverImage = Image.memory(
        Uint8List.fromList(coverData),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _buildCoverPlaceholder(isDark),
      );
    } else if (coverUrl != null && coverUrl.isNotEmpty) {
      // 支持 file:// URL 和网络 URL
      if (coverUrl.startsWith('file://')) {
        final filePath = localPathFromFileUri(coverUrl);
        coverImage = filePath == null
            ? _buildCoverPlaceholder(isDark)
            : Image.file(
                File(filePath),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => _buildCoverPlaceholder(isDark),
              );
      } else {
        coverImage = Image.network(
          coverUrl,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _buildCoverPlaceholder(isDark),
        );
      }
    } else {
      coverImage = _buildCoverPlaceholder(isDark);
    }

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: coverImage,
      ),
    );
  }

  Widget _buildCoverPlaceholder(bool isDark) => ColoredBox(
    color: isDark
        ? AppColors.darkSurfaceVariant
        : AppColors.lightSurfaceVariant,
    child: Icon(
      Icons.music_note_rounded,
      color: isDark
          ? AppColors.darkOnSurfaceVariant
          : AppColors.lightOnSurfaceVariant,
      size: 24,
    ),
  );

  Widget _buildControlButtons(
    WidgetRef ref,
    MusicPlayerState playerState,
    MusicPlayerNotifier playerNotifier,
    bool isDark,
  ) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      // 上一曲
      _buildControlButton(
        onPressed: playerNotifier.playPrevious,
        icon: Icons.skip_previous_rounded,
        size: 24,
        isDark: isDark,
      ),
      const SizedBox(width: 4),
      // 播放/暂停
      _buildPlayPauseButton(playerState, playerNotifier),
      const SizedBox(width: 4),
      // 下一曲
      _buildControlButton(
        onPressed: playerNotifier.playNext,
        icon: Icons.skip_next_rounded,
        size: 24,
        isDark: isDark,
      ),
    ],
  );

  Widget _buildControlButton({
    required VoidCallback onPressed,
    required IconData icon,
    required double size,
    required bool isDark,
  }) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(
          icon,
          size: size,
          color: isDark ? Colors.white70 : Colors.black54,
        ),
      ),
    ),
  );

  Widget _buildPlayPauseButton(
    MusicPlayerState playerState,
    MusicPlayerNotifier playerNotifier,
  ) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: playerNotifier.playOrPause,
    child: Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.secondary],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: playerState.isBuffering
          ? const Padding(
              padding: EdgeInsets.all(11),
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            )
          : Icon(
              playerState.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              size: 24,
              color: Colors.white,
            ),
    ),
  );
}

/// 动态进度条 - 带有流动动画效果
class _AnimatedProgressBar extends StatefulWidget {
  const _AnimatedProgressBar({
    required this.progress,
    required this.isPlaying,
    required this.isDark,
  });

  final double progress;
  final bool isPlaying;
  final bool isDark;

  @override
  State<_AnimatedProgressBar> createState() => _AnimatedProgressBarState();
}

class _AnimatedProgressBarState extends State<_AnimatedProgressBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    if (widget.isPlaying) {
      _shimmerController.repeat();
    }
  }

  @override
  void didUpdateWidget(_AnimatedProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !_shimmerController.isAnimating) {
      _shimmerController.repeat();
    } else if (!widget.isPlaying && _shimmerController.isAnimating) {
      _shimmerController.stop();
    }
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clampedProgress = widget.progress.clamp(0.0, 1.0);

    return SizedBox(
      height: 14,
      child: Row(
        children: [
          // 进度条
          Expanded(
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                // 背景轨道
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: widget.isDark
                        ? Colors.white.withValues(alpha: 0.15)
                        : Colors.black.withValues(alpha: 0.08),
                  ),
                ),
                // 进度
                AnimatedBuilder(
                  animation: _shimmerController,
                  builder: (context, child) => FractionallySizedBox(
                    widthFactor: clampedProgress,
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        gradient: LinearGradient(
                          colors: [
                            AppColors.primary,
                            AppColors.secondary,
                            AppColors.primary,
                          ],
                          stops: [0.0, _shimmerController.value, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
                // 进度点
                if (clampedProgress > 0)
                  Positioned(
                    child: FractionallySizedBox(
                      widthFactor: clampedProgress,
                      alignment: Alignment.centerLeft,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.5),
                                blurRadius: 4,
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
        ],
      ),
    );
  }
}
