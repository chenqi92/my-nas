import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';
import 'package:my_nas/features/music/presentation/pages/music_player_page.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';
import 'package:my_nas/features/music/presentation/widgets/animated_components.dart';

/// 播放卡片 - 现代化卡片设计
///
/// 特性:
/// - 卡片式布局（适配有顶栏的页面）
/// - 模糊背景
/// - 唱片旋转动画
/// - 呼吸光晕效果
/// - 内置进度条
/// - 播放控制按钮
class HeroPlayerCard extends ConsumerWidget {
  const HeroPlayerCard({
    required this.isDark,
    this.isDesktop = false,
    this.onShuffleTap,
    this.onPlayAllTap,
    this.scrollOffset = 0,
    super.key,
  });

  final bool isDark;
  final bool isDesktop;
  final VoidCallback? onShuffleTap;
  final VoidCallback? onPlayAllTap;
  final double scrollOffset;

  // 卡片参数
  static const double _cardHeight = 220.0;
  static const double _coverSize = 100.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMusic = ref.watch(currentMusicProvider);
    final playerState = ref.watch(musicPlayerControllerProvider);

    // 如果没有当前播放，显示欢迎卡片
    if (currentMusic == null) {
      return _buildWelcomeCard(context);
    }

    return _buildPlayingCard(context, ref, currentMusic, playerState);
  }

  /// 欢迎卡片 - 没有播放内容时显示
  Widget _buildWelcomeCard(BuildContext context) => Padding(
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 0 : 16),
      child: Container(
        height: _cardHeight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.primary,
              AppColors.primary.withValues(alpha: 0.8),
              AppColors.secondary,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 装饰性图案
              Positioned(
                right: -30,
                bottom: -30,
                child: Opacity(
                  opacity: 0.15,
                  child: Icon(
                    Icons.music_note_rounded,
                    size: 150,
                    color: Colors.white,
                  ),
                ),
              ),
              Positioned(
                left: -20,
                top: -20,
                child: Opacity(
                  opacity: 0.1,
                  child: Icon(
                    Icons.album_rounded,
                    size: 100,
                    color: Colors.white,
                  ),
                ),
              ),
              // 内容
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.play_circle_filled_rounded,
                      color: Colors.white,
                      size: 40,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      context.l10n.musicPlayerWelcomeTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      context.l10n.musicPlayerWelcomeSubtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 播放控制按钮组 - 欢迎状态只显示随机播放
                    _buildWelcomeActions(context),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

  /// 播放中卡片 - 显示当前播放内容
  Widget _buildPlayingCard(
    BuildContext context,
    WidgetRef ref,
    MusicItem currentMusic,
    MusicPlayerState playerState,
  ) => Padding(
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 0 : 16),
      child: GestureDetector(
        onTap: () => MusicPlayerPage.open(context),
        child: Container(
          height: _cardHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: isDark ? 0.3 : 0.2),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 模糊背景
                _buildBlurredBackground(currentMusic),
                // 渐变遮罩
                _buildGradientOverlay(),
                // 主内容
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      // 封面和信息
                      Expanded(
                        child: Row(
                          children: [
                            // 旋转封面 + 光晕
                            GlowingContainer(
                              isGlowing: playerState.isPlaying,
                              glowColor: AppColors.primary,
                              maxBlurRadius: 20,
                              minBlurRadius: 10,
                              maxSpreadRadius: 5,
                              minSpreadRadius: 2,
                              child: RotatingCover(
                                size: _coverSize,
                                isPlaying: playerState.isPlaying,
                                coverData: currentMusic.coverData,
                                coverUrl: currentMusic.coverUrl,
                                showVinyl: true,
                              ),
                            ),
                            const SizedBox(width: 16),
                            // 歌曲信息
                            Expanded(
                              child: _buildMusicInfo(context, currentMusic, playerState),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      // 进度条
                      _buildProgressBar(ref, playerState),
                      const SizedBox(height: 12),
                      // 播放控制按钮组
                      _buildPlaybackControls(context, ref, playerState),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

  /// 模糊背景
  Widget _buildBlurredBackground(MusicItem currentMusic) {
    final coverData = currentMusic.coverData;
    final coverUrl = currentMusic.coverUrl;

    Widget? coverImage;

    if (coverData != null && coverData.isNotEmpty) {
      coverImage = Image.memory(
        Uint8List.fromList(coverData),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _buildDefaultBackground(),
      );
    } else if (coverUrl != null && coverUrl.isNotEmpty) {
      if (coverUrl.startsWith('file://')) {
        final filePath = coverUrl.substring(7);
        coverImage = Image.file(
          File(filePath),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _buildDefaultBackground(),
        );
      } else {
        coverImage = Image.network(
          coverUrl,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _buildDefaultBackground(),
        );
      }
    }

    if (coverImage != null) {
      return ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Transform.scale(
          scale: 1.3, // 放大避免边缘露出
          child: coverImage,
        ),
      );
    }
    return _buildDefaultBackground();
  }

  Widget _buildDefaultBackground() => Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary,
            AppColors.primary.withValues(alpha: 0.7),
            AppColors.secondary,
          ],
        ),
      ),
    );

  Widget _buildGradientOverlay() => DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.3),
            Colors.black.withValues(alpha: 0.5),
          ],
        ),
      ),
    );

  /// 歌曲信息
  Widget _buildMusicInfo(BuildContext context, MusicItem currentMusic, MusicPlayerState playerState) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 播放状态标签
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (playerState.isPlaying)
                _buildPlayingIndicator()
              else
                Icon(
                  Icons.pause_circle_filled_rounded,
                  color: Colors.white,
                  size: 10,
                ),
              const SizedBox(width: 4),
              Text(
                playerState.isPlaying ? context.l10n.musicPlayerStatusPlaying : context.l10n.musicPlayerStatusPaused,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // 歌曲名 — 不要包 Flexible，否则 Column 高度紧时行高会被裁，
        // 中文字形下半部分（撇/捺/竖）会被切掉。Row 的 Expanded 已约束宽度，
        // maxLines:1 + ellipsis 自然处理水平溢出。
        Text(
          currentMusic.displayTitle,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.3,
            height: 1.3,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 3),
        // 艺术家
        Text(
          currentMusic.displayArtist,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.8),
            fontSize: 12,
            height: 1.3,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );

  /// 播放指示器动画
  Widget _buildPlayingIndicator() => SizedBox(
      width: 10,
      height: 10,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(3, (index) => _PlayingBar(delay: index * 100)),
      ),
    );

  /// 进度条
  Widget _buildProgressBar(WidgetRef ref, MusicPlayerState playerState) {
    final progress = playerState.progress.clamp(0.0, 1.0);

    return Column(
      children: [
        // 进度条
        SizedBox(
          height: 3,
          child: Stack(
            children: [
              // 背景轨道
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: Colors.white.withValues(alpha: 0.2),
                ),
              ),
              // 进度
              FractionallySizedBox(
                widthFactor: progress,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    gradient: LinearGradient(
                      colors: [Colors.white, Colors.white.withValues(alpha: 0.8)],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // 时间显示
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _formatDuration(playerState.position),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 10,
              ),
            ),
            Text(
              _formatDuration(playerState.duration),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 欢迎状态下的操作按钮（随机播放）
  Widget _buildWelcomeActions(BuildContext context) => Row(
      children: [
        // 随机播放
        if (onShuffleTap != null)
          _buildActionButton(
            icon: Icons.shuffle_rounded,
            label: context.l10n.musicPlayerShuffleButton,
            onTap: onShuffleTap!,
            isPrimary: true,
          ),
      ],
    );

  /// 播放控制按钮组
  Widget _buildPlaybackControls(
    BuildContext context,
    WidgetRef ref,
    MusicPlayerState playerState,
  ) {
    final playerNotifier = ref.read(musicPlayerControllerProvider.notifier);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 随机播放按钮（左侧）
        if (onShuffleTap != null) ...[
          _buildControlButton(
            icon: Icons.shuffle_rounded,
            onTap: onShuffleTap!,
            size: 32,
          ),
          const SizedBox(width: 12),
        ],
        // 上一首
        _buildControlButton(
          icon: Icons.skip_previous_rounded,
          onTap: playerNotifier.playPrevious,
          size: 36,
        ),
        const SizedBox(width: 8),
        // 播放/暂停
        _buildPlayPauseButton(
          isPlaying: playerState.isPlaying,
          onTap: playerNotifier.playOrPause,
        ),
        const SizedBox(width: 8),
        // 下一首
        _buildControlButton(
          icon: Icons.skip_next_rounded,
          onTap: playerNotifier.playNext,
          size: 36,
        ),
      ],
    );
  }

  /// 播放/暂停按钮（大号）
  Widget _buildPlayPauseButton({
    required bool isPlaying,
    required VoidCallback onTap,
  }) => AnimatedPressable(
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: AppColors.primary,
            size: 28,
          ),
        ),
      );

  /// 控制按钮（上一首/下一首等）
  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onTap,
    double size = 32,
  }) => AnimatedPressable(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          child: Icon(
            icon,
            color: Colors.white.withValues(alpha: 0.9),
            size: size * 0.75,
          ),
        ),
      );

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool isPrimary,
  }) => AnimatedPressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isPrimary ? Colors.white : Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isPrimary ? AppColors.primary : Colors.white,
              size: 16,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: isPrimary ? AppColors.primary : Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

/// 播放指示器条动画
class _PlayingBar extends StatefulWidget {
  const _PlayingBar({required this.delay});
  final int delay;

  @override
  State<_PlayingBar> createState() => _PlayingBarState();
}

class _PlayingBarState extends State<_PlayingBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _animation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    Future<void>.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) {
        _controller.repeat(reverse: true);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _animation,
      builder: (context, child) => Container(
          width: 2,
          height: 10 * _animation.value,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
    );
}
