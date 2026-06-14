import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/book/domain/entities/book_source.dart';
import 'package:my_nas/features/book/presentation/pages/book_settings_page.dart';
import 'package:my_nas/features/book/presentation/pages/book_sources_page.dart';
import 'package:my_nas/features/book/presentation/providers/book_source_provider.dart';
import 'package:my_nas/features/reading/data/services/reader_settings_service.dart';
import 'package:my_nas/features/reading/data/services/reading_progress_service.dart';
import 'package:my_nas/features/reading/presentation/providers/reader_settings_provider.dart';
import 'package:my_nas/shared/widgets/atoms/app_button.dart';
import 'package:my_nas/shared/widgets/atoms/app_segmented.dart';
import 'package:my_nas/shared/widgets/atoms/app_switch.dart';
import 'package:my_nas/shared/widgets/atoms/app_tag.dart';
import 'package:my_nas/shared/widgets/atoms/settings_atoms.dart';

/// 由 [ReadingProgressService] 现有进度 / 最近阅读派生的阅读统计。
///
/// 仅做现有数据的纯派生（不引入新存储、不改阅读器逻辑）：
/// - [reading]：有进度但未读完（0 < 进度 < 100%）
/// - [finished]：进度 = 100%
/// - [total]：有进度记录的条目总数
/// - [daily]：近 [_ReadingStats.heatmapDays] 天每天「读过的条目数」热力图数据，
///   时间戳取自 [ReadingProgressService.getRecentReading]（每条目记最近一次阅读）。
class _ReadingStats {
  const _ReadingStats({
    required this.reading,
    required this.finished,
    required this.total,
    required this.daily,
  });

  static const _ReadingStats empty = _ReadingStats(
    reading: 0,
    finished: 0,
    total: 0,
    daily: [],
  );

  /// 热力图天数（近 N 周，与 maint 听歌热力图一致）。
  static const int heatmapDays = 70;

  final int reading;
  final int finished;
  final int total;
  final List<({DateTime date, int count})> daily;

  /// 完读率（已读 / 有进度总数），无数据时为 0。
  double get finishRate => total <= 0 ? 0 : finished / total;

  String get finishRateText => '${(finishRate * 100).toStringAsFixed(0)}%';

  /// 读取服务并派生统计。调用方负责确保 [service] 已 `init()`。
  static _ReadingStats from(ReadingProgressService service) {
    final all = service.getAllProgress();
    var reading = 0;
    var finished = 0;
    for (final p in all) {
      if (p.progressPercent >= 1.0) {
        finished++;
      } else if (p.progressPercent > 0) {
        reading++;
      }
    }

    // 近 heatmapDays 天，按本地日期聚合「当天读过的条目数」。
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = today.subtract(const Duration(days: heatmapDays - 1));
    final counts = <DateTime, int>{};
    // 取尽量多的最近阅读记录（每条目一条）。
    for (final r in service.getRecentReading(limit: 9999)) {
      final ts = r.timestamp;
      final day = DateTime(ts.year, ts.month, ts.day);
      if (day.isBefore(start) || day.isAfter(today)) continue;
      counts[day] = (counts[day] ?? 0) + 1;
    }
    final daily = <({DateTime date, int count})>[];
    for (var i = 0; i < heatmapDays; i++) {
      final day = start.add(Duration(days: i));
      daily.add((date: day, count: counts[day] ?? 0));
    }

    return _ReadingStats(
      reading: reading,
      finished: finished,
      total: all.length,
      daily: daily,
    );
  }
}

/// 桌面「设置 · 阅读」详情 pane。
///
/// 对应设计稿 `settings_panes.jsx` 的 `PaneReading`：阅读器引擎、全局阅读偏好
/// 与在线书源（Legado 格式）列表。书源/图书设置的复杂管理沿用现有功能页
/// （[BookSourcesPage] / [BookSettingsPage]）。
class ReadingPane extends ConsumerStatefulWidget {
  const ReadingPane({super.key});

  @override
  ConsumerState<ReadingPane> createState() => _ReadingPaneState();
}

