import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/app/theme/ui_style.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/book/domain/entities/book_source.dart';
import 'package:my_nas/features/book/presentation/providers/book_source_provider.dart';
import 'package:my_nas/shared/mixins/tab_bar_visibility_mixin.dart';
import 'package:my_nas/shared/providers/ui_style_provider.dart';
import 'package:my_nas/shared/widgets/adaptive_glass_container.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';
import 'package:my_nas/shared/widgets/rounded_back_button.dart';
import 'package:my_nas/shared/widgets/sheet_drag_handle.dart';

/// 书源管理页面
class BookSourcesPage extends ConsumerStatefulWidget {
  const BookSourcesPage({super.key});

  @override
  ConsumerState<BookSourcesPage> createState() => _BookSourcesPageState();
}

class _BookSourcesPageState extends ConsumerState<BookSourcesPage>
    with TabBarVisibilityMixin {
  bool _isReorderMode = false;

  @override
  void initState() {
    super.initState();
    hideTabBar();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sourcesAsync = ref.watch(bookSourcesProvider);

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : null,
      appBar: AppBar(
        leading: const RoundedBackButton(),
        title: Text(context.l10n.bookSourcesPageTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          // 排序模式切换
          IconButton(
            icon: Icon(
              _isReorderMode ? Icons.done_rounded : Icons.swap_vert_rounded,
            ),
            onPressed: () => setState(() => _isReorderMode = !_isReorderMode),
            tooltip: _isReorderMode ? context.l10n.bookSourcesPageReorderMode : context.l10n.bookSourcesPageSortMode,
          ),
          // 导入按钮
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: _showImportSheet,
            tooltip: context.l10n.bookSourcesPageImportTooltip,
          ),
        ],
      ),
      body: sourcesAsync.when(
        data: (sources) => _buildContent(sources, isDark),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
              const SizedBox(height: 16),
              Text(context.l10n.bookSourcesPageLoadingError(e)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(bookSourcesProvider),
                child: Text(context.l10n.bookSourcesPageRetry),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(List<BookSource> sources, bool isDark) {
    if (sources.isEmpty) {
      return _buildEmptyState(isDark);
    }

    if (_isReorderMode) {
      return _buildReorderableList(sources, isDark);
    }

    return _buildNormalList(sources, isDark);
  }

  Widget _buildEmptyState(bool isDark) => Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.library_books_outlined,
            size: 64,
            color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            context.l10n.bookSourcesEmptyNoSources,
            style: context.textTheme.titleMedium?.copyWith(
              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.bookSourcesEmptyHint,
            style: context.textTheme.bodyMedium?.copyWith(
              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _showImportSheet,
            icon: const Icon(Icons.add_rounded),
            label: Text(context.l10n.bookSourcesEmptyImport),
          ),
        ],
      ),
    );

  Widget _buildNormalList(List<BookSource> sources, bool isDark) {
    final uiStyle = ref.watch(uiStyleProvider);

    return ListView.builder(
      padding: AppSpacing.paddingMd,
      itemCount: sources.length,
      itemBuilder: (context, index) {
        final source = sources[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: _BookSourceCard(
            source: source,
            isDark: isDark,
            uiStyle: uiStyle,
            onToggle: (enabled) => _handleToggle(source, enabled),
            onTap: () => _handleTap(source),
            onDelete: () => _handleDelete(source),
          ),
        );
      },
    );
  }

  Widget _buildReorderableList(List<BookSource> sources, bool isDark) {
    final uiStyle = ref.watch(uiStyleProvider);

    return ReorderableListView.builder(
      padding: AppSpacing.paddingMd,
      itemCount: sources.length,
      onReorder: _handleReorder,
      proxyDecorator: (child, index, animation) => AnimatedBuilder(
          animation: animation,
          builder: (context, child) => Material(
            elevation: 8 * animation.value,
            borderRadius: BorderRadius.circular(16),
            child: child,
          ),
          child: child,
        ),
      itemBuilder: (context, index) {
        final source = sources[index];
        return Padding(
          key: ValueKey(source.id),
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: _BookSourceCard(
            source: source,
            isDark: isDark,
            uiStyle: uiStyle,
            isReorderMode: true,
            onToggle: (enabled) => _handleToggle(source, enabled),
            onTap: () => _handleTap(source),
            onDelete: () => _handleDelete(source),
          ),
        );
      },
    );
  }

  void _showImportSheet() {
    showAdaptiveModalSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _BookSourceImportSheet(
        onImport: _handleImport,
      ),
    );
  }

  Future<void> _handleImport(String content, bool isUrl) async {
    try {
      final notifier = ref.read(bookSourcesProvider.notifier);
      List<BookSource> sources;

      if (isUrl) {
        sources = await notifier.importFromUrl(content);
      } else {
        sources = await notifier.importFromJson(content);
      }

      if (sources.isEmpty) {
        if (mounted) {
          context.showToast(context.l10n.bookSourcesImportNotFound);
        }
        return;
      }

      final count = await notifier.addSources(sources);

      if (mounted) {
        Navigator.pop(context);
        context.showToast(context.l10n.bookSourcesImportSuccess(count));
      }
    } catch (e, st) {
      AppError.handleWithUI(context, e, st, context.l10n.bookSourcesImportFailed, 'importBookSources');
    }
  }

  void _handleToggle(BookSource source, bool enabled) {
    ref.read(bookSourcesProvider.notifier).toggleSource(source.id, enabled: enabled);
  }

  Future<void> _handleTap(BookSource source) async {
    final controller = TextEditingController(
      text: const JsonEncoder.withIndent('  ').convert(source.toJson()),
    );
    String? errorText;

    final updated = await showDialog<BookSource>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(context.l10n.bookSourcesEditTitle(source.displayName)),
          content: SizedBox(
            width: 600,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.l10n.bookSourcesEditHint,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 480),
                  child: TextField(
                    controller: controller,
                    maxLines: null,
                    minLines: 12,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      isDense: true,
                      errorText: errorText,
                      hintText: '{"bookSourceName": "...", ...}',
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.l10n.bookSourcesEditCancel),
            ),
            FilledButton(
              onPressed: () {
                try {
                  final raw = jsonDecode(controller.text) as Map<String, dynamic>;
                  // 强制保留原 ID，避免改 ID 导致引用断裂
                  raw['id'] = source.id;
                  final parsed = BookSource.fromJson(raw);
                  Navigator.pop(dialogContext, parsed);
                } on Exception catch (e) {
                  setDialogState(() => errorText = context.l10n.bookSourcesEditJsonError(e));
                }
              },
              child: Text(context.l10n.bookSourcesEditSave),
            ),
          ],
        ),
      ),
    );

    controller.dispose();

    if (updated == null) return;

    try {
      await ref.read(bookSourcesProvider.notifier).updateSource(updated);
      if (mounted) {
        context.showToast(context.l10n.bookSourcesEditSuccess);
      }
    } on Exception catch (e, st) {
      if (mounted) {
        AppError.handleWithUI(context, e, st, context.l10n.bookSourcesEditUpdateFailed, 'updateBookSource');
      } else {
        AppError.handle(e, st, 'updateBookSource');
      }
    }
  }

  Future<void> _handleDelete(BookSource source) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.bookSourcesDeleteTitle),
        content: Text(context.l10n.bookSourcesDeleteConfirm(source.displayName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.bookSourcesDeleteCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text(context.l10n.bookSourcesDeleteConfirmBtn),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await ref.read(bookSourcesProvider.notifier).removeSource(source.id);
      if (mounted) {
        context.showToast(context.l10n.bookSourcesDeleteSuccess);
      }
    }
  }

  void _handleReorder(int oldIndex, int newIndex) {
    ref.read(bookSourcesProvider.notifier).reorderSources(oldIndex, newIndex);
  }
}

