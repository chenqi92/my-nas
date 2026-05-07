import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:media_kit/media_kit.dart';
import 'package:my_nas/app/app.dart';
import 'package:my_nas/core/di/injection.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/services/desktop_window_service.dart';
import 'package:my_nas/core/services/performance_mode_service.dart';
import 'package:my_nas/core/sync/app_settings_sync_module.dart';
import 'package:my_nas/core/sync/syncable_module.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/book/data/services/sources/book_source_manager_service.dart';
import 'package:my_nas/features/book/data/services/sync/book_sources_sync_module.dart';
import 'package:my_nas/features/music/data/services/music_audio_handler.dart';
import 'package:my_nas/features/music/data/services/music_audio_handler_interface.dart';
import 'package:my_nas/features/music/data/services/music_media_kit_handler.dart';
import 'package:my_nas/features/music/data/services/sync/favorites_sync_module.dart';
import 'package:my_nas/features/music/data/services/sync/music_settings_sync_module.dart';
import 'package:my_nas/features/music/data/services/sync/playlist_sync_module.dart';
import 'package:my_nas/features/music/presentation/pages/desktop_lyric_window.dart';
import 'package:my_nas/features/reading/data/services/sync/reading_progress_sync_module.dart';
import 'package:my_nas/features/video/data/services/audio_track_service.dart';
import 'package:my_nas/features/video/data/services/subtitle_service.dart';
import 'package:my_nas/features/video/data/services/sync/video_favorites_sync_module.dart';
import 'package:my_nas/features/video/data/services/tmdb_service.dart';
import 'package:my_nas/shared/providers/language_preference_provider.dart';
import 'package:my_nas/shared/services/native_tab_bar_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 全局 AudioHandler 实例
/// 用于音乐后台播放和系统媒体控制（锁屏、控制中心、蓝牙耳机等）
///
/// 支持两种引擎：
/// - [MusicAudioHandler] - 基于 just_audio（平台原生解码器）
/// - [MusicMediaKitAudioHandler] - 基于 media_kit（FFmpeg 解码器，支持 AC3/DTS 等）
late IMusicAudioHandler audioHandler;

Future<void> main(List<String> args) async {
  // 检查是否是桌面歌词子窗口（macOS 和 Windows 都使用 desktop_multi_window）
  if (args.isNotEmpty && args.first == 'multi_window') {
    // 子窗口入口：args[1] = windowId, args[2] = arguments
    await desktopLyricMain(args.sublist(1));
    return;
  }

  // 主窗口入口
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  // 初始化前台服务通信端口（必须在 runApp 之前调用）
  // 这允许后台任务与主 UI 进行通信
  // 注意：仅 Android 支持 Foreground Service，iOS 不支持此机制
  if (Platform.isAndroid) {
    FlutterForegroundTask.initCommunicationPort();
  }

  // 保持 native splash 直到手动移除
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // 设置全局错误处理
  _setupGlobalErrorHandling();

  // Initialize dependencies。任何子步骤抛异常都不应阻塞 runApp，否则用户
  // 看到的是黑屏而非错误界面。每个步骤内部已经各自 try-catch，这里再加
  // 一层 fallback 兜底。
  try {
    await _initApp();
  } on Object catch (e, st) {
    logger.f('App initialization failed, continuing to runApp', e, st);
  }

  runApp(
    const ProviderScope(
      child: MyNasApp(),
    ),
  );

  // 等待首帧渲染完成后再移除 native splash
  // 这样可以避免用户在 UI 未完全布局时触摸屏幕导致的 "Cannot hit test" 错误
  WidgetsBinding.instance.addPostFrameCallback((_) {
    FlutterNativeSplash.remove();
  });
}

/// 设置全局错误处理
void _setupGlobalErrorHandling() {
  // 捕获 Flutter 框架错误
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    _reportFlutterError(details);
  };

  // 捕获异步错误和平台错误
  PlatformDispatcher.instance.onError = (error, stack) {
    _reportPlatformError(error, stack);
    return true;
  };
}

/// 记录 Flutter 框架错误（仅本地日志）
void _reportFlutterError(FlutterErrorDetails details) {
  logger.f(
    '[FlutterFrameworkError] ${details.exceptionAsString()} '
    '(library=${details.library})',
    details.exception,
    details.stack,
  );
}

