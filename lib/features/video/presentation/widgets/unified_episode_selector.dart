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
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/features/video/presentation/providers/video_detail_provider.dart';
import 'package:my_nas/shared/widgets/adaptive_image.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';

/// 统一剧集选择器
///
/// 智能判断数据来源：
/// - 有 TMDB ID：从 TMDB 获取剧集详情（图片、标题、简介等）
/// - 无 TMDB ID：使用本地元数据，尝试显示本地缩略图
class UnifiedEpisodeSelector extends ConsumerStatefulWidget {
  const UnifiedEpisodeSelector({
    required this.localEpisodes,
    required this.onEpisodePlay,
    this.tmdbId,
    this.tmdbSeasons,
    this.initialSeason,
    this.episodeProgress = const {},
    this.showName,
    this.year,
    super.key,
  });

  /// TMDB ID（如果有）
  final int? tmdbId;

  /// TMDB 季信息（如果有）
  final List<TmdbSeason>? tmdbSeasons;

  /// 本地剧集 `Map<seasonNumber, Map<episodeNumber, VideoMetadata>>`
  final Map<int, Map<int, VideoMetadata>> localEpisodes;

  /// 剧集播放回调
  final void Function(VideoMetadata localFile, {TmdbEpisode? tmdbEpisode}) onEpisodePlay;

  /// 初始选中的季
  final int? initialSeason;

  /// 剧集播放进度 `Map<filePath, progress 0.0-1.0>`
  final Map<String, double> episodeProgress;

  /// 剧集名称（用于 PT 搜索和订阅）
  final String? showName;

  /// 年份（用于订阅）
  final String? year;

  @override
  ConsumerState<UnifiedEpisodeSelector> createState() => _UnifiedEpisodeSelectorState();
}

class _UnifiedEpisodeSelectorState extends ConsumerState<UnifiedEpisodeSelector> {
  late int _selectedSeason;

  bool get _hasTmdb => widget.tmdbId != null && widget.tmdbSeasons != null;

  @override
  void initState() {
    super.initState();
    _initSelectedSeason();
  }

