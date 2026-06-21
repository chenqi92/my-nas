import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/music/data/services/playlist_service.dart';
import 'package:my_nas/features/music/presentation/providers/playlist_provider.dart';
import 'package:my_nas/shared/widgets/rounded_back_button.dart';

/// 回收站页：显示已软删除的播放列表，30 天后自动清理。支持恢复 / 永久删除。
///
/// 当前仅接入音乐播放列表；其它模块（书架、PT 站、源等）待后续按相同模式接入。
class RecycleBinPage extends ConsumerStatefulWidget {
  const RecycleBinPage({super.key});

  @override
  ConsumerState<RecycleBinPage> createState() => _RecycleBinPageState();
}

class _RecycleBinPageState extends ConsumerState<RecycleBinPage> {
  final _service = PlaylistService();
  List<PlaylistEntry>? _items;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _service.getDeletedPlaylists();
    if (mounted) {
      setState(() {
        _items = list;
        _loading = false;
      });
    }
  }

  Future<void> _restore(PlaylistEntry p) async {
    await _service.restorePlaylist(p.id);
    // 通知 playlist provider 刷新
    await ref.read(playlistProvider.notifier).refresh();
    await _load();
  }

  Future<void> _purge(PlaylistEntry p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.musicRecycleBinDeleteConfirmTitle),
        content: Text(ctx.l10n.musicRecycleBinDeleteConfirmContent(p.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.musicRecycleBinDeleteCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.l10n.musicRecycleBinDeleteConfirm),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _service.purgePlaylist(p.id);
    await _load();
  }

  String _daysLeft(PlaylistEntry p) {
    final remaining = PlaylistService.retentionPeriod -
        DateTime.now().difference(p.deletedAt!);
    final days = remaining.inDays;
    if (days < 0) return context.l10n.musicRecycleBinRetentionExpiring;
    return context.l10n.musicRecycleBinRetentionDays(days);
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
          context.l10n.musicRecycleBinTitle,
          style: TextStyle(
            color: isDark ? AppColors.darkOnSurface : null,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: IconThemeData(
          color: isDark ? AppColors.darkOnSurface : null,
        ),
      ),
      body: _buildBody(isDark),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final items = _items;
    if (items == null) return const Center(child: CircularProgressIndicator());
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.delete_outline_rounded,
              size: 64,
              color: isDark ? Colors.white24 : Colors.black26,
            ),
            const SizedBox(height: 12),
            Text(
              context.l10n.musicRecycleBinEmptyTitle,
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              context.l10n.musicRecycleBinEmptySubtitle,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: AppSpacing.paddingMd,
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, i) {
        final p = items[i];
        return Container(
          padding: AppSpacing.paddingMd,
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.black.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                Icons.queue_music_rounded,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    Text(
                      '${context.l10n.musicRecycleBinItemCount(p.trackCount)} · ${_daysLeft(p)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.restore_rounded),
                tooltip: context.l10n.musicRecycleBinRestoreTooltip,
                onPressed: () => _restore(p),
              ),
              IconButton(
                icon: const Icon(Icons.delete_forever_rounded),
                tooltip: context.l10n.musicRecycleBinDeleteTooltip,
                onPressed: () => _purge(p),
              ),
            ],
          ),
        );
      },
    );
  }
}
