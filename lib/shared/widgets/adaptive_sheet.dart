import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/app/theme/ui_style.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/utils/platform_capabilities.dart';
import 'package:my_nas/shared/providers/ui_style_provider.dart';

/// 自适应弹框类型
enum AdaptiveSheetType {
  /// 自动选择：移动端底部弹框，桌面端居中对话框
  auto,

  /// 强制底部弹框
  bottomSheet,

  /// 强制居中对话框
  dialog,

  /// 侧边面板（桌面端从右侧滑出）
  sidePanel,
}

/// 自适应弹框尺寸
enum AdaptiveSheetSize {
  /// 小尺寸（对话框 400px）
  small,

  /// 中等尺寸（对话框 560px）
  medium,

  /// 大尺寸（对话框 720px）
  large,

  /// 超大尺寸（对话框 900px）
  extraLarge,
}

/// 显示自适应弹框
///
/// 根据平台自动选择最佳展示方式：
/// - 移动端：底部弹框 (ModalBottomSheet)
/// - 桌面端：居中对话框 (Dialog) 或侧边面板
///
/// [type] 弹框类型，默认自动选择
/// [size] 弹框尺寸，仅对桌面端对话框有效
/// [title] 标题
/// [builder] 内容构建器
/// [useScrollable] 是否使用可拖拽滚动（移动端底部弹框）
/// [initialChildSize] 初始高度比例（移动端底部弹框）
/// [barrierDismissible] 点击外部是否关闭
/// [showCloseButton] 是否显示关闭按钮
/// [actions] 底部操作按钮
Future<T?> showAdaptiveSheet<T>({
  required BuildContext context,
  required Widget Function(BuildContext context, ScrollController? scrollController) builder,
  AdaptiveSheetType type = AdaptiveSheetType.auto,
  AdaptiveSheetSize size = AdaptiveSheetSize.medium,
  String? title,
  Widget? titleWidget,
  bool useScrollable = true,
  double initialChildSize = 0.5,
  double minChildSize = 0.25,
  double maxChildSize = 0.9,
  bool barrierDismissible = true,
  bool showCloseButton = true,
  List<Widget>? actions,
  bool useSafeArea = true,
  bool enableDrag = true,
}) {
  // 确定实际使用的类型
  final effectiveType = _resolveSheetType(type, context);

  switch (effectiveType) {
    case AdaptiveSheetType.bottomSheet:
      return _showBottomSheet<T>(
        context: context,
        builder: builder,
        title: title,
        titleWidget: titleWidget,
        useScrollable: useScrollable,
        initialChildSize: initialChildSize,
        minChildSize: minChildSize,
        maxChildSize: maxChildSize,
        useSafeArea: useSafeArea,
        enableDrag: enableDrag,
        actions: actions,
      );

    case AdaptiveSheetType.dialog:
      return _showCenterDialog<T>(
        context: context,
        builder: builder,
        size: size,
        title: title,
        titleWidget: titleWidget,
        barrierDismissible: barrierDismissible,
        showCloseButton: showCloseButton,
        actions: actions,
      );

    case AdaptiveSheetType.sidePanel:
      return _showSidePanel<T>(
        context: context,
        builder: builder,
        size: size,
        title: title,
        titleWidget: titleWidget,
        barrierDismissible: barrierDismissible,
        showCloseButton: showCloseButton,
        actions: actions,
      );

    case AdaptiveSheetType.auto:
      // 不应该到达这里，已在 _resolveSheetType 中处理
      return _showBottomSheet<T>(
        context: context,
        builder: builder,
        title: title,
        titleWidget: titleWidget,
        useScrollable: useScrollable,
        initialChildSize: initialChildSize,
        minChildSize: minChildSize,
        maxChildSize: maxChildSize,
        useSafeArea: useSafeArea,
        enableDrag: enableDrag,
        actions: actions,
      );
  }
}

