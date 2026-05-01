import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:my_nas/app/theme/app_colors.dart';

/// 媒体信息条目（一行 key-value）
class MediaInfoEntry {
  const MediaInfoEntry({
    required this.label,
    required this.value,
    this.copyable = false,
  });

  final String label;

  /// 已格式化的展示值；空字符串会被忽略
  final String value;

  /// 是否提供"复制"按钮——长路径推荐打开
  final bool copyable;
}

/// 通用媒体信息底部弹窗
///
/// 用于列表上下文菜单中"查看详情"动作：展示文件元数据（名称、大小、修改时间、
/// 路径、来源等）。各媒体类型的列表页可拼装自己的 [entries] 传入。
class MediaInfoSheet extends StatelessWidget {
  const MediaInfoSheet({
    super.key,
    required this.title,
    required this.entries,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<MediaInfoEntry> entries;

  static Future<void> show({
    required BuildContext context,
    required String title,
    required List<MediaInfoEntry> entries,
    String? subtitle,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => MediaInfoSheet(
          title: title,
          entries: entries,
          subtitle: subtitle,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          // 拖动指示器
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 标题
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty)
                        Text(
                          subtitle!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              controller: scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              itemCount: entries.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final entry = entries[index];
                if (entry.value.isEmpty) return const SizedBox.shrink();
                return _MediaInfoRow(entry: entry, isDark: isDark);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaInfoRow extends StatelessWidget {
  const _MediaInfoRow({required this.entry, required this.isDark});

  final MediaInfoEntry entry;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurfaceVariant.withValues(alpha: 0.3)
            : AppColors.lightSurfaceVariant.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  entry.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (entry.copyable)
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: '复制',
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: entry.value));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('已复制'),
                        behavior: SnackBarBehavior.floating,
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(
            entry.value,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
