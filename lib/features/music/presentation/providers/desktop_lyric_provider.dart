import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/features/music/data/services/desktop_lyric_service.dart';
import 'package:my_nas/features/music/data/services/desktop_lyric_service_macos.dart';
import 'package:my_nas/features/music/data/services/desktop_lyric_service_windows.dart';
import 'package:my_nas/features/music/domain/entities/desktop_lyric_settings.dart';
import 'package:my_nas/features/music/presentation/providers/lyric_provider.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';
import 'package:my_nas/shared/providers/theme_provider.dart';
import 'package:window_manager/window_manager.dart';

/// 桌面歌词状态
class DesktopLyricState {
  const DesktopLyricState({
    this.settings = const DesktopLyricSettings(),
    this.isVisible = false,
    this.isInitialized = false,
  });

  final DesktopLyricSettings settings;
  final bool isVisible;
  final bool isInitialized;

  DesktopLyricState copyWith({
    DesktopLyricSettings? settings,
    bool? isVisible,
    bool? isInitialized,
  }) => DesktopLyricState(
      settings: settings ?? this.settings,
      isVisible: isVisible ?? this.isVisible,
      isInitialized: isInitialized ?? this.isInitialized,
    );
}

/// 桌面歌词 Provider
final desktopLyricProvider =
    StateNotifierProvider<DesktopLyricNotifier, DesktopLyricState>(DesktopLyricNotifier.new);

