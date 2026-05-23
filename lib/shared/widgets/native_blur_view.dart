import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// 原生模糊视图 - 在 Apple 平台使用原生 API 实现真正的系统级毛玻璃效果
///
/// iOS: 使用 UIVisualEffectView + UIBlurEffect
/// macOS: 使用 NSVisualEffectView
/// 其他平台: 回退到 Flutter 的 BackdropFilter
///
/// 特点：
/// - Apple 平台使用原生硬件加速，性能优异
/// - 自动适配系统主题（亮色/暗色模式）
/// - 与系统 UI 风格保持一致
/// - 支持活力效果（Vibrancy）
class NativeBlurView extends StatelessWidget {
  const NativeBlurView({
    required this.child,
    this.style = NativeBlurStyle.systemMaterial,
    this.isDark = false,
    this.cornerRadius = 0,
    this.enableBorder = true,
    this.borderOpacity = 0.2,
    this.enableVibrancy = false,
    this.fallbackBlurIntensity = 20,
    this.fallbackOpacity = 0.7,
    super.key,
  });

  /// 子组件
  final Widget child;

  /// 模糊样式
  final NativeBlurStyle style;

  /// 是否为深色模式
  final bool isDark;

  /// 圆角半径
  final double cornerRadius;

  /// 是否启用边框
  final bool enableBorder;

  /// 边框不透明度
  final double borderOpacity;

  /// 是否启用活力效果（仅 iOS）
  final bool enableVibrancy;

  /// 回退模式的模糊强度
  final double fallbackBlurIntensity;

  /// 回退模式的背景不透明度
  final double fallbackOpacity;

  /// 是否支持原生模糊（仅 iOS 和 macOS）
  static bool get isNativeBlurSupported =>
      !kIsWeb && (Platform.isIOS || Platform.isMacOS);

  @override
  Widget build(BuildContext context) {
    // Apple 平台使用原生实现
    if (isNativeBlurSupported) {
      return _NativeBlurPlatformView(
        style: style,
        isDark: isDark,
        cornerRadius: cornerRadius,
        enableBorder: enableBorder,
        borderOpacity: borderOpacity,
        enableVibrancy: enableVibrancy,
        child: child,
      );
    }

    // 其他平台使用 Flutter 实现
    return _FlutterBlurView(
      isDark: isDark,
      cornerRadius: cornerRadius,
      enableBorder: enableBorder,
      borderOpacity: borderOpacity,
      blurIntensity: fallbackBlurIntensity,
      opacity: fallbackOpacity,
      child: child,
    );
  }
}

/// 原生模糊样式枚举
enum NativeBlurStyle {
  /// 超薄材质（最透明）
  systemUltraThinMaterial,

  /// 薄材质
  systemThinMaterial,

  /// 标准材质
  systemMaterial,

  /// 厚材质
  systemThickMaterial,

  /// Chrome 材质（导航栏风格）
  systemChromeMaterial,

  /// 常规模糊
  regular,

  /// 突出模糊
  prominent,

  // macOS 专用材质
  /// 标题栏
  titlebar,

  /// 菜单
  menu,

  /// 弹出框
  popover,

  /// 侧边栏
  sidebar,

  /// 头部视图
  headerView,

  /// 表单
  sheet,

  /// 窗口背景
  windowBackground,

  /// 内容背景
  contentBackground,

  /// 窗口下方背景
  underWindowBackground,
}

/// 原生模糊 Platform View 包装
class _NativeBlurPlatformView extends StatelessWidget {
  const _NativeBlurPlatformView({
    required this.child,
    required this.style,
    required this.isDark,
    required this.cornerRadius,
    required this.enableBorder,
    required this.borderOpacity,
    required this.enableVibrancy,
  });

  final Widget child;
  final NativeBlurStyle style;
  final bool isDark;
  final double cornerRadius;
  final bool enableBorder;
  final double borderOpacity;
  final bool enableVibrancy;

