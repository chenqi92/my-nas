import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/features/video/data/services/video_database_service.dart';
import 'package:my_nas/features/video/domain/entities/video_category_config.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/features/video/presentation/widgets/video_poster.dart';

/// 分类浏览卡片行（Infuse 风格）
///
/// 显示一组分类卡片，每个卡片使用该分类下视频海报作为背景，
/// 叠加彩色渐变层，中央显示分类名称。
class CategoryBrowseCardsRow extends StatefulWidget {
  const CategoryBrowseCardsRow({
    super.key,
    required this.category,
    required this.isDark,
    required this.onCategoryTap,
    required this.selectedFilters,
    this.enabledPaths,
  });

  /// 分类类型（电影-类型、电影-地区、剧集-类型、剧集-地区）
  final VideoHomeCategory category;

  /// 是否暗色主题
  final bool isDark;

  /// 点击分类卡片回调
  final void Function(String filter) onCategoryTap;

  /// 用户选择的筛选条件（只显示这些卡片）
  final List<String> selectedFilters;

  /// 启用的媒体库路径（用于过滤已禁用目录）
  final List<({String sourceId, String path})>? enabledPaths;

  @override
  State<CategoryBrowseCardsRow> createState() => _CategoryBrowseCardsRowState();
}

class _CategoryBrowseCardsRowState extends State<CategoryBrowseCardsRow> {
  List<_CategoryCardData>? _categories;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void didUpdateWidget(covariant CategoryBrowseCardsRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedFilters.length != widget.selectedFilters.length ||
        !_listEquals(oldWidget.selectedFilters, widget.selectedFilters)) {
      _loadCategories();
    }
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _loadCategories() async {
    if (widget.selectedFilters.isEmpty) {
      if (mounted) {
        setState(() {
          _categories = [];
          _loading = false;
        });
      }
      return;
    }

    setState(() => _loading = true);

    try {
      final db = VideoDatabaseService();
      await db.init();

      MediaCategory? mediaCategory;

      switch (widget.category) {
        case VideoHomeCategory.browseMovieGenres:
        case VideoHomeCategory.browseMovieRegions:
          mediaCategory = MediaCategory.movie;
        case VideoHomeCategory.browseTvGenres:
        case VideoHomeCategory.browseTvRegions:
          mediaCategory = MediaCategory.tvShow;
        default:
          mediaCategory = MediaCategory.movie;
      }

      // 为每个用户选择的筛选条件获取多个视频用于海报拼贴
      final categories = <_CategoryCardData>[];

      for (final filter in widget.selectedFilters) {
        List<VideoMetadata> videos;

        // 获取该分类下的多个视频（过滤已禁用目录）
        if (widget.category.isGenreCategory) {
          videos = mediaCategory == MediaCategory.movie
              ? await db.getMoviesByGenre(
                  filter,
                  limit: 6,
                  enabledPaths: widget.enabledPaths,
                )
              : await db.getTvShowsByGenre(
                  filter,
                  limit: 6,
                  enabledPaths: widget.enabledPaths,
                );
        } else {
          videos = mediaCategory == MediaCategory.movie
              ? await db.getMoviesByCountry(
                  filter,
                  limit: 6,
                  enabledPaths: widget.enabledPaths,
                )
              : await db.getTvShowsByCountry(
                  filter,
                  limit: 6,
                  enabledPaths: widget.enabledPaths,
                );
        }

        // 收集有海报的视频及其 sourceId（优先使用 displayPosterUrl 以支持本地 NFO 海报）
        final posterInfos = videos
            .where(
              (v) =>
                  v.displayPosterUrl != null && v.displayPosterUrl!.isNotEmpty,
            )
            .map((v) => (url: v.displayPosterUrl!, sourceId: v.sourceId))
            .toList();

        categories.add(
          _CategoryCardData(name: filter, posterInfos: posterInfos),
        );
      }

      if (mounted) {
        setState(() {
          _categories = categories;
          _loading = false;
        });
      }
    } on Exception {
      if (mounted) {
        setState(() {
          _categories = [];
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox.shrink();
    }

    if (_categories == null || _categories!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题栏
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _getIconColor().withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(_getIcon(), size: 18, color: _getIconColor()),
              ),
              const SizedBox(width: 10),
              Text(
                widget.category.displayName,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: widget.isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
        ),
        // 卡片列表（横向渐变色卡片）
        SizedBox(
          height: 120,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _categories!.length,
            itemBuilder: (context, index) {
              final category = _categories![index];
              return _InfuseStyleCard(
                data: category,
                isDark: widget.isDark,
                colorIndex: index,
                onTap: () => widget.onCategoryTap(category.name),
              );
            },
          ),
        ),
      ],
    );
  }