/// 记录平台异步错误（仅本地日志）
void _reportPlatformError(Object error, StackTrace stack) {
  // ignore: no_runtimeType_toString
  final errorType = error.runtimeType.toString();
  logger.f('[PlatformDispatcherError] $errorType: $error', error, stack);
}

Future<void> _initApp() async {
  // 初始化文件日志（会清空之前的日志）
  await logger.initFileLogging();

  logger.i('Initializing MyNAS...');

  // Initialize Hive for local storage
  await Hive.initFlutter();

  // 初始化桌面窗口管理（仅 macOS / Windows / Linux）
  // 必须在显示任何 UI 之前完成，以正确恢复用户上次的窗口尺寸 / 位置。
  await DesktopWindowService.instance.initialize();

  // 初始化原生 Tab Bar 服务（iOS）
  // 必须在 UI 启动前初始化，以便接收原生 Tab 事件
  if (!kIsWeb && Platform.isIOS) {
    NativeTabBarService.instance.initialize();
    logger.i('NativeTabBarService initialized');
  }

  // Initialize sqflite_common_ffi for desktop platforms (Windows, macOS, Linux)
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    logger.i('SQLite FFI initialized for desktop platform');
  }

  // Initialize MediaKit for video playback
  MediaKit.ensureInitialized();

  // Initialize JustAudioMediaKit to use MediaKit as audio backend
  // This fixes the just_audio_windows threading issue on Windows
  JustAudioMediaKit.ensureInitialized();

  // 初始化性能模式服务（需要 SharedPreferences，会打开 settings box）
  await PerformanceModeService().init();
  logger.i('PerformanceMode: ${PerformanceModeService.isPerformanceMode ? "enabled" : "disabled"}');

  // 初始化书源管理服务（非阻塞，在后台加载）
  AppError.fireAndForget(
    BookSourceManagerService.instance.init(),
    action: 'BookSourceManagerService.init',
  );

  // Initialize AudioSession for proper audio playback on iOS/Android
  // This is critical for just_audio to work correctly
  await _initAudioSession();

  // 初始化 AudioHandler 用于后台音频播放和系统媒体控制
  // 这会自动处理：
  // - iOS 锁屏和控制中心媒体控制
  // - Android 通知栏媒体控制
  // - 蓝牙耳机/AirPods 按钮控制
  // - 后台音频稳定播放
  audioHandler = await _initAudioHandler();

  // Configure dependency injection
  await configureDependencies();

  // Load TMDB API key from settings
  await _loadTmdbApiKey();

  // 注册第三方开源库许可证
  _registerThirdPartyLicenses();

  // 注册可同步模块到 CloudSyncRegistry
  _registerSyncModules();

  logger.i('MyNAS initialized successfully');
}

/// 把所有支持云同步的模块注册到中心同步系统
void _registerSyncModules() {
  CloudSyncRegistry.instance
    ..register(PlaylistSyncModule())
    ..register(FavoritesSyncModule())
    ..register(VideoFavoritesSyncModule())
    ..register(ReadingProgressSyncModule())
    ..register(BookSourcesSyncModule())
    ..register(MusicSettingsSyncModule())
    ..register(AppSettingsSyncModule());
}

/// 注册第三方开源库的许可证
void _registerThirdPartyLicenses() {
  // FFmpeg - GPL v3 许可证
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      ['FFmpeg'],
      '''FFmpeg - A complete, cross-platform solution to record, convert and stream audio and video.

Copyright (c) 2000-2025 the FFmpeg developers

This software is licensed under the GNU General Public License version 3 (GPL v3).

You can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

Source Code: https://github.com/FFmpeg/FFmpeg
Website: https://ffmpeg.org
License: https://www.gnu.org/licenses/gpl-3.0.html

This application uses FFmpeg for video transcoding functionality. FFmpeg is called as an external process and is not linked into the application code.''',
    );
  });
}

