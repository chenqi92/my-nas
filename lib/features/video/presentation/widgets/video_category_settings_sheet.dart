import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/ui_style.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/video/data/services/video_database_service.dart';
import 'package:my_nas/features/video/domain/entities/video_category_config.dart';
import 'package:my_nas/features/video/domain/entities/video_metadata.dart';
import 'package:my_nas/features/video/presentation/providers/video_category_settings_provider.dart';
import 'package:my_nas/shared/providers/language_preference_provider.dart';
import 'package:my_nas/shared/providers/ui_style_provider.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';
import 'package:my_nas/shared/widgets/sheet_drag_handle.dart';

/// 视频分类设置弹窗
///
/// 允许用户调整分类显示顺序、切换可见性、添加/移除动态分类
class VideoCategorySettingsSheet extends ConsumerStatefulWidget {
  const VideoCategorySettingsSheet({super.key, this.useNativePresentation = false});

  /// 是否使用原生 sheet presentation（由 show 方法自动设置）
  final bool useNativePresentation;

  /// 显示设置弹窗
  static Future<void> show(BuildContext context) async {
    // 检查是否为玻璃模式
    final container = ProviderScope.containerOf(context);
    final uiStyle = container.read(uiStyleProvider);

    if (uiStyle.isGlass && !kIsWeb && Platform.isIOS) {
      // 玻璃模式使用原生 sheet presentation 以获得 iOS 26 Liquid Glass 效果
      // 但内容仍使用 Flutter 渲染
      await showAdaptiveModalSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        useSafeArea: true,
        builder: (context) => const VideoCategorySettingsSheet(useNativePresentation: true),
      );
    } else {
      // 经典模式使用标准 Flutter 底部弹框
      await showAdaptiveModalSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => const VideoCategorySettingsSheet(),
      );
    }
  }

  @override
  ConsumerState<VideoCategorySettingsSheet> createState() =>
      _VideoCategorySettingsSheetState();
}

