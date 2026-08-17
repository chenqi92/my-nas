import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/app/theme/ui_style.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/shared/providers/ui_style_provider.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';

/// iOS 原生底部弹框通道
const _nativeBottomSheetChannel = MethodChannel(
  'com.kkape.mynas/glass_bottom_sheet',
);

/// 底部弹框回调管理器（单例）
/// 避免重复设置 MethodCallHandler 导致回调丢失
class _BottomSheetCallbackManager {
  factory _BottomSheetCallbackManager() => _instance;

  _BottomSheetCallbackManager._() {
    _nativeBottomSheetChannel.setMethodCallHandler(_handleMethodCall);
  }

  static final _BottomSheetCallbackManager _instance =
      _BottomSheetCallbackManager._();

  final Map<int, Completer<String?>> _completers = {};
  final Map<int, void Function(String)> _actionCallbacks = {};

  void registerCompleter(int sheetId, Completer<String?> completer) {
    _completers[sheetId] = completer;
  }

  void removeCompleter(int sheetId) {
    _completers.remove(sheetId);
  }

  void registerActionCallback(int sheetId, void Function(String) callback) {
    _actionCallbacks[sheetId] = callback;
  }

  void removeActionCallback(int sheetId) {
    _actionCallbacks.remove(sheetId);
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    final args = call.arguments as Map<dynamic, dynamic>?;
    if (args == null) return;

    final sheetId = args['sheetId'] as int?;
    if (sheetId == null) return;

    switch (call.method) {
      case 'onItemSelected':
        final completer = _completers[sheetId];
        if (completer != null && !completer.isCompleted) {
          final value = args['value'] as String?;
          completer.complete(value);
          _completers.remove(sheetId);
        }
      case 'onDismiss':
        final completer = _completers[sheetId];
        if (completer != null && !completer.isCompleted) {
          final selectedValue = args['selectedValue'] as String?;
          completer.complete(selectedValue);
          _completers.remove(sheetId);
        }
      case 'onActionTapped':
        final actionId = args['actionId'] as String?;
        if (actionId != null) {
          _actionCallbacks[sheetId]?.call(actionId);
        }
      case 'onFilterResult':
        final filterCompleter = _filterCompleters[sheetId];
        if (filterCompleter != null && !filterCompleter.isCompleted) {
          final result = args['result'] as Map<dynamic, dynamic>?;
          if (result != null) {
            final typedResult = result
                .map(
                  (key, value) => MapEntry(key.toString(), value?.toString()),
                )
                .cast<String, String?>();
            filterCompleter.complete(typedResult);
          } else {
            filterCompleter.complete(null);
          }
          _filterCompleters.remove(sheetId);
        }
    }
  }

  // 筛选弹框回调
  final Map<int, Completer<Map<String, String?>?>> _filterCompleters = {};

  void registerFilterCompleter(
    int sheetId,
    Completer<Map<String, String?>?> completer,
  ) {
    _filterCompleters[sheetId] = completer;
  }

  void removeFilterCompleter(int sheetId) {
    _filterCompleters.remove(sheetId);
  }
}

/// 获取回调管理器实例
final _callbackManager = _BottomSheetCallbackManager();

/// 显示应用统一风格的底部弹窗
///
/// [context] 上下文
/// [builder] 构建内容
/// [title] 标题（可选）
/// [titleWidget] 自定义标题组件（可选，优先级高于 title）
/// [useScrollable] 是否使用可拖拽滚动（默认 true，适用于内容较多的情况）
/// [initialChildSize] 初始高度比例（0.0 - 1.0）
/// [minChildSize] 最小高度比例
/// [maxChildSize] 最大高度比例
/// [useSafeArea] 是否使用安全区域（默认 true）
/// [isDismissible] 是否可以点击背景关闭（默认 true）
Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required Widget Function(
    BuildContext context,
    ScrollController? scrollController,
  )
  builder,
  String? title,
  Widget? titleWidget,
  bool useScrollable = true,
  double initialChildSize = 0.5,
  double minChildSize = 0.25,
  double maxChildSize = 0.9,
  bool useSafeArea = true,
  bool enableDrag = true,
  bool isDismissible = true,
}) => showAdaptiveModalSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: useSafeArea,
  backgroundColor: Colors.transparent,
  enableDrag: enableDrag,
  isDismissible: isDismissible,
  builder: (context) => useScrollable
      ? _ScrollableBottomSheet(
          title: title,
          titleWidget: titleWidget,
          initialChildSize: initialChildSize,
          minChildSize: minChildSize,
          maxChildSize: maxChildSize,
          builder: builder,
        )
      : _FixedBottomSheet(
          title: title,
          titleWidget: titleWidget,
          builder: builder,
        ),
);

/// 可滚动的底部弹窗（使用 DraggableScrollableSheet）
class _ScrollableBottomSheet extends ConsumerWidget {
  const _ScrollableBottomSheet({
    required this.builder,
    this.title,
    this.titleWidget,
    this.initialChildSize = 0.5,
    this.minChildSize = 0.25,
    this.maxChildSize = 0.9,
  });

  final Widget Function(
    BuildContext context,
    ScrollController? scrollController,
  )
  builder;
  final String? title;
  final Widget? titleWidget;
  final double initialChildSize;
  final double minChildSize;
  final double maxChildSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiStyle = ref.watch(uiStyleProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final glassStyle = GlassTheme.getStyle(uiStyle, isDark: isDark);

    return DraggableScrollableSheet(
      initialChildSize: initialChildSize,
      minChildSize: minChildSize,
      maxChildSize: maxChildSize,
      expand: false,
      builder: (context, scrollController) => _buildContainer(
        context,
        isDark,
        glassStyle,
        child: Column(
          children: [
            _buildDragHandle(isDark),
            if (titleWidget != null || title != null)
              _buildHeader(context, isDark),
            Expanded(child: builder(context, scrollController)),
            // 底部安全区域（包含原生 Tab Bar 高度）
            SizedBox(height: _getBottomPadding(context, uiStyle)),
          ],
        ),
      ),
    );
  }

