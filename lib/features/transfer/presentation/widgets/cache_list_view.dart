import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/transfer/domain/entities/transfer_task.dart';
import 'package:my_nas/features/transfer/presentation/providers/transfer_provider.dart';

/// 缓存列表视图
class CacheListView extends ConsumerWidget {
  const CacheListView({
    super.key,
    required this.activeTasks,
    required this.onDeleteCache,
    required this.onClearAll,
  });

  /// 正在进行的缓存任务
  final List<TransferTask> activeTasks;

  /// 删除缓存回调
  final Future<void> Function(CachedMediaItem item) onDeleteCache;

  /// 清空所有缓存回调
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cachedItemsAsync = ref.watch(allCachedItemsProvider);

    return cachedItemsAsync.when(
      data: (cachedItems) => _buildContent(
        context,
        ref,
        cachedItems,
        theme,
        colorScheme,
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => _buildEmptyState(context),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    List<CachedMediaItem> cachedItems,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    // 按媒体类型分组已缓存的内容
    final groupedCache = <MediaType, List<CachedMediaItem>>{};
    for (final item in cachedItems) {
      groupedCache.putIfAbsent(item.mediaType, () => []).add(item);
    }

    if (activeTasks.isEmpty && cachedItems.isEmpty) {
      return _buildEmptyState(context);
    }

    return CustomScrollView(
      slivers: [
        // 缓存统计
        SliverToBoxAdapter(
          child: _buildCacheStats(context, ref),
        ),

        // 正在缓存的任务
        if (activeTasks.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                context.l10n.cacheListViewCaching,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final task = activeTasks[index];
                return _buildActiveCacheItem(context, task);
              },
              childCount: activeTasks.length,
            ),
          ),
        ],

        // 已缓存的内容
        if (cachedItems.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Text(
                    context.l10n.cacheListViewCached,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: onClearAll,
                    child: Text(context.l10n.cacheListViewClearAll),
                  ),
                ],
              ),
            ),
          ),

          // 按媒体类型显示
          for (final entry in groupedCache.entries) ...[
            SliverToBoxAdapter(
              child: _buildMediaTypeHeader(context, entry.key, entry.value.length),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final item = entry.value[index];
                  return _buildCachedItem(context, item);
                },
                childCount: entry.value.length,
              ),
            ),
          ],
        ],

        const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.storage_outlined,
            size: 64,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            context.l10n.cacheListViewEmpty,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.cacheListViewEmptyHint,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCacheStats(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statsAsync = ref.watch(cacheStatsProvider);

    return statsAsync.when(
      data: (stats) {
        var totalCount = 0;
        var totalSize = 0;
        for (final entry in stats.entries) {
          totalCount += entry.value.count;
          totalSize += entry.value.size;
        }

        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.cacheListViewUsed,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatBytes(totalSize),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: colorScheme.outlineVariant,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.cacheListViewCount,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.l10n.cacheListViewCountValue(totalCount),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  Widget _buildMediaTypeHeader(
    BuildContext context,
    MediaType mediaType,
    int count,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final (icon, label) = switch (mediaType) {
      MediaType.photo => (Icons.photo_library, context.l10n.cacheListViewMediaTypePhoto),
      MediaType.music => (Icons.music_note, context.l10n.cacheListViewMediaTypeMusic),
      MediaType.video => (Icons.movie, context.l10n.cacheListViewMediaTypeVideo),
      MediaType.book => (Icons.book, context.l10n.cacheListViewMediaTypeBook),
      MediaType.comic => (Icons.menu_book, context.l10n.cacheListViewMediaTypeComic),
      MediaType.note => (Icons.note, context.l10n.cacheListViewMediaTypeNote),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '($count)',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveCacheItem(BuildContext context, TransferTask task) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    task.fileName,
                    style: theme.textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  task.progressText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: task.progress,
                minHeight: 4,
                backgroundColor: colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              task.sizeProgressText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCachedItem(BuildContext context, CachedMediaItem item) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dismissible(
      key: ValueKey('${item.sourceId}_${item.sourcePath}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: colorScheme.error,
        child: Icon(Icons.delete_rounded, color: colorScheme.onError),
      ),
      onDismissed: (_) => onDeleteCache(item),
      child: ListTile(
        leading: Icon(
          _getMediaTypeIcon(item.mediaType),
          color: colorScheme.onSurfaceVariant,
        ),
        title: Text(
          item.displayTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(item.fileSizeText),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: () => onDeleteCache(item),
        ),
      ),
    );
  }

  IconData _getMediaTypeIcon(MediaType mediaType) => switch (mediaType) {
        MediaType.photo => Icons.photo_rounded,
        MediaType.music => Icons.audiotrack,
        MediaType.video => Icons.videocam,
        MediaType.book => Icons.book,
        MediaType.comic => Icons.menu_book,
        MediaType.note => Icons.note,
      };

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
