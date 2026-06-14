import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/music/data/services/play_history_store.dart';
import 'package:my_nas/features/music/presentation/pages/duplicate_songs_page.dart';
import 'package:my_nas/features/music/presentation/pages/listening_stats_page.dart';
import 'package:my_nas/features/music/presentation/pages/recycle_bin_page.dart';
import 'package:my_nas/shared/widgets/atoms/app_button.dart';
import 'package:my_nas/shared/widgets/atoms/app_segmented.dart';
import 'package:my_nas/shared/widgets/atoms/app_tag.dart';
import 'package:my_nas/shared/widgets/atoms/settings_atoms.dart';

/// 桌面「维护与统计」设置 pane。
///
/// 对齐设计稿 `settings_panes.jsx · PaneMaint`：听歌统计（kv-strip + 活跃热力图
/// + Top 排行）+ 库维护（重复检测 / 回收站）。
///
/// 听歌统计直接读 [PlayHistoryStore]（本地播放历史聚合）的真实数据：周/月/年切换、
/// 摘要四项、按天热力图。Top 排行 / 重复检测 / 回收站用按钮打开现有功能页保留完整能力。
class MaintPane extends ConsumerStatefulWidget {
  const MaintPane({super.key});

  @override
  ConsumerState<MaintPane> createState() => _MaintPaneState();
}

class _MaintPaneState extends ConsumerState<MaintPane> {
  PlayHistoryRange _range = PlayHistoryRange.month;
  Future<void>? _initFuture;

  @override
  void initState() {
    super.initState();
    _initFuture = PlayHistoryStore.instance.init();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SetHead(
        icon: Icons.document_scanner_outlined,
        title: '维护与统计',
        subtitle: '听歌统计、重复检测与回收站。统计来自本地播放历史。',
        actions: [
          AppSegmented<PlayHistoryRange>(
            dense: true,
            options: const [
              AppSegmentedOption(value: PlayHistoryRange.week, label: '周'),
              AppSegmentedOption(value: PlayHistoryRange.month, label: '月'),
              AppSegmentedOption(value: PlayHistoryRange.year, label: '年'),
            ],
            value: _range,
            onChanged: (v) => setState(() => _range = v),
          ),
        ],
      ),

      // 听歌统计
      SetSection(
        title: '听歌统计',
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
            title: 'Top 排行',
            desc: '歌曲 / 艺术家 / 专辑 排行榜与活跃总览',
            trailing: AppButton(
              label: '查看排行',
              icon: Icons.leaderboard_outlined,
              dense: true,
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const ListeningStatsPage()),
              ),
            ),
          ),
          SetRow(
            title: '年度报告',
            desc: '可分享的年度听歌总结',
            last: true,
            trailing: const AppTag('即将推出', variant: TagVariant.plan),
          ),
        ],
      ),

      // 库维护
      SetSection(
        title: '库维护',
        hint: '仅清理本地索引 · 不动 NAS 原文件',
        bottomMargin: false,
        children: [
          SetRow(
            title: '重复歌曲检测',
            desc: '同一首歌的多版本（mp3 + flac），按音质评分推荐保留',
            trailing: AppButton(
              label: '处理',
              icon: Icons.content_copy_outlined,
              dense: true,
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const DuplicateSongsPage()),
              ),
            ),
          ),
          SetRow(
            title: '回收站',
            desc: '歌单删除项保留 30 天可恢复',
            last: true,
            trailing: AppButton(
              label: '打开',
              icon: Icons.restore_from_trash_outlined,
              dense: true,
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const RecycleBinPage()),
              ),
            ),
          ),
        ],
      ),
    ],
  );
}

/// 设计稿 `.kv-strip`：摘要四宫格（播放次数 / 总时长 / 活跃天 / 不重复曲目）。
class _KvStrip extends StatelessWidget {
  const _KvStrip({required this.summary});

  final PlayHistorySummary summary;

  @override
  Widget build(BuildContext context) {
    final hours = summary.totalSec / 3600;
    final hoursLabel = hours >= 10
        ? '${hours.toStringAsFixed(0)} h'
        : '${hours.toStringAsFixed(1)} h';
    final cells = <(String, String)>[
      (summary.totalPlays.toString(), '播放次数'),
      (hoursLabel, '总时长'),
      (summary.activeDays.toString(), '活跃天'),
      (summary.uniqueSongs.toString(), '不重复曲目'),
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
    final t = DesignTokens.of(context);
    final maxCount = daily.fold<int>(0, (a, d) => d.count > a ? d.count : a);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 9),
          child: Text(
            daily.isEmpty ? '活跃热力图' : '近 ${daily.length} 天活跃热力图',
            style: TextStyle(fontSize: 11, color: t.text3),
          ),
        ),
        if (daily.isEmpty)
          Text(
            '听满 30 秒的歌曲会被记入统计',
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
