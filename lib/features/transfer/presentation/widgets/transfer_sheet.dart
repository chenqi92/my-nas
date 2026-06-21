import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/transfer/data/services/cache_config_service.dart';
import 'package:my_nas/features/transfer/domain/entities/transfer_task.dart';
import 'package:my_nas/features/transfer/presentation/providers/transfer_provider.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';
import 'package:my_nas/shared/widgets/sheet_drag_handle.dart';

/// 传输类型
enum TransferSheetType {
  download,
  upload,
  cache,
}

/// 显示下载任务列表
void showTransferDownloads(BuildContext context) {
  _showTransferSheet(context, TransferSheetType.download);
}

/// 显示上传任务列表
void showTransferUploads(BuildContext context) {
  _showTransferSheet(context, TransferSheetType.upload);
}

/// 显示缓存列表
void showTransferCache(BuildContext context) {
  _showTransferSheet(context, TransferSheetType.cache);
}

void _showTransferSheet(BuildContext context, TransferSheetType type) {
  showAdaptiveModalSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _TransferSheet(type: type),
  );
}

class _TransferSheet extends ConsumerWidget {
  const _TransferSheet({required this.type});

  final TransferSheetType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final tasks = switch (type) {
      TransferSheetType.download => ref.watch(downloadTasksProvider),
      TransferSheetType.upload => ref.watch(uploadTasksProvider),
      TransferSheetType.cache => ref.watch(cacheTasksProvider),
    };

    final (icon, title, emptyIcon, emptyText) = switch (type) {
      TransferSheetType.download => (
          Icons.download_rounded,
          context.l10n.transferSheetDownloadTitle,
          Icons.download_done_rounded,
          context.l10n.transferSheetDownloadEmpty,
        ),
      TransferSheetType.upload => (
          Icons.upload_rounded,
          context.l10n.transferSheetUploadTitle,
          Icons.cloud_upload_outlined,
          context.l10n.transferSheetUploadEmpty,
        ),
      TransferSheetType.cache => (
          Icons.storage_rounded,
          context.l10n.transferSheetCacheTitle,
          Icons.storage_outlined,
          context.l10n.transferSheetCacheEmpty,
        ),
    };

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkSurface.withValues(alpha: 0.95)
                  : AppColors.lightSurface.withValues(alpha: 0.98),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(
                top: BorderSide(
                  color: isDark ? AppColors.glassStroke : AppColors.lightOutline.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: Column(
              children: [
                // 拖动指示器
                const SheetDragHandle(),
                // 标题栏
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(icon, color: AppColors.primary, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        title,
                        style: context.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppColors.darkOnSurface : null,
                        ),
                      ),
                      const Spacer(),
                      _buildClearButton(context, ref, isDark, tasks),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: Divider(
                    height: 1,
                    color: isDark
                        ? AppColors.darkOutline.withValues(alpha: 0.2)
                        : AppColors.lightOutline.withValues(alpha: 0.3),
                  ),
                ),
                // 缓存统计（仅缓存类型显示）
                if (type == TransferSheetType.cache) _CacheStats(isDark: isDark),
                // 内容区域
                Expanded(
                  child: type == TransferSheetType.cache
                      ? _CacheContent(
                          scrollController: scrollController,
                          isDark: isDark,
                          activeTasks: tasks.where((t) => !t.isCompleted).toList(),
                          emptyIcon: emptyIcon,
                          emptyText: emptyText,
                        )
                      : tasks.isEmpty
                          ? _buildEmptyState(context, isDark, emptyIcon, emptyText)
                          : _buildTaskList(context, ref, scrollController, tasks, isDark),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildClearButton(
    BuildContext context,
    WidgetRef ref,
    bool isDark,
    List<TransferTask> tasks,
  ) {
    final hasCompleted = tasks.any((t) => t.isCompleted);
    if (!hasCompleted && type != TransferSheetType.cache) {
      return const SizedBox.shrink();
    }

    final buttonText = type == TransferSheetType.cache ? context.l10n.transferSheetClearCacheButton : context.l10n.transferSheetClearCompletedButton;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _handleClear(context, ref),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.darkSurfaceVariant.withValues(alpha: 0.5)
                : AppColors.lightSurfaceVariant,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            buttonText,
            style: context.textTheme.labelMedium?.copyWith(
              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleClear(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(transferTasksProvider.notifier);

    if (type == TransferSheetType.cache) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.transferSheetClearCacheDialogTitle),
          content: Text(context.l10n.transferSheetClearCacheDialogMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.transferSheetCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.transferSheetConfirm),
            ),
          ],
        ),
      );
      if (confirmed ?? false) {
        await notifier.clearAllCache();
      }
    } else if (type == TransferSheetType.download) {
      await notifier.clearCompletedDownloads();
    } else {
      await notifier.clearCompletedUploads();
    }
  }

  Widget _buildEmptyState(
    BuildContext context,
    bool isDark,
    IconData icon,
    String text,
  ) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: AppColors.success),
            ),
            const SizedBox(height: 16),
            Text(
              text,
              style: context.textTheme.titleMedium?.copyWith(
                color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              type == TransferSheetType.cache ? context.l10n.transferSheetOfflineAccessHint : context.l10n.transferSheetTaskCompletionHint,
              style: context.textTheme.bodyMedium?.copyWith(
                color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
              ),
            ),
          ],
        ),
      );

  Widget _buildTaskList(
    BuildContext context,
    WidgetRef ref,
    ScrollController scrollController,
    List<TransferTask> tasks,
    bool isDark,
  ) {
    // 按状态排序
    final sortedTasks = List<TransferTask>.from(tasks)
      ..sort((a, b) {
        final statusOrder = {
          TransferStatus.transferring: 0,
          TransferStatus.queued: 1,
          TransferStatus.pending: 2,
          TransferStatus.paused: 3,
          TransferStatus.failed: 4,
          TransferStatus.completed: 5,
          TransferStatus.cancelled: 6,
        };
        final aOrder = statusOrder[a.status] ?? 99;
        final bOrder = statusOrder[b.status] ?? 99;
        if (aOrder != bOrder) return aOrder.compareTo(bOrder);
        return b.createdAt.compareTo(a.createdAt);
      });

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: sortedTasks.length,
      itemBuilder: (context, index) => _TransferTaskTile(
        task: sortedTasks[index],
        isDark: isDark,
        type: type,
      ),
    );
  }
}

