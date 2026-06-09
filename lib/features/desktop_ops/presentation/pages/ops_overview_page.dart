import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/downloader/presentation/providers/downloader_aggregate_provider.dart';
import 'package:my_nas/features/downloader/presentation/widgets/download_detail_sheet.dart';
import 'package:my_nas/features/pt_sites/presentation/providers/pt_site_provider.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/shared/widgets/atoms/app_card.dart';
import 'package:my_nas/shared/widgets/atoms/app_chip.dart';
import 'package:my_nas/shared/widgets/atoms/glass_panel.dart';
import 'package:my_nas/shared/widgets/atoms/status_dot.dart';

/// 桌面端「运维总览」。
///
/// 实时吞吐 / stat tiles / 3 客户端卡片 / 正在下载列表均接 downloader 聚合
/// provider（aria2 + qBittorrent + Transmission）。
class OpsOverviewPage extends ConsumerWidget {
  const OpsOverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DesignTokens.of(context);
    final connections = ref.watch(activeConnectionsProvider);
    final totalSources =
        ref.watch(sourcesProvider).valueOrNull?.length ?? connections.length;
    final throughput = ref.watch(downloaderThroughputProvider);
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

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(30, 26, 30, 120),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1500),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '运维总览',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: t.text0,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '下载器 · 传输 · PT · 自动化 · 数据源 — 一处掌控',
                style: TextStyle(fontSize: 13, color: t.text2),
              ),
              const SizedBox(height: 22),
              _LiveThroughput(throughput: throughput),
              const SizedBox(height: 16),
              _StatRow(
                connectedSources: connections.length,
                totalSources: totalSources,
                throughput: throughput,
                avgRatio: avgRatio,
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
  const _LiveThroughput({required this.throughput});
  final DownloaderThroughput throughput;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final live = throughput.connectedClients > 0;
    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '实时吞吐',
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
                    ? '聚合 ${throughput.connectedClients} 个客户端 · 每秒刷新'
                    : '暂无在线下载客户端',
                style: TextStyle(fontSize: 11.5, color: t.text2),
              ),
              const Spacer(),
              _speed('↓', formatSpeed(throughput.downloadSpeed), t.accentBright, t),
              const SizedBox(width: 18),
              _speed('↑', formatSpeed(throughput.uploadSpeed), t.text0, t),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(height: 150, child: _ThroughputChart()),
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

/// 简易吞吐图：用两条静态 ribbon 表达 dn / up（视觉氛围，数值见上方读数）。
class _ThroughputChart extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return CustomPaint(
      painter: _RibbonPainter(
        accent: t.accent,
        accentBright: t.accentBright,
        text2: t.text2,
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
  });

  final Color accent;
  final Color accentBright;
  final Color text2;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final dnPath = Path()..moveTo(0, h);
    final upPath = Path()..moveTo(0, h);
    const points = 60;
    for (var i = 0; i <= points; i++) {
      final x = w * i / points;
      final dnY = h - h * 0.55 *
          (0.42 + 0.5 * (0.5 + 0.5 * _sinish(i * 0.42)));
      final upY = h - h * 0.28 *
          (0.30 + 0.5 * (0.5 + 0.5 * _sinish(i * 0.55 + 1.4)));
      dnPath.lineTo(x, dnY);
      upPath.lineTo(x, upY);
    }
    dnPath.lineTo(w, h);
    upPath.lineTo(w, h);

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

    final upFill = Paint()
      ..color = text2.withValues(alpha: 0.10);
    canvas.drawPath(upPath, upFill);
  }

  double _sinish(double x) {
    final wrapped = x - x.toInt();
    return 1 - (wrapped - 0.5).abs() * 4;
  }

  @override
  bool shouldRepaint(covariant _RibbonPainter old) =>
      old.accent != accent ||
      old.accentBright != accentBright ||
      old.text2 != text2;
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.connectedSources,
    required this.totalSources,
    required this.throughput,
    required this.avgRatio,
  });

  final int connectedSources;
  final int totalSources;
  final DownloaderThroughput throughput;

  /// 已连接 PT 站点的平均分享率；无数据时为 null（降级占位）。
  final double? avgRatio;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 4,
      crossAxisSpacing: 14,
      mainAxisSpacing: 14,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.6,
      children: [
        _StatTile(
          label: '活动任务',
          value: '${throughput.activeCount}',
          unit: '/ ${throughput.totalCount}',
        ),
        _StatTile(
          label: '源在线 · 共 $totalSources',
          value: '$connectedSources',
          dot: DotStatus.ok,
        ),
        _StatTile(
          label: 'PT 平均分享率',
          value: avgRatio == null ? '—' : avgRatio!.toStringAsFixed(2),
        ),
        const _StatTile(label: '订阅追剧中', value: '0', accent: true),
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
          Text.rich(TextSpan(
            children: [
              TextSpan(
                text: value,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: accent ? t.accentBright : t.text0,
                  letterSpacing: -0.4,
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
          )),
          const SizedBox(height: 4),
          Row(
            children: [
              if (dot != null) ...[
                StatusDot(dot!),
                const SizedBox(width: 6),
              ],
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
    // 没有任何下载源时，展示三种受支持客户端的占位卡片。
    if (clients.isEmpty) {
      const placeholders = ['qBittorrent', 'aria2', 'Transmission'];
      return GridView.count(
        crossAxisCount: 3,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 3.0,
        children: [
          for (final name in placeholders)
            _ClientCard(
              name: name,
              connected: false,
              downloadSpeed: 0,
              uploadSpeed: 0,
              taskCount: 0,
            ),
        ],
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
                connected ? '$taskCount 任务' : '未连接',
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
    final downloading = tasks
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
                      '正在下载',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: t.text0,
                      ),
                    ),
                    const Spacer(),
                    AppChip(
                      label: '下载器',
                      icon: Icons.open_in_new_rounded,
                      compact: true,
                      onTap: () => GoRouter.of(context).go('/download'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (downloading.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        '没有正在下载的任务。',
                        style: TextStyle(fontSize: 13, color: t.text2),
                      ),
                    ),
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
                      'PT 概况',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: t.text0,
                      ),
                    ),
                    const Spacer(),
                    const AppChip(
                      label: '站点',
                      icon: Icons.open_in_new_rounded,
                      compact: true,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (ptRows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        '尚未配置 PT 站点。',
                        style: TextStyle(fontSize: 13, color: t.text2),
                      ),
                    ),
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
                    fontWeight: FontWeight.w600,
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
              Text('分享率', style: TextStyle(fontSize: 10.5, color: t.text2)),
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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
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
