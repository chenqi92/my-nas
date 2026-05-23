import 'dart:io';

import 'package:flutter/services.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/features/music/data/services/desktop_lyric_service.dart';
import 'package:my_nas/features/music/domain/entities/desktop_lyric_settings.dart';

/// macOS 桌面歌词服务实现
/// 使用 Method Channel 与原生 Swift 代码通信
class DesktopLyricServiceMacOSImpl implements DesktopLyricService {
  DesktopLyricServiceMacOSImpl._();
  static final DesktopLyricServiceMacOSImpl _instance =
      DesktopLyricServiceMacOSImpl._();
  static DesktopLyricServiceMacOSImpl get instance => _instance;

  static const _channel = MethodChannel('com.kkape.mynas/desktop_lyric');

  bool _isVisible = false;
  bool _isInitialized = false;
  DesktopLyricSettings _settings = const DesktopLyricSettings();

  /// 位置保存回调
  void Function(double x, double y)? onPositionChanged;

  /// 播放控制回调
  void Function(String action)? onControlAction;

  @override
  bool get isSupported => Platform.isMacOS;

  @override
  bool get isVisible => _isVisible;

  @override
  Future<void> init(DesktopLyricSettings settings) async {
    if (!isSupported) return;

    _settings = settings;

    // 设置 Method Channel 回调
    _channel.setMethodCallHandler(_handleMethodCall);

    // 初始化原生层
    await AppError.guard(
      () async {
        await _channel.invokeMethod('init', {
          'settings': settings.toJson(),
        });
        _isInitialized = true;
      },
      action: 'initDesktopLyricMacOS',
    );
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    final args = call.arguments as Map<dynamic, dynamic>?;
    switch (call.method) {
      case 'onPositionChanged':
        final x = args?['x'] as double;
        final y = args?['y'] as double;
        onPositionChanged?.call(x, y);
      case 'onWindowClosed':
        _isVisible = false;
      case 'onLockToggled':
        final isLocked = args?['isLocked'] as bool;
        _settings = _settings.copyWith(lockPosition: isLocked);
      case 'onControlAction':
        final action = args?['action'] as String?;
        if (action != null) {
          onControlAction?.call(action);
        }
    }
    return null;
  }

  @override
  Future<void> show() async {
    if (!isSupported || !_isInitialized) return;

    await AppError.guard(
      () async {
        await _channel.invokeMethod('show');
        _isVisible = true;
      },
      action: 'showDesktopLyricMacOS',
    );
  }

  @override
  Future<void> hide() async {
    if (!isSupported) return;

    await AppError.guard(
      () async {
        await _channel.invokeMethod('hide');
        _isVisible = false;
      },
      action: 'hideDesktopLyricMacOS',
    );
  }

  @override
  Future<void> toggle() async {
    if (_isVisible) {
      await hide();
    } else {
      await show();
    }
  }

  @override
  Future<void> updateLyric({
    required LyricLineData? currentLine,
    LyricLineData? nextLine,
    required bool isPlaying,
    double progress = 0.0,
  }) async {
    if (!isSupported || !_isVisible) return;

    await AppError.guard(
      () async {
        await _channel.invokeMethod('updateLyric', {
          'currentLine': currentLine != null
              ? {
                  'text': currentLine.text,
                  'translation': currentLine.translation,
                }
              : null,
          'nextLine': nextLine != null
              ? {
                  'text': nextLine.text,
                  'translation': nextLine.translation,
                }
              : null,
          'isPlaying': isPlaying,
          'progress': progress,
        });
      },
      action: 'updateDesktopLyricMacOS',
    );
  }

  @override
  Future<void> updatePlayingState(bool isPlaying) async {
    if (!isSupported || !_isVisible) return;

    await AppError.guard(
      () async {
        await _channel.invokeMethod('updatePlayingState', {
          'isPlaying': isPlaying,
        });
      },
      action: 'updatePlayingStateMacOS',
    );
  }