/// 桌面歌词状态管理器
class DesktopLyricNotifier extends StateNotifier<DesktopLyricState>
    with WindowListener {
  DesktopLyricNotifier(this._ref) : super(const DesktopLyricState()) {
    _init();
  }

  final Ref _ref;
  DesktopLyricService? _service;
  Timer? _syncTimer;
  Timer? _positionSaveTimer; // 位置保存防抖定时器
  HotKey? _toggleHotKey;

  /// 是否因最小化而显示桌面歌词（用于恢复时判断是否需要隐藏）
  bool _shownByMinimize = false;

  /// 是否从桌面歌词控制按钮触发的暂停（此时不应隐藏歌词窗口）
  bool _pausedFromDesktopLyric = false;

  /// 是否支持桌面歌词
  bool get isSupported => Platform.isWindows || Platform.isMacOS;

  Future<void> _init() async {
    if (!isSupported) return;

    await AppError.guard(
      () async {
        // 加载保存的设置
        final settings = await _loadSettings();
        if (!mounted) return;

        // 获取平台服务
        // Windows: 使用多窗口实现（更稳定）
        // macOS: 使用原生 Method Channel 实现
        if (Platform.isWindows) {
          _service = DesktopLyricServiceWindowsImpl.instance;
        } else if (Platform.isMacOS) {
          _service = DesktopLyricServiceMacOSImpl.instance;
        }

        if (_service != null) {
          await _service!.init(settings);
          if (!mounted) {
            await _service!.dispose();
            _service = null;
            return;
          }

          // 设置回调
          if (_service is DesktopLyricServiceMacOSImpl) {
            (_service! as DesktopLyricServiceMacOSImpl)
              ..onPositionChanged = _onPositionChanged
              ..onControlAction = _onControlAction;
          } else if (_service is DesktopLyricServiceWindowsImpl) {
            (_service! as DesktopLyricServiceWindowsImpl).onPositionChanged =
                _onPositionChanged;
          }

          state = state.copyWith(
            settings: settings,
            isInitialized: true,
          );

          // 如果设置了启用，且当前正在播放音乐，则自动显示
          if (settings.enabled) {
            final playerState = _ref.read(musicPlayerControllerProvider);
            if (playerState.isPlaying) {
              await _service!.show();
              if (!mounted) return;
              state = state.copyWith(isVisible: true);
            }
          }

          // 注册全局快捷键
          await _registerHotKey();
          if (!mounted) return;

          // 注册主窗口状态监听（用于最小化时显示桌面歌词）
          windowManager.addListener(this);

          // 开始监听歌词和播放状态
          _startListening();

          // 监听配色方案变化，更新高亮颜色
          _ref.listen(colorSchemePresetProvider, (previous, next) {
            _updateHighlightColor();
          });
        }
      },
      action: 'initDesktopLyric',
    );
  }

  /// 主窗口最小化时触发
  @override
  void onWindowMinimize() {
    if (!state.settings.showOnMinimize) return;
    if (state.isVisible) return; // 已经显示，不需要再处理

    // 检查是否有正在播放的音乐
    final playerState = _ref.read(musicPlayerControllerProvider);
    if (!playerState.isPlaying) return; // 没有播放音乐时不显示

    _showByMinimize();
  }

  /// 主窗口恢复时触发
  @override
  void onWindowRestore() {
    if (!state.settings.showOnMinimize) return;
    if (!_shownByMinimize) return; // 不是因最小化显示的，不需要隐藏

    if (state.settings.hideOnRestore) {
      _hideByRestore();
    }
  }

  /// 因最小化而显示桌面歌词（不修改 enabled 设置）
  Future<void> _showByMinimize() async {
    if (_service == null) return;

    await AppError.guard(
      () async {
        await _service!.show();
        state = state.copyWith(isVisible: true);
        _shownByMinimize = true;
      },
      action: 'showDesktopLyricByMinimize',
    );
  }

  /// 因恢复窗口而隐藏桌面歌词（不修改 enabled 设置）
  Future<void> _hideByRestore() async {
    if (_service == null) return;

    await AppError.guard(
      () async {
        await _service!.hide();
        state = state.copyWith(isVisible: false);
        _shownByMinimize = false;
      },
      action: 'hideDesktopLyricByRestore',
    );
  }

  void _startListening() {
    _ref
      // 监听歌词变化
      ..listen<LyricState>(currentLyricProvider, (previous, next) {
        _syncLyric();
      })
      // 监听播放状态变化
      ..listen<MusicPlayerState>(musicPlayerControllerProvider,
          (previous, next) {
        // 播放状态变化时处理自动显示/隐藏
        if (previous?.isPlaying != next.isPlaying) {
          _syncPlayingState(next.isPlaying);
          _handlePlayingStateChange(next.isPlaying);
        }
        // 定期同步歌词
        _syncLyric();
      });

    // 启动同步定时器（50ms 间隔以获得流畅的卡拉OK效果）
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      _syncLyric();
    });
  }

  /// 处理播放状态变化，自动显示/隐藏桌面歌词
  void _handlePlayingStateChange(bool isPlaying) {
    if (_service == null) return;

    // 情况1：用户启用了桌面歌词功能 (enabled=true)
    // 播放时显示，停止时隐藏（但从桌面歌词暂停时不隐藏）
    if (state.settings.enabled) {
      if (isPlaying && !state.isVisible) {
        _showByPlaying();
      } else if (!isPlaying && state.isVisible) {
        // 如果是从桌面歌词控制暂停的，不隐藏
        if (_pausedFromDesktopLyric) {
          return;
        }
        _hideByPlaying();
      }
      return;
    }

    // 情况2：用户未启用桌面歌词，但开启了"播放时自动显示"选项
    if (state.settings.showWhenPlaying) {
      if (isPlaying && !state.isVisible) {
        _showByPlaying();
      } else if (!isPlaying && state.isVisible && _shownByMinimize) {
        // 如果是从桌面歌词控制暂停的，不隐藏
        if (_pausedFromDesktopLyric) {
          return;
        }
        // 停止播放时隐藏（仅当是自动显示的情况）
        _hideByPlaying();
      }
    }
  }

  /// 因播放而显示桌面歌词
  Future<void> _showByPlaying() async {
    if (_service == null) return;

    await AppError.guard(
      () async {
        await _service!.show();
        state = state.copyWith(isVisible: true);
        _shownByMinimize = true; // 复用此标记表示自动显示
      },
      action: 'showDesktopLyricByPlaying',
    );
  }

  /// 因停止播放而隐藏桌面歌词
  Future<void> _hideByPlaying() async {
    if (_service == null) return;

    await AppError.guard(
      () async {
        await _service!.hide();
        state = state.copyWith(isVisible: false);
        _shownByMinimize = false;
      },
      action: 'hideDesktopLyricByPlaying',
    );
  }

  void _syncLyric() {
    if (!state.isVisible || _service == null) return;

    final lyricState = _ref.read(currentLyricProvider);
    final playerState = _ref.read(musicPlayerControllerProvider);

    if (lyricState.lyricData.isEmpty) {
      _service!.updateLyric(
        currentLine: null,
        nextLine: null,
        isPlaying: playerState.isPlaying,
        progress: 0.0,
      );
      return;
    }

    final currentIndex =
        lyricState.lyricData.getCurrentLineIndex(playerState.position);

    if (currentIndex < 0) {
      _service!.updateLyric(
        currentLine: null,
        nextLine: null,
        isPlaying: playerState.isPlaying,
        progress: 0.0,
      );
      return;
    }

    final lines = lyricState.lyricData.lines;
    final currentLyricLine = lines[currentIndex];

    // 计算当前行的进度（用于卡拉OK效果）
    var progress = 0.0;
    if (playerState.isPlaying) {
      final currentTimeMs = playerState.position.inMilliseconds;
      final lineStartMs = currentLyricLine.time.inMilliseconds;

      // 计算当前行结束时间（下一行开始时间）
      int lineEndMs;
      if (currentIndex + 1 < lines.length) {
        lineEndMs = lines[currentIndex + 1].time.inMilliseconds;
      } else {
        // 最后一行，假设持续 5 秒
        lineEndMs = lineStartMs + 5000;
      }

      final lineDuration = lineEndMs - lineStartMs;
      if (lineDuration > 0) {
        progress = ((currentTimeMs - lineStartMs) / lineDuration).clamp(0.0, 1.0);
      }
    }

    // 检测翻译歌词（同一时间戳的下一行）
    String? translation;
    LyricLineData? nextLine;

    if (currentIndex + 1 < lines.length) {
      final nextLyricLine = lines[currentIndex + 1];
      // 如果时间相同，认为是翻译
      if (nextLyricLine.time == currentLyricLine.time) {
        translation = nextLyricLine.text;
        // 下一行变成 +2
        if (currentIndex + 2 < lines.length) {
          final actualNextLine = lines[currentIndex + 2];
          nextLine = LyricLineData(
            text: actualNextLine.text,
            startTime: actualNextLine.time,
          );
        }
      } else {
        nextLine = LyricLineData(
          text: nextLyricLine.text,
          startTime: nextLyricLine.time,
        );
      }
    }

    final currentLine = LyricLineData(
      text: currentLyricLine.text,
      translation: translation,
      startTime: currentLyricLine.time,
    );

    _service!.updateLyric(
      currentLine: currentLine,
      nextLine: nextLine,
      isPlaying: playerState.isPlaying,
      progress: progress,
    );
  }

  void _syncPlayingState(bool isPlaying) {
    if (!state.isVisible || _service == null) return;
    _service!.updatePlayingState(isPlaying);
  }

  void _onPositionChanged(double x, double y) {
    final newSettings = state.settings.copyWith(
      windowX: x,
      windowY: y,
    );
    state = state.copyWith(settings: newSettings);

    // 防抖：500ms 内只保存最后一次位置
    _positionSaveTimer?.cancel();
    _positionSaveTimer = Timer(const Duration(milliseconds: 500), () {
      _saveSettings(newSettings);
    });
  }

  /// 处理桌面歌词控制动作
  void _onControlAction(String action) {
    final playerNotifier = _ref.read(musicPlayerControllerProvider.notifier);
    switch (action) {
      case 'play':
        // 从桌面歌词恢复播放，清除标记
        _pausedFromDesktopLyric = false;
        playerNotifier.playOrPause();
      case 'pause':
        // 从桌面歌词暂停，设置标记防止隐藏歌词窗口
        _pausedFromDesktopLyric = true;
        playerNotifier.playOrPause();
      case 'previous':
        playerNotifier.playPrevious();
      case 'next':
        playerNotifier.playNext();
    }
  }

  /// 更新高亮颜色为当前主题色
  Future<void> _updateHighlightColor() async {
    if (!state.isInitialized) return;

    final newSettings = state.settings.copyWith(
      highlightColor: AppColors.primary,
    );
    state = state.copyWith(settings: newSettings);

    if (_service != null && state.isVisible) {
      await _service!.updateSettings(newSettings);
    }
  }

  /// 显示桌面歌词
  Future<void> show() async {
    if (_service == null) return;

    await AppError.guard(
      () async {
        await _service!.show();
        state = state.copyWith(isVisible: true);
        _shownByMinimize = false; // 手动显示，重置标记

        final newSettings = state.settings.copyWith(enabled: true);
        state = state.copyWith(settings: newSettings);
        await _saveSettings(newSettings);
      },
      action: 'showDesktopLyric',
    );
  }

  /// 隐藏桌面歌词
  Future<void> hide() async {
    if (_service == null) return;

    await AppError.guard(
      () async {
        await _service!.hide();
        state = state.copyWith(isVisible: false);
        _shownByMinimize = false; // 手动隐藏，重置标记
        _pausedFromDesktopLyric = false; // 清除暂停标记

        final newSettings = state.settings.copyWith(enabled: false);
        state = state.copyWith(settings: newSettings);
        await _saveSettings(newSettings);
      },
      action: 'hideDesktopLyric',
    );
  }

  /// 切换显示状态
  Future<void> toggle() async {
    if (state.isVisible) {
      await hide();
    } else {
      await show();
    }
  }

  /// 更新设置
  Future<void> updateSettings(DesktopLyricSettings settings) async {
    state = state.copyWith(settings: settings);
    await _saveSettings(settings);

    if (_service != null && state.isVisible) {
      await _service!.updateSettings(settings);
    }
  }

  Future<void> _registerHotKey() async {
    if (!isSupported) return;

    await AppError.guard(
      () async {
        // 先注销之前的快捷键（如果有）
        if (_toggleHotKey != null) {
          await hotKeyManager.unregister(_toggleHotKey!);
        }

        // 注册切换快捷键：Ctrl/Cmd + Shift + L
        _toggleHotKey = HotKey(
          key: PhysicalKeyboardKey.keyL,
          modifiers: [
            if (Platform.isMacOS) HotKeyModifier.meta else HotKeyModifier.control,
            HotKeyModifier.shift,
          ],
          scope: HotKeyScope.system,
        );

        await hotKeyManager.register(
          _toggleHotKey!,
          keyDownHandler: (hotKey) {
            toggle();
          },
        );
      },
      action: 'registerDesktopLyricHotKey',
    );
  }

  Future<DesktopLyricSettings> _loadSettings() async {
    try {
      final box = await Hive.openBox<Map<dynamic, dynamic>>('music_settings');
      final data = box.get('desktop_lyric_settings');
      if (data != null) {
        final settings = DesktopLyricSettings.fromJson(
          Map<String, dynamic>.from(data),
        );
        // 使用当前主题色作为高亮色
        return settings.copyWith(highlightColor: AppColors.primary);
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '加载桌面歌词设置失败');
    }
    // 默认设置使用当前主题色
    return DesktopLyricSettings(highlightColor: AppColors.primary);
  }

  Future<void> _saveSettings(DesktopLyricSettings settings) async {
    await AppError.guard(
      () async {
        final box =
            await Hive.openBox<Map<dynamic, dynamic>>('music_settings');
        await box.put('desktop_lyric_settings', settings.toJson());
      },
      action: 'saveDesktopLyricSettings',
    );
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _positionSaveTimer?.cancel();
    windowManager.removeListener(this);
    if (_toggleHotKey != null) {
      hotKeyManager.unregister(_toggleHotKey!);
    }
    _service?.dispose();
    super.dispose();
  }
}

