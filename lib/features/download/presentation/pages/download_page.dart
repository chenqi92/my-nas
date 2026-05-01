import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/shared/providers/download_provider.dart';
import 'package:my_nas/shared/services/download_service.dart';

class DownloadPage extends ConsumerWidget {
  const DownloadPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(downloadTasksProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : null,
      body: Column(
        children: [
          // 自定义顶部栏
          _buildHeader(context, ref, isDark),
          // 任务列表
          Expanded(
            child: tasksAsync.when(
              data: (tasks) {
                if (tasks.isEmpty) {
                  return _buildEmptyState(context, isDark);
                }

                // 分类任务
                final downloading = tasks
                    .where((t) =>
                        t.status == DownloadStatus.downloading ||
                        t.status == DownloadStatus.pending ||
                        t.status == DownloadStatus.paused)
                    .toList();
                final completed = tasks
                    .where((t) => t.status == DownloadStatus.completed)
                    .toList();
                final failed = tasks
                    .where((t) =>
                        t.status == DownloadStatus.failed ||
                        t.status == DownloadStatus.cancelled)
                    .toList();

                return ListView(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  children: [
                    if (downloading.isNotEmpty) ...[
                      _buildSectionHeader(context, '下载中', Icons.downloading_rounded, isDark),
                      const SizedBox(height: AppSpacing.sm),
                      ...downloading.map((task) => _DownloadTaskTile(
                            task: task,
                            isDark: isDark,
                          )),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                    if (completed.isNotEmpty) ...[
                      _buildSectionHeader(context, '已完成', Icons.check_circle_rounded, isDark),
                      const SizedBox(height: AppSpacing.sm),
                      ...completed.map((task) => _DownloadTaskTile(
                            task: task,
                            isDark: isDark,
                          )),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                    if (failed.isNotEmpty) ...[
                      _buildSectionHeader(context, '失败', Icons.error_rounded, isDark),
                      const SizedBox(height: AppSpacing.sm),
                      ...failed.map((task) => _DownloadTaskTile(
                            task: task,
                            isDark: isDark,
                          )),
                    ],
                  ],
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
    );
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref, bool isDark) => DecoratedBox(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : context.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? AppColors.darkOutline.withValues(alpha: 0.2)
                : context.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 16, 16),
          child: Row(
            children: [
              Text(
                '下载',
                style: context.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.darkOnSurface : null,
                ),
              ),
              const Spacer(),
              _buildClearButton(context, ref, isDark),
            ],
          ),
        ),
      ),
    );

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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cleaning_services_rounded,
                size: 16,
                color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                '清除已完成',
                style: context.textTheme.labelMedium?.copyWith(
                  color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );

  Widget _buildSectionHeader(BuildContext context, String title, IconData icon, bool isDark) => Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 16,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: context.textTheme.titleSmall?.copyWith(
            color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );

  Widget _buildEmptyState(BuildContext context, bool isDark) => Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.download_done_rounded,
              size: 48,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '暂无下载任务',
            style: context.textTheme.titleLarge?.copyWith(
              color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '在文件浏览器中选择文件下载\n下载的文件将显示在这里',
            textAlign: TextAlign.center,
            style: context.textTheme.bodyMedium?.copyWith(
              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
              height: 1.5,
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
                      const SizedBox(height: 2),
                      Text(
                        _getStatusText(),
                        style: context.textTheme.bodySmall?.copyWith(
                          color: _getStatusColor(),
                        ),
                      ),
                    ],
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

  String _getStatusText() => switch (task.status) {
        DownloadStatus.pending => '等待中',
        DownloadStatus.downloading => '下载中...',
        DownloadStatus.paused => '已暂停',
        DownloadStatus.completed => '已完成',
        DownloadStatus.failed => '下载失败',
        DownloadStatus.cancelled => '已取消',
      };

  Color _getStatusColor() => switch (task.status) {
        DownloadStatus.pending => AppColors.warning,
        DownloadStatus.downloading => AppColors.primary,
        DownloadStatus.paused => AppColors.warning,
        DownloadStatus.completed => AppColors.success,
        DownloadStatus.failed => AppColors.error,
        DownloadStatus.cancelled => AppColors.fileOther,
      };

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
      width: 44,
      height: 44,
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
              size: 22,
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
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkSurfaceElevated
                  : AppColors.lightSurfaceVariant,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 20,
              color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
            ),
          ),
        ),
      ),
    );
  }
}