class _ReadingPaneState extends ConsumerState<ReadingPane> {
  final ReadingProgressService _progressService = ReadingProgressService();
  _ReadingStats _stats = _ReadingStats.empty;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    await _progressService.init();
    if (!mounted) return;
    setState(() => _stats = _ReadingStats.from(_progressService));
  }

  void _openStats() => showDialog<void>(
        context: context,
        builder: (_) => _ReadingStatsDialog(stats: _stats),
      );

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final settings = ref.watch(bookReaderSettingsProvider);
    final sourcesAsync = ref.watch(bookSourcesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SetHead(
          icon: Icons.menu_book_outlined,
          title: '阅读',
          subtitle:
              '阅读器引擎、在线书源与全局阅读偏好。图书 / 漫画 / PDF 共享统一阅读进度（itemType 区分）。',
          actions: [
            AppButton(
              label: '导入书源',
              icon: Icons.add_rounded,
              onPressed: () => _openSources(context),
            ),
          ],
        ),

        // ---- 阅读器 ----
        SetSection(
          title: '阅读器',
          children: [
            SetRow(
              title: 'EPUB 引擎',
              desc: '原生（快、省内存）/ WebView（排版还原度高）',
              trailing: AppSegmented<EpubReaderEngine>(
                options: const [
                  AppSegmentedOption(
                    value: EpubReaderEngine.native,
                    label: 'EPUB 原生',
                  ),
                  AppSegmentedOption(
                    value: EpubReaderEngine.foliate,
                    label: 'WebView',
                  ),
                ],
                value: settings.epubEngine,
                onChanged: (v) => ref
                    .read(bookReaderSettingsProvider.notifier)
                    .setEpubEngine(v),
              ),
            ),
            SetRow(
              title: '保持屏幕常亮',
              desc: '阅读图书时不自动熄屏',
              trailing: AppSwitch(
                value: settings.keepScreenOn,
                onChanged: (v) => ref
                    .read(bookReaderSettingsProvider.notifier)
                    .setKeepScreenOn(value: v),
              ),
            ),
            SetRow(
              title: '显示阅读进度',
              desc: '在阅读器底部显示章节进度与百分比',
              trailing: AppSwitch(
                value: settings.showProgress,
                onChanged: (v) => ref
                    .read(bookReaderSettingsProvider.notifier)
                    .setShowProgress(value: v),
              ),
            ),
            SetRow(
              title: '全局阅读偏好',
              desc: '字号 / 字体 / 主题 / 翻页方式 — 新书自动套用',
              trailing: AppButton(
                label: '打开',
                icon: Icons.tune_rounded,
                dense: true,
                onPressed: () => _openBookSettings(context),
              ),
            ),
            SetRow(
              title: '阅读历史统计',
              desc: _stats.total > 0
                  ? '在读 ${_stats.reading} · 已读 ${_stats.finished} · '
                      '完读率 ${_stats.finishRateText}'
                  : '完读率 / 在读已读 / 阅读活跃热力图',
              last: true,
              trailing: AppButton(
                label: '查看',
                icon: Icons.insights_outlined,
                dense: true,
                onPressed: _stats.total > 0 ? _openStats : null,
              ),
            ),
          ],
        ),

        // ---- 在线书源 ----
        SetSection(
          title: '在线书源',
          hint: sourcesAsync.maybeWhen(
            data: (s) => 'Legado 格式 · ${s.length} 个',
            orElse: () => 'Legado 格式',
          ),
          children: _buildSourceRows(context, t, sourcesAsync),
        ),
      ],
    );
  }

  List<Widget> _buildSourceRows(
    BuildContext context,
    DesignTokens t,
    AsyncValue<List<BookSource>> sourcesAsync,
  ) {
    final preview = sourcesAsync.maybeWhen(
      data: (s) => s,
      orElse: () => const <BookSource>[],
    );

    final rows = <Widget>[];

    if (sourcesAsync.isLoading && preview.isEmpty) {
      rows.add(
        const SetRow(
          title: '加载中…',
          desc: '正在读取已配置的书源',
        ),
      );
    } else if (preview.isEmpty) {
      rows.add(
        const SetRow(
          title: '暂无书源',
          desc: '导入 Legado 格式书源后可在线搜索、阅读或加入书架',
        ),
      );
    } else {
      final shown = preview.take(4).toList();
      for (var i = 0; i < shown.length; i++) {
        final s = shown[i];
        final isLastRow = i == shown.length - 1 && preview.length <= 4;
        rows.add(
          SetRow(
            title: s.displayName,
            desc: '规则引擎：搜索 / 探索 / 正文 / 目录（CSS-XPath）',
            leading: _SourceIcon(t: t),
            last: isLastRow,
            trailing: AppTag(
              s.enabled ? '启用' : '停用',
              variant: s.enabled ? TagVariant.free : TagVariant.limit,
            ),
          ),
        );
      }
      if (preview.length > 4) {
        rows.add(
          SetRow(
            title: '查看全部 ${preview.length} 个书源',
            desc: '导入 / 编辑 / 启停 / 排序 / 在线搜索',
            last: true,
            trailing: AppButton(
              label: '管理',
              icon: Icons.tune_rounded,
              dense: true,
              onPressed: () => _openSources(context),
            ),
          ),
        );
      }
    }

    rows.add(
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '书源支持导入 / 编辑 / 启停 / 搜索；在线结果可直接阅读或加入书架。',
                style: TextStyle(fontSize: 12, height: 1.4, color: t.text2),
              ),
            ),
            const SizedBox(width: 14),
            AppButton(
              label: '管理书源',
              icon: Icons.dns_rounded,
              dense: true,
              onPressed: () => _openSources(context),
            ),
          ],
        ),
      ),
    );

    return rows;
  }

  void _openSources(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const BookSourcesPage()),
      );

  void _openBookSettings(BuildContext context) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const BookSettingsPage()),
      );
}