  Widget _buildContainer(
    BuildContext context,
    bool isDark,
    GlassStyle glassStyle, {
    required Widget child,
  }) {
    final borderRadius = const BorderRadius.vertical(top: Radius.circular(24));

    // 计算背景色 - 底部弹窗使用稍高的不透明度
    final bgColor = glassStyle.needsBlur
        ? (isDark
              ? AppColors.darkSurface.withValues(
                  alpha: (glassStyle.backgroundOpacity + 0.15).clamp(0.0, 1.0),
                )
              : AppColors.lightSurface.withValues(
                  alpha: (glassStyle.backgroundOpacity + 0.1).clamp(0.0, 1.0),
                ))
        : (isDark ? AppColors.darkSurface : AppColors.lightSurface);

    final decoration = BoxDecoration(
      color: bgColor,
      borderRadius: borderRadius,
      border: Border(
        top: BorderSide(
          color: isDark
              ? AppColors.glassStroke
              : AppColors.lightOutline.withValues(alpha: 0.2),
        ),
      ),
    );

    Widget content = DecoratedBox(decoration: decoration, child: child);

    final blurFilter = glassStyle.blurFilter;
    if (blurFilter != null) {
      content = ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(filter: blurFilter, child: content),
      );
    }

    return content;
  }

  Widget _buildDragHandle(bool isDark) => Container(
    margin: const EdgeInsets.only(top: 12, bottom: 8),
    width: 40,
    height: 4,
    decoration: BoxDecoration(
      color: isDark
          ? AppColors.darkOnSurfaceVariant.withValues(alpha: 0.3)
          : AppColors.lightOnSurfaceVariant.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(2),
    ),
  );

  Widget _buildHeader(BuildContext context, bool isDark) {
    if (titleWidget != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        child: titleWidget,
      );
    }

    if (title != null && title!.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title!,
                style: context.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isDark
                      ? AppColors.darkOnSurface
                      : AppColors.lightOnSurface,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

/// 计算底部弹窗的底部间距
///
/// 在 iOS 玻璃风格下需要额外添加原生 Tab Bar 的高度，
/// 因为原生 UITabBar 悬浮在 Flutter 内容之上。
double _getBottomPadding(BuildContext context, UIStyle uiStyle) {
  final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
  // 确保至少有一点底部间距
  var padding = bottomPadding > 0 ? bottomPadding : AppSpacing.md;

  // iOS 玻璃风格下需要额外添加原生 Tab Bar 的高度
  // 因为原生 UITabBar 悬浮在 Flutter 内容之上
  if (!kIsWeb && Platform.isIOS && uiStyle.isGlass) {
    // UITabBar 标准高度约 49pt
    padding += 49;
  }

  return padding;
}

/// 固定高度的底部弹窗（内容较少时使用）
class _FixedBottomSheet extends ConsumerWidget {
  const _FixedBottomSheet({
    required this.builder,
    this.title,
    this.titleWidget,
  });

  final Widget Function(
    BuildContext context,
    ScrollController? scrollController,
  )
  builder;
  final String? title;
  final Widget? titleWidget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiStyle = ref.watch(uiStyleProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final glassStyle = GlassTheme.getStyle(uiStyle, isDark: isDark);
    final bottomPadding = _getBottomPadding(context, uiStyle);
    final borderRadius = const BorderRadius.vertical(top: Radius.circular(24));

    // 计算背景色
    final bgColor = glassStyle.needsBlur
        ? (isDark
              ? AppColors.darkSurface.withValues(
                  alpha: (glassStyle.backgroundOpacity + 0.15).clamp(0.0, 1.0),
                )
              : AppColors.lightSurface.withValues(
                  alpha: (glassStyle.backgroundOpacity + 0.1).clamp(0.0, 1.0),
                ))
        : (isDark ? AppColors.darkSurface : AppColors.lightSurface);

    final decoration = BoxDecoration(
      color: bgColor,
      borderRadius: borderRadius,
      border: Border(
        top: BorderSide(
          color: isDark
              ? AppColors.glassStroke
              : AppColors.lightOutline.withValues(alpha: 0.2),
        ),
      ),
    );

    Widget content = DecoratedBox(
      decoration: decoration,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖动指示器
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkOnSurfaceVariant.withValues(alpha: 0.3)
                  : AppColors.lightOnSurfaceVariant.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 标题
          if (titleWidget != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              child: titleWidget,
            )
          else if (title != null && title!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(
                title!,
                style: context.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isDark
                      ? AppColors.darkOnSurface
                      : AppColors.lightOnSurface,
                ),
              ),
            ),
          // 内容（使用 SingleChildScrollView 确保内容可以滚动）
          Flexible(child: SingleChildScrollView(child: builder(context, null))),
          // 底部安全区域（包含原生 Tab Bar 高度）
          SizedBox(height: bottomPadding),
        ],
      ),
    );

    final blurFilter = glassStyle.blurFilter;
    if (blurFilter != null) {
      content = ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(filter: blurFilter, child: content),
      );
    }

    return content;
  }
}

