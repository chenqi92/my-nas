import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/note/domain/entities/note_item.dart';

/// 任务列表组件
class TaskListWidget extends StatelessWidget {
  const TaskListWidget({
    required this.tasks,
    required this.onToggle,
    required this.isDark,
    super.key,
  });

  final List<TaskItem> tasks;
  final void Function(int index) onToggle;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    // 分组：待完成、已完成
    final pendingTasks = <int, TaskItem>{};
    final completedTasks = <int, TaskItem>{};

    for (var i = 0; i < tasks.length; i++) {
      if (tasks[i].isCompleted) {
        completedTasks[i] = tasks[i];
      } else {
        pendingTasks[i] = tasks[i];
      }
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        // 统计
        _buildStatistics(context, pendingTasks.length, completedTasks.length),
        const SizedBox(height: 16),

        // 待完成任务
        if (pendingTasks.isNotEmpty) ...[
          _buildSectionHeader(context, context.l10n.taskListPendingSectionTitle, pendingTasks.length),
          ...pendingTasks.entries.map((e) => _TaskTile(
                task: e.value,
                index: e.key,
                onToggle: () => onToggle(e.key),
                isDark: isDark,
              )),
          const SizedBox(height: 16),
        ],

        // 已完成任务
        if (completedTasks.isNotEmpty) ...[
          _buildSectionHeader(context, context.l10n.taskListCompletedSectionTitle, completedTasks.length),
          ...completedTasks.entries.map((e) => _TaskTile(
                task: e.value,
                index: e.key,
                onToggle: () => onToggle(e.key),
                isDark: isDark,
              )),
        ],
      ],
    );
  }

  Widget _buildStatistics(BuildContext context, int pending, int completed) {
    final total = pending + completed;
    final progress = total > 0 ? completed / total : 0.0;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.15),
            AppColors.secondary.withValues(alpha: 0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.taskListProgressTitle,
                    style: context.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppColors.darkOnSurface : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.l10n.taskListCompletedCount(completed, total),
                    style: context.textTheme.bodySmall?.copyWith(
                      color: isDark ? AppColors.darkOnSurfaceVariant : null,
                    ),
                  ),
                ],
              ),
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark ? AppColors.darkSurface : Colors.white,
                ),
                child: Center(
                  child: Text(
                    '${(progress * 100).toInt()}%',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: isDark
                  ? AppColors.darkSurfaceVariant
                  : Colors.white.withValues(alpha: 0.5),
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, int count) => Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 8),
      child: Row(
        children: [
          Text(
            title,
            style: context.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.darkOnSurface : null,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurfaceVariant : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.darkOnSurfaceVariant : Colors.grey.shade600,
              ),
            ),
          ),
        ],
      ),
    );
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({
    required this.task,
    required this.index,
    required this.onToggle,
    required this.isDark,
  });

  final TaskItem task;
  final int index;
  final VoidCallback onToggle;
  final bool isDark;

  @override
  Widget build(BuildContext context) => Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceVariant.withValues(alpha: 0.3) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _getBorderColor(),
          width: task.priority > 0 ? 2 : 1,
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 复选框
                _buildCheckbox(context),
                const SizedBox(width: 12),
                // 内容
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // 优先级标签
                          if (task.priority > 0) ...[
                            _buildPriorityBadge(context),
                            const SizedBox(width: 8),
                          ],
                          // 内容
                          Expanded(
                            child: Text(
                              task.content,
                              style: context.textTheme.bodyMedium?.copyWith(
                                decoration: task.isCompleted
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: task.isCompleted
                                    ? (isDark
                                        ? AppColors.darkOnSurfaceVariant
                                        : Colors.grey)
                                    : (isDark ? AppColors.darkOnSurface : null),
                              ),
                            ),
                          ),
                        ],
                      ),
                      // 标签和截止日期
                      if (task.tags.isNotEmpty || task.dueDate != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            // 标签
                            ...task.tags.map((tag) => Container(
                                  margin: const EdgeInsets.only(right: 6),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '#$tag',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                )),
                            const Spacer(),
                            // 截止日期
                            if (task.dueDate != null) _buildDueDateBadge(context),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

  Color _getBorderColor() {
    if (task.isOverdue) return AppColors.error.withValues(alpha: 0.5);
    if (task.priority == 2) return AppColors.error.withValues(alpha: 0.4);
    if (task.priority == 1) return AppColors.warning.withValues(alpha: 0.4);
    if (task.isCompleted) return AppColors.success.withValues(alpha: 0.3);
    return isDark
        ? AppColors.darkOutline.withValues(alpha: 0.2)
        : Colors.grey.shade200;
  }

  Widget _buildCheckbox(BuildContext context) => Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: task.isCompleted
            ? AppColors.success
            : (task.isOverdue
                ? AppColors.error.withValues(alpha: 0.1)
                : (isDark ? AppColors.darkSurfaceVariant : Colors.grey.shade100)),
        border: task.isCompleted
            ? null
            : Border.all(
                color: task.isOverdue
                    ? AppColors.error
                    : (isDark ? AppColors.darkOutline : Colors.grey.shade400),
                width: 2,
              ),
      ),
      child: task.isCompleted
          ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
          : null,
    );

  Widget _buildPriorityBadge(BuildContext context) {
    final isUrgent = task.priority == 2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isUrgent
            ? AppColors.error.withValues(alpha: 0.1)
            : AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isUrgent ? Icons.priority_high_rounded : Icons.flag_rounded,
            size: 12,
            color: isUrgent ? AppColors.error : AppColors.warning,
          ),
          const SizedBox(width: 2),
          Text(
            isUrgent ? context.l10n.taskListPriorityUrgent : context.l10n.taskListPriorityImportant,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: isUrgent ? AppColors.error : AppColors.warning,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDueDateBadge(BuildContext context) {
    final date = task.dueDate!;
    final isOverdue = task.isOverdue;
    final isToday = _isToday(date);
    final isTomorrow = _isTomorrow(date);

    String text;
    if (isToday) {
      text = context.l10n.taskListDueDateToday;
    } else if (isTomorrow) {
      text = context.l10n.taskListDueDateTomorrow;
    } else {
      text = '${date.month}/${date.day}';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isOverdue
            ? AppColors.error.withValues(alpha: 0.1)
            : (isToday
                ? AppColors.warning.withValues(alpha: 0.1)
                : Colors.grey.withValues(alpha: 0.1)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.schedule_rounded,
            size: 12,
            color: isOverdue
                ? AppColors.error
                : (isToday ? AppColors.warning : Colors.grey),
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: isOverdue
                  ? AppColors.error
                  : (isToday ? AppColors.warning : Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  bool _isTomorrow(DateTime date) {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    return date.year == tomorrow.year &&
        date.month == tomorrow.month &&
        date.day == tomorrow.day;
  }
}
