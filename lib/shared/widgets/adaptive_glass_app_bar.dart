import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/ui_style.dart';
import 'package:my_nas/shared/providers/ui_style_provider.dart';

/// 自适应玻璃顶栏 - 根据平台和 UI 风格自动选择最佳实现
///
/// iOS 26+: 使用原生 UIVisualEffectView (Liquid Glass)
/// iOS 13-25/macOS: 使用原生模糊效果
/// Android/Windows/Linux: 使用 Flutter BackdropFilter
/// 经典模式: 使用不透明背景
///
/// 使用示例:
/// ```dart
/// AdaptiveGlassAppBar(
///   title: Text('标题'),
///   leading: BackButton(),
///   actions: [IconButton(...)],
///   backgroundColor: Colors.blue.withOpacity(0.1), // 可选染色
/// )
/// ```
class AdaptiveGlassAppBar extends ConsumerWidget {
  const AdaptiveGlassAppBar({
    this.title,
    this.leading,
    this.actions,
    this.bottom,
    this.backgroundColor,
    this.elevation = 0,
    this.toolbarHeight,
    this.expandedHeight,
    this.flexibleSpace,
    this.pinned = true,
    this.floating = false,
    this.snap = false,
    this.forceClassic = false,
    this.centerTitle,
    this.titleSpacing,
    this.automaticallyImplyLeading = true,
    super.key,
  });

  /// 标题组件
  final Widget? title;

  /// 左侧组件（通常是返回按钮）
  final Widget? leading;

  /// 右侧操作按钮列表
  final List<Widget>? actions;

  /// 底部组件（如 TabBar）
  final PreferredSizeWidget? bottom;

  /// 背景颜色/染色（玻璃模式下会作为染色层）
  final Color? backgroundColor;

  /// 阴影高度
  final double elevation;

  /// 工具栏高度
  final double? toolbarHeight;

  /// 展开高度（用于 SliverAppBar）
  final double? expandedHeight;

  /// 弹性空间（用于 SliverAppBar）
  final Widget? flexibleSpace;

  /// 是否固定在顶部
  final bool pinned;

  /// 是否浮动
  final bool floating;

  /// 是否快速显示
  final bool snap;

  /// 强制使用经典模式（不使用玻璃效果）
  final bool forceClassic;

  /// 是否居中标题
  final bool? centerTitle;

  /// 标题间距
  final double? titleSpacing;

  /// 是否自动添加返回按钮
  final bool automaticallyImplyLeading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiStyle = ref.watch(uiStyleProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 强制经典模式或设置为经典风格时，使用不透明背景
    if (forceClassic || !uiStyle.isGlass) {
      return _buildClassicAppBar(context, isDark);
    }

    // 玻璃模式
    if (PlatformGlassConfig.shouldUseNativeBlur(uiStyle)) {
      return _buildNativeGlassAppBar(context, uiStyle, isDark);
    }

    return _buildFlutterGlassAppBar(context, uiStyle, isDark);
  }

  /// 经典模式 - 不透明背景
  Widget _buildClassicAppBar(BuildContext context, bool isDark) {
    final bgColor = backgroundColor ??
        (isDark ? AppColors.darkSurface : AppColors.lightSurface);

    return SliverAppBar(
      title: title,
      leading: leading,
      actions: actions,
      bottom: bottom,
      backgroundColor: bgColor,
      elevation: elevation,
      toolbarHeight: toolbarHeight ?? kToolbarHeight,
      expandedHeight: expandedHeight,
      flexibleSpace: flexibleSpace,
      pinned: pinned,
      floating: floating,
      snap: snap,
      centerTitle: centerTitle,
      titleSpacing: titleSpacing,
      automaticallyImplyLeading: automaticallyImplyLeading,
      surfaceTintColor: Colors.transparent,
    );
  }

  /// iOS/macOS 原生玻璃效果
  Widget _buildNativeGlassAppBar(
    BuildContext context,
    UIStyle uiStyle,
    bool isDark,
  ) {
    final height = (toolbarHeight ?? kToolbarHeight) +
        (bottom?.preferredSize.height ?? 0) +
        MediaQuery.of(context).padding.top;

    final nativeStyle =
        PlatformGlassConfig.getNativeBlurStyle(uiStyle, isDark: isDark);

    final creationParams = <String, dynamic>{
      'style': nativeStyle,
      'material': nativeStyle,
      'isDark': isDark,
      'cornerRadius': 0.0,
      'enableBorder': false,
      'borderOpacity': 0.0,
      'enableVibrancy': false,
      'blendingMode': 'behindWindow',
      'useLiquidGlass': true,
      'isInteractive': false,
    };

    final viewKey = ValueKey('appbar_blur_${isDark}_${uiStyle.name}');

    return SliverPersistentHeader(
      pinned: pinned,
      floating: floating,
      delegate: _GlassAppBarDelegate(
        minHeight: (toolbarHeight ?? kToolbarHeight) +
            (bottom?.preferredSize.height ?? 0) +
            MediaQuery.of(context).padding.top,
        maxHeight: expandedHeight ?? height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 原生模糊背景
            Positioned.fill(
              child: _buildPlatformView(creationParams, viewKey),
            ),
            // 染色层
            if (backgroundColor != null)
              Positioned.fill(
                child: ColoredBox(color: backgroundColor!),
              ),
            // 底部边框
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: 0.5,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.05),
              ),
            ),
            // 内容
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  _buildToolbar(context, isDark),
                  if (bottom != null) bottom!,
                ],
              ),
            ),
          ],
        ),
        flexibleSpace: flexibleSpace,
      ),
    );
  }

  Widget _buildPlatformView(Map<String, dynamic> creationParams, Key viewKey) {
    const viewType = 'com.kkape.mynas/native_blur_view';

    if (Platform.isIOS) {
      return UiKitView(
        key: viewKey,
        viewType: viewType,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      );
    } else if (Platform.isMacOS) {
      return AppKitView(
        key: viewKey,
        viewType: viewType,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      );
    }

    return const SizedBox.shrink();
  }

  /// Flutter BackdropFilter 玻璃效果
  Widget _buildFlutterGlassAppBar(
    BuildContext context,
    UIStyle uiStyle,
    bool isDark,
  ) {
    final glassStyle = GlassTheme.getNavBarStyle(uiStyle, isDark: isDark);
    final optimizedStyle =
        PlatformGlassConfig.getOptimizedStyle(glassStyle, isDark: isDark);
    final bgColor = GlassTheme.getBackgroundColor(optimizedStyle,
        isDark: isDark, tintColor: backgroundColor);

    final height = (toolbarHeight ?? kToolbarHeight) +
        (bottom?.preferredSize.height ?? 0) +
        MediaQuery.of(context).padding.top;

    return SliverPersistentHeader(
      pinned: pinned,
      floating: floating,
      delegate: _GlassAppBarDelegate(
        minHeight: (toolbarHeight ?? kToolbarHeight) +
            (bottom?.preferredSize.height ?? 0) +
            MediaQuery.of(context).padding.top,
        maxHeight: expandedHeight ?? height,
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: optimizedStyle.blurIntensity,
              sigmaY: optimizedStyle.blurIntensity,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: bgColor,
                border: Border(
                  bottom: BorderSide(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.black.withValues(alpha: 0.05),
                    width: 0.5,
                  ),
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    _buildToolbar(context, isDark),
                    if (bottom != null) bottom!,
                  ],
                ),
              ),
            ),
          ),
        ),
        flexibleSpace: flexibleSpace,
      ),
    );
  }

  Widget _buildToolbar(BuildContext context, bool isDark) {
    return SizedBox(
      height: toolbarHeight ?? kToolbarHeight,
      child: NavigationToolbar(
        leading: leading ??
            (automaticallyImplyLeading && Navigator.canPop(context)
                ? const BackButton()
                : null),
        middle: title,
        trailing: actions != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: actions!,
              )
            : null,
        centerMiddle: centerTitle ?? true,
        middleSpacing: titleSpacing ?? NavigationToolbar.kMiddleSpacing,
      ),
    );
  }
}

/// 玻璃顶栏委托
class _GlassAppBarDelegate extends SliverPersistentHeaderDelegate {
  _GlassAppBarDelegate({
    required this.minHeight,
    required this.maxHeight,
    required this.child,
    this.flexibleSpace,
  });

  final double minHeight;
  final double maxHeight;
  final Widget child;
  final Widget? flexibleSpace;

  @override
  double get minExtent => minHeight;

  @override
  double get maxExtent => maxHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    if (flexibleSpace != null && maxHeight > minHeight) {
      final progress = (shrinkOffset / (maxHeight - minHeight)).clamp(0.0, 1.0);
      return Stack(
        fit: StackFit.expand,
        children: [
          Opacity(
            opacity: 1.0 - progress,
            child: flexibleSpace,
          ),
          Opacity(
            opacity: progress,
            child: child,
          ),
        ],
      );
    }
    return child;
  }

  @override
  bool shouldRebuild(_GlassAppBarDelegate oldDelegate) =>
      minHeight != oldDelegate.minHeight ||
      maxHeight != oldDelegate.maxHeight ||
      child != oldDelegate.child ||
      flexibleSpace != oldDelegate.flexibleSpace;
}

/// 简化版玻璃顶栏 - 用于非 Sliver 场景
///
/// 适用于普通 Scaffold 的 AppBar 位置
///
/// iOS 26 Liquid Glass 设计特点：
/// - 玻璃模式下无边框，与内容无缝融合
/// - 按钮悬浮在玻璃层上方，有独立的玻璃背景
/// - 经典模式保留边框作为视觉分隔
class AdaptiveGlassHeader extends ConsumerWidget {
  const AdaptiveGlassHeader({
    required this.child,
    this.height,
    this.backgroundColor,
    this.enableBorder,
    this.forceClassic = false,
    super.key,
  });

  /// 子组件（顶栏内容）
  final Widget child;

  /// 高度（不包含安全区域）
  final double? height;

  /// 背景颜色/染色
  final Color? backgroundColor;