Future<void> _loadTmdbApiKey() async {
  try {
    // Hive 已经在 PerformanceModeService 中打开了 'settings' box（Box<dynamic>）
    // 直接获取已打开的 box，而不是尝试以不同类型重新打开
    final box = Hive.box<dynamic>('settings');
    final tmdbService = TmdbService();

    // 加载 TMDB API Key
    final apiKey = box.get('tmdb_api_key') as String?;
    if (apiKey != null && apiKey.isNotEmpty) {
      tmdbService.setApiKey(apiKey);
      logger.i('TMDB API key loaded');
    }

    // 加载 TMDB API URL（自定义代理）
    final apiUrl = box.get('tmdb_api_url') as String?;
    if (apiUrl != null && apiUrl.isNotEmpty) {
      tmdbService.setApiUrl(apiUrl);
      logger.i('TMDB API URL loaded: $apiUrl');
    }

    // 加载 TMDB 图片 URL（自定义代理）
    final imageUrl = box.get('tmdb_image_url') as String?;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      tmdbService.setImageUrl(imageUrl);
      logger.i('TMDB image URL loaded: $imageUrl');
    }

    // 加载语言偏好设置并传递给相关服务
    final langPrefJson = box.get('language_preference') as String?;
    if (langPrefJson != null && langPrefJson.isNotEmpty) {
      final preference = _parseLanguagePreference(langPrefJson);
      if (preference != null) {
        tmdbService.setLanguagePreference(preference);
        SubtitleService().setLanguagePreference(preference);
        AudioTrackService().setLanguagePreference(preference);
        logger.i('语言偏好已加载: 元数据=${preference.metadataLanguages.first.code}, '
            '字幕=${preference.subtitleLanguages.first.code}, '
            '音轨=${preference.audioLanguages.first.code}');
      }
    }

    // 设置系统语言环境
    tmdbService.setSystemLocale(
      WidgetsBinding.instance.platformDispatcher.locale,
    );
  } on Exception catch (e, st) {
    AppError.ignore(e, st, '加载 TMDB 设置失败（可选功能）');
  }
}

/// 解析语言偏好 JSON 字符串
LanguagePreference? _parseLanguagePreference(String jsonStr) {
  try {
    final result = jsonDecode(jsonStr) as Map<String, dynamic>;
    return result.isNotEmpty ? LanguagePreference.fromJson(result) : null;
  } on Exception catch (_) {
    return null;
  }
}

/// 初始化音频处理器
/// 根据用户设置选择 just_audio 或 media_kit 引擎
Future<IMusicAudioHandler> _initAudioHandler() async {
  try {
    // 尝试读取音乐设置中的播放引擎配置
    final box = await Hive.openBox<Map<dynamic, dynamic>>('music_settings');
    final data = box.get('settings');
    final engineIndex = data?['playerEngine'] as int? ?? 0;
    final useMediaKit = engineIndex == MusicPlayerEngine.mediaKit.index;

    if (useMediaKit) {
      logger.i('初始化音频处理器: media_kit 引擎 (支持 AC3/DTS/Dolby)');
      return initMediaKitAudioHandler();
    } else {
      logger.i('初始化音频处理器: just_audio 引擎 (平台原生解码器)');
      return initAudioHandler();
    }
  } on Exception catch (e, st) {
    // 如果读取设置失败，使用默认的 just_audio 引擎
    AppError.ignore(e, st, '读取音乐播放引擎设置失败，使用默认引擎');
    logger.i('初始化音频处理器: just_audio 引擎 (默认)');
    return initAudioHandler();
  }
}

/// 初始化音频会话
/// 这是 just_audio 在 iOS/Android 上正常播放音频的关键配置
Future<void> _initAudioSession() async {
  try {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration(
      // 音频类型：音乐（适合音乐播放器）
      avAudioSessionCategory: AVAudioSessionCategory.playback,
      avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.none,
      avAudioSessionMode: AVAudioSessionMode.defaultMode,
      avAudioSessionRouteSharingPolicy:
          AVAudioSessionRouteSharingPolicy.defaultPolicy,
      avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
      // Android 音频属性
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.music,
        usage: AndroidAudioUsage.media,
      ),
      androidWillPauseWhenDucked: true,
    ));
    logger.i('AudioSession initialized for music playback');
  } on Exception catch (e, st) {
    AppError.ignore(e, st, '初始化 AudioSession 失败（可选功能）');
  }
}