/// 显示简单的选项菜单底部弹窗
///
/// iOS 26+: 使用原生 UISheetPresentationController (Liquid Glass 自动效果)
/// 其他平台: 使用 Flutter 实现
Future<T?> showOptionsBottomSheet<T>({
  required BuildContext context,
  required List<OptionItem<T>> options,
  String? title,
  bool showCancelButton = true,
}) async {
  // iOS 平台使用原生底部弹框
  if (!kIsWeb && Platform.isIOS) {
    return _showNativeOptionsBottomSheet<T>(
      context: context,
      options: options,
      title: title,
      showCancelButton: showCancelButton,
    );
  }

  // 其他平台使用 Flutter 实现
  return showAppBottomSheet<T>(
    context: context,
    title: title,
    useScrollable: false,
    isDismissible: true,
    builder: (context, _) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [for (final option in options) _OptionTile<T>(option: option)],
    ),
  );
}

/// 列表选择项（用于 showNativeListSheet）
class ListSheetItem<T> {
  const ListSheetItem({
    required this.title,
    this.subtitle,
    this.icon,
    this.value,
    this.isSelected = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final T? value;
  final bool isSelected;
}

/// 显示原生列表选择底部弹框
///
/// 适用于音轨选择、字幕选择、画质选择等场景
/// iOS 26+: 使用原生 UISheetPresentationController (Liquid Glass 自动效果)
/// 其他平台: 使用 Flutter 暗色风格底部弹框
Future<T?> showNativeListSheet<T>({
  required BuildContext context,
  required List<ListSheetItem<T>> items,
  required String title,
  IconData? titleIcon,
  bool showCancelButton = true,
  String? emptyMessage,
  IconData? emptyIcon,
  String initialDetent = 'medium',
}) async {
  // iOS 平台使用原生底部弹框
  if (!kIsWeb && Platform.isIOS) {
    return _showNativeListSheet<T>(
      context: context,
      items: items,
      title: title,
      showCancelButton: showCancelButton,
      initialDetent: initialDetent,
    );
  }

  // 其他平台使用 Flutter 暗色风格实现
  return showAdaptiveModalSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => _FlutterListSheet<T>(
      items: items,
      title: title,
      titleIcon: titleIcon,
      emptyMessage: emptyMessage,
      emptyIcon: emptyIcon,
    ),
  );
}

/// iOS 原生列表选择底部弹框
Future<T?> _showNativeListSheet<T>({
  required BuildContext context,
  required List<ListSheetItem<T>> items,
  required String title,
  bool showCancelButton = true,
  String initialDetent = 'medium',
}) async {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  // 构建选项列表
  final nativeItems = <Map<String, dynamic>>[];
  final valueMap = <String, T>{};

  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    final valueKey = 'item_$i';

    if (item.value != null) {
      valueMap[valueKey] = item.value as T;
    }

    nativeItems.add({
      'title': item.title,
      'subtitle': item.subtitle,
      'icon': _iconDataToSFSymbol(item.icon),
      'value': valueKey,
      'isSelected': item.isSelected,
      'isDestructive': false,
      'autoDismiss': true,
    });
  }

  try {
    final sheetId = await _nativeBottomSheetChannel.invokeMethod<int>(
      'showSheet',
      {
        'isDark': isDark,
        'title': title,
        'items': nativeItems,
        'showDragHandle': true,
        'showCancelButton': showCancelButton,
        'dismissOnTapBackground': true,
        'initialDetent': initialDetent,
        'allowedDetents': ['medium', 'large'],
      },
    );

    if (sheetId == null) return null;

    // 使用回调管理器等待用户选择
    final completer = Completer<String?>();
    _callbackManager.registerCompleter(sheetId, completer);

    final selectedValueKey = await completer.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () {
        _callbackManager.removeCompleter(sheetId);
        return null;
      },
    );

    if (selectedValueKey != null && valueMap.containsKey(selectedValueKey)) {
      return valueMap[selectedValueKey];
    }
    return null;
  } catch (e) {
    // 回退到 Flutter 实现
    logger.w(
      'Native list sheet failed, falling back to Flutter implementation',
      e,
    );
    return showAdaptiveModalSheet<T>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _FlutterListSheet<T>(items: items, title: title),
    );
  }
}

// MARK: - 筛选弹框 API

/// 筛选分区配置
class FilterSection {
  const FilterSection({
    required this.id,
    required this.title,
    required this.items,
  });

  final String id;
  final String title;
  final List<FilterItem> items;

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'items': items.map((e) => e.toMap()).toList(),
  };
}

/// 筛选选项
class FilterItem {
  const FilterItem({required this.value, required this.title});

  final String value;
  final String title;

  Map<String, dynamic> toMap() => {'value': value, 'title': title};
}

/// 筛选结果
class FilterResult {
  const FilterResult(this.selectedValues);

  /// 分区ID -> 选中值
  final Map<String, String?> selectedValues;

  String? getSelected(String sectionId) => selectedValues[sectionId];

  bool get isEmpty => selectedValues.values.every((v) => v == null);
}