  /// 是否显示底部边框
  /// 默认行为：玻璃模式下 false，经典模式下 true
  final bool? enableBorder;

  /// 强制使用经典模式
  final bool forceClassic;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiStyle = ref.watch(uiStyleProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final safeTop = MediaQuery.of(context).padding.top;

    // 确定是否使用玻璃模式
    final isGlassMode = !forceClassic && uiStyle.isGlass;

    // 边框默认行为：玻璃模式下 false（iOS 26 无边框设计），经典模式下 true
    final showBorder = enableBorder ?? !isGlassMode;

    // 经典模式
    if (!isGlassMode) {
      return _buildClassicHeader(context, isDark, safeTop, showBorder);
    }

    // 玻璃模式
    if (PlatformGlassConfig.shouldUseNativeBlur(uiStyle)) {
      return _buildNativeGlassHeader(context, uiStyle, isDark, safeTop, showBorder);
    }

    return _buildFlutterGlassHeader(context, uiStyle, isDark, safeTop, showBorder);
  }

  Widget _buildClassicHeader(
    BuildContext context,
    bool isDark,
    double safeTop,
    bool showBorder,
  ) {
    final bgColor = backgroundColor ??
        (isDark ? AppColors.darkSurface : AppColors.lightSurface);

    return Container(
      padding: EdgeInsets.only(top: safeTop),
      decoration: BoxDecoration(
        color: bgColor,
        border: showBorder
            ? Border(
                bottom: BorderSide(
                  color: isDark
                      ? AppColors.darkOutline.withValues(alpha: 0.2)
                      : AppColors.lightOutline.withValues(alpha: 0.3),
                ),
              )
            : null,
      ),
      child: SizedBox(
        height: height,
        child: child,
      ),
    );
  }

  Widget _buildNativeGlassHeader(
    BuildContext context,
    UIStyle uiStyle,
    bool isDark,
    double safeTop,
    bool showBorder,
  ) {
    final nativeStyle =
        PlatformGlassConfig.getNativeBlurStyle(uiStyle, isDark: isDark);

    final creationParams = <String, dynamic>{
      'style': nativeStyle,
      'material': nativeStyle,
      'isDark': isDark,
      'cornerRadius': 0.0,
      'enableBorder': false,
      'borderOpacity': 0.0,
      'enableVibrancy': false,
      'blendingMode': 'behindWindow',
      'useLiquidGlass': true,
      'isInteractive': false,
    };

    final viewKey = ValueKey('header_blur_${isDark}_${uiStyle.name}');

    return Stack(
      children: [
        // 原生模糊背景
        Positioned.fill(
          child: _buildPlatformView(creationParams, viewKey),
        ),
        // 染色层
        if (backgroundColor != null)
          Positioned.fill(
            child: ColoredBox(color: backgroundColor!),
          ),
        // 底部边框（iOS 26 Liquid Glass 默认无边框）
        if (showBorder)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: 0.5,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.black.withValues(alpha: 0.05),
            ),
          ),
        // 内容
        Padding(
          padding: EdgeInsets.only(top: safeTop),
          child: SizedBox(
            height: height,
            child: child,
          ),
        ),
      ],
    );
  }

  Widget _buildPlatformView(Map<String, dynamic> creationParams, Key viewKey) {
    const viewType = 'com.kkape.mynas/native_blur_view';

    if (!kIsWeb && Platform.isIOS) {
      return UiKitView(
        key: viewKey,
        viewType: viewType,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      );
    } else if (!kIsWeb && Platform.isMacOS) {
      return AppKitView(
        key: viewKey,
        viewType: viewType,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildFlutterGlassHeader(
    BuildContext context,
    UIStyle uiStyle,
    bool isDark,
    double safeTop,
    bool showBorder,
  ) {
    final glassStyle = GlassTheme.getNavBarStyle(uiStyle, isDark: isDark);
    final optimizedStyle =
        PlatformGlassConfig.getOptimizedStyle(glassStyle, isDark: isDark);
    final bgColor = GlassTheme.getBackgroundColor(optimizedStyle,
        isDark: isDark, tintColor: backgroundColor);

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: optimizedStyle.blurIntensity,
          sigmaY: optimizedStyle.blurIntensity,
        ),
        child: Container(
          padding: EdgeInsets.only(top: safeTop),
          decoration: BoxDecoration(
            color: bgColor,
            border: showBorder
                ? Border(
                    bottom: BorderSide(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.1)
                          : Colors.black.withValues(alpha: 0.05),
                      width: 0.5,
                    ),
                  )
                : null,
          ),
          child: SizedBox(
            height: height,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// 玻璃效果按钮 - iOS 26 风格的悬浮按钮
///
/// iOS 26 的按钮不再集成在导航栏中，而是悬浮在玻璃层上方
/// 带有自己的玻璃背景
class GlassButton extends ConsumerWidget {
  const GlassButton({
    required this.child,
    this.onPressed,
    this.padding = const EdgeInsets.all(8),
    this.borderRadius = 10,
    super.key,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final EdgeInsets padding;
  final double borderRadius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiStyle = ref.watch(uiStyleProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 经典模式 - 普通按钮
    if (!uiStyle.isGlass) {
      return IconButton(
        onPressed: onPressed,
        padding: padding,
        icon: child,
      );
    }

    // 玻璃模式 - 带玻璃背景的按钮
    final glassStyle = GlassTheme.getStyle(uiStyle, isDark: isDark);
    final bgColor = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.05);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: glassStyle.borderOpacity)
        : Colors.black.withValues(alpha: glassStyle.borderOpacity * 0.5);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(borderRadius),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: padding,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(borderRadius),
                border: Border.all(color: borderColor, width: 0.5),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// 玻璃效果图标按钮 - iOS 26 风格的悬浮图标按钮
///
/// 专门用于顶栏的图标按钮，在玻璃模式下：
/// - 圆形玻璃背景
/// - 细微边框
/// - 轻微模糊效果
///
/// 经典模式下使用普通 IconButton
class GlassIconButton extends ConsumerWidget {
  const GlassIconButton({
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = 22,
    this.color,
    super.key,
  });

  /// 图标
  final IconData icon;

  /// 点击回调
  final VoidCallback? onPressed;

  /// 提示文字
  final String? tooltip;

  /// 图标大小
  final double size;

  /// 图标颜色（默认根据主题自动选择）
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiStyle = ref.watch(uiStyleProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = color ?? (isDark ? Colors.white : Colors.black87);

    // 经典模式 - 普通 IconButton
    if (!uiStyle.isGlass) {
      return IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: size, color: iconColor),
        tooltip: tooltip,
      );
    }

    // 玻璃模式 - 悬浮玻璃按钮
    final glassStyle = GlassTheme.getStyle(uiStyle, isDark: isDark);
    final bgColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.06);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: glassStyle.borderOpacity * 0.8)
        : Colors.black.withValues(alpha: glassStyle.borderOpacity * 0.4);

    Widget button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: bgColor,
                shape: BoxShape.circle,
                border: Border.all(color: borderColor, width: 0.5),
              ),
              child: Icon(icon, size: size, color: iconColor),
            ),
          ),
        ),
      ),
    );

    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }

    return button;
  }
}

/// 玻璃效果按钮组 - 将多个按钮组合在一起
///
/// iOS 26+: 使用原生 UIGlassEffect 实现真正的 Liquid Glass 效果
/// iOS 13-25: 使用原生 UIBlurEffect 回退
/// 其他平台: 使用 Flutter BackdropFilter
///
/// 多个相邻的按钮会合并在同一个胶囊形玻璃背景中
class GlassButtonGroup extends ConsumerStatefulWidget {
  const GlassButtonGroup({
    required this.children,
    this.spacing = 0,
    super.key,
  });

  /// 按钮列表（GlassGroupIconButton）
  final List<Widget> children;

  /// 按钮间距
  final double spacing;

  @override
  ConsumerState<GlassButtonGroup> createState() => _GlassButtonGroupState();
}

class _GlassButtonGroupState extends ConsumerState<GlassButtonGroup> {
  MethodChannel? _channel;

  @override
  void dispose() {
    // 清理 method channel，防止在 dispose 后收到回调导致崩溃
    _channel?.setMethodCallHandler(null);
    _channel = null;
    super.dispose();
  }

  /// 从 children 中提取按钮配置
  List<Map<String, dynamic>> _extractButtonConfigs() {
    final configs = <Map<String, dynamic>>[];
    for (final child in widget.children) {
      if (child is GlassGroupIconButton) {
        // 将 IconData 转换为 SF Symbol 名称
        final sfSymbol = _iconDataToSFSymbol(child.icon);
        configs.add({
          'icon': sfSymbol,
          'tooltip': child.tooltip,
          'isMenuButton': false,
          'menuItems': <Map<String, dynamic>>[],
        });
      } else if (child is GlassGroupPopupMenuButton) {
        // PopupMenu 按钮 - 提取菜单项传递给原生端
        final sfSymbol = _iconDataToSFSymbol(child.icon);
        final menuItems = _extractMenuItems(child);
        configs.add({
          'icon': sfSymbol,
          'tooltip': child.tooltip,
          'isMenuButton': true,
          'menuItems': menuItems,
        });
      } else if (child is GlassGroupDynamicButton) {
        // 动态图标按钮
        final sfSymbol = _iconDataToSFSymbol(child.icon);
        configs.add({
          'icon': sfSymbol,
          'tooltip': child.tooltip,
          'isMenuButton': false,
          'menuItems': <Map<String, dynamic>>[],
        });
      }
    }
    return configs;
  }

