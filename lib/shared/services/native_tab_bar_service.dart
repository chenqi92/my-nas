import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/utils/debug_log.dart';

/// 原生 Tab Bar 服务
///
/// 用于与 iOS 原生 UITabBarController 通信，实现 Liquid Glass 效果
/// 在非 iOS 平台上，所有方法都是空操作
class NativeTabBarService {
  NativeTabBarService._();

  static final NativeTabBarService _instance = NativeTabBarService._();
  static NativeTabBarService get instance => _instance;

  static const _channelName = 'com.kkape.mynas/native_tab_bar';
  MethodChannel? _channel;

  /// Tab 选择回调
  final _tabSelectedController = StreamController<TabSelectedEvent>.broadcast();

  /// 主题变化回调
  final _themeChangedController = StreamController<bool>.broadcast();

  /// Tab 选择事件流
  Stream<TabSelectedEvent> get onTabSelected => _tabSelectedController.stream;

  /// 主题变化事件流（true = dark）
  Stream<bool> get onThemeChanged => _themeChangedController.stream;

  /// 是否是 iOS 平台
  bool get _isIOS => !kIsWeb && Platform.isIOS;

  /// 是否已初始化
  bool _isInitialized = false;

  /// 是否启用原生 Tab Bar（仅在玻璃模式下启用）
  /// 由 MainScaffold 在 UI 风格变化时更新
  bool _isNativeTabBarEnabled = false;

  /// 获取原生 Tab Bar 是否启用
  bool get isNativeTabBarEnabled => _isNativeTabBarEnabled;

  /// 设置原生 Tab Bar 启用状态
  /// 由 MainScaffold 调用
  void setNativeTabBarEnabled(bool enabled) {
    _isNativeTabBarEnabled = enabled;
    debugLog('NativeTabBarService: Native tab bar enabled: $enabled');
  }

  /// 初始化服务
  ///
  /// 在 app 启动时调用
  void initialize() {
    if (!_isIOS || _isInitialized) return;

    _channel = const MethodChannel(_channelName);
    _channel!.setMethodCallHandler(_handleMethodCall);
    _isInitialized = true;

    debugLog('NativeTabBarService: Initialized');
  }

  /// 处理来自原生的方法调用
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onTabSelected':
        final args = call.arguments as Map<dynamic, dynamic>;
        final index = args['index'] as int;
        final route = args['route'] as String;

        debugLog('NativeTabBarService: Tab selected - index: $index, route: $route');
        _tabSelectedController.add(TabSelectedEvent(index: index, route: route));
        return null;

      case 'onThemeChanged':
        final isDark = call.arguments as bool;
        debugLog('NativeTabBarService: Theme changed - isDark: $isDark');
        _themeChangedController.add(isDark);
        return null;

      default:
        throw PlatformException(
          code: 'Unimplemented',
          details: 'Method ${call.method} not implemented',
        );
    }
  }

  /// 设置选中的 Tab 索引
  ///
  /// 当 Flutter 路由变化时调用，同步原生 Tab Bar
  Future<void> setSelectedIndex(int index) async {
    if (!_isIOS || _channel == null) return;

    await AppError.guard(
      () => _channel!.invokeMethod<void>('setSelectedIndex', index),
      action: 'setSelectedIndex',
    );
  }

  /// 获取当前选中的 Tab 索引
  Future<int> getSelectedIndex() async {
    if (!_isIOS || _channel == null) return 0;

    final result = await AppError.guard(
      () => _channel!.invokeMethod<int>('getSelectedIndex'),
      action: 'getSelectedIndex',
    );
    return result ?? 0;
  }

  /// 设置原生 Tab Bar 是否处于「滚动最小化」状态（仅 iOS 26+ 生效）
  ///
  /// iOS 26 的 `tabBarMinimizeBehavior` 依赖 UIKit 自己找到一个原生
  /// UIScrollView 来追踪滚动，而 Flutter 的滚动全部发生在 FlutterView
  /// 内部，UIKit 追踪不到，该属性形同虚设。因此原生侧设为 `.never`，
  /// 由 Flutter 监听自己的滚动事件后调用此方法显式驱动。
  ///
  /// iOS 26 以下与非 iOS 平台调用即忽略，行为完全不变。
  Future<void> setTabBarMinimized({required bool minimized}) async {
    if (!_isIOS || _channel == null) return;
    if (_lastMinimized == minimized) return;
    _lastMinimized = minimized;

    await AppError.guard(
      () => _channel!.invokeMethod<void>('setTabBarMinimized', minimized),
      action: 'setTabBarMinimized',
    );
  }

  /// 上一次下发的最小化状态，避免滚动过程中每帧都过桥
  bool? _lastMinimized;

  /// 获取 Tab Bar 高度
  Future<double> getTabBarHeight() async {
    if (!_isIOS || _channel == null) return 49.0; // iOS 默认 tab bar 高度

    final result = await AppError.guard(
      () => _channel!.invokeMethod<double>('getTabBarHeight'),
      action: 'getTabBarHeight',
    );
    return result ?? 49.0;
  }

  /// 获取底部安全区高度
  Future<double> getSafeAreaBottom() async {
    if (!_isIOS || _channel == null) return 34.0; // iPhone 默认底部安全区

    final result = await AppError.guard(
      () => _channel!.invokeMethod<double>('getSafeAreaBottom'),
      action: 'getSafeAreaBottom',
    );
    return result ?? 34.0;
  }

  /// 检查是否支持 Liquid Glass
  Future<bool> isLiquidGlassSupported() async {
    if (!_isIOS || _channel == null) return false;

    final result = await AppError.guard(
      () => _channel!.invokeMethod<bool>('isLiquidGlassSupported'),
      action: 'isLiquidGlassSupported',
    );
    return result ?? false;
  }

  /// 设置 Tab Bar 是否可见
  ///
  /// 用于在全屏页面（如视频播放、图片查看）隐藏 tab bar
  /// 注意：仅在原生 Tab Bar 启用时生效（玻璃模式）
  /// 经典模式下此方法不会有任何效果
  Future<void> setTabBarVisible(bool visible) async {
    if (!_isIOS || _channel == null) return;

    // 经典模式下不操作原生 Tab Bar
    // 显示时需要检查是否启用，隐藏时总是允许（以防万一）
    if (visible && !_isNativeTabBarEnabled) {
      debugLog('NativeTabBarService: Ignoring setTabBarVisible(true) - native tab bar not enabled');
      return;
    }

    await AppError.guard(
      () => _channel!.invokeMethod<void>('setTabBarVisible', visible),
      action: 'setTabBarVisible',
    );
  }

  /// 获取 Tab Bar 是否可见
  Future<bool> isTabBarVisible() async {
    if (!_isIOS || _channel == null) return true;

    final result = await AppError.guard(
      () => _channel!.invokeMethod<bool>('isTabBarVisible'),
      action: 'isTabBarVisible',
    );
    return result ?? true;
  }

  /// 释放资源
  void dispose() {
    _tabSelectedController.close();
    _themeChangedController.close();
  }
}

/// Tab 选择事件
class TabSelectedEvent {
  const TabSelectedEvent({
    required this.index,
    required this.route,
  });

  /// 选中的 Tab 索引
  final int index;

  /// 对应的 Flutter 路由
  final String route;

  @override
  String toString() => 'TabSelectedEvent(index: $index, route: $route)';
}
