import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/photo/data/services/photo_database_service.dart';
import 'package:my_nas/features/sources/data/services/source_manager_service.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/shared/widgets/sheet_drag_handle.dart';
import 'package:my_nas/shared/widgets/stream_image.dart';

/// 时间线导航器 Provider
final timelineNavigatorProvider =
    StateNotifierProvider<TimelineNavigatorNotifier, TimelineNavigatorState>(
        TimelineNavigatorNotifier.new);

/// 时间线导航状态
class TimelineNavigatorState {
  const TimelineNavigatorState({
    this.yearGroups = const [],
    this.selectedYear,
    this.isLoading = true,
    this.isExpanded = false,
  });

  final List<YearMonthGroup> yearGroups;
  final int? selectedYear;
  final bool isLoading;
  final bool isExpanded;

  /// 获取所有年份
  List<int> get years => yearGroups.map((g) => g.year).toList();

  /// 获取选中年份的月份数据
  List<MonthData> get selectedMonths {
    if (selectedYear == null) return [];
    return yearGroups
        .firstWhere((g) => g.year == selectedYear,
            orElse: () => const YearMonthGroup(year: 0, months: [], totalCount: 0))
        .months;
  }

  TimelineNavigatorState copyWith({
    List<YearMonthGroup>? yearGroups,
    int? selectedYear,
    bool? isLoading,
    bool? isExpanded,
  }) =>
      TimelineNavigatorState(
        yearGroups: yearGroups ?? this.yearGroups,
        selectedYear: selectedYear ?? this.selectedYear,
        isLoading: isLoading ?? this.isLoading,
        isExpanded: isExpanded ?? this.isExpanded,
      );
}

/// 时间线导航状态管理
class TimelineNavigatorNotifier extends StateNotifier<TimelineNavigatorState> {
  TimelineNavigatorNotifier(Ref _) : super(const TimelineNavigatorState()) {
    _loadData();
  }

  final PhotoDatabaseService _db = PhotoDatabaseService();

  Future<void> _loadData() async {
    try {
      await _db.init();
      final yearGroups = await _db.getMonthlyGroups();

      state = state.copyWith(
        yearGroups: yearGroups,
        selectedYear: yearGroups.isNotEmpty ? yearGroups.first.year : null,
        isLoading: false,
      );
    } on Exception {
      state = state.copyWith(isLoading: false);
    }
  }

  /// 刷新数据
  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    await _loadData();
  }

  /// 选择年份
  void selectYear(int year) {
    state = state.copyWith(selectedYear: year);
  }

  /// 切换展开状态
  void toggleExpanded() {
    state = state.copyWith(isExpanded: !state.isExpanded);
  }

  /// 设置展开状态
  void setExpanded(bool expanded) {
    state = state.copyWith(isExpanded: expanded);
  }
}

/// 年份选择器组件
class YearSelector extends ConsumerWidget {
  const YearSelector({
    super.key,
    required this.years,
    required this.selectedYear,
    required this.onYearSelected,
  });

  final List<int> years;
  final int? selectedYear;
  final ValueChanged<int> onYearSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: years.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final year = years[index];
          final isSelected = year == selectedYear;

