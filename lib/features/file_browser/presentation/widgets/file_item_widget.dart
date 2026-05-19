import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

class FileItemWidget extends StatelessWidget {
  const FileItemWidget({
    required this.file,
    required this.onTap,
    super.key,
    this.onLongPress,
    this.onSecondaryTap,
    this.isGridView = false,
    this.isSelected = false,
    this.isMultiSelectMode = false,
  });

  final FileItem file;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTap;
  final bool isGridView;
  final bool isSelected;
  final bool isMultiSelectMode;

  @override
  Widget build(BuildContext context) =>
      isGridView ? _buildGridItem(context) : _buildListItem(context);

  Widget _buildListItem(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: isSelected
            ? (isDark
                ? AppColors.primary.withValues(alpha: 0.2)
                : AppColors.primary.withValues(alpha: 0.1))
            : (isDark
                ? AppColors.darkSurfaceVariant.withValues(alpha: 0.3)
                : context.colorScheme.surface),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? AppColors.primary
              : (isDark
                  ? AppColors.darkOutline.withValues(alpha: 0.2)
                  : context.colorScheme.outlineVariant.withValues(alpha: 0.5)),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          onSecondaryTap: onSecondaryTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                // 多选模式下显示复选框
                if (isMultiSelectMode) ...[
                  _buildCheckbox(isDark),
                  const SizedBox(width: AppSpacing.sm),
                ],
                // 文件图标
                _buildIconContainer(context, size: 48),
                const SizedBox(width: AppSpacing.md),
                // 文件信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        file.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: isDark
                              ? AppColors.darkOnSurface
                              : context.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _getSubtitle(),
                        style: context.textTheme.bodySmall?.copyWith(
                          color: isDark
                              ? AppColors.darkOnSurfaceVariant
                              : context.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // 右侧信息
                if (!isMultiSelectMode) ...[
                  if (file.isDirectory)
                    Icon(
                      Icons.chevron_right_rounded,
                      color: isDark
                          ? AppColors.darkOnSurfaceVariant
                          : context.colorScheme.onSurfaceVariant,
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.darkSurfaceElevated
                            : context.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        file.displaySize,
                        style: context.textTheme.labelSmall?.copyWith(
                          color: isDark
                              ? AppColors.darkOnSurfaceVariant
                              : context.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGridItem(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isSelected
            ? (isDark
                ? AppColors.primary.withValues(alpha: 0.2)
                : AppColors.primary.withValues(alpha: 0.1))
            : (isDark
                ? AppColors.darkSurfaceVariant.withValues(alpha: 0.3)
                : context.colorScheme.surface),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected
              ? AppColors.primary
              : (isDark
                  ? AppColors.darkOutline.withValues(alpha: 0.2)
                  : context.colorScheme.outlineVariant.withValues(alpha: 0.5)),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          onSecondaryTap: onSecondaryTap,
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Center(
                        child: _buildIconContainer(context, size: 56),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: Text(
                        file.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: context.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: isDark
                              ? AppColors.darkOnSurface
                              : context.colorScheme.onSurface,
                        ),
                      ),
                    ),
                    if (!file.isDirectory)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          file.displaySize,
                          style: context.textTheme.labelSmall?.copyWith(
                            color: isDark
                                ? AppColors.darkOnSurfaceVariant
                                : context.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // 多选模式下在右上角显示复选框
              if (isMultiSelectMode)
                Positioned(
                  top: 8,
                  right: 8,
                  child: _buildCheckbox(isDark),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCheckbox(bool isDark) => Container(
    width: 24,
    height: 24,
    decoration: BoxDecoration(
      color: isSelected
          ? AppColors.primary
          : (isDark ? AppColors.darkSurface : Colors.white),
      shape: BoxShape.circle,
      border: Border.all(
        color: isSelected
            ? AppColors.primary
            : (isDark ? AppColors.darkOutline : Colors.grey),
        width: 2,
      ),
    ),
    child: isSelected
        ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
        : null,
  );

  Widget _buildIconContainer(BuildContext context, {required double size}) {
    final iconData = _getIconData();
    final color = _getIconColor();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.15 : 0.1),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(
        iconData,
        size: size * 0.5,
        color: color,
      ),
    );
  }

  IconData _getIconData() => switch (file.type) {
        FileType.folder => Icons.folder_rounded,
        FileType.image => Icons.image_rounded,
        FileType.video => Icons.play_circle_rounded,
        FileType.audio => Icons.music_note_rounded,
        FileType.document => Icons.description_rounded,
        FileType.archive => Icons.folder_zip_rounded,
        FileType.code => Icons.code_rounded,
        FileType.text => Icons.article_rounded,
        FileType.pdf => Icons.picture_as_pdf_rounded,
        FileType.epub || FileType.comic => Icons.menu_book_rounded,
        FileType.other => Icons.insert_drive_file_rounded,
      };

  Color _getIconColor() => switch (file.type) {
        FileType.folder => AppColors.fileFolder,
        FileType.image => AppColors.fileImage,
        FileType.video => AppColors.fileVideo,
        FileType.audio => AppColors.fileAudio,
        FileType.document => AppColors.fileDocument,
        FileType.archive => AppColors.fileArchive,
        FileType.code => AppColors.fileCode,
        FileType.pdf => AppColors.error,
        FileType.epub || FileType.comic => AppColors.accent,
        FileType.text => AppColors.fileDocument,
        FileType.other => AppColors.fileOther,
      };

  String _getSubtitle() {
    if (file.isDirectory) return '文件夹';

    final parts = <String>[];
    if (file.modifiedTime != null) {
      parts.add(_formatDate(file.modifiedTime!));
    }
    return parts.isEmpty ? '文件' : parts.join(' · ');
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return '今天 ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return '昨天';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} 天前';
    } else {
      return '${date.month}/${date.day}';
    }
  }
}