  @override
  Widget build(BuildContext context) {
    final creationParams = <String, dynamic>{
      'style': _getStyleString(),
      'material': _getMaterialString(),
      'isDark': isDark,
      'cornerRadius': cornerRadius,
      'enableBorder': enableBorder,
      'borderOpacity': borderOpacity,
      'enableVibrancy': enableVibrancy,
      'blendingMode': 'behindWindow',
    };

    return Stack(
      fit: StackFit.passthrough,
      children: [
        // 原生模糊背景
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(cornerRadius),
            child: _buildPlatformView(creationParams),
          ),
        ),
        // Flutter 子组件
        child,
      ],
    );
  }

  Widget _buildPlatformView(Map<String, dynamic> creationParams) {
    const viewType = 'com.kkape.mynas/native_blur_view';

    if (Platform.isIOS) {
      return UiKitView(
        viewType: viewType,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      );
    } else if (Platform.isMacOS) {
      return AppKitView(
        viewType: viewType,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      );
    }

    return const SizedBox.shrink();
  }

  String _getStyleString() => switch (style) {
        NativeBlurStyle.systemUltraThinMaterial => 'systemUltraThinMaterial',
        NativeBlurStyle.systemThinMaterial => 'systemThinMaterial',
        NativeBlurStyle.systemMaterial => 'systemMaterial',
        NativeBlurStyle.systemThickMaterial => 'systemThickMaterial',
        NativeBlurStyle.systemChromeMaterial => 'systemChromeMaterial',
        NativeBlurStyle.regular => 'regular',
        NativeBlurStyle.prominent => 'prominent',
        _ => 'systemMaterial',
      };

  String _getMaterialString() => switch (style) {
        NativeBlurStyle.titlebar => 'titlebar',
        NativeBlurStyle.menu => 'menu',
        NativeBlurStyle.popover => 'popover',
        NativeBlurStyle.sidebar => 'sidebar',
        NativeBlurStyle.headerView => 'headerView',
        NativeBlurStyle.sheet => 'sheet',
        NativeBlurStyle.windowBackground => 'windowBackground',
        NativeBlurStyle.contentBackground => 'contentBackground',
        NativeBlurStyle.underWindowBackground => 'underWindowBackground',
        _ => 'contentBackground',
      };
}

/// Flutter 模糊视图回退实现
class _FlutterBlurView extends StatelessWidget {
  const _FlutterBlurView({
    required this.child,
    required this.isDark,
    required this.cornerRadius,
    required this.enableBorder,
    required this.borderOpacity,
    required this.blurIntensity,
    required this.opacity,
  });

  final Widget child;
  final bool isDark;
  final double cornerRadius;
  final bool enableBorder;
  final double borderOpacity;
  final double blurIntensity;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final bgColor = isDark
        ? Colors.black.withValues(alpha: opacity)
        : Colors.white.withValues(alpha: opacity);

    final borderColor = isDark
        ? Colors.white.withValues(alpha: borderOpacity)
        : Colors.black.withValues(alpha: borderOpacity * 0.5);

    return ClipRRect(
      borderRadius: BorderRadius.circular(cornerRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: blurIntensity,
          sigmaY: blurIntensity,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(cornerRadius),
            border: enableBorder
                ? Border.all(color: borderColor, width: 0.5)
                : null,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 便捷的玻璃卡片组件
/// 自动根据平台选择最佳模糊实现
class GlassCard extends StatelessWidget {
  const GlassCard({
    required this.child,
    this.isDark = false,
    this.cornerRadius = 20,
    this.padding = EdgeInsets.zero,
    this.enableBorder = true,
    this.borderOpacity = 0.2,
    this.style = NativeBlurStyle.systemMaterial,
    super.key,
  });

  final Widget child;
  final bool isDark;
  final double cornerRadius;
  final EdgeInsets padding;
  final bool enableBorder;
  final double borderOpacity;
  final NativeBlurStyle style;

  @override
  Widget build(BuildContext context) => NativeBlurView(
      style: style,
      isDark: isDark,
      cornerRadius: cornerRadius,
      enableBorder: enableBorder,
      borderOpacity: borderOpacity,
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
}
