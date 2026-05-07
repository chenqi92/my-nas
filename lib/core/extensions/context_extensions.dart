import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/services/toast_service.dart';
import 'package:my_nas/shared/providers/ui_style_provider.dart';
import 'package:my_nas/shared/widgets/toast_overlay.dart';

extension BuildContextExtensions on BuildContext {
  // Theme
  ThemeData get theme => Theme.of(this);
  ColorScheme get colorScheme => theme.colorScheme;
  TextTheme get textTheme => theme.textTheme;
  bool get isDarkMode => theme.brightness == Brightness.dark;

  // ============ 悬浮导航栏支持 ============

  /// 获取滚动内容的底部 padding
  ///
  /// 在 iOS 玻璃风格模式下，此值包含：
  /// - 系统安全区域（Home Indicator）
  /// - 原生 UITabBar 高度 (49pt)
  ///
  /// 用于 ListView、GridView、CustomScrollView 等滚动组件的底部 padding，
  /// 确保内容可以滚动到导航栏后面，而最后一项不会被遮挡。
  ///
  /// 使用示例:
  /// ```dart
  /// ListView(
  ///   padding: EdgeInsets.only(bottom: context.scrollBottomPadding),
  /// )
  /// ```
  double get scrollBottomPadding {
    var padding = mediaQuery.padding.bottom;

    // iOS 玻璃风格下需要额外添加原生 Tab Bar 的高度
    // 因为原生 UITabBar 悬浮在 Flutter 内容之上
    if (!kIsWeb && Platform.isIOS) {
      try {
        final container = ProviderScope.containerOf(this);
        final uiStyle = container.read(uiStyleProvider);
        if (uiStyle.isGlass) {
          // UITabBar 标准高度约 49pt
          padding += 49;
        } else {
          // 经典模式：Flutter 底部导航栏高度（56 + SafeArea）
          // 由于 MainScaffold 使用 extendBody: true，需要添加导航栏高度
          padding += 56;
        }
      } on Exception catch (_) {
        // 如果无法访问 provider，使用默认值（经典模式假设）
        padding += 56;
      }
    } else if (!kIsWeb && Platform.isAndroid) {
      // Android 经典模式也需要添加导航栏高度
      padding += 56;
    }
    // 桌面端使用侧边导航栏，不需要额外底部 padding

    return padding;
  }

  // ============ 语义化颜色（根据亮暗模式自动调整）============

  /// 成功颜色
  Color get successColor => AppColors.success;

  /// 警告颜色
  Color get warningColor => AppColors.warning;

  /// 信息颜色（使用主题色）
  Color get infoColor => colorScheme.primary;

  /// 危险/删除颜色
  Color get dangerColor => AppColors.error;

  /// 评分星星颜色
  Color get starColor => AppColors.warning;

  /// 禁用状态颜色
  Color get disabledColor => AppColors.disabled;

  /// 根据评分获取对应颜色
  /// - ≥8 分：绿色（高分）
  /// - 6-8 分：橙色（中等）
  /// - <6 分：红色（低分）
  Color ratingColor(double rating) => AppColors.ratingColor(rating);

  /// 占位符/骨架屏背景色（亮暗模式自适应）
  Color get placeholderColor =>
      isDarkMode ? colorScheme.surfaceContainerHighest : const Color(0xFFE0E0E0);

  /// 占位符/骨架屏高亮色（亮暗模式自适应）
  Color get placeholderHighlightColor =>
      isDarkMode ? colorScheme.surface : const Color(0xFFF5F5F5);

  // MediaQuery
  MediaQueryData get mediaQuery => MediaQuery.of(this);
  Size get screenSize => mediaQuery.size;
  double get screenWidth => screenSize.width;
  double get screenHeight => screenSize.height;
  EdgeInsets get padding => mediaQuery.padding;
  EdgeInsets get viewInsets => mediaQuery.viewInsets;
  EdgeInsets get viewPadding => mediaQuery.viewPadding;

  // Responsive
  bool get isCompact => screenWidth < 600;
  bool get isMedium => screenWidth >= 600 && screenWidth < 840;
  bool get isExpanded => screenWidth >= 840 && screenWidth < 1200;
  bool get isLarge => screenWidth >= 1200 && screenWidth < 1600;
  bool get isExtraLarge => screenWidth >= 1600;