  /// 从 GlassGroupPopupMenuButton 提取菜单项
  List<Map<String, dynamic>> _extractMenuItems(GlassGroupPopupMenuButton<dynamic> button) {
    try {
      // 使用 dynamic 绕过泛型
      // ignore: avoid_dynamic_calls
      final dynamic dynamicButton = button;
      // ignore: avoid_dynamic_calls
      final itemBuilderCallback = dynamicButton.itemBuilder as List<PopupMenuEntry<dynamic>> Function(BuildContext);
      
      final items = itemBuilderCallback(context);
      final menuItems = <Map<String, dynamic>>[];
      
      for (final item in items) {
        if (item is PopupMenuItem) {
          // 提取 PopupMenuItem 的信息
          final menuItem = item;
          String title = '';
          String? iconName;
          bool isDestructive = false;
          
          // 尝试从 child 提取文本
          final child = menuItem.child;
          if (child is Text) {
            title = child.data ?? '';
          } else if (child is Row) {
            // 常见模式: Row(children: [Icon, SizedBox, Text])
            for (final rowChild in child.children) {
              if (rowChild is Text) {
                title = rowChild.data ?? '';
              } else if (rowChild is Icon) {
                iconName = _iconDataToSFSymbol(rowChild.icon ?? Icons.circle);
              }
            }
          }
          
          // 检查是否为红色/破坏性操作
          if (child is Text && child.style?.color == Colors.red) {
            isDestructive = true;
          }
          
          menuItems.add({
            'title': title,
            'icon': iconName,
            'value': menuItem.value?.toString() ?? '',
            'isDestructive': isDestructive,
          });
        }
      }
      
      return menuItems;
    } catch (e) {
      debugPrint('GlassButtonGroup._extractMenuItems: Error extracting menu items: $e');
      return [];
    }
  }

  /// 将 Flutter IconData 转换为 iOS SF Symbol 名称
  String _iconDataToSFSymbol(IconData icon) {
    // 常用图标映射
    final mapping = <int, String>{
      // 通用操作
      Icons.search_rounded.codePoint: 'magnifyingglass',
      Icons.tune_rounded.codePoint: 'slider.horizontal.3',
      Icons.more_vert_rounded.codePoint: 'ellipsis',
      Icons.settings_rounded.codePoint: 'gearshape',
      Icons.refresh_rounded.codePoint: 'arrow.clockwise',
      Icons.add_rounded.codePoint: 'plus',
      Icons.close_rounded.codePoint: 'xmark',
      Icons.check_rounded.codePoint: 'checkmark',
      Icons.arrow_back_rounded.codePoint: 'chevron.left',
      Icons.arrow_back_ios_new_rounded.codePoint: 'chevron.left',

      // 排序和筛选
      Icons.swap_vert_rounded.codePoint: 'arrow.up.arrow.down',
      Icons.sort_rounded.codePoint: 'arrow.up.arrow.down',
      Icons.filter_alt_rounded.codePoint: 'line.3.horizontal.decrease.circle',
      Icons.filter_list_rounded.codePoint: 'line.3.horizontal.decrease',

      // 列表和视图
      Icons.list_rounded.codePoint: 'list.bullet',
      Icons.queue_music_rounded.codePoint: 'list.bullet',
      Icons.check_circle_outline_rounded.codePoint: 'checkmark.circle',
      Icons.view_timeline_rounded.codePoint: 'list.bullet.rectangle',
      Icons.grid_view_rounded.codePoint: 'square.grid.2x2',
      Icons.view_module_rounded.codePoint: 'square.grid.2x2',

      // 下拉箭头
      Icons.arrow_drop_down_rounded.codePoint: 'chevron.down',
      Icons.arrow_drop_up_rounded.codePoint: 'chevron.up',
      Icons.expand_more_rounded.codePoint: 'chevron.down',
      Icons.expand_less_rounded.codePoint: 'chevron.up',

      // 阅读相关
      Icons.menu_book_rounded.codePoint: 'book.fill',
      Icons.collections_bookmark_rounded.codePoint: 'books.vertical.fill',
      Icons.note_alt_rounded.codePoint: 'note.text',
      Icons.bookmark_rounded.codePoint: 'bookmark.fill',
      Icons.bookmark_border_rounded.codePoint: 'bookmark',
      Icons.auto_stories_rounded.codePoint: 'book.pages',

      // 媒体相关
      Icons.photo_library_rounded.codePoint: 'photo.on.rectangle',
      Icons.video_library_rounded.codePoint: 'video.fill',
      Icons.music_note_rounded.codePoint: 'music.note',
      Icons.album_rounded.codePoint: 'opticaldisc.fill',
      Icons.live_tv_rounded.codePoint: 'play.tv',
      Icons.movie_rounded.codePoint: 'film',
      Icons.tv_rounded.codePoint: 'tv',

      // 云和存储
      Icons.cloud_rounded.codePoint: 'cloud.fill',
      Icons.cloud_outlined.codePoint: 'cloud',
      Icons.folder_rounded.codePoint: 'folder.fill',
      Icons.storage_rounded.codePoint: 'externaldrive.fill',
      Icons.phone_iphone_rounded.codePoint: 'iphone',

      // 复制和重复
      Icons.content_copy_rounded.codePoint: 'doc.on.doc',
      Icons.copy_rounded.codePoint: 'doc.on.doc',

      // 分享和导出
      Icons.share_rounded.codePoint: 'square.and.arrow.up',
      Icons.download_rounded.codePoint: 'arrow.down.circle',
      Icons.upload_rounded.codePoint: 'arrow.up.circle',
    };
    return mapping[icon.codePoint] ?? 'circle';
  }

  void _handleButtonTap(int index) {
    debugPrint('GlassButtonGroup._handleButtonTap: index=$index');
    // 找到对应的按钮并调用其 onPressed
    var buttonIndex = 0;
    for (final child in widget.children) {
      if (child is GlassGroupIconButton) {
        if (buttonIndex == index) {
          debugPrint('GlassButtonGroup._handleButtonTap: calling GlassGroupIconButton.onPressed');
          child.onPressed?.call();
          return;
        }
        buttonIndex++;
      } else if (child is GlassGroupPopupMenuButton) {
        if (buttonIndex == index) {
          // 对于 PopupMenu，需要手动显示菜单
          debugPrint('GlassButtonGroup._handleButtonTap: showing popup menu for index $index');
          _showPopupMenuForButtonUntyped(child);
          return;
        }
        buttonIndex++;
      } else if (child is GlassGroupDynamicButton) {
        if (buttonIndex == index) {
          debugPrint('GlassButtonGroup._handleButtonTap: calling GlassGroupDynamicButton.onPressed');
          child.onPressed?.call();
          return;
        }
        buttonIndex++;
      }
    }
    debugPrint('GlassButtonGroup._handleButtonTap: no matching button found for index $index');
  }

  /// 为 PopupMenuButton 显示菜单 - 使用 dynamic 类型处理，避免泛型推断问题
  Future<void> _showPopupMenuForButtonUntyped(GlassGroupPopupMenuButton<dynamic> button) async {
    debugPrint('GlassButtonGroup._showPopupMenuForButtonUntyped: called');
    
    try {
      // 使用 dynamic 完全绕过泛型类型检查
      // ignore: avoid_dynamic_calls
      final dynamic dynamicButton = button;
      debugPrint('GlassButtonGroup._showPopupMenuForButtonUntyped: button.onSelected=${dynamicButton.onSelected}');

      // ignore: avoid_dynamic_calls
      final onSelectedCallback = dynamicButton.onSelected as Function?;
      // ignore: avoid_dynamic_calls
      final itemBuilderCallback = dynamicButton.itemBuilder as List<PopupMenuEntry<dynamic>> Function(BuildContext);

      final isDark = Theme.of(context).brightness == Brightness.dark;
      final uiStyle = ref.read(uiStyleProvider);
      final renderBox = context.findRenderObject() as RenderBox?;
      if (renderBox == null) {
        debugPrint('GlassButtonGroup._showPopupMenuForButtonUntyped: renderBox is null');
        return;
      }

      final overlay = Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
      if (overlay == null) {
        debugPrint('GlassButtonGroup._showPopupMenuForButtonUntyped: overlay is null');
        return;
      }

      // 计算按钮组的位置
      final position = RelativeRect.fromRect(
        Rect.fromPoints(
          renderBox.localToGlobal(Offset.zero, ancestor: overlay),
          renderBox.localToGlobal(renderBox.size.bottomRight(Offset.zero), ancestor: overlay),
        ),
        Offset.zero & overlay.size,
      );
      debugPrint('GlassButtonGroup._showPopupMenuForButtonUntyped: position=$position');

      final items = itemBuilderCallback(context);
      debugPrint('GlassButtonGroup._showPopupMenuForButtonUntyped: ${items.length} items');

      final value = await showGlassPopupMenu<dynamic>(
        context: context,
        position: position,
        items: items,
        isDark: isDark,
        isGlassMode: uiStyle.isGlass,
      );

      debugPrint('GlassButtonGroup._showPopupMenuForButtonUntyped: returned value: $value (type: ${value.runtimeType})');
      debugPrint('GlassButtonGroup._showPopupMenuForButtonUntyped: onSelectedCallback=$onSelectedCallback');

      if (value != null && onSelectedCallback != null) {
        debugPrint('GlassButtonGroup._showPopupMenuForButtonUntyped: calling onSelected with value: $value');
        // ignore: avoid_dynamic_calls
        (onSelectedCallback as Function)(value);
      } else {
        debugPrint('GlassButtonGroup._showPopupMenuForButtonUntyped: NOT calling onSelected - value=$value, onSelectedCallback=$onSelectedCallback');
      }
    } catch (e, st) {
      debugPrint('GlassButtonGroup._showPopupMenuForButtonUntyped: EXCEPTION: $e');
      debugPrint('GlassButtonGroup._showPopupMenuForButtonUntyped: stackTrace: $st');
    }
  }

  void _setupChannel(int viewId) {
    _channel = MethodChannel('com.kkape.mynas/glass_button_group_$viewId');
    _channel?.setMethodCallHandler((call) async {
      // 检查是否已 dispose，防止崩溃
      if (!mounted) return;
      
      switch (call.method) {
        case 'onButtonTap':
          final index = call.arguments as int;
          _handleButtonTap(index);
          break;
        case 'onMenuItemSelected':
          // iOS 14+ 原生菜单选中回调
          final args = call.arguments as Map<Object?, Object?>;
          final buttonIndex = args['buttonIndex'] as int;
          final value = args['value'] as String?;
          debugPrint('GlassButtonGroup: onMenuItemSelected buttonIndex=$buttonIndex, value=$value');
          if (value != null) {
            _handleMenuItemSelected(buttonIndex, value);
          }
          break;
        case 'onMenuButtonTap':
          // iOS 13 回退: 需要 Flutter 显示菜单
          final index = call.arguments as int;
          _handleButtonTap(index);
          break;
      }
    });
  }