  void _initSelectedSeason() {
    if (widget.initialSeason != null) {
      _selectedSeason = widget.initialSeason!;
      return;
    }

    // 优先从本地剧集中选择第一个非特别篇的季
    final localSeasons = widget.localEpisodes.keys.toList()..sort();
    final nonSpecialSeason = localSeasons.where((s) => s > 0).firstOrNull;
    if (nonSpecialSeason != null) {
      _selectedSeason = nonSpecialSeason;
      return;
    }

    // 从 TMDB 季中选择
    if (_hasTmdb) {
      final tmdbSeason = widget.tmdbSeasons!
          .where((s) => s.seasonNumber > 0 && s.episodeCount > 0)
          .firstOrNull;
      if (tmdbSeason != null) {
        _selectedSeason = tmdbSeason.seasonNumber;
        return;
      }
    }

    _selectedSeason = localSeasons.firstOrNull ?? 1;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 获取可用的季列表
    final availableSeasons = _getAvailableSeasons();
    if (availableSeasons.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题和季选择器
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                '剧集',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                ),
              ),
              const Spacer(),
              _buildSeasonDropdown(availableSeasons, isDark),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 剧集列表
        _buildEpisodeList(isDark),
      ],
    );
  }

  /// 获取可用的季列表（合并 TMDB 和本地数据）
  List<_SeasonInfo> _getAvailableSeasons() {
    final seasons = <int, _SeasonInfo>{};

    // 添加本地季
    for (final entry in widget.localEpisodes.entries) {
      seasons[entry.key] = _SeasonInfo(
        seasonNumber: entry.key,
        localEpisodeCount: entry.value.length,
        tmdbEpisodeCount: 0,
      );
    }

    // 合并 TMDB 季信息
    if (_hasTmdb) {
      for (final tmdbSeason in widget.tmdbSeasons!) {
        if (tmdbSeason.episodeCount > 0) {
          final existing = seasons[tmdbSeason.seasonNumber];
          if (existing != null) {
            seasons[tmdbSeason.seasonNumber] = existing.copyWith(
              tmdbEpisodeCount: tmdbSeason.episodeCount,
            );
          } else {
            seasons[tmdbSeason.seasonNumber] = _SeasonInfo(
              seasonNumber: tmdbSeason.seasonNumber,
              localEpisodeCount: 0,
              tmdbEpisodeCount: tmdbSeason.episodeCount,
            );
          }
        }
      }
    }

    final result = seasons.values.toList()
      ..sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
    return result;
  }

  Widget _buildSeasonDropdown(List<_SeasonInfo> seasons, bool isDark) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurfaceVariant : Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDark ? AppColors.darkOutline : Colors.grey[300]!,
          ),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: _selectedSeason,
            isDense: true,
            icon: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
            ),
            dropdownColor: isDark ? AppColors.darkSurface : Colors.white,
            items: seasons.map((season) {
              final label = season.seasonNumber == 0 ? '特别篇' : '第${season.seasonNumber}季';
              final countText = _hasTmdb
                  ? '(${season.localEpisodeCount}/${season.tmdbEpisodeCount}集)'
                  : '(${season.localEpisodeCount}集)';

              return DropdownMenuItem(
                value: season.seasonNumber,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      countText,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? AppColors.darkOnSurfaceVariant
                            : AppColors.lightOnSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedSeason = value);
              }
            },
          ),
        ),
      );

  Widget _buildEpisodeList(bool isDark) {
    if (_hasTmdb) {
      return _buildTmdbEpisodeList(isDark);
    }
    return _buildLocalEpisodeList(isDark);
  }

  /// 使用 TMDB 数据构建剧集列表
  ///
  /// 优先显示本地剧集，异步加载 TMDB 数据来增强显示（封面、评分等）
  /// 这样即使网络不好，用户也能立即看到和播放剧集
  Widget _buildTmdbEpisodeList(bool isDark) {
    final localSeasonEpisodes = widget.localEpisodes[_selectedSeason] ?? {};

    // 如果没有本地剧集，显示空状态（不等待 TMDB）
    if (localSeasonEpisodes.isEmpty) {
      // 但仍尝试从 TMDB 获取剧集信息（可能显示"无资源"的剧集）
      final seasonDetailAsync = ref.watch(
        seasonDetailProvider((tvId: widget.tmdbId!, seasonNumber: _selectedSeason)),
      );

      return seasonDetailAsync.when(
        loading: () => const SizedBox(
          height: 130,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (_, _) => SizedBox(
          height: 100,
          child: Center(
            child: Text(
              '暂无剧集',
              style: TextStyle(
                color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
              ),
            ),
          ),
        ),
        data: (seasonDetail) {
          if (seasonDetail == null || seasonDetail.episodes.isEmpty) {
            return SizedBox(
              height: 100,
              child: Center(
                child: Text(
                  '暂无剧集',
                  style: TextStyle(
                    color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                  ),
                ),
              ),
            );
          }
          // 显示 TMDB 剧集（都是"无资源"状态）
          return _buildEpisodeListView(
            seasonDetail.episodes,
            localSeasonEpisodes,
            isDark,
          );
        },
      );
    }

    // 有本地剧集：先立即显示本地数据，同时异步加载 TMDB 数据增强
    final seasonDetailAsync = ref.watch(
      seasonDetailProvider((tvId: widget.tmdbId!, seasonNumber: _selectedSeason)),
    );

    return seasonDetailAsync.when(
      // 加载中：立即显示本地剧集（不阻塞）
      loading: () => _buildLocalOnlyEpisodeList(localSeasonEpisodes, isDark),
      // 加载失败：使用本地数据
      error: (_, _) => _buildLocalOnlyEpisodeList(localSeasonEpisodes, isDark),
      // 加载成功：合并 TMDB 和本地数据
      data: (seasonDetail) {
        if (seasonDetail == null || seasonDetail.episodes.isEmpty) {
          return _buildLocalOnlyEpisodeList(localSeasonEpisodes, isDark);
        }
        return _buildEpisodeListView(
          seasonDetail.episodes,
          localSeasonEpisodes,
          isDark,
        );
      },
    );
  }

  /// 构建仅使用本地数据的剧集列表
  Widget _buildLocalOnlyEpisodeList(Map<int, VideoMetadata> localEpisodes, bool isDark) {
    final episodeNumbers = localEpisodes.keys.toList()..sort();

    return SizedBox(
      height: 130,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: episodeNumbers.length,
        itemBuilder: (context, index) {
          final episodeNum = episodeNumbers[index];
          final episode = localEpisodes[episodeNum]!;
          final progress = widget.episodeProgress[episode.filePath];
          final thumbnailUrl = episode.posterUrl ?? episode.backdropUrl;

          return Padding(
            padding: EdgeInsets.only(right: index < episodeNumbers.length - 1 ? 12 : 0),
            child: _UnifiedEpisodeCard(
              episodeNumber: episodeNum,
              title: episode.episodeTitle ?? episode.fileName,
              imageUrl: thumbnailUrl,
              isAvailable: true,
              isLoading: true, // 显示加载指示器
              watchProgress: progress,
              onTap: () => widget.onEpisodePlay(episode),
            ),
          );
        },
      ),
    );
  }

  /// 构建合并了 TMDB 数据的剧集列表视图
  Widget _buildEpisodeListView(
    List<TmdbEpisode> tmdbEpisodes,
    Map<int, VideoMetadata> localEpisodes,
    bool isDark,
  ) => SizedBox(
      height: 130,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: tmdbEpisodes.length,
        itemBuilder: (context, index) {
          final tmdbEpisode = tmdbEpisodes[index];
          final localFile = localEpisodes[tmdbEpisode.episodeNumber];
          final isAvailable = localFile != null;
          final progress = localFile != null
              ? widget.episodeProgress[localFile.filePath]
              : null;

          final onTapCallback = localFile != null
              ? () => widget.onEpisodePlay(localFile, tmdbEpisode: tmdbEpisode)
              : null;

          // 缺失剧集点击回调
          final onMissingTapCallback = localFile == null
              ? () => _showMissingEpisodeActions(
                    context,
                    tmdbEpisode,
                    _selectedSeason,
                  )
              : null;

          return Padding(
            padding: EdgeInsets.only(right: index < tmdbEpisodes.length - 1 ? 12 : 0),
            child: _UnifiedEpisodeCard(
              episodeNumber: tmdbEpisode.episodeNumber,
              title: tmdbEpisode.name,
              imageUrl: tmdbEpisode.stillUrl,
              runtime: tmdbEpisode.runtime,
              airDate: tmdbEpisode.airDate,
              rating: tmdbEpisode.voteAverage,
              isAvailable: isAvailable,
              watchProgress: progress,
              onTap: onTapCallback,
              onMissingTap: onMissingTapCallback,
            ),
          );
        },
      ),
    );

  /// 显示缺失剧集的操作选项
  void _showMissingEpisodeActions(
    BuildContext context,
    TmdbEpisode episode,
    int seasonNumber,
  ) {
    final ptSites = ref.read(ptSitesSourcesProvider);
    final nastoolSources = ref.read(nastoolSourcesProvider);

    // 如果没有配置任何服务，显示提示
    if (ptSites.isEmpty && nastoolSources.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先配置 PT 站点或 NASTool 服务'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    showAdaptiveModalSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _MissingEpisodeActionSheet(
        showName: widget.showName ?? '',
        year: widget.year,
        tmdbId: widget.tmdbId,
        seasonNumber: seasonNumber,
        episodeNumber: episode.episodeNumber,
        episodeName: episode.name,
        ptSites: ptSites,
        nastoolSources: nastoolSources,
      ),
    );
  }

  /// 使用本地数据构建剧集列表
  Widget _buildLocalEpisodeList(bool isDark) {
    final seasonEpisodes = widget.localEpisodes[_selectedSeason] ?? {};
    if (seasonEpisodes.isEmpty) {
      return SizedBox(
        height: 100,
        child: Center(
          child: Text(
            '暂无剧集',
            style: TextStyle(
              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final episodeNumbers = seasonEpisodes.keys.toList()..sort();

    return SizedBox(
      height: 130,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: episodeNumbers.length,
        itemBuilder: (context, index) {
          final episodeNum = episodeNumbers[index];
          final episode = seasonEpisodes[episodeNum]!;
          final progress = widget.episodeProgress[episode.filePath];

          // 尝试获取本地缩略图
          final thumbnailUrl = episode.posterUrl ?? episode.backdropUrl;

          return Padding(
            padding: EdgeInsets.only(right: index < episodeNumbers.length - 1 ? 12 : 0),
            child: _UnifiedEpisodeCard(
              episodeNumber: episodeNum,
              title: episode.episodeTitle ?? episode.fileName,
              imageUrl: thumbnailUrl,
              isAvailable: true,
              watchProgress: progress,
              onTap: () => widget.onEpisodePlay(episode),
            ),
          );
        },
      ),
    );
  }
}

/// 季信息
class _SeasonInfo {
  const _SeasonInfo({
    required this.seasonNumber,
    required this.localEpisodeCount,
    required this.tmdbEpisodeCount,
  });

  final int seasonNumber;
  final int localEpisodeCount;
  final int tmdbEpisodeCount;

  _SeasonInfo copyWith({
    int? seasonNumber,
    int? localEpisodeCount,
    int? tmdbEpisodeCount,
  }) =>
      _SeasonInfo(
        seasonNumber: seasonNumber ?? this.seasonNumber,
        localEpisodeCount: localEpisodeCount ?? this.localEpisodeCount,
        tmdbEpisodeCount: tmdbEpisodeCount ?? this.tmdbEpisodeCount,
      );
}

/// 统一的剧集卡片
class _UnifiedEpisodeCard extends StatefulWidget {
  const _UnifiedEpisodeCard({
    required this.episodeNumber,
    required this.title,
    this.imageUrl,
    this.runtime,
    this.airDate,
    this.rating,
    this.isAvailable = false,
    this.isLoading = false,
    this.watchProgress,
    this.onTap,
    this.onMissingTap,
  });

  final int episodeNumber;
  final String title;
  final String? imageUrl;
  final int? runtime;
  final String? airDate;
  final double? rating;
  final bool isAvailable;

  /// 是否正在加载 TMDB 数据（显示加载指示器）
  final bool isLoading;
  final double? watchProgress;
  final VoidCallback? onTap;

  /// 缺失剧集点击回调（用于 PT 搜索/订阅）
  final VoidCallback? onMissingTap;
  static const double width = 160;

  @override
  State<_UnifiedEpisodeCard> createState() => _UnifiedEpisodeCardState();
}

class _UnifiedEpisodeCardState extends State<_UnifiedEpisodeCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasImage = widget.imageUrl != null && widget.imageUrl!.isNotEmpty;
    const aspectRatio = 16 / 9;
    const cardWidth = _UnifiedEpisodeCard.width;
    const imageHeight = cardWidth / aspectRatio;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.isAvailable ? widget.onTap : widget.onMissingTap,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: widget.isAvailable ? 1.0 : 0.5,
          child: SizedBox(
            width: cardWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 缩略图区域
                Stack(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: _isHovered ? 0.2 : 0.1),
                            blurRadius: _isHovered ? 8 : 4,
                            offset: Offset(0, _isHovered ? 3 : 1),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: cardWidth,
                          height: imageHeight,
                          child: hasImage
                              ? AdaptiveImage(
                                  imageUrl: widget.imageUrl!,
                                  placeholder: (_) => _buildPlaceholder(isDark),
                                  errorWidget: (_, _) => _buildPlaceholder(isDark),
                                )
                              : _buildPlaceholder(isDark),
                        ),
                      ),
                    ),
                    // 播放图标
                    if (widget.isAvailable && _isHovered)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.black.withValues(alpha: 0.4),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.play_circle_fill_rounded,
                              size: 40,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    // 时长标签
                    if (widget.runtime != null && widget.runtime! > 0)
                      Positioned(
                        right: 6,
                        bottom: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _formatRuntime(widget.runtime!),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    // 不可用标签
                    if (!widget.isAvailable)
                      Positioned(
                        left: 6,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '无资源',
                            style: TextStyle(color: Colors.white70, fontSize: 10),
                          ),
                        ),
                      ),
                    // TMDB 数据加载中指示器
                    if (widget.isLoading)
                      Positioned(
                        right: 6,
                        top: 6,
                        child: Container(
                          width: 16,
                          height: 16,
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const CircularProgressIndicator(
                            strokeWidth: 1.5,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                          ),
                        ),
                      ),
                    // 进度条（放在图片底部）
                    if (widget.watchProgress != null && widget.watchProgress! > 0)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                          child: LinearProgressIndicator(
                            value: widget.watchProgress!.clamp(0.0, 1.0),
                            minHeight: 3,
                            backgroundColor: Colors.black.withValues(alpha: 0.3),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              widget.watchProgress! >= 0.9 ? AppColors.success : AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                // 简洁的标题：集数.名称
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${widget.episodeNumber}. ${widget.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                    ),
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
            size: 32,
            color: isDark ? Colors.grey[600] : Colors.grey[400],
          ),
        ),
      );

  String _formatRuntime(int minutes) {
    if (minutes < 60) return '$minutes分钟';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return mins > 0 ? '$hours小时$mins分钟' : '$hours小时';
  }
}

