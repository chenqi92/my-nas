import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/music/data/services/duplicate_detector.dart';
import 'package:my_nas/features/music/data/services/music_database_service.dart';
import 'package:my_nas/shared/widgets/rounded_back_button.dart';

/// 重复歌曲检测页：扫描整个 library，按 (title, artist, duration±2s) 桶分组，
/// 每组里按 lossless + size 评分排序。第一项推荐保留，其余推荐删除。
///
/// 删除操作仅清理本地元数据库索引，不会动到 NAS 上的真实文件。
class DuplicateSongsPage extends ConsumerStatefulWidget {
  const DuplicateSongsPage({super.key});

  @override
  ConsumerState<DuplicateSongsPage> createState() =>
      _DuplicateSongsPageState();
}

class _DuplicateSongsPageState extends ConsumerState<DuplicateSongsPage> {
  final _db = MusicDatabaseService();
  List<DuplicateGroup>? _groups;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    try {
      await _db.init();
      // 一次性拉全表（曲目通常 < 1 万条；分页扫描复杂度过高）
      final all = await _db.getPage(limit: 100000);
      final groups = DuplicateDetector.detect(all);
      if (mounted) {
        setState(() {
          _groups = groups;
          _scanning = false;
        });
      }
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'duplicateSongsPage.scan');
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _deleteFromLibrary(MusicTrackEntity track) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.musicDuplicateRemoveDialogTitle),
        content: Text(
          ctx.l10n.musicDuplicateRemoveDialogContent(track.fileName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.musicDuplicateRemoveCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.l10n.musicDuplicateRemoveConfirm),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _db.delete(track.sourceId, track.filePath);
    await _scan();
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
          context.l10n.musicDuplicatePageTitle,
          style: TextStyle(
            color: isDark ? AppColors.darkOnSurface : null,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: IconThemeData(
          color: isDark ? AppColors.darkOnSurface : null,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _scanning ? null : _scan,
          ),
        ],
      ),
      body: _buildBody(isDark),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_scanning) {
      return const Center(child: CircularProgressIndicator());
    }
    final groups = _groups;
    if (groups == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_rounded,
              size: 64,
              color: Colors.green.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 12),
            Text(
              context.l10n.musicDuplicateEmptyMessage,
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              context.l10n.musicDuplicateEmptyHint,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
          ],
        ),
      );
    }
    final totalDup = groups.fold<int>(0, (a, g) => a + g.redundant.length);
    return Column(
      children: [
        Padding(
          padding: AppSpacing.paddingMd,
          child: Row(
            children: [
              Icon(
                Icons.content_copy_rounded,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                context.l10n.musicDuplicateSummary(groups.length, totalDup),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            itemCount: groups.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, i) =>
                _GroupCard(group: groups[i], isDark: isDark, onDelete: _deleteFromLibrary),
          ),
        ),
      ],
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.isDark,
    required this.onDelete,
  });
  final DuplicateGroup group;
  final bool isDark;
  final Future<void> Function(MusicTrackEntity) onDelete;

  @override
  Widget build(BuildContext context) => Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
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
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      group.artist,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  context.l10n.musicDuplicateVersionBadge(group.count),
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < group.tracks.length; i++)
            _TrackRow(
              track: group.tracks[i],
              isBest: i == 0,
              isDark: isDark,
              onDelete: () => onDelete(group.tracks[i]),
            ),
        ],
      ),
    );
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.track,
    required this.isBest,
    required this.isDark,
    required this.onDelete,
  });
  final MusicTrackEntity track;
  final bool isBest;
  final bool isDark;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final color = isBest
        ? Colors.green
        : (isDark ? Colors.white60 : Colors.black54);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            isBest ? Icons.star_rounded : Icons.audiotrack_rounded,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.fileName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        isBest ? FontWeight.w600 : FontWeight.normal,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${track.folderName} · ${track.displaySize}'
                  '${isBest ? ' · ${context.l10n.musicDuplicateRecommendKeep}' : ''}',
                  style: TextStyle(
                    fontSize: 10,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            color: isDark ? Colors.white54 : Colors.black54,
            tooltip: context.l10n.musicDuplicateRemoveTooltip,
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