/// 书源行左侧的小图标（对齐设计稿 `.conn-ic` 32×32）。
class _SourceIcon extends StatelessWidget {
  const _SourceIcon({required this.t});

  final DesignTokens t;

  @override
  Widget build(BuildContext context) => Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: t.insetBg,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: t.hairline, width: 0.5),
        ),
        child: Icon(Icons.menu_book_outlined, size: 16, color: t.text2),
      );
}

/// 阅读历史统计弹窗：摘要四宫格 + 近 N 天阅读活跃热力图。
///
/// 数据全部由 [ReadingProgressService] 现有进度 / 最近阅读派生（见 [_ReadingStats]）。
class _ReadingStatsDialog extends StatelessWidget {
  const _ReadingStatsDialog({required this.stats});

  final _ReadingStats stats;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Dialog(
      backgroundColor: t.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        side: BorderSide(color: t.cardBorder),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.insights_outlined, size: 20, color: t.accentBright),
                  const SizedBox(width: 10),
                  Text(
                    '阅读历史统计',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: t.text0,
                    ),
                  ),
                  const Spacer(),
                  AppButton(
                    label: '关闭',
                    dense: true,
                    variant: AppButtonVariant.ghost,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _StatKvStrip(stats: stats),
              const SizedBox(height: 18),
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: t.hairline)),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: _ReadingHeatmap(daily: stats.daily),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 摘要四宫格：在读 / 已读 / 完读率 / 有进度总数。
class _StatKvStrip extends StatelessWidget {
  const _StatKvStrip({required this.stats});

  final _ReadingStats stats;

  @override
  Widget build(BuildContext context) {
    final cells = <(String, String)>[
      (stats.reading.toString(), '在读'),
      (stats.finished.toString(), '已读'),
      (stats.finishRateText, '完读率'),
      (stats.total.toString(), '有进度'),
    ];
    return Row(
      children: [
        for (final (value, label) in cells)
          Expanded(child: _StatKvCell(value: value, label: label)),
      ],
    );
  }
}

class _StatKvCell extends StatelessWidget {
  const _StatKvCell({required this.value, required this.label});

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

/// 近 N 天阅读活跃热力图（仿 maint 听歌热力图）。每格 = 当天读过的条目数。
class _ReadingHeatmap extends StatelessWidget {
  const _ReadingHeatmap({required this.daily});

  final List<({DateTime date, int count})> daily;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final maxCount = daily.fold<int>(0, (a, d) => d.count > a ? d.count : a);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: Text(
            '近 ${daily.length} 天阅读活跃',
            style: TextStyle(fontSize: 11, color: t.text3),
          ),
        ),
        if (maxCount == 0)
          Text(
            '近期还没有阅读记录',
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