/// 缓存内容区域 - 使用真实缓存项
class _CacheContent extends ConsumerWidget {
  const _CacheContent({
    required this.scrollController,
    required this.isDark,
    required this.activeTasks,
    required this.emptyIcon,
    required this.emptyText,
  });

  final ScrollController scrollController;
  final bool isDark;
  final List<TransferTask> activeTasks;
  final IconData emptyIcon;
  final String emptyText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cachedItemsAsync = ref.watch(allCachedItemsProvider);

    return cachedItemsAsync.when(
      data: (cachedItems) {
        if (activeTasks.isEmpty && cachedItems.isEmpty) {
          return _buildEmptyState(context);
        }

        // 按媒体类型分组
        final groupedCache = <MediaType, List<CachedMediaItem>>{};
        for (final item in cachedItems) {
          groupedCache.putIfAbsent(item.mediaType, () => []).add(item);
        }

        return CustomScrollView(
          controller: scrollController,
          slivers: [
            // 正在缓存的任务
            if (activeTasks.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Text(
                    context.l10n.transferSheetCachingSection,
                    style: context.textTheme.titleSmall?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: _TransferTaskTile(
                      task: activeTasks[index],
                      isDark: isDark,
                      type: TransferSheetType.cache,
                    ),
                  ),
                  childCount: activeTasks.length,
                ),
              ),
            ],

            // 已缓存的内容
            if (cachedItems.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    context.l10n.transferSheetCachedSection,
                    style: context.textTheme.titleSmall?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
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
                    (context, index) => _CachedItemTile(
                      item: entry.value[index],
                      isDark: isDark,
                    ),
                    childCount: entry.value.length,
                  ),
                ),
              ],
            ],

            const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => _buildEmptyState(context),
    );
  }

  Widget _buildEmptyState(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(emptyIcon, size: 40, color: AppColors.success),
            ),
            const SizedBox(height: 16),
            Text(
              emptyText,
              style: context.textTheme.titleMedium?.copyWith(
                color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.transferSheetOfflineAccessHint,
              style: context.textTheme.bodyMedium?.copyWith(
                color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
              ),
            ),
          ],
        ),
      );

  Widget _buildMediaTypeHeader(BuildContext context, MediaType mediaType, int count) {
    final (icon, label) = switch (mediaType) {
      MediaType.photo => (Icons.photo_library, context.l10n.transferSheetPhotoLabel),
      MediaType.music => (Icons.music_note, context.l10n.transferSheetMusicLabel),
      MediaType.video => (Icons.movie, context.l10n.transferSheetVideoLabel),
      MediaType.book => (Icons.book, context.l10n.transferSheetBookLabel),
      MediaType.comic => (Icons.menu_book, context.l10n.transferSheetComicLabel),
      MediaType.note => (Icons.note, context.l10n.transferSheetNoteLabel),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: context.textTheme.bodyMedium?.copyWith(
              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '($count)',
            style: context.textTheme.bodySmall?.copyWith(
              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 缓存项卡片
class _CachedItemTile extends ConsumerWidget {
  const _CachedItemTile({
    required this.item,
    required this.isDark,
  });

  final CachedMediaItem item;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(transferTasksProvider.notifier);

    return Dismissible(
      key: ValueKey('${item.sourceId}_${item.sourcePath}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: AppColors.error,
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      onDismissed: (_) => notifier.deleteCache(item.sourceId, item.sourcePath),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.darkSurfaceVariant.withValues(alpha: 0.3)
              : AppColors.lightSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark
                ? AppColors.darkOutline.withValues(alpha: 0.2)
                : AppColors.lightOutline.withValues(alpha: 0.3),
          ),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _getMediaTypeColor(item.mediaType).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _getMediaTypeIcon(item.mediaType),
              color: _getMediaTypeColor(item.mediaType),
              size: 20,
            ),
          ),
          title: Text(
            item.displayTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color: isDark ? AppColors.darkOnSurface : null,
            ),
          ),
          subtitle: Text(
            item.fileSizeText,
            style: context.textTheme.bodySmall?.copyWith(
              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
            ),
          ),
          trailing: _buildDeleteButton(context, notifier),
        ),
      ),
    );
  }

  Widget _buildDeleteButton(
    BuildContext context,
    TransferTasksNotifier notifier,
  ) =>
      Tooltip(
        message: context.l10n.transferSheetDeleteCacheTooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => notifier.deleteCache(item.sourceId, item.sourcePath),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.darkSurfaceElevated
                    : AppColors.lightSurfaceVariant,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.delete_outline_rounded,
                size: 18,
                color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
              ),
            ),
          ),
        ),
      );

  IconData _getMediaTypeIcon(MediaType mediaType) => switch (mediaType) {
        MediaType.photo => Icons.photo_rounded,
        MediaType.music => Icons.audiotrack,
        MediaType.video => Icons.videocam,
        MediaType.book => Icons.book,
        MediaType.comic => Icons.menu_book,
        MediaType.note => Icons.note,
      };

  Color _getMediaTypeColor(MediaType mediaType) => switch (mediaType) {
        MediaType.photo => AppColors.fileImage,
        MediaType.music => AppColors.fileAudio,
        MediaType.video => AppColors.fileVideo,
        MediaType.book => AppColors.fileDocument,
        MediaType.comic => AppColors.fileDocument,
        MediaType.note => AppColors.fileDocument,
      };
}