  /// 处理原生菜单选中
  void _handleMenuItemSelected(int buttonIndex, String value) {
    var currentIndex = 0;
    for (final child in widget.children) {
      if (currentIndex == buttonIndex) {
        if (child is GlassGroupPopupMenuButton) {
          try {
            // ignore: avoid_dynamic_calls
            final dynamic dynamicButton = child;
            // ignore: avoid_dynamic_calls
            final onSelectedCallback = dynamicButton.onSelected as Function?;
            if (onSelectedCallback != null) {
              debugPrint('GlassButtonGroup: calling onSelected with value: $value');
              // 尝试解析 value 为原始类型
              dynamic parsedValue = value;
              // 尝试解析为整数
              final intValue = int.tryParse(value);
              if (intValue != null) {
                parsedValue = intValue;
              }
              // ignore: avoid_dynamic_calls
              (onSelectedCallback as Function)(parsedValue);
            }
          } catch (e) {
            debugPrint('GlassButtonGroup._handleMenuItemSelected: Error: $e');
          }
        }
        return;
      }
      if (child is GlassGroupIconButton || 
          child is GlassGroupPopupMenuButton || 
          child is GlassGroupDynamicButton) {
        currentIndex++;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uiStyle = ref.watch(uiStyleProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 经典模式 - 直接排列普通按钮
    if (!uiStyle.isGlass) {
      return _buildClassicButtonGroup(isDark);
    }

    // 玻璃模式
    // Apple 平台: 使用原生玻璃效果
    if (!kIsWeb && (Platform.isIOS || Platform.isMacOS)) {
      return _buildNativeGlassButtonGroup(isDark);
    }

    // 其他平台: 使用 Flutter BackdropFilter
    return _buildFlutterGlassButtonGroup(isDark);
  }

  Widget _buildClassicButtonGroup(bool isDark) {
    // 经典模式使用标准大小的图标
    const classicIconSize = 22.0;

    debugPrint('GlassButtonGroup._buildClassicButtonGroup: ${widget.children.length} children');
    for (var i = 0; i < widget.children.length; i++) {
      final child = widget.children[i];
      debugPrint('GlassButtonGroup._buildClassicButtonGroup: child[$i] = ${child.runtimeType}');
      debugPrint('GlassButtonGroup._buildClassicButtonGroup: child[$i] is GlassGroupPopupMenuButton = ${child is GlassGroupPopupMenuButton}');
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: widget.children.map((child) {
        if (child is GlassGroupIconButton) {
          return IconButton(
            onPressed: child.onPressed,
            icon: Icon(
              child.icon,
              size: classicIconSize,
              color: child.color ?? (isDark ? Colors.white : Colors.black87),
            ),
            tooltip: child.tooltip,
          );
        } else if (child is GlassGroupDynamicButton) {
          return IconButton(
            onPressed: child.onPressed,
            icon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  child.icon,
                  size: classicIconSize,
                  color: child.color ?? (isDark ? Colors.white : Colors.black87),
                ),
                if (child.showDropdownIndicator)
                  Icon(
                    Icons.arrow_drop_down_rounded,
                    size: 16,
                    color: (child.color ?? (isDark ? Colors.white : Colors.black87))
                        .withValues(alpha: 0.7),
                  ),
              ],
            ),
            tooltip: child.tooltip,
          );
        } else if (child is GlassGroupPopupMenuButton) {
          // 经典模式的弹出菜单按钮
          final button = child;
          debugPrint('GlassButtonGroup._buildClassicButtonGroup: creating IconButton for PopupMenuButton');
          
          // 创建 GlobalKey 来追踪按钮位置
          final buttonKey = GlobalKey();
          
          return IconButton(
            key: buttonKey,
            onPressed: () {
              debugPrint('GlassButtonGroup: classic PopupMenuButton tapped!');
              _showClassicPopupMenuWithKey(button, isDark, buttonKey);
            },
            icon: Icon(
              child.icon,
              size: classicIconSize,
              color: child.color ?? (isDark ? Colors.white : Colors.black87),
            ),
            tooltip: child.tooltip,
          );
        }
        return child;
      }).toList(),
    );
  }

  /// 经典模式下显示标准弹出菜单 - 使用 GlobalKey 定位按钮
  Future<void> _showClassicPopupMenuWithKey(
    // ignore: strict_raw_type
    GlassGroupPopupMenuButton button,
    bool isDark,
    GlobalKey buttonKey,
  ) async {
    debugPrint('GlassButtonGroup._showClassicPopupMenuWithKey: called');

    try {
      // 使用 dynamic 完全绕过泛型类型检查
      // ignore: avoid_dynamic_calls
      final dynamic dynamicButton = button;
      // ignore: avoid_dynamic_calls
      final onSelectedCallback = dynamicButton.onSelected as Function?;
      // ignore: avoid_dynamic_calls
      final itemBuilderCallback = dynamicButton.itemBuilder as List<PopupMenuEntry<dynamic>> Function(BuildContext);

      // 使用 GlobalKey 获取 RenderBox
      final renderBox = buttonKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null) {
        debugPrint('GlassButtonGroup._showClassicPopupMenuWithKey: renderBox is null');
        return;
      }

      final navigatorState = Navigator.of(context);
      final overlay = navigatorState.overlay?.context.findRenderObject() as RenderBox?;
      if (overlay == null) {
        debugPrint('GlassButtonGroup._showClassicPopupMenuWithKey: overlay is null');
        return;
      }

      // 计算按钮的实际位置
      final buttonPosition = renderBox.localToGlobal(Offset.zero, ancestor: overlay);
      final buttonSize = renderBox.size;

      debugPrint('GlassButtonGroup._showClassicPopupMenuWithKey: buttonPosition=$buttonPosition, buttonSize=$buttonSize');

      // 菜单显示在按钮下方
      final position = RelativeRect.fromLTRB(
        buttonPosition.dx + buttonSize.width - 200, // 菜单宽度约 200，右对齐
        buttonPosition.dy + buttonSize.height + 4,   // 按钮下方 4px
        overlay.size.width - (buttonPosition.dx + buttonSize.width),
        0,
      );

      final items = itemBuilderCallback(context);
      debugPrint('GlassButtonGroup._showClassicPopupMenuWithKey: ${items.length} items');

      // 使用标准 Flutter showMenu
      final value = await showMenu<dynamic>(
        context: context,
        position: position,
        items: items,
      );

      debugPrint('GlassButtonGroup._showClassicPopupMenuWithKey: returned value: $value');
      if (value != null && onSelectedCallback != null) {
        debugPrint('GlassButtonGroup._showClassicPopupMenuWithKey: calling onSelected');
        // ignore: avoid_dynamic_calls
        (onSelectedCallback as Function)(value);
      }
    } catch (e, st) {
      debugPrint('GlassButtonGroup._showClassicPopupMenuWithKey: EXCEPTION: $e');
      debugPrint('GlassButtonGroup._showClassicPopupMenuWithKey: stackTrace: $st');
    }
  }

  Widget _buildNativeGlassButtonGroup(bool isDark) {
    final buttonConfigs = _extractButtonConfigs();
    final buttonCount = buttonConfigs.length;

    // iOS 26 风格：更宽松的按钮布局
    // 每个按钮 40px + 分隔线 0.5px + 左右内边距 20px
    final width = buttonCount * 40.0 + (buttonCount - 1) * 0.5 + 20;
    const height = 44.0;

    final creationParams = <String, dynamic>{
      'isDark': isDark,
      'items': buttonConfigs,
      'buttonSize': 40.0,
      'spacing': widget.spacing,
      'cornerRadius': 22.0,
    };

    final viewType = 'com.kkape.mynas/glass_button_group';

    if (Platform.isIOS) {
      return SizedBox(
        width: width,
        height: height,
        child: UiKitView(
          viewType: viewType,
          creationParams: creationParams,
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _setupChannel,
          hitTestBehavior: PlatformViewHitTestBehavior.opaque,
        ),
      );
    }

    if (Platform.isMacOS) {
      return SizedBox(
        width: width,
        height: height,
        child: AppKitView(
          viewType: viewType,
          creationParams: creationParams,
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _setupChannel,
          hitTestBehavior: PlatformViewHitTestBehavior.opaque,
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildFlutterGlassButtonGroup(bool isDark) {
    final glassStyle = GlassTheme.getStyle(ref.watch(uiStyleProvider), isDark: isDark);
    final bgColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.06);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: glassStyle.borderOpacity * 0.8)
        : Colors.black.withValues(alpha: glassStyle.borderOpacity * 0.4);

    // iOS 26 标准：使用间距而不是竖线分隔
    final wrappedChildren = <Widget>[];
    for (var i = 0; i < widget.children.length; i++) {
      wrappedChildren.add(widget.children[i]);
      // 按钮之间添加 4px 间距（iOS 26 标准）
      if (i < widget.children.length - 1) {
        wrappedChildren.add(const SizedBox(width: 4));
      }
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: borderColor, width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: wrappedChildren,
          ),
        ),
      ),
    );
  }
}

/// 简化版玻璃图标按钮 - 无背景，仅在玻璃模式下提供提示
///
/// 用于 GlassButtonGroup 内部，不带独立的玻璃背景
class GlassGroupIconButton extends StatelessWidget {
  const GlassGroupIconButton({
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = 18,
    this.color,
    this.badge = false,
    super.key,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final Color? color;
  /// 是否显示角标（用于指示有筛选等状态）
  final bool badge;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDisabled = onPressed == null;
    // 禁用时使用较淡的颜色
    final iconColor = isDisabled
        ? (isDark ? Colors.white38 : Colors.black26)
        : (color ?? (isDark ? Colors.white : Colors.black87));

    Widget button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(icon, size: size, color: iconColor),
              // 角标指示器
              if (badge)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }

    return button;
  }
}

