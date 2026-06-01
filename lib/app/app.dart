import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:my_nas/app/router/app_router.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_theme.dart';
import 'package:my_nas/app/theme/color_scheme_preset.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/platform/jump_list_controller.dart';
import 'package:my_nas/core/platform/spotlight/spotlight_deep_link_handler.dart';
import 'package:my_nas/core/services/background_task_service.dart';
import 'package:my_nas/core/services/deep_link_service.dart';
import 'package:my_nas/core/services/toast_service.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/app_lock/presentation/widgets/app_lock_gate.dart';
import 'package:my_nas/features/book/data/services/book_database_service.dart';
import 'package:my_nas/features/music/data/services/music_database_service.dart';
import 'package:my_nas/features/music/presentation/providers/desktop_lyric_provider.dart';
import 'package:my_nas/features/photo/data/services/photo_database_service.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/video/data/services/video_database_service.dart';
import 'package:my_nas/features/video/data/services/video_scanner_service.dart';
import 'package:my_nas/shared/providers/theme_provider.dart';
import 'package:my_nas/shared/providers/ui_style_provider.dart';
import 'package:my_nas/shared/services/widget_data_service.dart';
import 'package:my_nas/shared/widgets/stream_image.dart';
import 'package:my_nas/l10n/app_localizations.dart';
import 'package:my_nas/shared/widgets/toast_overlay.dart';

class MyNasApp extends ConsumerStatefulWidget {
  const MyNasApp({super.key});

  @override
  ConsumerState<MyNasApp> createState() => _MyNasAppState();
}

class _MyNasAppState extends ConsumerState<MyNasApp> with WidgetsBindingObserver {
  bool _deepLinkInitialized = false;
  bool _desktopLyricInitialized = false;
  bool _jumpListInitialized = false;
  bool _spotlightHandlerInitialized = false;

  /// 全局 Toast 服务实例
  final ToastService _toastService = ToastService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 设置全局错误 Widget（只需设置一次）
    ErrorWidget.builder = (details) {
      logger.e('Flutter Error: ${details.exception}', details.exception, details.stack);
      return Material(
        child: Container(
          color: Colors.red.shade100,
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                '发生错误',
                style: TextStyle(fontSize: 20, color: Colors.red, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                details.exception.toString(),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      );
    };
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 释放 ToastService
    _toastService.dispose();
    // 释放 DeepLinkService
    if (Platform.isIOS) {
      DeepLinkService().dispose();
    }
    super.dispose();
  }

  /// 初始化 DeepLinkService（仅 iOS）
  void _initDeepLinkService() {
    if (_deepLinkInitialized || !Platform.isIOS) return;
    _deepLinkInitialized = true;

    // 添加错误处理，防止初始化失败导致应用崩溃
    try {
      DeepLinkService().init(ref);
      logger.i('MyNasApp: DeepLinkService 初始化成功');
    } on Exception catch (e, stackTrace) {
      AppError.handle(e, stackTrace, 'initDeepLinkService');
      // 不抛出异常，允许应用继续运行
    }
  }

  /// 初始化 Windows 任务栏 Jump List
  void _initJumpList() {
    if (_jumpListInitialized || !Platform.isWindows) return;
    _jumpListInitialized = true;
    AppError.guardSync(
      () => JumpListController().init(ref),
      action: 'initJumpList',
    );
  }

  /// 初始化桌面歌词服务（macOS/Windows）
  void _initDesktopLyricService() {
    if (_desktopLyricInitialized) return;
    if (!Platform.isMacOS && !Platform.isWindows) return;
    _desktopLyricInitialized = true;

    // 读取 provider 触发初始化
    // provider 内部会检查设置并自动显示桌面歌词（如果已启用）
    ref.read(desktopLyricProvider);
    logger.i('MyNasApp: DesktopLyricProvider 已初始化');
  }

  /// 初始化 Spotlight 深链 handler（仅 macOS）
  void _initSpotlightHandler() {
    if (_spotlightHandlerInitialized) return;
    if (!Platform.isMacOS) return;
    _spotlightHandlerInitialized = true;

    SpotlightDeepLinkHandler.ensureStarted(ref);
    logger.i('MyNasApp: SpotlightDeepLinkHandler 已初始化');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    logger.d('MyNasApp: AppLifecycleState changed to $state');

    switch (state) {
      case AppLifecycleState.paused:
        // 应用进入后台
        // 清理图片内存缓存以节省内存
        StreamImage.clearCache();
        logger.d('MyNasApp: 应用进入后台，已清理图片内存缓存');
        // 注意：后台任务会继续运行（通过 Foreground Service）
        _logBackgroundTaskStatus();

      case AppLifecycleState.detached:
        // 应用被销毁
        StreamImage.clearCache();
        logger.d('MyNasApp: 应用即将被销毁');
        // 停止后台服务（如果正在运行）
        // 任务状态已保存到数据库，下次启动时会自动恢复
        _stopBackgroundServiceIfNeeded();

      case AppLifecycleState.resumed:
        // 应用从后台恢复
        logger.d('MyNasApp: 应用已从后台恢复');
        // 检查后台任务状态
        _checkAndResumeBackgroundTask();

      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        // 不处理这些状态
        break;
    }
  }

  /// 记录后台任务状态
  void _logBackgroundTaskStatus() {
    final scanner = VideoScannerService();
    if (scanner.isScraping) {
      logger.i('MyNasApp: 刮削任务正在后台运行');
    }
    if (scanner.isScanning) {
      logger.i('MyNasApp: 扫描任务正在后台运行');
    }
  }

  /// 停止后台服务并安全关闭数据库
  ///
  /// 在应用被销毁时调用，确保：
  /// 1. 所有数据库写入完成（WAL checkpoint）
  /// 2. Hive 缓存刷新到磁盘
  /// 3. 后台服务正常停止
  Future<void> _stopBackgroundServiceIfNeeded() async {
    try {
      // 并行安全关闭所有 SQLite 数据库（执行 WAL checkpoint）
      await Future.wait([
        VideoDatabaseService().close(),
        MusicDatabaseService().close(),
        PhotoDatabaseService().close(),
        BookDatabaseService().close(),
      ]);

      // 关闭所有 Hive boxes
      await Hive.close();

      logger.i('MyNasApp: 所有数据库已安全关闭');
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'closeDatabases');
    }

    // 当应用被销毁时，我们选择让服务继续运行
    // 因为用户可能希望任务在后台完成
    // 如果需要强制停止，取消下面的注释：
    // await BackgroundTaskService().stopService();
  }