/// 显示自适应确认对话框
///
/// 移动端：底部弹框样式
/// 桌面端：居中对话框样式
Future<bool?> showAdaptiveConfirmDialog({
  required BuildContext context,
  required String title,
  String? message,
  String confirmText = '确定',
  String cancelText = '取消',
  bool isDestructive = false,
}) => showAdaptiveSheet<bool>(
    context: context,
    title: title,
    size: AdaptiveSheetSize.small,
    useScrollable: false,
    showCloseButton: false,
    builder: (context, _) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: message != null
          ? Text(
              message,
              style: context.textTheme.bodyLarge,
            )
          : const SizedBox.shrink(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: Text(cancelText),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        style: isDestructive
            ? FilledButton.styleFrom(
                backgroundColor: AppColors.error,
              )
            : null,
        child: Text(confirmText),
      ),
    ],
  );

/// 显示自适应选项菜单
Future<T?> showAdaptiveOptions<T>({
  required BuildContext context,
  required List<AdaptiveOptionItem<T>> options,
  String? title,
}) => showAdaptiveSheet<T>(
    context: context,
    title: title,
    size: AdaptiveSheetSize.small,
    useScrollable: false,
    showCloseButton: false,
    builder: (context, _) => Column(
      mainAxisSize: MainAxisSize.min,
      children: options.map((option) => _AdaptiveOptionTile<T>(option: option)).toList(),
    ),
  );

/// 选项项
class AdaptiveOptionItem<T> {
  const AdaptiveOptionItem({
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

// ============================================================================
// 私有实现
// ============================================================================

AdaptiveSheetType _resolveSheetType(AdaptiveSheetType type, BuildContext context) {
  if (type != AdaptiveSheetType.auto) return type;

  // 与 MainScaffold 保持一致的 Shell 形态判断：桌面平台始终走 Dialog，
  // Web ≥840 走 Dialog，移动端 / 小窗口 Web 仍用底部 Sheet。
  if (context.isDesktopLayout) {
    return AdaptiveSheetType.dialog;
  }
  return AdaptiveSheetType.bottomSheet;
}

double _getDialogWidth(AdaptiveSheetSize size) {
  switch (size) {
    case AdaptiveSheetSize.small:
      return 400;
    case AdaptiveSheetSize.medium:
      return 560;
    case AdaptiveSheetSize.large:
      return 720;
    case AdaptiveSheetSize.extraLarge:
      return 900;
  }
}

double _getSidePanelWidth(AdaptiveSheetSize size) {
  switch (size) {
    case AdaptiveSheetSize.small:
      return 320;
    case AdaptiveSheetSize.medium:
      return 400;
    case AdaptiveSheetSize.large:
      return 480;
    case AdaptiveSheetSize.extraLarge:
      return 560;
  }
}

/// 显示底部弹框（移动端）
Future<T?> _showBottomSheet<T>({
  required BuildContext context,
  required Widget Function(BuildContext context, ScrollController? scrollController) builder,
  String? title,
  Widget? titleWidget,
  bool useScrollable = true,
  double initialChildSize = 0.5,
  double minChildSize = 0.25,
  double maxChildSize = 0.9,
  bool useSafeArea = true,
  bool enableDrag = true,
  List<Widget>? actions,
}) => showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: useSafeArea,
    backgroundColor: Colors.transparent,
    enableDrag: enableDrag,
    builder: (context) => _MobileBottomSheet(
      title: title,
      titleWidget: titleWidget,
      useScrollable: useScrollable,
      initialChildSize: initialChildSize,
      minChildSize: minChildSize,
      maxChildSize: maxChildSize,
      actions: actions,
      builder: builder,
    ),
  );

/// 显示居中对话框（桌面端）
Future<T?> _showCenterDialog<T>({
  required BuildContext context,
  required Widget Function(BuildContext context, ScrollController? scrollController) builder,
  AdaptiveSheetSize size = AdaptiveSheetSize.medium,
  String? title,
  Widget? titleWidget,
  bool barrierDismissible = true,
  bool showCloseButton = true,
  List<Widget>? actions,
}) => showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (context) => _DesktopDialog(
      width: _getDialogWidth(size),
      title: title,
      titleWidget: titleWidget,
      showCloseButton: showCloseButton,
      actions: actions,
      builder: builder,
    ),
  );

/// 显示侧边面板（桌面端）
Future<T?> _showSidePanel<T>({
  required BuildContext context,
  required Widget Function(BuildContext context, ScrollController? scrollController) builder,
  AdaptiveSheetSize size = AdaptiveSheetSize.medium,
  String? title,
  Widget? titleWidget,
  bool barrierDismissible = true,
  bool showCloseButton = true,
  List<Widget>? actions,
}) => showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (context, animation, secondaryAnimation) => _DesktopSidePanel(
      width: _getSidePanelWidth(size),
      title: title,
      titleWidget: titleWidget,
      showCloseButton: showCloseButton,
      actions: actions,
      builder: builder,
    ),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final offset = Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      ));
      return SlideTransition(position: offset, child: child);
    },
  );

