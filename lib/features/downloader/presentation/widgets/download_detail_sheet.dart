import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/aria2/presentation/providers/aria2_provider.dart';
import 'package:my_nas/features/downloader/presentation/providers/downloader_aggregate_provider.dart';
import 'package:my_nas/features/qbittorrent/presentation/providers/qbittorrent_provider.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/transmission/presentation/providers/transmission_provider.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/shared/widgets/atoms/app_tag.dart';
import 'package:my_nas/shared/widgets/atoms/status_dot.dart';

/// 打开下载任务详情右侧抽屉（设计稿 dialogs.jsx · DownloadDetail，右侧 drawer）。
Future<void> showDownloadDetailDrawer(BuildContext context, String taskKey) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: AppLocalizations.of(context).dlDetailBarrierLabel,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, _, _) =>
        Align(alignment: Alignment.centerRight, child: DownloadDetailSheet(taskKey: taskKey)),
    transitionBuilder: (_, anim, _, child) => SlideTransition(
      position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
          .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

/// 下载任务详情抽屉内容（设计稿 dialogs.jsx · DownloadDetail）。
///
/// 复用 [UnifiedDownloadTask]，按 sourceId 实时跟随 aggregate provider，
/// 提供 暂停 / 继续 / 删除（可选删文件）等操作，跨 aria2 / qBittorrent /
/// Transmission 统一分发。
class DownloadDetailSheet extends ConsumerWidget {
  const DownloadDetailSheet({required this.taskKey, super.key});

  /// [UnifiedDownloadTask.uniqueKey]，浮层据此从最新列表里取实时快照。
  final String taskKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DesignTokens.of(context);
    final tasks = ref.watch(aggregatedDownloadTasksProvider);
    final task = tasks.where((e) => e.uniqueKey == taskKey).firstOrNull;

    return Material(
      color: t.panelBgStrong,
      child: Container(
        width: 440,
        height: double.infinity,
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: t.hairline)),
        ),
        child: SafeArea(
          child: task == null
              ? _Gone(t: t, onClose: () => Navigator.of(context).pop())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(
                      task: task,
                      t: t,
                      onClose: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 22, vertical: 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Progress(task: task, t: t),
                            const SizedBox(height: 18),
                            _Stats(task: task, t: t),
                            const SizedBox(height: 18),
                            _Meta(task: task, t: t),
                            if (task.sourceType ==
                                SourceType.qbittorrent) ...[
                              const SizedBox(height: 18),
                              _Files(task: task, t: t),
                            ],
                          ],
                        ),
                      ),
                    ),
                    _Actions(task: task, ref: ref, t: t),
                  ],
                ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.task, required this.t, required this.onClose});
  final UnifiedDownloadTask task;
  final DesignTokens t;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 18, 14, 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.hairline)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: StatusDot(_dot(task.status)),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: t.text0,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    AppTag(task.status.label(l)),
                    AppTag(task.sourceType.displayName,
                        variant: TagVariant.neutral),
                    AppTag(task.sourceName, variant: TagVariant.free),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onClose,
            icon: Icon(Icons.close_rounded, size: 16, color: t.text2),
          ),
        ],
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.task, required this.t});
  final UnifiedDownloadTask task;
  final DesignTokens t;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '${(task.progress * 100).toStringAsFixed(1)}%',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: t.text0,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const Spacer(),
            Text(
              '${formatBytes(task.completedBytes)} / ${formatBytes(task.totalBytes)}',
              style: TextStyle(fontSize: 12.5, color: t.text2),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: task.progress,
            minHeight: 8,
            backgroundColor: t.insetBg,
            valueColor: AlwaysStoppedAnimation(t.accent),
          ),
        ),
      ],
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.task, required this.t});
  final UnifiedDownloadTask task;
  final DesignTokens t;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Row(
      children: [
        _tile(l.dlDetailDownSpeed, formatSpeed(task.downloadSpeed),
            t.accentBright),
        _tile(l.dlDetailUpSpeed, formatSpeed(task.uploadSpeed), t.text0),
        _tile(l.dlDetailRemaining, formatEta(task.etaSeconds), t.text0),
        if (task.ratio != null)
          _tile(l.dlDetailRatio, task.ratio!.toStringAsFixed(2), t.text0),
      ],
    );
  }

  Widget _tile(String label, String value, Color color) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 11.5, color: t.text2)),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      );
}

