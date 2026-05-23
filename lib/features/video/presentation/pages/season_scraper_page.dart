import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/video/data/services/scraper_manager_service.dart';
import 'package:my_nas/features/video/data/services/video_metadata_service.dart';
import 'package:my_nas/features/video/domain/entities/scraper_result.dart';
import 'package:my_nas/features/video/domain/entities/scraper_source.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/features/video/presentation/providers/scraper_provider.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/shared/mixins/tab_bar_visibility_mixin.dart';
import 'package:my_nas/shared/widgets/adaptive_image.dart';
import 'package:my_nas/shared/widgets/rounded_back_button.dart';

/// 整剧刮削页面
/// 批量刮削电视剧的所有季
class SeasonScraperPage extends ConsumerStatefulWidget {
  const SeasonScraperPage({
    super.key,
    required this.showDirectory,
    required this.sourceId,
    this.tmdbId,
    this.fileSystem,
    this.initialSeasonNumber,
  });

  /// 电视剧目录
  final String showDirectory;

  /// 来源 ID
  final String sourceId;

  /// TMDB ID（如果已有）
  final int? tmdbId;

  /// 文件系统
  final NasFileSystem? fileSystem;

  /// 初始选中的季号（用于预选）
  final int? initialSeasonNumber;

  @override
  ConsumerState<SeasonScraperPage> createState() => _SeasonScraperPageState();
}