/// 动态图标按钮 - 支持根据状态改变图标
///
/// 用于需要动态切换图标的场景，如阅读页面的内容类型切换
/// 在 iOS 原生模式下会显示主图标
class GlassGroupDynamicButton extends StatelessWidget {
  const GlassGroupDynamicButton({
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = 20,
    this.color,
    this.showDropdownIndicator = false,
    super.key,
  });

  /// 当前显示的图标
  final IconData icon;

  /// 点击回调
  final VoidCallback? onPressed;

  /// 提示文本
  final String? tooltip;

  /// 图标大小
  final double size;

  /// 图标颜色
  final Color? color;

  /// 是否显示下拉指示器
  final bool showDropdownIndicator;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = color ?? (isDark ? Colors.white : Colors.black87);

    Widget button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: showDropdownIndicator ? 52 : 40,
          height: 40,
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: size, color: iconColor),
              if (showDropdownIndicator) ...[
                const SizedBox(width: 2),
                Icon(
                  Icons.arrow_drop_down_rounded,
                  size: 16,
                  color: iconColor.withValues(alpha: 0.7),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }

    return button;
  }
}

/// 玻璃风格 PopupMenu 按钮
///
/// 与 GlassGroupIconButton 样式一致，但点击后显示紧跟按钮的弹出菜单
/// iOS 26 风格：点击后按钮消失，菜单在按钮位置展示
/// 经典模式：使用标准 Flutter 弹出菜单
class GlassGroupPopupMenuButton<T> extends ConsumerStatefulWidget {
  const GlassGroupPopupMenuButton({
    required this.itemBuilder,
    this.icon = Icons.more_vert_rounded,
    this.onSelected,
    this.tooltip,
    this.size = 18,
    this.color,
    this.offset = const Offset(0, 8),
    super.key,
  });

  /// 菜单图标
  final IconData icon;

  /// 菜单项构建器
  final List<PopupMenuEntry<T>> Function(BuildContext context) itemBuilder;

  /// 选中回调
  final void Function(T value)? onSelected;

  /// 提示文本
  final String? tooltip;

  /// 图标大小
  final double size;

  /// 图标颜色
  final Color? color;

  /// 菜单偏移量
  final Offset offset;

  @override
  ConsumerState<GlassGroupPopupMenuButton<T>> createState() =>
      _GlassGroupPopupMenuButtonState<T>();
}

class _GlassGroupPopupMenuButtonState<T>
    extends ConsumerState<GlassGroupPopupMenuButton<T>> {
  bool _isMenuOpen = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor =
        widget.color ?? (isDark ? Colors.white : Colors.black87);

    // 玻璃模式：菜单打开时隐藏按钮（_isMenuOpen 只在玻璃模式下为 true）
    return Opacity(
      opacity: _isMenuOpen ? 0.0 : 1.0,
      child: GestureDetector(
        onTap: () => _showGlassMenu(context),
        child: Tooltip(
          message: widget.tooltip ?? '',
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            child: Icon(widget.icon, size: widget.size, color: iconColor),
          ),
        ),
      ),
    );
  }

  Future<void> _showGlassMenu(BuildContext context) async {
    if (_isMenuOpen) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final uiStyle = ref.read(uiStyleProvider);

    // 经典模式：直接显示标准菜单，按钮不消失
    if (!uiStyle.isGlass) {
      _showClassicMenu(context, isDark);
      return;
    }

    // 玻璃模式：先隐藏按钮，等待一帧后再显示菜单
    setState(() => _isMenuOpen = true);

    // 等待一帧确保按钮已隐藏
    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (!mounted) return;

    final button = context.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;

    // 计算按钮位置（按钮已隐藏，但位置信息还在）
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero),
            ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    // 构建菜单项
    final items = widget.itemBuilder(context);
    debugPrint('GlassGroupPopupMenuButton: _showGlassMenu called with ${items.length} items');

    try {
      final value = await showGlassPopupMenu<T>(
        context: context,
        position: position,
        items: items,
        isDark: isDark,
        isGlassMode: true,
      );

      debugPrint('GlassGroupPopupMenuButton: showGlassPopupMenu returned value: $value');
      if (value != null && widget.onSelected != null) {
        debugPrint('GlassGroupPopupMenuButton: calling onSelected with value: $value');
        widget.onSelected!(value);
      }
    } finally {
      // 确保菜单关闭后恢复按钮显示
      if (mounted) {
        setState(() => _isMenuOpen = false);
      }
    }
  }

  /// 经典模式下显示标准菜单
  void _showClassicMenu(BuildContext context, bool isDark) {
    final button = context.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;

    // 计算按钮在 overlay 中的位置
    final buttonPosition = button.localToGlobal(Offset.zero, ancestor: overlay);
    final buttonSize = button.size;

    // 菜单显示在按钮下方，右对齐
    // 使用 fromLTRB: left, top, right, bottom
    // right 和 bottom 是相对于屏幕右下角的距离
    final position = RelativeRect.fromLTRB(
      buttonPosition.dx + buttonSize.width - 200, // 假设菜单宽度约 200，尝试右对齐
      buttonPosition.dy + buttonSize.height,      // 按钮正下方
      overlay.size.width - (buttonPosition.dx + buttonSize.width),
      overlay.size.height - (buttonPosition.dy + buttonSize.height + 300), // 给足够的高度空间
    );

    final items = widget.itemBuilder(context);
    debugPrint('GlassGroupPopupMenuButton: _showClassicMenu called with ${items.length} items');

    showMenu<T>(
      context: context,
      position: position,
      items: items,
    ).then((value) {
      debugPrint('GlassGroupPopupMenuButton: showMenu returned value: $value');
      if (value != null && widget.onSelected != null) {
        debugPrint('GlassGroupPopupMenuButton: calling onSelected with value: $value');
        widget.onSelected!(value);
      }
    });
  }
}

/// 显示玻璃风格弹出菜单
///
/// 根据 [isGlassMode] 参数决定显示样式：
/// - 玻璃模式:
///   - iOS 26+: 使用原生 UIAlertController (Liquid Glass 自动效果)
///   - 其他平台: 使用 Flutter BackdropFilter 实现毛玻璃效果
/// - 经典模式: 使用 Flutter 标准 PopupMenuButton 样式
Future<T?> showGlassPopupMenu<T>({
  required BuildContext context,
  required RelativeRect position,
  required List<PopupMenuEntry<T>> items,
  bool isDark = false,
  double elevation = 8,
  double blurSigma = 20,
  bool isGlassMode = true,
}) async {
  debugPrint('showGlassPopupMenu: isGlassMode=$isGlassMode, items=${items.length}');

  // 经典模式：使用 Flutter 标准弹出菜单
  if (!isGlassMode) {
    debugPrint('showGlassPopupMenu: using Flutter showMenu');
    final result = await showMenu<T>(
      context: context,
      position: position,
      items: items,
      elevation: elevation,
    );
    debugPrint('showGlassPopupMenu: Flutter showMenu returned: $result');
    return result;
  }

  // 玻璃模式
  // iOS 平台使用原生弹出菜单
  if (!kIsWeb && (Platform.isIOS || Platform.isMacOS)) {
    debugPrint('showGlassPopupMenu: using native Apple popup menu');
    final result = await _showNativeApplePopupMenu<T>(
      context: context,
      position: position,
      items: items,
      isDark: isDark,
    );
    debugPrint('showGlassPopupMenu: native Apple returned: $result');
    return result;
  }

  // 其他平台使用 Flutter 玻璃效果实现
  debugPrint('showGlassPopupMenu: using Flutter glass popup route');
  final result = await Navigator.of(context).push<T>(
    _GlassPopupMenuRoute<T>(
      position: position,
      items: items,
      isDark: isDark,
      elevation: elevation,
      blurSigma: blurSigma,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    ),
  );
  debugPrint('showGlassPopupMenu: Flutter glass route returned: $result');
  return result;
}

/// iOS 原生弹出菜单实现
Future<T?> _showNativeApplePopupMenu<T>({
  required BuildContext context,
  required RelativeRect position,
  required List<PopupMenuEntry<T>> items,
  required bool isDark,
}) async {
  const channel = MethodChannel('com.kkape.mynas/glass_popup_menu');

  // 提取菜单项信息
  final menuItems = <Map<String, dynamic>>[];
  final valueMap = <String, T>{};

  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    if (item is PopupMenuItem<T>) {
      final valueKey = 'item_$i';
      if (item.value != null) {
        valueMap[valueKey] = item.value as T;
      }

      // 尝试从 child 提取文本和图标
      String title = '';
      String? icon;

      if (item.child is Text) {
        title = (item.child as Text).data ?? '';
      } else if (item.child is Row) {
        final row = item.child as Row;
        for (final child in row.children) {
          if (child is Text) {
            title = child.data ?? '';
          } else if (child is Icon) {
            icon = _iconDataToSFSymbol(child.icon);
          }
        }
      } else if (item.child is ListTile) {
        // 处理 ListTile 类型的菜单项
        final listTile = item.child as ListTile;
        if (listTile.title is Text) {
          title = (listTile.title as Text).data ?? '';
        }
        if (listTile.leading is Icon) {
          icon = _iconDataToSFSymbol((listTile.leading as Icon).icon);
        }
      } else {
        // 其他类型，尝试获取 Widget 的描述性文本
        title = _extractTextFromWidget(item.child);
      }

      menuItems.add({
        'title': title,
        'icon': icon,
        'value': valueKey,
        'isDestructive': false,
      });
    }
  }

  // 计算屏幕坐标
  final size = MediaQuery.of(context).size;
  final x = size.width - position.right;
  final y = size.height - position.bottom;

  try {
    final result = await channel.invokeMethod<String>('showMenu', {
      'x': x,
      'y': y,
      'isDark': isDark,
      'items': menuItems,
      'screenWidth': size.width,
      'screenHeight': size.height,
    });

    if (result != null && valueMap.containsKey(result)) {
      return valueMap[result];
    } else if (result != null) {
      debugPrint('Warning: Native popup returned result "$result" which was not found in valueMap keys: ${valueMap.keys}');
    }
  } catch (e) {
    // 如果原生调用失败，回退到 Flutter 实现
    debugPrint('Native popup menu failed: $e, falling back to Flutter implementation');
    return Navigator.of(context).push<T>(
      _GlassPopupMenuRoute<T>(
        position: position,
        items: items,
        isDark: isDark,
        elevation: 8,
        blurSigma: 20,
        barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      ),
    );
  }

  return null;
}

