import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/nastool/presentation/providers/nastool_provider.dart';
import 'package:my_nas/features/pt_sites/presentation/pages/pt_site_detail_page.dart';
import 'package:my_nas/features/pt_sites/presentation/providers/pt_site_provider.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/video/data/services/tmdb_service.dart';
import 'package:my_nas/features/video/data/services/video_database_service.dart';
import 'package:my_nas/features/video/presentation/pages/video_detail_page.dart';
import 'package:my_nas/shared/mixins/tab_bar_visibility_mixin.dart';
import 'package:my_nas/shared/providers/ui_style_provider.dart';
import 'package:my_nas/shared/widgets/adaptive_glass_app_bar.dart';
import 'package:my_nas/shared/widgets/adaptive_image.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';
import 'package:my_nas/shared/widgets/sheet_drag_handle.dart';

/// TMDB 预览页面 - 用于展示本地不存在的 TMDB 内容
class TmdbPreviewPage extends ConsumerStatefulWidget {
  const TmdbPreviewPage({
    required this.tmdbId,
    required this.isMovie,
    required this.title,
    this.posterUrl,
    this.backdropUrl,
    super.key,
  });

  final int tmdbId;
  final bool isMovie;
  final String title;
  final String? posterUrl;
  final String? backdropUrl;

  @override
  ConsumerState<TmdbPreviewPage> createState() => _TmdbPreviewPageState();
}

