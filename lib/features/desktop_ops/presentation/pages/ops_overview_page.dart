import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/downloader/presentation/providers/downloader_aggregate_provider.dart';
import 'package:my_nas/features/downloader/presentation/widgets/download_detail_sheet.dart';
import 'package:my_nas/features/nastool/presentation/providers/nastool_provider.dart';
import 'package:my_nas/features/pt_sites/presentation/providers/pt_site_provider.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/shared/widgets/atoms/app_card.dart';
import 'package:my_nas/shared/widgets/atoms/app_chip.dart';
import 'package:my_nas/shared/widgets/atoms/glass_panel.dart';
import 'package:my_nas/shared/widgets/atoms/status_dot.dart';
import 'package:my_nas/shared/widgets/desktop_shell/desktop_empty_state.dart';

/// 桌面端「运维总览」。
///
/// 实时吞吐 / stat tiles / 3 客户端卡片 / 正在下载列表均接 downloader 聚合
/// provider（aria2 + qBittorrent + Transmission）。
class OpsOverviewPage extends ConsumerWidget {
  const OpsOverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DesignTokens.of(context);
    final l = AppLocalizations.of(context);
    final connections = ref.watch(activeConnectionsProvider);
    final totalSources =
        ref.watch(sourcesProvider).valueOrNull?.length ?? connections.length;
    final throughput = ref.watch(downloaderThroughputProvider);
    final throughputHistory = ref.watch(downloaderThroughputHistoryProvider);
    final clients = ref.watch(downloaderClientsProvider);
    final tasks = ref.watch(aggregatedDownloadTasksProvider);

    // PT 概况：仅复用已建立连接拿到的 userInfo（本页不主动发起连接），
    // 未连接的站点同样列出但 ratio 留空降级。平均分享率只对已拿到 ratio
    // 的站点求平均。
    final ptSources = ref.watch(ptSitesSourcesProvider);
    final ptRows = [
      for (final s in ptSources)
        () {
          final conn = ref.watch(ptSiteConnectionProvider(s.id));
          return _PtSiteRow(
            name: conn.userInfo?.username ?? s.displayName,
            level: conn.userInfo?.userClass,
            ratio: conn.userInfo?.ratio,
          );
        }(),
    ];
    final ratios = ptRows
        .map((r) => r.ratio)
        .whereType<double>()
        .where((v) => v.isFinite)
        .toList();
    final avgRatio = ratios.isEmpty
        ? null
        : ratios.reduce((a, b) => a + b) / ratios.length;

    // 订阅追剧数：聚合各 NAStool 源的订阅列表；无 NAStool 源时降级为「—」。
    final nastoolSources = ref.watch(nastoolSourcesProvider);
    final subscribeValue = nastoolSources.isEmpty
        ? '—'
        : nastoolSources
              .fold<int>(
                0,
                (sum, s) =>
                    sum +
                    (ref
                            .watch(nastoolSubscribesProvider(s.id))
                            .valueOrNull
                            ?.length ??
                        0),
              )
              .toString();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(30, 26, 30, 120),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.opsTitle,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: t.text0,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                l.opsSubtitle,
                style: TextStyle(fontSize: 13, color: t.text2),
              ),
              const SizedBox(height: 22),
              _LiveThroughput(
                throughput: throughput,
                history: throughputHistory,
              ),
              const SizedBox(height: 16),
              _StatRow(
                connectedSources: connections.length,
                totalSources: totalSources,
                throughput: throughput,
                avgRatio: avgRatio,
                subscribeValue: subscribeValue,
              ),
              const SizedBox(height: 22),
              _ClientsRow(clients: clients),
              const SizedBox(height: 16),
              _BottomTwoCol(tasks: tasks, ptRows: ptRows),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveThroughput extends StatelessWidget {
  const _LiveThroughput({required this.throughput, required this.history});
  final DownloaderThroughput throughput;
  final List<DownloaderThroughputSample> history;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final l = AppLocalizations.of(context);
    final live = throughput.connectedClients > 0;
    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                l.opsLiveThroughput,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: t.text0,
                ),
              ),
              const SizedBox(width: 9),
              StatusDot(live ? DotStatus.ok : DotStatus.off),
              const SizedBox(width: 5),
              Text(
                live
                    ? l.opsLiveClientsRealtime(throughput.connectedClients)
                    : l.opsNoOnlineClients,
                style: TextStyle(fontSize: 11.5, color: t.text2),
              ),
              const Spacer(),
              _speed(
                '↓',
                formatSpeed(throughput.downloadSpeed),
                t.accentBright,
                t,
              ),
              const SizedBox(width: 18),
              _speed('↑', formatSpeed(throughput.uploadSpeed), t.text0, t),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(height: 150, child: _ThroughputChart(samples: history)),
        ],
      ),
    );
  }

  Widget _speed(String arrow, String value, Color color, DesignTokens t) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(arrow, style: TextStyle(fontSize: 13, color: t.text2)),
      const SizedBox(width: 4),
      Text(
        value,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    ],
  );
}