  @override
  Future<void> setPosition(Offset position) async {
    if (!isSupported) return;

    await AppError.guard(
      () async {
        await _channel.invokeMethod('setPosition', {
          'x': position.dx,
          'y': position.dy,
        });
      },
      action: 'setDesktopLyricPositionMacOS',
    );
  }

  @override
  Future<Offset?> getPosition() async {
    if (!isSupported) return null;

    try {
      final result =
          await _channel.invokeMethod<Map<dynamic, dynamic>>('getPosition');
      if (result != null) {
        return Offset(
          (result['x'] as num).toDouble(),
          (result['y'] as num).toDouble(),
        );
      }
      return null;
    } on Exception catch (e, st) {
      AppError.ignore(e, st, 'getDesktopLyricPositionMacOS');
      return null;
    }
  }

  @override
  Future<void> updateSettings(DesktopLyricSettings settings) async {
    _settings = settings;

    if (!isSupported || !_isVisible) return;

    await AppError.guard(
      () async {
        await _channel.invokeMethod('updateSettings', {
          'settings': settings.toJson(),
        });
      },
      action: 'updateDesktopLyricSettingsMacOS',
    );
  }

  @override
  Future<void> dispose() async {
    await hide();
    _channel.setMethodCallHandler(null);
    _isInitialized = false;
  }
}

/// macOS 状态栏服务
class MenuBarServiceMacOS {
  MenuBarServiceMacOS._();
  static final MenuBarServiceMacOS _instance = MenuBarServiceMacOS._();
  static MenuBarServiceMacOS get instance => _instance;

  static const _channel = MethodChannel('com.kkape.mynas/menu_bar');

  bool _isInitialized = false;

  /// 控制动作回调
  void Function(String action)? onControlAction;

  bool get isSupported => Platform.isMacOS;

  Future<void> init(MenuBarSettings settings) async {
    if (!isSupported) return;

    _channel.setMethodCallHandler(_handleMethodCall);

    await AppError.guard(
      () async {
        await _channel.invokeMethod('init', {
          'settings': settings.toJson(),
        });
        _isInitialized = true;
      },
      action: 'initMenuBarMacOS',
    );
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    final args = call.arguments as Map<dynamic, dynamic>?;
    switch (call.method) {
      case 'onControlAction':
        final action = args?['action'] as String?;
        if (action != null) {
          onControlAction?.call(action);
        }
    }
    return null;
  }

  Future<void> updatePlayingState(bool isPlaying) async {
    if (!isSupported || !_isInitialized) return;

    await AppError.guard(
      () async {
        await _channel.invokeMethod('updatePlayingState', {
          'isPlaying': isPlaying,
        });
      },
      action: 'updateMenuBarPlayingState',
    );
  }

  Future<void> updateMusicInfo({
    required String title,
    required String artist,
    String? album,
    List<int>? coverData,
    bool isPlaying = false,
    double progress = 0.0,
    int currentTimeMs = 0,
    int totalTimeMs = 0,
  }) async {
    if (!isSupported || !_isInitialized) return;

    await AppError.guard(
      () async {
        await _channel.invokeMethod('updateMusicInfo', {
          'title': title,
          'artist': artist,
          'album': album,
          'coverData': coverData,
          'isPlaying': isPlaying,
          'progress': progress,
          'currentTimeMs': currentTimeMs,
          'totalTimeMs': totalTimeMs,
        });
      },
      action: 'updateMenuBarMusicInfo',
    );
  }

  Future<void> updateLyric({
    String? currentLine,
    String? nextLine,
  }) async {
    if (!isSupported || !_isInitialized) return;

    await AppError.guard(
      () async {
        await _channel.invokeMethod('updateLyric', {
          'currentLine': currentLine,
          'nextLine': nextLine,
        });
      },
      action: 'updateMenuBarLyric',
    );
  }

  Future<void> setVisible(bool visible) async {
    if (!isSupported || !_isInitialized) return;

    await AppError.guard(
      () async {
        await _channel.invokeMethod('setVisible', {
          'visible': visible,
        });
      },
      action: 'setMenuBarVisible',
    );
  }

  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
    _isInitialized = false;
  }
}
