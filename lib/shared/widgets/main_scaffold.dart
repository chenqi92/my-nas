import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:my_nas/app/router/app_router.dart';
import 'package:my_nas/app/router/routes.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/ui_style.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/shared/providers/bottom_nav_visibility_provider.dart';
import 'package:my_nas/shared/providers/ui_style_provider.dart';
import 'package:my_nas/shared/services/native_tab_bar_service.dart';
import 'package:my_nas/shared/services/update_service.dart';
import 'package:my_nas/shared/widgets/desktop_shell/desktop_scaffold.dart';
import 'package:my_nas/shared/widgets/desktop_shortcuts.dart';
import 'package:my_nas/shared/widgets/shell_layout.dart';
import 'package:my_nas/shared/widgets/tab_bar_minimize_on_scroll.dart';
import 'package:my_nas/shared/widgets/tv_shell/tv_back_policy.dart';
import 'package:my_nas/shared/widgets/tv_shell/tv_scaffold.dart';
import 'package:my_nas/shared/widgets/update_dialog.dart';

class MainScaffold extends ConsumerStatefulWidget {
  const MainScaffold({required this.navigationShell, super.key});

  /// StatefulShellRoute 注入的 shell，提供 currentIndex / goBranch / 各
  /// branch 的 Navigator。
  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends ConsumerState<MainScaffold> {
  static bool _hasCheckedForUpdates = false;

  /// 原生 Tab 选择订阅
  StreamSubscription<TabSelectedEvent>? _tabSelectedSubscription;

  /// 是否正在处理 Tab 切换（防止循环）
  bool _isHandlingTabChange = false;

  /// 缓存的 UI 风格（用于判断是否需要重新订阅原生 Tab Bar）
  UIStyle? _cachedUiStyle;

  /// 是否使用原生 Tab Bar
  /// 仅在 iOS 玻璃风格时使用原生 Tab Bar（Liquid Glass 效果）
  /// 经典风格使用 Flutter 自己的导航栏
  bool _shouldUseNativeTabBar(UIStyle uiStyle) {
    if (kIsWeb) return false;
    if (!Platform.isIOS) return false;
    // 仅玻璃风格使用原生 Tab Bar
    return uiStyle.isGlass;
  }

  @override
  void initState() {
    super.initState();

    // 仅在首次显示 MainScaffold 时检查更新
    if (!_hasCheckedForUpdates) {
      _hasCheckedForUpdates = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkForUpdatesOnStartup();
      });
    }
  }

  @override
  void dispose() {
    _tabSelectedSubscription?.cancel();
    super.dispose();
  }

  /// 处理原生 Tab 选择事件
  void _handleNativeTabSelected(TabSelectedEvent event) {
    if (_isHandlingTabChange || !mounted) return;

    _isHandlingTabChange = true;

    // 切换到主 Tab 页面时，重置底部导航栏可见性
    // 这确保从详情页直接切换 Tab 时导航栏能正确显示
    ref.read(bottomNavVisibleProvider.notifier).reset();

    // 使用原生传来的路由进行导航
    context.go(event.route);

    // 延迟重置标志，避免路由变化时触发循环
    Future.delayed(const Duration(milliseconds: 50), () {
      _isHandlingTabChange = false;
    });
  }

  Future<void> _checkForUpdatesOnStartup() async {
    // 仅在非 Web 平台检查更新
    if (kIsWeb) return;

    // 延迟一点时间，确保应用完全启动
    await Future<void>.delayed(const Duration(seconds: 2));

    final updateService = UpdateService();
    await updateService.checkForUpdates(silent: true);

    // 如果有更新，显示更新对话框
    if (updateService.hasUpdate && updateService.updateInfo != null && mounted) {
      // 检查是否是桌面平台或移动平台（iOS 除外，因为需要通过 App Store 更新）
      if (!Platform.isIOS) {
        await showUpdateDialog(context, updateService.updateInfo!);
      }
    }
  }

  // 5 主 tab 的 metadata。`branchIndex` 是它在 StatefulShellRoute.branches
  // 列表里的索引（顺序与 `app_router.dart::branchNavigatorKeys` 一致）。
  // 桌面新增 home/live/ops 后这些主 tab 不再是 0-4。
  static const _destinations = [
    _Destination(
      icon: Icons.movie_filter_outlined,
      selectedIcon: Icons.movie_filter_rounded,
      labelKey: 'mainNavTabFilms',
      route: Routes.video,
      branchIndex: AppBranch.video,
      sfSymbol: 'film',
    ),
    _Destination(
      icon: Icons.library_music_outlined,
      selectedIcon: Icons.library_music_rounded,
      labelKey: 'mainNavTabMusic',
      route: Routes.music,
      branchIndex: AppBranch.music,
      sfSymbol: 'music.note.list',
    ),
    _Destination(
      icon: Icons.photo_album_outlined,
      selectedIcon: Icons.photo_album_rounded,
      labelKey: 'mainNavTabPhotos',
      route: Routes.photo,
      branchIndex: AppBranch.photo,
      sfSymbol: 'photo.on.rectangle',
    ),
    _Destination(
      icon: Icons.menu_book_outlined,
      selectedIcon: Icons.menu_book_rounded,
      labelKey: 'mainNavTabReading',
      route: Routes.reading,
      branchIndex: AppBranch.reading,
      sfSymbol: 'book',
    ),
    _Destination(
      icon: Icons.account_circle_outlined,
      selectedIcon: Icons.account_circle_rounded,
      labelKey: 'mainNavTabMe',
      route: Routes.mine,
      branchIndex: AppBranch.mine,
      sfSymbol: 'person.circle',
    ),
  ];

  /// 主 tab + 工具区所有页面的路由（用于"是否在 branch 首屏"判断）
  static const _mainTabRoutes = {
    Routes.video,
    Routes.music,
    Routes.photo,
    Routes.reading,
    Routes.mine,
    Routes.download,
    Routes.transfer,
    Routes.sources,
  };

  /// 判断当前 GoRouter 路由是否是主 Tab 页面
  bool _isMainTabRoute(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    return _mainTabRoutes.contains(location);
  }

  /// 获取本地化的导航标签
  String _getLocalizedLabel(BuildContext context, String labelKey) => switch (labelKey) {
      'mainNavTabFilms' => context.l10n.mainNavTabFilms,
      'mainNavTabMusic' => context.l10n.mainNavTabMusic,
      'mainNavTabPhotos' => context.l10n.mainNavTabPhotos,
      'mainNavTabReading' => context.l10n.mainNavTabReading,
      'mainNavTabMe' => context.l10n.mainNavTabMe,
      _ => '',
    };

  /// `index` 是 _destinations 列表的索引（0..4）。
  /// 通过 destination.branchIndex 映射到全局 branch index。
  void _onDestinationSelected(BuildContext context, int index) {
    if (_isHandlingTabChange) return;

    _isHandlingTabChange = true;

    ref.read(bottomNavVisibleProvider.notifier).reset();

    final branchIndex = _destinations[index].branchIndex;
    widget.navigationShell.goBranch(
      branchIndex,
      initialLocation: branchIndex == widget.navigationShell.currentIndex,
    );

    Future.delayed(const Duration(milliseconds: 100), () {
      _isHandlingTabChange = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = widget.navigationShell.currentIndex;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final uiStyle = ref.watch(uiStyleProvider);
    final glassStyle = GlassTheme.getNavBarStyle(uiStyle, isDark: isDark);
    final optimizedStyle = PlatformGlassConfig.getOptimizedStyle(glassStyle, isDark: isDark);
    final enableGlass = PlatformGlassConfig.shouldEnableGlass(uiStyle);
    final useNativeTabBar = _shouldUseNativeTabBar(uiStyle);

    // 监听底部导航栏可见性
    // 由子页面通过 BottomNavVisibilityNotifier 控制
    final bottomNavVisible = ref.watch(bottomNavVisibleProvider);

    // 检查当前是否在主 Tab 路由上
    final isMainTabRoute = _isMainTabRoute(context);

    // 处理 UI 风格变化时的原生 Tab Bar 订阅
    _handleUiStyleChange(uiStyle, useNativeTabBar, currentIndex, bottomNavVisible);

    // Shell 布局判断：TV 模式优先；其次桌面平台走 Rail；移动平台走底栏；Web 按宽度。
    // 与 context.isDesktop（屏宽≥1200）解耦，避免桌面端缩窗口时退化为手机布局。
    // 优先级定义在 resolveShellLayout（纯函数，有单测穷举组合）。
    final layout = resolveShellLayout(
      isTvLayout: context.isTvLayout,
      isDesktopLayout: context.isDesktopLayout,
      useNativeTabBar: useNativeTabBar,
    );

    final Widget scaffold;
    if (layout == ShellLayout.tv) {
      // TV 模式：左侧 Rail + 主内容 + overscan 安全区
      scaffold = TvScaffold(navigationShell: widget.navigationShell);
    } else if (layout == ShellLayout.desktop) {
      // 桌面下统一覆盖各 page 的 AppBar 主题：高度 48（vs 56）、字号略减、
      // 去掉默认 elevation，使用扁平边框分隔。各 page 自己用 AppBar()
      // 都会自动应用，无需逐个改。自定义 Container 顶部条不受影响（需要
      // 各 page 自行响应 isDesktopLayout）。
      final desktopTheme = Theme.of(context).copyWith(
        appBarTheme: Theme.of(context).appBarTheme.copyWith(
              toolbarHeight: 48,
              elevation: 0,
              scrolledUnderElevation: 0,
              titleTextStyle: context.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: isDark
                    ? AppColors.darkOnSurface
                    : context.colorScheme.onSurface,
              ),
              shape: Border(
                bottom: BorderSide(
                  color: isDark
                      ? AppColors.darkOutline.withValues(alpha: 0.3)
                      : context.colorScheme.outlineVariant,
                ),
              ),
            ),
        // 桌面下 ListTile 默认 dense，整体信息密度提升一档。
        listTileTheme: Theme.of(context).listTileTheme.copyWith(
              dense: true,
              minVerticalPadding: 6,
              visualDensity: VisualDensity.compact,
            ),
        // 桌面下 IconButton 视觉密度紧凑。
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            visualDensity: VisualDensity.compact,
          ),
        ),
        // 桌面下 OutlinedButton / FilledButton 默认 padding 紧凑。
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          ),
        ),
        // 整体页面默认走更高视觉密度（让 Material 自身的 ListTile /
        // TextField / Switch / Checkbox 等都跟着变紧凑）。
        visualDensity: VisualDensity.compact,
        // 桌面 SnackBar：floating + 圆角 + 限宽，避免在大屏全宽铺满。
        snackBarTheme: Theme.of(context).snackBarTheme.copyWith(
              behavior: SnackBarBehavior.floating,
              width: 480,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
        // 桌面 Dialog：稍紧凑的圆角 + 默认 elevation 减小。
        dialogTheme: Theme.of(context).dialogTheme.copyWith(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 12,
            ),
      );
      // 桌面端走重设计的 DesktopScaffold（sidebar + topbar + mini dock +
      // cmdk + activity drawer + ambient），原 _buildDesktopNav 已下线。
      // desktopTheme 在外壳内层注入，让各 page 的 AppBar/ListTile 享受
      // 桌面紧凑视觉。
      scaffold = Theme(
        data: desktopTheme,
        child: MediaQuery.removePadding(
          context: context,
          removeTop: true,
          child: DesktopScaffold(navigationShell: widget.navigationShell),
        ),
      );
    } else if (layout == ShellLayout.nativeTabBar) {
      // iOS 玻璃风格：使用原生 UITabBar
      //
      // 在这里统一包一层滚动最小化，而不是逐个页面包裹：
      // NotificationListener 会收到所有后代的滚动通知，一处接线覆盖全部
      // 主 Tab 页面，也不会漏掉后续新增的滚动区域。
      // 此分支仅 iOS 玻璃模式可达，Android / 桌面 / 经典模式不受影响。
      scaffold = Scaffold(
        backgroundColor: isDark ? AppColors.darkBackground : null,
        body: TabBarMinimizeOnScroll(child: widget.navigationShell),
      );
    } else {
      // 其他情况: 使用 Flutter 底部导航栏
      // 只有在主 Tab 路由且 provider 允许时才显示底栏
      final showBottomNav = isMainTabRoute && bottomNavVisible;

      scaffold = Scaffold(
        backgroundColor: isDark ? AppColors.darkBackground : null,
        // 始终让内容延伸到导航栏下方，确保动画平滑
        extendBody: true,
        body: widget.navigationShell,
        // 始终渲染导航栏，使用 AnimatedSlide 实现平滑过渡
        bottomNavigationBar: _AnimatedBottomNav(
          visible: showBottomNav,
          child: _buildMobileNav(
            context,
            currentIndex,
            isDark,
            optimizedStyle,
            enableGlass,
          ),
        ),
      );
    }

    // 桌面 / Web 注册全局快捷键（Cmd+1..5 切 tab、Esc pop）；
    // iOS / Android 直接返回 scaffold，DesktopShortcuts 内部会判断并 no-op。
    final shortcuts = DesktopShortcuts(
      onSwitchTab: (index) {
        widget.navigationShell.goBranch(
          index,
          initialLocation: index == widget.navigationShell.currentIndex,
        );
      },
      onGotoSettings: () {
        // 跳到 mine tab 并强制清空该 branch 栈，让用户看到设置主页。
        widget.navigationShell.goBranch(AppBranch.mine, initialLocation: true);
      },
      onEscape: () {
        // Esc 优先 pop 当前 branch navigator（覆盖 push 的详情/工具页），
        // 没有可 pop 的再尝试 root navigator（处理顶层模态）。
        final idx = widget.navigationShell.currentIndex;
        final branchKey =
            idx >= 0 && idx < branchNavigatorKeys.length
                ? branchNavigatorKeys[idx]
                : null;
        final branchNav = branchKey?.currentState;
        if (branchNav != null && branchNav.canPop()) {
          branchNav.maybePop();
          return;
        }
        final rootNav = rootNavigatorKey.currentState;
        if (rootNav != null && rootNav.canPop()) {
          rootNav.maybePop();
        }
      },
      child: scaffold,
    );

    // TV：遥控器 BACK 走逐级降级（模态 → 详情 → 首页 Tab → 退出应用）。
    // 非 TV 不包 PopScope，保持手机的系统返回手势和桌面行为不变。
    if (!context.isTvLayout) return shortcuts;

    return PopScope(
      // canPop: false 让所有 BACK 先进 onPopInvokedWithResult；
      // 只有解析成 exitApp 时才手动把这次返回交还系统。
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleTvBack();
      },
      child: shortcuts,
    );
  }

  /// TV BACK 键：按 [resolveTvBackAction] 的降级顺序执行。
  void _handleTvBack() {
    final idx = widget.navigationShell.currentIndex;
    final branchKey = idx >= 0 && idx < branchNavigatorKeys.length
        ? branchNavigatorKeys[idx]
        : null;
    final branchNav = branchKey?.currentState;
    final rootNav = rootNavigatorKey.currentState;

    final action = resolveTvBackAction(
      rootCanPop: rootNav?.canPop() ?? false,
      branchCanPop: branchNav?.canPop() ?? false,
      isHomeBranch: idx == tvRailBranches.first,
    );

    switch (action) {
      case TvBackAction.popRoot:
        rootNav?.maybePop();
      case TvBackAction.popBranch:
        branchNav?.maybePop();
      case TvBackAction.goHomeBranch:
        widget.navigationShell.goBranch(tvRailBranches.first);
      case TvBackAction.exitApp:
        // 交还系统：Android 上即退出应用。SystemNavigator.pop 在这里等价于
        // 让这次 BACK「未被消费」，不能用 Navigator.pop（栈底无可 pop 项）。
        AppError.fireAndForget(
          SystemNavigator.pop(),
          action: 'tvBack.exitApp',
        );
    }
  }

  /// 处理 UI 风格变化
  void _handleUiStyleChange(
    UIStyle uiStyle,
    bool useNativeTabBar,
    int currentIndex,
    bool bottomNavVisible,
  ) {
    // 首次调用或风格变化时
    if (_cachedUiStyle != uiStyle) {
      final wasUsingNative = _cachedUiStyle != null && _shouldUseNativeTabBar(_cachedUiStyle!);
      _cachedUiStyle = uiStyle;

      if (useNativeTabBar && !wasUsingNative) {
        // 切换到玻璃风格：启用原生 Tab Bar，订阅原生事件
        NativeTabBarService.instance.setNativeTabBarEnabled(true);
        _tabSelectedSubscription?.cancel();
        _tabSelectedSubscription =
            NativeTabBarService.instance.onTabSelected.listen(_handleNativeTabSelected);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          // 根据 provider 状态决定是否显示原生 Tab Bar
          NativeTabBarService.instance.setTabBarVisible(bottomNavVisible);
          if (bottomNavVisible) {
            final nativeIndex = mobileMainTabIndexForBranch(currentIndex);
            if (nativeIndex != null) {
              NativeTabBarService.instance.setSelectedIndex(nativeIndex);
            }
          }
        });
      } else if (!useNativeTabBar && wasUsingNative) {
        // 切换到经典风格：禁用原生 Tab Bar，取消订阅
        NativeTabBarService.instance.setNativeTabBarEnabled(false);
        _tabSelectedSubscription?.cancel();
        _tabSelectedSubscription = null;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          NativeTabBarService.instance.setTabBarVisible(false);
        });
      }
    } else if (useNativeTabBar) {
      // 玻璃风格下，根据 provider 状态更新原生 Tab Bar 可见性
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        NativeTabBarService.instance.setTabBarVisible(bottomNavVisible);
        if (bottomNavVisible && !_isHandlingTabChange) {
          final nativeIndex = mobileMainTabIndexForBranch(currentIndex);
          if (nativeIndex != null) {
            NativeTabBarService.instance.setSelectedIndex(nativeIndex);
          }
        }
      });
    }
  }

  Widget _buildMobileNav(
    BuildContext context,
    int currentIndex,
    bool isDark,
    GlassStyle glassStyle,
    bool enableGlass,
  ) {
    // 计算背景色
    final bgColor = enableGlass
        ? GlassTheme.getBackgroundColor(glassStyle, isDark: isDark)
        : (isDark ? AppColors.darkSurface : context.colorScheme.surface);

    final borderColor = enableGlass
        ? GlassTheme.getBorderColor(glassStyle, isDark: isDark)
        : (isDark
            ? AppColors.darkOutline.withValues(alpha: 0.3)
            : context.colorScheme.outlineVariant);

    Widget navContent = DecoratedBox(
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          top: BorderSide(color: borderColor),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: SizedBox(
            height: 56,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(_destinations.length, (index) {
                final dest = _destinations[index];
                final isSelected = currentIndex == dest.branchIndex;

                return Expanded(
                  child: GestureDetector(
                    onTap: () => _onDestinationSelected(context, index),
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primary.withValues(alpha: isDark ? 0.2 : 0.1)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            isSelected ? dest.selectedIcon : dest.icon,
                            color: isSelected
                                ? AppColors.primary
                                : isDark
                                    ? AppColors.darkOnSurfaceVariant
                                    : context.colorScheme.onSurfaceVariant,
                            size: 22,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _getLocalizedLabel(context, dest.labelKey),
                          style: TextStyle(
                            fontSize: 10,
                            color: isSelected
                                ? AppColors.primary
                                : isDark
                                    ? AppColors.darkOnSurfaceVariant
                                    : context.colorScheme.onSurfaceVariant,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );

    // 玻璃效果：添加模糊背景
    if (enableGlass && glassStyle.needsBlur) {
      navContent = ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: glassStyle.blurIntensity,
            sigmaY: glassStyle.blurIntensity,
          ),
          child: navContent,
        ),
      );
    }

    return navContent;
  }
}

class _Destination {
  const _Destination({
    required this.icon,
    required this.selectedIcon,
    required this.labelKey,
    required this.route,
    required this.branchIndex,
    this.sfSymbol,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String labelKey;
  final String route;

  /// 在 `StatefulShellRoute.branches` 中的全局索引（与 app_router 顺序一致）。
  final int branchIndex;
  final String? sfSymbol;
}

/// 桌面 NavigationRail 的单个入口。同时被主 tab 和工具区复用，
/// 主 tab 通过 [isSelected] 高亮，工具区始终未选中。
/// 带动画的底部导航栏包装器
///
/// 同时驱动 size / slide / opacity，确保隐藏时高度真正归零。
/// 仅做 transform/opacity 的方案会让 bottomNavigationBar 仍占据
/// 56+SafeArea.bottom 的布局高度，从而把 body 的 MediaQuery
/// bottom padding 顶大，导致页面底部出现一块空白。
class _AnimatedBottomNav extends StatefulWidget {
  const _AnimatedBottomNav({
    required this.visible,
    required this.child,
  });

  final bool visible;
  final Widget child;

  @override
  State<_AnimatedBottomNav> createState() => _AnimatedBottomNavState();
}

class _AnimatedBottomNavState extends State<_AnimatedBottomNav>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    duration: const Duration(milliseconds: 300),
    vsync: this,
    value: widget.visible ? 1.0 : 0.0,
  );

  late final CurvedAnimation _curve =
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut);

  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 1),
    end: Offset.zero,
  ).animate(_curve);

  @override
  void didUpdateWidget(covariant _AnimatedBottomNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != oldWidget.visible) {
      if (widget.visible) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizeTransition(
        sizeFactor: _curve,
        axisAlignment: -1.0,
        child: SlideTransition(
          position: _slide,
          child: FadeTransition(
            opacity: _curve,
            child: widget.child,
          ),
        ),
      );
}
