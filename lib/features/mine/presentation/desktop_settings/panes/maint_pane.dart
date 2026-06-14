import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/music/data/services/play_history_store.dart';
import 'package:my_nas/features/music/data/services/playlist_service.dart';
import 'package:my_nas/features/music/presentation/pages/duplicate_songs_page.dart';
import 'package:my_nas/features/music/presentation/pages/listening_stats_page.dart';
import 'package:my_nas/features/music/presentation/pages/recycle_bin_page.dart';
import 'package:my_nas/features/photo/presentation/pages/photo_duplicates_page.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/shared/widgets/atoms/app_button.dart';
import 'package:my_nas/shared/widgets/atoms/app_segmented.dart';
import 'package:my_nas/shared/widgets/atoms/settings_atoms.dart';

/// 桌面「维护与统计」设置 pane。
///
/// 对齐设计稿 `settings_panes.jsx · PaneMaint`：听歌统计（kv-strip + 活跃热力图
/// + Top 排行）+ 库维护（重复检测 / 回收站）。
///
/// 听歌统计直接读 [PlayHistoryStore]（本地播放历史聚合）的真实数据：周/月/年切换、
/// 摘要四项、按天热力图。回收站行内显示待恢复项数量（[PlaylistService] 软删除记录，
/// 小 box 低成本计数）。Top 排行 / 重复检测 / 回收站用按钮打开现有功能页保留完整能力。
/// 重复检测无低成本计数 provider（需全表扫描 + 内存分组），仅保留按钮。
class MaintPane extends ConsumerStatefulWidget {
  const MaintPane({super.key});

  @override
  ConsumerState<MaintPane> createState() => _MaintPaneState();
}

class _MaintPaneState extends ConsumerState<MaintPane> {
  PlayHistoryRange _range = PlayHistoryRange.month;
  Future<void>? _initFuture;
  int? _recycleCount;

  @override
  void initState() {
    super.initState();
    _initFuture = PlayHistoryStore.instance.init();
    _loadRecycleCount();
  }

  Future<void> _loadRecycleCount() async {
    final deleted = await PlaylistService().getDeletedPlaylists();
    if (mounted) setState(() => _recycleCount = deleted.length);
  }

  Future<void> _openRecycleBin() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const RecycleBinPage()),
    );
    // 回到 pane 后刷新计数（页面里可能恢复 / 永久删除了项目）
    await _loadRecycleCount();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SetHead(
        icon: Icons.document_scanner_outlined,
        title: l.paneMaintTitle,
        subtitle: l.paneMaintSubtitle,
        actions: [
          AppSegmented<PlayHistoryRange>(
            dense: true,
            options: [
              AppSegmentedOption(
                value: PlayHistoryRange.week,
                label: l.paneMaintRangeWeek,
              ),
              AppSegmentedOption(
                value: PlayHistoryRange.month,
                label: l.paneMaintRangeMonth,
              ),
              AppSegmentedOption(
                value: PlayHistoryRange.year,
                label: l.paneMaintRangeYear,
              ),
            ],
            value: _range,
            onChanged: (v) => setState(() => _range = v),
          ),
        ],
      ),

      // 听歌统计
      SetSection(
        title: l.paneMaintStatsSection,
        hint: 'music_play_history',
        children: [
          FutureBuilder<void>(
            future: _initFuture,
            builder: (context, snapshot) {
              final ready = snapshot.connectionState == ConnectionState.done;
              final store = PlayHistoryStore.instance;
              final summary = ready
                  ? store.summary(_range)
                  : PlayHistorySummary.empty;
              final daily = ready
                  ? store.dailyPlayCounts(_range)
                  : const <({DateTime date, int count})>[];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: _KvStrip(summary: summary),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: DesignTokens.of(context).hairline,
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _Heatmap(daily: daily),
                    ),
                  ),
                ],
              );
            },
          ),
          SetRow(
            title: l.paneMaintTopChartTitle,
            desc: l.paneMaintTopChartDesc,
            trailing: AppButton(
              label: l.paneMaintTopChartButton,
              icon: Icons.leaderboard_outlined,
              dense: true,
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const ListeningStatsPage()),
              ),
            ),
          ),
          SetRow(
            title: l.paneMaintYearReportTitle,
            desc: l.paneMaintYearReportDesc,
            last: true,
            trailing: AppButton(
              label: l.paneMaintYearReportButton,
              icon: Icons.auto_awesome_outlined,
              dense: true,
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const _YearReportDialog(),
              ),
            ),
          ),
        ],
      ),

      // 库维护
      SetSection(
        title: l.paneMaintLibrarySection,
        hint: l.paneMaintLibrarySectionHint,
        bottomMargin: false,
        children: [
          SetRow(
            title: l.paneMaintDuplicateTitle,
            desc: l.paneMaintDuplicateDesc,
            trailing: AppButton(
              label: l.paneMaintDuplicateButton,
              icon: Icons.content_copy_outlined,
              dense: true,
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const DuplicateSongsPage()),
              ),
            ),
          ),
          SetRow(
            title: l.maintPhotoTitle,
            desc: l.maintPhotoDesc,
            trailing: AppButton(
              label: l.maintPhotoButton,
              icon: Icons.photo_library_outlined,
              dense: true,
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const PhotoDuplicatesPage()),
              ),
            ),
          ),
          SetRow(
            title: l.paneMaintRecycleBinTitle,
            desc: l.paneMaintRecycleBinDesc,
            last: true,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_recycleCount != null && _recycleCount! > 0) ...[
                  Text(
                    l.paneMaintRecycleBinCount(_recycleCount!),
                    style: TextStyle(
                      fontSize: 12,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: DesignTokens.of(context).text2,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                AppButton(
                  label: l.paneMaintRecycleBinButton,
                  icon: Icons.restore_from_trash_outlined,
                  dense: true,
                  onPressed: _openRecycleBin,
                ),
              ],
            ),
          ),
        ],
      ),
    ],
    );
  }
}

