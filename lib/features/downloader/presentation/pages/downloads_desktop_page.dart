import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/features/downloader/presentation/providers/downloader_aggregate_provider.dart';
import 'package:my_nas/features/downloader/presentation/widgets/download_detail_sheet.dart';
import 'package:my_nas/shared/widgets/atoms/app_chip.dart';
import 'package:my_nas/shared/widgets/atoms/glass_panel.dart';
import 'package:my_nas/shared/widgets/atoms/status_dot.dart';
import 'package:my_nas/shared/widgets/desktop_shell/desktop_page_scaffold.dart';
import 'package:my_nas/shared/widgets/dialogs/add_download_dialog.dart';

/// 桌面端「下载器」——聚合 aria2 / qBittorrent / Transmission 真实任务。
///
/// 客户端 chips 跟随已配置「下载工具」源，状态 chips 过滤任务，dense-table
/// 展示进度 / 上下行速度，点击行打开 [DownloadDetailSheet]。
class DownloadsDesktopPage extends ConsumerStatefulWidget {
  const DownloadsDesktopPage({super.key});

  @override
  ConsumerState<DownloadsDesktopPage> createState() =>
      _DownloadsDesktopPageState();
}

class _DownloadsDesktopPageState extends ConsumerState<DownloadsDesktopPage> {
  String _client = '全部';
  String _filter = '全部';

  static const _filters = ['全部', '下载中', '做种', '已暂停', '已完成'];

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final clients = ref.watch(downloaderClientsProvider);
    final throughput = ref.watch(downloaderThroughputProvider);
    final allTasks = ref.watch(aggregatedDownloadTasksProvider);

    final clientNames = ['全部', ...clients.map((c) => c.source.displayName)];
    if (_client != '全部' && !clientNames.contains(_client)) _client = '全部';

    final tasks = allTasks.where((task) {
      final byClient = _client == '全部' || task.sourceName == _client;
      final byFilter = task.status.matchesFilter(_filter);
      return byClient && byFilter;
    }).toList()
      ..sort((a, b) => b.downloadSpeed.compareTo(a.downloadSpeed));

    return DesktopPageScaffold(
      title: '下载器',
      subtitle: 'qBittorrent · aria2 · Transmission — 跨客户端统一任务台',
      maxWidth: 1500,
      actions: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: FilledButton.icon(
          onPressed: () => showDialog<void>(
            context: context,
            barrierColor: Colors.black.withValues(alpha: 0.5),
            builder: (_) => const AddDownloadDialog(),
          ),
          icon: const Icon(Icons.add_rounded, size: 16),
          label: const Text('新建任务'),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Toolbar(
            clients: clients,
            clientFilter: _client,
            statusFilter: _filter,
            statusFilters: _filters,
            onClient: (c) => setState(() => _client = c),
            onStatus: (f) => setState(() => _filter = f),
          ),
          const SizedBox(height: 14),
          _SummaryBar(throughput: throughput),
          const SizedBox(height: 14),
          if (clients.isEmpty)
            _EmptyClients(t: t)
          else if (tasks.isEmpty)
            _EmptyTasks(t: t)
          else
            _TaskTable(
              tasks: tasks,
              onOpen: (task) => showDialog<void>(
                context: context,
                barrierColor: Colors.black.withValues(alpha: 0.55),
                builder: (_) => DownloadDetailSheet(taskKey: task.uniqueKey),
              ),
            ),
        ],
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.clients,
    required this.clientFilter,
    required this.statusFilter,
    required this.statusFilters,
    required this.onClient,
    required this.onStatus,
  });

  final List<DownloaderClient> clients;
  final String clientFilter;
  final String statusFilter;
  final List<String> statusFilters;
  final ValueChanged<String> onClient;
  final ValueChanged<String> onStatus;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AppChip(
          label: '全部',
          active: clientFilter == '全部',
          compact: true,
          onTap: () => onClient('全部'),
        ),
        for (final c in clients)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: AppChip(
              label: c.source.displayName,
              active: clientFilter == c.source.displayName,
              compact: true,
              onTap: () => onClient(c.source.displayName),
              trailing: StatusDot(c.connected ? DotStatus.ok : DotStatus.off),
            ),
          ),
        const Spacer(),
        for (final f in statusFilters)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: AppChip(
              label: f,
              active: f == statusFilter,
              compact: true,
              onTap: () => onStatus(f),
            ),
          ),
      ],
    );
  }
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.throughput});
  final DownloaderThroughput throughput;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        children: [
          _metric('↓ 总下行', formatSpeed(throughput.downloadSpeed),
              t.accentBright, t),
          _div(t),
          _metric('↑ 总上行', formatSpeed(throughput.uploadSpeed), t.text0, t),
          _div(t),
          _metric('活动任务', '${throughput.activeCount} / ${throughput.totalCount}',
              t.text0, t),
          _div(t),
          _metric(
              '在线客户端',
              '${throughput.connectedClients} / ${throughput.totalClients}',
              t.text0,
              t),
        ],
      ),
    );
  }

  Widget _div(DesignTokens t) => Container(
        width: 1,
        height: 28,
        margin: const EdgeInsets.symmetric(horizontal: 18),
        color: t.hairline,
      );

  Widget _metric(String label, String value, Color color, DesignTokens t) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: t.text2)),
          const SizedBox(height: 3),
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