  bool get isMobile => isCompact;
  bool get isTablet => isMedium || isExpanded;
  bool get isDesktop => isLarge || isExtraLarge;

  /// 是否使用桌面级 Shell 布局（NavigationRail / Master-Detail 等）。
  ///
  /// 与 [isDesktop] 的区别：
  /// - [isDesktop] 只看屏幕宽度（≥1200），用于已有页面内的 grid/列表样式判断；
  ///   保持原有语义，避免连带影响。
  /// - [isDesktopLayout] 仅决定外层 Shell 形态：
  ///   * macOS / Windows / Linux 桌面应用：始终为 true（不论窗口缩到多小都
  ///     保持 Rail，不退化成底部栏）；
  ///   * Web：按宽度，≥840 用 Rail；
  ///   * iOS / Android：始终为 false（移动端体验完全不变）。
  bool get isDesktopLayout {
    if (kIsWeb) {
      return screenWidth >= 840;
    }
    return Platform.isMacOS || Platform.isWindows || Platform.isLinux;
  }

  // Navigation
  NavigatorState get navigator => Navigator.of(this);
  void pop<T>([T? result]) => navigator.pop(result);
  Future<T?> push<T>(Route<T> route) => navigator.push(route);

  // ============ Toast 消息（新版，推荐使用）============

  /// 获取 ToastService 实例
  ToastService? get _toastService => ToastServiceProvider.maybeOf(this);

  /// 显示 Toast 消息
  ///
  /// [message] 消息内容
  /// [type] 消息类型，默认为 info
  /// [duration] 持续时间，不传则使用默认值
  /// [action] 操作回调
  /// [actionLabel] 操作按钮标签
  void showToast(
    String message, {
    ToastType type = ToastType.info,
    Duration? duration,
    VoidCallback? action,
    String? actionLabel,
  }) {
    _toastService?.show(
      message,
      type: type,
      duration: duration,
      action: action,
      actionLabel: actionLabel,
      isDesktop: isDesktop,
    );
  }

  /// 显示成功 Toast
  void showSuccessToast(String message, {VoidCallback? action, String? actionLabel}) {
    _toastService?.success(message, action: action, actionLabel: actionLabel, isDesktop: isDesktop);
  }

  /// 显示信息 Toast
  void showInfoToast(String message, {VoidCallback? action, String? actionLabel}) {
    _toastService?.info(message, action: action, actionLabel: actionLabel, isDesktop: isDesktop);
  }

  /// 显示警告 Toast
  void showWarningToast(String message, {VoidCallback? action, String? actionLabel}) {
    _toastService?.warning(message, action: action, actionLabel: actionLabel, isDesktop: isDesktop);
  }

  /// 显示错误 Toast
  void showErrorToast(String message, {VoidCallback? action, String? actionLabel}) {
    _toastService?.error(message, action: action, actionLabel: actionLabel, isDesktop: isDesktop);
  }

  // ============ SnackBar（旧版，兼容保留，内部使用 Toast）============

  // ignore: deprecated_member_use_from_same_package
  ScaffoldMessengerState get scaffoldMessenger => ScaffoldMessenger.of(this);

  /// 显示普通消息（使用 Toast 系统）
  void showSnackBar(
    String message, {
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    // 优先使用 Toast 系统
    if (_toastService != null) {
      showInfoToast(
        message,
        action: action?.onPressed,
        actionLabel: action?.label,
      );
    } else {
      // 回退到原生 SnackBar
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(message),
          duration: duration,
          action: action,
        ),
      );
    }
  }

  /// 显示错误消息（使用 Toast 系统）
  void showErrorSnackBar(String message) {
    if (_toastService != null) {
      showErrorToast(message);
    } else {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: colorScheme.error,
        ),
      );
    }
  }

  /// 显示成功消息（使用 Toast 系统）
  void showSuccessSnackBar(String message) {
    if (_toastService != null) {
      showSuccessToast(message);
    } else {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: successColor,
        ),
      );
    }
  }

  /// 显示警告消息（使用 Toast 系统）
  void showWarningSnackBar(String message) {
    if (_toastService != null) {
      showWarningToast(message);
    } else {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: warningColor,
        ),
      );
    }
  }
}