/// 设计稿 `.kv-strip`：摘要四宫格（播放次数 / 总时长 / 活跃天 / 不重复曲目）。
class _KvStrip extends StatelessWidget {
  const _KvStrip({required this.summary});

  final PlayHistorySummary summary;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final hours = summary.totalSec / 3600;
    final hoursLabel = hours >= 10
        ? '${hours.toStringAsFixed(0)} h'
        : '${hours.toStringAsFixed(1)} h';
    final cells = <(String, String)>[
      (summary.totalPlays.toString(), l.paneMaintKvPlays),
      (hoursLabel, l.paneMaintKvDuration),
      (summary.activeDays.toString(), l.paneMaintKvActiveDays),
      (summary.uniqueSongs.toString(), l.paneMaintKvUniqueSongs),
    ];
    return Row(
      children: [
        for (final (value, label) in cells)
          Expanded(
            child: _KvCell(value: value, label: label),
          ),
      ],
    );
  }
}

class _KvCell extends StatelessWidget {
  const _KvCell({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: t.text0,
          ),
        ),
        const SizedBox(height: 3),
        Text(label, style: TextStyle(fontSize: 11.5, color: t.text2)),
      ],
    );
  }
}

/// 设计稿 `.heat-grid`：近 N 周活跃热力图。每格 = 当天播放数，颜色越深次数越多。
class _Heatmap extends StatelessWidget {
  const _Heatmap({required this.daily});

  final List<({DateTime date, int count})> daily;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    final maxCount = daily.fold<int>(0, (a, d) => d.count > a ? d.count : a);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 9),
          child: Text(
            daily.isEmpty
                ? l.paneMaintHeatmapTitle
                : l.paneMaintHeatmapTitleDays(daily.length),
            style: TextStyle(fontSize: 11, color: t.text3),
          ),
        ),
        if (daily.isEmpty)
          Text(
            l.paneMaintHeatmapEmpty,
            style: TextStyle(fontSize: 12, color: t.text2),
          )
        else
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final day in daily)
                _HeatCell(color: _level(t, day.count, maxCount)),
            ],
          ),
      ],
    );
  }

  Color _level(DesignTokens t, int count, int maxCount) {
    if (count == 0 || maxCount == 0) return t.insetBg;
    final ratio = (count / maxCount).clamp(0.0, 1.0);
    if (ratio < 0.34) return t.accent.withValues(alpha: 0.3);
    if (ratio < 0.67) return t.accent.withValues(alpha: 0.55);
    return t.accent;
  }
}

class _HeatCell extends StatelessWidget {
  const _HeatCell({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 13,
    height: 13,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
    ),
  );
}

/// 年度听歌报告 — 全部数据取自 [PlayHistoryStore]（近一年范围）。
///
/// 摘要四项与 Top 排行复用 store 已有聚合 API；「最活跃月份」额外按月份桶统计
/// [PlayHistoryStore.entriesIn] 的播放数。无新增持久化字段、无新业务逻辑，仅做
/// 只读展示。
class _YearReportDialog extends StatelessWidget {
  const _YearReportDialog();