  IconData _getIcon() {
    switch (widget.category) {
      case VideoHomeCategory.browseMovieGenres:
        return Icons.category_rounded;
      case VideoHomeCategory.browseMovieRegions:
        return Icons.public_rounded;
      case VideoHomeCategory.browseTvGenres:
        return Icons.category_rounded;
      case VideoHomeCategory.browseTvRegions:
        return Icons.language_rounded;
      default:
        return Icons.category_rounded;
    }
  }

  Color _getIconColor() {
    switch (widget.category) {
      case VideoHomeCategory.browseMovieGenres:
        return AppColors.downloadColor;
      case VideoHomeCategory.browseMovieRegions:
        return AppColors.photoColor;
      case VideoHomeCategory.browseTvGenres:
        return AppColors.warning;
      case VideoHomeCategory.browseTvRegions:
        return AppColors.musicColor;
      default:
        return AppColors.primary;
    }
  }
}

/// 分类卡片数据
class _CategoryCardData {
  _CategoryCardData({required this.name, required this.posterInfos});

  final String name;

  /// 海报信息列表：(url, sourceId)
  final List<({String url, String sourceId})> posterInfos;
}

/// Infuse 风格的分类卡片（横向渐变色风格）
///
/// 特点：
/// - 横向卡片（240x120）
/// - 海报作为背景，叠加彩色渐变层
/// - 白色文字居中显示分类名称
class _InfuseStyleCard extends StatefulWidget {
  const _InfuseStyleCard({
    required this.data,
    required this.isDark,
    required this.colorIndex,
    required this.onTap,
  });

  final _CategoryCardData data;
  final bool isDark;
  final int colorIndex;
  final VoidCallback onTap;

  @override
  State<_InfuseStyleCard> createState() => _InfuseStyleCardState();
}

class _InfuseStyleCardState extends State<_InfuseStyleCard> {
  bool _isHovered = false;

  /// Infuse 风格的渐变色配置
  static const List<List<Color>> _gradientColors = [
    // 紫红色（爱情）
    [Color(0xFFE91E63), Color(0xFF9C27B0)],
    // 深蓝色（电视电影）
    [Color(0xFF1565C0), Color(0xFF0D47A1)],
    // 橙红色（动作）
    [Color(0xFFFF5722), Color(0xFFE64A19)],
    // 深紫色（犯罪/悬疑）
    [Color(0xFF512DA8), Color(0xFF311B92)],
    // 青色（科幻）
    [Color(0xFF00ACC1), Color(0xFF006064)],
    // 绿色（冒险/自然）
    [Color(0xFF43A047), Color(0xFF1B5E20)],
    // 琥珀色（历史/西部）
    [Color(0xFFFF8F00), Color(0xFFE65100)],
    // 靛蓝色（奇幻）
    [Color(0xFF3949AB), Color(0xFF1A237E)],
    // 棕红色（恐怖）
    [Color(0xFFC62828), Color(0xFF8E0000)],
    // 蓝灰色（纪录片）
    [Color(0xFF546E7A), Color(0xFF37474F)],
  ];

  List<Color> get _gradient =>
      _gradientColors[widget.colorIndex % _gradientColors.length];

  @override
  Widget build(BuildContext context) {
    // 卡片尺寸：横向渐变色卡片
    const cardWidth = 240.0;
    const cardHeight = 120.0;

    return Container(
      width: cardWidth,
      height: cardHeight,
      margin: const EdgeInsets.only(right: 12),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _isHovered ? 1.03 : 1.0,
            duration: const Duration(milliseconds: 150),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: _gradient[0].withValues(
                      alpha: _isHovered ? 0.5 : 0.4,
                    ),
                    blurRadius: _isHovered ? 16 : 12,
                    offset: Offset(0, _isHovered ? 6 : 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // 背景图片（使用第一张海报）
                    _buildBackground(),
                    // 彩色渐变叠加层
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            _gradient[0].withValues(alpha: 0.85),
                            _gradient[1].withValues(alpha: 0.75),
                          ],
                        ),
                      ),
                    ),
                    // 居中文字
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          widget.data.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                            shadows: [
                              Shadow(
                                color: Colors.black26,
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    // 悬停边框
                    if (_isHovered)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.5),
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 构建背景图片（支持 NAS 路径和网络 URL）
  Widget _buildBackground() {
    if (widget.data.posterInfos.isEmpty) {
      return _buildPlaceholder();
    }

    // 使用第一张海报作为背景
    final posterInfo = widget.data.posterInfos[0];
    return _buildSmartImage(posterInfo.url, posterInfo.sourceId);
  }

  /// 智能图片加载 - 支持 NAS 路径和网络 URL
  Widget _buildSmartImage(String imageUrl, String sourceId) => VideoPoster(
    posterUrl: imageUrl,
    sourceId: sourceId,
    fit: BoxFit.cover,
    placeholder: _buildPlaceholder(),
    errorWidget: _buildPlaceholder(),
  );

  Widget _buildPlaceholder() => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: _gradient,
      ),
    ),
  );
}
