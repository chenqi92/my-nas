import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/shared/providers/download_provider.dart';
import 'package:my_nas/shared/services/download_service.dart';

/// 显示下载管理器
void showDownloadManager(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const DownloadManagerSheet(),
  );
}

class DownloadManagerSheet extends ConsumerWidget {
  const DownloadManagerSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(downloadTasksProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkOnSurfaceVariant.withValues(alpha: 0.3)
                        : AppColors.lightOnSurfaceVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // 标题
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
                        child: Icon(
                          Icons.download_rounded,
                          color: AppColors.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '下载管理',
                        style: context.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppColors.darkOnSurface : null,
                        ),
                      ),
                      const Spacer(),
                      _buildClearButton(context, ref, isDark),
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
                // 任务列表
                Expanded(
                  child: tasksAsync.when(
                    data: (tasks) {
                      if (tasks.isEmpty) {
                        return _buildEmptyState(context, isDark);
                      }

                      return ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.all(AppSpacing.md),
                        itemCount: tasks.length,
                        itemBuilder: (context, index) => _DownloadTaskTile(
                          task: tasks[index],
                          isDark: isDark,
                        ),
                      );
                    },
                    loading: () => Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    ),
                    error: (error, _) => Center(
                      child: Text(
                        '错误: $error',
                        style: TextStyle(
                          color: isDark ? AppColors.darkOnSurfaceVariant : null,
                        ),
                      ),
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

  Widget _buildClearButton(BuildContext context, WidgetRef ref, bool isDark) => Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          final service = ref.read(downloadServiceProvider);
          for (final task in service.tasks) {
            if (task.status == DownloadStatus.completed ||
                task.status == DownloadStatus.cancelled ||
                task.status == DownloadStatus.failed) {
              service.removeTask(task.id);
            }
          }
        },
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
            '清除已完成',
            style: context.textTheme.labelMedium?.copyWith(
              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );

  Widget _buildEmptyState(BuildContext context, bool isDark) => Center(
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
            child: const Icon(
              Icons.download_done_rounded,
              size: 40,
              color: AppColors.success,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '暂无下载任务',
            style: context.textTheme.titleMedium?.copyWith(
              color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '下载的文件将显示在这里',
            style: context.textTheme.bodyMedium?.copyWith(
              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
            ),
          ),
        ],
      ),
    );
}

class _DownloadTaskTile extends ConsumerWidget {
  const _DownloadTaskTile({
    required this.task,
    required this.isDark,
  });

  final DownloadTask task;
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.read(downloadServiceProvider);

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
            // 文件名和状态图标
            Row(
              children: [
                _buildStatusIcon(context),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    task.fileName,
                    style: context.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: isDark ? AppColors.darkOnSurface : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _buildActionButton(context, service),
              ],
            ),
            // 进度条
            if (task.status == DownloadStatus.downloading ||
                task.status == DownloadStatus.paused) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: task.progress,
                  backgroundColor: isDark
                      ? AppColors.darkSurfaceElevated
                      : AppColors.lightSurfaceVariant,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    task.status == DownloadStatus.paused
                        ? AppColors.warning
                        : AppColors.primary,
                  ),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    task.sizeText,
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
            if (task.status == DownloadStatus.failed && task.errorMessage != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      size: 16,
                      color: AppColors.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        task.errorMessage!,
                        style: context.textTheme.labelSmall?.copyWith(
                          color: AppColors.error,
                        ),
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
      DownloadStatus.pending => (Icons.schedule_rounded, AppColors.warning, false),
      DownloadStatus.downloading => (null, AppColors.primary, true),
      DownloadStatus.paused => (Icons.pause_circle_rounded, AppColors.warning, false),
      DownloadStatus.completed => (Icons.check_circle_rounded, AppColors.success, false),
      DownloadStatus.failed => (Icons.error_rounded, AppColors.error, false),
      DownloadStatus.cancelled => (Icons.cancel_rounded, AppColors.fileOther, false),
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
          : Icon(
              icon,
              color: color,
              size: 20,
            ),
    );
  }

  Widget _buildActionButton(BuildContext context, DownloadService service) {
    final (icon, tooltip, onTap) = switch (task.status) {
      DownloadStatus.pending => (
          Icons.play_arrow_rounded,
          '开始',
          () => service.startDownload(task.id),
        ),
      DownloadStatus.downloading => (
          Icons.pause_rounded,
          '暂停',
          () => service.pauseDownload(task.id),
        ),
      DownloadStatus.paused => (
          Icons.play_arrow_rounded,
          '继续',
          () => service.resumeDownload(task.id),
        ),
      DownloadStatus.completed => (
          Icons.folder_open_rounded,
          '打开',
          () async {
            final result = await service.openFile(task.id);
            if (!result.success && context.mounted && result.message != null) {
              context.showWarningToast(result.message!);
            }
          },
        ),
      DownloadStatus.failed => (
          Icons.refresh_rounded,
          '重试',
          () => service.retryDownload(task.id),
        ),
      DownloadStatus.cancelled => (
          Icons.delete_rounded,
          '删除',
          () => service.removeTask(task.id),
        ),
    };

    return Tooltip(
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
              color: isDark
                  ? AppColors.darkSurfaceElevated
                  : AppColors.lightSurfaceVariant,
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
}
