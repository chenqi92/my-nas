import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:my_nas/core/utils/hive_utils.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:window_manager/window_manager.dart';

/// 桌面窗口管理服务
///
/// 负责：
/// - 设置最小窗口尺寸（1024x720），避免窗口缩到不可用
/// - 启动时恢复上次的窗口大小 / 位置
/// - macOS 标题栏隐藏（title bar inset 由原生侧 macos/Runner/MainFlutterWindow 处理）
/// - 退出 / 失焦时持久化窗口几何数据
///
/// 仅作用于桌面平台（macOS / Windows / Linux）。移动端 / Web 调用即 no-op。
class DesktopWindowService with WindowListener {
  DesktopWindowService._();

  static final DesktopWindowService instance = DesktopWindowService._();

  static const _hiveKeyWidth = 'desktop_window_width';
  static const _hiveKeyHeight = 'desktop_window_height';
  static const _hiveKeyOffsetX = 'desktop_window_offset_x';
  static const _hiveKeyOffsetY = 'desktop_window_offset_y';
  static const _hiveKeyMaximized = 'desktop_window_maximized';

  static const Size _defaultSize = Size(1280, 800);
  static const Size _minSize = Size(1024, 720);

  bool _initialized = false;

  /// 在 runApp 之前调用。仅桌面平台执行实际初始化。
  ///
  /// 整个流程包在 try-catch：任何步骤失败（windowManager 通信、Hive box
  /// 被另一个进程锁定等）都不应阻塞 runApp，否则用户看到黑屏。失败时
  /// 退化为窗口默认尺寸，不持久化几何。
  Future<void> initialize() async {
    if (_initialized) return;
    if (kIsWeb) return;
    if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) return;

    try {
      await windowManager.ensureInitialized();

      // 读取上次窗口几何（Hive box 失败也不影响窗口显示）。
      double? savedWidth;
      double? savedHeight;
      double? savedOffsetX;
      double? savedOffsetY;
      var wasMaximized = false;
      try {
        final box = await HiveUtils.getSettingsBox();
        savedWidth = (box.get(_hiveKeyWidth) as num?)?.toDouble();
        savedHeight = (box.get(_hiveKeyHeight) as num?)?.toDouble();
        savedOffsetX = (box.get(_hiveKeyOffsetX) as num?)?.toDouble();
        savedOffsetY = (box.get(_hiveKeyOffsetY) as num?)?.toDouble();
        wasMaximized = box.get(_hiveKeyMaximized) as bool? ?? false;
      } on Exception catch (e, st) {
        logger.w('DesktopWindowService: 读取窗口偏好失败，使用默认尺寸', e, st);
      }

      final initialSize = (savedWidth != null && savedHeight != null)
          ? Size(savedWidth, savedHeight)
          : _defaultSize;

      final options = WindowOptions(
        size: initialSize,
        minimumSize: _minSize,
        center: savedOffsetX == null,
        // 保留 macOS 默认标题栏（灰条 + 交通灯）。之前试过 TitleBarStyle.hidden
        // 让内容延伸到顶端，但各 page 的 AppBar 会直接顶到屏幕最上方，跟红黄绿
        // 按钮挤在一起。沉浸式标题栏需要每个 page 配合 inset，工程量大，先保守。
        titleBarStyle: TitleBarStyle.normal,
        title: 'MyNAS',
      );

      await windowManager.waitUntilReadyToShow(options, () async {
        if (savedOffsetX != null && savedOffsetY != null) {
          await windowManager.setPosition(Offset(savedOffsetX, savedOffsetY));
        }
        await windowManager.show();
        await windowManager.focus();
        if (wasMaximized) {
          await windowManager.maximize();
        }
      });

      windowManager.addListener(this);
      _initialized = true;
      logger.i('DesktopWindowService initialized '
          '(size=$initialSize, maximized=$wasMaximized)');
    } on Exception catch (e, st) {
      logger.w('DesktopWindowService 初始化失败，应用继续启动', e, st);
    }
  }

  /// 持久化当前窗口几何数据。
  Future<void> _persist() async {
    if (!_initialized) return;
    try {
      final box = await HiveUtils.getSettingsBox();
      final isMaximized = await windowManager.isMaximized();
      await box.put(_hiveKeyMaximized, isMaximized);

      // 仅在非最大化状态下保存尺寸 / 位置，避免最大化几何覆盖用户偏好。
      if (!isMaximized) {
        final size = await windowManager.getSize();
        final pos = await windowManager.getPosition();
        await box.put(_hiveKeyWidth, size.width);
        await box.put(_hiveKeyHeight, size.height);
        await box.put(_hiveKeyOffsetX, pos.dx);
        await box.put(_hiveKeyOffsetY, pos.dy);
      }
    } on Exception catch (e, st) {
      logger.w('DesktopWindowService persist failed', e, st);
    }
  }

  @override
  void onWindowResized() {
    unawaited(_persist());
  }

  @override
  void onWindowMoved() {
    unawaited(_persist());
  }

  @override
  void onWindowMaximize() {
    unawaited(_persist());
  }

  @override
  void onWindowUnmaximize() {
    unawaited(_persist());
  }

  @override
  void onWindowClose() {
    unawaited(_persist());
  }
}