/// 简易吞吐图：使用下载器聚合 provider 的历史采样绘制 dn / up。
class _ThroughputChart extends StatelessWidget {
  const _ThroughputChart({required this.samples});

  final List<DownloaderThroughputSample> samples;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return CustomPaint(
      painter: _RibbonPainter(
        accent: t.accent,
        accentBright: t.accentBright,
        text2: t.text2,
        samples: samples,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _RibbonPainter extends CustomPainter {
  _RibbonPainter({
    required this.accent,
    required this.accentBright,
    required this.text2,
    required this.samples,
  });

  final Color accent;
  final Color accentBright;
  final Color text2;
  final List<DownloaderThroughputSample> samples;

  @override
  void paint(Canvas canvas, Size size) {
    final maxSpeed = samples.fold<int>(
      0,
      (max, s) =>
          [max, s.downloadSpeed, s.uploadSpeed].reduce((a, b) => a > b ? a : b),
    );
    final dnPath = _areaPath(
      size,
      samples.map((s) => s.downloadSpeed).toList(),
      maxSpeed,
      0.88,
    );
    final upPath = _areaPath(
      size,
      samples.map((s) => s.uploadSpeed).toList(),
      maxSpeed,
      0.46,
    );

    final dnFill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          accentBright.withValues(alpha: 0.30),
          accent.withValues(alpha: 0.02),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(dnPath, dnFill);

    final upFill = Paint()..color = text2.withValues(alpha: 0.10);
    canvas.drawPath(upPath, upFill);
  }

  Path _areaPath(
    Size size,
    List<int> values,
    int maxSpeed,
    double heightFactor,
  ) {
    final w = size.width;
    final h = size.height;
    final path = Path()..moveTo(0, h);
    if (values.isEmpty || maxSpeed <= 0) {
      path
        ..lineTo(w, h)
        ..close();
      return path;
    }

    final denom = values.length > 1 ? values.length - 1 : 1;
    for (var i = 0; i < values.length; i++) {
      final x = w * i / denom;
      final normalized = (values[i] / maxSpeed).clamp(0.0, 1.0);
      final y = h - h * heightFactor * normalized;
      path.lineTo(x, y);
    }
    path
      ..lineTo(w, h)
      ..close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _RibbonPainter old) =>
      old.accent != accent ||
      old.accentBright != accentBright ||
      old.text2 != text2 ||
      old.samples != samples;
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.connectedSources,
    required this.totalSources,
    required this.throughput,
    required this.avgRatio,
    required this.subscribeValue,
  });

  final int connectedSources;
  final int totalSources;
  final DownloaderThroughput throughput;

  /// 已连接 PT 站点的平均分享率；无数据时为 null（降级占位）。
  final double? avgRatio;

  /// NAStool 订阅追剧数（聚合文本，无源时为「—」）。
  final String subscribeValue;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return GridView.count(
      crossAxisCount: 4,
      crossAxisSpacing: 14,
      mainAxisSpacing: 14,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.6,
      children: [
        _StatTile(
          label: l.opsStatActiveTasks,
          value: '${throughput.activeCount}',
          unit: '/ ${throughput.totalCount}',
        ),
        _StatTile(
          label: l.opsStatSourcesOnline(totalSources),
          value: '$connectedSources',
          dot: DotStatus.ok,
        ),
        _StatTile(
          label: l.opsStatPtAvgRatio,
          value: avgRatio == null ? '—' : avgRatio!.toStringAsFixed(2),
        ),
        _StatTile(
          label: l.opsStatSubscribing,
          value: subscribeValue,
          accent: true,
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    this.unit,
    this.accent = false,
    this.dot,
  });

  final String label;
  final String value;
  final String? unit;
  final bool accent;
  final DotStatus? dot;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: accent ? t.accentBright : t.text0,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (unit != null)
                  TextSpan(
                    text: ' $unit',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: t.text2,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              if (dot != null) ...[StatusDot(dot!), const SizedBox(width: 6)],
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 12, color: t.text2),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ClientsRow extends StatelessWidget {
  const _ClientsRow({required this.clients});
  final List<DownloaderClient> clients;

  @override
  Widget build(BuildContext context) {
    if (clients.isEmpty) {
      final l = AppLocalizations.of(context);
      return DesktopEmptyState(
        icon: Icons.download_rounded,
        title: l.opsNoDownloaderClientsTitle,
        message: l.opsNoDownloaderClients,
        actionLabel: l.opsDownloaderChip,
        onAction: () => GoRouter.of(context).go('/download'),
        compact: true,
      );
    }
    return GridView.count(
      crossAxisCount: 3,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 3.0,
      children: [
        for (final c in clients)
          _ClientCard(
            name: c.source.displayName,
            connected: c.connected,
            downloadSpeed: c.downloadSpeed,
            uploadSpeed: c.uploadSpeed,
            taskCount: c.taskCount,
          ),
      ],
    );
  }
}

class _ClientCard extends StatelessWidget {
  const _ClientCard({
    required this.name,
    required this.connected,
    required this.downloadSpeed,
    required this.uploadSpeed,
    required this.taskCount,
  });

  final String name;
  final bool connected;
  final int downloadSpeed;
  final int uploadSpeed;
  final int taskCount;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final l = AppLocalizations.of(context);
    return AppCard(
      onTap: () => GoRouter.of(context).go('/download'),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusDot(connected ? DotStatus.ok : DotStatus.off),
              const SizedBox(width: 9),
              Text(
                name,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: t.text0,
                ),
              ),
              const Spacer(),
              Text(
                connected
                    ? l.opsClientTaskCount(taskCount)
                    : l.opsClientNotConnected,
                style: TextStyle(fontSize: 11, color: t.text2),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _speedCol('↓', formatSpeed(downloadSpeed), t.accentBright, t),
              const SizedBox(width: 18),
              _speedCol('↑', formatSpeed(uploadSpeed), t.text0, t),
            ],
          ),
        ],
      ),
    );
  }

  Widget _speedCol(String arrow, String value, Color color, DesignTokens t) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$arrow$value',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: color,
              fontFamily: 'SF Mono',
              fontFamilyFallback: const ['Menlo'],
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      );
}

