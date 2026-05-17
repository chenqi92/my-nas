import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart' as fp;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/file_browser/presentation/providers/file_browser_provider.dart';
import 'package:my_nas/features/file_browser/presentation/widgets/file_item_widget.dart';
import 'package:my_nas/features/sources/domain/entities/source_entity.dart';
import 'package:my_nas/features/sources/presentation/pages/sources_page.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';
import 'package:my_nas/shared/providers/download_provider.dart';
import 'package:my_nas/shared/widgets/animated_list_item.dart';
import 'package:my_nas/shared/widgets/download_manager_sheet.dart';
import 'package:my_nas/shared/widgets/empty_widget.dart';
import 'package:my_nas/shared/widgets/skeleton_loader.dart';
import 'package:my_nas/shared/mixins/tab_bar_visibility_mixin.dart';

class FileBrowserPage extends ConsumerStatefulWidget {
  const FileBrowserPage({
    this.sourceId,
    this.sourceName,
    super.key,
  });

  /// 指定要浏览的源 ID（如果为空则使用当前选中的源）
  final String? sourceId;

  /// 源名称（用于标题显示）
  final String? sourceName;

  @override
  ConsumerState<FileBrowserPage> createState() => _FileBrowserPageState();
}

class _FileBrowserPageState extends ConsumerState<FileBrowserPage>
    with ConsumerTabBarVisibilityMixin {
  /// 是否从外部导航进入（需要显示返回按钮）
  bool get _isNavigatedFrom => widget.sourceId != null;

  @override
  void initState() {
    super.initState();
    hideTabBar();
    Future.microtask(() {
      // 如果指定了源 ID，先切换到该源
      if (widget.sourceId != null) {
        ref.read(selectedSourceIdProvider.notifier).state = widget.sourceId;
      }
      // 使用源配置的初始路径（如 SMB 的 shareName/path）
      ref.read(fileListProvider.notifier).loadInitialDirectory();
    });
  }

  @override
  Widget build(BuildContext context) {
    final fileState = ref.watch(fileListProvider);
    final currentPath = ref.watch(currentPathProvider);
    final viewMode = ref.watch(viewModeProvider);
    final isGridView = viewMode == ViewMode.grid;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final browsableSources = ref.watch(browsableSourcesProvider);
    final selectedSourceId = ref.watch(selectedSourceIdProvider);
    final isMultiSelectMode = ref.watch(multiSelectModeProvider);
    final selectedFiles = ref.watch(selectedFilesProvider);

    // 桌面下若有多个连接源，把 source 选择器从顶部水平条搬到左侧 sidebar。
    final isDesktop = context.isDesktopLayout;
    final showDesktopSourceSidebar =
        isDesktop && browsableSources.length > 1 && !isMultiSelectMode;

    final mainColumn = Column(
      children: [
        if (isMultiSelectMode)
          _buildMultiSelectAppBar(context, selectedFiles, isDark)
        else
          _buildAppBar(context, currentPath, isGridView, isDark),
        // 顶部源选择器：仅移动端 / 桌面但只有 1 个源时显示
        if (!showDesktopSourceSidebar &&
            browsableSources.length > 1 &&
            !isMultiSelectMode)
          _buildSourceSelector(browsableSources, selectedSourceId, isDark),
        if (!isMultiSelectMode) _buildBreadcrumb(currentPath, isDark),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => ref.read(fileListProvider.notifier).refresh(),
            color: AppColors.primary,
            backgroundColor: isDark ? AppColors.darkSurface : null,
            child: _buildContent(fileState, isGridView, isDark),
          ),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : null,
      body: showDesktopSourceSidebar
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 200,
                  child: _buildDesktopSourceSidebar(
                    browsableSources,
                    selectedSourceId,
                    isDark,
                  ),
                ),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: isDark
                      ? AppColors.darkOutline.withValues(alpha: 0.3)
                      : context.colorScheme.outlineVariant,
                ),
                Expanded(child: mainColumn),
              ],
            )
          : mainColumn,
      floatingActionButton: isMultiSelectMode ? null : _buildFab(isDark),
    );
  }

  /// 桌面端左侧 source sidebar：每个已连接源一个 entry，点击切换当前源。
  Widget _buildDesktopSourceSidebar(
    List<(SourceEntity, BrowsableConnection)> browsableSources,
    String? selectedSourceId,
    bool isDark,
  ) {
    return Container(
      color: isDark ? AppColors.darkSurface : context.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(
              '连接源',
              style: context.textTheme.labelSmall?.copyWith(
                color: isDark
                    ? AppColors.darkOnSurfaceVariant
                    : AppColors.lightOnSurfaceVariant,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: browsableSources.length,
              itemBuilder: (context, index) {
                final (source, _) = browsableSources[index];
                final isSelected = source.id == selectedSourceId;
                final fg = isSelected
                    ? AppColors.primary
                    : (isDark
                        ? AppColors.darkOnSurfaceVariant
                        : context.colorScheme.onSurfaceVariant);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        ref.read(selectedSourceIdProvider.notifier).state =
                            source.id;
                        ref.read(currentPathProvider.notifier).state = '/';
                        ref
                            .read(fileListProvider.notifier)
                            .loadDirectory('/');
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primary.withValues(
                                  alpha: isDark ? 0.18 : 0.1)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _getSourceIcon(source.type),
                              size: 16,
                              color: fg,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    source.name,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                      color: fg,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (source.host.isNotEmpty)
                                    Text(
                                      source.host,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark
                                            ? AppColors.darkOnSurfaceVariant
                                                .withValues(alpha: 0.7)
                                            : AppColors.lightOnSurfaceVariant
                                                .withValues(alpha: 0.8),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                          ],
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
  }

  Widget _buildAppBar(BuildContext context, String currentPath, bool isGridView, bool isDark) {
    // 确定标题文本
    final title = widget.sourceName ?? '文件';

    return DecoratedBox(
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
          padding: AppSpacing.appBarContentPadding,
          child: Row(
            children: [
              // 返回按钮 - 根据情况显示不同类型
              if (_isNavigatedFrom && currentPath == '/')
                // 从外部导航进入且在根目录：返回上一页面
                _buildIconButton(
                  icon: Icons.arrow_back_rounded,
                  onTap: () => Navigator.of(context).pop(),
                  isDark: isDark,
                  tooltip: '返回',
                )
              else if (currentPath != '/')
                // 在子目录中：返回上级目录
                _buildIconButton(
                  icon: Icons.arrow_back_rounded,
                  onTap: () => ref.read(fileListProvider.notifier).navigateUp(),
                  isDark: isDark,
                  tooltip: '返回上级',
                )
              else
                const SizedBox(width: 40),
              const SizedBox(width: 8),
              // 标题
              Expanded(
                child: Text(
                  title,
                  style: context.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.darkOnSurface : null,
                  ),
                ),
              ),
              // 操作按钮
              _buildIconButton(
                icon: isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded,
                onTap: () {
                  ref.read(viewModeProvider.notifier).state =
                      isGridView ? ViewMode.list : ViewMode.grid;
                },
                isDark: isDark,
                tooltip: isGridView ? '列表视图' : '网格视图',
              ),
              _buildIconButton(
                icon: Icons.swap_vert_rounded,
                onTap: () => _showSortOptions(context, isDark),
                isDark: isDark,
                tooltip: '排序',
              ),
              _buildIconButton(
                icon: Icons.download_rounded,
                onTap: () => showDownloadManager(context),
                isDark: isDark,
                tooltip: '下载管理',
              ),
              _buildIconButton(
                icon: Icons.more_vert_rounded,
                onTap: () => _showMoreOptions(context, isDark),
                isDark: isDark,
                tooltip: '更多',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMultiSelectAppBar(BuildContext context, Set<String> selectedFiles, bool isDark) {
    final fileState = ref.watch(fileListProvider);
    final allFiles = fileState is FileListLoaded ? fileState.files : <FileItem>[];
    final selectedCount = selectedFiles.length;
    final allSelected = allFiles.isNotEmpty && selectedFiles.length == allFiles.length;

    return DecoratedBox(
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
          padding: AppSpacing.appBarContentPadding,
          child: Row(
            children: [
              // 取消按钮
              _buildIconButton(
                icon: Icons.close_rounded,
                onTap: _exitMultiSelectMode,
                isDark: isDark,
                tooltip: '取消',
              ),
              const SizedBox(width: 8),
              // 已选数量
              Expanded(
                child: Text(
                  '已选择 $selectedCount 项',
                  style: context.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.darkOnSurface : null,
                  ),
                ),
              ),
              // 全选/取消全选
              _buildIconButton(
                icon: allSelected ? Icons.deselect_rounded : Icons.select_all_rounded,
                onTap: () => _toggleSelectAll(allFiles),
                isDark: isDark,
                tooltip: allSelected ? '取消全选' : '全选',
              ),
              // 删除按钮
              if (selectedCount > 0)
                _buildIconButton(
                  icon: Icons.delete_rounded,
                  onTap: () => _showBatchDeleteConfirm(selectedFiles, isDark),
                  isDark: isDark,
                  tooltip: '删除',
                ),
              // 更多操作
              if (selectedCount > 0)
                _buildIconButton(
                  icon: Icons.more_vert_rounded,
                  onTap: () => _showBatchOperations(context, selectedFiles, isDark),
                  isDark: isDark,
                  tooltip: '更多操作',
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _enterMultiSelectMode() {
    ref.read(multiSelectModeProvider.notifier).state = true;
  }

  void _exitMultiSelectMode() {
    ref.read(multiSelectModeProvider.notifier).state = false;
    ref.read(selectedFilesProvider.notifier).state = {};
  }

  void _toggleFileSelection(String path) {
    final selectedFiles = ref.read(selectedFilesProvider);
    final newSelection = Set<String>.from(selectedFiles);
    if (newSelection.contains(path)) {
      newSelection.remove(path);
    } else {
      newSelection.add(path);
    }
    ref.read(selectedFilesProvider.notifier).state = newSelection;

    // 如果没有选中任何文件，自动退出多选模式
    if (newSelection.isEmpty) {
      ref.read(multiSelectModeProvider.notifier).state = false;
    }
  }

  void _toggleSelectAll(List<FileItem> allFiles) {
    final selectedFiles = ref.read(selectedFilesProvider);
    if (selectedFiles.length == allFiles.length) {
      // 取消全选
      ref.read(selectedFilesProvider.notifier).state = {};
    } else {
      // 全选
      ref.read(selectedFilesProvider.notifier).state =
          allFiles.map((f) => f.path).toSet();
    }
  }

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback onTap,
    required bool isDark,
    String? tooltip,
  }) => Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: isDark ? AppColors.darkOnSurfaceVariant : null,
              size: 22,
            ),
          ),
        ),
      ),
    );

  Widget _buildSourceSelector(
    List<(SourceEntity, BrowsableConnection)> browsableSources,
    String? selectedSourceId,
    bool isDark,
  ) {
    // 查找当前选中的源
    final selectedSource = browsableSources.firstWhere(
      (item) => item.$1.id == selectedSourceId,
      orElse: () => browsableSources.first,
    );

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurfaceVariant.withValues(alpha: 0.3)
            : AppColors.lightSurfaceVariant.withValues(alpha: 0.6),
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? AppColors.darkOutline.withValues(alpha: 0.1)
                : AppColors.lightOutline.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _getSourceIcon(selectedSource.$1.type),
              color: AppColors.primary,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: PopupMenuButton<String>(
              initialValue: selectedSourceId,
              onSelected: (sourceId) {
                ref.read(selectedSourceIdProvider.notifier).state = sourceId;
                ref.read(currentPathProvider.notifier).state = '/';
                ref.read(fileListProvider.notifier).loadDirectory('/');
              },
              offset: const Offset(0, 44),
              itemBuilder: (context) => browsableSources.map((item) {
                final (source, _) = item;
                return PopupMenuItem<String>(
                  value: source.id,
                  child: Row(
                    children: [
                      Icon(
                        _getSourceIcon(source.type),
                        size: 18,
                        color: source.id == selectedSourceId
                            ? AppColors.primary
                            : (isDark ? AppColors.darkOnSurfaceVariant : null),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              source.name,
                              style: TextStyle(
                                fontWeight: source.id == selectedSourceId
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                color: source.id == selectedSourceId
                                    ? AppColors.primary
                                    : null,
                              ),
                            ),
                            Text(
                              source.host,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? AppColors.darkOnSurfaceVariant
                                    : AppColors.lightOnSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (source.id == selectedSourceId)
                        Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: AppColors.primary,
                        ),
                    ],
                  ),
                );
              }).toList(),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          selectedSource.$1.name,
                          style: context.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isDark ? AppColors.darkOnSurface : null,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          selectedSource.$1.host,
                          style: context.textTheme.bodySmall?.copyWith(
                            color: isDark
                                ? AppColors.darkOnSurfaceVariant
                                : AppColors.lightOnSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.unfold_more_rounded,
                    size: 20,
                    color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getSourceIcon(SourceType type) => switch (type) {
        SourceType.synology => Icons.storage_rounded,
        SourceType.qnap => Icons.storage_rounded,
        SourceType.webdav => Icons.cloud_rounded,
        SourceType.smb => Icons.lan_rounded,
        SourceType.jellyfin => Icons.play_circle_rounded,
        SourceType.emby => Icons.play_circle_rounded,
        SourceType.plex => Icons.play_circle_rounded,
        SourceType.local => Icons.phone_android_rounded,
        _ => Icons.dns_rounded,
      };

  Widget _buildBreadcrumb(String currentPath, bool isDark) {
    // 构建面包屑路径列表：[(显示名称, 完整路径), ...]
    final breadcrumbs = _buildBreadcrumbPaths(currentPath);

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurfaceVariant.withValues(alpha: 0.2)
            : AppColors.lightSurfaceVariant.withValues(alpha: 0.5),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        children: [
          _buildBreadcrumbItem(
            context: context,
            label: '根目录',
            icon: Icons.home_rounded,
            isFirst: true,
            isDark: isDark,
            onTap: () => ref.read(fileListProvider.notifier).loadDirectory('/'),
          ),
          for (final (label, path) in breadcrumbs)
            _buildBreadcrumbItem(
              context: context,
              label: label,
              isDark: isDark,
              onTap: () => ref.read(fileListProvider.notifier).loadDirectory(path),
            ),
        ],
      ),
    );
  }

  /// 构建面包屑路径列表，正确处理跨平台路径分隔符
  List<(String, String)> _buildBreadcrumbPaths(String currentPath) {
    if (currentPath == '/' || currentPath.isEmpty) return [];

    final result = <(String, String)>[];

    // 检测是否是 Windows 路径（包含驱动器字母如 C: 或 D:）
    final isWindowsPath = currentPath.length >= 2 &&
        currentPath[1] == ':' &&
        RegExp('^[A-Za-z]').hasMatch(currentPath);

    if (isWindowsPath) {
      // Windows 路径处理：C:\Users\Documents -> [(C:, C:\), (Users, C:\Users), ...]
      // 标准化分隔符为 \
      final normalized = currentPath.replaceAll('/', r'\');
      final parts = normalized.split(r'\').where((s) => s.isNotEmpty).toList();

      for (var i = 0; i < parts.length; i++) {
        String path;
        if (i == 0) {
          // 驱动器根目录
          path = '${parts[0]}\\';
        } else {
          path = '${parts[0]}\\${parts.sublist(1, i + 1).join(r'\')}';
        }
        result.add((parts[i], path));
      }
    } else {
      // Unix 路径处理：/Users/john/Documents -> [(Users, /Users), (john, /Users/john), ...]
      final parts = currentPath.split('/').where((s) => s.isNotEmpty).toList();

      for (var i = 0; i < parts.length; i++) {
        final path = '/${parts.sublist(0, i + 1).join('/')}';
        result.add((parts[i], path));
      }
    }

    return result;
  }

  Widget _buildBreadcrumbItem({
    required BuildContext context,
    required String label,
    required bool isDark,
    required VoidCallback onTap,
    IconData? icon,
    bool isFirst = false,
  }) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isFirst)
          Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
          ),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(
                      icon,
                      size: 16,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    label,
                    style: context.textTheme.bodyMedium?.copyWith(
                      color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );

  Widget _buildContent(FileListState state, bool isGridView, bool isDark) {
    final content = switch (state) {
      FileListLoading() => KeyedSubtree(
          key: const ValueKey('loading'),
          child: FileListSkeleton(isGridView: isGridView),
        ),
      FileListNotConnected() => KeyedSubtree(
          key: const ValueKey('not_connected'),
          child: _buildNotConnectedPrompt(isDark),
        ),
      FileListError(:final message, :final hasCustomPath, :final failedPath) => KeyedSubtree(
          key: const ValueKey('error'),
          child: _buildErrorContent(message, hasCustomPath, failedPath, isDark),
        ),
      FileListLoaded(:final files) when files.isEmpty => const KeyedSubtree(
          key: ValueKey('empty'),
          child: EmptyWidget(
            icon: Icons.folder_open_outlined,
            title: '文件夹为空',
            message: '此文件夹中没有文件或子文件夹',
          ),
        ),
      FileListLoaded(:final files) => KeyedSubtree(
          key: ValueKey('loaded_${files.length}'),
          child: isGridView ? _buildGrid(files, isDark) : _buildList(files, isDark),
        ),
    };

    return AnimatedContentSwitcher(child: content);
  }

  Widget _buildNotConnectedPrompt(bool isDark) => Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.cloud_off_rounded,
                size: 40,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '未连接到 NAS',
              style: context.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.darkOnSurface : null,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '请先在设置中配置并连接到 NAS 服务器',
              style: context.textTheme.bodyMedium?.copyWith(
                color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(builder: (_) => const SourcesPage()),
                  ),
                  borderRadius: BorderRadius.circular(16),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_rounded, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          '添加连接',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

  /// 构建错误内容，支持自定义路径失败时返回根目录
  Widget _buildErrorContent(String message, bool hasCustomPath, String? failedPath, bool isDark) => Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline_rounded,
                size: 40,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              hasCustomPath ? '无法访问指定目录' : '加载失败',
              style: context.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.darkOnSurface : null,
              ),
            ),
            const SizedBox(height: 12),
            if (hasCustomPath && failedPath != null) ...[
              Text(
                '目录 "$failedPath" 可能不存在或无权访问',
                style: context.textTheme.bodyMedium?.copyWith(
                  color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
            ],
            Text(
              message,
              style: context.textTheme.bodySmall?.copyWith(
                color: isDark
                    ? AppColors.darkOnSurfaceVariant.withValues(alpha: 0.7)
                    : AppColors.lightOnSurfaceVariant.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 重试按钮
                OutlinedButton.icon(
                  onPressed: () => ref.read(fileListProvider.notifier).refresh(),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('重试'),
                ),
                // 如果有自定义路径，显示返回根目录按钮
                if (hasCustomPath) ...[
                  const SizedBox(width: 16),
                  FilledButton.icon(
                    onPressed: () => ref.read(fileListProvider.notifier).loadRootDirectory(),
                    icon: const Icon(Icons.folder_rounded),
                    label: const Text('浏览所有共享'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );

  Widget _buildList(List<FileItem> files, bool isDark) {
    final isMultiSelectMode = ref.watch(multiSelectModeProvider);
    final selectedFiles = ref.watch(selectedFilesProvider);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: files.length,
      itemBuilder: (context, index) {
        final file = files[index];
        return AnimatedListItem(
          index: index,
          child: FileItemWidget(
            file: file,
            isMultiSelectMode: isMultiSelectMode,
            isSelected: selectedFiles.contains(file.path),
            onTap: () => _handleFileTap(file),
            onLongPress: () {
              if (isMultiSelectMode) {
                _toggleFileSelection(file.path);
              } else {
                _enterMultiSelectMode();
                _toggleFileSelection(file.path);
              }
            },
            onSecondaryTap: () {
              // 桌面端右键：显示文件操作菜单
              _showFileOptions(context, file, isDark);
            },
          ),
        );
      },
    );
  }

  Widget _buildGrid(List<FileItem> files, bool isDark) {
    final isMultiSelectMode = ref.watch(multiSelectModeProvider);
    final selectedFiles = ref.watch(selectedFilesProvider);

    return GridView.builder(
      padding: AppSpacing.paddingMd,
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: context.isDesktop ? 160 : 120,
        mainAxisSpacing: AppSpacing.sm,
        crossAxisSpacing: AppSpacing.sm,
        childAspectRatio: 0.85,
      ),
      itemCount: files.length,
      itemBuilder: (context, index) {
        final file = files[index];
        return AnimatedGridItem(
          index: index,
          child: FileItemWidget(
            file: file,
            isGridView: true,
            isMultiSelectMode: isMultiSelectMode,
            isSelected: selectedFiles.contains(file.path),
            onTap: () => _handleFileTap(file),
            onLongPress: () {
              if (isMultiSelectMode) {
                _toggleFileSelection(file.path);
              } else {
                _enterMultiSelectMode();
                _toggleFileSelection(file.path);
              }
            },
            onSecondaryTap: () {
              // 桌面端右键：显示文件操作菜单
              _showFileOptions(context, file, isDark);
            },
          ),
        );
      },
    );
  }

  Widget _buildFab(bool isDark) => DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: AppColors.primaryGradient,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showCreateOptions(context, isDark),
          borderRadius: BorderRadius.circular(18),
          child: const SizedBox(
            width: 60,
            height: 60,
            child: Icon(
              Icons.add_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
      ),
    );

  void _handleFileTap(FileItem file) {
    final isMultiSelectMode = ref.read(multiSelectModeProvider);

    if (isMultiSelectMode) {
      // 多选模式下，点击切换选中状态
      _toggleFileSelection(file.path);
    } else {
      // 正常模式
      final isDark = Theme.of(context).brightness == Brightness.dark;
      if (file.isDirectory) {
        ref.read(fileListProvider.notifier).loadDirectory(file.path);
      } else {
        _showFileOptions(context, file, isDark);
      }
    }
  }

  void _showSortOptions(BuildContext context, bool isDark) {
    final sortMode = ref.read(sortModeProvider);
    final ascending = ref.read(sortAscendingProvider);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _buildBottomSheet(
        context,
        isDark,
        title: '排序方式',
        children: [
          for (final mode in SortMode.values)
            _buildOptionTile(
              context,
              isDark,
              icon: _getSortModeIcon(mode),
              title: _getSortModeName(mode),
              isSelected: sortMode == mode,
              onTap: () {
                ref.read(sortModeProvider.notifier).state = mode;
                ref.read(fileListProvider.notifier).refresh();
                Navigator.pop(context);
              },
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Divider(
              color: isDark
                  ? AppColors.darkOutline.withValues(alpha: 0.2)
                  : AppColors.lightOutline.withValues(alpha: 0.3),
            ),
          ),
          _buildSwitchTile(
            context,
            isDark,
            title: '升序排列',
            value: ascending,
            onChanged: (v) {
              ref.read(sortAscendingProvider.notifier).state = v;
              ref.read(fileListProvider.notifier).refresh();
            },
          ),
        ],
      ),
    );
  }

  IconData _getSortModeIcon(SortMode mode) => switch (mode) {
        SortMode.name => Icons.sort_by_alpha_rounded,
        SortMode.size => Icons.straighten_rounded,
        SortMode.date => Icons.schedule_rounded,
        SortMode.type => Icons.category_rounded,
      };

  String _getSortModeName(SortMode mode) => switch (mode) {
        SortMode.name => '名称',
        SortMode.size => '大小',
        SortMode.date => '修改日期',
        SortMode.type => '类型',
      };

  void _showMoreOptions(BuildContext context, bool isDark) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _buildBottomSheet(
        context,
        isDark,
        title: '更多选项',
        children: [
          _buildActionTile(
            context,
            isDark,
            icon: Icons.refresh_rounded,
            iconColor: AppColors.info,
            title: '刷新',
            onTap: () {
              Navigator.pop(context);
              ref.read(fileListProvider.notifier).refresh();
            },
          ),
          _buildActionTile(
            context,
            isDark,
            icon: Icons.select_all_rounded,
            iconColor: AppColors.secondary,
            title: '多选',
            onTap: () {
              Navigator.pop(context);
              _enterMultiSelectMode();
            },
          ),
        ],
      ),
    );
  }

  void _showCreateOptions(BuildContext context, bool isDark) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _buildBottomSheet(
        context,
        isDark,
        title: '新建',
        children: [
          _buildActionTile(
            context,
            isDark,
            icon: Icons.create_new_folder_rounded,
            iconColor: AppColors.fileFolder,
            title: '新建文件夹',
            onTap: () {
              Navigator.pop(context);
              _showCreateFolderDialog(isDark);
            },
          ),
          _buildActionTile(
            context,
            isDark,
            icon: Icons.upload_file_rounded,
            iconColor: AppColors.primary,
            title: '上传文件',
            onTap: () {
              Navigator.pop(context);
              _pickAndUploadFiles();
            },
          ),
        ],
      ),
    );
  }

  void _showCreateFolderDialog(bool isDark) {
    final controller = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkSurface : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          '新建文件夹',
          style: TextStyle(
            color: isDark ? AppColors.darkOnSurface : null,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: isDark ? AppColors.darkOnSurface : null),
          decoration: InputDecoration(
            hintText: '文件夹名称',
            hintStyle: TextStyle(
              color: isDark ? AppColors.darkOnSurfaceVariant : null,
            ),
            filled: true,
            fillColor: isDark
                ? AppColors.darkSurfaceVariant.withValues(alpha: 0.5)
                : AppColors.lightSurfaceVariant,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.primary, width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '取消',
              style: TextStyle(
                color: isDark ? AppColors.darkOnSurfaceVariant : null,
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  if (controller.text.isNotEmpty) {
                    ref.read(fileListProvider.notifier).createFolder(controller.text);
                    Navigator.pop(context);
                  }
                },
                borderRadius: BorderRadius.circular(12),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Text(
                    '创建',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showFileOptions(BuildContext context, FileItem file, bool isDark) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _buildBottomSheet(
        context,
        isDark,
        title: '',
        children: [
          // 文件信息头部
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Row(
              children: [
                _buildFileIcon(file, isDark),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file.name,
                        style: context.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isDark ? AppColors.darkOnSurface : null,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (!file.isDirectory)
                        Text(
                          file.displaySize,
                          style: context.textTheme.bodySmall?.copyWith(
                            color: isDark
                                ? AppColors.darkOnSurfaceVariant
                                : AppColors.lightOnSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Divider(
              color: isDark
                  ? AppColors.darkOutline.withValues(alpha: 0.2)
                  : AppColors.lightOutline.withValues(alpha: 0.3),
            ),
          ),
          if (!file.isDirectory) ...[
            _buildActionTile(
              context,
              isDark,
              icon: Icons.download_rounded,
              iconColor: AppColors.primary,
              title: '下载',
              onTap: () {
                Navigator.pop(context);
                _downloadFile(file);
              },
            ),
            _buildActionTile(
              context,
              isDark,
              icon: Icons.share_rounded,
              iconColor: AppColors.accent,
              title: '分享',
              onTap: () {
                Navigator.pop(context);
                _shareFile(file);
              },
            ),
          ],
          _buildActionTile(
            context,
            isDark,
            icon: Icons.content_copy_rounded,
            iconColor: AppColors.info,
            title: '复制到...',
            onTap: () {
              Navigator.pop(context);
              _showDestinationPicker(file, isDark, isCopy: true);
            },
          ),
          _buildActionTile(
            context,
            isDark,
            icon: Icons.drive_file_move_rounded,
            iconColor: AppColors.accent,
            title: '移动到...',
            onTap: () {
              Navigator.pop(context);
              _showDestinationPicker(file, isDark, isCopy: false);
            },
          ),
          _buildActionTile(
            context,
            isDark,
            icon: Icons.edit_rounded,
            iconColor: AppColors.secondary,
            title: '重命名',
            onTap: () {
              Navigator.pop(context);
              _showRenameDialog(file, isDark);
            },
          ),
          _buildActionTile(
            context,
            isDark,
            icon: Icons.delete_rounded,
            iconColor: AppColors.error,
            title: '删除',
            titleColor: AppColors.error,
            onTap: () {
              Navigator.pop(context);
              _showDeleteConfirm(file, isDark);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFileIcon(FileItem file, bool isDark) {
    final color = _getFileColor(file);
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(
        _getFileIcon(file),
        color: color,
        size: 26,
      ),
    );
  }

  IconData _getFileIcon(FileItem file) => switch (file.type) {
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

  Color _getFileColor(FileItem file) => switch (file.type) {
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

  void _showRenameDialog(FileItem file, bool isDark) {
    final controller = TextEditingController(text: file.name);

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkSurface : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          '重命名',
          style: TextStyle(
            color: isDark ? AppColors.darkOnSurface : null,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: isDark ? AppColors.darkOnSurface : null),
          decoration: InputDecoration(
            hintText: '新名称',
            hintStyle: TextStyle(
              color: isDark ? AppColors.darkOnSurfaceVariant : null,
            ),
            filled: true,
            fillColor: isDark
                ? AppColors.darkSurfaceVariant.withValues(alpha: 0.5)
                : AppColors.lightSurfaceVariant,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.primary, width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '取消',
              style: TextStyle(
                color: isDark ? AppColors.darkOnSurfaceVariant : null,
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  if (controller.text.isNotEmpty && controller.text != file.name) {
                    ref.read(fileListProvider.notifier).rename(file.path, controller.text);
                    Navigator.pop(context);
                  }
                },
                borderRadius: BorderRadius.circular(12),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Text(
                    '确定',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirm(FileItem file, bool isDark) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkSurface : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          '确认删除',
          style: TextStyle(
            color: isDark ? AppColors.darkOnSurface : null,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          '确定要删除 "${file.name}" 吗？此操作无法撤销。',
          style: TextStyle(
            color: isDark ? AppColors.darkOnSurfaceVariant : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '取消',
              style: TextStyle(
                color: isDark ? AppColors.darkOnSurfaceVariant : null,
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.error, AppColors.errorDark],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  ref.read(fileListProvider.notifier).delete(file.path);
                  Navigator.pop(context);
                },
                borderRadius: BorderRadius.circular(12),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Text(
                    '删除',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showBatchDeleteConfirm(Set<String> selectedFiles, bool isDark) {
    final count = selectedFiles.length;

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkSurface : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          '确认删除',
          style: TextStyle(
            color: isDark ? AppColors.darkOnSurface : null,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          '确定要删除选中的 $count 个项目吗？此操作无法撤销。',
          style: TextStyle(
            color: isDark ? AppColors.darkOnSurfaceVariant : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '取消',
              style: TextStyle(
                color: isDark ? AppColors.darkOnSurfaceVariant : null,
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.error, AppColors.errorDark],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () async {
                  Navigator.pop(context);
                  await _batchDelete(selectedFiles);
                },
                borderRadius: BorderRadius.circular(12),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Text(
                    '删除',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _batchDelete(Set<String> paths) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final fileNotifier = ref.read(fileListProvider.notifier);

    var successCount = 0;
    var failCount = 0;

    for (final path in paths) {
      try {
        await fileNotifier.delete(path);
        successCount++;
      } on Exception {
        failCount++;
      }
    }

    _exitMultiSelectMode();
    await fileNotifier.refresh();

    if (!mounted) return;

    if (failCount == 0) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('已删除 $successCount 个项目'),
          backgroundColor: isDark ? AppColors.darkSurfaceElevated : null,
        ),
      );
    } else {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('删除完成：成功 $successCount 个，失败 $failCount 个'),
          backgroundColor: AppColors.warning,
        ),
      );
    }
  }

  void _showBatchOperations(BuildContext context, Set<String> selectedFiles, bool isDark) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _buildBottomSheet(
        context,
        isDark,
        title: '批量操作',
        children: [
          _buildActionTile(
            context,
            isDark,
            icon: Icons.content_copy_rounded,
            iconColor: AppColors.info,
            title: '复制到...',
            onTap: () {
              Navigator.pop(context);
              _showBatchDestinationPicker(selectedFiles, isDark, isCopy: true);
            },
          ),
          _buildActionTile(
            context,
            isDark,
            icon: Icons.drive_file_move_rounded,
            iconColor: AppColors.accent,
            title: '移动到...',
            onTap: () {
              Navigator.pop(context);
              _showBatchDestinationPicker(selectedFiles, isDark, isCopy: false);
            },
          ),
          _buildActionTile(
            context,
            isDark,
            icon: Icons.download_rounded,
            iconColor: AppColors.primary,
            title: '下载',
            onTap: () {
              Navigator.pop(context);
              _batchDownload(selectedFiles);
            },
          ),
          _buildActionTile(
            context,
            isDark,
            icon: Icons.delete_rounded,
            iconColor: AppColors.error,
            title: '删除',
            titleColor: AppColors.error,
            onTap: () {
              Navigator.pop(context);
              _showBatchDeleteConfirm(selectedFiles, isDark);
            },
          ),
        ],
      ),
    );
  }

  void _showBatchDestinationPicker(Set<String> selectedFiles, bool isDark, {required bool isCopy}) {
    var selectedPath = '/';

    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: isDark ? AppColors.darkSurface : null,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            isCopy ? '复制到' : '移动到',
            style: TextStyle(
              color: isDark ? AppColors.darkOnSurface : null,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: _DestinationBrowser(
              initialPath: selectedPath,
              isDark: isDark,
              onPathChanged: (path) => setState(() => selectedPath = path),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                '取消',
                style: TextStyle(
                  color: isDark ? AppColors.darkOnSurfaceVariant : null,
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () async {
                    Navigator.pop(context);
                    if (isCopy) {
                      await _batchCopy(selectedFiles, selectedPath);
                    } else {
                      await _batchMove(selectedFiles, selectedPath);
                    }
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    child: Text(
                      isCopy ? '复制到此处' : '移动到此处',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
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

  Future<void> _batchCopy(Set<String> paths, String destPath) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final fileNotifier = ref.read(fileListProvider.notifier);

    var successCount = 0;
    var failCount = 0;

    for (final path in paths) {
      try {
        await fileNotifier.copyTo(path, destPath);
        successCount++;
      } on Exception {
        failCount++;
      }
    }

    _exitMultiSelectMode();
    await fileNotifier.refresh();

    if (!mounted) return;

    if (failCount == 0) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('已复制 $successCount 个项目到 $destPath'),
          backgroundColor: isDark ? AppColors.darkSurfaceElevated : null,
        ),
      );
    } else {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('复制完成：成功 $successCount 个，失败 $failCount 个'),
          backgroundColor: AppColors.warning,
        ),
      );
    }
  }

  Future<void> _batchMove(Set<String> paths, String destPath) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final fileNotifier = ref.read(fileListProvider.notifier);

    var successCount = 0;
    var failCount = 0;

    for (final path in paths) {
      try {
        await fileNotifier.moveTo(path, destPath);
        successCount++;
      } on Exception {
        failCount++;
      }
    }

    _exitMultiSelectMode();
    await fileNotifier.refresh();

    if (!mounted) return;

    if (failCount == 0) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('已移动 $successCount 个项目到 $destPath'),
          backgroundColor: isDark ? AppColors.darkSurfaceElevated : null,
        ),
      );
    } else {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('移动完成：成功 $successCount 个，失败 $failCount 个'),
          backgroundColor: AppColors.warning,
        ),
      );
    }
  }

  Future<void> _batchDownload(Set<String> paths) async {
    final connection = ref.read(selectedBrowsableConnectionProvider);
    if (connection == null || connection.status != SourceStatus.connected) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final fileState = ref.read(fileListProvider);

    if (fileState is! FileListLoaded) return;

    // 获取选中的文件（排除文件夹）
    final files = fileState.files.where((f) => paths.contains(f.path) && !f.isDirectory).toList();

    if (files.isEmpty) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: const Text('没有可下载的文件（文件夹不支持直接下载）'),
          backgroundColor: isDark ? AppColors.darkSurfaceElevated : null,
        ),
      );
      return;
    }

    var successCount = 0;
    var failCount = 0;

    for (final file in files) {
      try {
        final url = await connection.fileSystem.getFileUrl(file.path);
        final service = ref.read(downloadServiceProvider);
        final task = await service.addTask(url: url, fileName: file.name);
        await service.startDownload(task.id);
        successCount++;
      } on Exception {
        failCount++;
      }
    }

    _exitMultiSelectMode();

    if (!mounted) return;

    if (failCount == 0) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('已添加 $successCount 个下载任务'),
          backgroundColor: isDark ? AppColors.darkSurfaceElevated : null,
          action: SnackBarAction(
            label: '查看',
            textColor: AppColors.primary,
            onPressed: () => showDownloadManager(context),
          ),
        ),
      );
    } else {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('下载任务添加完成：成功 $successCount 个，失败 $failCount 个'),
          backgroundColor: AppColors.warning,
        ),
      );
    }
  }

  /// 分享 NAS 文件
  ///
  /// 远程文件不能直接分享 URL（多数 NAS 链接含临时凭证或私网地址），
  /// 因此先流式下载到应用临时目录，再用 share_plus 弹系统分享面板。
  /// 大文件会有进度提示，分享完成后异步清理临时文件。
  Future<void> _shareFile(FileItem file) async {
    final connection = ref.read(selectedBrowsableConnectionProvider);
    if (connection == null || connection.status != SourceStatus.connected) {
      return;
    }

    File? tempFile;
    final messenger = ScaffoldMessenger.of(context);
    final loadingController = messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text('准备分享: ${file.name}')),
          ],
        ),
        duration: const Duration(minutes: 30),
      ),
    );

    try {
      final tempDir = await getTemporaryDirectory();
      final shareDir = Directory(p.join(tempDir.path, 'mynas_share'));
      if (!shareDir.existsSync()) {
        await shareDir.create(recursive: true);
      }
      // 在文件名前加时间戳，避免重名冲突
      final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      tempFile = File(p.join(shareDir.path, '${stamp}_${file.name}'));

      final stream = await connection.fileSystem.getFileStream(file.path);
      final sink = tempFile.openWrite();
      try {
        await stream.pipe(sink);
      } finally {
        await sink.close();
      }

      loadingController.close();

      if (!mounted) {
        AppError.fireAndForget(tempFile.delete(), action: 'fileBrowser.share.cleanupAfterUnmount');
        return;
      }

      final result = await Share.shareXFiles(
        [XFile(tempFile.path, name: file.name)],
        subject: file.name,
      );

      // 用户取消分享时也属正常路径
      if (result.status == ShareResultStatus.unavailable && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前平台不支持系统分享')),
        );
      }
    } on Exception catch (e, st) {
      loadingController.close();
      if (mounted) {
        AppError.handleWithUI(context, e, st, '分享失败', 'shareFile');
      } else {
        AppError.handle(e, st, 'shareFile');
      }
    } finally {
      // 5 分钟后清理临时文件，给系统分享面板足够时间使用
      if (tempFile != null) {
        final fileToCleanup = tempFile;
        Future<void>.delayed(const Duration(minutes: 5), () async {
          try {
            if (await fileToCleanup.exists()) {
              await fileToCleanup.delete();
            }
          } on Exception catch (e, st) {
            AppError.ignore(e, st, '清理分享临时文件失败');
          }
        });
      }
    }
  }

  Future<void> _downloadFile(FileItem file) async {
    final connection = ref.read(selectedBrowsableConnectionProvider);
    if (connection == null || connection.status != SourceStatus.connected) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    try {
      final url = await connection.fileSystem.getFileUrl(file.path);
      final service = ref.read(downloadServiceProvider);
      final task = await service.addTask(url: url, fileName: file.name);
      await service.startDownload(task.id);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('开始下载: ${file.name}'),
          backgroundColor: isDark ? AppColors.darkSurfaceElevated : null,
          action: SnackBarAction(
            label: '查看',
            textColor: AppColors.primary,
            onPressed: () => showDownloadManager(context),
          ),
        ),
      );
    } on Exception catch (e, st) {
      if (!mounted) return;
      AppError.handleWithUI(context, e, st, '下载失败', 'downloadFile');
    }
  }

  Future<void> _pickAndUploadFiles() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    try {
      final result = await fp.FilePicker.platform.pickFiles(
        allowMultiple: true,
      );

      if (result == null || result.files.isEmpty) return;

      for (final file in result.files) {
        if (file.path == null) continue;

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('正在上传: ${file.name}'),
            backgroundColor: isDark ? AppColors.darkSurfaceElevated : null,
            duration: const Duration(seconds: 1),
          ),
        );

        await ref.read(fileListProvider.notifier).uploadFile(
              file.path!,
              fileName: file.name,
            );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('上传完成: ${result.files.length} 个文件'),
          backgroundColor: isDark ? AppColors.darkSurfaceElevated : null,
        ),
      );
    } on Exception catch (e, st) {
      if (!mounted) return;
      AppError.handleWithUI(context, e, st, '上传失败', 'uploadFile');
    }
  }

  void _showDestinationPicker(FileItem file, bool isDark, {required bool isCopy}) {
    var selectedPath = '/';

    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: isDark ? AppColors.darkSurface : null,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            isCopy ? '复制到' : '移动到',
            style: TextStyle(
              color: isDark ? AppColors.darkOnSurface : null,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: _DestinationBrowser(
              initialPath: selectedPath,
              isDark: isDark,
              onPathChanged: (path) => setState(() => selectedPath = path),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                '取消',
                style: TextStyle(
                  color: isDark ? AppColors.darkOnSurfaceVariant : null,
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () async {
                    final scaffoldMessenger = ScaffoldMessenger.of(context);
                    Navigator.pop(context);
                    try {
                      if (isCopy) {
                        await ref.read(fileListProvider.notifier).copyTo(file.path, selectedPath);
                        scaffoldMessenger.showSnackBar(
                          SnackBar(
                            content: Text('已复制到 $selectedPath'),
                            backgroundColor: isDark ? AppColors.darkSurfaceElevated : null,
                          ),
                        );
                      } else {
                        await ref.read(fileListProvider.notifier).moveTo(file.path, selectedPath);
                        scaffoldMessenger.showSnackBar(
                          SnackBar(
                            content: Text('已移动到 $selectedPath'),
                            backgroundColor: isDark ? AppColors.darkSurfaceElevated : null,
                          ),
                        );
                      }
                    } on Exception catch (e, st) {
                      AppError.handle(e, st, isCopy ? 'copyFile' : 'moveFile');
                      scaffoldMessenger.showSnackBar(
                        SnackBar(
                          content: Text('操作失败: ${AppError.getUserFriendlyMessage(e)}'),
                          backgroundColor: AppColors.error,
                        ),
                      );
                    }
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    child: Text(
                      isCopy ? '复制到此处' : '移动到此处',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
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

  Widget _buildBottomSheet(
    BuildContext context,
    bool isDark, {
    required String title,
    required List<Widget> children,
  }) {
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          // 限制最大高度为屏幕高度的 80%
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
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
            mainAxisSize: MainAxisSize.min,
            children: [
              // 拖动指示器（固定在顶部）
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkOnSurfaceVariant.withValues(alpha: 0.3)
                      : AppColors.lightOnSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // 标题（固定在顶部）
              if (title.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Text(
                    title,
                    style: context.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                    ),
                  ),
                ),
              // 内容区域（可滚动）
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: children,
                  ),
                ),
              ),
              // 底部安全区域
              SizedBox(height: bottomPadding > 0 ? bottomPadding : AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionTile(
    BuildContext context,
    bool isDark, {
    required IconData icon,
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) => Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary.withValues(alpha: 0.15)
                      : (isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant)
                          .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: isSelected
                      ? AppColors.primary
                      : (isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant),
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  title,
                  style: context.textTheme.bodyLarge?.copyWith(
                    color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              if (isSelected)
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.primaryGradient,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
            ],
          ),
        ),
      ),
    );

  Widget _buildSwitchTile(
    BuildContext context,
    bool isDark, {
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant)
                  .withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              value ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              title,
              style: context.textTheme.bodyLarge?.copyWith(
                color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
              ),
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeTrackColor: AppColors.primary,
          ),
        ],
      ),
    );

  Widget _buildActionTile(
    BuildContext context,
    bool isDark, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required VoidCallback onTap, Color? titleColor,
  }) => Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: iconColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                title,
                style: context.textTheme.bodyLarge?.copyWith(
                  color: titleColor ??
                      (isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
}

/// 目录选择器组件
class _DestinationBrowser extends ConsumerStatefulWidget {
  const _DestinationBrowser({
    required this.initialPath,
    required this.isDark,
    required this.onPathChanged,
  });

  final String initialPath;
  final bool isDark;
  final ValueChanged<String> onPathChanged;

  @override
  ConsumerState<_DestinationBrowser> createState() => _DestinationBrowserState();
}

class _DestinationBrowserState extends ConsumerState<_DestinationBrowser> {
  late String _currentPath;
  List<FileItem>? _directories;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.initialPath;
    _loadDirectories();
  }

  Future<void> _loadDirectories() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final connection = ref.read(selectedBrowsableConnectionProvider);
      if (connection == null || connection.status != SourceStatus.connected) {
        setState(() {
          _error = '未连接';
          _isLoading = false;
        });
        return;
      }

      final files = await connection.fileSystem.listDirectory(_currentPath);
      final dirs = files.where((f) => f.isDirectory).toList();

      setState(() {
        _directories = dirs;
        _isLoading = false;
      });

      widget.onPathChanged(_currentPath);
    } on Exception catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _navigateTo(String path) {
    _currentPath = path;
    _loadDirectories();
  }

  void _navigateUp() {
    if (_currentPath == '/' || _currentPath.isEmpty) return;
    final parts = _currentPath.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return;
    parts.removeLast();
    _navigateTo(parts.isEmpty ? '/' : '/${parts.join('/')}');
  }

  @override
  Widget build(BuildContext context) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 当前路径和返回按钮
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: widget.isDark
                ? AppColors.darkSurfaceVariant.withValues(alpha: 0.5)
                : AppColors.lightSurfaceVariant,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              if (_currentPath != '/')
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, size: 20),
                  onPressed: _navigateUp,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  color: widget.isDark ? AppColors.darkOnSurface : null,
                ),
              Expanded(
                child: Text(
                  _currentPath == '/' ? '根目录' : _currentPath,
                  style: TextStyle(
                    color: widget.isDark ? AppColors.darkOnSurface : null,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 目录列表
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: widget.isDark ? AppColors.darkOnSurfaceVariant : null,
                        ),
                      ),
                    )
                  : _directories == null || _directories!.isEmpty
                      ? Center(
                          child: Text(
                            '没有子文件夹',
                            style: TextStyle(
                              color: widget.isDark ? AppColors.darkOnSurfaceVariant : null,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _directories!.length,
                          itemBuilder: (context, index) {
                            final dir = _directories![index];
                            return ListTile(
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: AppColors.fileFolder.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.folder_rounded,
                                  color: AppColors.fileFolder,
                                  size: 22,
                                ),
                              ),
                              title: Text(
                                dir.name,
                                style: TextStyle(
                                  color: widget.isDark ? AppColors.darkOnSurface : null,
                                ),
                              ),
                              trailing: Icon(
                                Icons.chevron_right_rounded,
                                color: widget.isDark ? AppColors.darkOnSurfaceVariant : null,
                              ),
                              onTap: () => _navigateTo(dir.path),
                            );
                          },
                        ),
        ),
      ],
    );
}