class _SeasonScraperPageState extends ConsumerState<SeasonScraperPage>
    with ConsumerTabBarVisibilityMixin {
  final VideoMetadataService _metadataService = VideoMetadataService();
  final ScraperManagerService _scraperManager = ScraperManagerService();

  // 本地剧集
  Map<int, Map<int, VideoMetadata>> _localEpisodes = {};

  // 搜索状态
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  Map<ScraperType, List<ScraperMediaItem>> _searchResults = {};
  String? _errorMessage;

  // 选中的电视剧
  ScraperTvDetail? _selectedTvDetail;
  bool _isLoadingDetail = false;

  // 季选择 - 支持多选
  Set<int> _selectedSeasons = {};
  final Map<int, ScraperSeasonDetail> _seasonDetails = {};
  bool _isLoadingSeasonDetails = false;

  // 刮削选项
  bool _updateMetadata = true;
  bool _downloadPoster = true;
  bool _downloadFanart = true;
  bool _generateNfo = true;

  @override
  void initState() {
    super.initState();
    hideTabBar();
    _loadLocalEpisodes();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadLocalEpisodes() async {
    await _metadataService.init();
    final episodes = await _metadataService.getEpisodesByShowDirectory(widget.showDirectory);
    setState(() {
      _localEpisodes = episodes;
      // 默认选中所有季
      _selectedSeasons = episodes.keys.toSet();
    });

    // 从第一个剧集提取搜索关键词
    if (episodes.isNotEmpty) {
      final firstSeason = episodes.values.first;
      if (firstSeason.isNotEmpty) {
        final firstEpisode = firstSeason.values.first;
        // 使用剧集的 title 或从文件名解析
        final info = VideoFileNameParser.parse(firstEpisode.fileName);
        _searchController.text = firstEpisode.title ?? info.cleanTitle;

        // 如果有 tmdbId 则直接加载详情
        if (widget.tmdbId != null) {
          AppError.fireAndForget(
            _loadTvDetailByTmdbId(widget.tmdbId!),
            action: 'SeasonScraperPage._loadTvDetailByTmdbId',
          );
        } else {
          // 自动搜索
          WidgetsBinding.instance.addPostFrameCallback((_) => _search());
        }
      }
    }
  }

  Future<void> _loadTvDetailByTmdbId(int tmdbId) async {
    setState(() {
      _isLoadingDetail = true;
      _errorMessage = null;
    });

    try {
      final detail = await _scraperManager.getTvDetail(
        externalId: tmdbId.toString(),
        source: ScraperType.tmdb,
      );

      if (detail != null) {
        setState(() {
          _selectedTvDetail = detail;
          _isLoadingDetail = false;
        });
        // 加载所有选中季的详情
        await _loadAllSeasonDetails();
      } else {
        setState(() {
          _isLoadingDetail = false;
        });
      }
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'SeasonScraperPage._loadTvDetailByTmdbId');
      setState(() {
        _errorMessage = '获取详情失败: $e';
        _isLoadingDetail = false;
      });
    }
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _errorMessage = null;
      _searchResults.clear();
      _selectedTvDetail = null;
      _seasonDetails.clear();
    });

    try {
      final result = await _scraperManager.searchTvShows(query);

      final grouped = <ScraperType, List<ScraperMediaItem>>{};
      for (final item in result.items) {
        grouped.putIfAbsent(item.source, () => []).add(item);
      }

      setState(() {
        _searchResults = grouped;
        _isSearching = false;
      });
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'SeasonScraperPage._search');
      setState(() {
        _errorMessage = '搜索失败: $e';
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
      final detail = await _scraperManager.getTvDetail(
        externalId: item.externalId,
        source: item.source,
      );
      setState(() {
        _selectedTvDetail = detail;
        _isLoadingDetail = false;
      });
      // 加载所有选中季的详情
      await _loadAllSeasonDetails();
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'SeasonScraperPage._selectItem');
      setState(() {
        _errorMessage = '获取详情失败: $e';
        _isLoadingDetail = false;
      });
    }
  }

  /// 加载所有选中季的详情
  Future<void> _loadAllSeasonDetails() async {
    final tvDetail = _selectedTvDetail;
    if (tvDetail == null || _selectedSeasons.isEmpty) return;

    setState(() {
      _isLoadingSeasonDetails = true;
      _seasonDetails.clear();
    });

    try {
      for (final seasonNumber in _selectedSeasons) {
        final detail = await _scraperManager.getSeasonDetail(
          tvId: tvDetail.externalId,
          seasonNumber: seasonNumber,
          source: tvDetail.source,
        );
        if (detail != null) {
          _seasonDetails[seasonNumber] = detail;
        }
      }
      setState(() {
        _isLoadingSeasonDetails = false;
      });
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'SeasonScraperPage._loadAllSeasonDetails');
      setState(() {
        _isLoadingSeasonDetails = false;
      });
    }
  }

  /// 加载单个季的详情
  Future<void> _loadSeasonDetailForSeason(int seasonNumber) async {
    final tvDetail = _selectedTvDetail;
    if (tvDetail == null) return;
    if (_seasonDetails.containsKey(seasonNumber)) return; // 已加载

    try {
      final detail = await _scraperManager.getSeasonDetail(
        tvId: tvDetail.externalId,
        seasonNumber: seasonNumber,
        source: tvDetail.source,
      );
      if (detail != null && mounted) {
        setState(() {
          _seasonDetails[seasonNumber] = detail;
        });
      }
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'SeasonScraperPage._loadSeasonDetailForSeason');
    }
  }

  /// 计算所有选中季的总集数
  int get _totalSelectedEpisodes {
    var total = 0;
    for (final season in _selectedSeasons) {
      total += _localEpisodes[season]?.length ?? 0;
    }
    return total;
  }

  Future<void> _startScraping() async {
    final tvDetail = _selectedTvDetail;
    if (tvDetail == null || _selectedSeasons.isEmpty) return;

    final totalEpisodes = _totalSelectedEpisodes;
    if (totalEpisodes == 0) {
      context.showInfoToast('没有本地剧集可刮削');
      return;
    }

    final options = ScrapeOptions(
      updateMetadata: _updateMetadata,
      downloadPoster: _downloadPoster,
      downloadFanart: _downloadFanart,
      generateNfo: _generateNfo,
    );

    // 使用后台刮削管理器启动刮削
    final started = await ref.read(backgroundScrapingProvider.notifier).startTvShowScraping(
      showDirectory: widget.showDirectory,
      tvDetail: tvDetail,
      selectedSeasons: _selectedSeasons,
      localEpisodes: _localEpisodes,
      seasonDetails: _seasonDetails,
      fileSystem: widget.fileSystem,
      options: options,
    );

    if (started && mounted) {
      // 显示提示并返回详情页
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text('正在后台刮削 $totalEpisodes 集...')),
            ],
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tvDetail = _selectedTvDetail;
    final hasSelection = tvDetail != null;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : Colors.grey[50],
      appBar: AppBar(
        leading: const RoundedBackButton(),
        title: Text(hasSelection ? '整剧刮削' : '选择电视剧'),
        backgroundColor: isDark ? AppColors.darkSurface : null,
        actions: [
          if (hasSelection)
            TextButton(
              onPressed: () {
                setState(() {
                  _selectedTvDetail = null;
                  _seasonDetails.clear();
                });
              },
              child: const Text('重新搜索'),
            ),
        ],
      ),
      body: hasSelection
          ? _buildSeasonView(isDark, tvDetail)
          : _buildSearchView(isDark),
      bottomNavigationBar: hasSelection
          ? _buildBottomBar(isDark)
          : null,
    );
  }

  Widget _buildSearchView(bool isDark) => Column(
        children: [
          // 本地剧集统计
          _buildLocalEpisodesInfo(isDark),

          // 搜索栏
          _buildSearchBar(isDark),

          // 搜索结果
          Expanded(
            child: _buildSearchResults(isDark),
          ),
        ],
      );

  Widget _buildLocalEpisodesInfo(bool isDark) {
    final totalEpisodes = _localEpisodes.values
        .fold<int>(0, (sum, season) => sum + season.length);

    return Container(
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
          Icon(
            Icons.folder_special_rounded,
            size: 40,
            color: AppColors.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '本地剧集',
                  style: context.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '共 ${_localEpisodes.length} 季，$totalEpisodes 集',
                  style: context.textTheme.bodySmall?.copyWith(
                    color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(bool isDark) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurfaceElevated : Colors.white,
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: '搜索电视剧',
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
                  : const Text('搜索'),
            ),
          ],
        ),
      );

  Widget _buildSearchResults(bool isDark) {
    if (_isSearching || _isLoadingDetail) {
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
              '搜索电视剧以开始刮削',
              style: context.textTheme.titleMedium?.copyWith(
                color: Colors.grey[600],
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
                  '${items.length} 个结果',
                  style: context.textTheme.bodySmall?.copyWith(
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
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
                        : Container(
                            color: isDark ? Colors.grey[800] : Colors.grey[200],
                            child: const Icon(Icons.tv),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
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
                            Text('${item.year}', style: context.textTheme.bodySmall),
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
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      );

  Widget _buildSeasonView(bool isDark, ScraperTvDetail tvDetail) {
    final availableSeasons = _localEpisodes.keys.toList()..sort();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 电视剧信息
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 100,
                  height: 150,
                  child: tvDetail.posterUrl != null
                      ? AdaptiveImage(
                          imageUrl: tvDetail.posterUrl!,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          color: isDark ? Colors.grey[800] : Colors.grey[200],
                          child: const Icon(Icons.tv, size: 48),
                        ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tvDetail.title,
                      style: context.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (tvDetail.originalTitle != null &&
                        tvDetail.originalTitle != tvDetail.title) ...[
                      const SizedBox(height: 4),
                      Text(
                        tvDetail.originalTitle!,
                        style: context.textTheme.titleMedium?.copyWith(
                          color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (tvDetail.year != null) ...[
                          Text('${tvDetail.year}', style: context.textTheme.bodyMedium),
                          const SizedBox(width: 12),
                        ],
                        if (tvDetail.rating != null && tvDetail.rating! > 0) ...[
                          const Icon(Icons.star_rounded, size: 18, color: Colors.amber),
                          const SizedBox(width: 4),
                          Text(
                            tvDetail.rating!.toStringAsFixed(1),
                            style: context.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getSourceColor(tvDetail.source).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        tvDetail.source.displayName,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _getSourceColor(tvDetail.source),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 季选择
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '选择要刮削的季',
                style: context.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _selectedSeasons = availableSeasons.toSet();
                      });
                      _loadAllSeasonDetails();
                    },
                    child: const Text('全选'),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _selectedSeasons.clear();
                        _seasonDetails.clear();
                      });
                    },
                    child: const Text('全不选'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: availableSeasons.map((season) {
              final episodeCount = _localEpisodes[season]?.length ?? 0;
              final isSelected = _selectedSeasons.contains(season);

              return FilterChip(
                label: Text('第 $season 季 ($episodeCount 集)'),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedSeasons.add(season);
                    } else {
                      _selectedSeasons.remove(season);
                      _seasonDetails.remove(season);
                    }
                  });
                  if (selected) {
                    _loadSeasonDetailForSeason(season);
                  }
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 24),

          // 剧集匹配预览
          _buildEpisodeMatchPreview(isDark),
          const SizedBox(height: 24),

          // 刮削选项
          _buildScrapeOptions(isDark),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildEpisodeMatchPreview(bool isDark) {
    if (_selectedSeasons.isEmpty) {
      return Card(
        color: isDark ? AppColors.darkSurfaceElevated : null,
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Text('请选择要刮削的季'),
        ),
      );
    }

    final sortedSeasons = _selectedSeasons.toList()..sort();

    return Card(
      color: isDark ? AppColors.darkSurfaceElevated : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.compare_arrows, size: 20),
                const SizedBox(width: 8),
                Text(
                  '剧集匹配预览',
                  style: context.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '共 $_totalSelectedEpisodes 集',
                  style: context.textTheme.bodySmall?.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_isLoadingSeasonDetails)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              )
            else
              ...sortedSeasons.expand((seasonNumber) {
                final localSeasonEpisodes = _localEpisodes[seasonNumber] ?? {};
                final seasonDetail = _seasonDetails[seasonNumber];

                if (localSeasonEpisodes.isEmpty) return <Widget>[];

                return [
                  // 季标题
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Text(
                      '第 $seasonNumber 季 (${localSeasonEpisodes.length} 集)',
                      style: context.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  // 剧集列表
                  ...localSeasonEpisodes.entries.map((entry) {
                    final episodeNumber = entry.key;
                    final metadata = entry.value;
                    final scraperEpisode = seasonDetail?.getEpisode(episodeNumber);
                    final hasMatch = scraperEpisode != null;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Icon(
                            hasMatch ? Icons.check_circle : Icons.help_outline_rounded,
                            size: 16,
                            color: hasMatch ? AppColors.success : AppColors.warning,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'E$episodeNumber: ${metadata.fileName}',
                              style: context.textTheme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ];
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildScrapeOptions(bool isDark) => Card(
        color: isDark ? AppColors.darkSurfaceElevated : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '刮削选项',
                style: context.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('更新元数据'),
                subtitle: const Text('保存到本地数据库'),
                value: _updateMetadata,
                onChanged: (v) => setState(() => _updateMetadata = v),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile(
                title: const Text('下载海报'),
                subtitle: const Text('保存到视频目录'),
                value: _downloadPoster,
                onChanged: (v) => setState(() => _downloadPoster = v),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile(
                title: const Text('下载背景图'),
                subtitle: const Text('保存到视频目录'),
                value: _downloadFanart,
                onChanged: (v) => setState(() => _downloadFanart = v),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile(
                title: const Text('生成 NFO 文件'),
                subtitle: const Text('Kodi/Jellyfin 兼容格式'),
                value: _generateNfo,
                onChanged: (v) => setState(() => _generateNfo = v),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      );

  Widget _buildBottomBar(bool isDark) {
    final totalEpisodes = _totalSelectedEpisodes;
    final seasonCount = _selectedSeasons.length;

    return Container(
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
                onPressed: () {
                  setState(() {
                    _selectedTvDetail = null;
                    _seasonDetails.clear();
                  });
                },
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: '返回搜索',
              ),
            ),
            const SizedBox(width: 16),
            // 确认按钮 - 大按钮
            Expanded(
              child: SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: totalEpisodes == 0 ? null : _startScraping,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.auto_fix_high_rounded, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        seasonCount > 1
                            ? '刮削 $seasonCount 季共 $totalEpisodes 集'
                            : '刮削 $totalEpisodes 集',
                        style: const TextStyle(
                          fontSize: 15,
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
  }

  Color _getSourceColor(ScraperType source) => switch (source) {
        ScraperType.tmdb => Colors.blue,
        ScraperType.doubanApi => Colors.green,
        ScraperType.doubanWeb => Colors.orange,
      };
}
