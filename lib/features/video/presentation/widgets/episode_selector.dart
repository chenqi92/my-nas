import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/video/data/services/tmdb_service.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/features/video/presentation/providers/video_detail_provider.dart';
import 'package:my_nas/features/video/presentation/widgets/episode_card.dart';

/// 剧集选择器组件
class EpisodeSelector extends ConsumerStatefulWidget {
  const EpisodeSelector({
    required this.tvId,
    required this.seasons,
    required this.onEpisodePlay,
    this.initialSeason,
    this.localEpisodes = const {},
    this.episodeProgress = const {},
    super.key,
  });

  final int tvId;
  final List<TmdbSeason> seasons;
  final void Function(TmdbEpisode episode, VideoMetadata? localFile) onEpisodePlay;
  final int? initialSeason;
  /// 本地可用的剧集文件 `Map<seasonNumber, Map<episodeNumber, VideoMetadata>>`
  final Map<int, Map<int, VideoMetadata>> localEpisodes;
  /// 剧集播放进度 `Map<filePath, progress 0.0-1.0>`
  final Map<String, double> episodeProgress;

  @override
  ConsumerState<EpisodeSelector> createState() => _EpisodeSelectorState();
}

class _EpisodeSelectorState extends ConsumerState<EpisodeSelector> {
  late int _selectedSeason;