/// 缓存统计
class _CacheStats extends ConsumerWidget {
  const _CacheStats({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            color: isDark
                ? AppColors.darkSurfaceVariant.withValues(alpha: 0.3)
                : AppColors.lightSurfaceVariant,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.transferSheetCacheUsageLabel,
                          style: context.textTheme.bodySmall?.copyWith(
                            color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatBytes(totalSize),
                          style: context.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isDark ? AppColors.darkOnSurface : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    color: isDark
                        ? AppColors.darkOutline.withValues(alpha: 0.3)
                        : AppColors.lightOutline.withValues(alpha: 0.3),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.transferSheetCacheCountLabel,
                            style: context.textTheme.bodySmall?.copyWith(
                              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            context.l10n.transferSheetCacheCountValue(totalCount),
                            style: context.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: isDark ? AppColors.darkOnSurface : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 缓存限制设置按钮
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _showCacheSettingsDialog(context, ref),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkSurfaceElevated.withValues(alpha: 0.5)
                          : AppColors.lightSurface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isDark
                            ? AppColors.darkOutline.withValues(alpha: 0.3)
                            : AppColors.lightOutline.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.settings_outlined,
                          size: 18,
                          color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          context.l10n.transferSheetCacheLimitSettings,
                          style: context.textTheme.bodyMedium?.copyWith(
                            color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                        ),
                      ],
                    ),
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

  Future<void> _showCacheSettingsDialog(BuildContext context, WidgetRef ref) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _CacheSettingsDialog(isDark: isDark),
    );
    // 刷新缓存统计
    ref.invalidate(cacheStatsProvider);
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// 缓存设置对话框
class _CacheSettingsDialog extends ConsumerStatefulWidget {
  const _CacheSettingsDialog({required this.isDark});

  final bool isDark;

  @override
  ConsumerState<_CacheSettingsDialog> createState() => _CacheSettingsDialogState();
}

class _CacheSettingsDialogState extends ConsumerState<_CacheSettingsDialog> {
  final _configService = CacheConfigService();
  final Map<MediaType, int> _cacheLimits = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    await _configService.init();
    final limits = await _configService.getAllCacheSizeLimits();
    if (mounted) {
      setState(() {
        _cacheLimits.addAll(limits);
        _isLoading = false;
      });
    }
  }

  Future<void> _updateLimit(MediaType type, int sizeMB) async {
    await _configService.setCacheSizeLimit(type, sizeMB);
    if (mounted) {
      setState(() {
        _cacheLimits[type] = sizeMB;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;

    return AlertDialog(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.storage_rounded, color: AppColors.primary, size: 18),
          ),
          const SizedBox(width: 12),
          Text(
            context.l10n.transferSheetCacheLimitSettings,
            style: context.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.darkOnSurface : null,
            ),
          ),
        ],
      ),
      content: _isLoading
          ? const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            )
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.l10n.transferSheetCacheLimitDescription,
                    style: context.textTheme.bodySmall?.copyWith(
                      color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ..._buildMediaTypeSettings(context),
                ],
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.transferSheetClose),
        ),
      ],
    );
  }

  List<Widget> _buildMediaTypeSettings(BuildContext context) {
    final isDark = widget.isDark;
    final mediaTypes = [
      (MediaType.photo, context.l10n.transferSheetPhotoLabel, Icons.photo_library_rounded),
      (MediaType.music, context.l10n.transferSheetMusicLabel, Icons.music_note_rounded),
      (MediaType.video, context.l10n.transferSheetVideoLabel, Icons.movie_rounded),
      (MediaType.book, context.l10n.transferSheetBookLabel, Icons.book_rounded),
      (MediaType.comic, context.l10n.transferSheetComicLabel, Icons.menu_book_rounded),
    ];

    return mediaTypes.map((item) {
      final (type, label, icon) = item;
      final currentLimit = _cacheLimits[type] ?? CacheConfigService.defaultCacheSizesMB[type] ?? 1024;

      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.darkSurfaceVariant.withValues(alpha: 0.3)
              : AppColors.lightSurfaceVariant,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: context.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: isDark ? AppColors.darkOnSurface : null,
                  ),
                ),
                const Spacer(),
                Text(
                  CacheConfigService.formatSizeMB(currentLimit),
                  style: context.textTheme.bodyMedium?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: CacheSizeOption.options.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final option = CacheSizeOption.options[index];
                  final isSelected = option.sizeMB == currentLimit;

                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _updateLimit(type, option.sizeMB),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primary
                              : (isDark
                                  ? AppColors.darkSurfaceElevated
                                  : AppColors.lightSurface),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary
                                : (isDark
                                    ? AppColors.darkOutline.withValues(alpha: 0.3)
                                    : AppColors.lightOutline.withValues(alpha: 0.3)),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          option.label,
                          style: context.textTheme.labelSmall?.copyWith(
                            color: isSelected
                                ? Colors.white
                                : (isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface),
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    }).toList();
  }
}

