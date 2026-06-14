import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/aria2/presentation/providers/aria2_provider.dart';
import 'package:my_nas/features/downloader/presentation/providers/downloader_aggregate_provider.dart';
import 'package:my_nas/features/downloader/presentation/widgets/download_detail_sheet.dart';
import 'package:my_nas/features/qbittorrent/presentation/providers/qbittorrent_provider.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/transmission/presentation/providers/transmission_provider.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/shared/widgets/atoms/app_chip.dart';
import 'package:my_nas/shared/widgets/atoms/app_tag.dart';
import 'package:my_nas/shared/widgets/atoms/glass_panel.dart';
import 'package:my_nas/shared/widgets/atoms/status_dot.dart';
import 'package:my_nas/shared/widgets/atoms/status_pill.dart';
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
  /// null = 全部客户端（与 chip 显示标签解耦的内部哨兵）。
  String? _client;
  DownloadStatusFilter _filter = DownloadStatusFilter.all;
  final Set<String> _selected = {};

  /// 批量操作：按 sourceId 分组后分发到各客户端的批量 API。
  Future<void> _batch(
    List<UnifiedDownloadTask> selectedTasks,
    _BatchOp op,
  ) async {
    final l = AppLocalizations.of(context);
    final groups = <String, List<UnifiedDownloadTask>>{};
    for (final task in selectedTasks) {
      groups.putIfAbsent(task.sourceId, () => []).add(task);
    }
    try {
      for (final entry in groups.entries) {
        final sourceId = entry.key;
        final group = entry.value;
        final ids = group.map((t) => t.taskId).toList();
        switch (group.first.sourceType) {
          case SourceType.aria2:
            final a = ref.read(aria2ActionsProvider(sourceId));
            for (final id in ids) {
              switch (op) {
                case _BatchOp.pause:
                  await a.pause(id);
                case _BatchOp.resume:
                  await a.resume(id);
                case _BatchOp.delete:
                  await a.remove(id);
              }
            }
          case SourceType.qbittorrent:
            final a = ref.read(qbittorrentActionsProvider(sourceId));
            switch (op) {
              case _BatchOp.pause:
                await a.pause(ids);
              case _BatchOp.resume:
                await a.resume(ids);
              case _BatchOp.delete:
                await a.delete(ids, deleteFiles: false);
            }
          case SourceType.transmission:
            final a = ref.read(transmissionActionsProvider(sourceId));
            final intIds = ids.map(int.tryParse).whereType<int>().toList();
            switch (op) {
              case _BatchOp.pause:
                await a.stop(intIds);
              case _BatchOp.resume:
                await a.start(intIds);
              case _BatchOp.delete:
                await a.remove(intIds, deleteFiles: false);
            }
          default:
            break;
        }
      }
      if (mounted) setState(_selected.clear);
    } on Object catch (e) {
      if (mounted) context.showErrorToast(l.dlPageBatchOpFailed(e.toString()));
    }
  }

  Future<void> _confirmBatchDelete(List<UnifiedDownloadTask> selected) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.dlPageDeleteSelectedTitle),
        content: Text(l.dlPageDeleteSelectedConfirm(selected.length)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l.dlPageCancel)),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l.dlPageDelete)),
        ],
      ),
    );
    if (ok == true) await _batch(selected, _BatchOp.delete);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    final clients = ref.watch(downloaderClientsProvider);
    final throughput = ref.watch(downloaderThroughputProvider);
    final allTasks = ref.watch(aggregatedDownloadTasksProvider);

    if (_client != null &&
        !clients.any((c) => c.source.displayName == _client)) {
      _client = null;
    }

    final tasks = allTasks.where((task) {
      final byClient = _client == null || task.sourceName == _client;
      final byFilter = _filter.matches(task.status);
      return byClient && byFilter;
    }).toList()
      ..sort((a, b) => b.downloadSpeed.compareTo(a.downloadSpeed));

    // 全局限速控件仅 qBittorrent 客户端支持（API 提供 setGlobalSpeedLimits）。
    final qbClients = clients
        .where((c) => c.source.type == SourceType.qbittorrent)
        .toList();
    final qbSourceId = qbClients.isEmpty ? null : qbClients.first.source.id;

    return DesktopPageScaffold(
      title: l.dlPageTitle,
      subtitle: l.dlPageSubtitle,
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
          label: Text(l.dlPageNewTask),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Toolbar(
            clients: clients,
            clientFilter: _client,
            statusFilter: _filter,
            onClient: (c) => setState(() => _client = c),
            onStatus: (f) => setState(() => _filter = f),
          ),
          const SizedBox(height: 14),
          _SummaryBar(throughput: throughput),
          const SizedBox(height: 14),
          if (_selected.isNotEmpty) ...[
            _BatchBar(
              count: _selected.length,
              onPause: () => _batch(
                tasks.where((t) => _selected.contains(t.uniqueKey)).toList(),
                _BatchOp.pause,
              ),
              onResume: () => _batch(
                tasks.where((t) => _selected.contains(t.uniqueKey)).toList(),
                _BatchOp.resume,
              ),
              onDelete: () => _confirmBatchDelete(
                tasks.where((t) => _selected.contains(t.uniqueKey)).toList(),
              ),
              onClear: () => setState(_selected.clear),
            ),
            const SizedBox(height: 12),
          ],
          if (clients.isEmpty)
            _EmptyClients(t: t)
          else if (tasks.isEmpty)
            _EmptyTasks(t: t)
          else
            _TaskTable(
              tasks: tasks,
              qbSourceId: qbSourceId,
              selected: _selected,
              onToggle: (key) => setState(() {
                _selected.contains(key)
                    ? _selected.remove(key)
                    : _selected.add(key);
              }),
              onToggleAll: () => setState(() {
                final keys = tasks.map((t) => t.uniqueKey).toSet();
                if (keys.every(_selected.contains)) {
                  _selected.removeAll(keys);
                } else {
                  _selected.addAll(keys);
                }
              }),
              onOpen: (task) =>
                  showDownloadDetailDrawer(context, task.uniqueKey),
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
    required this.onClient,
    required this.onStatus,
  });

  final List<DownloaderClient> clients;
  final String? clientFilter;
  final DownloadStatusFilter statusFilter;
  final ValueChanged<String?> onClient;
  final ValueChanged<DownloadStatusFilter> onStatus;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Row(
      children: [
        AppChip(
          label: l.downloadFilterAll,
          active: clientFilter == null,
          compact: true,
          onTap: () => onClient(null),
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
        for (final f in DownloadStatusFilter.values)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: AppChip(
              label: f.label(l),
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
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        children: [
          _metric('↓ ${l.dlPageTotalDown}', formatSpeed(throughput.downloadSpeed),
              t.accentBright, t),
          _div(t),
          _metric('↑ ${l.dlPageTotalUp}', formatSpeed(throughput.uploadSpeed),
              t.text0, t),
          _div(t),
          _metric(l.dlPageActiveTasks,
              '${throughput.activeCount} / ${throughput.totalCount}', t.text0, t),
          _div(t),
          _metric(
              l.dlPageOnlineClients,
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
  const _TaskTable({
    required this.tasks,
    required this.qbSourceId,
    required this.selected,
    required this.onToggle,
    required this.onToggleAll,
    required this.onOpen,
  });
  final List<UnifiedDownloadTask> tasks;
  final String? qbSourceId;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final VoidCallback onToggleAll;
  final ValueChanged<UnifiedDownloadTask> onOpen;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    final allSelected =
        tasks.isNotEmpty && tasks.every((x) => selected.contains(x.uniqueKey));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassPanel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _headerRow(l, t, allSelected),
              for (final task in tasks)
                _TaskRow(
                  task: task,
                  selected: selected.contains(task.uniqueKey),
                  onToggleSelect: () => onToggle(task.uniqueKey),
                  onTap: () => onOpen(task),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Text(l.dlPageGlobalRateLimit,
                style: TextStyle(fontSize: 12, color: t.text2)),
            const SizedBox(width: 8),
            if (qbSourceId != null)
              AppChip(
                label: l.dlPageConfigureQb,
                icon: Icons.speed_rounded,
                compact: true,
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => _GlobalLimitDialog(sourceId: qbSourceId!),
                ),
              )
            else
              AppTag(l.dlPageManagedInClient, variant: TagVariant.neutral),
            const Spacer(),
            Text(
              l.dlPageRateLimitHint,
              style: TextStyle(fontSize: 12, color: t.text2),
            ),
          ],
        ),
      ],
    );
  }

  Widget _headerRow(AppLocalizations l, DesignTokens t, bool allSelected) {
    TextStyle s() => TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: t.text3,
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.hairline)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Checkbox(
              value: allSelected,
              visualDensity: VisualDensity.compact,
              onChanged: (_) => onToggleAll(),
            ),
          ),
          Expanded(child: Text(l.dlPageColName, style: s())),
          const SizedBox(width: 10),
          SizedBox(width: 96, child: Text(l.dlPageColClient, style: s())),
          SizedBox(width: 80, child: Text(l.dlPageColStatus, style: s())),
          SizedBox(width: 150, child: Text(l.dlPageColProgress, style: s())),
          const SizedBox(width: 10),
          SizedBox(width: 92, child: Text('↓ ${l.dlPageColSpeed}', style: s())),
          SizedBox(width: 92, child: Text('↑ ${l.dlPageColSpeed}', style: s())),
          SizedBox(width: 72, child: Text(l.dlPageColSize, style: s())),
          SizedBox(width: 64, child: Text('ETA', style: s())),
        ],
      ),
    );
  }
}

