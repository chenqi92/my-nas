import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/features/pt_sites/presentation/utils/pt_search_launcher.dart';
import 'package:my_nas/features/video/data/services/tmdb_service.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/features/video/presentation/providers/video_detail_provider.dart';
import 'package:my_nas/features/video/presentation/widgets/video_poster.dart';
import 'package:my_nas/shared/widgets/adaptive_image.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';

/// 推荐内容区域组件
class RecommendationsSection extends ConsumerWidget {
  const RecommendationsSection({
    required this.tmdbId,
    required this.isMovie,
    required this.onItemTap,
    this.title = '推荐内容',
    this.maxCount = 20,
    super.key,
  });

  final int tmdbId;
  final bool isMovie;
  final void Function(TmdbMediaItem item) onItemTap;
  final String title;
  final int maxCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 获取推荐内容
    final recommendationsAsync = isMovie
        ? ref.watch(movieRecommendationsProvider(tmdbId))
        : ref.watch(tvRecommendationsProvider(tmdbId));

    return recommendationsAsync.when(
      loading: () => _buildSection(
        isDark,
        child: const SizedBox(
          height: 180,
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (recommendations) {
        if (recommendations.isEmpty) return const SizedBox.shrink();

        final displayItems = recommendations.take(maxCount).toList();

        return _buildSection(
          isDark,
          child: SizedBox(
            height: 200,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: displayItems.length,
              itemBuilder: (context, index) => Padding(
                  padding: EdgeInsets.only(
                    right: index < displayItems.length - 1 ? 12 : 0,
                  ),
                  child: _RecommendationCard(
                    item: displayItems[index],
                    onTap: () => onItemTap(displayItems[index]),
                  ),
                ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSection(bool isDark, {required Widget child}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
            ),
          ),
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
}

/// 相似内容区域组件
class SimilarContentSection extends ConsumerWidget {
  const SimilarContentSection({
    required this.tmdbId,
    required this.isMovie,
    required this.onItemTap,
    this.title = '相似内容',
    this.maxCount = 20,
    super.key,
  });

  final int tmdbId;
  final bool isMovie;
  final void Function(TmdbMediaItem item) onItemTap;
  final String title;
  final int maxCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final similarAsync = isMovie
        ? ref.watch(similarMoviesProvider(tmdbId))
        : ref.watch(similarTvShowsProvider(tmdbId));

    return similarAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (similar) {
        if (similar.isEmpty) return const SizedBox.shrink();

        final displayItems = similar.take(maxCount).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: displayItems.length,
                itemBuilder: (context, index) => Padding(
                    padding: EdgeInsets.only(
                      right: index < displayItems.length - 1 ? 12 : 0,
                    ),
                    child: _RecommendationCard(
                      item: displayItems[index],
                      onTap: () => onItemTap(displayItems[index]),
                    ),
                  ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 推荐卡片组件
class _RecommendationCard extends ConsumerStatefulWidget {
  const _RecommendationCard({
    required this.item,
    required this.onTap,
  });

  final TmdbMediaItem item;
  final VoidCallback onTap;

  @override
  ConsumerState<_RecommendationCard> createState() => _RecommendationCardState();
}

class _RecommendationCardState extends ConsumerState<_RecommendationCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const cardWidth = 120.0;

    // 查询本地是否有该视频的元数据
    final localVideoAsync = ref.watch(localVideoByTmdbIdProvider(widget.item.id));

    // 确定要使用的封面 URL：优先本地缓存，其次 TMDB 网络 URL
    final localPosterUrl = localVideoAsync.whenOrNull(
      data: (localVideo) => localVideo?.displayPosterUrl,
    );
    final posterUrl = localPosterUrl ?? widget.item.posterUrl;
    final hasPoster = posterUrl.isNotEmpty;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: () => _showQuickActions(context),
        onSecondaryTap: () => _showQuickActions(context),
        child: AnimatedScale(
          scale: _isHovered ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: SizedBox(
            width: cardWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 海报
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: _isHovered ? 0.3 : 0.2),
                          blurRadius: _isHovered ? 12 : 6,
                          offset: Offset(0, _isHovered ? 6 : 3),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // 图片 - 优先使用本地缓存的封面
                          if (hasPoster)
                            _buildPosterImage(posterUrl, localVideoAsync, isDark)
                          else
                            _buildPlaceholder(isDark),
                          // 渐变遮罩
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              height: 60,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withValues(alpha: 0.7),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // 评分
                          if (widget.item.voteAverage > 0)
                            Positioned(
                              right: 6,
                              bottom: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _getRatingColor(widget.item.voteAverage),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.star_rounded,
                                      size: 10,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      widget.item.ratingText,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          // 电视剧标记
                          if (!widget.item.isMovie)
                            Positioned(
                              left: 6,
                              top: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.accent.withValues(alpha: 0.9),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  '剧集',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          // 悬停边框
                          if (_isHovered)
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: AppColors.primary.withValues(alpha: 0.8),
                                  width: 2,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // 标题
                Text(
                  widget.item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                  ),
                ),
                // 年份
                if (widget.item.year != null)
                  Text(
                    '${widget.item.year}',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? AppColors.darkOnSurfaceVariant
                          : AppColors.lightOnSurfaceVariant,
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
      color: isDark ? AppColors.darkSurfaceVariant : Colors.grey[200],
      child: Center(
        child: Icon(
          widget.item.isMovie ? Icons.movie_rounded : Icons.live_tv_rounded,
          size: 32,
          color: isDark ? Colors.grey[600] : Colors.grey[400],
        ),
      ),
    );

  /// 构建海报图片 - 根据是否有本地视频选择合适的加载方式
  Widget _buildPosterImage(
    String posterUrl,
    AsyncValue<VideoMetadata?> localVideoAsync,
    bool isDark,
  ) {
    // 检查是否是 NAS 路径（本地缓存的海报）
    final isNasPath = posterUrl.startsWith('/') &&
        !posterUrl.startsWith('//') &&
        !posterUrl.contains('://');

    if (isNasPath) {
      // NAS 路径 - 使用 VideoPoster
      final localVideo = localVideoAsync.valueOrNull;
      final sourceId = localVideo?.sourceId ?? '';
      return VideoPoster(
        posterUrl: posterUrl,
        sourceId: sourceId,
        placeholder: _buildPlaceholder(isDark),
        errorWidget: _buildPlaceholder(isDark),
      );
    }

    // 网络 URL - 使用 AdaptiveImage
    return AdaptiveImage(
      imageUrl: posterUrl,
      placeholder: (_) => _buildPlaceholder(isDark),
      errorWidget: (_, _) => _buildPlaceholder(isDark),
    );
  }

  Color _getRatingColor(double rating) => AppColors.ratingColor(rating);

  /// 长按弹出快捷操作（去 PT 站搜索资源）
  Future<void> _showQuickActions(BuildContext context) async {
    final item = widget.item;
    final title = item.title.trim().isNotEmpty
        ? item.title.trim()
        : item.originalTitle.trim();
    if (title.isEmpty) return;

    final year = item.year;
    final queryWithYear = year != null ? '$title $year' : title;

    final action = await showAdaptiveModalSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.cloud_download_outlined),
              title: Text('在 PT 站搜索 "$title"'),
              subtitle: year != null ? Text('包含年份 $year') : null,
              onTap: () => Navigator.pop(sheetContext, 'searchWithYear'),
            ),
            ListTile(
              leading: const Icon(Icons.search_rounded),
              title: Text('在 PT 站搜索 "$title"（不含年份）'),
              onTap: () => Navigator.pop(sheetContext, 'searchTitleOnly'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!context.mounted || action == null) return;

    final query = action == 'searchWithYear' ? queryWithYear : title;
    await launchPtSearchForMedia(context, ref, query: query);
  }
}

/// 综合推荐区域 (推荐 + 相似)
class CombinedRecommendationsSection extends ConsumerWidget {
  const CombinedRecommendationsSection({
    required this.tmdbId,
    required this.isMovie,
    required this.onItemTap,
    super.key,
  });

  final int tmdbId;
  final bool isMovie;
  final void Function(TmdbMediaItem item) onItemTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
      children: [
        RecommendationsSection(
          tmdbId: tmdbId,
          isMovie: isMovie,
          onItemTap: onItemTap,
        ),
        const SizedBox(height: 24),
        SimilarContentSection(
          tmdbId: tmdbId,
          isMovie: isMovie,
          onItemTap: onItemTap,
        ),
      ],
    );
}
