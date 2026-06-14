import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/sources/domain/entities/media_library.dart';
import 'package:my_nas/features/transfer/domain/entities/transfer_task.dart';
import 'package:my_nas/features/transfer/presentation/providers/transfer_provider.dart';
import 'package:my_nas/features/transfer/presentation/widgets/cache_list_view.dart';
import 'package:my_nas/features/transfer/presentation/widgets/transfer_task_tile.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/shared/mixins/tab_bar_visibility_mixin.dart';
import 'package:my_nas/shared/widgets/desktop_shell/desktop_page_scaffold.dart';
import 'package:my_nas/shared/widgets/rounded_back_button.dart';

/// 传输管理页面
class TransferManagerPage extends ConsumerStatefulWidget {
  const TransferManagerPage({super.key, this.initialTab = 0});

  /// 初始选中的 Tab（0: 下载, 1: 上传, 2: 缓存）
  final int initialTab;

  @override
  ConsumerState<TransferManagerPage> createState() => _TransferManagerPageState();
}

class _TransferManagerPageState extends ConsumerState<TransferManagerPage>
    with SingleTickerProviderStateMixin, ConsumerTabBarVisibilityMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    hideTabBar();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = ref.watch(transferTasksProvider);
    final uploadTasks = ref.watch(uploadTasksProvider);
    final downloadTasks = ref.watch(downloadTasksProvider);
    final cacheTasks = ref.watch(cacheTasksProvider);
    // 缓存角标与缓存列表同口径（均取 allCachedItemsProvider），不再用已完成
    // 缓存「任务」计数（任务可能已清除而缓存项仍在）。
    final cachedCount = ref.watch(allCachedItemsProvider).valueOrNull?.length ?? 0;
    final isDesktop = context.isDesktopLayout;

    final actions = <Widget>[
      PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert_rounded),
        onSelected: _handleMenuAction,
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'clear_completed_downloads',
            child: Text(l.transferPageClearCompletedDownloads),
          ),
          PopupMenuItem(
            value: 'clear_completed_uploads',
            child: Text(l.transferPageClearCompletedUploads),
          ),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'clear_all_cache',
            child: Text(l.transferPageClearAllCache),
          ),
        ],
      ),
    ];

    // 桌面：左 sidebar 替代 TabBar，让"下载/上传/缓存"垂直排列，
    // 右侧显示选中分类的内容。AppBar 收回三段 TabBar。
    if (isDesktop) {
      return DesktopPageScaffold(
        title: l.transferPageQueueTitle,
        subtitle: l.transferPageQueueSubtitle,
        maxWidth: 1500,
        actions: Row(mainAxisSize: MainAxisSize.min, children: actions),
        body: SizedBox(
          // DesktopPageScaffold 是 SingleChildScrollView，内部列表需有界高度：
          // 用视口高度减去页眉/留白估值，随窗口大小自适应。
          height: (context.screenHeight - 220).clamp(360.0, 1100.0),
          child: state.isLoading
              ? const Center(child: CircularProgressIndicator())
              : state.error != null
              ? _TransferError(
                  message: state.error!,
                  onRetry: () => ref.invalidate(transferTasksProvider),
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 180,
                      child: _buildDesktopSidebar(
                        downloadCount: downloadTasks.where(_isActive).length,
                        uploadCount: uploadTasks.where(_isActive).length,
                        cacheCount: cachedCount,
                      ),
                    ),
                    VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? AppColors.darkOutline.withValues(alpha: 0.3)
                          : Theme.of(context).colorScheme.outlineVariant,
                    ),
                    Expanded(
                      child: AnimatedBuilder(
                        animation: _tabController,
                        builder: (_, _) => IndexedStack(
                          index: _tabController.index,
                          children: [
                            _buildTaskList(
                              tasks: downloadTasks,
                              emptyIcon: Icons.download_done,
                              emptyText: l.transferPageNoDownloadTasks,
                            ),
                            _buildTaskList(
                              tasks: uploadTasks,
                              emptyIcon: Icons.cloud_upload_outlined,
                              emptyText: l.transferPageNoUploadTasks,
                            ),
                            CacheListView(
                              activeTasks: cacheTasks
                                  .where((t) => !t.isCompleted)
                                  .toList(),
                              onDeleteCache: _handleDeleteCacheItem,
                              onClearAll: _showClearCacheConfirmDialog,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: const RoundedBackButton(),
        title: Text(l.transferPageTitle),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            _buildTab(
              icon: Icons.download_rounded,
              label: l.transferPageTabDownload,
              count: downloadTasks.where(_isActive).length,
            ),
            _buildTab(
              icon: Icons.upload_rounded,
              label: l.transferPageTabUpload,
              count: uploadTasks.where(_isActive).length,
            ),
            _buildTab(
              icon: Icons.storage,
              label: l.transferPageTabCache,
              count: cachedCount,
            ),
          ],
        ),
        actions: actions,
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.error != null
              ? _TransferError(
                  message: state.error!,
                  onRetry: () => ref.invalidate(transferTasksProvider),
                )
              : TabBarView(
              controller: _tabController,
              children: [
                _buildTaskList(
                  tasks: downloadTasks,
                  emptyIcon: Icons.download_done,
                  emptyText: l.transferPageNoDownloadTasks,
                ),
                _buildTaskList(
                  tasks: uploadTasks,
                  emptyIcon: Icons.cloud_upload_outlined,
                  emptyText: l.transferPageNoUploadTasks,
                ),
                CacheListView(
                  activeTasks: cacheTasks.where((t) => !t.isCompleted).toList(),
                  onDeleteCache: _handleDeleteCacheItem,
                  onClearAll: _showClearCacheConfirmDialog,
                ),
              ],
            ),
    );
  }

  /// 桌面端 sidebar：3 个 entry（下载 / 上传 / 缓存），点击切 _tabController.index。
  Widget _buildDesktopSidebar({
    required int downloadCount,
    required int uploadCount,
    required int cacheCount,
  }) {
    final l = AppLocalizations.of(context);
    return AnimatedBuilder(
      animation: _tabController,
      builder: (_, _) => ListView(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        children: [
          _DesktopTransferEntry(
            icon: Icons.download_rounded,
            label: l.transferPageTabDownload,
            count: downloadCount,
            selected: _tabController.index == 0,
            onTap: () => _tabController.animateTo(0),
          ),
          _DesktopTransferEntry(
            icon: Icons.upload_rounded,
            label: l.transferPageTabUpload,
            count: uploadCount,
            selected: _tabController.index == 1,
            onTap: () => _tabController.animateTo(1),
          ),
          _DesktopTransferEntry(
            icon: Icons.storage_rounded,
            label: l.transferPageTabCache,
            count: cacheCount,
            selected: _tabController.index == 2,
            onTap: () => _tabController.animateTo(2),
          ),
        ],
      ),
    );
  }

  bool _isActive(TransferTask task) =>
      task.status == TransferStatus.transferring ||
      task.status == TransferStatus.queued ||
      task.status == TransferStatus.pending;

  Widget _buildTab({
    required IconData icon,
    required String label,
    required int count,
  }) => Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 4),
          Text(label),
          if (count > 0) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );

  Widget _buildTaskList({
    required List<TransferTask> tasks,
    required IconData emptyIcon,
    required String emptyText,
  }) {
    if (tasks.isEmpty) {
      return _buildEmptyState(icon: emptyIcon, text: emptyText);
    }

    // 按状态排序：进行中 > 排队中 > 等待中 > 暂停 > 失败 > 完成
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
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: sortedTasks.length,
      itemBuilder: (context, index) {
        final task = sortedTasks[index];
        return TransferTaskTile(
          task: task,
          onPause: () => _handlePause(task),
          onResume: () => _handleResume(task),
          onCancel: () => _handleCancel(task),
          onRetry: () => _handleRetry(task),
          onDelete: () => _handleDelete(task),
        );
      },
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String text,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 64,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            text,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  void _handleMenuAction(String action) {
    switch (action) {
      case 'clear_completed_downloads':
        ref.read(transferTasksProvider.notifier).clearCompletedDownloads();
      case 'clear_completed_uploads':
        ref.read(transferTasksProvider.notifier).clearCompletedUploads();
      case 'clear_all_cache':
        _showClearCacheConfirmDialog();
    }
  }

  Future<void> _showClearCacheConfirmDialog() async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.transferPageClearCacheTitle),
        content: Text(l.transferPageClearCacheMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.transferPageCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.transferPageConfirm),
          ),
        ],
      ),
    );

    if ((confirmed ?? false) && mounted) {
      await _handleClearAllCache(null);
    }
  }

  void _handlePause(TransferTask task) {
    ref.read(transferTasksProvider.notifier).pauseTask(task.id);
  }

  void _handleResume(TransferTask task) {
    ref.read(transferTasksProvider.notifier).resumeTask(task.id);
  }

  void _handleCancel(TransferTask task) {
    ref.read(transferTasksProvider.notifier).cancelTask(task.id);
  }

  void _handleRetry(TransferTask task) {
    ref.read(transferTasksProvider.notifier).retryTask(task.id);
  }

  void _handleDelete(TransferTask task) {
    ref.read(transferTasksProvider.notifier).deleteTask(task.id);
  }

  Future<void> _handleDeleteCacheItem(CachedMediaItem item) async {
    await ref.read(transferTasksProvider.notifier).deleteCache(
          item.sourceId,
          item.sourcePath,
        );
  }

  Future<void> _handleClearAllCache(MediaType? mediaType) async {
    await ref.read(transferTasksProvider.notifier).clearAllCache(
          mediaType: mediaType,
        );
  }
}

/// 桌面 sidebar 内单个 entry：icon + label + count badge。
class _DesktopTransferEntry extends StatelessWidget {
  const _DesktopTransferEntry({
    required this.icon,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final active = colorScheme.primary;
    final fg = selected
        ? active
        : (isDark
            ? AppColors.darkOnSurfaceVariant
            : colorScheme.onSurfaceVariant);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? active.withValues(alpha: isDark ? 0.18 : 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      color: fg,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                if (count > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: active,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      count.toString(),
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 传输服务初始化失败时的占位（带重试），替代静默空列表。
class _TransferError extends StatelessWidget {
  const _TransferError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, size: 40, color: scheme.error),
          const SizedBox(height: 12),
          Text(message, style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: Text(l.transferPageRetry),
          ),
        ],
      ),
    );
  }
}