  @override
  void initState() {
    super.initState();
    // 默认选中第一个非特别篇的季
    _selectedSeason = widget.initialSeason ??
        widget.seasons.where((s) => s.seasonNumber > 0).firstOrNull?.seasonNumber ??
        widget.seasons.firstOrNull?.seasonNumber ??
        1;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 过滤掉没有剧集的季 (seasonNumber = 0 通常是特别篇)
    final displaySeasons = widget.seasons.where((s) => s.episodeCount > 0).toList();

    if (displaySeasons.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题和季选择器
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                context.l10n.videoEpisodeSelectorTitle,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                ),
              ),
              const Spacer(),
              // 季选择下拉框
              _buildSeasonDropdown(displaySeasons, isDark),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 剧集列表
        _buildEpisodeList(isDark),
      ],
    );
  }

  Widget _buildSeasonDropdown(List<TmdbSeason> seasons, bool isDark) => Container(
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
            final localEpisodesCount = widget.localEpisodes[season.seasonNumber]?.length ?? 0;
            return DropdownMenuItem(
              value: season.seasonNumber,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    season.seasonNumber == 0 ? context.l10n.videoEpisodeSelectorSpecialSeason : context.l10n.videoEpisodeSelectorSeasonLabel(season.seasonNumber),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    localEpisodesCount > 0
                        ? context.l10n.videoEpisodeSelectorCountBoth(localEpisodesCount, season.episodeCount)
                        : context.l10n.videoEpisodeSelectorCountTmdb(season.episodeCount),
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
    // 获取当前季的剧集详情
    final seasonDetailAsync = ref.watch(
      seasonDetailProvider((tvId: widget.tvId, seasonNumber: _selectedSeason)),
    );

    return seasonDetailAsync.when(
      loading: () => const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => SizedBox(
        height: 100,
        child: Center(
          child: Text(
            context.l10n.videoEpisodeSelectorLoadFailed,
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
                context.l10n.videoEpisodeSelectorEmpty,
                style: TextStyle(
                  color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                ),
              ),
            ),
          );
        }

        final episodes = seasonDetail.episodes;
        final localSeasonEpisodes = widget.localEpisodes[_selectedSeason] ?? {};

        return SizedBox(
          height: 240, // 卡片高度
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: episodes.length,
            itemBuilder: (context, index) {
              final episode = episodes[index];
              final localFile = localSeasonEpisodes[episode.episodeNumber];
              final isAvailable = localFile != null;
              final progress = localFile != null
                  ? widget.episodeProgress[localFile.filePath]
                  : null;

              return Padding(
                padding: EdgeInsets.only(
                  right: index < episodes.length - 1 ? 16 : 0,
                ),
                child: EpisodeCard(
                  episode: episode,
                  isAvailable: isAvailable,
                  watchProgress: progress,
                  onTap: () => widget.onEpisodePlay(episode, localFile),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// 本地剧集选择器（无 TMDB 数据时使用）
///
/// 基于本地元数据的 seasonNumber 和 episodeNumber 显示剧集
class LocalEpisodeSelector extends StatefulWidget {
  const LocalEpisodeSelector({
    required this.episodes,
    required this.onEpisodePlay,
    this.initialSeason,
    this.episodeProgress = const {},
    super.key,
  });

  /// 剧集映射 `Map<seasonNumber, Map<episodeNumber, VideoMetadata>>`
  final Map<int, Map<int, VideoMetadata>> episodes;
  final void Function(VideoMetadata episode) onEpisodePlay;
  final int? initialSeason;
  /// 剧集播放进度 `Map<filePath, progress 0.0-1.0>`
  final Map<String, double> episodeProgress;

  @override
  State<LocalEpisodeSelector> createState() => _LocalEpisodeSelectorState();
}

class _LocalEpisodeSelectorState extends State<LocalEpisodeSelector> {
  late int _selectedSeason;

  @override
  void initState() {
    super.initState();
    // 默认选中第一个非特别篇的季
    final seasons = widget.episodes.keys.toList()..sort();
    _selectedSeason = widget.initialSeason ??
        seasons.where((s) => s > 0).firstOrNull ??
        seasons.firstOrNull ??
        1;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 按季号排序
    final seasons = widget.episodes.keys.toList()..sort();
    if (seasons.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题和季选择器
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                context.l10n.videoEpisodeSelectorTitle,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                ),
              ),
              const Spacer(),
              // 季选择下拉框
              _buildSeasonDropdown(seasons, isDark),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 剧集列表
        _buildEpisodeList(isDark),
      ],
    );
  }

  Widget _buildSeasonDropdown(List<int> seasons, bool isDark) => Container(
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
          items: seasons.map((seasonNum) {
            final episodeCount = widget.episodes[seasonNum]?.length ?? 0;
            return DropdownMenuItem(
              value: seasonNum,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    seasonNum == 0 ? context.l10n.videoEpisodeSelectorSpecialSeason : context.l10n.videoEpisodeSelectorSeasonLabel(seasonNum),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    context.l10n.videoEpisodeSelectorCountLocal(episodeCount),
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
    final seasonEpisodes = widget.episodes[_selectedSeason] ?? {};
    if (seasonEpisodes.isEmpty) {
      return SizedBox(
        height: 100,
        child: Center(
          child: Text(
            context.l10n.videoEpisodeSelectorEmpty,
            style: TextStyle(
              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
            ),
          ),
        ),
      );
    }

    // 按集号排序
    final episodeNumbers = seasonEpisodes.keys.toList()..sort();

    return SizedBox(
      height: 120,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: episodeNumbers.length,
        itemBuilder: (context, index) {
          final episodeNum = episodeNumbers[index];
          final episode = seasonEpisodes[episodeNum]!;
          final progress = widget.episodeProgress[episode.filePath];

          return Padding(
            padding: EdgeInsets.only(
              right: index < episodeNumbers.length - 1 ? 12 : 0,
            ),
            child: _LocalEpisodeCard(
              episode: episode,
              watchProgress: progress,
              onTap: () => widget.onEpisodePlay(episode),
            ),
          );
        },
      ),
    );
  }
}

/// 本地剧集卡片（简化版，无 TMDB 剧集图片）
class _LocalEpisodeCard extends StatelessWidget {
  const _LocalEpisodeCard({
    required this.episode,
    required this.onTap,
    this.watchProgress,
  });

  final VideoMetadata episode;
  final VoidCallback onTap;
  final double? watchProgress;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isWatched = watchProgress != null && watchProgress! > 0.9;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140,
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurfaceVariant : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? AppColors.darkOutline : Colors.grey[300]!,
          ),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 集号标题区域
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isWatched
                    ? AppColors.primary.withValues(alpha: 0.1)
                    : (isDark ? AppColors.darkSurface : Colors.grey[50]),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
              ),
              child: Row(
                children: [
                  // 集号
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      context.l10n.videoEpisodeSelectorEpisodeLabel(episode.episodeNumber ?? 0),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const Spacer(),
                  // 已观看图标
                  if (isWatched)
                    Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: AppColors.primary,
                    ),
                ],
              ),
            ),
            // 集标题
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      episode.episodeTitle ?? episode.fileName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                      ),
                    ),
                    // 播放进度
                    if (watchProgress != null && watchProgress! > 0 && !isWatched) ...[
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: watchProgress,
                          minHeight: 3,
                          backgroundColor: isDark ? AppColors.darkOutline : AppColors.lightOutline,
                          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 紧凑版剧集选择器 (垂直列表)
class CompactEpisodeSelector extends ConsumerStatefulWidget {
  const CompactEpisodeSelector({
    required this.tvId,
    required this.seasons,
    required this.onEpisodePlay,
    this.initialSeason,
    this.localEpisodes = const {},
    this.episodeProgress = const {},
    super.key,
  });

  final int tvId;
  final List<TmdbSeason> seasons;
  final void Function(TmdbEpisode episode, VideoMetadata? localFile) onEpisodePlay;
  final int? initialSeason;
  final Map<int, Map<int, VideoMetadata>> localEpisodes;
  final Map<String, double> episodeProgress;

  @override
  ConsumerState<CompactEpisodeSelector> createState() => _CompactEpisodeSelectorState();
}

class _CompactEpisodeSelectorState extends ConsumerState<CompactEpisodeSelector> {
  late int _selectedSeason;
  bool _showAllEpisodes = false;

  @override
  void initState() {
    super.initState();
    _selectedSeason = widget.initialSeason ??
        widget.seasons.where((s) => s.seasonNumber > 0).firstOrNull?.seasonNumber ??
        1;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displaySeasons = widget.seasons.where((s) => s.episodeCount > 0).toList();

    if (displaySeasons.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 季选择标签
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: displaySeasons.map((season) {
              final isSelected = season.seasonNumber == _selectedSeason;
              final localCount = widget.localEpisodes[season.seasonNumber]?.length ?? 0;

              return GestureDetector(
                onTap: () => setState(() {
                  _selectedSeason = season.seasonNumber;
                  _showAllEpisodes = false;
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary
                        : (isDark ? AppColors.darkSurfaceVariant : Colors.grey[100]),
                    borderRadius: BorderRadius.circular(20),
                    border: isSelected
                        ? null
                        : Border.all(
                            color: isDark ? AppColors.darkOutline : Colors.grey[300]!,
                          ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        season.seasonNumber == 0 ? context.l10n.videoEpisodeSelectorSpecialSeason : context.l10n.videoEpisodeSelectorSeasonLabel(season.seasonNumber),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? Colors.white
                              : (isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface),
                        ),
                      ),
                      if (localCount > 0) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.white.withValues(alpha: 0.2)
                                : AppColors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$localCount',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isSelected ? Colors.white : AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),
        // 剧集列表
        _buildCompactEpisodeList(isDark),
      ],
    );
  }

  Widget _buildCompactEpisodeList(bool isDark) {
    final seasonDetailAsync = ref.watch(
      seasonDetailProvider((tvId: widget.tvId, seasonNumber: _selectedSeason)),
    );

    return seasonDetailAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            context.l10n.videoEpisodeSelectorLoadFailed,
            style: TextStyle(
              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
            ),
          ),
        ),
      ),
      data: (seasonDetail) {
        if (seasonDetail == null || seasonDetail.episodes.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Text(
                context.l10n.videoEpisodeSelectorEmpty,
                style: TextStyle(
                  color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                ),
              ),
            ),
          );
        }

        final episodes = seasonDetail.episodes;
        final localSeasonEpisodes = widget.localEpisodes[_selectedSeason] ?? {};
        final displayCount = _showAllEpisodes ? episodes.length : 5.clamp(0, episodes.length);

        return Column(
          children: [
            // 剧集列表
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: displayCount,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                color: isDark ? AppColors.darkOutline : Colors.grey[200],
              ),
              itemBuilder: (context, index) {
                final episode = episodes[index];
                final localFile = localSeasonEpisodes[episode.episodeNumber];
                final isAvailable = localFile != null;
                final progress = localFile != null
                    ? widget.episodeProgress[localFile.filePath]
                    : null;

                return CompactEpisodeCard(
                  episode: episode,
                  isAvailable: isAvailable,
                  watchProgress: progress,
                  onTap: () => widget.onEpisodePlay(episode, localFile),
                );
              },
            ),
            // 展开/收起按钮
            if (episodes.length > 5)
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextButton(
                  onPressed: () => setState(() => _showAllEpisodes = !_showAllEpisodes),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _showAllEpisodes ? context.l10n.videoEpisodeSelectorCollapse : context.l10n.videoEpisodeSelectorExpandAll(episodes.length),
                        style: TextStyle(color: AppColors.primary),
                      ),
                      Icon(
                        _showAllEpisodes
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
