import 'dart:io';

import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/music/data/services/music_cover_cache_service.dart';
import 'package:my_nas/features/music/presentation/pages/music_list_page.dart';
import 'package:my_nas/features/music/presentation/widgets/animated_components.dart';

/// 最近播放区域 - 大封面卡片横向滚动
///
/// 现代化设计：
/// - 140x140 大封面尺寸
/// - 悬浮播放按钮带动画
/// - 阴影增强的卡片效果
class RecentTracksSection extends StatelessWidget {
  const RecentTracksSection({
    required this.tracks,
    required this.isDark,
    required this.onTrackTap,
    required this.onMoreTap,
    this.isDesktop = false,
    this.title = 'Recently Played',
    super.key,
  });

  final List<MusicFileWithSource> tracks;
  final bool isDark;
  final bool isDesktop;
  final String title;
  final void Function(MusicFileWithSource track) onTrackTap;
  final VoidCallback onMoreTap;

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) {
      return const SizedBox.shrink();
    }

    final displayTracks = tracks.take(isDesktop ? 10 : 8).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题栏
        _buildHeader(context),
        const SizedBox(height: 14),
        // 水平滚动列表
        SizedBox(
          height: isDesktop ? 220 : 200,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: isDesktop ? 0 : 16),
            itemCount: displayTracks.length,
            itemBuilder: (context, index) {
              final track = displayTracks[index];
              return Padding(
                padding: EdgeInsets.only(
                  right: index == displayTracks.length - 1 ? 0 : 14,
                ),
                child: _ModernTrackCard(
                  track: track,
                  isDark: isDark,
                  isDesktop: isDesktop,
                  onTap: () => onTrackTap(track),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) => Padding(
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 0 : 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  fontSize: isDesktop ? 20 : 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
          AnimatedPressable(
            onTap: onMoreTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.l10n.musicViewAll,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 14,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
}

/// 现代化歌曲卡片
class _ModernTrackCard extends StatefulWidget {
  const _ModernTrackCard({
    required this.track,
    required this.isDark,
    required this.onTap,
    this.isDesktop = false,
  });

  final MusicFileWithSource track;
  final bool isDark;
  final bool isDesktop;
  final VoidCallback onTap;

  @override
  State<_ModernTrackCard> createState() => _ModernTrackCardState();
}

class _ModernTrackCardState extends State<_ModernTrackCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final cardWidth = widget.isDesktop ? 160.0 : 140.0;
    final coverSize = widget.isDesktop ? 160.0 : 140.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedPressable(
        onTap: widget.onTap,
        child: SizedBox(
          width: cardWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 封面
              _buildCover(coverSize),
              const SizedBox(height: 10),
              // 歌曲信息
              Text(
                widget.track.displayTitle,
                style: TextStyle(
                  fontSize: widget.isDesktop ? 14 : 13,
                  fontWeight: FontWeight.w600,
                  color: widget.isDark ? Colors.white : Colors.black87,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Text(
                widget.track.displayArtist,
                style: TextStyle(
                  fontSize: widget.isDesktop ? 12 : 11,
                  color: widget.isDark ? Colors.white54 : Colors.black45,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCover(double size) {
    Widget coverImage;
    final effectiveCoverPath = _getEffectiveCoverPath();
    if (effectiveCoverPath != null && effectiveCoverPath.isNotEmpty) {
      // 本地文件封面
      coverImage = Image.file(
        File(effectiveCoverPath),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _buildDefaultCover(),
      );
    } else if (widget.track.coverUrl != null && widget.track.coverUrl!.isNotEmpty) {
      // 远程 URL 封面
      coverImage = Image.network(
        widget.track.coverUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _buildDefaultCover(),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _buildDefaultCover();
        },
      );
    } else {
      coverImage = _buildDefaultCover();
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: widget.isDark ? 0.35 : 0.15),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            coverImage,
            // 渐变遮罩
            Positioned.fill(
              child: AnimatedOpacity(
                opacity: _isHovered ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.4),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // 悬浮播放按钮
            Positioned(
              right: 10,
              bottom: 10,
              child: AnimatedScale(
                scale: _isHovered ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutBack,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.primary, AppColors.secondary],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.4),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ),
            // 常驻播放按钮（移动端）
            if (!_isHovered)
              Positioned(
                right: 10,
                bottom: 10,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultCover() => ColoredBox(
      color: widget.isDark
          ? Colors.white.withValues(alpha: 0.1)
          : Colors.black.withValues(alpha: 0.05),
      child: Icon(
        Icons.music_note_rounded,
        color: widget.isDark ? Colors.white30 : Colors.black26,
        size: 48,
      ),
    );

  /// 动态获取有效的封面路径
  String? _getEffectiveCoverPath() {
    // 1. 检查直接存储的路径
    if (widget.track.coverPath != null && widget.track.coverPath!.isNotEmpty) {
      if (File(widget.track.coverPath!).existsSync()) {
        return widget.track.coverPath;
      }
    }
    // 2. 动态从缓存服务获取
    final uniqueKey = '${widget.track.sourceId}_${widget.track.path}';
    return MusicCoverCacheService().getCachedCoverPathSync(uniqueKey);
  }
}

/// 热门歌曲区域 - 现代列表设计
///
/// 现代化设计：
/// - 更大的封面（52x52）
/// - 排名高亮
/// - 专辑色彩条
class PopularTracksSection extends StatelessWidget {
  const PopularTracksSection({
    required this.tracks,
    required this.isDark,
    required this.onTrackTap,
    required this.onMoreTap,
    this.isDesktop = false,
    this.title = 'Recommended for you',
    this.maxItems = 5,
    super.key,
  });

  final List<MusicFileWithSource> tracks;
  final bool isDark;
  final bool isDesktop;
  final String title;
  final int maxItems;
  final void Function(MusicFileWithSource track) onTrackTap;
  final VoidCallback onMoreTap;

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) {
      return const SizedBox.shrink();
    }

    final displayTracks = tracks.take(maxItems).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题栏
        _buildHeader(context),
        const SizedBox(height: 14),
        // 歌曲列表
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isDesktop ? 0 : 16),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Column(
                children: List.generate(displayTracks.length, (index) {
                  final track = displayTracks[index];
                  return _ModernTrackItem(
                    track: track,
                    index: index + 1,
                    isDark: isDark,
                    isDesktop: isDesktop,
                    isLast: index == displayTracks.length - 1,
                    onTap: () => onTrackTap(track),
                  );
                }),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) => Padding(
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 0 : 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(
                  color: AppColors.secondary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  fontSize: isDesktop ? 20 : 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
          AnimatedPressable(
            onTap: onMoreTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.l10n.musicViewAll,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 14,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
}

/// 现代化歌曲列表项
class _ModernTrackItem extends StatelessWidget {
  const _ModernTrackItem({
    required this.track,
    required this.index,
    required this.isDark,
    required this.onTap,
    this.isDesktop = false,
    this.isLast = false,
  });

  final MusicFileWithSource track;
  final int index;
  final bool isDark;
  final bool isDesktop;
  final bool isLast;
  final VoidCallback onTap;

  // 排名颜色
  Color get _rankColor {
    switch (index) {
      case 1:
        return const Color(0xFFFFD700); // 金色
      case 2:
        return const Color(0xFFC0C0C0); // 银色
      case 3:
        return const Color(0xFFCD7F32); // 铜色
      default:
        return isDark ? Colors.white38 : Colors.black26;
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedPressable(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isDesktop ? 16 : 14,
          vertical: isDesktop ? 12 : 10,
        ),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : Border(
                  bottom: BorderSide(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.black.withValues(alpha: 0.04),
                  ),
                ),
        ),
        child: Row(
          children: [
            // 排名
            SizedBox(
              width: 28,
              child: index <= 3
                  ? Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: _rankColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: Text(
                          '$index',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _rankColor,
                          ),
                        ),
                      ),
                    )
                  : Text(
                      '$index',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: _rankColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
            ),
            const SizedBox(width: 14),
            // 封面
            _buildCover(),
            const SizedBox(width: 14),
            // 信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.displayTitle,
                    style: TextStyle(
                      fontSize: isDesktop ? 14 : 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    track.displayArtist,
                    style: TextStyle(
                      fontSize: isDesktop ? 12 : 11,
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // 时长
            if (track.duration != null &&
                track.duration! > 0 &&
                track.duration! <= 86400000)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  track.durationText,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
              ),
            const SizedBox(width: 8),
            // 播放按钮
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.play_arrow_rounded,
                color: AppColors.primary,
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );

  Widget _buildCover() {
    Widget coverImage;
    final effectiveCoverPath = _getEffectiveCoverPath();
    if (effectiveCoverPath != null && effectiveCoverPath.isNotEmpty) {
      // 本地文件封面
      coverImage = Image.file(
        File(effectiveCoverPath),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _buildDefaultCover(),
      );
    } else if (track.coverUrl != null && track.coverUrl!.isNotEmpty) {
      // 远程 URL 封面
      coverImage = Image.network(
        track.coverUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _buildDefaultCover(),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _buildDefaultCover();
        },
      );
    } else {
      coverImage = _buildDefaultCover();
    }

    return Container(
      width: isDesktop ? 52 : 48,
      height: isDesktop ? 52 : 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 6,
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

  Widget _buildDefaultCover() => ColoredBox(
      color: isDark
          ? Colors.white.withValues(alpha: 0.1)
          : Colors.black.withValues(alpha: 0.05),
      child: Icon(
        Icons.music_note_rounded,
        color: isDark ? Colors.white30 : Colors.black26,
        size: 24,
      ),
    );

  /// 动态获取有效的封面路径
  String? _getEffectiveCoverPath() {
    // 1. 检查直接存储的路径
    if (track.coverPath != null && track.coverPath!.isNotEmpty) {
      if (File(track.coverPath!).existsSync()) {
        return track.coverPath;
      }
    }
    // 2. 动态从缓存服务获取
    final uniqueKey = '${track.sourceId}_${track.path}';
    return MusicCoverCacheService().getCachedCoverPathSync(uniqueKey);
  }
}