/// 缺失剧集操作选项底部弹窗
class _MissingEpisodeActionSheet extends ConsumerWidget {
  const _MissingEpisodeActionSheet({
    required this.showName,
    required this.year,
    required this.tmdbId,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.episodeName,
    required this.ptSites,
    required this.nastoolSources,
  });

  final String showName;
  final String? year;
  final int? tmdbId;
  final int seasonNumber;
  final int episodeNumber;
  final String episodeName;
  final List<SourceEntity> ptSites;
  final List<SourceEntity> nastoolSources;

  String get _searchKeyword => showName.isNotEmpty
      ? '$showName S${seasonNumber.toString().padLeft(2, '0')}E${episodeNumber.toString().padLeft(2, '0')}'
      : episodeName;

  String get _displayTitle => showName.isNotEmpty
      ? '$showName 第$seasonNumber季第$episodeNumber集'
      : '第$episodeNumber集';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 拖动指示器
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[600] : Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // 标题
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.cloud_off_rounded,
                      color: AppColors.warning,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '缺失剧集',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _displayTitle,
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
            // 操作选项
            if (ptSites.isNotEmpty)
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.search_rounded,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                ),
                title: const Text(
                  '在 PT 站搜索',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  '搜索 "$_searchKeyword"',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(context);
                  _onPtSearch(context, ref);
                },
              ),
            if (nastoolSources.isNotEmpty)
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF673AB7).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.add_alert,
                    color: Color(0xFF673AB7),
                    size: 20,
                  ),
                ),
                title: const Text(
                  '添加 NASTool 订阅',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  '订阅整季: $showName 第$seasonNumber季',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(context);
                  _onNastoolSubscribe(context, ref);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _onPtSearch(BuildContext context, WidgetRef ref) {
    if (ptSites.length == 1) {
      _navigateToPtSite(context, ref, ptSites.first);
    } else {
      _showPtSiteSelection(context, ref);
    }
  }

  void _navigateToPtSite(BuildContext context, WidgetRef ref, SourceEntity source) {
    ref.read(ptTorrentListProvider(source.id).notifier).setKeyword(_searchKeyword);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => PTSiteDetailPage(source: source),
      ),
    );
  }

  void _showPtSiteSelection(BuildContext context, WidgetRef ref) {
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
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[600] : Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
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
                            '搜索: $_searchKeyword',
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
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(context);
                  _navigateToPtSite(context, ref, site);
                },
              )),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _onNastoolSubscribe(BuildContext context, WidgetRef ref) {
    if (nastoolSources.length == 1) {
      _addNastoolSubscribe(context, ref, nastoolSources.first);
    } else {
      _showNastoolSelection(context, ref);
    }
  }

  Future<void> _addNastoolSubscribe(BuildContext context, WidgetRef ref, SourceEntity source) async {
    try {
      final connection = ref.read(nastoolConnectionProvider(source.id));
      if (connection == null || connection.status != NasToolConnectionStatus.connected) {
        context.showWarningToast('${source.name} 未连接');
        return;
      }

      // NASTool 订阅整季
      await ref.read(nastoolActionsProvider(source.id)).addSubscribe(
        name: showName,
        type: 'TV',
        year: year,
        season: seasonNumber,
        mediaId: tmdbId != null ? 'tmdb:$tmdbId' : null,
      );

      if (context.mounted) {
        context.showSuccessToast('已添加订阅: $showName 第$seasonNumber季');
      }
    } catch (e, st) {
      AppError.handle(e, st, 'addNastoolSubscribeForEpisode');
      if (context.mounted) {
        context.showErrorToast('添加订阅失败: $e');
      }
    }
  }

  void _showNastoolSelection(BuildContext context, WidgetRef ref) {
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
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[600] : Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
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
                            '订阅: $showName 第$seasonNumber季',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.grey[400] : Colors.grey[600],
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
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(context);
                  _addNastoolSubscribe(context, ref, source);
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