class _TaskTable extends StatelessWidget {
  const _TaskTable({required this.tasks, required this.onOpen});
  final List<UnifiedDownloadTask> tasks;
  final ValueChanged<UnifiedDownloadTask> onOpen;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        children: [
          _headerRow(t),
          for (final task in tasks)
            _TaskRow(task: task, onTap: () => onOpen(task)),
        ],
      ),
    );
  }

  Widget _headerRow(DesignTokens t) {
    TextStyle s() => TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: t.text3,
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          Expanded(flex: 5, child: Text('名称', style: s())),
          Expanded(flex: 3, child: Text('进度', style: s())),
          SizedBox(width: 90, child: Text('↓ 下行', style: s())),
          SizedBox(width: 90, child: Text('↑ 上行', style: s())),
          SizedBox(width: 70, child: Text('剩余', style: s())),
          SizedBox(width: 64, child: Text('状态', style: s())),
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task, required this.onTap});
  final UnifiedDownloadTask task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
        hoverColor: t.chipBg,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: t.text0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${task.sourceName} · ${formatBytes(task.totalBytes)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: t.text2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: task.progress,
                          minHeight: 6,
                          backgroundColor: t.insetBg,
                          valueColor: AlwaysStoppedAnimation(
                            task.status == UnifiedDownloadStatus.seeding
                                ? t.ok
                                : t.accent,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(task.progress * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: t.text2,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 90,
                child: Text(
                  formatSpeed(task.downloadSpeed),
                  style: TextStyle(
                    fontSize: 12,
                    color: task.downloadSpeed > 0 ? t.accentBright : t.text3,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              SizedBox(
                width: 90,
                child: Text(
                  formatSpeed(task.uploadSpeed),
                  style: TextStyle(
                    fontSize: 12,
                    color: t.text2,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              SizedBox(
                width: 70,
                child: Text(
                  formatEta(task.etaSeconds),
                  style: TextStyle(fontSize: 12, color: t.text2),
                ),
              ),
              SizedBox(
                width: 64,
                child: Row(
                  children: [
                    StatusDot(_dot(task.status)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        task.status.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: t.text2),
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

class _EmptyClients extends StatelessWidget {
  const _EmptyClients({required this.t});
  final DesignTokens t;

  @override
  Widget build(BuildContext context) {
    return DesktopComingSoon(
      icon: Icons.download_outlined,
      message: '尚未连接下载客户端。\n到「数据源」添加 qBittorrent / aria2 / '
          'Transmission 之后，所有任务会聚合到这里（含 PT 一键发送）。',
    );
  }
}

class _EmptyTasks extends StatelessWidget {
  const _EmptyTasks({required this.t});
  final DesignTokens t;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 42),
      decoration: BoxDecoration(
        color: t.panelBg,
        border: Border.all(color: t.panelBorder),
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
      ),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.inbox_outlined, size: 36, color: t.text3),
            const SizedBox(height: 10),
            Text(
              '当前筛选下没有任务。',
              style: TextStyle(fontSize: 13, color: t.text2),
            ),
          ],
        ),
      ),
    );
  }
}

DotStatus _dot(UnifiedDownloadStatus s) => switch (s) {
      UnifiedDownloadStatus.downloading => DotStatus.accent,
      UnifiedDownloadStatus.seeding => DotStatus.ok,
      UnifiedDownloadStatus.paused => DotStatus.off,
      UnifiedDownloadStatus.completed => DotStatus.ok,
      UnifiedDownloadStatus.waiting => DotStatus.warn,
      UnifiedDownloadStatus.error => DotStatus.err,
    };