/// 设计稿 .state-pill：彩色状态徽章。
/// 下载任务状态徽标：薄适配层，复用共享原子 [StatusPill]，
/// 不再重复一套配色 switch。
class _StatePill extends StatelessWidget {
  const _StatePill({required this.status});
  final UnifiedDownloadStatus status;

  static PillStatus _toPill(UnifiedDownloadStatus s) => switch (s) {
        UnifiedDownloadStatus.downloading => PillStatus.downloading,
        UnifiedDownloadStatus.seeding => PillStatus.seeding,
        UnifiedDownloadStatus.paused => PillStatus.paused,
        UnifiedDownloadStatus.waiting => PillStatus.queued,
        UnifiedDownloadStatus.completed => PillStatus.completed,
        UnifiedDownloadStatus.error => PillStatus.error,
      };

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: StatusPill(
          _toPill(status),
          label: status.label(AppLocalizations.of(context)),
        ),
      );
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.task,
    required this.selected,
    required this.onToggleSelect,
    required this.onTap,
  });
  final UnifiedDownloadTask task;
  final bool selected;
  final VoidCallback onToggleSelect;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    return Material(
      color: selected ? t.chipBgActive : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
        hoverColor: t.chipBg,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.hairline)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 30,
                child: Checkbox(
                  value: selected,
                  visualDensity: VisualDensity.compact,
                  onChanged: (_) => onToggleSelect(),
                ),
              ),
              Expanded(
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
                    if (task.ratio != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        l.dlPageRatio(task.ratio!.toStringAsFixed(2)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10.5, color: t.text3),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 96,
                child: Text(
                  task.sourceName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: t.text2),
                ),
              ),
              SizedBox(width: 80, child: _StatePill(status: task.status)),
              SizedBox(
                width: 150,
                child: Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: task.progress,
                          minHeight: 5,
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
                    SizedBox(
                      width: 30,
                      child: Text(
                        '${(task.progress * 100).toStringAsFixed(0)}%',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 11,
                          color: t.text3,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 92,
                child: Text(
                  task.downloadSpeed > 0
                      ? '↓${formatSpeed(task.downloadSpeed)}'
                      : '—',
                  style: TextStyle(
                    fontSize: 12,
                    color: task.downloadSpeed > 0 ? t.accentBright : t.text3,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              SizedBox(
                width: 92,
                child: Text(
                  task.uploadSpeed > 0
                      ? '↑${formatSpeed(task.uploadSpeed)}'
                      : '—',
                  style: TextStyle(
                    fontSize: 12,
                    color: t.text2,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              SizedBox(
                width: 72,
                child: Text(
                  formatBytes(task.totalBytes),
                  style: TextStyle(
                    fontSize: 12,
                    color: t.text2,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              SizedBox(
                width: 64,
                child: Text(
                  formatEta(task.etaSeconds),
                  style: TextStyle(fontSize: 12, color: t.text2),
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
    final l = AppLocalizations.of(context);
    return DesktopComingSoon(
      icon: Icons.download_outlined,
      message: l.dlPageEmptyClientsHint,
    );
  }
}

class _EmptyTasks extends StatelessWidget {
  const _EmptyTasks({required this.t});
  final DesignTokens t;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
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
              l.dlPageNoTasksUnderFilter,
              style: TextStyle(fontSize: 13, color: t.text2),
            ),
          ],
        ),
      ),
    );
  }
}


enum _BatchOp { pause, resume, delete }

/// qBittorrent 全局限速对话框：读取当前限速（KB/s）回填，可编辑后下发。
class _GlobalLimitDialog extends ConsumerStatefulWidget {
  const _GlobalLimitDialog({required this.sourceId});
  final String sourceId;

  @override
  ConsumerState<_GlobalLimitDialog> createState() => _GlobalLimitDialogState();
}

class _GlobalLimitDialogState extends ConsumerState<_GlobalLimitDialog> {
  final _dl = TextEditingController();
  final _up = TextEditingController();
  bool _prefilled = false;
  bool _saving = false;

  @override
  void dispose() {
    _dl.dispose();
    _up.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final l = AppLocalizations.of(context);
    setState(() => _saving = true);
    final dl = (int.tryParse(_dl.text.trim()) ?? 0) * 1024;
    final up = (int.tryParse(_up.text.trim()) ?? 0) * 1024;
    try {
      await ref
          .read(qbittorrentActionsProvider(widget.sourceId))
          .setGlobalSpeedLimits(dlLimit: dl, upLimit: up);
      ref.invalidate(qbPreferencesProvider(widget.sourceId));
      if (mounted) {
        Navigator.of(context).pop();
        context.showSuccessToast(l.dlPageGlobalLimitUpdated);
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        context.showErrorToast(l.dlPageSaveFailed(e.toString()));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // 首次拿到偏好时按 KB/s 回填输入框。
    ref.watch(qbPreferencesProvider(widget.sourceId)).whenData((p) {
      if (!_prefilled && p != null) {
        _prefilled = true;
        _dl.text = (p.dlLimit / 1024).round().toString();
        _up.text = (p.upLimit / 1024).round().toString();
      }
    });
    return AlertDialog(
      title: Text(l.dlPageGlobalRateLimit),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.dlPageRateLimitUnitHint, style: const TextStyle(fontSize: 12.5)),
          const SizedBox(height: 14),
          TextField(
            controller: _dl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
                labelText: l.dlPageDownloadLimitLabel, isDense: true),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _up,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
                labelText: l.dlPageUploadLimitLabel, isDense: true),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l.dlPageCancel)),
        FilledButton(
          onPressed: _saving ? null : _apply,
          child: Text(l.dlPageApply),
        ),
      ],
    );
  }
}

/// 多选批量操作条：选中任意任务后出现，跨客户端批量暂停/继续/删除。
class _BatchBar extends StatelessWidget {
  const _BatchBar({
    required this.count,
    required this.onPause,
    required this.onResume,
    required this.onDelete,
    required this.onClear,
  });

  final int count;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onDelete;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          Text(
            l.dlPageSelectedCount(count),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: t.text0,
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: onResume,
            icon: const Icon(Icons.play_arrow_rounded, size: 16),
            label: Text(l.dlPageResume),
          ),
          TextButton.icon(
            onPressed: onPause,
            icon: const Icon(Icons.pause_rounded, size: 16),
            label: Text(l.dlPagePause),
          ),
          TextButton.icon(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded, size: 16),
            label: Text(l.dlPageDelete),
          ),
          const SizedBox(width: 6),
          IconButton(
            onPressed: onClear,
            tooltip: l.dlPageClearSelection,
            icon: Icon(Icons.close_rounded, size: 16, color: t.text2),
          ),
        ],
      ),
    );
  }
}