/// 显示原生筛选弹框
///
/// iOS 使用原生 UICollectionView 实现 chip 选择
/// 其他平台使用 Flutter 实现
Future<FilterResult?> showNativeFilterSheet({
  required BuildContext context,
  required List<FilterSection> sections,
  String? title,
  Map<String, String>? initialSelectedValues,
  bool showResetButton = true,
  String? applyButtonText,
  String? resetButtonText,
}) async {
  final effTitle = title ?? context.l10n.bottomSheetFilterDefaultTitle;
  final effApply = applyButtonText ?? context.l10n.bottomSheetApplyButtonText;
  final effReset = resetButtonText ?? context.l10n.bottomSheetResetButtonText;
  // iOS 平台使用原生实现
  if (!kIsWeb && Platform.isIOS) {
    return _showNativeFilterSheetImpl(
      context: context,
      sections: sections,
      title: effTitle,
      initialSelectedValues: initialSelectedValues,
      showResetButton: showResetButton,
      applyButtonText: effApply,
      resetButtonText: effReset,
    );
  }

  // 其他平台使用 Flutter 实现
  return showAdaptiveModalSheet<FilterResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _FlutterFilterSheet(
      sections: sections,
      title: effTitle,
      initialSelectedValues: initialSelectedValues ?? {},
      showResetButton: showResetButton,
      applyButtonText: effApply,
      resetButtonText: effReset,
    ),
  );
}

/// iOS 原生筛选弹框实现
Future<FilterResult?> _showNativeFilterSheetImpl({
  required BuildContext context,
  required List<FilterSection> sections,
  required String title,
  Map<String, String>? initialSelectedValues,
  required bool showResetButton,
  required String applyButtonText,
  required String resetButtonText,
}) async {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  try {
    final sheetId = await _nativeBottomSheetChannel
        .invokeMethod<int>('showFilterSheet', {
          'isDark': isDark,
          'title': title,
          'sections': sections.map((s) => s.toMap()).toList(),
          'selectedValues': initialSelectedValues ?? {},
          'showResetButton': showResetButton,
          'applyButtonText': applyButtonText,
          'resetButtonText': resetButtonText,
        });

    if (sheetId == null) return null;

    // 等待用户选择结果
    final completer = Completer<Map<String, String?>?>();
    _callbackManager.registerFilterCompleter(sheetId, completer);

    final result = await completer.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () {
        _callbackManager.removeFilterCompleter(sheetId);
        return null;
      },
    );

    if (result != null) {
      return FilterResult(result);
    }
    return null;
  } catch (e) {
    logger.w('Native filter sheet failed, falling back to Flutter', e);
    // 回退到 Flutter 实现
    return showAdaptiveModalSheet<FilterResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _FlutterFilterSheet(
        sections: sections,
        title: title,
        initialSelectedValues: initialSelectedValues ?? {},
        showResetButton: showResetButton,
        applyButtonText: applyButtonText,
        resetButtonText: resetButtonText,
      ),
    );
  }
}

/// Flutter 风格筛选弹框
class _FlutterFilterSheet extends StatefulWidget {
  const _FlutterFilterSheet({
    required this.sections,
    required this.title,
    required this.initialSelectedValues,
    required this.showResetButton,
    required this.applyButtonText,
    required this.resetButtonText,
  });

  final List<FilterSection> sections;
  final String title;
  final Map<String, String> initialSelectedValues;
  final bool showResetButton;
  final String applyButtonText;
  final String resetButtonText;

  @override
  State<_FlutterFilterSheet> createState() => _FlutterFilterSheetState();
}

class _FlutterFilterSheetState extends State<_FlutterFilterSheet> {
  late Map<String, String?> _selectedValues;