/// 书源卡片
class _BookSourceCard extends StatelessWidget {
  const _BookSourceCard({
    required this.source,
    required this.isDark,
    required this.uiStyle,
    required this.onToggle,
    required this.onTap,
    required this.onDelete,
    this.isReorderMode = false,
  });

  final BookSource source;
  final bool isDark;
  final UIStyle uiStyle;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final bool isReorderMode;

  @override
  Widget build(BuildContext context) => AdaptiveGlassContainer(
      uiStyle: uiStyle,
      isDark: isDark,
      cornerRadius: 16,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isReorderMode ? null : onTap,
          onLongPress: isReorderMode ? null : onDelete,
          onSecondaryTap: isReorderMode ? null : onDelete,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                if (isReorderMode) ...[
                  const Icon(Icons.drag_handle_rounded, size: 24),
                  const SizedBox(width: AppSpacing.sm),
                ],
                // 图标
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _getTypeColor().withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    source.bookSourceType == BookSourceType.audio
                        ? Icons.headphones_rounded
                        : Icons.auto_stories_rounded,
                    color: _getTypeColor(),
                    size: 22,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                // 信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              source.displayName,
                              style: context.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? AppColors.darkOnSurface
                                    : AppColors.lightOnSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (source.groups.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                source.groups.first,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        source.bookSourceUrl,
                        style: context.textTheme.bodySmall?.copyWith(
                          color: isDark
                              ? AppColors.darkOnSurfaceVariant
                              : AppColors.lightOnSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // 开关
                if (!isReorderMode)
                  Switch.adaptive(
                    value: source.enabled,
                    onChanged: onToggle,
                    activeTrackColor: AppColors.primary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );

  Color _getTypeColor() => source.bookSourceType == BookSourceType.audio
        ? AppColors.accent
        : Colors.amber;
}

/// 书源导入弹框
class _BookSourceImportSheet extends StatefulWidget {
  const _BookSourceImportSheet({required this.onImport});

  final Future<void> Function(String content, bool isUrl) onImport;

  @override
  State<_BookSourceImportSheet> createState() => _BookSourceImportSheetState();
}

class _BookSourceImportSheetState extends State<_BookSourceImportSheet> {
  final _controller = TextEditingController();
  bool _isUrl = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    final isDesktop = context.isDesktopLayout;
    // 桌面下 Dialog 全圆角；移动端保留底部 sheet 风格（仅顶圆角）。
    final containerRadius = isDesktop
        ? BorderRadius.circular(AppRadius.sheet)
        : const BorderRadius.vertical(top: Radius.circular(24));

    return ClipRRect(
      borderRadius: containerRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.darkSurface.withValues(alpha: 0.95)
                : AppColors.lightSurface.withValues(alpha: 0.98),
            borderRadius: containerRadius,
          ),
          padding: EdgeInsets.only(bottom: bottomPadding),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 拖拽指示器（桌面 Dialog 下自动隐藏）
                const SheetDragHandle(),
                // 标题
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Text(
                    context.l10n.bookSourcesImportSheetTitle,
                    style: context.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                    ),
                  ),
                ),
                // 免责声明
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.warning.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 18,
                          color: AppColors.warning,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            context.l10n.bookSourcesImportDisclaimer,
                            style: context.textTheme.bodySmall?.copyWith(
                              color: isDark
                                  ? AppColors.darkOnSurfaceVariant
                                  : AppColors.lightOnSurfaceVariant,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                // 切换选项
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildOption(
                          context,
                          context.l10n.bookSourcesImportPasteJson,
                          Icons.content_paste_rounded,
                          !_isUrl,
                          () => setState(() => _isUrl = false),
                          isDark,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: _buildOption(
                          context,
                          context.l10n.bookSourcesImportNetworkLink,
                          Icons.link_rounded,
                          _isUrl,
                          () => setState(() => _isUrl = true),
                          isDark,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                // 输入框
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: TextField(
                    controller: _controller,
                    maxLines: _isUrl ? 1 : 5,
                    decoration: InputDecoration(
                      hintText: _isUrl
                          ? context.l10n.bookSourcesImportUrlHint
                          : context.l10n.bookSourcesImportJsonHint,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: isDark
                          ? AppColors.darkSurfaceVariant.withValues(alpha: 0.3)
                          : AppColors.lightSurfaceVariant.withValues(alpha: 0.3),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                // 导入按钮
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isLoading ? null : _handleImport,
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(context.l10n.bookSourcesImportButton),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOption(
    BuildContext context,
    String label,
    IconData icon,
    bool isSelected,
    VoidCallback onTap,
    bool isDark,
  ) => GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.15)
              : (isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant)
                  .withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected
                  ? AppColors.primary
                  : (isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected
                    ? AppColors.primary
                    : (isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface),
              ),
            ),
          ],
        ),
      ),
    );

  Future<void> _handleImport() async {
    final content = _controller.text.trim();
    if (content.isEmpty) {
      context.showToast(_isUrl ? context.l10n.bookSourcesImportEmptyUrl : context.l10n.bookSourcesImportEmptyJson);
      return;
    }

    setState(() => _isLoading = true);

    try {
      await widget.onImport(content, _isUrl);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
