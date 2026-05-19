import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

abstract final class AppSpacing {
  // Base unit: 4px
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double xxxxl = 48;

  // ============================================================================
  // 平台自适应间距
  // ============================================================================

  /// 是否为桌面平台
  static bool get _isDesktop =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  /// 卡片内边距
  /// 桌面端：12dp，移动端：16dp
  static EdgeInsets get cardPadding => _isDesktop
      ? const EdgeInsets.all(md)
      : const EdgeInsets.all(lg);

  /// 列表项内边距
  /// 桌面端：更紧凑，移动端：更宽松便于触摸
  static EdgeInsets get listItemPadding => _isDesktop
      ? const EdgeInsets.symmetric(horizontal: md, vertical: sm)
      : const EdgeInsets.symmetric(horizontal: lg, vertical: md);

  /// 列表项垂直内边距
  static double get listItemVerticalPadding => _isDesktop ? sm : md;

  /// 列表项水平内边距
  static double get listItemHorizontalPadding => _isDesktop ? md : lg;

  /// 网格间距
  static double get gridSpacing => _isDesktop ? lg : 10;

  /// 页面内边距
  static EdgeInsets get pagePadding => _isDesktop
      ? const EdgeInsets.all(lg)
      : const EdgeInsets.symmetric(horizontal: md, vertical: sm);

  /// 对话框内边距
  static EdgeInsets get dialogPadding => _isDesktop
      ? const EdgeInsets.all(xxl)
      : const EdgeInsets.all(lg);

  /// 工具栏按钮间距
  static double get toolbarButtonSpacing => _isDesktop ? sm : md;

  /// 图标与文字间距
  static double get iconTextGap => _isDesktop ? sm : md;

  /// 分组标题与内容间距
  static double get sectionSpacing => _isDesktop ? lg : xl;

  /// 底部操作栏高度
  static double get bottomBarHeight => _isDesktop ? 56 : 64;

  // ============================================================================
  // 触摸目标尺寸
  // ============================================================================

  /// 最小触摸目标尺寸
  /// 移动端：48dp（Material Design 规范）
  /// 桌面端：32dp（鼠标点击精度更高）
  static double get minTouchTarget => _isDesktop ? 32 : 48;

  /// 图标按钮尺寸
  static double get iconButtonSize => _isDesktop ? 36 : 44;

  /// 紧凑图标按钮尺寸
  static double get compactIconButtonSize => _isDesktop ? 28 : 36;

  // ============================================================================
  // 列表项高度
  // ============================================================================

  /// 标准列表项高度
  /// 移动端：72dp，桌面端：48dp
  static double get listItemHeight => _isDesktop ? 48 : 72;

  /// 紧凑列表项高度
  static double get compactListItemHeight => _isDesktop ? 40 : 56;

  /// 单行列表项高度
  static double get singleLineListItemHeight => _isDesktop ? 40 : 48;

  /// 双行列表项高度
  static double get twoLineListItemHeight => _isDesktop ? 56 : 72;

  /// 三行列表项高度
  static double get threeLineListItemHeight => _isDesktop ? 72 : 88;

  // ============================================================================
  // 图标尺寸
  // ============================================================================

  /// 标准图标尺寸
  static double get iconSize => _isDesktop ? 20 : 24;

  /// 小图标尺寸
  static double get smallIconSize => _isDesktop ? 16 : 20;

  /// 大图标尺寸
  static double get largeIconSize => _isDesktop ? 24 : 28;

  /// 列表前置图标尺寸
  static double get leadingIconSize => _isDesktop ? 20 : 24;

  /// 列表尾部图标尺寸
  static double get trailingIconSize => _isDesktop ? 18 : 20;

  // App bar content padding (inside SafeArea)
  // iOS: Minimal vertical padding since iOS navigation bars are compact
  // Android: Slightly more padding for Material feel
  // Desktop: Most padding for mouse interaction areas
  static EdgeInsets get appBarContentPadding {
    if (kIsWeb) {
      return const EdgeInsets.symmetric(horizontal: 16, vertical: 8);
    }
    if (Platform.isIOS) {
      // iOS: 更紧凑的顶部间距，符合 iOS HIG
      return const EdgeInsets.symmetric(horizontal: 16, vertical: 4);
    }
    if (Platform.isAndroid) {
      // Android: Material Design 适中间距
      return const EdgeInsets.symmetric(horizontal: 12, vertical: 6);
    }
    // Desktop: 更多呼吸空间
    return const EdgeInsets.symmetric(horizontal: 16, vertical: 8);
  }