// ============================================================================
// 移动端底部弹框组件
// ============================================================================

class _MobileBottomSheet extends ConsumerWidget {
  const _MobileBottomSheet({
    required this.builder,
    this.title,
    this.titleWidget,
    this.useScrollable = true,
    this.initialChildSize = 0.5,
    this.minChildSize = 0.25,
    this.maxChildSize = 0.9,
    this.actions,
  });

  final Widget Function(BuildContext context, ScrollController? scrollController) builder;
  final String? title;
  final Widget? titleWidget;
  final bool useScrollable;
  final double initialChildSize;
  final double minChildSize;
  final double maxChildSize;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiStyle = ref.watch(uiStyleProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final glassStyle = GlassTheme.getStyle(uiStyle, isDark: isDark);
    final bottomPadding = _getBottomPadding(context, uiStyle);
    final borderRadius = const BorderRadius.vertical(top: Radius.circular(24));

    final bgColor = glassStyle.needsBlur
        ? (isDark
            ? AppColors.darkSurface.withValues(alpha: (glassStyle.backgroundOpacity + 0.15).clamp(0.0, 1.0))
            : AppColors.lightSurface.withValues(alpha: (glassStyle.backgroundOpacity + 0.1).clamp(0.0, 1.0)))
        : (isDark ? AppColors.darkSurface : AppColors.lightSurface);

    final decoration = BoxDecoration(
      color: bgColor,
      borderRadius: borderRadius,
      border: Border(
        top: BorderSide(
          color: isDark ? AppColors.glassStroke : AppColors.lightOutline.withValues(alpha: 0.2),
        ),
      ),
    );

    Widget buildContent(ScrollController? scrollController) => Column(
          mainAxisSize: useScrollable ? MainAxisSize.max : MainAxisSize.min,
          children: [
            _buildDragHandle(isDark),
            if (titleWidget != null || title != null) _buildHeader(context, isDark),
            if (useScrollable)
              Expanded(child: builder(context, scrollController))
            else
              Flexible(child: SingleChildScrollView(child: builder(context, null))),
            if (actions != null && actions!.isNotEmpty) _buildActions(context, isDark),
            SizedBox(height: bottomPadding),
          ],
        );

    Widget content;
    if (useScrollable) {
      content = DraggableScrollableSheet(
        initialChildSize: initialChildSize,
        minChildSize: minChildSize,
        maxChildSize: maxChildSize,
        expand: false,
        builder: (context, scrollController) => DecoratedBox(
          decoration: decoration,
          child: buildContent(scrollController),
        ),
      );
    } else {
      content = DecoratedBox(
        decoration: decoration,
        child: buildContent(null),
      );
    }

    if (glassStyle.needsBlur) {
      content = ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: glassStyle.blurFilter!,
          child: content,
        ),
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
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
        child: titleWidget,
      );
    }

    if (title != null && title!.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title!,
                style: context.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildActions(BuildContext context, bool isDark) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            for (int i = 0; i < actions!.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.sm),
              actions![i],
            ],
          ],
        ),
      );
}