  @override
  void initState() {
    super.initState();
    _selectedValues = Map.from(widget.initialSelectedValues);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖动条
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 标题栏
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                ),
                if (widget.showResetButton)
                  TextButton(
                    onPressed: () {
                      setState(() => _selectedValues.clear());
                    },
                    child: Text(widget.resetButtonText),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 筛选内容
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: widget.sections
                    .map(
                      (section) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            section.title,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: section.items.map((item) {
                              final isSelected =
                                  _selectedValues[section.id] == item.value;
                              return GestureDetector(
                                onTap: () {
                                  setState(() {
                                    if (isSelected) {
                                      _selectedValues.remove(section.id);
                                    } else {
                                      _selectedValues[section.id] = item.value;
                                    }
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? cs.primary
                                        : cs.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: isSelected
                                          ? cs.primary
                                          : cs.outlineVariant,
                                    ),
                                  ),
                                  child: Text(
                                    item.title,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: isSelected
                                          ? cs.onPrimary
                                          : cs.onSurface,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
          // 应用按钮
          Container(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + MediaQuery.of(context).padding.bottom,
            ),
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border(top: BorderSide(color: cs.outlineVariant)),
            ),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () =>
                    Navigator.of(context).pop(FilterResult(_selectedValues)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: cs.primary,
                  foregroundColor: cs.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  widget.applyButtonText,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Flutter 暗色风格列表选择弹框
class _FlutterListSheet<T> extends StatelessWidget {
  const _FlutterListSheet({
    required this.items,
    required this.title,
    this.titleIcon,
    this.emptyMessage,
    this.emptyIcon,
  });

  final List<ListSheetItem<T>> items;
  final String title;
  final IconData? titleIcon;
  final String? emptyMessage;
  final IconData? emptyIcon;

  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.6,
    ),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.92),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 拖拽指示器
        Container(
          margin: const EdgeInsets.only(top: 12),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white24,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        // 标题栏
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
          child: Row(
            children: [
              if (titleIcon != null) ...[
                Icon(titleIcon, color: Colors.white70, size: 20),
                const SizedBox(width: 8),
              ],
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white24, height: 1),
        // 列表内容
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                Icon(
                  emptyIcon ?? Icons.inbox_rounded,
                  size: 48,
                  color: Colors.white38,
                ),
                const SizedBox(height: 12),
                Text(
                  emptyMessage ?? appL10n.bottomSheetEmptyMessage,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          )
        else
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return _ListSheetTile<T>(item: item);
              },
            ),
          ),
        SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
      ],
    ),
  );
}

/// 列表选项项
class _ListSheetTile<T> extends StatelessWidget {
  const _ListSheetTile({required this.item});

  final ListSheetItem<T> item;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: () => Navigator.pop(context, item.value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            if (item.icon != null) ...[
              Icon(
                item.icon,
                color: item.isSelected ? Colors.white : Colors.white60,
                size: 20,
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: TextStyle(
                      color: item.isSelected ? Colors.white : Colors.white70,
                      fontSize: 14,
                      fontWeight: item.isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  if (item.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle!,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (item.isSelected)
              const Icon(
                Icons.check_circle_rounded,
                color: Colors.white,
                size: 20,
              ),
          ],
        ),
      ),
    ),
  );
}

// MARK: - Sectioned Sheet Support

/// 分区（用于 showNativeSectionedSheet）
class SectionedSheetSection<T> {
  const SectionedSheetSection({required this.items, this.header});

  final String? header;
  final List<ListSheetItem<T>> items;
}

/// 操作按钮（用于 showNativeSectionedSheet）
class SectionedSheetAction {
  const SectionedSheetAction({
    required this.id,
    required this.title,
    this.icon,
  });

  final String id;
  final String title;
  final IconData? icon;
}

/// 显示原生分区列表底部弹框
///
/// 适用于字幕选择（多分区）、设置列表等场景
/// iOS: 使用原生 UISheetPresentationController
/// 其他平台: 使用 Flutter 暗色风格底部弹框
Future<SectionedSheetResult<T>?> showNativeSectionedSheet<T>({
  required BuildContext context,
  required List<SectionedSheetSection<T>> sections,
  required String title,
  List<SectionedSheetAction> actions = const [],
  String? headerInfo,
  bool showCancelButton = true,
  String initialDetent = 'medium',
  void Function(String actionId)? onActionTapped,
}) async {
  if (!kIsWeb && Platform.isIOS) {
    return _showNativeSectionedSheet<T>(
      context: context,
      sections: sections,
      title: title,
      actions: actions,
      headerInfo: headerInfo,
      showCancelButton: showCancelButton,
      initialDetent: initialDetent,
      onActionTapped: onActionTapped,
    );
  }

  // 其他平台使用 Flutter 实现
  return showAdaptiveModalSheet<SectionedSheetResult<T>>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => _FlutterSectionedSheet<T>(
      sections: sections,
      title: title,
      actions: actions,
      onActionTapped: onActionTapped,
    ),
  );
}

/// 分区选择结果
class SectionedSheetResult<T> {
  const SectionedSheetResult({
    required this.sectionIndex,
    required this.itemIndex,
    required this.value,
  });

  final int sectionIndex;
  final int itemIndex;
  final T value;
}

/// iOS 原生分区列表
Future<SectionedSheetResult<T>?> _showNativeSectionedSheet<T>({
  required BuildContext context,
  required List<SectionedSheetSection<T>> sections,
  required String title,
  List<SectionedSheetAction> actions = const [],
  String? headerInfo,
  bool showCancelButton = true,
  String initialDetent = 'medium',
  void Function(String actionId)? onActionTapped,
}) async {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  // 构建分区数据并建立值映射
  final nativeSections = <Map<String, dynamic>>[];
  final valueMap =
      <
        String,
        (int, int, T)
      >{}; // value -> (sectionIndex, itemIndex, actualValue)

  for (var si = 0; si < sections.length; si++) {
    final section = sections[si];
    final nativeItems = <Map<String, dynamic>>[];

    for (var ii = 0; ii < section.items.length; ii++) {
      final item = section.items[ii];
      final valueKey = 'section_${si}_item_$ii';

      if (item.value != null) {
        valueMap[valueKey] = (si, ii, item.value as T);
      }

      nativeItems.add({
        'title': item.title,
        'subtitle': item.subtitle,
        'icon': _iconDataToSFSymbol(item.icon),
        'value': valueKey,
        'isSelected': item.isSelected,
        'autoDismiss': true,
      });
    }

    nativeSections.add({'header': section.header, 'items': nativeItems});
  }

  // 构建操作按钮
  final nativeActions = actions
      .map(
        (a) => {
          'id': a.id,
          'title': a.title,
          'icon': _iconDataToSFSymbol(a.icon),
        },
      )
      .toList();

  try {
    final sheetId = await _nativeBottomSheetChannel.invokeMethod<int>(
      'showSectionedSheet',
      {
        'isDark': isDark,
        'title': title,
        'sections': nativeSections,
        'actions': nativeActions,
        'headerInfo': headerInfo,
        'showDragHandle': true,
        'showCancelButton': showCancelButton,
        'initialDetent': initialDetent,
        'allowedDetents': ['medium', 'large'],
      },
    );

    if (sheetId == null) return null;

    // 注册操作回调
    if (onActionTapped != null) {
      _callbackManager.registerActionCallback(sheetId, onActionTapped);
    }

    // 等待选择结果
    final completer = Completer<String?>();
    _callbackManager.registerCompleter(sheetId, completer);

    final selectedValueKey = await completer.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () {
        _callbackManager
          ..removeCompleter(sheetId)
          ..removeActionCallback(sheetId);
        return null;
      },
    );

    _callbackManager.removeActionCallback(sheetId);

    if (selectedValueKey != null && valueMap.containsKey(selectedValueKey)) {
      final (si, ii, value) = valueMap[selectedValueKey]!;
      return SectionedSheetResult<T>(
        sectionIndex: si,
        itemIndex: ii,
        value: value,
      );
    }
    return null;
  } catch (e) {
    logger.w('Native sectioned sheet failed', e);
    return null;
  }
}

