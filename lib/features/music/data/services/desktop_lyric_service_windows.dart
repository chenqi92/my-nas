import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/features/music/data/services/desktop_lyric_service.dart';
import 'package:my_nas/features/music/domain/entities/desktop_lyric_settings.dart';
// ignore: depend_on_referenced_packages
import 'package:screen_retriever/screen_retriever.dart';

/// Windows 桌面歌词服务实现
class DesktopLyricServiceWindowsImpl implements DesktopLyricService {
  DesktopLyricServiceWindowsImpl._();
  static final DesktopLyricServiceWindowsImpl _instance =
      DesktopLyricServiceWindowsImpl._();
  static DesktopLyricServiceWindowsImpl get instance => _instance;

  WindowController? _windowController;
  bool _isVisible = false;
  DesktopLyricSettings _settings = const DesktopLyricSettings();
  bool _isInitialized = false;
  Offset? _currentPosition;

  /// 位置变化回调
  void Function(double x, double y)? onPositionChanged;

  @override
  bool get isSupported => Platform.isWindows;

  @override
  bool get isVisible => _isVisible;

  @override
  Future<void> init(DesktopLyricSettings settings) async {
    if (!isSupported) return;
    _settings = settings;
    _isInitialized = true;
  }

  @override
  Future<void> show() async {
    if (!isSupported || !_isInitialized) return;

    await AppError.guard(
      () async {
        if (_windowController == null) {
          await _createWindow();
        } else {
          await _windowController!.show();
        }
        _isVisible = true;
      },
      action: 'showDesktopLyric',
    );
  }

  @override
  Future<void> hide() async {
    if (!isSupported) return;

    await AppError.guard(
      () async {
        if (_windowController != null) {
          await _windowController!.close();
          _windowController = null;
        }
        _isVisible = false;
      },
      action: 'hideDesktopLyric',
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
    if (_windowController == null || !_isVisible) return;

    await AppError.guard(
      () async {
        final data = {
          'type': 'updateLyric',
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
        };
        await DesktopMultiWindow.invokeMethod(
          _windowController!.windowId,
          'updateData',
          jsonEncode(data),
        );
      },
      action: 'updateDesktopLyric',
    );
  }

  @override
  Future<void> updatePlayingState(bool isPlaying) async {
    if (_windowController == null || !_isVisible) return;

    await AppError.guard(
      () async {
        final data = {
          'type': 'updatePlayingState',
          'isPlaying': isPlaying,
        };
        await DesktopMultiWindow.invokeMethod(
          _windowController!.windowId,
          'updateData',
          jsonEncode(data),
        );
      },
      action: 'updatePlayingState',
    );
  }

  @override
  Future<void> setPosition(Offset position) async {
    if (_windowController == null) return;

    await AppError.guard(
      () async {
        await _windowController!.setFrame(
          Rect.fromLTWH(
            position.dx,
            position.dy,
            _settings.windowWidth,
            _settings.windowHeight,
          ),
        );
        _currentPosition = position;
      },
      action: 'setDesktopLyricPosition',
    );
  }

  @override
  Future<Offset?> getPosition() async =>
      // WindowController 不支持 getFrame，返回缓存的位置
      _currentPosition;

  @override
  Future<void> updateSettings(DesktopLyricSettings settings) async {
    _settings = settings;

    if (_windowController == null || !_isVisible) return;

    await AppError.guard(
      () async {
        final data = {
          'type': 'updateSettings',
          'settings': settings.toJson(),
        };
        await DesktopMultiWindow.invokeMethod(
          _windowController!.windowId,
          'updateData',
          jsonEncode(data),
        );
      },
      action: 'updateDesktopLyricSettings',
    );
  }

  @override
  Future<void> dispose() async {
    await hide();
    _isInitialized = false;
  }

  Future<void> _createWindow() async {
    // 计算窗口位置
    Offset position;
    if (_settings.hasPosition) {
      position = Offset(_settings.windowX!, _settings.windowY!);
    } else {
      // 默认在屏幕底部中央
      position = await _getDefaultPosition();
    }

    // 创建窗口参数
    final arguments = jsonEncode({
      'type': 'desktopLyric',
      'settings': _settings.toJson(),
    });

    // 创建子窗口
    _windowController = await DesktopMultiWindow.createWindow(arguments);

    // 配置窗口属性
    await _windowController!.setFrame(
      Rect.fromLTWH(
        position.dx,
        position.dy,
        _settings.windowWidth,
        _settings.windowHeight,
      ),
    );

    // 设置窗口标题（不显示，但用于识别）
    await _windowController!.setTitle('Desktop Lyrics');

    // 设置窗口回调（通过 DesktopMultiWindow handler）
    // 主窗口接收来自子窗口的消息
    DesktopMultiWindow.setMethodHandler((call, fromWindowId) async {
      // 只处理来自歌词子窗口的消息
      final lyricWindowId = _windowController?.windowId;
      if (lyricWindowId == null || fromWindowId != lyricWindowId) return null;

      switch (call.method) {
        case 'onWindowClose':
          _isVisible = false;
          _windowController = null;

        case 'saveDesktopLyricPosition':
          if (call.arguments != null) {
            final data = jsonDecode(call.arguments as String) as Map<String, dynamic>;
            final x = (data['x'] as num).toDouble();
            final y = (data['y'] as num).toDouble();
            _currentPosition = Offset(x, y);
            onPositionChanged?.call(x, y);
          }
      }
      return null;
    });

    await _windowController!.show();
  }

  Future<Offset> _getDefaultPosition() async {
    final screenRetriever = ScreenRetriever.instance;
    final primaryDisplay = await screenRetriever.getPrimaryDisplay();
    final screenSize = primaryDisplay.size;

    // 屏幕底部中央，距离底部 100px
    final x = (screenSize.width - _settings.windowWidth) / 2;
    final y = screenSize.height - _settings.windowHeight - 100;

    return Offset(x, y);
  }
}