          return GestureDetector(
            onTap: () => onYearSelected(year),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary
                    : isDark
                        ? AppColors.darkSurfaceElevated
                        : context.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected
                      ? AppColors.primary
                      : isDark
                          ? Colors.grey[700]!
                          : Colors.grey[300]!,
                ),
              ),
              child: Text(
                '$year',
                style: TextStyle(
                  color: isSelected
                      ? Colors.white
                      : isDark
                          ? Colors.white
                          : Colors.black87,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 月份网格组件
class MonthGrid extends ConsumerWidget {
  const MonthGrid({
    super.key,
    required this.year,
    required this.months,
    required this.onMonthTap,
  });

  final int year;
  final List<MonthData> months;
  final void Function(int year, int month) onMonthTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final connections = ref.watch(activeConnectionsProvider);

    // 创建12个月的占位符
    final monthSlots = List.generate(12, (index) {
      final month = index + 1;
      return months.firstWhere(
        (m) => m.month == month,
        orElse: () => MonthData(month: month, count: 0),
      );
    });

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          childAspectRatio: 1,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: 12,
        itemBuilder: (context, index) {
          final monthData = monthSlots[index];
          final hasPhotos = monthData.count > 0;

          // 获取缩略图的文件系统
          SourceConnection? connection;
          if (monthData.thumbnailSourceId != null) {
            connection = connections[monthData.thumbnailSourceId];
          }

          return GestureDetector(
            onTap: hasPhotos ? () => onMonthTap(year, monthData.month) : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: hasPhotos
                    ? null
                    : isDark
                        ? AppColors.darkSurfaceElevated.withValues(alpha: 0.5)
                        : Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
                border: hasPhotos
                    ? Border.all(color: AppColors.primary.withValues(alpha: 0.3))
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // 缩略图或占位符
                    if (hasPhotos && monthData.thumbnailPath != null)
                      StreamImage(
                        url: monthData.thumbnailUrl,
                        path: monthData.thumbnailPath,
                        fileSystem: connection?.adapter.fileSystem,
                        placeholder: _buildPlaceholder(isDark),
                        errorWidget: _buildPlaceholder(isDark),
                        cacheKey: monthData.thumbnailPath,
                      )
                    else
                      _buildPlaceholder(isDark),

                    // 渐变遮罩 + 信息
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: hasPhotos ? 0.7 : 0.3),
                          ],
                        ),
                      ),
                    ),

                    // 月份和数量
                    Positioned(
                      left: 8,
                      right: 8,
                      bottom: 8,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            monthData.shortMonthName,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              shadows: hasPhotos
                                  ? [
                                      Shadow(
                                        color: Colors.black.withValues(alpha: 0.5),
                                        blurRadius: 4,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                          if (hasPhotos)
                            Text(
                              context.l10n.photoTimelinePhotoCount(monthData.count),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlaceholder(bool isDark) => Container(
        color: isDark ? Colors.grey[850] : Colors.grey[300],
        child: Icon(
          Icons.photo_outlined,
          color: isDark ? Colors.grey[700] : Colors.grey[400],
          size: 24,
        ),
      );
}

/// 右侧快速月份索引条
class MonthQuickIndex extends StatelessWidget {
  const MonthQuickIndex({
    super.key,
    required this.yearGroups,
    required this.onMonthTap,
  });

  final List<YearMonthGroup> yearGroups;
  final void Function(int year, int month) onMonthTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: 44,
      margin: const EdgeInsets.only(right: 4),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: yearGroups.length,
        itemBuilder: (context, yearIndex) {
          final yearGroup = yearGroups[yearIndex];
          return Column(
            children: [
              // 年份标签
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                margin: const EdgeInsets.only(bottom: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${yearGroup.year}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
              // 月份按钮
              ...yearGroup.months.map((monthData) => InkWell(
                    onTap: () => onMonthTap(yearGroup.year, monthData.month),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      child: Text(
                        '${monthData.month}',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                        ),
                      ),
                    ),
                  )),
              const SizedBox(height: 8),
            ],
          );
        },
      ),
    );
  }
}

/// 完整的时间线导航面板（可折叠）
class TimelineNavigatorPanel extends ConsumerWidget {
  const TimelineNavigatorPanel({
    super.key,
    required this.onMonthTap,
  });