class _VideoCategorySettingsSheetState
    extends ConsumerState<VideoCategorySettingsSheet> {
  /// 各动态分类的可用筛选项缓存
  final Map<VideoHomeCategory, List<String>> _filterCache = {};
  final Map<VideoHomeCategory, bool> _loadingStates = {};

  @override
  void initState() {
    super.initState();
    // 预加载所有动态分类的筛选项
    _preloadAllFilters();
  }

  Future<void> _preloadAllFilters() async {
    final categories = [
      VideoHomeCategory.byMovieGenre,
      VideoHomeCategory.byMovieRegion,
      VideoHomeCategory.byTvGenre,
      VideoHomeCategory.byTvRegion,
    ];

    for (final category in categories) {
      AppError.fireAndForget(
        _loadFilters(category),
        action: 'videoCategorySettings.loadFilters',
        extraData: {'category': category.name},
      );
    }
  }

  Future<void> _loadFilters(VideoHomeCategory category) async {
    if (_filterCache.containsKey(category)) return;

    setState(() => _loadingStates[category] = true);

    try {
      final db = VideoDatabaseService();
      await db.init();

      // 根据语言偏好决定是否优先显示中文
      final langPref = ref.read(languagePreferenceProvider);
      final systemLocale = PlatformDispatcher.instance.locale;
      final metadataLangs = langPref.getMetadataLanguageCodes(systemLocale);
      // 如果首选语言是中文，则优先显示中文
      final preferChinese = metadataLangs.isNotEmpty &&
          (metadataLangs.first.startsWith('zh') || metadataLangs.first == 'auto');

      List<String> filters;
      switch (category) {
        case VideoHomeCategory.byMovieGenre:
          filters = await db.getAvailableGenres(
            category: MediaCategory.movie,
            preferChinese: preferChinese,
          );
        case VideoHomeCategory.byMovieRegion:
          filters = await db.getAvailableCountries(
            category: MediaCategory.movie,
            preferChinese: preferChinese,
          );
        case VideoHomeCategory.byTvGenre:
          filters = await db.getAvailableGenres(
            category: MediaCategory.tvShow,
            preferChinese: preferChinese,
          );
        case VideoHomeCategory.byTvRegion:
          filters = await db.getAvailableCountries(
            category: MediaCategory.tvShow,
            preferChinese: preferChinese,
          );
        default:
          filters = [];
      }

      if (mounted) {
        setState(() {
          _filterCache[category] = filters;
          _loadingStates[category] = false;
        });
      }
    } on Exception {
      if (mounted) {
        setState(() {
          _filterCache[category] = [];
          _loadingStates[category] = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = ref.watch(videoCategorySettingsProvider);
    final uiStyle = ref.watch(uiStyleProvider);

    // 只获取基础分类（非动态分类）
    final basicSections = settings.sortedSections
        .where((s) => !s.category.isDynamic)
        .toList();

    // 计算经典模式下的底部 padding
    // 经典模式使用 Flutter 渲染的导航栏，需要额外预留空间
    final classicBottomPadding = _getClassicBottomPadding(context, uiStyle);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // 拖动指示器
            const SheetDragHandle(bottomPadding: 0),
            // 标题栏
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.tune_rounded, color: AppColors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.l10n.videoCategorySettingsTitle,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => ref
                        .read(videoCategorySettingsProvider.notifier)
                        .resetToDefaults(),
                    child: Text(context.l10n.videoCategorySettingsReset),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 内容区域
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: EdgeInsets.only(bottom: 24 + classicBottomPadding),
                children: [
                  // 基础分类区域
                  _buildSectionHeader(isDark, context.l10n.videoCategorySettingsBasicSection, context.l10n.videoCategorySettingsBasicSubtitle),
                  _buildBasicCategoriesList(isDark, basicSections),
                  const SizedBox(height: 16),
                  // 动态分类区域
                  _buildSectionHeader(isDark, context.l10n.videoCategorySettingsDynamicSection, context.l10n.videoCategorySettingsDynamicSubtitle),
                  _buildDynamicCategoryExpansion(
                    isDark,
                    VideoHomeCategory.byMovieGenre,
                    context.l10n.videoCategorySettingsMovieGenre,
                    Icons.theater_comedy_rounded,
                    AppColors.downloadColor,
                    settings,
                  ),
                  _buildDynamicCategoryExpansion(
                    isDark,
                    VideoHomeCategory.byMovieRegion,
                    context.l10n.videoCategorySettingsMovieRegion,
                    Icons.language_rounded,
                    AppColors.photoColor,
                    settings,
                  ),
                  _buildDynamicCategoryExpansion(
                    isDark,
                    VideoHomeCategory.byTvGenre,
                    context.l10n.videoCategorySettingsTvGenre,
                    Icons.theaters_rounded,
                    AppColors.warning,
                    settings,
                  ),
                  _buildDynamicCategoryExpansion(
                    isDark,
                    VideoHomeCategory.byTvRegion,
                    context.l10n.videoCategorySettingsTvRegion,
                    Icons.flag_rounded,
                    AppColors.musicColor,
                    settings,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(bool isDark, String title, String subtitle) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.grey[500] : Colors.grey[600],
              ),
            ),
          ],
        ),
      );

  Widget _buildBasicCategoriesList(
    bool isDark,
    List<VideoCategorySectionConfig> sections,
  ) =>
      ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        padding: EdgeInsets.zero,
        itemCount: sections.length,
        onReorderItem: (oldIndex, newIndex) {
          // 需要将索引转换回完整列表的索引
          final settings = ref.read(videoCategorySettingsProvider);
          final allSorted = settings.sortedSections;
          final oldSection = sections[oldIndex];
          final newSection = sections[newIndex];

          final realOldIndex = allSorted.indexWhere(
            (s) => s.uniqueKey == oldSection.uniqueKey,
          );
          final realNewIndex = allSorted.indexWhere(
            (s) => s.uniqueKey == newSection.uniqueKey,
          );

          if (realOldIndex != -1 && realNewIndex != -1) {
            ref
                .read(videoCategorySettingsProvider.notifier)
                .reorder(realOldIndex, realNewIndex);
          }
        },
        itemBuilder: (context, index) {
          final section = sections[index];
          return _BasicCategoryTile(
            key: ValueKey(section.uniqueKey),
            section: section,
            isDark: isDark,
            index: index,
            onToggle: () => ref
                .read(videoCategorySettingsProvider.notifier)
                .toggleVisibility(section.uniqueKey),
          );
        },
      );

  Widget _buildDynamicCategoryExpansion(
    bool isDark,
    VideoHomeCategory category,
    String title,
    IconData icon,
    Color color,
    VideoCategorySettings settings,
  ) {
    final filters = _filterCache[category] ?? [];
    final isLoading = _loadingStates[category] ?? false;
    final selectedFilters = settings.getFiltersForCategory(category);
    final selectedCount = selectedFilters.where((f) => f != null).length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBackground : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.grey[800]!
              : Colors.grey[200]!,
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          title: Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          subtitle: Text(
            selectedCount > 0 ? context.l10n.videoCategorySettingsSelectedCount(selectedCount) : context.l10n.videoCategorySettingsNoneSelected,
            style: TextStyle(
              fontSize: 12,
              color: selectedCount > 0
                  ? color
                  : (isDark ? Colors.grey[600] : Colors.grey[500]),
            ),
          ),
          children: [
            if (isLoading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (filters.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  context.l10n.videoCategorySettingsNoAvailable(category.isGenreCategory ? context.l10n.videoCategorySettingsGenreType : context.l10n.videoCategorySettingsRegionType),
                  style: TextStyle(
                    color: isDark ? Colors.grey[600] : Colors.grey[500],
                  ),
                ),
              )
            else
              _buildFilterSelector(
                isDark,
                category,
                filters,
                selectedFilters,
                color,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterSelector(
    bool isDark,
    VideoHomeCategory category,
    List<String> filters,
    Set<String?> selectedFilters,
    Color color,
  ) {
    final allSelected = filters.every((f) => selectedFilters.contains(f));
    final noneSelected = !filters.any((f) => selectedFilters.contains(f));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 全选/取消全选按钮行
          Row(
            children: [
              _buildActionButton(
                isDark,
                allSelected ? context.l10n.videoCategorySettingsDeselect : context.l10n.videoCategorySettingsSelectAll,
                allSelected ? Icons.deselect : Icons.select_all,
                color,
                () {
                  if (allSelected) {
                    ref
                        .read(videoCategorySettingsProvider.notifier)
                        .removeAllDynamicCategoriesOfType(category);
                  } else {
                    ref
                        .read(videoCategorySettingsProvider.notifier)
                        .addDynamicCategories(category, filters);
                  }
                },
              ),
              if (!noneSelected && !allSelected) ...[
                const SizedBox(width: 8),
                _buildActionButton(
                  isDark,
                  context.l10n.videoCategorySettingsClear,
                  Icons.clear_all,
                  Colors.red,
                  () => ref
                      .read(videoCategorySettingsProvider.notifier)
                      .removeAllDynamicCategoriesOfType(category),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          // 筛选项网格
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: filters.map((filter) {
              final isSelected = selectedFilters.contains(filter);
              return FilterChip(
                label: Text(
                  filter,
                  style: TextStyle(
                    fontSize: 13,
                    color: isSelected
                        ? (isDark ? Colors.white : color)
                        : (isDark ? Colors.grey[400] : Colors.grey[700]),
                  ),
                ),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) {
                    ref
                        .read(videoCategorySettingsProvider.notifier)
                        .addDynamicCategory(category, filter);
                  } else {
                    ref
                        .read(videoCategorySettingsProvider.notifier)
                        .removeDynamicCategory(category, filter);
                  }
                },
                selectedColor: color.withValues(alpha: 0.2),
                backgroundColor: isDark ? Colors.grey[850] : Colors.white,
                checkmarkColor: color,
                side: BorderSide(
                  color: isSelected
                      ? color.withValues(alpha: 0.5)
                      : (isDark ? Colors.grey[700]! : Colors.grey[300]!),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    bool isDark,
    String label,
    IconData icon,
    Color color,
    VoidCallback onPressed,
  ) =>
      OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.5)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          minimumSize: Size.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
}

/// 计算经典模式下的底部 padding
///
/// 经典模式下 Flutter 渲染导航栏，需要为底部弹框预留导航栏高度
/// 玻璃模式下原生导航栏悬浮在内容之上，由 _getBottomPadding 处理
double _getClassicBottomPadding(BuildContext context, UIStyle uiStyle) {
  // 玻璃模式不需要额外 padding（已由原生导航栏的安全区域处理）
  if (uiStyle.isGlass) return 0;

  // 经典模式：添加导航栏高度 + 安全区域
  final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
  // 标准导航栏高度为 56，移动端约 kBottomNavigationBarHeight
  const navBarHeight = kBottomNavigationBarHeight;

  return navBarHeight + bottomPadding;
}

/// 基础分类项 Tile
class _BasicCategoryTile extends StatelessWidget {
  const _BasicCategoryTile({
    required super.key,
    required this.section,
    required this.isDark,
    required this.index,
    required this.onToggle,
  });

  final VideoCategorySectionConfig section;
  final bool isDark;
  final int index;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        child: ListTile(
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 拖动手柄
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(
                    Icons.drag_handle,
                    color: isDark ? Colors.grey[600] : Colors.grey[400],
                  ),
                ),
              ),
              // 分类图标
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _getCategoryColor(section.category).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _getCategoryIcon(section.category),
                  color: _getCategoryColor(section.category),
                  size: 20,
                ),
              ),
            ],
          ),
          title: Text(
            section.displayName,
            style: TextStyle(
              color: section.visible
                  ? (isDark ? Colors.white : Colors.black87)
                  : (isDark ? Colors.grey[600] : Colors.grey[400]),
            ),
          ),
          trailing: Switch.adaptive(
            value: section.visible,
            onChanged: (_) => onToggle(),
            thumbColor: WidgetStateProperty.resolveWith((states) =>
                states.contains(WidgetState.selected) ? AppColors.primary : null),
            trackColor: WidgetStateProperty.resolveWith((states) =>
                states.contains(WidgetState.selected)
                    ? AppColors.primary.withValues(alpha: 0.5)
                    : null),
          ),
        ),
      );

  IconData _getCategoryIcon(VideoHomeCategory category) {
    switch (category) {
      case VideoHomeCategory.heroBanner:
        return Icons.auto_awesome_rounded;
      case VideoHomeCategory.continueWatching:
        return Icons.play_circle_filled_rounded;
      case VideoHomeCategory.recentlyAdded:
        return Icons.fiber_new_rounded;
      case VideoHomeCategory.movies:
        return Icons.movie_filter_rounded;
      case VideoHomeCategory.tvShows:
        return Icons.tv_rounded;
      case VideoHomeCategory.movieCollections:
        return Icons.video_library_rounded;
      case VideoHomeCategory.topRated:
        return Icons.star_rounded;
      case VideoHomeCategory.unwatched:
        return Icons.remove_red_eye_rounded;
      case VideoHomeCategory.others:
        return Icons.folder_special_rounded;
      case VideoHomeCategory.browseMovieGenres:
        return Icons.theater_comedy_rounded;
      case VideoHomeCategory.browseMovieRegions:
        return Icons.language_rounded;
      case VideoHomeCategory.browseTvGenres:
        return Icons.theaters_rounded;
      case VideoHomeCategory.browseTvRegions:
        return Icons.flag_rounded;
      case VideoHomeCategory.liveStreaming:
        return Icons.live_tv_rounded;
      default:
        return Icons.category_rounded;
    }
  }

  Color _getCategoryColor(VideoHomeCategory category) {
    switch (category) {
      case VideoHomeCategory.heroBanner:
        return AppColors.subscriptionColor;
      case VideoHomeCategory.continueWatching:
        return AppColors.warning;
      case VideoHomeCategory.recentlyAdded:
        return AppColors.downloadColor;
      case VideoHomeCategory.movies:
        return AppColors.primary;
      case VideoHomeCategory.tvShows:
        return AppColors.accent;
      case VideoHomeCategory.movieCollections:
        return AppColors.musicColor;
      case VideoHomeCategory.topRated:
        return AppColors.tertiary;
      case VideoHomeCategory.unwatched:
        return AppColors.controlColor;
      case VideoHomeCategory.others:
        return AppColors.disabled;
      case VideoHomeCategory.browseMovieGenres:
        return AppColors.downloadColor;
      case VideoHomeCategory.browseMovieRegions:
        return AppColors.photoColor;
      case VideoHomeCategory.browseTvGenres:
        return AppColors.warning;
      case VideoHomeCategory.browseTvRegions:
        return AppColors.musicColor;
      case VideoHomeCategory.liveStreaming:
        return Colors.red;
      default:
        return AppColors.disabled;
    }
  }
}
