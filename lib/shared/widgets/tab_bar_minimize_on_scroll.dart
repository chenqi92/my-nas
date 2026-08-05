import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:my_nas/shared/services/native_tab_bar_service.dart';

/// 滚动时最小化 iOS 26 原生底栏
///
/// iOS 26 的 `UITabBarController.tabBarMinimizeBehavior` 需要 UIKit 自己找到
/// 一个原生 UIScrollView 来追踪滚动。Flutter 的滚动全部发生在 FlutterView
/// 内部，UIKit 追踪不到，该属性形同虚设（React Native 社区同样踩过此坑）。
///
/// 所以原生侧把 minimizeBehavior 设为 `.never`，改由这里监听 Flutter 自己的
/// 滚动通知，向下滚时收起底栏、向上滚时恢复。
///
/// **平台行为**：
/// - iOS 26+ 且玻璃风格：生效
/// - iOS 26 以下：`NativeTabBarService.setTabBarMinimized` 在原生侧被忽略，
///   等同于没有此组件
/// - Android / 桌面 / Web：`_isIOS` 判断直接返回，不产生任何调用
///
/// 用法：把页面的滚动区域包一层即可，无需改动滚动组件本身。
/// ```dart
/// TabBarMinimizeOnScroll(
///   child: CustomScrollView(slivers: [...]),
/// )
/// ```
class TabBarMinimizeOnScroll extends StatefulWidget {
  const TabBarMinimizeOnScroll({
    required this.child,
    this.threshold = 12,
    super.key,
  });

  final Widget child;

  /// 触发阈值（像素）。小幅抖动不应引起底栏反复收放。
  final double threshold;

  @override
  State<TabBarMinimizeOnScroll> createState() => _TabBarMinimizeOnScrollState();
}

class _TabBarMinimizeOnScrollState extends State<TabBarMinimizeOnScroll> {
  /// 累计滚动距离，跨过 threshold 才下发状态
  double _accumulated = 0;
  bool _minimized = false;

  bool get _isApplicable {
    if (kIsWeb) return false;
    return Platform.isIOS;
  }

  @override
  void dispose() {
    // 离开页面时恢复，避免把最小化状态泄漏给下一个页面
    if (_isApplicable && _minimized) {
      NativeTabBarService.instance.setTabBarMinimized(minimized: false);
    }
    super.dispose();
  }

  void _onScroll(ScrollUpdateNotification notification) {
    final delta = notification.scrollDelta;
    if (delta == null || delta == 0) return;

    // 只响应竖直方向的主滚动区，忽略横向列表等嵌套滚动
    if (notification.metrics.axis != Axis.vertical) return;

    // 忽略不可滚动的短内容：其 pixels 恒为 0，一次弹性拖拽就会误触发
    if (notification.metrics.maxScrollExtent <= 0) return;

    // 顶部回弹区间一律视为展开，否则下拉刷新时底栏会误收
    if (notification.metrics.pixels <= 0) {
      _apply(minimized: false);
      _accumulated = 0;
      return;
    }

    // 方向反转时清零，避免旧方向的累计量拖慢响应
    if ((delta > 0) != (_accumulated > 0)) {
      _accumulated = 0;
    }
    _accumulated += delta;

    if (_accumulated > widget.threshold) {
      _apply(minimized: true);
      _accumulated = 0;
    } else if (_accumulated < -widget.threshold) {
      _apply(minimized: false);
      _accumulated = 0;
    }
  }

  void _apply({required bool minimized}) {
    if (_minimized == minimized) return;
    _minimized = minimized;
    // Service 内部还有一层去重，这里的判断只是省掉一次方法调用
    NativeTabBarService.instance.setTabBarMinimized(minimized: minimized);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isApplicable) return widget.child;

    return NotificationListener<ScrollUpdateNotification>(
      onNotification: (notification) {
        _onScroll(notification);
        // 不拦截，让外层其它监听者照常收到
        return false;
      },
      child: widget.child,
    );
  }
}
