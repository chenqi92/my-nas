import 'package:flutter/material.dart';
import 'package:my_nas/shared/providers/bottom_nav_visibility_provider.dart';
import 'package:my_nas/shared/services/native_tab_bar_service.dart';

/// 导航扩展方法
///
/// 提供自动隐藏/恢复底部导航栏的导航方法
extension NavigationExtensions on NavigatorState {
  /// Push 一个页面并自动隐藏底部导航栏
  ///
  /// 在页面返回后自动恢复底部导航栏
  /// 同时控制：
  /// - iOS 玻璃风格：原生 UITabBar
  /// - 经典风格：Flutter BottomNavigationBar
  Future<T?> pushAndHideBottomNav<T extends Object?>(Route<T> route) async {
    // 隐藏底栏
    _hideBottomNav();

    // 等待页面返回
    final result = await push<T>(route);

    // 恢复底栏
    _showBottomNav();

    return result;
  }

  /// Push 一个 MaterialPageRoute 并自动隐藏底部导航栏
  Future<T?> pushPageAndHideBottomNav<T extends Object?>({
    required Widget page,
    bool fullscreenDialog = false,
  }) => pushAndHideBottomNav<T>(
      MaterialPageRoute<T>(
        builder: (context) => page,
        fullscreenDialog: fullscreenDialog,
      ),
    );
}

/// BuildContext 导航扩展
extension ContextNavigationExtensions on BuildContext {
  /// Push 一个页面并自动隐藏底部导航栏
  Future<T?> pushPageAndHideBottomNav<T extends Object?>({
    required Widget page,
    bool fullscreenDialog = false,
  }) => Navigator.of(this).pushPageAndHideBottomNav<T>(
      page: page,
      fullscreenDialog: fullscreenDialog,
    );
}

/// 隐藏底部导航栏
void _hideBottomNav() {
  // 控制 iOS 原生 Tab Bar（玻璃风格）
  NativeTabBarService.instance.setTabBarVisible(false);
  // 控制 Flutter 导航栏（经典风格）
  BottomNavVisibilityNotifier.instance?.hide();
}

/// 显示底部导航栏
void _showBottomNav() {
  // 控制 iOS 原生 Tab Bar（玻璃风格）
  NativeTabBarService.instance.setTabBarVisible(true);
  // 控制 Flutter 导航栏（经典风格）
  BottomNavVisibilityNotifier.instance?.show();
}

/// 全局函数：隐藏底部导航栏
///
/// 在无法使用扩展方法时使用
void hideBottomNavBar() => _hideBottomNav();

/// 全局函数：显示底部导航栏
///
/// 在无法使用扩展方法时使用
void showBottomNavBar() => _showBottomNav();