/// macOS 状态栏 Provider
final menuBarProvider =
    StateNotifierProvider<MenuBarNotifier, MenuBarState>(MenuBarNotifier.new);

/// 状态栏状态
class MenuBarState {
  const MenuBarState({
    this.settings = const MenuBarSettings(),
    this.isVisible = false,
    this.isInitialized = false,
  });

  final MenuBarSettings settings;
  final bool isVisible;
  final bool isInitialized;

  MenuBarState copyWith({
    MenuBarSettings? settings,
    bool? isVisible,
    bool? isInitialized,
  }) => MenuBarState(
      settings: settings ?? this.settings,
      isVisible: isVisible ?? this.isVisible,
      isInitialized: isInitialized ?? this.isInitialized,
    );
}

/// 状态栏状态管理器
class MenuBarNotifier extends StateNotifier<MenuBarState> {
  MenuBarNotifier(this._ref) : super(const MenuBarState()) {
    _init();
  }

  final Ref _ref;
  MenuBarServiceMacOS? _service;
  Timer? _syncTimer;

  bool get isSupported => Platform.isMacOS;

  Future<void> _init() async {
    if (!isSupported) return;

    await AppError.guard(
      () async {
        final settings = await _loadSettings();
        if (!mounted) return;

        _service = MenuBarServiceMacOS.instance;
        await _service!.init(settings);
        if (!mounted) {
          await _service!.dispose();
          _service = null;
          return;
        }

        // 设置控制回调
        _service!.onControlAction = _handleControlAction;

        state = state.copyWith(
          settings: settings,
          isInitialized: true,
          isVisible: settings.enabled,
        );

        if (settings.enabled) {
          _startListening();
        }
      },
      action: 'initMenuBar',
    );
  }