/// 传输任务卡片
class _TransferTaskTile extends ConsumerWidget {
  const _TransferTaskTile({
    required this.task,
    required this.isDark,
    required this.type,
  });

  final TransferTask task;
  final bool isDark;
  final TransferSheetType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(transferTasksProvider.notifier);
    final isActive = task.status == TransferStatus.transferring ||
        task.status == TransferStatus.queued ||
        task.status == TransferStatus.pending;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurfaceVariant.withValues(alpha: 0.3)
            : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? AppColors.darkOutline.withValues(alpha: 0.2)
              : AppColors.lightOutline.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 文件名和操作按钮
            Row(
              children: [
                _buildStatusIcon(context),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.fileName,
                        style: context.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: isDark ? AppColors.darkOnSurface : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (type == TransferSheetType.cache && task.isCompleted)
                        Text(
                          task.fileSizeText,
                          style: context.textTheme.bodySmall?.copyWith(
                            color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                _buildActionButton(context, notifier),
              ],
            ),
            // 进度条（仅活动任务显示）
            if (isActive) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: task.progress,
                  backgroundColor: isDark ? AppColors.darkSurfaceElevated : AppColors.lightSurfaceVariant,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    task.status == TransferStatus.paused ? AppColors.warning : AppColors.primary,
                  ),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    task.sizeProgressText,
                    style: context.textTheme.labelSmall?.copyWith(
                      color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                    ),
                  ),
                  Text(
                    task.progressText,
                    style: context.textTheme.labelSmall?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
            // 错误信息
            if (task.status == TransferStatus.failed && task.error != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 16, color: AppColors.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        task.error!,
                        style: context.textTheme.labelSmall?.copyWith(color: AppColors.error),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon(BuildContext context) {
    final (icon, color, showProgress) = switch (task.status) {
      TransferStatus.pending => (Icons.schedule_rounded, AppColors.warning, false),
      TransferStatus.queued => (Icons.queue_rounded, AppColors.info, false),
      TransferStatus.transferring => (null, AppColors.primary, true),
      TransferStatus.paused => (Icons.pause_circle_rounded, AppColors.warning, false),
      TransferStatus.completed => (Icons.check_circle_rounded, AppColors.success, false),
      TransferStatus.failed => (Icons.error_rounded, AppColors.error, false),
      TransferStatus.cancelled => (Icons.cancel_rounded, AppColors.fileOther, false),
    };

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: showProgress
          ? Padding(
              padding: const EdgeInsets.all(10),
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                value: task.progress,
                color: color,
              ),
            )
          : Icon(icon, color: color, size: 20),
    );
  }

