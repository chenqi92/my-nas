import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/features/video/presentation/providers/scraper_provider.dart'
    show ScrapingStatus, ScrapingTaskState;
import 'package:my_nas/features/video/presentation/widgets/media_info_badges.dart';
import 'package:my_nas/features/video/presentation/widgets/video_poster.dart';
import 'package:my_nas/shared/widgets/adaptive_image.dart';

/// 详情页 Hero 区域组件
///
/// 重新设计后的 Banner:
/// - 更大的高度，占据更多屏幕空间
/// - 简介、按钮、详细信息浮动在 Banner 上
/// - TMDB/Trakt 评分标识
/// - 已观看/未观看按钮
class DetailHeroSection extends StatelessWidget {
  const DetailHeroSection({
    required this.metadata,
    required this.onPlay,
    this.onFavorite,
    this.onToggleWatched,
    this.onScrape,
    this.isFavorite = false,
    this.isWatched = false,
    this.watchProgress,
    this.backdropUrl,
    this.tagline,
    this.displayTitle,
    this.overview,
    this.tmdbRating,
    this.doubanRating,
    this.traktRating,
    this.imdbRating,
    this.metacriticRating,
    this.voteCount,
    this.sourceId,
    this.hideEpisodeInfo = false,
    this.scrapingTask,
    this.onScrapingDismiss,
    this.showMediaInfoBadges = true,
    super.key,
  });

  final VideoMetadata metadata;
  final VoidCallback onPlay;
  final VoidCallback? onFavorite;
  final VoidCallback? onToggleWatched;
  final VoidCallback? onScrape;
  final bool isFavorite;
  final bool isWatched;
  final double? watchProgress;
  final String? backdropUrl;
  final String? tagline;
  final String? displayTitle;
  final String? overview;
  final double? tmdbRating;
  /// 豆瓣评分（当只有豆瓣数据时使用）
  final double? doubanRating;
  final double? traktRating;
  /// IMDb 评分
  final double? imdbRating;
  /// Metacritic 评分（0-100）
  final int? metacriticRating;
  final int? voteCount;
  /// 用于加载 NAS 路径图片的 sourceId
  final String? sourceId;
  /// 是否隐藏剧集信息（S/E 标记），用于电视剧总览页
  final bool hideEpisodeInfo;
  /// 后台刮削任务状态
  final ScrapingTaskState? scrapingTask;
  /// 刮削完成后关闭回调
  final VoidCallback? onScrapingDismiss;
  /// 是否显示媒体信息标签（4K, HDR, Atmos 等）
  final bool showMediaInfoBadges;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isWide = size.width > 800;
    // 增加 Banner 高度：宽屏 600px，窄屏 550px
    final heroHeight = isWide ? 600.0 : 550.0;

    final displayBackdrop = backdropUrl ?? metadata.backdropUrl;
    final displayPoster = metadata.displayPosterUrl;
    final hasBackdrop = displayBackdrop != null && displayBackdrop.isNotEmpty;
    final hasPoster = displayPoster != null && displayPoster.isNotEmpty;

    // 使用简介：优先使用传入的 overview，否则使用 metadata 的
    final displayOverview = overview ?? metadata.overview;
    final hasOverview = displayOverview != null && displayOverview.isNotEmpty;