  // App bar vertical padding only (for simpler cases)
  static double get appBarVerticalPadding {
    if (kIsWeb) return sm;
    if (Platform.isIOS) return xs;
    if (Platform.isAndroid) return 6;
    return sm;
  }

  // App bar horizontal padding
  static double get appBarHorizontalPadding {
    if (kIsWeb) return lg;
    if (Platform.isIOS) return lg;
    if (Platform.isAndroid) return md;
    return lg;
  }

  // Common paddings
  static const EdgeInsets paddingXs = EdgeInsets.all(xs);
  static const EdgeInsets paddingSm = EdgeInsets.all(sm);
  static const EdgeInsets paddingMd = EdgeInsets.all(md);
  static const EdgeInsets paddingLg = EdgeInsets.all(lg);
  static const EdgeInsets paddingXl = EdgeInsets.all(xl);
  static const EdgeInsets paddingXxl = EdgeInsets.all(xxl);

  // Horizontal paddings
  static const EdgeInsets paddingHorizontalSm =
      EdgeInsets.symmetric(horizontal: sm);
  static const EdgeInsets paddingHorizontalMd =
      EdgeInsets.symmetric(horizontal: md);
  static const EdgeInsets paddingHorizontalLg =
      EdgeInsets.symmetric(horizontal: lg);
  static const EdgeInsets paddingHorizontalXl =
      EdgeInsets.symmetric(horizontal: xl);

  // Vertical paddings
  static const EdgeInsets paddingVerticalSm =
      EdgeInsets.symmetric(vertical: sm);
  static const EdgeInsets paddingVerticalMd =
      EdgeInsets.symmetric(vertical: md);
  static const EdgeInsets paddingVerticalLg =
      EdgeInsets.symmetric(vertical: lg);
  static const EdgeInsets paddingVerticalXl =
      EdgeInsets.symmetric(vertical: xl);

  // Screen padding
  static const EdgeInsets screenPadding = EdgeInsets.symmetric(
    horizontal: lg,
    vertical: md,
  );
}

abstract final class AppRadius {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double full = 999;

  static const BorderRadius borderRadiusXs =
      BorderRadius.all(Radius.circular(xs));
  static const BorderRadius borderRadiusSm =
      BorderRadius.all(Radius.circular(sm));
  static const BorderRadius borderRadiusMd =
      BorderRadius.all(Radius.circular(md));
  static const BorderRadius borderRadiusLg =
      BorderRadius.all(Radius.circular(lg));
  static const BorderRadius borderRadiusXl =
      BorderRadius.all(Radius.circular(xl));
  static const BorderRadius borderRadiusXxl =
      BorderRadius.all(Radius.circular(xxl));
  static const BorderRadius borderRadiusFull =
      BorderRadius.all(Radius.circular(full));

  // ============================================================================
  // 平台自适应圆角
  // 桌面（macOS/Windows/Linux）默认更小、更克制；移动端保持现状。
  // ============================================================================

  static bool get _isDesktop =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  /// 卡片/容器圆角。桌面 8，移动 12。
  static double get card => _isDesktop ? sm : md;

  /// 弹层/Dialog/BottomSheet 圆角。桌面 8，移动 16。
  static double get sheet => _isDesktop ? sm : lg;

  /// 按钮/输入框圆角。桌面 6，移动 12。
  static double get control => _isDesktop ? 6.0 : md;

  /// 小型 chip / badge 圆角。桌面 4，移动 8。
  static double get chip => _isDesktop ? xs : sm;
}

/// 阴影/elevation 令牌。
/// 桌面端使用扁平 + 1px hairline 风格（与 macOS Settings / Linear 一致），
/// 移动端保持 Material 的层级阴影。
abstract final class AppElevation {
  static bool get _isDesktop =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  /// 普通卡片：桌面 0（靠 hairline border 分层），移动 1
  static double get card => _isDesktop ? 0.0 : 1.0;

  /// hover 提升：桌面 1，移动 2
  static double get hover => _isDesktop ? 1.0 : 2.0;

  /// dialog/弹窗：桌面 2，移动 8
  static double get dialog => _isDesktop ? 2.0 : 8.0;

  /// BottomSheet/Drawer：桌面 2，移动 16
  static double get sheet => _isDesktop ? 2.0 : 16.0;
}