  void _handleControlAction(String action) {
    final playerNotifier = _ref.read(musicPlayerControllerProvider.notifier);

    switch (action) {
      case 'play':
        playerNotifier.playOrPause();
      case 'pause':
        playerNotifier.playOrPause();
      case 'previous':
        playerNotifier.playPrevious();
      case 'next':
        playerNotifier.playNext();
    }
  }

  void _startListening() {
    _ref
      // 监听播放器状态
      ..listen<MusicPlayerState>(musicPlayerControllerProvider,
          (previous, next) {
        _syncMusicInfo();
      })
      // 监听歌词
      ..listen<LyricState>(currentLyricProvider, (previous, next) {
        _syncLyric();
      });

    // 启动同步定时器
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _syncMusicInfo();
      _syncLyric();
    });

    // 立即同步一次
    _syncMusicInfo();
    _syncLyric();
  }

  void _syncMusicInfo() {
    if (_service == null || !state.isVisible) return;

    final playerState = _ref.read(musicPlayerControllerProvider);
    final currentMusic = _ref.read(currentMusicProvider);

    if (currentMusic == null) {
      _service!.updateMusicInfo(
        title: '',
        artist: '',
        isPlaying: false,
      );
      return;
    }

    final progress = playerState.duration.inMilliseconds > 0
        ? playerState.position.inMilliseconds /
            playerState.duration.inMilliseconds
        : 0.0;

    _service!.updateMusicInfo(
      title: currentMusic.title ?? currentMusic.name,
      artist: currentMusic.artist ?? '',
      album: currentMusic.album,
      coverData: currentMusic.coverData,
      isPlaying: playerState.isPlaying,
      progress: progress,
      currentTimeMs: playerState.position.inMilliseconds,
      totalTimeMs: playerState.duration.inMilliseconds,
    );
  }

  void _syncLyric() {
    if (_service == null || !state.isVisible) return;

    final lyricState = _ref.read(currentLyricProvider);
    final playerState = _ref.read(musicPlayerControllerProvider);

    if (lyricState.lyricData.isEmpty) {
      _service!.updateLyric(currentLine: null, nextLine: null);
      return;
    }

    final currentIndex =
        lyricState.lyricData.getCurrentLineIndex(playerState.position);

    if (currentIndex < 0) {
      _service!.updateLyric(currentLine: null, nextLine: null);
      return;
    }

    final lines = lyricState.lyricData.lines;
    final currentLine = lines[currentIndex].text;
    final nextLine =
        currentIndex + 1 < lines.length ? lines[currentIndex + 1].text : null;

    _service!.updateLyric(currentLine: currentLine, nextLine: nextLine);
  }

  Future<void> setVisible(bool visible) async {
    if (_service == null) return;

    await _service!.setVisible(visible);
    state = state.copyWith(isVisible: visible);

    if (visible) {
      _startListening();
    } else {
      _syncTimer?.cancel();
    }

    final newSettings = state.settings.copyWith(enabled: visible);
    state = state.copyWith(settings: newSettings);
    await _saveSettings(newSettings);
  }

  Future<MenuBarSettings> _loadSettings() async {
    try {
      final box = await Hive.openBox<Map<dynamic, dynamic>>('music_settings');
      final data = box.get('menu_bar_settings');
      if (data != null) {
        return MenuBarSettings.fromJson(
          Map<String, dynamic>.from(data),
        );
      }
    } on Exception catch (e, st) {
      AppError.ignore(e, st, '加载状态栏设置失败');
    }
    return const MenuBarSettings();
  }

  Future<void> _saveSettings(MenuBarSettings settings) async {
    await AppError.guard(
      () async {
        final box =
            await Hive.openBox<Map<dynamic, dynamic>>('music_settings');
        await box.put('menu_bar_settings', settings.toJson());
      },
      action: 'saveMenuBarSettings',
    );
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _service?.dispose();
    super.dispose();
  }
}
