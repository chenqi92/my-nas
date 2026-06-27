import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// 系统托盘菜单文案（由调用方从本地化取好后传入，避免 core 层依赖 l10n）。
class TrayLabels {
  const TrayLabels({
    required this.show,
    required this.playPause,
    required this.previous,
    required this.next,
    required this.exit,
    required this.tooltip,
  });

  final String show;
  final String playPause;
  final String previous;
  final String next;
  final String exit;
  final String tooltip;
}

/// 系统托盘 + 最小化到托盘（Windows / Linux / macOS）。
///
/// - 托盘图标 + 右键菜单：显示窗口 / 播放暂停 / 上一首 / 下一首 / 退出。
/// - 关闭窗口时隐藏到托盘而非退出（仅当托盘初始化成功才 setPreventClose，
///   否则保持系统默认关闭行为，避免托盘不可用时用户无法关闭窗口）。
/// - 移动端 / Web 调用 [ensureStarted] 直接 no-op。
///
/// 播放控制通过回调注入（由桌面外壳绑定到 musicPlayerController），
/// core 层不直接依赖 Riverpod / music feature。
class TrayService with TrayListener, WindowListener {
  TrayService._();

  static final TrayService instance = TrayService._();

  static const _kShow = 'tray.show';
  static const _kPlayPause = 'tray.playPause';
  static const _kPrevious = 'tray.previous';
  static const _kNext = 'tray.next';
  static const _kExit = 'tray.exit';

  /// Windows 用 .ico 渲染最佳；这里复用应用 logo（png），若 Windows 托盘图标
  /// 不显示，可在 assets 放一个 .ico 并改这里的路径。
  static const _defaultIconPath = 'assets/logo.png';

  /// macOS 菜单栏会把图标压到很小，直接缩应用大图会显得方硬。
  /// 使用带透明外边距与圆角底板的专用小图，选中高亮时更贴近系统风格。
  static const _macosIconPath = 'assets/icons/tray_macos.png';

  bool _started = false;
  bool _exiting = false;

  VoidCallback? _onPlayPause;
  VoidCallback? _onPrevious;
  VoidCallback? _onNext;

  static bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  /// 幂等初始化。首次调用建立托盘图标 + 菜单 + 窗口监听；后续调用仅刷新
  /// 播放控制回调（外壳每帧 build 调用是安全的）。
  Future<void> ensureStarted(
    TrayLabels labels, {
    required VoidCallback onPlayPause,
    required VoidCallback onPrevious,
    required VoidCallback onNext,
  }) async {
    _onPlayPause = onPlayPause;
    _onPrevious = onPrevious;
    _onNext = onNext;

    if (_started) return;
    if (!_isDesktop) return;
    _started = true;

    try {
      await trayManager.setIcon(_iconPath);
      await trayManager.setToolTip(labels.tooltip);
      await _setMenu(labels);
      trayManager.addListener(this);
      windowManager.addListener(this);
      // 仅在托盘就绪后才拦截关闭，确保托盘不可用时窗口仍可正常关闭。
      await windowManager.setPreventClose(true);
      logger.i('TrayService 初始化完成');
    } on Object catch (e, st) {
      // 托盘不可用（如部分 Linux 无 StatusNotifier）：退化为无托盘，保持默认
      // 关闭行为，不阻塞应用。
      _started = false;
      AppError.handle(e, st, 'trayInit');
    }
  }

  String get _iconPath => Platform.isMacOS ? _macosIconPath : _defaultIconPath;

  Future<void> _setMenu(TrayLabels labels) async {
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: _kShow, label: labels.show),
          MenuItem.separator(),
          MenuItem(key: _kPlayPause, label: labels.playPause),
          MenuItem(key: _kPrevious, label: labels.previous),
          MenuItem(key: _kNext, label: labels.next),
          MenuItem.separator(),
          MenuItem(key: _kExit, label: labels.exit),
        ],
      ),
    );
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _exit() async {
    _exiting = true;
    // 解除拦截后销毁窗口，真正退出进程。
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  // ---- TrayListener ----

  @override
  void onTrayIconMouseDown() {
    // Windows/Linux 左键点击托盘图标 → 还原窗口；macOS 习惯弹菜单。
    if (!kIsWeb && Platform.isMacOS) {
      AppError.fireAndForget(
        trayManager.popUpContextMenu(),
        action: 'trayPopupMenu',
      );
    } else {
      AppError.fireAndForget(_showWindow(), action: 'trayShowWindow');
    }
  }

  @override
  void onTrayIconRightMouseDown() {
    AppError.fireAndForget(
      trayManager.popUpContextMenu(),
      action: 'trayPopupMenu',
    );
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case _kShow:
        AppError.fireAndForget(_showWindow(), action: 'trayShowWindow');
      case _kPlayPause:
        _onPlayPause?.call();
      case _kPrevious:
        _onPrevious?.call();
      case _kNext:
        _onNext?.call();
      case _kExit:
        AppError.fireAndForget(_exit(), action: 'trayExit');
    }
  }

  // ---- WindowListener ----

  @override
  void onWindowClose() {
    if (_exiting) return;
    // 关闭按钮 → 隐藏到托盘而非退出（preventClose 已开启时窗口不会真正关闭）。
    AppError.fireAndForget(windowManager.hide(), action: 'trayHideOnClose');
  }
}
