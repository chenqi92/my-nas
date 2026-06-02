import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/aria2/presentation/providers/aria2_provider.dart';
import 'package:my_nas/features/downloader/presentation/providers/downloader_aggregate_provider.dart';
import 'package:my_nas/features/qbittorrent/presentation/providers/qbittorrent_provider.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/transmission/presentation/providers/transmission_provider.dart';
import 'package:my_nas/shared/widgets/atoms/app_tag.dart';
import 'package:my_nas/shared/widgets/atoms/glass_panel.dart';
import 'package:my_nas/shared/widgets/atoms/status_dot.dart';

/// 下载任务详情浮层（设计稿 dialogs.jsx · DownloadDetail）。
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

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
        child: GlassPanel(
          strong: true,
          padding: EdgeInsets.zero,
          child: task == null
              ? _Gone(t: t, onClose: () => Navigator.of(context).pop())
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(
                      task: task,
                      t: t,
                      onClose: () => Navigator.of(context).pop(),
                    ),
                    Flexible(
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
                    AppTag(task.status.label),
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
    return Row(
      children: [
        _tile('↓ 下行', formatSpeed(task.downloadSpeed), t.accentBright),
        _tile('↑ 上行', formatSpeed(task.uploadSpeed), t.text0),
        _tile('剩余', formatEta(task.etaSeconds), t.text0),
        if (task.ratio != null)
          _tile('分享率', task.ratio!.toStringAsFixed(2), t.text0),
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
          _row('保存位置', task.savePath ?? '—'),
          const SizedBox(height: 8),
          _row('任务 ID', task.taskId),
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
            label: const Text('删除任务'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => _remove(context, deleteFiles: true),
            icon: const Icon(Icons.delete_forever_rounded, size: 15),
            label: const Text('删除并清文件'),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: () => _toggle(context, resume: paused),
            icon: Icon(
              paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              size: 16,
            ),
            label: Text(paused ? '继续' : '暂停'),
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
      if (context.mounted) context.showErrorToast('操作失败：$e');
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
      if (context.mounted) context.showErrorToast('删除失败：$e');
    }
  }
}

class _Gone extends StatelessWidget {
  const _Gone({required this.t, required this.onClose});
  final DesignTokens t;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.task_alt_rounded, size: 40, color: t.text3),
          const SizedBox(height: 12),
          Text(
            '任务已结束或被移除。',
            style: TextStyle(fontSize: 13.5, color: t.text2),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: onClose, child: const Text('关闭')),
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
