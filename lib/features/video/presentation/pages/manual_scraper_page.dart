import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/video/data/services/scraper_manager_service.dart';
import 'package:my_nas/features/video/data/services/video_metadata_service.dart';
import 'package:my_nas/features/video/domain/entities/scraper_result.dart';
import 'package:my_nas/features/video/domain/entities/scraper_source.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/features/video/presentation/providers/scrape_defaults_provider.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/shared/mixins/tab_bar_visibility_mixin.dart';
import 'package:my_nas/shared/widgets/adaptive_image.dart';
import 'package:my_nas/shared/widgets/rounded_back_button.dart';

/// 手动刮削页面
class ManualScraperPage extends ConsumerStatefulWidget {
  const ManualScraperPage({
    super.key,
    required this.metadata,
    this.fileSystem,
  });

  final VideoMetadata metadata;
  final NasFileSystem? fileSystem;

  @override
  ConsumerState<ManualScraperPage> createState() => _ManualScraperPageState();
}

class _ManualScraperPageState extends ConsumerState<ManualScraperPage>
    with ConsumerTabBarVisibilityMixin {
  final VideoMetadataService _metadataService = VideoMetadataService();
  final ScraperManagerService _scraperManager = ScraperManagerService();

  // 搜索状态
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  bool _isMovie = true;
  String? _errorMessage;

  // 电视剧特有字段
  final TextEditingController _seasonController = TextEditingController(text: '1');
  final TextEditingController _episodeController = TextEditingController(text: '1');

  // 搜索结果（按来源分组）
  Map<ScraperType, List<ScraperMediaItem>> _searchResults = {};

  // 选中的详情
  ScraperMovieDetail? _selectedMovieDetail;
  ScraperTvDetail? _selectedTvDetail;
  bool _isLoadingDetail = false;

  // 刮削选项
  bool _updateMetadata = true;
  bool _downloadPoster = true;
  bool _downloadFanart = true;
  bool _generateNfo = true;
  bool _isScraping = false;

  @override
  void initState() {
    super.initState();
    hideTabBar();
    final defaults = ref.read(scrapeDefaultsProvider);
    _generateNfo = defaults.generateNfo;
    _downloadPoster = defaults.downloadPoster;
    _downloadFanart = defaults.downloadFanart;
    _initSearchFromFileName();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _seasonController.dispose();
    _episodeController.dispose();
    super.dispose();
  }

  void _initSearchFromFileName() {
    // 解析文件名获取初始搜索关键词
    final info = VideoFileNameParser.parse(widget.metadata.fileName);
    _searchController.text = info.cleanTitle;

    // 判断是否为电视剧
    _isMovie = !info.isTvShow;

    // 设置季号和集号
    if (info.season != null) {
      _seasonController.text = info.season.toString();
    }
    if (info.episode != null) {
      _episodeController.text = info.episode.toString();
    }

    // 自动搜索
    WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _errorMessage = null;
      _searchResults.clear();
      _selectedMovieDetail = null;
      _selectedTvDetail = null;
    });

    try {
      final result = _isMovie
          ? await _scraperManager.searchMovies(query)
          : await _scraperManager.searchTvShows(query);

      // 按来源分组
      final grouped = <ScraperType, List<ScraperMediaItem>>{};
      for (final item in result.items) {
        grouped.putIfAbsent(item.source, () => []).add(item);
      }

      setState(() {
        _searchResults = grouped;
        _isSearching = false;
      });
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'ManualScraperPage._search');
      setState(() {
        _errorMessage = context.l10n.videoManualScraperSearchFailed(e);
        _isSearching = false;
      });
    }
  }

  Future<void> _selectItem(ScraperMediaItem item) async {
    setState(() {
      _isLoadingDetail = true;
      _errorMessage = null;
    });

    try {
      if (_isMovie) {
        final detail = await _scraperManager.getMovieDetail(
          externalId: item.externalId,
          source: item.source,
        );
        setState(() {
          _selectedMovieDetail = detail;
          _selectedTvDetail = null;
          _isLoadingDetail = false;
        });
      } else {
        final detail = await _scraperManager.getTvDetail(
          externalId: item.externalId,
          source: item.source,
        );
        setState(() {
          _selectedTvDetail = detail;
          _selectedMovieDetail = null;
          _isLoadingDetail = false;
        });
      }
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'ManualScraperPage._selectItem');
      setState(() {
        _errorMessage = context.l10n.videoManualScraperDetailFailed(e);
        _isLoadingDetail = false;
      });
    }
  }

  Future<void> _confirmAndScrape() async {
    if (_selectedMovieDetail == null && _selectedTvDetail == null) return;

    // 获取文件系统
    var fileSystem = widget.fileSystem;
    if (fileSystem == null) {
      final connections = ref.read(activeConnectionsProvider);
      final connection = connections[widget.metadata.sourceId];
      if (connection?.status == SourceStatus.connected) {
        fileSystem = connection!.adapter.fileSystem;
      }
    }

    setState(() => _isScraping = true);

    try {
      final options = ScrapeOptions(
        updateMetadata: _updateMetadata,
        downloadPoster: _downloadPoster,
        downloadFanart: _downloadFanart,
        generateNfo: _generateNfo,
      );

      int? seasonNum;
      int? episodeNum;
      if (!_isMovie) {
        seasonNum = int.tryParse(_seasonController.text);
        episodeNum = int.tryParse(_episodeController.text);
      }

      await _metadataService.scrapeAndSave(
        metadata: widget.metadata,
        movieDetail: _selectedMovieDetail,
        tvDetail: _selectedTvDetail,
        seasonNumber: seasonNum,
        episodeNumber: episodeNum,
        fileSystem: fileSystem,
        options: options,
      );

      if (mounted) {
        context.showSuccessToast(context.l10n.videoManualScraperSuccess);
        Navigator.pop(context, true); // 返回 true 表示已刮削
      }
    // 使用通用 catch 捕获所有类型的异常（包括 SMB 库抛出的 String 异常）
    } catch (e, st) {
      AppError.handle(e, st, 'ManualScraperPage._confirmAndScrape');
      setState(() => _isScraping = false);
      if (mounted) {
        context.showErrorToast(context.l10n.videoManualScraperError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasSelection = _selectedMovieDetail != null || _selectedTvDetail != null;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : Colors.grey[50],
      appBar: AppBar(
        leading: const RoundedBackButton(),
        title: Text(hasSelection ? context.l10n.videoManualScraperConfirmTitle : context.l10n.videoManualScraperTitle),
        backgroundColor: isDark ? AppColors.darkSurface : null,
        actions: [
          if (hasSelection)
            TextButton(
              onPressed: () {
                setState(() {
                  _selectedMovieDetail = null;
                  _selectedTvDetail = null;
                });
              },
              child: Text(context.l10n.videoManualScraperResearch),
            ),
        ],
      ),
      body: hasSelection ? _buildConfirmView(isDark) : _buildSearchView(isDark),
      bottomNavigationBar: hasSelection ? _buildBottomBar(isDark) : null,
    );
  }

  Widget _buildSearchView(bool isDark) => Column(
        children: [
          // 文件信息
          _buildFileInfo(isDark),

          // 搜索栏
          _buildSearchBar(isDark),

          // 搜索结果
          Expanded(
            child: _buildSearchResults(isDark),
          ),
        ],
      );

  Widget _buildFileInfo(bool isDark) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurfaceElevated : Colors.white,
          border: Border(
            bottom: BorderSide(
              color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
            ),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.video_file_rounded, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.metadata.fileName,
                    style: context.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.metadata.filePath,
                    style: context.textTheme.bodySmall?.copyWith(
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
      );

  Widget _buildSearchBar(bool isDark) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurfaceElevated : Colors.white,
        ),
        child: Column(
          children: [
            // 搜索框
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: context.l10n.videoManualScraperInputHint,
                      prefixIcon: const Icon(Icons.search_rounded),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _isSearching ? null : _search,
                  child: _isSearching
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(context.l10n.videoManualScraperSearchButton),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 类型选择
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(value: true, label: Text(context.l10n.videoManualScraperTypeMovie)),
                      ButtonSegment(value: false, label: Text(context.l10n.videoManualScraperTypeTV)),
                    ],
                    selected: {_isMovie},
                    onSelectionChanged: (value) {
                      setState(() => _isMovie = value.first);
                      _search();
                    },
                  ),
                ),
              ],
            ),

            // 电视剧季/集输入
            if (!_isMovie) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _seasonController,
                      decoration: InputDecoration(
                        labelText: context.l10n.videoManualScraperSeasonLabel,
                        prefixIcon: Icon(Icons.folder_outlined),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _episodeController,
                      decoration: InputDecoration(
                        labelText: context.l10n.videoManualScraperEpisodeLabel,
                        prefixIcon: Icon(Icons.play_circle_outline),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      );

  Widget _buildSearchResults(bool isDark) {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: TextStyle(color: AppColors.error)),
          ],
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              context.l10n.videoManualScraperNoResults,
              style: context.textTheme.titleMedium?.copyWith(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.videoManualScraperTryOtherKeywords,
              style: context.textTheme.bodyMedium?.copyWith(
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final entry = _searchResults.entries.elementAt(index);
        return _buildSourceGroup(entry.key, entry.value, isDark);
      },
    );
  }

  Widget _buildSourceGroup(
    ScraperType source,
    List<ScraperMediaItem> items,
    bool isDark,
  ) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 来源标题
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getSourceColor(source).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    source.displayName,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _getSourceColor(source),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  context.l10n.videoManualScraperResultCount(items.length),
                  style: context.textTheme.bodySmall?.copyWith(
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),

          // 结果列表
          ...items.map((item) => _buildSearchResultItem(item, isDark)),

          const SizedBox(height: 16),
        ],
      );

  Widget _buildSearchResultItem(ScraperMediaItem item, bool isDark) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        color: isDark ? AppColors.darkSurfaceElevated : null,
        child: InkWell(
          onTap: _isLoadingDetail ? null : () => _selectItem(item),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // 海报
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    width: 50,
                    height: 75,
                    child: item.posterUrl != null
                        ? AdaptiveImage(
                            imageUrl: item.posterUrl!,
                            fit: BoxFit.cover,
                          )
                        : ColoredBox(
                            color: isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant,
                            child: const Icon(Icons.movie),
                          ),
                  ),
                ),
                const SizedBox(width: 12),

                // 信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: context.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (item.originalTitle != null &&
                          item.originalTitle != item.title) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.originalTitle!,
                          style: context.textTheme.bodySmall?.copyWith(
                            color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (item.year != null) ...[
                            Text(
                              '${item.year}',
                              style: context.textTheme.bodySmall,
                            ),
                            const SizedBox(width: 8),
                          ],
                          if (item.rating != null && item.rating! > 0) ...[
                            const Icon(Icons.star_rounded, size: 14, color: Colors.amber),
                            const SizedBox(width: 2),
                            Text(
                              item.rating!.toStringAsFixed(1),
                              style: context.textTheme.bodySmall,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                // 箭头
                if (_isLoadingDetail)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      );

  Widget _buildConfirmView(bool isDark) {
    final detail = _selectedMovieDetail ?? _selectedTvDetail;
    if (detail == null) return const SizedBox.shrink();

    final title = _selectedMovieDetail?.title ?? _selectedTvDetail?.title ?? '';
    final originalTitle =
        _selectedMovieDetail?.originalTitle ?? _selectedTvDetail?.originalTitle;
    final year = _selectedMovieDetail?.year ?? _selectedTvDetail?.year;
    final rating = _selectedMovieDetail?.rating ?? _selectedTvDetail?.rating;
    final overview =
        _selectedMovieDetail?.overview ?? _selectedTvDetail?.overview;
    final posterUrl =
        _selectedMovieDetail?.posterUrl ?? _selectedTvDetail?.posterUrl;
    final genres = _selectedMovieDetail?.genres ?? _selectedTvDetail?.genres;
    final source = _selectedMovieDetail?.source ?? _selectedTvDetail?.source;
    final runtime =
        _selectedMovieDetail?.runtime ?? _selectedTvDetail?.episodeRuntime;
    final director = _selectedMovieDetail?.director;
    final cast = _selectedMovieDetail?.cast ?? _selectedTvDetail?.cast;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 海报和基本信息
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 120,
                  height: 180,
                  child: posterUrl != null
                      ? AdaptiveImage(
                          imageUrl: posterUrl,
                          fit: BoxFit.cover,
                        )
                      : ColoredBox(
                          color: isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant,
                          child: const Icon(Icons.movie, size: 48),
                        ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: context.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (originalTitle != null && originalTitle != title) ...[
                      const SizedBox(height: 4),
                      Text(
                        originalTitle,
                        style: context.textTheme.titleMedium?.copyWith(
                          color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (year != null) ...[
                          Text('$year', style: context.textTheme.bodyMedium),
                          const SizedBox(width: 12),
                        ],
                        if (rating != null && rating > 0) ...[
                          const Icon(Icons.star_rounded, size: 18, color: Colors.amber),
                          const SizedBox(width: 4),
                          Text(
                            rating.toStringAsFixed(1),
                            style: context.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        if (runtime != null && runtime > 0) ...[
                          Text(
                            context.l10n.videoManualScraperRuntime(runtime),
                            style: context.textTheme.bodyMedium,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _getSourceColor(source!).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        source.displayName,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _getSourceColor(source),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 类型
          if (genres != null && genres.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: genres
                  .map(
                    (g) => Chip(
                      label: Text(g, style: const TextStyle(fontSize: 12)),
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),
          ],

          // 简介
          if (overview != null && overview.isNotEmpty) ...[
            Text(
              context.l10n.videoManualScraperSummary,
              style: context.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              overview,
              style: context.textTheme.bodyMedium?.copyWith(
                color: isDark ? Colors.grey[300] : Colors.grey[700],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // 导演/演员
          if (director != null && director.isNotEmpty) ...[
            Text(
              context.l10n.videoManualScraperDirector(director),
              style: context.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
          ],
          if (cast != null && cast.isNotEmpty) ...[
            Text(
              context.l10n.videoManualScraperCast(cast.take(5).join(', ')),
              style: context.textTheme.bodyMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
          ],

          // 刮削选项
          Card(
            color: isDark ? AppColors.darkSurfaceElevated : null,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.videoManualScraperOptions,
                    style: context.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: Text(context.l10n.videoManualScraperUpdateMetadata),
                    subtitle: Text(context.l10n.videoManualScraperUpdateMetadataDesc),
                    value: _updateMetadata,
                    onChanged: (v) => setState(() => _updateMetadata = v),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  SwitchListTile(
                    title: Text(context.l10n.videoManualScraperDownloadPoster),
                    subtitle: Text(context.l10n.videoManualScraperDownloadPosterDesc),
                    value: _downloadPoster,
                    onChanged: (v) => setState(() => _downloadPoster = v),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  SwitchListTile(
                    title: Text(context.l10n.videoManualScraperDownloadFanart),
                    subtitle: Text(context.l10n.videoManualScraperDownloadFanartDesc),
                    value: _downloadFanart,
                    onChanged: (v) => setState(() => _downloadFanart = v),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  SwitchListTile(
                    title: Text(context.l10n.videoManualScraperGenerateNfo),
                    subtitle: Text(context.l10n.videoManualScraperGenerateNfoDesc),
                    value: _generateNfo,
                    onChanged: (v) => setState(() => _generateNfo = v),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),

          // 底部间距
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildBottomBar(bool isDark) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Row(
            children: [
              // 返回按钮 - 圆形图标按钮
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                    width: 1.5,
                  ),
                ),
                child: IconButton(
                  onPressed: _isScraping
                      ? null
                      : () {
                          setState(() {
                            _selectedMovieDetail = null;
                            _selectedTvDetail = null;
                          });
                        },
                  icon: const Icon(Icons.arrow_back_rounded),
                  tooltip: context.l10n.videoManualScraperBackToSearch,
                ),
              ),
              const SizedBox(width: 16),
              // 确认按钮 - 大按钮
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: _isScraping ? null : _confirmAndScrape,
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _isScraping
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(context.l10n.videoManualScraperScraping),
                            ],
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check_rounded, size: 22),
                              const SizedBox(width: 8),
                              Text(
                                context.l10n.videoManualScraperConfirm,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Color _getSourceColor(ScraperType source) => switch (source) {
        ScraperType.tmdb => Colors.blue,
        ScraperType.doubanApi => Colors.green,
        ScraperType.doubanWeb => Colors.orange,
      };
}