/// 从 Widget 中提取文本（递归查找）
String _extractTextFromWidget(Widget? widget) {
  if (widget == null) return '';
  if (widget is Text) return widget.data ?? '';
  if (widget is ListTile) {
    if (widget.title is Text) {
      return (widget.title as Text).data ?? '';
    }
  }
  if (widget is Row || widget is Column || widget is Flex) {
    final flex = widget as Flex;
    for (final child in flex.children) {
      final text = _extractTextFromWidget(child);
      if (text.isNotEmpty) return text;
    }
  }
  return '';
}

/// 将 Flutter IconData 转换为 iOS SF Symbol 名称
String? _iconDataToSFSymbol(IconData? icon) {
  if (icon == null) return null;

  final mapping = <int, String>{
    Icons.add_rounded.codePoint: 'plus',
    Icons.delete_rounded.codePoint: 'trash',
    Icons.edit_rounded.codePoint: 'pencil',
    Icons.share_rounded.codePoint: 'square.and.arrow.up',
    Icons.copy_rounded.codePoint: 'doc.on.doc',
    Icons.content_copy_rounded.codePoint: 'doc.on.doc',
    Icons.favorite_rounded.codePoint: 'heart.fill',
    Icons.favorite_border_rounded.codePoint: 'heart',
    Icons.queue_music_rounded.codePoint: 'list.bullet',
    Icons.playlist_add_rounded.codePoint: 'plus.rectangle.on.rectangle',
    Icons.info_rounded.codePoint: 'info.circle',
    Icons.settings_rounded.codePoint: 'gearshape',
    Icons.refresh_rounded.codePoint: 'arrow.clockwise',
    Icons.download_rounded.codePoint: 'arrow.down.circle',
    Icons.upload_rounded.codePoint: 'arrow.up.circle',
    Icons.folder_rounded.codePoint: 'folder',
    Icons.person_rounded.codePoint: 'person',
    Icons.album_rounded.codePoint: 'opticaldisc',
    Icons.cloud_rounded.codePoint: 'cloud',
    Icons.photo_library_rounded.codePoint: 'photo.on.rectangle',
  };

  return mapping[icon.codePoint];
}

/// 玻璃风格弹出菜单路由
class _GlassPopupMenuRoute<T> extends PopupRoute<T> {
  _GlassPopupMenuRoute({
    required this.position,
    required this.items,
    required this.isDark,
    required this.elevation,
    required this.blurSigma,
    required this.barrierLabel,
  });

  final RelativeRect position;
  final List<PopupMenuEntry<T>> items;
  final bool isDark;
  final double elevation;
  final double blurSigma;

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => Colors.transparent;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 200);

  @override
  Animation<double> createAnimation() {
    return CurvedAnimation(
      parent: super.createAnimation(),
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      removeBottom: true,
      removeLeft: true,
      removeRight: true,
      child: Builder(
        builder: (context) {
          return CustomSingleChildLayout(
            delegate: _GlassPopupMenuRouteLayout(
              position,
              Directionality.of(context),
            ),
            child: _GlassPopupMenu<T>(
              route: this,
              animation: animation,
            ),
          );
        },
      ),
    );
  }
}

/// 玻璃风格弹出菜单布局
class _GlassPopupMenuRouteLayout extends SingleChildLayoutDelegate {
  _GlassPopupMenuRouteLayout(this.position, this.textDirection);

  final RelativeRect position;
  final TextDirection textDirection;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints.loose(
      constraints.biggest - const Offset(16, 16) as Size,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    // 默认在按钮下方右对齐
    double x = size.width - position.right - childSize.width;
    double y = size.height - position.bottom + 8;

    // 确保不超出屏幕边界
    if (x < 8) x = 8;
    if (x + childSize.width > size.width - 8) {
      x = size.width - childSize.width - 8;
    }
    if (y + childSize.height > size.height - 8) {
      // 如果下方空间不够，显示在按钮上方
      y = position.top - childSize.height - 8;
    }
    if (y < 8) y = 8;

    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_GlassPopupMenuRouteLayout oldDelegate) {
    return position != oldDelegate.position ||
        textDirection != oldDelegate.textDirection;
  }
}

/// 玻璃风格弹出菜单组件
class _GlassPopupMenu<T> extends StatelessWidget {
  const _GlassPopupMenu({
    required this.route,
    required this.animation,
  });

  final _GlassPopupMenuRoute<T> route;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final isDark = route.isDark;

    // 背景颜色 - 半透明
    final backgroundColor = isDark
        ? Colors.black.withValues(alpha: 0.6)
        : Colors.white.withValues(alpha: 0.7);

    // 边框颜色
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.15)
        : Colors.black.withValues(alpha: 0.08);

    return FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.9, end: 1.0).animate(animation),
        alignment: Alignment.topRight,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: route.blurSigma,
              sigmaY: route.blurSigma,
            ),
            child: Container(
              constraints: const BoxConstraints(
                minWidth: 180,
                maxWidth: 280,
              ),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderColor, width: 0.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: IntrinsicWidth(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _buildMenuItems(context),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildMenuItems(BuildContext context) {
    final List<Widget> children = [];

    for (int i = 0; i < route.items.length; i++) {
      final item = route.items[i];

      if (item is PopupMenuDivider) {
        children.add(
          Divider(
            height: 1,
            thickness: 0.5,
            color: route.isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.black.withValues(alpha: 0.08),
          ),
        );
      } else if (item is PopupMenuItem<T>) {
        children.add(
          _GlassMenuItem<T>(
            value: item.value,
            isDark: route.isDark,
            onTap: () {
              debugPrint('_GlassMenuItem: onTap called, value: ${item.value}');
              Navigator.of(context).pop(item.value);
            },
            child: item.child ?? const SizedBox.shrink(),
          ),
        );
      }
    }

    return children;
  }
}

/// 玻璃风格菜单项
class _GlassMenuItem<T> extends StatefulWidget {
  const _GlassMenuItem({
    required this.child,
    required this.isDark,
    required this.onTap,
    this.value,
  });

  final Widget child;
  final bool isDark;
  final VoidCallback onTap;
  final T? value;

  @override
  State<_GlassMenuItem<T>> createState() => _GlassMenuItemState<T>();
}

class _GlassMenuItemState<T> extends State<_GlassMenuItem<T>> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final hoverColor = widget.isDark
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.05);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: () {
          debugPrint('_GlassMenuItemState: GestureDetector onTap triggered, value: ${widget.value}');
          widget.onTap();
        },
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: _isHovered ? hoverColor : Colors.transparent,
          ),
          child: DefaultTextStyle(
            style: TextStyle(
              color: widget.isDark ? Colors.white : Colors.black87,
              fontSize: 15,
              fontWeight: FontWeight.w400,
            ),
            child: IconTheme(
              data: IconThemeData(
                color: widget.isDark ? Colors.white70 : Colors.black54,
                size: 18,
              ),
              // IgnorePointer 防止 ListTile 等拦截点击事件
              child: IgnorePointer(child: widget.child),
            ),
          ),
        ),
      ),
    );
  }
}

/// iOS 26 Liquid Glass 页面布局
///
/// 实现 iOS 26 风格的悬浮导航：
/// - 大标题在内容区域内，随内容滚动
/// - 工具栏按钮悬浮于内容之上
/// - 无固定顶栏背景区域
///
/// 使用示例：
/// ```dart
/// LiquidGlassPageLayout(
///   floatingButtons: GlassButtonGroup(children: [...]),
///   largeTitle: '问候语',
///   subtitle: '副标题',
///   body: CustomScrollView(slivers: [...]),
/// )
/// ```
class LiquidGlassPageLayout extends ConsumerWidget {
  const LiquidGlassPageLayout({
    required this.body,
    this.floatingButtons,
    this.floatingButtonsLeft,
    this.largeTitle,
    this.subtitle,
    this.subtitleWidget,
    this.backgroundColor,
    this.largeTitlePadding = const EdgeInsets.fromLTRB(20, 8, 20, 16),
    super.key,
  });

  /// 页面主体内容（通常是 CustomScrollView）
  final Widget body;

  /// 悬浮按钮组（右上角）
  final Widget? floatingButtons;

  /// 左侧悬浮按钮（如返回按钮）
  final Widget? floatingButtonsLeft;

  /// 大标题文本
  final String? largeTitle;

  /// 副标题文本
  final String? subtitle;

  /// 副标题组件（优先于 subtitle）
  final Widget? subtitleWidget;

  /// 背景颜色
  final Color? backgroundColor;

  /// 大标题内边距
  final EdgeInsets largeTitlePadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiStyle = ref.watch(uiStyleProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final safeTop = MediaQuery.of(context).padding.top;

    // 经典模式使用传统布局
    if (!uiStyle.isGlass) {
      return _buildClassicLayout(context, isDark, safeTop);
    }

    // iOS 26 Liquid Glass 布局
    return _buildLiquidGlassLayout(context, isDark, safeTop);
  }

  Widget _buildClassicLayout(BuildContext context, bool isDark, double safeTop) {
    return Stack(
      children: [
        // 主内容
        body,
        // 悬浮按钮（右上角）
        if (floatingButtons != null)
          Positioned(
            top: safeTop + 8,
            right: 16,
            child: floatingButtons!,
          ),
        // 左侧按钮
        if (floatingButtonsLeft != null)
          Positioned(
            top: safeTop + 8,
            left: 16,
            child: floatingButtonsLeft!,
          ),
      ],
    );
  }

