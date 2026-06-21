import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/music/data/services/play_history_store.dart';
import 'package:my_nas/shared/widgets/rounded_back_button.dart';

/// 听歌统计页 — 周/月/年的听歌总览 + Top 歌曲/艺术家/专辑
class ListeningStatsPage extends ConsumerStatefulWidget {
  const ListeningStatsPage({super.key});

  @override
  ConsumerState<ListeningStatsPage> createState() =>
      _ListeningStatsPageState();
}

class _ListeningStatsPageState extends ConsumerState<ListeningStatsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController =
      TabController(length: 3, vsync: this);

  PlayHistoryRange _range = PlayHistoryRange.week;
  Future<void>? _initFuture;

  @override
  void initState() {
    super.initState();
    _initFuture = PlayHistoryStore.instance.init();
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      setState(() {
        _range = PlayHistoryRange.values[_tabController.index];
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : null,
      appBar: AppBar(
        leading: const RoundedBackButton(),
        backgroundColor: isDark ? AppColors.darkSurface : null,
        title: Text(
          context.l10n.listeningStatsPageTitle,
          style: TextStyle(
            color: isDark ? AppColors.darkOnSurface : null,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: IconThemeData(
          color: isDark ? AppColors.darkOnSurface : null,
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: context.l10n.listeningStatsTabWeek),
            Tab(text: context.l10n.listeningStatsTabMonth),
            Tab(text: context.l10n.listeningStatsTabYear),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: context.l10n.listeningStatsClearHistoryTooltip,
            onPressed: _confirmClear,
          ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _initFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return _buildBody(isDark);
        },
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    final store = PlayHistoryStore.instance;
    final summary = store.summary(_range);
    final topSongs = store.topSongs(_range);
    final topArtists = store.topArtists(_range);
    final topAlbums = store.topAlbums(_range);
    final daily = store.dailyPlayCounts(_range);

    if (summary.totalPlays == 0) {
      return Center(
        child: Padding(
          padding: AppSpacing.paddingLg,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.bar_chart_rounded,
                size: 64,
                color: isDark ? Colors.white24 : Colors.black26,
              ),
              const SizedBox(height: 12),
              Text(
                context.l10n.listeningStatsEmptyTitle,
                style: TextStyle(
                  fontSize: 16,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                context.l10n.listeningStatsEmptyHint,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: AppSpacing.paddingMd,
      children: [
        _SummaryCard(summary: summary, isDark: isDark),
        const SizedBox(height: AppSpacing.lg),
        _Heatmap(daily: daily, isDark: isDark),
        const SizedBox(height: AppSpacing.lg),
        _RankSection(
          title: context.l10n.listeningStatsRankSectionSongs,
          icon: Icons.music_note_rounded,
          items: topSongs,
          isDark: isDark,
        ),
        const SizedBox(height: AppSpacing.lg),
        _RankSection(
          title: context.l10n.listeningStatsRankSectionArtists,
          icon: Icons.person_rounded,
          items: topArtists,
          isDark: isDark,
        ),
        const SizedBox(height: AppSpacing.lg),
        _RankSection(
          title: context.l10n.listeningStatsRankSectionAlbums,
          icon: Icons.album_rounded,
          items: topAlbums,
          isDark: isDark,
        ),
      ],
    );
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.listeningStatsDialogTitle),
        content: Text(ctx.l10n.listeningStatsDialogContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.listeningStatsDialogCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.l10n.listeningStatsDialogConfirm),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await PlayHistoryStore.instance.clearAll();
    if (mounted) setState(() {});
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary, required this.isDark});
  final PlayHistorySummary summary;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final hours = summary.totalSec / 3600;
    return Container(
      padding: AppSpacing.paddingLg,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withValues(alpha: 0.18),
            AppColors.secondary.withValues(alpha: 0.12),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SummaryCell(
              value: summary.totalPlays.toString(),
              label: context.l10n.listeningStatsSummaryCellPlays,
              isDark: isDark,
            ),
          ),
          Expanded(
            child: _SummaryCell(
              value: hours >= 10
                  ? hours.toStringAsFixed(0)
                  : hours.toStringAsFixed(1),
              label: context.l10n.listeningStatsSummaryCellHours,
              isDark: isDark,
            ),
          ),
          Expanded(
            child: _SummaryCell(
              value: summary.uniqueSongs.toString(),
              label: context.l10n.listeningStatsSummaryCellUniqueSongs,
              isDark: isDark,
            ),
          ),
          Expanded(
            child: _SummaryCell(
              value: summary.activeDays.toString(),
              label: context.l10n.listeningStatsSummaryCellActiveDays,
              isDark: isDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCell extends StatelessWidget {
  const _SummaryCell({
    required this.value,
    required this.label,
    required this.isDark,
  });
  final String value;
  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
        ],
      );
}

/// 简易 7 列热力图。每一格 = 当天播放数；颜色越深次数越多。
class _Heatmap extends StatelessWidget {
  const _Heatmap({required this.daily, required this.isDark});
  final List<({DateTime date, int count})> daily;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    if (daily.isEmpty) return const SizedBox.shrink();
    final maxCount =
        daily.map((d) => d.count).fold<int>(0, (a, b) => a > b ? a : b);
    return Container(
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.listeningStatsHeatmapTitle,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final day in daily)
                _HeatmapCell(
                  count: day.count,
                  maxCount: maxCount,
                  isDark: isDark,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeatmapCell extends StatelessWidget {
  const _HeatmapCell({
    required this.count,
    required this.maxCount,
    required this.isDark,
  });
  final int count;
  final int maxCount;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final intensity =
        maxCount == 0 ? 0.0 : (count / maxCount).clamp(0.0, 1.0);
    final base = AppColors.primary;
    final color = count == 0
        ? (isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.05))
        : base.withValues(alpha: 0.2 + intensity * 0.7);
    return SizedBox(
      width: 14,
      height: 14,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}

class _RankSection extends StatelessWidget {
  const _RankSection({
    required this.title,
    required this.icon,
    required this.items,
    required this.isDark,
  });

  final String title;
  final IconData icon;
  final List<RankedItem> items;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: AppSpacing.paddingMd,
            child: Row(
              children: [
                Icon(icon, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < items.length; i++)
            _RankRow(
              rank: i + 1,
              item: items[i],
              isDark: isDark,
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.rank,
    required this.item,
    required this.isDark,
  });
  final int rank;
  final RankedItem item;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final rankColor = rank <= 3
        ? [Colors.amber, Colors.grey, Colors.brown][rank - 1]
        : (isDark ? Colors.white38 : Colors.black38);
    final minutes = (item.totalSec / 60).round();
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 6,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '$rank',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: rankColor,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                if (item.subtitle.isNotEmpty)
                  Text(
                    item.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            context.l10n.listeningStatsRankRowPlayCount(item.playCount),
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${minutes}m',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
        ],
      ),
    );
  }
}