/// Flutter 分区列表弹框
class _FlutterSectionedSheet<T> extends StatelessWidget {
  const _FlutterSectionedSheet({
    required this.sections,
    required this.title,
    required this.actions,
    this.onActionTapped,
  });

  final List<SectionedSheetSection<T>> sections;
  final String title;
  final List<SectionedSheetAction> actions;
  final void Function(String actionId)? onActionTapped;

  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.7,
    ),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.92),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 12),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white24,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
          child: Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white24, height: 1),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: sections.fold<int>(
              0,
              (sum, s) => sum + s.items.length + (s.header != null ? 1 : 0),
            ),
            itemBuilder: (context, index) {
              var currentIndex = 0;
              for (var si = 0; si < sections.length; si++) {
                final section = sections[si];
                if (section.header != null) {
                  if (currentIndex == index) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Text(
                        section.header!,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    );
                  }
                  currentIndex++;
                }
                for (var ii = 0; ii < section.items.length; ii++) {
                  if (currentIndex == index) {
                    final item = section.items[ii];
                    return _SectionedItemTile<T>(
                      item: item,
                      sectionIndex: si,
                      itemIndex: ii,
                    );
                  }
                  currentIndex++;
                }
              }
              return const SizedBox.shrink();
            },
          ),
        ),
        if (actions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: actions
                  .map(
                    (action) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ElevatedButton.icon(
                          onPressed: () => onActionTapped?.call(action.id),
                          icon: action.icon != null
                              ? Icon(action.icon, size: 18)
                              : const SizedBox.shrink(),
                          label: Text(action.title),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white12,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
      ],
    ),
  );
}

class _SectionedItemTile<T> extends StatelessWidget {
  const _SectionedItemTile({
    required this.item,
    required this.sectionIndex,
    required this.itemIndex,
  });

  final ListSheetItem<T> item;
  final int sectionIndex;
  final int itemIndex;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: () => Navigator.pop(
        context,
        SectionedSheetResult<T>(
          sectionIndex: sectionIndex,
          itemIndex: itemIndex,
          value: item.value as T,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            if (item.icon != null) ...[
              Icon(
                item.icon,
                color: item.isSelected ? Colors.white : Colors.white60,
                size: 20,
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: TextStyle(
                      color: item.isSelected ? Colors.white : Colors.white70,
                      fontSize: 14,
                      fontWeight: item.isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  if (item.subtitle != null)
                    Text(
                      item.subtitle!,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        decoration: TextDecoration.none,
                      ),
                    ),
                ],
              ),
            ),
            if (item.isSelected)
              const Icon(
                Icons.check_circle_rounded,
                color: Colors.white,
                size: 20,
              ),
          ],
        ),
      ),
    ),
  );
}

/// iOS 原生选项底部弹框
Future<T?> _showNativeOptionsBottomSheet<T>({
  required BuildContext context,
  required List<OptionItem<T>> options,
  String? title,
  bool showCancelButton = true,
}) async {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  // 构建选项列表
  final items = <Map<String, dynamic>>[];
  final valueMap = <String, T>{};

  for (var i = 0; i < options.length; i++) {
    final option = options[i];
    final valueKey = 'option_$i';

    if (option.value != null) {
      valueMap[valueKey] = option.value as T;
    }

    items.add({
      'title': option.title,
      'subtitle': option.subtitle,
      'icon': _iconDataToSFSymbol(option.icon),
      'value': valueKey,
      'isSelected': option.isSelected,
      'isDestructive': option.isDestructive,
      'autoDismiss': true,
    });
  }

  try {
    final sheetId = await _nativeBottomSheetChannel.invokeMethod<int>(
      'showSheet',
      {
        'isDark': isDark,
        'title': title,
        'items': items,
        'showDragHandle': true,
        'showCancelButton': showCancelButton,
        'dismissOnTapBackground': true,
        'initialDetent': 'medium',
        'allowedDetents': ['medium', 'large'],
      },
    );

    if (sheetId == null) return null;

    // 使用回调管理器等待用户选择
    final completer = Completer<String?>();
    _callbackManager.registerCompleter(sheetId, completer);

    final selectedValueKey = await completer.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () {
        _callbackManager.removeCompleter(sheetId);
        return null;
      },
    );

    if (selectedValueKey != null && valueMap.containsKey(selectedValueKey)) {
      return valueMap[selectedValueKey];
    }
    return null;
  } catch (e) {
    // 回退到 Flutter 实现
    logger.w(
      'Native bottom sheet failed, falling back to Flutter implementation',
      e,
    );
    return showAppBottomSheet<T>(
      context: context,
      title: title,
      useScrollable: false,
      isDismissible: true,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in options) _OptionTile<T>(option: option),
        ],
      ),
    );
  }
}