  Widget _buildLiquidGlassLayout(BuildContext context, bool isDark, double safeTop) {
    return Stack(
      children: [
        // 主内容（无固定顶栏，大标题在内容区域内）
        body,
        // 悬浮按钮组（右上角）- 真正悬浮于内容之上
        if (floatingButtons != null)
          Positioned(
            top: safeTop + 8,
            right: 16,
            child: floatingButtons!,
          ),
        // 左侧按钮
        if (floatingButtonsLeft != null)
          Positioned(
            top: safeTop + 8,
            left: 16,
            child: floatingButtonsLeft!,
          ),
      ],
    );
  }

  /// 构建大标题区域（用于放在 Sliver 中）
  static Widget buildLargeTitleSliver({
    required String title,
    String? subtitle,
    Widget? subtitleWidget,
    required bool isDark,
    EdgeInsets padding = const EdgeInsets.fromLTRB(20, 8, 20, 16),
    double topPadding = 0,
  }) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: padding.copyWith(top: padding.top + topPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
                letterSpacing: -0.5,
              ),
            ),
            if (subtitleWidget != null) ...[
              const SizedBox(height: 6),
              subtitleWidget,
            ] else if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 15,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.6)
                      : Colors.black.withValues(alpha: 0.5),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// iOS 26 风格玻璃搜索栏
///
/// 特性：
/// - 胶囊形状（pill-shaped）全圆角
/// - iOS 26+: 使用原生 UIGlassEffect
/// - iOS < 26 / 其他平台: 使用 Flutter BackdropFilter
/// - 搜索图标在左侧
/// - 可选的取消按钮
/// - 支持自动获取焦点
/// - 支持输入变化回调
class GlassSearchBar extends StatefulWidget {
  const GlassSearchBar({
    this.controller,
    this.hintText = '搜索',
    this.onChanged,
    this.onSubmitted,
    this.onCancel,
    this.autofocus = false,
    this.showCancelButton = true,
    this.width,
    this.height = 44,
    this.enabled = true,
    super.key,
  });

  /// 文本控制器
  final TextEditingController? controller;

  /// 提示文本
  final String hintText;

  /// 输入变化回调
  final ValueChanged<String>? onChanged;

  /// 提交回调
  final ValueChanged<String>? onSubmitted;

  /// 取消回调
  final VoidCallback? onCancel;

  /// 是否自动获取焦点
  final bool autofocus;

  /// 是否显示取消按钮
  final bool showCancelButton;

  /// 宽度（null 表示自动扩展）
  final double? width;

  /// 高度
  final double height;

  /// 是否启用
  final bool enabled;

  @override
  State<GlassSearchBar> createState() => _GlassSearchBarState();
}

