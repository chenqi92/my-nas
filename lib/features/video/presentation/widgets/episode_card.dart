import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/video/data/services/tmdb_service.dart';
import 'package:my_nas/shared/widgets/adaptive_image.dart';

/// 剧集卡片组件
class EpisodeCard extends StatefulWidget {
  const EpisodeCard({
    required this.episode,
    this.onTap,
    this.isAvailable = false,
    this.watchProgress,
    this.width = 200,
    super.key,
  });

  final TmdbEpisode episode;
  final VoidCallback? onTap;
  final bool isAvailable;
  final double? watchProgress;
  final double width;

  @override
  State<EpisodeCard> createState() => _EpisodeCardState();
}

class _EpisodeCardState extends State<EpisodeCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasStill = widget.episode.stillPath != null && widget.episode.stillPath!.isNotEmpty;
    final aspectRatio = 16 / 9;
    final imageHeight = widget.width / aspectRatio;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.isAvailable ? widget.onTap : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: widget.isAvailable ? 1.0 : 0.5,
          child: Container(
            width: widget.width,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: isDark ? AppColors.darkSurfaceVariant : Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: _isHovered ? 0.2 : 0.1),
                  blurRadius: _isHovered ? 12 : 6,
                  offset: Offset(0, _isHovered ? 4 : 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 剧照
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(12),
                      ),
                      child: SizedBox(
                        width: widget.width,
                        height: imageHeight,
                        child: hasStill
                            ? AdaptiveImage(
                                imageUrl: widget.episode.stillUrl,
                                placeholder: (_) => _buildPlaceholder(isDark),
                                errorWidget: (_, _) => _buildPlaceholder(isDark),
                              )
                            : _buildPlaceholder(isDark),
                      ),
                    ),
                    // 播放图标 (悬停或可播放时显示)
                    if (widget.isAvailable && _isHovered)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(12),
                            ),
                            color: Colors.black.withValues(alpha: 0.4),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.play_circle_fill_rounded,
                              size: 48,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    // 时长标签
                    if (widget.episode.runtime > 0)
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _formatRuntime(widget.episode.runtime),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    // 不可用标签
                    if (!widget.isAvailable)
                      Positioned(
                        left: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            context.l10n.videoEpisodeCardNoResource,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                // 进度条
                if (widget.watchProgress != null && widget.watchProgress! > 0)
                  ClipRRect(
                    child: LinearProgressIndicator(
                      value: widget.watchProgress!.clamp(0.0, 1.0),
                      minHeight: 3,
                      backgroundColor: isDark
                          ? AppColors.darkOutline
                          : Colors.grey[300],
                      valueColor: AlwaysStoppedAnimation<Color>(
                        widget.watchProgress! >= 0.9
                            ? AppColors.success
                            : AppColors.primary,
                      ),
                    ),
                  ),
                // 信息区域
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 集数和评分
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'E${widget.episode.episodeNumber}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          if (widget.episode.voteAverage > 0) ...[
                            const SizedBox(width: 8),
                            Icon(
                              Icons.star_rounded,
                              size: 14,
                              color: Colors.amber[600],
                            ),
                            const SizedBox(width: 2),
                            Text(
                              widget.episode.voteAverage.toStringAsFixed(1),
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? AppColors.darkOnSurfaceVariant
                                    : AppColors.lightOnSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      // 剧集标题
                      Text(
                        widget.episode.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                          color: isDark
                              ? AppColors.darkOnSurface
                              : AppColors.lightOnSurface,
                        ),
                      ),
                      // 播出日期
                      if (widget.episode.airDate.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          widget.episode.airDate,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? AppColors.darkOnSurfaceVariant
                                : AppColors.lightOnSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(bool isDark) => Container(
      color: isDark ? AppColors.darkSurfaceElevated : Colors.grey[200],
      child: Center(
        child: Icon(
          Icons.movie_rounded,
          size: 40,
          color: isDark ? Colors.grey[600] : Colors.grey[400],
        ),
      ),
    );

  String _formatRuntime(int minutes) {
    if (minutes < 60) {
      return context.l10n.videoEpisodeCardRuntimeMinutes(minutes);
    }
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return mins > 0
        ? context.l10n.videoEpisodeCardRuntimeHoursMinutes(hours, mins)
        : context.l10n.videoEpisodeCardRuntimeHours(hours);
  }
}

/// 简化版剧集卡片 (用于紧凑列表)
class CompactEpisodeCard extends StatelessWidget {
  const CompactEpisodeCard({
    required this.episode,
    this.onTap,
    this.isAvailable = false,
    this.watchProgress,
    super.key,
  });

  final TmdbEpisode episode;
  final VoidCallback? onTap;
  final bool isAvailable;
  final double? watchProgress;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasStill = episode.stillPath != null && episode.stillPath!.isNotEmpty;

    return InkWell(
      onTap: isAvailable ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: isAvailable ? 1.0 : 0.5,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              // 缩略图
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 120,
                      height: 68,
                      child: hasStill
                          ? AdaptiveImage(
                              imageUrl: episode.stillUrl,
                              placeholder: (_) => _buildMiniPlaceholder(isDark),
                              errorWidget: (_, _) => _buildMiniPlaceholder(isDark),
                            )
                          : _buildMiniPlaceholder(isDark),
                    ),
                  ),
                  // 进度条
                  if (watchProgress != null && watchProgress! > 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(6),
                        ),
                        child: LinearProgressIndicator(
                          value: watchProgress!.clamp(0.0, 1.0),
                          minHeight: 3,
                          backgroundColor: Colors.black.withValues(alpha: 0.5),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            watchProgress! >= 0.9
                                ? AppColors.success
                                : AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              // 信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 集数和标题
                    Row(
                      children: [
                        Text(
                          context.l10n.videoCompactEpisodeCardEpisodeNumber(episode.episodeNumber),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                        if (!isAvailable) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? AppColors.darkOutline
                                  : Colors.grey[300],
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              context.l10n.videoEpisodeCardNoResource,
                              style: TextStyle(
                                fontSize: 9,
                                color: isDark
                                    ? AppColors.darkOnSurfaceVariant
                                    : Colors.grey[600],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      episode.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? AppColors.darkOnSurface
                            : AppColors.lightOnSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // 时长和日期
                    Row(
                      children: [
                        if (episode.runtime > 0)
                          Text(
                            context.l10n.videoEpisodeCardRuntimeMinutes(episode.runtime),
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? AppColors.darkOnSurfaceVariant
                                  : AppColors.lightOnSurfaceVariant,
                            ),
                          ),
                        if (episode.runtime > 0 && episode.airDate.isNotEmpty)
                          Text(
                            ' | ',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? AppColors.darkOnSurfaceVariant
                                  : AppColors.lightOnSurfaceVariant,
                            ),
                          ),
                        if (episode.airDate.isNotEmpty)
                          Text(
                            episode.airDate,
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? AppColors.darkOnSurfaceVariant
                                  : AppColors.lightOnSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              // 播放按钮
              if (isAvailable)
                IconButton(
                  onPressed: onTap,
                  icon: Icon(
                    Icons.play_circle_outline_rounded,
                    color: AppColors.primary,
                    size: 32,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniPlaceholder(bool isDark) => Container(
      color: isDark ? AppColors.darkSurfaceElevated : Colors.grey[200],
      child: Center(
        child: Icon(
          Icons.movie_rounded,
          size: 24,
          color: isDark ? Colors.grey[600] : Colors.grey[400],
        ),
      ),
    );
}