  Widget _buildActionButton(BuildContext context, TransferTasksNotifier notifier) {
    // 缓存类型只显示删除按钮
    if (type == TransferSheetType.cache) {
      return _buildIconButton(
        context,
        icon: Icons.delete_outline_rounded,
        tooltip: '删除缓存',
        onTap: () => notifier.deleteCache(task.sourceId, task.sourcePath),
      );
    }

    final (icon, tooltip, onTap) = switch (task.status) {
      TransferStatus.pending || TransferStatus.queued => (
          Icons.close_rounded,
          context.l10n.transferSheetCancel,
          () => notifier.cancelTask(task.id),
        ),
      TransferStatus.transferring => (
          Icons.pause_rounded,
          context.l10n.transferSheetTaskPause,
          () => notifier.pauseTask(task.id),
        ),
      TransferStatus.paused => (
          Icons.play_arrow_rounded,
          context.l10n.transferSheetTaskResume,
          () => notifier.resumeTask(task.id),
        ),
      TransferStatus.completed => (
          Icons.delete_outline_rounded,
          context.l10n.transferSheetTaskDelete,
          () => notifier.deleteTask(task.id),
        ),
      TransferStatus.failed => (
          Icons.refresh_rounded,
          context.l10n.transferSheetTaskRetry,
          () => notifier.retryTask(task.id),
        ),
      TransferStatus.cancelled => (
          Icons.delete_outline_rounded,
          context.l10n.transferSheetTaskDelete,
          () => notifier.deleteTask(task.id),
        ),
    };

    return _buildIconButton(context, icon: icon, tooltip: tooltip, onTap: onTap);
  }

  Widget _buildIconButton(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) => Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurfaceElevated : AppColors.lightSurfaceVariant,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 18,
                color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
              ),
            ),
          ),
        ),
      );
}