  /// 找出近一年播放次数最多的月份；无数据返回 null。
  ({String label, int count})? _topMonth(AppLocalizations l) {
    final entries = PlayHistoryStore.instance.entriesIn(PlayHistoryRange.year);
    if (entries.isEmpty) return null;
    final buckets = <int, int>{}; // year*100 + month -> count
    for (final e in entries) {
      final key = e.playedAt.year * 100 + e.playedAt.month;
      buckets[key] = (buckets[key] ?? 0) + 1;
    }
    var bestKey = buckets.keys.first;
    var bestCount = buckets[bestKey]!;
    buckets.forEach((k, v) {
      if (v > bestCount) {
        bestKey = k;
        bestCount = v;
      }
    });
    final year = bestKey ~/ 100;
    final month = bestKey % 100;
    return (label: l.paneMaintYearMonthLabel(year, month), count: bestCount);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    final store = PlayHistoryStore.instance;
    final summary = store.summary(PlayHistoryRange.year);

    if (summary.totalPlays == 0) {
      return AlertDialog(
        title: Text(l.paneMaintYearReportTitle),
        content: Text(
          l.paneMaintYearReportEmpty,
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l.paneMaintYearReportGotIt),
          ),
        ],
      );
    }

    final hours = summary.totalSec / 3600;
    final hoursLabel = hours >= 10
        ? '${hours.toStringAsFixed(0)} h'
        : '${hours.toStringAsFixed(1)} h';
    final topSongs = store.topSongs(PlayHistoryRange.year, limit: 1);
    final topArtists = store.topArtists(PlayHistoryRange.year, limit: 1);
    final topAlbums = store.topAlbums(PlayHistoryRange.year, limit: 1);
    final topMonth = _topMonth(l);

    final summaryCells = <(String, String)>[
      (summary.totalPlays.toString(), l.paneMaintKvPlays),
      (hoursLabel, l.paneMaintKvDuration),
      (summary.activeDays.toString(), l.paneMaintKvActiveDays),
      (summary.uniqueSongs.toString(), l.paneMaintKvUniqueSongs),
    ];

    return AlertDialog(
      title: Text(l.paneMaintYearReportTitle),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.paneMaintYearReportHeader,
                style: TextStyle(fontSize: 12, color: t.text2),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 24,
                runSpacing: 14,
                children: [
                  for (final (value, label) in summaryCells)
                    SizedBox(
                      width: 150,
                      child: _KvCell(value: value, label: label),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Divider(height: 1, color: t.hairline),
              const SizedBox(height: 12),
              if (topSongs.isNotEmpty)
                _ReportLine(
                  icon: Icons.music_note_outlined,
                  label: l.paneMaintTopSongLabel,
                  value: topSongs.first.title,
                  meta:
                      '${topSongs.first.subtitle.isEmpty ? '' : '${topSongs.first.subtitle} · '}${l.paneMaintPlayCount(topSongs.first.playCount)}',
                ),
              if (topArtists.isNotEmpty)
                _ReportLine(
                  icon: Icons.person_outline,
                  label: l.paneMaintTopArtistLabel,
                  value: topArtists.first.title,
                  meta: l.paneMaintPlayCount(topArtists.first.playCount),
                ),
              if (topAlbums.isNotEmpty)
                _ReportLine(
                  icon: Icons.album_outlined,
                  label: l.paneMaintTopAlbumLabel,
                  value: topAlbums.first.title,
                  meta:
                      '${topAlbums.first.subtitle.isEmpty ? '' : '${topAlbums.first.subtitle} · '}${l.paneMaintPlayCount(topAlbums.first.playCount)}',
                ),
              if (topMonth != null)
                _ReportLine(
                  icon: Icons.calendar_month_outlined,
                  label: l.paneMaintTopMonthLabel,
                  value: topMonth.label,
                  meta: l.paneMaintPlayCount(topMonth.count),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.paneMaintClose),
        ),
      ],
    );
  }
}

/// 年度报告内的一行「图标 + 标签 / 主值 + 次要信息」。
class _ReportLine extends StatelessWidget {
  const _ReportLine({
    required this.icon,
    required this.label,
    required this.value,
    required this.meta,
  });

  final IconData icon;
  final String label;
  final String value;
  final String meta;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 16, color: t.accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 11, color: t.text3)),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: t.text0,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(
              meta,
              style: TextStyle(
                fontSize: 11.5,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: t.text2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