// ============================================================================
// 桌面端居中对话框组件
// ============================================================================

class _DesktopDialog extends ConsumerWidget {
  const _DesktopDialog({
    required this.builder,
    required this.width,
    this.title,
    this.titleWidget,
    this.showCloseButton = true,
    this.actions,
  });

  final Widget Function(BuildContext context, ScrollController? scrollController) builder;
  final double width;
  final String? title;
  final Widget? titleWidget;
  final bool showCloseButton;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiStyle = ref.watch(uiStyleProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final glassStyle = GlassTheme.getStyle(uiStyle, isDark: isDark);
    final screenHeight = MediaQuery.of(context).size.height;
    final maxHeight = screenHeight * 0.85;

    final bgColor = glassStyle.needsBlur
        ? (isDark
            ? AppColors.darkSurface.withValues(alpha: (glassStyle.backgroundOpacity + 0.2).clamp(0.0, 1.0))
            : AppColors.lightSurface.withValues(alpha: (glassStyle.backgroundOpacity + 0.15).clamp(0.0, 1.0)))
        : (isDark ? AppColors.darkSurface : AppColors.lightSurface);

    final borderRadius = BorderRadius.circular(16);

    Widget content = Container(
      width: width,
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: borderRadius,
        border: Border.all(
          color: isDark ? AppColors.glassStroke : AppColors.lightOutline.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (titleWidget != null || title != null || showCloseButton)
            _buildHeader(context, isDark),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: builder(context, null),
            ),
          ),
          if (actions != null && actions!.isNotEmpty) _buildActions(context, isDark),
        ],
      ),
    );

    if (glassStyle.needsBlur) {
      content = ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: glassStyle.blurFilter!,
          child: content,
        ),
      );
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: content,
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark) => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.md, AppSpacing.sm),
        child: Row(
          children: [
            if (titleWidget != null)
              Expanded(child: titleWidget!)
            else if (title != null && title!.isNotEmpty)
              Expanded(
                child: Text(
                  title!,
                  style: context.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                  ),
                ),
              )
            else
              const Spacer(),
            if (showCloseButton)
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
                iconSize: 20,
                tooltip: '关闭',
              ),
          ],
        ),
      );

  Widget _buildActions(BuildContext context, bool isDark) => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            for (int i = 0; i < actions!.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.sm),
              actions![i],
            ],
          ],
        ),
      );
}

// ============================================================================
// 桌面端侧边面板组件
// ============================================================================

class _DesktopSidePanel extends ConsumerWidget {
  const _DesktopSidePanel({
    required this.builder,
    required this.width,
    this.title,
    this.titleWidget,
    this.showCloseButton = true,
    this.actions,
  });