class _TmdbPreviewPageState extends ConsumerState<TmdbPreviewPage>
    with ConsumerTabBarVisibilityMixin {
  final TmdbService _tmdbService = TmdbService();
  bool _isLoading = true;
  Object? _detail; // TmdbMovieDetail or TmdbTvDetail
  List<TmdbMediaItem> _similarItems = [];
  List<TmdbMediaItem> _recommendedItems = [];

  @override
  void initState() {
    super.initState();
    hideTabBar();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      if (widget.isMovie) {
        final detail = await _tmdbService.getMovieDetail(widget.tmdbId);
        final similar = await _tmdbService.getSimilarMovies(widget.tmdbId);
        final recommended = await _tmdbService.getMovieRecommendations(widget.tmdbId);
        if (mounted) {
          setState(() {
            _detail = detail;
            _similarItems = similar.results;
            _recommendedItems = recommended.results;
            _isLoading = false;
          });
        }
      } else {
        final detail = await _tmdbService.getTvDetail(widget.tmdbId);
        final similar = await _tmdbService.getSimilarTvShows(widget.tmdbId);
        final recommended = await _tmdbService.getTvRecommendations(widget.tmdbId);
        if (mounted) {
          setState(() {
            _detail = detail;
            _similarItems = similar.results;
            _recommendedItems = recommended.results;
            _isLoading = false;
          });
        }
      }
    } on Exception catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final uiStyle = ref.watch(uiStyleProvider);
    final backdropUrl = widget.backdropUrl ?? _getBackdropUrl();
    final posterUrl = widget.posterUrl ?? _getPosterUrl();
    final safeTop = MediaQuery.of(context).padding.top;
    final bgColor = isDark ? const Color(0xFF0D0D0D) : Colors.grey[50];

    // iOS 26 玻璃模式
    if (uiStyle.isGlass) {
      return Scaffold(
        backgroundColor: bgColor,
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                children: [
                  // 主内容
                  CustomScrollView(
                    slivers: [
                      // 顶部背景区域
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: 300,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (backdropUrl != null && backdropUrl.isNotEmpty)
                                AdaptiveImage(
                                  imageUrl: backdropUrl,
                                  fit: BoxFit.cover,
                                ),
                              Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      bgColor!,
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // 内容
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // 海报
                                  if (posterUrl != null && posterUrl.isNotEmpty)
                                    Container(
                                      width: 100,
                                      height: 150,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.3),
                                            blurRadius: 8,
                                          ),
                                        ],
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: AdaptiveImage(
                                          imageUrl: posterUrl,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                  const SizedBox(width: 16),
                                  // 标题和信息
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _getTitle(),
                                          style: TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.bold,
                                            color: isDark ? Colors.white : Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        _buildMetaInfo(isDark),
                                        const SizedBox(height: 12),
                                        // 本地不可用标签
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: AppColors.warning.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(color: AppColors.warning.withValues(alpha: 0.5)),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.cloud_outlined, size: 16, color: AppColors.warning),
                                              const SizedBox(width: 6),
                                              Text(
                                                '本地不可用',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: AppColors.warning,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        // PT 站搜索按钮和 NASTool 订阅按钮
                                        _buildActionButtons(isDark),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                              // 简介
                              if (_getOverview().isNotEmpty) ...[
                                Text(
                                  '简介',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white : Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _getOverview(),
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: isDark ? Colors.grey[300] : Colors.grey[700],
                                    height: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 24),
                              ],
                              // 推荐内容
                              if (_recommendedItems.isNotEmpty)
                                _buildMediaSection('推荐内容', _recommendedItems, isDark),
                              // 相似内容
                              if (_similarItems.isNotEmpty)
                                _buildMediaSection('相似内容', _similarItems, isDark),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  // 悬浮返回按钮
                  Positioned(
                    top: safeTop + 8,
                    left: 16,
                    child: const GlassFloatingBackButton(),
                  ),
                ],
              ),
      );
    }

    // 经典模式
    return Scaffold(
      backgroundColor: bgColor,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                // 顶部背景
                SliverAppBar(
                  expandedHeight: 300,
                  pinned: true,
                  backgroundColor: bgColor,
                  flexibleSpace: FlexibleSpaceBar(
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (backdropUrl != null && backdropUrl.isNotEmpty)
                          AdaptiveImage(
                            imageUrl: backdropUrl,
                            fit: BoxFit.cover,
                          ),
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                bgColor!,
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // 内容
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 海报
                            if (posterUrl != null && posterUrl.isNotEmpty)
                              Container(
                                width: 100,
                                height: 150,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.3),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: AdaptiveImage(
                                    imageUrl: posterUrl,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            const SizedBox(width: 16),
                            // 标题和信息
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _getTitle(),
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  _buildMetaInfo(isDark),
                                  const SizedBox(height: 12),
                                  // 本地不可用标签
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: AppColors.warning.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: AppColors.warning.withValues(alpha: 0.5)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.cloud_outlined, size: 16, color: AppColors.warning),
                                        const SizedBox(width: 6),
                                        Text(
                                          '本地不可用',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.warning,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  // PT 站搜索按钮和 NASTool 订阅按钮
                                  _buildActionButtons(isDark),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        // 简介
                        if (_getOverview().isNotEmpty) ...[
                          Text(
                            '简介',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _getOverview(),
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark ? Colors.grey[300] : Colors.grey[700],
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                        // 推荐内容
                        if (_recommendedItems.isNotEmpty)
                          _buildMediaSection('推荐内容', _recommendedItems, isDark),
                        // 相似内容
                        if (_similarItems.isNotEmpty)
                          _buildMediaSection('相似内容', _similarItems, isDark),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildMetaInfo(bool isDark) {
    final items = <String>[];

    if (_detail is TmdbMovieDetail) {
      final movie = _detail! as TmdbMovieDetail;
      if (movie.year != null) items.add('${movie.year}');
      if (movie.runtime > 0) items.add('${movie.runtime}分钟');
      if (movie.voteAverage > 0) items.add('⭐ ${movie.voteAverage.toStringAsFixed(1)}');
    } else if (_detail is TmdbTvDetail) {
      final tv = _detail! as TmdbTvDetail;
      if (tv.year != null) items.add('${tv.year}');
      items.add('${tv.numberOfSeasons}季');
      if (tv.voteAverage > 0) items.add('⭐ ${tv.voteAverage.toStringAsFixed(1)}');
    }

    return Wrap(
      spacing: 12,
      children: items.map((item) => Text(
        item,
        style: TextStyle(
          fontSize: 14,
          color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
        ),
      )).toList(),
    );
  }

  Widget _buildMediaSection(String title, List<TmdbMediaItem> items, bool isDark) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 180,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return Padding(
                padding: EdgeInsets.only(right: index < items.length - 1 ? 12 : 0),
                child: _TmdbMediaCard(
                  item: item,
                  isMovie: widget.isMovie,
                  isDark: isDark,
                  onTap: () => _onMediaItemTap(item),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 24),
      ],
    );

  Future<void> _onMediaItemTap(TmdbMediaItem item) async {
    // 检查本地是否存在
    final db = VideoDatabaseService();
    final localVideo = await db.getFirstByTmdbId(item.id);

    if (!mounted) return;

    if (localVideo != null) {
      // 本地存在 - 跳转到 VideoDetailPage
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => VideoDetailPage(
            metadata: localVideo,
            sourceId: localVideo.sourceId,
          ),
        ),
      );
    } else {
      // 本地不存在 - 跳转到 TmdbPreviewPage
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => TmdbPreviewPage(
            tmdbId: item.id,
            isMovie: widget.isMovie,
            title: item.title,
            posterUrl: item.posterUrl,
            backdropUrl: item.backdropUrl,
          ),
        ),
      );
    }
  }

  String _getTitle() {
    if (_detail is TmdbMovieDetail) {
      return (_detail! as TmdbMovieDetail).title;
    } else if (_detail is TmdbTvDetail) {
      return (_detail! as TmdbTvDetail).name;
    }
    return widget.title;
  }

  String _getOverview() {
    if (_detail is TmdbMovieDetail) {
      return (_detail! as TmdbMovieDetail).overview;
    } else if (_detail is TmdbTvDetail) {
      return (_detail! as TmdbTvDetail).overview;
    }
    return '';
  }

  String? _getPosterUrl() {
    if (_detail is TmdbMovieDetail) {
      return (_detail! as TmdbMovieDetail).posterUrl;
    } else if (_detail is TmdbTvDetail) {
      return (_detail! as TmdbTvDetail).posterUrl;
    }
    return null;
  }

  String? _getBackdropUrl() {
    if (_detail is TmdbMovieDetail) {
      return (_detail! as TmdbMovieDetail).backdropUrl;
    } else if (_detail is TmdbTvDetail) {
      return (_detail! as TmdbTvDetail).backdropUrl;
    }
    return null;
  }

  /// 构建操作按钮（PT 搜索和 NASTool 订阅）
  Widget _buildActionButtons(bool isDark) {
    final ptSites = ref.watch(ptSitesSourcesProvider);
    final nastoolSources = ref.watch(nastoolSourcesProvider);

    // 如果都没有配置，不显示按钮
    if (ptSites.isEmpty && nastoolSources.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // PT 站搜索按钮
        if (ptSites.isNotEmpty)
          FilledButton.icon(
            onPressed: () => _onPtSearchPressed(ptSites),
            icon: const Icon(Icons.search_rounded, size: 18),
            label: const Text('PT 搜索'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        // NASTool 订阅按钮
        if (nastoolSources.isNotEmpty)
          FilledButton.icon(
            onPressed: () => _onNastoolSubscribePressed(nastoolSources),
            icon: const Icon(Icons.add_alert, size: 18),
            label: const Text('添加订阅'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF673AB7),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
      ],
    );
  }

  /// 处理 PT 站搜索按钮点击
  void _onPtSearchPressed(List<SourceEntity> ptSites) {
    final searchKeyword = _getTitle();

    if (ptSites.length == 1) {
      // 只有一个 PT 站，直接跳转
      _navigateToPtSite(ptSites.first, searchKeyword);
    } else {
      // 多个 PT 站，显示选择弹窗
      _showPtSiteSelectionSheet(ptSites, searchKeyword);
    }
  }

  /// 跳转到 PT 站详情页并搜索
  Future<void> _navigateToPtSite(SourceEntity source, String keyword) async {
    // 先设置搜索关键词
    ref.read(ptTorrentListProvider(source.id).notifier).setKeyword(keyword);

    // 跳转到 PT 站详情页
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => PTSiteDetailPage(source: source),
      ),
    );
  }

  /// 显示 PT 站选择弹窗
  void _showPtSiteSelectionSheet(List<SourceEntity> ptSites, String keyword) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showAdaptiveModalSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 拖动指示器
              const SheetDragHandle(topPadding: 12, bottomPadding: 12),
              // 标题
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.search_rounded,
                        color: Theme.of(context).colorScheme.primary,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '选择 PT 站',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '搜索: $keyword',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // PT 站列表
              ...ptSites.map((site) => ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: site.type.themeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    site.type.icon,
                    color: site.type.themeColor,
                    size: 20,
                  ),
                ),
                title: Text(
                  site.name.isEmpty ? site.type.displayName : site.name,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  site.host,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(context);
                  _navigateToPtSite(site, keyword);
                },
              )),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// 处理 NASTool 订阅按钮点击
  void _onNastoolSubscribePressed(List<SourceEntity> nastoolSources) {
    if (nastoolSources.length == 1) {
      // 只有一个 NASTool，直接添加订阅
      _addNastoolSubscribe(nastoolSources.first);
    } else {
      // 多个 NASTool，显示选择弹窗
      _showNastoolSelectionSheet(nastoolSources);
    }
  }

  /// 添加 NASTool 订阅
  Future<void> _addNastoolSubscribe(SourceEntity source) async {
    final title = _getTitle();
    final year = _getYear();
    final type = widget.isMovie ? 'MOV' : 'TV';
    final mediaId = 'tmdb:${widget.tmdbId}';

    try {
      // 确保 NASTool 已连接
      final connection = ref.read(nastoolConnectionProvider(source.id));
      if (connection == null || connection.status != NasToolConnectionStatus.connected) {
        if (!mounted) return;
        context.showWarningToast('${source.name} 未连接');
        return;
      }

      // 添加订阅
      await ref.read(nastoolActionsProvider(source.id)).addSubscribe(
        name: title,
        type: type,
        year: year,
        mediaId: mediaId,
      );

      if (!mounted) return;
      context.showSuccessToast('已添加订阅: $title');
    } catch (e, st) {
      AppError.handle(e, st, 'addNastoolSubscribe');
      if (!mounted) return;
      context.showErrorToast('添加订阅失败: $e');
    }
  }

  /// 获取年份
  String? _getYear() {
    if (_detail is TmdbMovieDetail) {
      final year = (_detail! as TmdbMovieDetail).year;
      return year?.toString();
    } else if (_detail is TmdbTvDetail) {
      final year = (_detail! as TmdbTvDetail).year;
      return year?.toString();
    }
    return null;
  }

  /// 显示 NASTool 选择弹窗
  void _showNastoolSelectionSheet(List<SourceEntity> nastoolSources) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = _getTitle();

    showAdaptiveModalSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 拖动指示器
              const SheetDragHandle(topPadding: 12, bottomPadding: 12),
              // 标题
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFF673AB7).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.add_alert,
                        color: Color(0xFF673AB7),
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '选择 NASTool',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '订阅: $title',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // NASTool 列表
              ...nastoolSources.map((source) => ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: source.type.themeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    source.type.icon,
                    color: source.type.themeColor,
                    size: 20,
                  ),
                ),
                title: Text(
                  source.name.isEmpty ? source.type.displayName : source.name,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  source.host,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(context);
                  _addNastoolSubscribe(source);
                },
              )),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// TMDB 媒体卡片
class _TmdbMediaCard extends StatelessWidget {
  const _TmdbMediaCard({
    required this.item,
    required this.isMovie,
    required this.isDark,
    required this.onTap,
  });

  final TmdbMediaItem item;
  final bool isMovie;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasPoster = item.posterUrl.isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 100,
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
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: hasPoster
                      ? AdaptiveImage(
                          imageUrl: item.posterUrl,
                          fit: BoxFit.cover,
                        )
                      : ColoredBox(
                          color: isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant,
                          child: Icon(
                            isMovie ? Icons.movie : Icons.tv,
                            color: isDark ? Colors.grey[600] : Colors.grey[400],
                            size: 32,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // 标题
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
