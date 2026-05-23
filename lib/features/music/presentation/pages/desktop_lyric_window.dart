import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';

import 'package:my_nas/features/music/domain/entities/desktop_lyric_settings.dart';
import 'package:my_nas/features/music/presentation/widgets/desktop_lyric_content.dart';

/// 桌面歌词窗口入口
/// 作为子窗口的 main 函数调用
Future<void> desktopLyricMain(List<String> args) async {
  // 解析窗口 ID 和参数
  final windowId = int.parse(args[0]);
  final arguments = args.length > 1 ? jsonDecode(args[1]) as Map<String, dynamic> : <String, dynamic>{};

  WidgetsFlutterBinding.ensureInitialized();

  // 解析设置
  final settingsJson = arguments['settings'] as Map<String, dynamic>?;
  final settings = settingsJson != null
      ? DesktopLyricSettings.fromJson(settingsJson)
      : const DesktopLyricSettings();

  // 注意：子窗口不能使用 window_manager 或 flutter_acrylic 进行初始化
  // 它们会检测到主窗口已存在并报错导致崩溃
  // 透明效果需要在创建窗口时通过 desktop_multi_window 原生代码设置

  runApp(DesktopLyricApp(
    windowId: windowId,
    initialSettings: settings,
  ));
}

/// 桌面歌词应用
class DesktopLyricApp extends StatelessWidget {
  const DesktopLyricApp({
    super.key,
    required this.windowId,
    required this.initialSettings,
  });

  final int windowId;
  final DesktopLyricSettings initialSettings;

  @override
  Widget build(BuildContext context) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.transparent,
      ),
      home: DesktopLyricWindow(
        windowId: windowId,
        initialSettings: initialSettings,
      ),
    );
}

/// 桌面歌词窗口
class DesktopLyricWindow extends StatefulWidget {
  const DesktopLyricWindow({
    super.key,
    required this.windowId,
    required this.initialSettings,
  });

  final int windowId;
  final DesktopLyricSettings initialSettings;

  @override
  State<DesktopLyricWindow> createState() => _DesktopLyricWindowState();
}

class _DesktopLyricWindowState extends State<DesktopLyricWindow> {
  late DesktopLyricSettings _settings;
  late WindowController _windowController;
  String? _currentLyric;
  String? _currentTranslation;
  String? _nextLyric;
  String? _nextTranslation;
  bool _isPlaying = false;
  double _progress = 0.0;
  bool _isHovering = false;
  Offset? _dragStartPosition;
  Offset? _windowStartPosition;

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;
    _windowController = WindowController.fromWindowId(widget.windowId);
    _setupMethodHandler();
    _initWindow();
  }

  Future<void> _initWindow() async {
    // 初始化窗口位置
    _windowStartPosition = Offset(
      _settings.windowX ?? 0,
      _settings.windowY ?? 0,
    );
  }

  void _setupMethodHandler() {
    DesktopMultiWindow.setMethodHandler((call, fromWindowId) async {
      if (call.method == 'updateData') {
        final data = jsonDecode(call.arguments as String) as Map<String, dynamic>;
        _handleUpdateData(data);
      }
      return null;
    });
  }

  void _handleUpdateData(Map<String, dynamic> data) {
    final type = data['type'] as String?;

    switch (type) {
      case 'updateLyric':
        final currentLine = data['currentLine'] as Map<String, dynamic>?;
        final nextLine = data['nextLine'] as Map<String, dynamic>?;
        setState(() {
          _currentLyric = currentLine?['text'] as String?;
          _currentTranslation = currentLine?['translation'] as String?;
          _nextLyric = nextLine?['text'] as String?;
          _nextTranslation = nextLine?['translation'] as String?;
          _isPlaying = data['isPlaying'] as bool? ?? false;
          _progress = (data['progress'] as num?)?.toDouble() ?? 0.0;
        });

      case 'updatePlayingState':
        setState(() {
          _isPlaying = data['isPlaying'] as bool? ?? false;
        });

      case 'updateSettings':
        final settingsJson = data['settings'] as Map<String, dynamic>?;
        if (settingsJson != null) {
          setState(() {
            _settings = DesktopLyricSettings.fromJson(settingsJson);
          });
        }
    }
  }

  Future<void> _closeWindow() async {
    // 通知主窗口
    await DesktopMultiWindow.invokeMethod(0, 'onWindowClose', null);
    await _windowController.close();
  }

  Future<void> _savePosition(Offset position) async {
    // 通知主窗口保存位置
    await DesktopMultiWindow.invokeMethod(
      0, // 主窗口 ID
      'saveDesktopLyricPosition',
      jsonEncode({
        'x': position.dx,
        'y': position.dy,
      }),
    );
  }

  void _onPanStart(DragStartDetails details) {
    _dragStartPosition = details.globalPosition;
  }

  Future<void> _onPanUpdate(DragUpdateDetails details) async {
    if (_dragStartPosition == null || _windowStartPosition == null) return;

    final delta = details.globalPosition - _dragStartPosition!;
    final newPosition = _windowStartPosition! + delta;

    await _windowController.setFrame(
      Rect.fromLTWH(
        newPosition.dx,
        newPosition.dy,
        _settings.windowWidth,
        _settings.windowHeight,
      ),
    );
  }

  Future<void> _onPanEnd(DragEndDetails details) async {
    if (_dragStartPosition == null || _windowStartPosition == null) return;

    // 计算最终位置
    final delta = details.localPosition - _dragStartPosition!;
    final finalPosition = _windowStartPosition! + delta;

    // 更新本地缓存的位置
    _windowStartPosition = finalPosition;

    // 保存位置到主窗口
    await _savePosition(finalPosition);
    _dragStartPosition = null;
  }

  @override
  Widget build(BuildContext context) {
    // 获取系统亮度模式
    final brightness = MediaQuery.platformBrightnessOf(context);
    final isDarkMode = brightness == Brightness.dark;

    // 根据系统外观调整颜色
    final effectiveTextColor = isDarkMode
        ? _settings.textColor
        : const Color(0xFF333333); // 亮色模式使用深色文字
    final effectiveBackgroundColor = isDarkMode
        ? _settings.backgroundColor
        : const Color(0xE6FFFFFF); // 亮色模式使用浅色背景

    final effectiveSettings = _settings.copyWith(
      textColor: effectiveTextColor,
      backgroundColor: effectiveBackgroundColor,
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: MouseRegion(
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        child: GestureDetector(
          onPanStart: _settings.lockPosition ? null : _onPanStart,
          onPanUpdate: _settings.lockPosition ? null : _onPanUpdate,
          onPanEnd: _settings.lockPosition ? null : _onPanEnd,
          child: DesktopLyricContent(
            currentLyric: _currentLyric,
            currentTranslation: _currentTranslation,
            nextLyric: _nextLyric,
            nextTranslation: _nextTranslation,
            isPlaying: _isPlaying,
            isHovering: _isHovering,
            settings: effectiveSettings,
            progress: _progress,
            onClose: _closeWindow,
            onLockToggle: () {
              setState(() {
                _settings = _settings.copyWith(lockPosition: !_settings.lockPosition);
              });
            },
          ),
        ),
      ),
    );
  }
}