/// 将 Flutter IconData 转换为 iOS SF Symbol 名称
String? _iconDataToSFSymbol(IconData? icon) {
  if (icon == null) return null;

  final mapping = <int, String>{
    // 通用操作
    Icons.add_rounded.codePoint: 'plus',
    Icons.add_rounded.codePoint: 'plus',
    Icons.remove_rounded.codePoint: 'minus',
    Icons.delete_rounded.codePoint: 'trash',
    Icons.delete_outline_rounded.codePoint: 'trash',
    Icons.delete_forever_rounded.codePoint: 'trash.fill',
    Icons.edit_rounded.codePoint: 'pencil',
    Icons.share_rounded.codePoint: 'square.and.arrow.up',
    Icons.copy_rounded.codePoint: 'doc.on.doc',
    Icons.content_copy_rounded.codePoint: 'doc.on.doc',
    Icons.paste_rounded.codePoint: 'doc.on.clipboard',

    // 收藏与喜欢
    Icons.favorite_rounded.codePoint: 'heart.fill',
    Icons.favorite_border_rounded.codePoint: 'heart',
    Icons.star_rounded.codePoint: 'star.fill',
    Icons.star_border_rounded.codePoint: 'star',
    Icons.bookmark_rounded.codePoint: 'bookmark.fill',
    Icons.bookmark_border_rounded.codePoint: 'bookmark',
    Icons.bookmarks_rounded.codePoint: 'bookmark',

    // 音乐相关
    Icons.queue_music_rounded.codePoint: 'list.bullet',
    Icons.playlist_add_rounded.codePoint: 'plus.rectangle.on.rectangle',
    Icons.playlist_play_rounded.codePoint: 'play.rectangle',
    Icons.album_rounded.codePoint: 'opticaldisc',
    Icons.music_note_rounded.codePoint: 'music.note',
    Icons.audiotrack_rounded.codePoint: 'music.note',
    Icons.headphones_rounded.codePoint: 'headphones',
    Icons.lyrics_rounded.codePoint: 'text.quote',
    Icons.graphic_eq_rounded.codePoint: 'waveform.path',
    Icons.equalizer_rounded.codePoint: 'slider.horizontal.3',

    // 播放控制
    Icons.play_arrow_rounded.codePoint: 'play.fill',
    Icons.pause_rounded.codePoint: 'pause.fill',
    Icons.stop_rounded.codePoint: 'stop.fill',
    Icons.skip_next_rounded.codePoint: 'forward.fill',
    Icons.skip_previous_rounded.codePoint: 'backward.fill',
    Icons.fast_forward_rounded.codePoint: 'forward.end.fill',
    Icons.fast_rewind_rounded.codePoint: 'backward.end.fill',
    Icons.shuffle_rounded.codePoint: 'shuffle',
    Icons.repeat_rounded.codePoint: 'repeat',
    Icons.repeat_one_rounded.codePoint: 'repeat.1',
    Icons.volume_up_rounded.codePoint: 'speaker.wave.3.fill',
    Icons.volume_down_rounded.codePoint: 'speaker.wave.1.fill',
    Icons.volume_off_rounded.codePoint: 'speaker.slash.fill',
    Icons.volume_mute_rounded.codePoint: 'speaker.fill',

    // 信息与设置
    Icons.info_rounded.codePoint: 'info.circle',
    Icons.info_outline_rounded.codePoint: 'info.circle',
    Icons.help_rounded.codePoint: 'questionmark.circle',
    Icons.help_outline_rounded.codePoint: 'questionmark.circle',
    Icons.settings_rounded.codePoint: 'gearshape',
    Icons.tune_rounded.codePoint: 'slider.horizontal.3',

    // 刷新与同步
    Icons.refresh_rounded.codePoint: 'arrow.clockwise',
    Icons.sync_rounded.codePoint: 'arrow.triangle.2.circlepath',

    // 下载与上传
    Icons.download_rounded.codePoint: 'arrow.down.circle',
    Icons.upload_rounded.codePoint: 'arrow.up.circle',
    Icons.cloud_download_rounded.codePoint: 'icloud.and.arrow.down',
    Icons.cloud_upload_rounded.codePoint: 'icloud.and.arrow.up',
    Icons.file_download_rounded.codePoint: 'arrow.down.doc',
    Icons.file_upload_rounded.codePoint: 'arrow.up.doc',

    // 文件与文件夹
    Icons.folder_rounded.codePoint: 'folder',
    Icons.folder_open_rounded.codePoint: 'folder',
    Icons.create_new_folder_rounded.codePoint: 'folder.badge.plus',
    Icons.drive_file_move_rounded.codePoint: 'folder.badge.questionmark',
    Icons.insert_drive_file_rounded.codePoint: 'doc',

    // 人物
    Icons.person_rounded.codePoint: 'person',
    Icons.person_add_rounded.codePoint: 'person.badge.plus',
    Icons.people_rounded.codePoint: 'person.2',
    Icons.group_rounded.codePoint: 'person.3',

    // 导航与查看
    Icons.check_rounded.codePoint: 'checkmark',
    Icons.check_circle_rounded.codePoint: 'checkmark.circle.fill',
    Icons.close_rounded.codePoint: 'xmark',
    Icons.cancel_rounded.codePoint: 'xmark.circle.fill',
    Icons.more_horiz_rounded.codePoint: 'ellipsis',
    Icons.more_vert_rounded.codePoint: 'ellipsis',
    Icons.search_rounded.codePoint: 'magnifyingglass',
    Icons.visibility_rounded.codePoint: 'eye',
    Icons.visibility_off_rounded.codePoint: 'eye.slash',
    Icons.open_in_new_rounded.codePoint: 'arrow.up.forward.square',
    Icons.launch_rounded.codePoint: 'arrow.up.forward.square',
    Icons.link_rounded.codePoint: 'link',
    Icons.arrow_forward_rounded.codePoint: 'arrow.right',
    Icons.arrow_back_rounded.codePoint: 'arrow.left',
    Icons.arrow_upward_rounded.codePoint: 'arrow.up',
    Icons.arrow_downward_rounded.codePoint: 'arrow.down',
    Icons.expand_more_rounded.codePoint: 'chevron.down',
    Icons.expand_less_rounded.codePoint: 'chevron.up',
    Icons.chevron_right_rounded.codePoint: 'chevron.right',
    Icons.chevron_left_rounded.codePoint: 'chevron.left',

    // 媒体类型
    Icons.photo_rounded.codePoint: 'photo',
    Icons.photo_library_rounded.codePoint: 'photo.on.rectangle',
    Icons.image_rounded.codePoint: 'photo',
    Icons.video_library_rounded.codePoint: 'film',
    Icons.movie_rounded.codePoint: 'film',
    Icons.theaters_rounded.codePoint: 'film',
    Icons.tv_rounded.codePoint: 'tv',
    Icons.live_tv_rounded.codePoint: 'tv',
    Icons.book_rounded.codePoint: 'book',
    Icons.menu_book_rounded.codePoint: 'book.fill',
    Icons.collections_bookmark_rounded.codePoint: 'books.vertical',
    Icons.note_alt_rounded.codePoint: 'note.text',

    // 排序与筛选
    Icons.sort_rounded.codePoint: 'arrow.up.arrow.down',
    Icons.sort_by_alpha_rounded.codePoint: 'textformat.abc',
    Icons.filter_list_rounded.codePoint: 'line.3.horizontal.decrease',
    Icons.filter_alt_rounded.codePoint: 'line.3.horizontal.decrease.circle',

    // 时间与日期
    Icons.access_time_rounded.codePoint: 'clock',
    Icons.schedule_rounded.codePoint: 'clock',
    Icons.calendar_today_rounded.codePoint: 'calendar',
    Icons.event_rounded.codePoint: 'calendar',
    Icons.history_rounded.codePoint: 'clock.arrow.circlepath',

    // 其他
    Icons.home_rounded.codePoint: 'house',
    Icons.language_rounded.codePoint: 'globe',
    Icons.wifi_rounded.codePoint: 'wifi',
    Icons.signal_wifi_off_rounded.codePoint: 'wifi.slash',
    Icons.bluetooth_rounded.codePoint: 'dot.radiowaves.left.and.right',
    Icons.battery_full_rounded.codePoint: 'battery.100',
    Icons.battery_charging_full_rounded.codePoint: 'battery.100.bolt',
    Icons.brightness_high_rounded.codePoint: 'sun.max',
    Icons.brightness_low_rounded.codePoint: 'sun.min',
    Icons.dark_mode_rounded.codePoint: 'moon',
    Icons.light_mode_rounded.codePoint: 'sun.max',
    Icons.lock_rounded.codePoint: 'lock',
    Icons.lock_open_rounded.codePoint: 'lock.open',
    Icons.security_rounded.codePoint: 'shield',
    Icons.warning_rounded.codePoint: 'exclamationmark.triangle',
    Icons.error_rounded.codePoint: 'xmark.circle',
    Icons.error_outline_rounded.codePoint: 'exclamationmark.circle',
    Icons.notifications_rounded.codePoint: 'bell',
    Icons.notifications_off_rounded.codePoint: 'bell.slash',
    Icons.send_rounded.codePoint: 'paperplane',
    Icons.mail_rounded.codePoint: 'envelope',
    Icons.attach_file_rounded.codePoint: 'paperclip',
    Icons.camera_alt_rounded.codePoint: 'camera',
    Icons.qr_code_rounded.codePoint: 'qrcode',
    Icons.crop_rounded.codePoint: 'crop',
    Icons.rotate_left_rounded.codePoint: 'rotate.left',
    Icons.rotate_right_rounded.codePoint: 'rotate.right',
    Icons.zoom_in_rounded.codePoint: 'plus.magnifyingglass',
    Icons.zoom_out_rounded.codePoint: 'minus.magnifyingglass',
    Icons.fullscreen_rounded.codePoint: 'arrow.up.left.and.arrow.down.right',
    Icons.fullscreen_exit_rounded.codePoint:
        'arrow.down.right.and.arrow.up.left',
    Icons.cast_rounded.codePoint: 'airplayvideo',
    Icons.airplay_rounded.codePoint: 'airplayvideo',
    Icons.subtitles_rounded.codePoint: 'captions.bubble',
    Icons.closed_caption_rounded.codePoint: 'captions.bubble',
    Icons.speed_rounded.codePoint: 'speedometer',
    Icons.timer_rounded.codePoint: 'timer',
    Icons.aspect_ratio_rounded.codePoint: 'aspectratio',
    Icons.hd_rounded.codePoint: 'sparkles.rectangle.stack',
  };

  return mapping[icon.codePoint];
}

/// 选项项
class OptionItem<T> {
  const OptionItem({
    required this.icon,
    required this.title,
    this.subtitle,
    this.iconColor,
    this.value,
    this.onTap,
    this.isSelected = false,
    this.isDestructive = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? iconColor;
  final T? value;
  final VoidCallback? onTap;
  final bool isSelected;
  final bool isDestructive;
}

class _OptionTile<T> extends StatelessWidget {
  const _OptionTile({required this.option});

  final OptionItem<T> option;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveColor = option.isDestructive
        ? AppColors.error
        : (option.iconColor ??
              (isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface));

    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: effectiveColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(option.icon, color: effectiveColor, size: 20),
      ),
      title: Text(
        option.title,
        style: TextStyle(
          color: option.isDestructive ? AppColors.error : null,
          fontWeight: option.isSelected ? FontWeight.w600 : null,
        ),
      ),
      subtitle: option.subtitle != null ? Text(option.subtitle!) : null,
      trailing: option.isSelected
          ? Icon(Icons.check_rounded, color: AppColors.primary)
          : null,
      onTap: () {
        if (option.value != null) {
          Navigator.pop(context, option.value);
        } else {
          option.onTap?.call();
        }
      },
    );
  }
}