class _GlassSearchBarState extends State<GlassSearchBar>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late final AnimationController _animationController;
  late final Animation<double> _scaleAnimation;
  bool _isFocused = false;
  bool _hasText = false;

  // iOS 原生视图相关
  MethodChannel? _nativeChannel;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
    _controller.addListener(_onTextChange);
    _hasText = _controller.text.isNotEmpty;

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.98).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.removeListener(_onTextChange);
    if (widget.controller == null) {
      _controller.dispose();
    }
    _animationController.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    setState(() {
      _isFocused = _focusNode.hasFocus;
    });
    if (_focusNode.hasFocus) {
      _animationController.forward();
    } else {
      _animationController.reverse();
    }
  }

  void _onTextChange() {
    final hasText = _controller.text.isNotEmpty;
    if (hasText != _hasText) {
      setState(() {
        _hasText = hasText;
      });
    }
    // 同步到原生视图
    _nativeChannel?.invokeMethod('setText', _controller.text);
  }

  void _handleCancel() {
    _controller.clear();
    _focusNode.unfocus();
    _nativeChannel?.invokeMethod('clear');
    widget.onCancel?.call();
  }

  void _handleClear() {
    _controller.clear();
    _nativeChannel?.invokeMethod('clear');
    widget.onChanged?.call('');
  }

  void _onNativePlatformViewCreated(int viewId) {
    _nativeChannel = MethodChannel('com.kkape.mynas/glass_search_bar_$viewId');
    _nativeChannel!.setMethodCallHandler(_handleNativeMethodCall);
  }

  Future<dynamic> _handleNativeMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onChanged':
        final text = call.arguments as String? ?? '';
        // 同步到 Flutter 控制器（避免循环）
        if (_controller.text != text) {
          _controller.text = text;
          _controller.selection = TextSelection.fromPosition(
            TextPosition(offset: text.length),
          );
        }
        setState(() {
          _hasText = text.isNotEmpty;
        });
        widget.onChanged?.call(text);
      case 'onSubmitted':
        final text = call.arguments as String? ?? '';
        widget.onSubmitted?.call(text);
      case 'onFocusChanged':
        final focused = call.arguments as bool? ?? false;
        setState(() {
          _isFocused = focused;
        });
        if (focused) {
          _animationController.forward();
        } else {
          _animationController.reverse();
        }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // iOS 平台使用原生 Platform View
    if (Platform.isIOS) {
      return _buildWithNativeView(context, isDark);
    }

    // 其他平台使用 Flutter 实现
    return _buildFlutterImplementation(context, isDark);
  }

  /// iOS 原生 Platform View 实现
  Widget _buildWithNativeView(BuildContext context, bool isDark) {
    final creationParams = <String, dynamic>{
      'isDark': isDark,
      'placeholder': widget.hintText,
      'text': _controller.text,
      'autofocus': widget.autofocus,
      'height': widget.height,
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 原生搜索框
        SizedBox(
          width: widget.width,
          height: widget.height,
          child: UiKitView(
            viewType: 'com.kkape.mynas/glass_search_bar',
            creationParams: creationParams,
            creationParamsCodec: const StandardMessageCodec(),
            onPlatformViewCreated: _onNativePlatformViewCreated,
          ),
        ),
        // 取消按钮
        if (widget.showCancelButton && (_isFocused || _hasText)) ...[
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _handleCancel,
            child: Text(
              '取消',
              style: TextStyle(
                fontSize: 16,
                color: AppColors.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Flutter 实现（用于非 iOS 平台）
  Widget _buildFlutterImplementation(BuildContext context, bool isDark) {
    // 玻璃效果颜色
    final glassColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.04);

    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.18)
        : Colors.black.withValues(alpha: 0.08);

    final focusedBorderColor = isDark
        ? Colors.white.withValues(alpha: 0.28)
        : Colors.black.withValues(alpha: 0.14);

    final iconColor = isDark ? Colors.white60 : Colors.black45;
    final textColor = isDark ? Colors.white : Colors.black87;
    final hintColor = isDark ? Colors.white38 : Colors.black38;

    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) => Transform.scale(
        scale: _scaleAnimation.value,
        child: child,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 搜索输入框
          ClipRRect(
            borderRadius: BorderRadius.circular(widget.height / 2),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: widget.width,
                height: widget.height,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: glassColor,
                  borderRadius: BorderRadius.circular(widget.height / 2),
                  border: Border.all(
                    color: _isFocused ? focusedBorderColor : borderColor,
                    width: _isFocused ? 1.0 : 0.5,
                  ),
                  // 添加微妙的内阴影效果
                  boxShadow: [
                    if (_isFocused)
                      BoxShadow(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.black.withValues(alpha: 0.03),
                        blurRadius: 8,
                        spreadRadius: -2,
                      ),
                  ],
                ),
                child: Row(
                  children: [
                    // 搜索图标
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      child: Icon(
                        Icons.search_rounded,
                        size: 20,
                        color: _isFocused
                            ? (isDark ? Colors.white70 : Colors.black54)
                            : iconColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    // 输入框
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        autofocus: widget.autofocus,
                        enabled: widget.enabled,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                        ),
                        decoration: InputDecoration(
                          hintText: widget.hintText,
                          hintStyle: TextStyle(
                            color: hintColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: widget.onChanged,
                        onSubmitted: widget.onSubmitted,
                        textInputAction: TextInputAction.search,
                      ),
                    ),
                    // 清除按钮（有文本时显示）
                    if (_hasText)
                      GestureDetector(
                        onTap: _handleClear,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.18)
                                  : Colors.black.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.close_rounded,
                              size: 11,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          // 取消按钮
          if (widget.showCancelButton && (_isFocused || _hasText)) ...[
            const SizedBox(width: 12),
            GestureDetector(
              onTap: _handleCancel,
              child: Text(
                '取消',
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// iOS 26 风格悬浮返回按钮
///
/// 用于详情页面左上角的返回按钮，悬浮在内容之上
/// 特性：
/// - 圆形玻璃背景
/// - iOS 26+: 使用原生 UIGlassEffect
/// - iOS < 26 / 其他平台: 使用 Flutter BackdropFilter
/// - 支持自定义图标
/// - 支持标题（可选）
///
/// 使用示例：
/// ```dart
/// GlassFloatingBackButton(
///   onPressed: () => Navigator.pop(context),
/// )
/// ```
class GlassFloatingBackButton extends ConsumerWidget {
  const GlassFloatingBackButton({
    this.onPressed,
    this.icon = Icons.arrow_back_ios_new_rounded,
    this.iconSize = 18,
    this.title,
    this.color,
    this.showBackground = true,
    super.key,
  });

  /// 点击回调（默认 Navigator.pop）
  final VoidCallback? onPressed;

  /// 图标
  final IconData icon;

  /// 图标大小
  final double iconSize;

  /// 可选标题（显示在图标右侧）
  final String? title;

  /// 图标颜色（默认根据主题自动选择）
  final Color? color;

  /// 是否显示玻璃背景
  final bool showBackground;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiStyle = ref.watch(uiStyleProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = color ?? (isDark ? Colors.white : Colors.black87);

    final onTap = onPressed ?? () => Navigator.of(context).maybePop();

    // 经典模式：简单的 IconButton
    if (!uiStyle.isGlass) {
      if (title != null) {
        return TextButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: iconSize, color: iconColor),
          label: Text(
            title!,
            style: TextStyle(
              color: iconColor,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      }
      return IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: iconSize, color: iconColor),
        tooltip: '返回',
      );
    }

    // 玻璃模式
    if (!showBackground) {
      // 无背景模式：仅图标
      return GestureDetector(
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: iconSize, color: iconColor),
            if (title != null) ...[
              const SizedBox(width: 4),
              Text(
                title!,
                style: TextStyle(
                  color: iconColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      );
    }

    // 有标题时使用胶囊形状
    if (title != null) {
      return GlassButtonGroup(
        children: [
          GestureDetector(
            onTap: onTap,
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: iconSize, color: iconColor),
                  const SizedBox(width: 6),
                  Text(
                    title!,
                    style: TextStyle(
                      color: iconColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // 仅图标时：使用胶囊形状而不是圆形，更符合 iOS 26 返回按钮风格
    // 添加 "返回" 文字或使用较宽的胶囊以区别于普通圆形按钮
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.black.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.15)
                    : Colors.black.withValues(alpha: 0.08),
                width: 0.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: iconSize, color: iconColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// iOS 26 风格玻璃导航栏
///
/// 用于详情页和列表页顶部，实现悬浮玻璃导航效果
/// 特性：
/// - 左侧返回按钮（可选）
/// - 中间标题（可选）
/// - 右侧操作按钮组（可选）
/// - 完全透明背景，悬浮于内容之上
///
/// 使用示例：
/// ```dart
/// GlassNavigationBar(
///   leading: GlassFloatingBackButton(),
///   title: '电影详情',
///   trailing: GlassButtonGroup(children: [...]),
/// )
/// ```
class GlassNavigationBar extends ConsumerWidget {
  const GlassNavigationBar({
    this.leading,
    this.title,
    this.titleWidget,
    this.trailing,
    this.height = 44,
    this.horizontalPadding = 16,
    super.key,
  });

  /// 左侧组件（通常是 GlassFloatingBackButton）
  final Widget? leading;

  /// 标题文本
  final String? title;

  /// 标题组件（优先于 title）
  final Widget? titleWidget;

  /// 右侧组件（通常是 GlassButtonGroup）
  final Widget? trailing;

  /// 导航栏高度（不含安全区域）
  final double height;

  /// 水平内边距
  final double horizontalPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final safeTop = MediaQuery.of(context).padding.top;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        height: safeTop + height,
        padding: EdgeInsets.only(top: safeTop),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: Row(
            children: [
              // 左侧
              if (leading != null) leading!,
              // 中间标题
              if (titleWidget != null || title != null)
                Expanded(
                  child: titleWidget ??
                      Text(
                        title!,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                )
              else
                const Spacer(),
              // 右侧
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

/// iOS 26 风格玻璃详情页顶栏
///
/// 专门用于详情页（如电影详情、剧集详情），提供：
/// - 左侧返回按钮（圆形玻璃背景）
/// - 右侧操作按钮组
/// - 完全透明，悬浮于内容之上
/// - 内容可滚动到按钮下方
///
/// 通常配合 Scaffold.extendBodyBehindAppBar 使用
class GlassDetailPageHeader extends ConsumerWidget {
  const GlassDetailPageHeader({
    this.onBack,
    this.actions,
    this.actionButtons,
    super.key,
  });

  /// 返回按钮回调（默认 Navigator.pop）
  final VoidCallback? onBack;

  /// 右侧操作按钮列表（GlassGroupIconButton）
  final List<Widget>? actions;

  /// 右侧按钮组组件（优先于 actions）
  final Widget? actionButtons;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final safeTop = MediaQuery.of(context).padding.top;

    return Positioned(
      top: safeTop + 8,
      left: 16,
      right: 16,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 左侧返回按钮
          GlassFloatingBackButton(onPressed: onBack),
          // 右侧操作按钮
          if (actionButtons != null)
            actionButtons!
          else if (actions != null && actions!.isNotEmpty)
            GlassButtonGroup(children: actions!),
        ],
      ),
    );
  }
}

/// iOS 26 风格玻璃列表页顶栏
///
/// 用于列表页（如"查看全部"页面），提供：
/// - 左侧返回按钮
/// - 中间标题
/// - 右侧操作按钮组（可选）
/// - 悬浮于内容之上
class GlassListPageHeader extends ConsumerWidget {
  const GlassListPageHeader({
    required this.title,
    this.onBack,
    this.subtitle,
    this.actions,
    super.key,
  });

  /// 页面标题
  final String title;

  /// 副标题（可选）
  final String? subtitle;

  /// 返回按钮回调
  final VoidCallback? onBack;

  /// 右侧操作按钮
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final safeTop = MediaQuery.of(context).padding.top;

    return Positioned(
      top: safeTop + 8,
      left: 16,
      right: 16,
      child: Row(
        children: [
          // 左侧返回按钮（带标题）
          GlassFloatingBackButton(
            onPressed: onBack,
            title: title,
          ),
          const Spacer(),
          // 右侧操作按钮
          if (actions != null && actions!.isNotEmpty)
            GlassButtonGroup(children: actions!),
        ],
      ),
    );
  }
}

/// iOS 26 风格玻璃搜索栏（悬浮版）
///
/// 用于浮动在内容上方的搜索栏，通常与 GlassButtonGroup 配合使用
class GlassFloatingSearchBar extends StatelessWidget {
  const GlassFloatingSearchBar({
    required this.controller,
    required this.onChanged,
    required this.onClose,
    this.hintText = '搜索',
    this.width = 240,
    super.key,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;
  final String hintText;
  final double width;

  @override
  Widget build(BuildContext context) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 玻璃搜索框 - 必须传递 width 给 GlassSearchBar，否则 iOS UiKitView 无法确定尺寸
        GlassSearchBar(
          controller: controller,
          hintText: hintText,
          onChanged: onChanged,
          autofocus: true,
          showCancelButton: false,
          height: 44,
          width: width,
        ),
        const SizedBox(width: 8),
        // 关闭按钮（圆形玻璃图标）
        GlassIconButton(
          icon: Icons.close_rounded,
          size: 18,
          onPressed: () {
            controller.clear();
            onChanged('');
            onClose();
          },
          tooltip: '关闭搜索',
        ),
      ],
    );
}

/// iOS 26 自适应列表页 Scaffold
///
/// 自动处理经典模式和玻璃模式的 AppBar 显示：
/// - 经典模式：使用标准 AppBar
/// - 玻璃模式：使用 Stack 布局，内容延伸到顶部，悬浮玻璃按钮
///
/// 使用示例：
/// ```dart
/// AdaptiveListScaffold(
///   title: '全部电影',
///   subtitle: '123 部',
///   onBack: () => Navigator.pop(context),
///   actions: [
///     GlassGroupIconButton(icon: Icons.sort, onPressed: _showSort),
///     GlassGroupIconButton(icon: Icons.filter_alt, onPressed: _showFilter),
///   ],
///   body: GridView.builder(...),
/// )
/// ```
class AdaptiveListScaffold extends ConsumerWidget {
  const AdaptiveListScaffold({
    required this.title,
    required this.body,
    this.subtitle,
    this.onBack,
    this.actions,
    this.classicAppBarActions,
    this.floatingContent,
    this.backgroundColor,
    this.classicAppBarBackgroundColor,
    super.key,
  });

  /// 页面标题
  final String title;

  /// 副标题（如数量）
  final String? subtitle;

  /// 返回按钮回调
  final VoidCallback? onBack;

  /// 右侧操作按钮（玻璃模式下显示为 GlassButtonGroup 的子项）
  final List<Widget>? actions;

  /// 经典模式的 AppBar actions（如果与玻璃模式不同）
  final List<Widget>? classicAppBarActions;

  /// 页面内容
  final Widget body;

  /// 悬浮内容（如筛选标签，显示在顶栏下方）
  final Widget? floatingContent;

  /// 背景颜色
  final Color? backgroundColor;

  /// 经典模式 AppBar 背景颜色
  final Color? classicAppBarBackgroundColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uiStyle = ref.watch(uiStyleProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final safeTop = MediaQuery.of(context).padding.top;

    final bgColor = backgroundColor ??
        (isDark ? AppColors.darkBackground : Colors.grey[50]);

    // iOS 26 玻璃模式：Stack 布局
    if (uiStyle.isGlass) {
      return Scaffold(
        backgroundColor: bgColor,
        body: Stack(
          children: [
            // 主内容（顶部留出安全区 + 顶栏空间）
            Positioned.fill(
              child: Column(
                children: [
                  // 顶部留白（安全区 + 顶栏 + 间距）
                  SizedBox(height: safeTop + 56),
                  // 悬浮内容
                  if (floatingContent != null) floatingContent!,
                  // 主内容
                  Expanded(child: body),
                ],
              ),
            ),
            // 悬浮顶栏
            Positioned(
              top: safeTop + 8,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  // 左侧返回按钮 + 标题
                  Expanded(
                    child: GlassFloatingBackButton(
                      onPressed: onBack,
                      title: subtitle != null ? '$title ($subtitle)' : title,
                    ),
                  ),
                  // 右侧操作按钮
                  if (actions != null && actions!.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    GlassButtonGroup(children: actions!),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }

    // 经典模式：标准 AppBar
    final displayTitle = subtitle != null ? '$title ($subtitle)' : title;
    final appBarBgColor = classicAppBarBackgroundColor ??
        (isDark ? AppColors.darkSurface : Colors.white);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: appBarBgColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_rounded,
            color: isDark ? Colors.white : Colors.black87,
          ),
          onPressed: onBack ?? () => Navigator.of(context).pop(),
        ),
        title: Text(
          displayTitle,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        actions: classicAppBarActions ?? actions,
      ),
      body: Column(
        children: [
          if (floatingContent != null) floatingContent!,
          Expanded(child: body),
        ],
      ),
    );
  }
}
