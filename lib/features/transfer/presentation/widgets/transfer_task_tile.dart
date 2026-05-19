import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/features/transfer/domain/entities/transfer_task.dart';

/// 传输任务列表项
class TransferTaskTile extends StatelessWidget {
  const TransferTaskTile({
    super.key,
    required this.task,
    this.onPause,
    this.onResume,
    this.onCancel,
    this.onRetry,
    this.onDelete,
  });

  final TransferTask task;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onCancel;
  final VoidCallback? onRetry;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题行
            Row(
              children: [
                _buildMediaTypeIcon(colorScheme),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.fileName,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        task.sizeProgressText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildStatusBadge(colorScheme),
              ],
            ),

            const SizedBox(height: 8),

            // 进度条
            if (task.isTransferring || task.status == TransferStatus.queued) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: task.progress,
                  minHeight: 4,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 8),
            ],

            // 操作按钮行
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // 暂停/继续按钮
                if (task.canPause)
                  _buildActionButton(
                    icon: Icons.pause_rounded,
                    label: '暂停',
                    onTap: onPause,
                  ),
                if (task.canResume)
                  _buildActionButton(
                    icon: Icons.play_arrow_rounded,
                    label: '继续',
                    onTap: onResume,
                  ),
                // 重试按钮
                if (task.canRetry)
                  _buildActionButton(
                    icon: Icons.refresh_rounded,
                    label: '重试',
                    onTap: onRetry,
                  ),
                // 取消按钮
                if (task.canCancel)
                  _buildActionButton(
                    icon: Icons.close_rounded,
                    label: '取消',
                    onTap: onCancel,
                  ),
                // 删除按钮（完成或取消后）
                if (task.isCompleted ||
                    task.status == TransferStatus.cancelled ||
                    task.isFailed)
                  _buildActionButton(
                    icon: Icons.delete_outline,
                    label: '删除',
                    onTap: onDelete,
                  ),
              ],
            ),

            // 错误信息
            if (task.error != null) ...[
              const SizedBox(height: 4),
              Text(
                task.error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.error,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMediaTypeIcon(ColorScheme colorScheme) {
    final (icon, color) = switch (task.mediaType.name) {
      'photo' => (Icons.photo_library, AppColors.photoColor),
      'music' => (Icons.music_note, AppColors.musicColor),
      'video' => (Icons.movie, AppColors.videoColor),
      'book' => (Icons.book, AppColors.bookColor),
      _ => (Icons.folder_rounded, colorScheme.primary),
    };

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        icon,
        color: color,
        size: 22,
      ),
    );
  }

  Widget _buildStatusBadge(ColorScheme colorScheme) {
    final (text, bgColor, textColor) = switch (task.status) {
      TransferStatus.pending => ('等待中', colorScheme.surfaceContainerHighest, colorScheme.onSurfaceVariant),
      TransferStatus.queued => ('排队中', colorScheme.primaryContainer, colorScheme.onPrimaryContainer),
      TransferStatus.transferring => (task.progressText, colorScheme.primaryContainer, colorScheme.onPrimaryContainer),
      TransferStatus.paused => ('已暂停', colorScheme.secondaryContainer, colorScheme.onSecondaryContainer),
      TransferStatus.completed => ('已完成', colorScheme.tertiaryContainer, colorScheme.onTertiaryContainer),
      TransferStatus.failed => ('失败', colorScheme.errorContainer, colorScheme.onErrorContainer),
      TransferStatus.cancelled => ('已取消', colorScheme.surfaceContainerHighest, colorScheme.onSurfaceVariant),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) => TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
}