    return SizedBox(
      height: heroHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 背景图
          if (hasBackdrop)
            _buildSmartImage(
              displayBackdrop,
              placeholder: _buildBackdropPlaceholder(isDark),
              fit: BoxFit.cover,
            )
          else
            _buildBackdropPlaceholder(isDark),

          // 渐变遮罩 - 更强的渐变以便内容可读
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.2),
                  Colors.black.withValues(alpha: 0.5),
                  if (isDark) AppColors.darkBackground.withValues(alpha: 0.95) else Colors.black.withValues(alpha: 0.85),
                  if (isDark) AppColors.darkBackground else Colors.black,
                ],
                stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
              ),
            ),
          ),

          // 左侧渐变 (宽屏模式)
          if (isWide)
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    if (isDark) AppColors.darkBackground.withValues(alpha: 0.7) else Colors.black.withValues(alpha: 0.5),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.4],
                ),
              ),
            ),

          // 内容区域
          SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isWide ? 48 : 16,
                vertical: 16,
              ),
              child: isWide
                  ? _buildWideLayout(context, isDark, hasPoster, displayPoster, hasOverview, displayOverview)
                  : _buildNarrowLayout(context, isDark, hasPoster, displayPoster, hasOverview, displayOverview),
            ),
          ),

          // 刮削进度指示器（右上角）
          if (scrapingTask != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 16,
              child: _buildScrapingIndicator(context, scrapingTask!),
            ),
        ],
      ),
    );
  }

  /// 构建刮削进度指示器（紧凑版，放在右上角）
  Widget _buildScrapingIndicator(BuildContext context, ScrapingTaskState task) {
    final isCompleted = task.isCompleted;
    final isScraping = task.isScraping;

    return GestureDetector(
      onTap: isCompleted ? onScrapingDismiss : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isCompleted
                ? (task.status == ScrapingStatus.completed
                    ? AppColors.success.withValues(alpha: 0.5)
                    : AppColors.error.withValues(alpha: 0.5))
                : AppColors.primary.withValues(alpha: 0.5),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 图标/进度
            if (isScraping)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: task.progressPercent,
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  color: AppColors.primary,
                ),
              )
            else if (task.status == ScrapingStatus.completed)
              Icon(Icons.check_circle_rounded, color: AppColors.success, size: 16)
            else
              Icon(Icons.error_rounded, color: AppColors.error, size: 16),
            const SizedBox(width: 8),
            // 文字
            Text(
              isScraping
                  ? '${task.progress}/${task.total}'
                  : (task.status == ScrapingStatus.completed
                      ? context.l10n.videoDetailHeroScrapingCompletedEpisodes(task.successCount)
                      : context.l10n.videoDetailHeroScrapingFailed),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            // 关闭按钮（完成后显示）
            if (isCompleted) ...[
              const SizedBox(width: 6),
              Icon(
                Icons.close_rounded,
                size: 14,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 宽屏布局 (海报在左，信息在右)
  Widget _buildWideLayout(
    BuildContext context,
    bool isDark,
    bool hasPoster,
    String? displayPoster,
    bool hasOverview,
    String? displayOverview,
  ) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 海报
          if (hasPoster)
            Container(
              width: 220,
              height: 330,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _buildSmartImage(
                  displayPoster!,
                  placeholder: _buildPosterPlaceholder(isDark),
                ),
              ),
            ),
          if (hasPoster) const SizedBox(width: 32),
          // 信息区域
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 评分标识区
                _buildRatingBadges(),
                const SizedBox(height: 12),
                // 标题
                _buildTitleSection(isDark, large: true),
                const SizedBox(height: 8),
                // 元数据标签
                _buildMetadataRow(context, isDark),
                // 标语
                if (tagline != null && tagline!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildTagline(isDark),
                ],
                // 简介 (浮动在 Banner 上)
                if (hasOverview) ...[
                  const SizedBox(height: 16),
                  _buildOverviewSection(displayOverview!, large: true),
                ],
                const SizedBox(height: 20),
                // 操作按钮
                _buildActionButtons(context, isDark, large: true),
              ],
            ),
          ),
        ],
      );

  /// 窄屏布局 (垂直排列)
  Widget _buildNarrowLayout(
    BuildContext context,
    bool isDark,
    bool hasPoster,
    String? displayPoster,
    bool hasOverview,
    String? displayOverview,
  ) =>
      Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 评分标识区
          _buildRatingBadges(),
          const SizedBox(height: 12),
          // 海报和标题横向排列
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // 小海报
              if (hasPoster)
                Container(
                  width: 110,
                  height: 165,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _buildSmartImage(
                      displayPoster!,
                      placeholder: _buildPosterPlaceholder(isDark),
                    ),
                  ),
                ),
              if (hasPoster) const SizedBox(width: 16),
              // 标题和元数据
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _buildTitleSection(isDark),
                    const SizedBox(height: 6),
                    _buildMetadataRow(context, isDark),
                  ],
                ),
              ),
            ],
          ),
          // 标语
          if (tagline != null && tagline!.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildTagline(isDark),
          ],
          // 简介 (浮动在 Banner 上)
          if (hasOverview) ...[
            const SizedBox(height: 12),
            _buildOverviewSection(displayOverview!),
          ],
          const SizedBox(height: 16),
          // 操作按钮
          _buildActionButtons(context, isDark),
        ],
      );

  Widget _buildTitleSection(bool isDark, {bool large = false}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 主标题（优先使用传入的本地化标题）
        Text(
          displayTitle ?? metadata.displayTitle,
          style: TextStyle(
            fontSize: large ? 32 : 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            height: 1.2,
            shadows: [
              Shadow(
                offset: const Offset(0, 2),
                blurRadius: 4,
                color: Colors.black.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
        // 原标题 (如果不同)
        if (metadata.originalTitle != null &&
            metadata.originalTitle != metadata.title &&
            metadata.originalTitle!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              metadata.originalTitle!,
              style: TextStyle(
                fontSize: large ? 16 : 13,
                color: Colors.white.withValues(alpha: 0.7),
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
      ],
    );

  Widget _buildMetadataRow(BuildContext context, bool isDark) {
    final items = <Widget>[];

    // 年份
    if (metadata.year != null) {
      items.add(_buildMetadataChip(text: '${metadata.year}'));
    }

    // 时长
    if (metadata.runtime != null && metadata.runtime! > 0) {
      items.add(_buildMetadataChip(text: _formatRuntime(metadata.runtime!, context)));
    }

    // 内容分级（PG-13, R 等）
    if (metadata.certification != null) {
      items.add(_buildCertificationChip(metadata.certification!));
    }

    // 分辨率（4K, 1080p 等）
    if (metadata.resolution != null) {
      items.add(_buildResolutionChip(metadata.resolution!));
    }

    // HDR 格式
    if (metadata.hdrFormat != null) {
      items.add(_buildHdrChip(metadata.hdrFormat!));
    }

    // 3D 标识
    if (metadata.is3D) {
      items.add(_buildMetadataChip(
        text: '3D',
        backgroundColor: const Color(0xFF00BCD4).withValues(alpha: 0.3),
      ));
    }

    // 音频格式（Atmos, DTS:X 等）
    if (metadata.audioFormat != null) {
      items.add(_buildAudioChip(metadata.audioFormat!));
    }

    // 来源（BluRay, Remux 等）
    if (metadata.isRemux) {
      items.add(_buildMetadataChip(
        text: 'Remux',
        backgroundColor: const Color(0xFF4A148C).withValues(alpha: 0.3),
      ));
    } else if (metadata.videoSource != null) {
      items.add(_buildSourceChip(metadata.videoSource!));
    }

    // 类型
    if (metadata.genres != null && metadata.genres!.isNotEmpty) {
      items.add(_buildMetadataChip(text: metadata.genres));
    }

    // 剧集信息（如果不是电视剧总览页）
    if (metadata.category == MediaCategory.tvShow && !hideEpisodeInfo) {
      if (metadata.seasonNumber != null && metadata.episodeNumber != null) {
        // 复核文件名是否真能解析出剧集信息：
        // 早期版本可能把录屏文件名（如 bandicam 2025-04-29 11-20-31-308.mp4）
        // 末尾的毫秒数误解析为 SxxEyy 并写入 DB。当前解析器对带时间戳的名字
        // 会拒绝识别为剧集，若复核结果无 season/episode 则不显示该 chip。
        final reparsed = VideoFileNameParser.parse(metadata.fileName);
        if (reparsed.season != null || reparsed.episode != null) {
          items.add(_buildMetadataChip(
            text: 'S${metadata.seasonNumber} E${metadata.episodeNumber}',
            backgroundColor: AppColors.accent.withValues(alpha: 0.3),
          ));
        }
      }
    }

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: items,
    );
  }

  /// 内容分级标签
  Widget _buildCertificationChip(String certification) {
    Color borderColor;
    final upper = certification.toUpperCase();
    if (upper == 'G' || upper == 'TV-G') {
      borderColor = AppColors.success;
    } else if (upper == 'PG' || upper == 'TV-PG') {
      borderColor = AppColors.info;
    } else if (upper == 'PG-13' || upper == 'TV-14') {
      borderColor = AppColors.warning;
    } else if (upper == 'R' || upper == 'TV-MA' || upper == 'NC-17') {
      borderColor = AppColors.error;
    } else {
      borderColor = Colors.white54;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: borderColor, width: 1.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        certification,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: borderColor,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  /// 分辨率标签
  Widget _buildResolutionChip(String resolution) {
    final upper = resolution.toUpperCase();
    final is4K = upper == '4K' || upper == '2160P';
    final isHD = upper == '1080P';
    return _buildMetadataChip(
      text: is4K ? '4K' : resolution.replaceAll('p', 'P'),
      backgroundColor: is4K
          ? const Color(0xFFE50914).withValues(alpha: 0.4)
          : isHD
              ? AppColors.primary.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.15),
    );
  }

  /// HDR 标签
  Widget _buildHdrChip(String hdrFormat) {
    final isDolbyVision = hdrFormat.toUpperCase().contains('DOLBY') || hdrFormat == 'DV';
    return _buildMetadataChip(
      text: isDolbyVision ? 'Dolby Vision' : hdrFormat,
      backgroundColor: isDolbyVision
          ? Colors.black.withValues(alpha: 0.5)
          : const Color(0xFFFFD700).withValues(alpha: 0.3),
    );
  }

  /// 音频格式标签
  Widget _buildAudioChip(String audioFormat) {
    final upper = audioFormat.toUpperCase();
    final isAtmos = upper.contains('ATMOS');
    final isDtsX = upper.contains('DTS') && upper.contains('X');
    Color bgColor;
    if (isAtmos || isDtsX) {
      bgColor = Colors.black.withValues(alpha: 0.5);
    } else {
      bgColor = Colors.white.withValues(alpha: 0.15);
    }
    return _buildMetadataChip(text: audioFormat, backgroundColor: bgColor);
  }

  /// 来源标签
  Widget _buildSourceChip(String source) {
    final upper = source.toUpperCase();
    final isBluRay = upper.contains('BLU') || upper.contains('BD');
    final isWeb = upper.contains('WEB');
    String displayText;
    Color bgColor;
    if (isBluRay) {
      displayText = 'BluRay';
      bgColor = const Color(0xFF0D47A1).withValues(alpha: 0.3);
    } else if (isWeb) {
      displayText = upper.contains('DL') ? 'WEB-DL' : 'WEB';
      bgColor = const Color(0xFF2E7D32).withValues(alpha: 0.3);
    } else {
      displayText = source;
      bgColor = Colors.white.withValues(alpha: 0.15);
    }
    return _buildMetadataChip(text: displayText, backgroundColor: bgColor);
  }

  Widget _buildMetadataChip({
    String? text,
    IconData? icon,
    Color? iconColor,
    Color? backgroundColor,
  }) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: iconColor ?? Colors.white),
            const SizedBox(width: 4),
          ],
          if (text != null)
            Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );

  Widget _buildTagline(bool isDark) => Text(
      '"$tagline"',
      style: TextStyle(
        fontSize: 14,
        fontStyle: FontStyle.italic,
        color: Colors.white.withValues(alpha: 0.8),
      ),
    );

  /// 评分标识区域
  Widget _buildRatingBadges() => RatingBadges(
        tmdbRating: tmdbRating,
        imdbRating: imdbRating,
        metacriticRating: metacriticRating,
        traktRating: traktRating,
        doubanRating: doubanRating ?? (tmdbRating == null ? metadata.rating : null),
        voteCount: voteCount,
      );

  /// 简介区域 (浮动在 Banner 上)
  Widget _buildOverviewSection(String overview, {bool large = false}) {
    final maxLines = large ? 4 : 3;
    return Text(
      overview,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: large ? 14 : 13,
        height: 1.5,
        color: Colors.white.withValues(alpha: 0.85),
        shadows: [
          Shadow(
            offset: const Offset(0, 1),
            blurRadius: 2,
            color: Colors.black.withValues(alpha: 0.5),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, bool isDark, {bool large = false}) {
    final buttonHeight = large ? 48.0 : 42.0;
    final fontSize = large ? 15.0 : 14.0;

    return Row(
      children: [
        // 播放按钮
        Expanded(
          flex: 2,
          child: SizedBox(
            height: buttonHeight,
            child: ElevatedButton.icon(
              onPressed: onPlay,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                elevation: 4,
              ),
              icon: const Icon(Icons.play_arrow_rounded, size: 24),
              label: Text(
                watchProgress != null && watchProgress! > 0.05
                    ? context.l10n.videoDetailHeroPlayContinue
                    : context.l10n.videoDetailHeroPlayStart,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
        // 播放进度指示
        if (watchProgress != null && watchProgress! > 0.05) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${(watchProgress! * 100).toInt()}%',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
        // 已观看/未观看按钮
        if (onToggleWatched != null) ...[
          const SizedBox(width: 10),
          SizedBox(
            height: buttonHeight,
            width: buttonHeight,
            child: IconButton.filled(
              onPressed: onToggleWatched,
              tooltip: isWatched ? context.l10n.videoDetailHeroMarkUnwatched : context.l10n.videoDetailHeroMarkWatched,
              style: IconButton.styleFrom(
                backgroundColor: isWatched
                    ? AppColors.primary.withValues(alpha: 0.3)
                    : Colors.white.withValues(alpha: 0.15),
                foregroundColor: Colors.white,
              ),
              icon: Icon(
                isWatched ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded,
                color: isWatched ? AppColors.primary : Colors.white,
              ),
            ),
          ),
        ],
        // 收藏按钮
        if (onFavorite != null) ...[
          const SizedBox(width: 10),
          SizedBox(
            height: buttonHeight,
            width: buttonHeight,
            child: IconButton.filled(
              onPressed: onFavorite,
              tooltip: isFavorite ? context.l10n.videoDetailHeroRemoveFavorite : context.l10n.videoDetailHeroAddFavorite,
              style: IconButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.15),
                foregroundColor: Colors.white,
              ),
              icon: Icon(
                isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: isFavorite ? AppColors.error : Colors.white,
              ),
            ),
          ),
        ],
        // 刮削按钮
        if (onScrape != null) ...[
          const SizedBox(width: 10),
          SizedBox(
            height: buttonHeight,
            width: buttonHeight,
            child: IconButton.filled(
              onPressed: onScrape,
              tooltip: context.l10n.videoDetailHeroManualScrape,
              style: IconButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.15),
                foregroundColor: Colors.white,
              ),
              icon: const Icon(
                Icons.auto_fix_high_rounded,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBackdropPlaceholder(bool isDark) => Container(
      color: isDark ? AppColors.darkSurface : Colors.grey[800],
      child: Center(
        child: Icon(
          Icons.movie_rounded,
          size: 80,
          color: isDark ? Colors.grey[700] : Colors.grey[600],
        ),
      ),
    );

  Widget _buildPosterPlaceholder(bool isDark) => Container(
      color: isDark ? AppColors.darkSurfaceVariant : Colors.grey[700],
      child: Center(
        child: Icon(
          metadata.category == MediaCategory.tvShow
              ? Icons.live_tv_rounded
              : Icons.movie_rounded,
          size: 40,
          color: isDark ? Colors.grey[600] : Colors.grey[500],
        ),
      ),
    );

  /// 智能图片加载 - 根据 URL 类型选择合适的加载方式
  Widget _buildSmartImage(
    String imageUrl, {
    required Widget placeholder,
    BoxFit fit = BoxFit.cover,
  }) {
    // 检查是否是 NAS 路径（本地缓存的图片）
    final isNasPath = imageUrl.startsWith('/') &&
        !imageUrl.startsWith('//') &&
        !imageUrl.contains('://');

    final effectiveSourceId = sourceId;
    if (isNasPath && effectiveSourceId != null && effectiveSourceId.isNotEmpty) {
      // NAS 路径 - 使用 VideoPoster
      return VideoPoster(
        posterUrl: imageUrl,
        sourceId: effectiveSourceId,
        placeholder: placeholder,
        errorWidget: placeholder,
        fit: fit,
      );
    }

    // 网络 URL 或没有 sourceId - 使用 AdaptiveImage
    return AdaptiveImage(
      imageUrl: imageUrl,
      fit: fit,
      placeholder: (_) => placeholder,
      errorWidget: (_, _) => placeholder,
    );
  }

  String _formatRuntime(int minutes, BuildContext context) {
    if (minutes < 60) {
      return context.l10n.videoDetailHeroRuntimeMinutes(minutes);
    }
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
  }
}