/// PT 概况单行视图模型（从已连接站点的 userInfo 派生，纯展示）。
class _PtSiteRow {
  const _PtSiteRow({required this.name, this.level, this.ratio});
  final String name;
  final String? level;
  final double? ratio;
}

class _BottomTwoCol extends StatelessWidget {
  const _BottomTwoCol({required this.tasks, required this.ptRows});
  final List<UnifiedDownloadTask> tasks;
  final List<_PtSiteRow> ptRows;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final l = AppLocalizations.of(context);
    final downloading =
        tasks
            .where((task) => task.status == UnifiedDownloadStatus.downloading)
            .toList()
          ..sort((a, b) => b.downloadSpeed.compareTo(a.downloadSpeed));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 7,
          child: GlassPanel(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      l.opsDownloadingTitle,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: t.text0,
                      ),
                    ),
                    const Spacer(),
                    AppChip(
                      label: l.opsDownloaderChip,
                      icon: Icons.open_in_new_rounded,
                      compact: true,
                      onTap: () => GoRouter.of(context).go('/download'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (downloading.isEmpty)
                  DesktopEmptyState(
                    icon: Icons.download_done_rounded,
                    message: l.opsNoDownloadingTasks,
                    compact: true,
                    embedded: true,
                  )
                else
                  for (final task in downloading.take(6))
                    _MiniTaskRow(task: task),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 5,
          child: GlassPanel(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      l.opsPtOverviewTitle,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: t.text0,
                      ),
                    ),
                    const Spacer(),
                    AppChip(
                      label: l.opsSitesChip,
                      icon: Icons.open_in_new_rounded,
                      compact: true,
                      onTap: () => GoRouter.of(context).go('/pt'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (ptRows.isEmpty)
                  DesktopEmptyState(
                    icon: Icons.flag_circle_outlined,
                    message: l.opsNoPtSites,
                    compact: true,
                    embedded: true,
                  )
                else
                  for (final row in ptRows.take(6)) _PtRow(row: row),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PtRow extends StatelessWidget {
  const _PtRow({required this.row});
  final _PtSiteRow row;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final l = AppLocalizations.of(context);
    final ratio = row.ratio;
    final hasRatio = ratio != null && ratio.isFinite;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: t.text0,
                  ),
                ),
                if (row.level != null && row.level!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    row.level!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: t.text2),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                hasRatio ? ratio.toStringAsFixed(2) : '—',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  // 设计稿：分享率 > 4 用 ok 绿，否则常规文本色。
                  color: hasRatio && ratio > 4 ? t.ok : t.text0,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                l.opsRatioLabel,
                style: TextStyle(fontSize: 10.5, color: t.text2),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniTaskRow extends StatelessWidget {
  const _MiniTaskRow({required this.task});
  final UnifiedDownloadTask task;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => showDownloadDetailDrawer(context, task.uniqueKey),
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
        hoverColor: t.chipBg,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 11),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: t.text0,
                      ),
                    ),
                    const SizedBox(height: 7),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: task.progress,
                        minHeight: 5,
                        backgroundColor: t.insetBg,
                        valueColor: AlwaysStoppedAnimation(t.accent),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // 设计稿右侧两行：速度（accent）/ ETA（muted），右对齐。
              SizedBox(
                width: 90,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '↓${formatSpeed(task.downloadSpeed)}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: t.accentBright,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatEta(task.etaSeconds),
                      style: TextStyle(
                        fontSize: 10.5,
                        color: t.text2,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