  final Widget Function(BuildContext context, ScrollController? scrollController) builder;
  final double width;
  final String? title;
  final Widget? titleWidget;
  final bool showCloseButton;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiStyle = ref.watch(uiStyleProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final glassStyle = GlassTheme.getStyle(uiStyle, isDark: isDark);

    final bgColor = glassStyle.needsBlur
        ? (isDark
            ? AppColors.darkSurface.withValues(alpha: (glassStyle.backgroundOpacity + 0.25).clamp(0.0, 1.0))
            : AppColors.lightSurface.withValues(alpha: (glassStyle.backgroundOpacity + 0.2).clamp(0.0, 1.0)))
        : (isDark ? AppColors.darkSurface : AppColors.lightSurface);

    Widget content = Container(
      width: width,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          left: BorderSide(
            color: isDark ? AppColors.glassStroke : AppColors.lightOutline.withValues(alpha: 0.2),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(-4, 0),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (titleWidget != null || title != null || showCloseButton)
              _buildHeader(context, isDark),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: builder(context, null),
              ),
            ),
            if (actions != null && actions!.isNotEmpty) _buildActions(context, isDark),
          ],
        ),
      ),
    );

    if (glassStyle.needsBlur) {
      content = ClipRect(
        child: BackdropFilter(
          filter: glassStyle.blurFilter!,
          child: content,
        ),
      );
    }

    return Align(
      alignment: Alignment.centerRight,
      child: content,
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark) => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.md, AppSpacing.sm),
        child: Row(
          children: [
            if (showCloseButton)
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
                iconSize: 20,
                tooltip: '关闭',
              ),
            const SizedBox(width: AppSpacing.sm),
            if (titleWidget != null)
              Expanded(child: titleWidget!)
            else if (title != null && title!.isNotEmpty)
              Expanded(
                child: Text(
                  title!,
                  style: context.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface,
                  ),
                ),
              )
            else
              const Spacer(),
          ],
        ),
      );

  Widget _buildActions(BuildContext context, bool isDark) => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            for (int i = 0; i < actions!.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.sm),
              actions![i],
            ],
          ],
        ),
      );
}

// ============================================================================
// 选项列表项组件
// ============================================================================

class _AdaptiveOptionTile<T> extends StatelessWidget {
  const _AdaptiveOptionTile({required this.option});

  final AdaptiveOptionItem<T> option;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDesktop = PlatformCapabilities.isDesktop || context.isDesktop;
    final effectiveColor = option.isDestructive
        ? AppColors.error
        : (option.iconColor ?? (isDark ? AppColors.darkOnSurface : AppColors.lightOnSurface));

    // 桌面端使用更紧凑的布局
    final iconSize = isDesktop ? 18.0 : 20.0;
    final containerSize = isDesktop ? 36.0 : 40.0;
    final verticalPadding = isDesktop ? 8.0 : 12.0;

    return InkWell(
      onTap: () {
        if (option.value != null) {
          Navigator.pop(context, option.value);
        } else {
          option.onTap?.call();
        }
      },
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: verticalPadding),
        child: Row(
          children: [
            Container(
              width: containerSize,
              height: containerSize,
              decoration: BoxDecoration(
                color: effectiveColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(isDesktop ? 8 : 10),
              ),
              child: Icon(option.icon, color: effectiveColor, size: iconSize),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    option.title,
                    style: TextStyle(
                      color: option.isDestructive ? AppColors.error : null,
                      fontWeight: option.isSelected ? FontWeight.w600 : null,
                      fontSize: isDesktop ? 14 : 16,
                    ),
                  ),
                  if (option.subtitle != null)
                    Text(
                      option.subtitle!,
                      style: TextStyle(
                        color: isDark
                            ? AppColors.darkOnSurfaceVariant
                            : AppColors.lightOnSurfaceVariant,
                        fontSize: isDesktop ? 12 : 14,
                      ),
                    ),
                ],
              ),
            ),
            if (option.isSelected)
              Icon(Icons.check_rounded, color: AppColors.primary, size: iconSize + 2),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 工具函数
// ============================================================================

/// 计算底部弹窗的底部间距
///
/// 在 iOS 玻璃风格下需要额外添加原生 Tab Bar 的高度，
/// 因为原生 UITabBar 悬浮在 Flutter 内容之上。
double _getBottomPadding(BuildContext context, UIStyle uiStyle) {
  final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
  // 确保至少有一点底部间距
  var padding = bottomPadding > 0 ? bottomPadding : AppSpacing.lg;

  // iOS 玻璃风格下需要额外添加原生 Tab Bar 的高度
  // 因为原生 UITabBar 悬浮在 Flutter 内容之上
  if (!kIsWeb && Platform.isIOS && uiStyle.isGlass) {
    // UITabBar 标准高度约 49pt
    padding += 49;
  }

  return padding;
}