  /// 检查并恢复后台任务
  Future<void> _checkAndResumeBackgroundTask() async {
    // 强制广播当前刮削统计，确保 UI 同步最新进度
    // 这解决了从后台切回前台时进度不更新的问题
    await VideoScannerService().broadcastCurrentStats();

    // 刷新连接状态并尝试自动重连
    // 这解决了从后台恢复后连接可能已断开但 UI 仍显示已连接的问题
    try {
      logger.d('MyNasApp: 检查并恢复连接状态...');
      // 先刷新状态，让 UI 反映真实连接状态
      ref.read(activeConnectionsProvider.notifier).refresh();
      // 然后尝试自动重连
      await ref.read(activeConnectionsProvider.notifier).autoConnectAll();
      logger.d('MyNasApp: 连接状态已刷新');
    } on Exception catch (e) {
      logger.w('MyNasApp: 恢复连接失败: $e');
    }

    // 仅在移动平台检查后台服务状态
    if (!Platform.isAndroid && !Platform.isIOS) return;

    final backgroundService = BackgroundTaskService();
    final isRunning = await backgroundService.checkServiceRunning();

    if (isRunning) {
      logger.i('MyNasApp: 后台服务仍在运行');
    } else {
      // 服务已停止，检查是否有未完成的任务需要恢复
      // 这会在 VideoListNotifier 中自动处理
      logger.d('MyNasApp: 后台服务未运行，等待自动恢复检查');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 初始化 DeepLinkService（在 build 中调用以确保 ref 可用）
    _initDeepLinkService();

    // 初始化桌面歌词服务（macOS/Windows）
    _initDesktopLyricService();

    // 初始化 Spotlight 深链 handler（仅 macOS）
    _initSpotlightHandler();

    // 初始化 Windows JumpList（任务栏图标右键的快捷操作 / 最近播放）
    _initJumpList();

    final themeMode = ref.watch(themeModeProvider);
    final colorPreset = ref.watch(colorSchemePresetProvider);
    final uiStyle = ref.watch(uiStyleProvider);

    // 同步更新 AppColors 的静态配色方案
    AppColors.setPreset(colorPreset);

    // 监听配色方案变化，同步更新原生 Widget 主题
    ref.listen<ColorSchemePreset>(colorSchemePresetProvider, (previous, next) {
      if (previous != next) {
        WidgetDataService().updateThemeWidget();
      }
    });

    // 桌面端重设计：注入 DesignTokens 到 ThemeData.extensions，所有新外壳
    // 和 atom widget 通过 `DesignTokens.of(context)` 取色，避免每个 widget
    // 都订阅 uiStyle / colorPreset / themeMode 三个 provider。
    final lightTokens = DesignTokens.build(
      brightness: Brightness.light,
      uiStyle: uiStyle,
      preset: colorPreset,
    );
    final darkTokens = DesignTokens.build(
      brightness: Brightness.dark,
      uiStyle: uiStyle,
      preset: colorPreset,
    );

    return MaterialApp.router(
      title: 'MyNAS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightFromPreset(colorPreset)
          .copyWith(extensions: [lightTokens]),
      darkTheme: AppTheme.darkFromPreset(colorPreset)
          .copyWith(extensions: [darkTokens]),
      themeMode: themeMode,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: appRouter,
      // 包装 ToastServiceProvider、ToastOverlay 和 AppLockGate
      builder: (context, child) => ToastServiceProvider(
        service: _toastService,
        child: ToastOverlay(
          toastService: _toastService,
          child: AppLockLifecycleListener(
            child: AppLockGate(
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }
}