class _Meta extends StatelessWidget {
  const _Meta({required this.task, required this.t});
  final UnifiedDownloadTask task;
  final DesignTokens t;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.cardBg,
        border: Border.all(color: t.cardBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row(l.dlDetailSavePath, task.savePath ?? '—'),
          const SizedBox(height: 8),
          _row(l.dlDetailTaskId, task.taskId),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(label,
                style: TextStyle(fontSize: 12, color: t.text2)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: t.text1,
                fontFamily: 'SF Mono',
                fontFamilyFallback: const ['Menlo'],
              ),
            ),
          ),
        ],
      );
}

class _Actions extends StatelessWidget {
  const _Actions({required this.task, required this.ref, required this.t});
  final UnifiedDownloadTask task;
  final WidgetRef ref;
  final DesignTokens t;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final paused = task.status == UnifiedDownloadStatus.paused;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.hairline)),
      ),
      child: Row(
        children: [
          OutlinedButton.icon(
            onPressed: () => _remove(context, deleteFiles: false),
            icon: const Icon(Icons.delete_outline_rounded, size: 15),
            label: Text(l.dlDetailDeleteTask),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => _remove(context, deleteFiles: true),
            icon: const Icon(Icons.delete_forever_rounded, size: 15),
            label: Text(l.dlDetailDeleteWithFiles),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: () => _toggle(context, resume: paused),
            icon: Icon(
              paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              size: 16,
            ),
            label: Text(paused ? l.dlDetailResume : l.dlDetailPause),
          ),
        ],
      ),
    );
  }

  Future<void> _toggle(BuildContext context, {required bool resume}) async {
    try {
      switch (task.sourceType) {
        case SourceType.aria2:
          final a = ref.read(aria2ActionsProvider(task.sourceId));
          resume ? await a.resume(task.taskId) : await a.pause(task.taskId);
        case SourceType.qbittorrent:
          final a = ref.read(qbittorrentActionsProvider(task.sourceId));
          resume
              ? await a.resume([task.taskId])
              : await a.pause([task.taskId]);
        case SourceType.transmission:
          final a = ref.read(transmissionActionsProvider(task.sourceId));
          final id = int.tryParse(task.taskId);
          if (id != null) {
            resume ? await a.start([id]) : await a.stop([id]);
          }
        default:
          break;
      }
    } on Object catch (e) {
      if (context.mounted) {
        context.showErrorToast(
          AppLocalizations.of(context).dlDetailOpFailed('$e'),
        );
      }
    }
  }

  Future<void> _remove(BuildContext context,
      {required bool deleteFiles}) async {
    try {
      switch (task.sourceType) {
        case SourceType.aria2:
          await ref.read(aria2ActionsProvider(task.sourceId)).remove(task.taskId);
        case SourceType.qbittorrent:
          await ref
              .read(qbittorrentActionsProvider(task.sourceId))
              .delete([task.taskId], deleteFiles: deleteFiles);
        case SourceType.transmission:
          final id = int.tryParse(task.taskId);
          if (id != null) {
            await ref
                .read(transmissionActionsProvider(task.sourceId))
                .remove([id], deleteFiles: deleteFiles);
          }
        default:
          break;
      }
      if (context.mounted) Navigator.of(context).pop();
    } on Object catch (e) {
      if (context.mounted) {
        context.showErrorToast(
          AppLocalizations.of(context).dlDetailDeleteFailed('$e'),
        );
      }
    }
  }
}

class _Gone extends StatelessWidget {
  const _Gone({required this.t, required this.onClose});
  final DesignTokens t;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.task_alt_rounded, size: 40, color: t.text3),
          const SizedBox(height: 12),
          Text(
            l.dlDetailGone,
            style: TextStyle(fontSize: 13.5, color: t.text2),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: onClose, child: Text(l.dlDetailClose)),
        ],
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

/// qBittorrent 任务的文件列表（接 qbTorrentFilesProvider 真实数据）。
class _Files extends ConsumerWidget {
  const _Files({required this.task, required this.t});
  final UnifiedDownloadTask task;
  final DesignTokens t;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final filesAsync =
        ref.watch(qbTorrentFilesProvider((task.sourceId, task.taskId)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.dlDetailFilesTitle,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: t.text3,
          ),
        ),
        const SizedBox(height: 10),
        filesAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (e, _) => Text(l.dlDetailFilesLoadError,
              style: TextStyle(fontSize: 12.5, color: t.text3)),
          data: (files) {
            if (files.isEmpty) {
              return Text(l.dlDetailNoFiles,
                  style: TextStyle(fontSize: 12.5, color: t.text3));
            }
            return Column(
              children: [
                for (final f in files)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            f.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12.5, color: t.text1),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${(f.progress * 100).round()}% · ${formatBytes(f.size)}',
                          style: TextStyle(fontSize: 11, color: t.text3),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
