import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/video/data/services/video_favorites_service.dart';
import 'package:my_nas/features/video/presentation/providers/video_favorites_provider.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';
import 'package:my_nas/shared/widgets/sheet_drag_handle.dart';

/// 显示书签列表
void showBookmarkSheet(
  BuildContext context, {
  required String videoPath,
  required String videoName,
  required Duration currentPosition,
  required void Function(Duration position) onSeek,
}) {
  showAdaptiveModalSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => BookmarkSheet(
      videoPath: videoPath,
      videoName: videoName,
      currentPosition: currentPosition,
      onSeek: onSeek,
    ),
  );
}

class BookmarkSheet extends ConsumerStatefulWidget {
  const BookmarkSheet({
    required this.videoPath,
    required this.videoName,
    required this.currentPosition,
    required this.onSeek,
    super.key,
  });

  final String videoPath;
  final String videoName;
  final Duration currentPosition;
  final void Function(Duration position) onSeek;

  @override
  ConsumerState<BookmarkSheet> createState() => _BookmarkSheetState();
}

class _BookmarkSheetState extends ConsumerState<BookmarkSheet> {
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bookmarksAsync = ref.watch(videoBookmarksProvider(widget.videoPath));

    return DraggableScrollableSheet(
      minChildSize: 0.3,
      maxChildSize: 0.8,
      builder: (context, scrollController) => DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // 拖拽指示器
            const SheetDragHandle(bottomPadding: 0),

            // 标题栏
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.bookmark_rounded,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.videoBookmarkTitle,
                          style: context.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          context.l10n.videoBookmarkCurrentPosition(_formatDuration(widget.currentPosition)),
                          style: context.textTheme.bodySmall?.copyWith(
                            color: isDark
                                ? AppColors.darkOnSurfaceVariant
                                : AppColors.lightOnSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 添加书签按钮
                  FilledButton.icon(
                    onPressed: () => _showAddBookmarkDialog(context),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(context.l10n.videoBookmarkAddButton),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // 书签列表
            Expanded(
              child: bookmarksAsync.when(
                data: (bookmarks) => bookmarks.isEmpty
                    ? _buildEmptyState(context, isDark)
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.sm,
                        ),
                        itemCount: bookmarks.length,
                        itemBuilder: (context, index) {
                          final bookmark = bookmarks[index];
                          return _BookmarkItem(
                            bookmark: bookmark,
                            isDark: isDark,
                            onTap: () {
                              widget.onSeek(bookmark.position);
                              Navigator.pop(context);
                            },
                            onDelete: () async {
                              await ref
                                  .read(bookmarksProvider.notifier)
                                  .removeBookmark(bookmark.id);
                            },
                            onEditNote: () =>
                                _showEditNoteDialog(context, bookmark),
                          );
                        },
                      ),
                loading: () => const Center(
                  child: CircularProgressIndicator(),
                ),
                error: (_, _) => Center(
                  child: Text(
                    context.l10n.videoBookmarkLoadError,
                    style: TextStyle(
                      color: isDark
                          ? AppColors.darkOnSurfaceVariant
                          : AppColors.lightOnSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bookmark_border_rounded,
              size: 64,
              color: isDark
                  ? AppColors.darkOnSurfaceVariant.withValues(alpha: 0.5)
                  : AppColors.lightOnSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.videoBookmarkEmptyTitle,
              style: context.textTheme.titleMedium?.copyWith(
                color: isDark
                    ? AppColors.darkOnSurfaceVariant
                    : AppColors.lightOnSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.videoBookmarkEmptyHint,
              style: context.textTheme.bodyMedium?.copyWith(
                color: isDark
                    ? AppColors.darkOnSurfaceVariant.withValues(alpha: 0.7)
                    : AppColors.lightOnSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      );

  void _showAddBookmarkDialog(BuildContext context) {
    _noteController.clear();

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.videoBookmarkAddDialogTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.videoBookmarkPositionLabel(_formatDuration(widget.currentPosition)),
              style: context.textTheme.bodyMedium?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _noteController,
              decoration: InputDecoration(
                labelText: context.l10n.videoBookmarkNoteLabel,
                hintText: context.l10n.videoBookmarkNoteHint,
                border: const OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.videoBookmarkCancelButton),
          ),
          FilledButton(
            onPressed: () {
              ref.read(bookmarksProvider.notifier).addBookmark(
                    videoPath: widget.videoPath,
                    videoName: widget.videoName,
                    position: widget.currentPosition,
                    note: _noteController.text.isEmpty
                        ? null
                        : _noteController.text,
                  );
              Navigator.pop(context);
            },
            child: Text(context.l10n.videoBookmarkAddButton),
          ),
        ],
      ),
    );
  }

  void _showEditNoteDialog(BuildContext context, VideoBookmarkItem bookmark) {
    _noteController.text = bookmark.note ?? '';

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.videoBookmarkEditDialogTitle),
        content: TextField(
          controller: _noteController,
          decoration: const InputDecoration(
            labelText: '备注',
            hintText: '输入书签备注...',
            border: OutlineInputBorder(),
          ),
          maxLines: 2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.videoBookmarkCancelButton),
          ),
          FilledButton(
            onPressed: () {
              ref.read(bookmarksProvider.notifier).updateNote(
                    bookmark.id,
                    _noteController.text.isEmpty ? null : _noteController.text,
                  );
              Navigator.pop(context);
            },
            child: Text(context.l10n.videoBookmarkSaveButton),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

class _BookmarkItem extends StatelessWidget {
  const _BookmarkItem({
    required this.bookmark,
    required this.isDark,
    required this.onTap,
    required this.onDelete,
    required this.onEditNote,
  });

  final VideoBookmarkItem bookmark;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onEditNote;

  @override
  Widget build(BuildContext context) => Dismissible(
        key: Key(bookmark.id),
        direction: DismissDirection.endToStart,
        onDismissed: (_) => onDelete(),
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          color: AppColors.error,
          child: const Icon(Icons.delete_rounded, color: Colors.white),
        ),
        child: ListTile(
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                bookmark.formattedPosition,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
          title: Text(
            bookmark.note ?? context.l10n.videoBookmarkUnnamedTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: bookmark.note == null
                  ? (isDark
                      ? AppColors.darkOnSurfaceVariant
                      : AppColors.lightOnSurfaceVariant)
                  : null,
            ),
          ),
          subtitle: Text(
            _formatDate(context, bookmark.createdAt),
            style: TextStyle(
              fontSize: 12,
              color: isDark
                  ? AppColors.darkOnSurfaceVariant
                  : AppColors.lightOnSurfaceVariant,
            ),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.edit_note_rounded),
            onPressed: onEditNote,
            tooltip: context.l10n.videoBookmarkEditNoteTooltip,
          ),
          onTap: onTap,
        ),
      );

  String _formatDate(BuildContext context, DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return context.l10n.videoBookmarkTimeJustNow;
    if (diff.inHours < 1) return context.l10n.videoBookmarkTimeMinutesAgo(diff.inMinutes);
    if (diff.inDays < 1) return context.l10n.videoBookmarkTimeHoursAgo(diff.inHours);
    if (diff.inDays < 7) return context.l10n.videoBookmarkTimeDaysAgo(diff.inDays);

    return '${date.month}/${date.day}';
  }
}