  final void Function(int year, int month) onMonthTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(timelineNavigatorProvider);
    final notifier = ref.read(timelineNavigatorProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (state.isLoading) {
      return const SizedBox.shrink();
    }

    if (state.yearGroups.isEmpty) {
      return const SizedBox.shrink();
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurface
            : context.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 头部 - 年份选择器
          GestureDetector(
            onTap: notifier.toggleExpanded,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      const SizedBox(width: 16),
                      Icon(
                        Icons.calendar_month_rounded,
                        size: 20,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        context.l10n.photoTimelineNavigatorTitle,
                        style: context.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      AnimatedRotation(
                        duration: const Duration(milliseconds: 200),
                        turns: state.isExpanded ? 0.5 : 0,
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: isDark ? AppColors.darkOnSurfaceVariant : AppColors.lightOnSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 16),
                    ],
                  ),
                  const SizedBox(height: 8),
                  YearSelector(
                    years: state.years,
                    selectedYear: state.selectedYear,
                    onYearSelected: notifier.selectYear,
                  ),
                ],
              ),
            ),
          ),

          // 月份网格（可折叠）
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: state.isExpanded
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: MonthGrid(
                      year: state.selectedYear ?? DateTime.now().year,
                      months: state.selectedMonths,
                      onMonthTap: (year, month) {
                        onMonthTap(year, month);
                        notifier.setExpanded(false);
                      },
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

/// 时间线筛选底部弹窗
/// 用于按年/月筛选照片，只显示有数据的月份
class TimelineFilterBottomSheet extends ConsumerWidget {
  const TimelineFilterBottomSheet({
    super.key,
    required this.onYearSelected,
    required this.onMonthSelected,
    required this.onClearFilter,
    this.currentYear,
    this.currentMonth,
  });

  final void Function(int year) onYearSelected;
  final void Function(int year, int month) onMonthSelected;
  final VoidCallback onClearFilter;
  final int? currentYear;
  final int? currentMonth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(timelineNavigatorProvider);
    final notifier = ref.read(timelineNavigatorProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      expand: false,
      snap: true,
      snapSizes: const [0.5, 0.95],
      builder: (context, scrollController) => DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
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
                  Icon(
                    Icons.calendar_month_rounded,
                    color: AppColors.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    context.l10n.photoTimelineFilterTitle,
                    style: context.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  // 当前筛选提示
                  if (currentYear != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            currentMonth != null
                                ? context.l10n.photoTimelineYearMonthLabel(currentYear!, currentMonth!)
                                : context.l10n.photoTimelineYearLabel(currentYear!),
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () {
                              onClearFilter();
                              Navigator.pop(context);
                            },
                            child: Icon(
                              Icons.close_rounded,
                              size: 14,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 年份和月份列表（用 scrollController 驱动 sheet 拖动放大/缩小）
            Expanded(
              child: _buildContent(
                context,
                state,
                notifier,
                scrollController,
                isDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    TimelineNavigatorState state,
    TimelineNavigatorNotifier notifier,
    ScrollController scrollController,
    bool isDark,
  ) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom + 8;

    if (state.isLoading) {
      return SingleChildScrollView(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        child: const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (state.yearGroups.isEmpty) {
      return SingleChildScrollView(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Text(
              context.l10n.photoTimelineNoDataPlaceholder,
              style: TextStyle(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      controller: scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(0, 8, 0, bottomInset),
      itemCount: state.yearGroups.length,
      itemBuilder: (context, index) {
        final yearGroup = state.yearGroups[index];
        final isSelectedYear = yearGroup.year == currentYear;

        return _buildYearSection(
          context,
          yearGroup,
          isSelectedYear,
          isDark,
          notifier,
        );
      },
    );
  }

  Widget _buildYearSection(
    BuildContext context,
    YearMonthGroup yearGroup,
    bool isSelectedYear,
    bool isDark,
    TimelineNavigatorNotifier notifier,
  ) =>
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: isSelectedYear
              ? AppColors.primary.withValues(alpha: 0.08)
              : (isDark ? AppColors.darkSurfaceElevated : Colors.grey[50]),
          borderRadius: BorderRadius.circular(12),
          border: isSelectedYear
              ? Border.all(color: AppColors.primary.withValues(alpha: 0.3))
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 年份标题（可点击筛选整年）
            InkWell(
              onTap: () {
                onYearSelected(yearGroup.year);
                Navigator.pop(context);
              },
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Text(
                      context.l10n.photoTimelineYearLabel(yearGroup.year),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isSelectedYear
                            ? AppColors.primary
                            : (isDark ? Colors.white : Colors.black87),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: (isSelectedYear ? AppColors.primary : Colors.grey)
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        context.l10n.photoTimelinePhotoCount(yearGroup.totalCount),
                        style: TextStyle(
                          fontSize: 11,
                          color: isSelectedYear
                              ? AppColors.primary
                              : (isDark ? Colors.grey[400] : Colors.grey[600]),
                        ),
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      isSelectedYear && currentMonth == null
                          ? Icons.check_circle
                          : Icons.arrow_forward_ios,
                      size: 16,
                      color: isSelectedYear
                          ? AppColors.primary
                          : (isDark ? Colors.grey[600] : Colors.grey[400]),
                    ),
                  ],
                ),
              ),
            ),
            // 月份网格（只显示有数据的月份）
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: yearGroup.months.map((monthData) {
                  final isSelectedMonth =
                      isSelectedYear && monthData.month == currentMonth;

                  return InkWell(
                    onTap: () {
                      onMonthSelected(yearGroup.year, monthData.month);
                      Navigator.pop(context);
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelectedMonth
                            ? AppColors.primary
                            : (isDark
                                ? AppColors.darkSurface.withValues(alpha: 0.8)
                                : Colors.white),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelectedMonth
                              ? AppColors.primary
                              : (isDark ? Colors.grey[700]! : Colors.grey[300]!),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            context.l10n.photoTimelineMonthLabel(monthData.month),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isSelectedMonth ? FontWeight.bold : FontWeight.w500,
                              color: isSelectedMonth
                                  ? Colors.white
                                  : (isDark ? Colors.white : Colors.black87),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${monthData.count}',
                            style: TextStyle(
                              fontSize: 11,
                              color: isSelectedMonth
                                  ? Colors.white.withValues(alpha: 0.8)
                                  : (isDark ? Colors.grey[500] : Colors.grey[600]),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      );
}
