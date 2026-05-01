// ignore_for_file: unused_field

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/features/music/data/services/desktop_lyric_service.dart';
import 'package:my_nas/features/music/domain/entities/desktop_lyric_settings.dart';

// Win32 常量定义
const int _WM_MOUSELEAVE = 0x02A3;
const int _TME_LEAVE = 0x00000002;

/// 把 [Color] 的浮点分量（0.0–1.0）转回 0–255 字节值，
/// 用于 Win32 RGB() 调用。Flutter 3.32+ 移除了 Color.red/green/blue。
int _byteOf(double v) => (v * 255.0).round() & 0xff;
const int _FW_NORMAL = 400;
const int _FW_BOLD = 700;
const int _DEFAULT_CHARSET = 1;
const int _OUT_DEFAULT_PRECIS = 0;
const int _CLIP_DEFAULT_PRECIS = 0;
const int _CLEARTYPE_QUALITY = 5;
const int _DEFAULT_PITCH = 0;
const int _FF_DONTCARE = 0;

// TRACKMOUSEEVENT 结构体
final class _TRACKMOUSEEVENT extends Struct {
  @Uint32()
  external int cbSize;
  @Uint32()
  external int dwFlags;
  @IntPtr()
  external int hwndTrack;
  @Uint32()
  external int dwHoverTime;
}

/// Win32 FFI 函数封装类（延迟初始化）
class _Win32Functions {
  _Win32Functions._();
  static final _Win32Functions instance = _Win32Functions._();

  DynamicLibrary? _user32;
  DynamicLibrary? _gdi32;

  DynamicLibrary get user32 => _user32 ??= DynamicLibrary.open('user32.dll');
  DynamicLibrary get gdi32 => _gdi32 ??= DynamicLibrary.open('gdi32.dll');

  // 缓存的函数指针
  int Function(Pointer<_TRACKMOUSEEVENT>)? _trackMouseEvent;
  int Function(int, int, int, int, int, int, int, int, int, int, int, int, int, Pointer<Utf16>)? _createFont;
  int Function(int, Pointer<Utf16>, int, Pointer<SIZE>)? _getTextExtentPoint32;
  int Function(int, int, int, int, int, int)? _createRoundRectRgn;
  int Function(int, int)? _selectClipRgn;

  int Function(Pointer<_TRACKMOUSEEVENT>) get trackMouseEvent =>
      _trackMouseEvent ??= user32.lookupFunction<
          Int32 Function(Pointer<_TRACKMOUSEEVENT>),
          int Function(Pointer<_TRACKMOUSEEVENT>)>('TrackMouseEvent');

  int Function(int, int, int, int, int, int, int, int, int, int, int, int, int, Pointer<Utf16>) get createFont =>
      _createFont ??= gdi32.lookupFunction<
          IntPtr Function(Int32, Int32, Int32, Int32, Int32, Uint32, Uint32, Uint32, Uint32, Uint32, Uint32, Uint32, Uint32, Pointer<Utf16>),
          int Function(int, int, int, int, int, int, int, int, int, int, int, int, int, Pointer<Utf16>)>('CreateFontW');

  int Function(int, Pointer<Utf16>, int, Pointer<SIZE>) get getTextExtentPoint32 =>
      _getTextExtentPoint32 ??= gdi32.lookupFunction<
          Int32 Function(IntPtr, Pointer<Utf16>, Int32, Pointer<SIZE>),
          int Function(int, Pointer<Utf16>, int, Pointer<SIZE>)>('GetTextExtentPoint32W');

  int Function(int, int, int, int, int, int) get createRoundRectRgn =>
      _createRoundRectRgn ??= gdi32.lookupFunction<
          IntPtr Function(Int32, Int32, Int32, Int32, Int32, Int32),
          int Function(int, int, int, int, int, int)>('CreateRoundRectRgn');

  int Function(int, int) get selectClipRgn =>
      _selectClipRgn ??= gdi32.lookupFunction<
          Int32 Function(IntPtr, IntPtr),
          int Function(int, int)>('SelectClipRgn');
}

// 便捷访问
_Win32Functions get _win32 => _Win32Functions.instance;

/// Windows 原生桌面歌词服务实现
/// 使用 Win32 API 创建透明悬浮窗口
class DesktopLyricServiceWindowsNativeImpl implements DesktopLyricService {
  DesktopLyricServiceWindowsNativeImpl._();
  static final DesktopLyricServiceWindowsNativeImpl _instance =
      DesktopLyricServiceWindowsNativeImpl._();
  static DesktopLyricServiceWindowsNativeImpl get instance => _instance;

  // 窗口句柄
  int _hwnd = 0;

  // 窗口类名
  static const String _className = 'MyNasDesktopLyric';

  // 状态
  bool _isVisible = false;
  bool _isInitialized = false;
  DesktopLyricSettings _settings = const DesktopLyricSettings();

  // 当前歌词数据
  String? _currentLyric;
  String? _currentTranslation;
  String? _nextLyric;
  bool _isPlaying = false;
  double _progress = 0.0;

  // 窗口位置
  int _windowX = 0;
  int _windowY = 0;

  // 刷新定时器
  Timer? _refreshTimer;

  // 鼠标悬停状态
  bool _isHovering = false;

  // 位置变化回调
  void Function(double x, double y)? onPositionChanged;

  // 窗口过程回调（必须是顶级函数或静态方法）
  static int _wndProc(int hwnd, int msg, int wParam, int lParam) {
    switch (msg) {
      case WM_DESTROY:
        PostQuitMessage(0);
        return 0;

      case WM_NCHITTEST:
        // 允许拖动整个窗口
        final result = DefWindowProc(hwnd, msg, wParam, lParam);
        if (result == HTCLIENT) {
          return HTCAPTION; // 让客户区可拖动
        }
        return result;

      case WM_MOVE:
        // 窗口移动时保存位置
        final x = lParam & 0xFFFF;
        final y = (lParam >> 16) & 0xFFFF;
        _instance._windowX = x;
        _instance._windowY = y;
        _instance.onPositionChanged?.call(x.toDouble(), y.toDouble());
        return 0;

      case WM_MOUSEMOVE:
        if (!_instance._isHovering) {
          _instance._isHovering = true;
          _instance._invalidateWindow();

          // 设置鼠标离开追踪
          final tme = calloc<_TRACKMOUSEEVENT>();
          tme.ref.cbSize = sizeOf<_TRACKMOUSEEVENT>();
          tme.ref.dwFlags = _TME_LEAVE;
          tme.ref.hwndTrack = hwnd;
          tme.ref.dwHoverTime = 0;
          _win32.trackMouseEvent(tme);
          calloc.free(tme);
        }
        return 0;

      case _WM_MOUSELEAVE:
        _instance._isHovering = false;
        _instance._invalidateWindow();
        return 0;

      case WM_LBUTTONDOWN:
        // 检查是否点击关闭按钮
        if (_instance._isHovering) {
          final x = lParam & 0xFFFF;
          final y = (lParam >> 16) & 0xFFFF;
          if (_instance._isCloseButtonHit(x, y)) {
            _instance.hide();
            return 0;
          }
        }
        // 开始拖动
        ReleaseCapture();
        SendMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
        return 0;

      case WM_PAINT:
        _instance._onPaint(hwnd);
        return 0;

      default:
        return DefWindowProc(hwnd, msg, wParam, lParam);
    }
  }

  bool _isCloseButtonHit(int x, int y) {
    // 关闭按钮在右上角，30x30 像素
    final width = _settings.windowWidth.toInt();
    return x >= width - 40 && x <= width - 10 && y >= 10 && y <= 40;
  }

  void _invalidateWindow() {
    if (_hwnd != 0) {
      InvalidateRect(_hwnd, nullptr, TRUE);
    }
  }

  @override
  bool get isSupported => Platform.isWindows;

  @override
  bool get isVisible => _isVisible;

  @override
  Future<void> init(DesktopLyricSettings settings) async {
    if (!isSupported) return;
    _settings = settings;

    await AppError.guard(
      () async {
        _registerWindowClass();
        _isInitialized = true;
      },
      action: 'initDesktopLyricWindowsNative',
    );
  }

  void _registerWindowClass() {
    final hInstance = GetModuleHandle(nullptr);
    final className = _className.toNativeUtf16();

    final wc = calloc<WNDCLASS>();
    wc.ref.style = CS_HREDRAW | CS_VREDRAW;
    wc.ref.lpfnWndProc = Pointer.fromFunction<WNDPROC>(_wndProc, 0);
    wc.ref.hInstance = hInstance;
    wc.ref.hCursor = LoadCursor(NULL, IDC_ARROW);
    wc.ref.hbrBackground = NULL; // 透明背景
    wc.ref.lpszClassName = className;

    RegisterClass(wc);

    calloc.free(wc);
    calloc.free(className);
  }

  @override
  Future<void> show() async {
    if (!isSupported || !_isInitialized) return;

    await AppError.guard(
      () async {
        try {
          if (_hwnd == 0) {
            _createWindow();
          }
          if (_hwnd != 0) {
            ShowWindow(_hwnd, SW_SHOWNOACTIVATE);
            _isVisible = true;
            _startRefreshTimer();
          }
        } catch (e) {
          // FFI 调用失败时不崩溃
          _isVisible = false;
          rethrow;
        }
      },
      action: 'showDesktopLyricWindowsNative',
    );
  }

  void _createWindow() {
    final hInstance = GetModuleHandle(nullptr);
    final className = _className.toNativeUtf16();
    final windowName = 'Desktop Lyrics'.toNativeUtf16();

    // 计算窗口位置
    if (_settings.hasPosition) {
      _windowX = _settings.windowX!.toInt();
      _windowY = _settings.windowY!.toInt();
    } else {
      // 默认在屏幕底部中央
      final screenWidth = GetSystemMetrics(SM_CXSCREEN);
      final screenHeight = GetSystemMetrics(SM_CYSCREEN);
      _windowX = (screenWidth - _settings.windowWidth.toInt()) ~/ 2;
      _windowY = screenHeight - _settings.windowHeight.toInt() - 100;
    }

    // 创建窗口
    // WS_EX_LAYERED: 支持透明
    // WS_EX_TOPMOST: 始终置顶
    // WS_EX_TOOLWINDOW: 不显示在任务栏
    // WS_EX_NOACTIVATE: 不激活窗口
    _hwnd = CreateWindowEx(
      WS_EX_LAYERED | WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
      className,
      windowName,
      WS_POPUP, // 无边框
      _windowX,
      _windowY,
      _settings.windowWidth.toInt(),
      _settings.windowHeight.toInt(),
      NULL,
      NULL,
      hInstance,
      nullptr,
    );

    calloc.free(className);
    calloc.free(windowName);

    if (_hwnd != 0) {
      // 设置窗口透明度
      SetLayeredWindowAttributes(
        _hwnd,
        0,
        (_settings.opacity * 255).toInt(),
        LWA_ALPHA,
      );

      // 初始绘制
      _invalidateWindow();
    }
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    // 每 50ms 刷新一次以获得流畅的卡拉OK效果
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (_isVisible && _hwnd != 0) {
        try {
          _invalidateWindow();
          _processMessages();
        } catch (e) {
          // 忽略绘制错误，防止崩溃
        }
      }
    });
  }

  void _processMessages() {
    final msg = calloc<MSG>();
    while (PeekMessage(msg, _hwnd, 0, 0, PM_REMOVE) != 0) {
      TranslateMessage(msg);
      DispatchMessage(msg);
    }
    calloc.free(msg);
  }

  void _onPaint(int hwnd) {
    if (hwnd == 0) return;

    final ps = calloc<PAINTSTRUCT>();
    final hdc = BeginPaint(hwnd, ps);

    if (hdc == 0) {
      calloc.free(ps);
      return;
    }

    try {
      final rect = calloc<RECT>();
      GetClientRect(hwnd, rect);
      final width = rect.ref.right - rect.ref.left;
      final height = rect.ref.bottom - rect.ref.top;

      if (width <= 0 || height <= 0) {
        calloc.free(rect);
        EndPaint(hwnd, ps);
        calloc.free(ps);
        return;
      }

      // 创建双缓冲
      final memDC = CreateCompatibleDC(hdc);
      final memBitmap = CreateCompatibleBitmap(hdc, width, height);
      final oldBitmap = SelectObject(memDC, memBitmap);

      // 绘制背景
      _drawBackground(memDC, width, height);

      // 绘制歌词
      _drawLyrics(memDC, width, height);

      // 绘制控制按钮（仅在悬停时）
      if (_isHovering) {
        _drawControls(memDC, width, height);
      }

      // 复制到窗口
      BitBlt(hdc, 0, 0, width, height, memDC, 0, 0, SRCCOPY);

      // 清理
      SelectObject(memDC, oldBitmap);
      DeleteObject(memBitmap);
      DeleteDC(memDC);

      calloc.free(rect);
    } finally {
      EndPaint(hwnd, ps);
      calloc.free(ps);
    }
  }

  void _drawBackground(int hdc, int width, int height) {
    // 创建背景刷
    final bgColor = _settings.backgroundColor;
    final colorRef = RGB(_byteOf(bgColor.r), _byteOf(bgColor.g), _byteOf(bgColor.b));

    final brush = CreateSolidBrush(colorRef);
    final rect = calloc<RECT>();
    rect.ref.left = 0;
    rect.ref.top = 0;
    rect.ref.right = width;
    rect.ref.bottom = height;

    // 创建圆角矩形区域
    final rgn = _win32.createRoundRectRgn(0, 0, width, height, 20, 20);
    _win32.selectClipRgn(hdc, rgn);

    FillRect(hdc, rect, brush);

    DeleteObject(rgn);
    DeleteObject(brush);
    calloc.free(rect);
  }

  void _drawLyrics(int hdc, int width, int height) {
    if (_currentLyric == null || _currentLyric!.isEmpty) {
      _drawCenteredText(hdc, width, height ~/ 2 - 14, '等待播放...', _settings.fontSize.toInt(), false);
      return;
    }

    // 设置文字渲染模式
    SetBkMode(hdc, TRANSPARENT);

    // 计算文字位置
    var yPos = 20;

    // 绘制当前歌词（大字）
    _drawLyricLine(hdc, width, yPos, _currentLyric!, _settings.fontSize.toInt(), true);
    yPos += _settings.fontSize.toInt() + 8;

    // 绘制翻译（如果有）
    if (_currentTranslation != null && _currentTranslation!.isNotEmpty && _settings.showTranslation) {
      _drawCenteredText(hdc, width, yPos, _currentTranslation!, (_settings.fontSize * 0.7).toInt(), false);
      yPos += (_settings.fontSize * 0.7).toInt() + 8;
    }

    // 绘制下一行歌词（小字）
    if (_nextLyric != null && _nextLyric!.isNotEmpty && _settings.showNextLine) {
      _drawCenteredText(hdc, width, yPos, _nextLyric!, (_settings.fontSize * 0.6).toInt(), false);
    }
  }

  void _drawLyricLine(int hdc, int width, int y, String text, int fontSize, bool isCurrentLine) {
    if (!isCurrentLine || _progress <= 0) {
      _drawCenteredText(hdc, width, y, text, fontSize, true);
      return;
    }

    // 卡拉OK效果：已唱部分和未唱部分用不同颜色
    final textWidth = _measureText(hdc, text, fontSize);
    final x = (width - textWidth) ~/ 2;

    // 计算已唱部分的宽度
    final highlightWidth = (textWidth * _progress).toInt();

    // 创建字体
    final fontName = 'Microsoft YaHei'.toNativeUtf16();
    final hFont = _win32.createFont(
      fontSize, 0, 0, 0,
      _FW_BOLD,
      FALSE, FALSE, FALSE,
      _DEFAULT_CHARSET,
      _OUT_DEFAULT_PRECIS,
      _CLIP_DEFAULT_PRECIS,
      _CLEARTYPE_QUALITY,
      _DEFAULT_PITCH | _FF_DONTCARE,
      fontName,
    );
    calloc.free(fontName);

    final oldFont = SelectObject(hdc, hFont);

    // 绘制未唱部分（白色）
    final textColor = _settings.textColor;
    SetTextColor(hdc, RGB(_byteOf(textColor.r), _byteOf(textColor.g), _byteOf(textColor.b)));
    final textPtr = text.toNativeUtf16();
    TextOut(hdc, x, y, textPtr, text.length);

    // 绘制已唱部分（高亮色）- 使用裁剪区域
    final highlightColor = _settings.highlightColor;
    SetTextColor(hdc, RGB(_byteOf(highlightColor.r), _byteOf(highlightColor.g), _byteOf(highlightColor.b)));

    final clipRect = calloc<RECT>();
    clipRect.ref.left = x;
    clipRect.ref.top = y;
    clipRect.ref.right = x + highlightWidth;
    clipRect.ref.bottom = y + fontSize + 5;

    final clipRgn = CreateRectRgn(clipRect.ref.left, clipRect.ref.top, clipRect.ref.right, clipRect.ref.bottom);
    _win32.selectClipRgn(hdc, clipRgn);
    TextOut(hdc, x, y, textPtr, text.length);
    _win32.selectClipRgn(hdc, NULL);

    DeleteObject(clipRgn);
    calloc.free(clipRect);
    calloc.free(textPtr);

    SelectObject(hdc, oldFont);
    DeleteObject(hFont);
  }

  void _drawCenteredText(int hdc, int width, int y, String text, int fontSize, bool bold) {
    final fontName = 'Microsoft YaHei'.toNativeUtf16();
    final hFont = _win32.createFont(
      fontSize, 0, 0, 0,
      bold ? _FW_BOLD : _FW_NORMAL,
      FALSE, FALSE, FALSE,
      _DEFAULT_CHARSET,
      _OUT_DEFAULT_PRECIS,
      _CLIP_DEFAULT_PRECIS,
      _CLEARTYPE_QUALITY,
      _DEFAULT_PITCH | _FF_DONTCARE,
      fontName,
    );
    calloc.free(fontName);

    final oldFont = SelectObject(hdc, hFont);

    final textColor = _settings.textColor;
    SetTextColor(hdc, RGB(_byteOf(textColor.r), _byteOf(textColor.g), _byteOf(textColor.b)));

    final textPtr = text.toNativeUtf16();
    final textWidth = _measureText(hdc, text, fontSize);
    final x = (width - textWidth) ~/ 2;

    TextOut(hdc, x, y, textPtr, text.length);

    calloc.free(textPtr);
    SelectObject(hdc, oldFont);
    DeleteObject(hFont);
  }

  int _measureText(int hdc, String text, int fontSize) {
    final fontName = 'Microsoft YaHei'.toNativeUtf16();
    final hFont = _win32.createFont(
      fontSize, 0, 0, 0,
      _FW_BOLD,
      FALSE, FALSE, FALSE,
      _DEFAULT_CHARSET,
      _OUT_DEFAULT_PRECIS,
      _CLIP_DEFAULT_PRECIS,
      _CLEARTYPE_QUALITY,
      _DEFAULT_PITCH | _FF_DONTCARE,
      fontName,
    );
    calloc.free(fontName);

    final oldFont = SelectObject(hdc, hFont);

    final size = calloc<SIZE>();
    final textPtr = text.toNativeUtf16();
    _win32.getTextExtentPoint32(hdc, textPtr, text.length, size);
    final width = size.ref.cx;

    calloc.free(textPtr);
    calloc.free(size);
    SelectObject(hdc, oldFont);
    DeleteObject(hFont);

    return width;
  }

  void _drawControls(int hdc, int width, int height) {
    // 绘制关闭按钮
    final closeX = width - 35;
    const closeY = 15;
    const closeSize = 20;

    // 绘制 X 图标
    final pen = CreatePen(PS_SOLID, 2, RGB(255, 255, 255));
    final oldPen = SelectObject(hdc, pen);

    MoveToEx(hdc, closeX, closeY, nullptr);
    LineTo(hdc, closeX + closeSize, closeY + closeSize);
    MoveToEx(hdc, closeX + closeSize, closeY, nullptr);
    LineTo(hdc, closeX, closeY + closeSize);

    SelectObject(hdc, oldPen);
    DeleteObject(pen);

    // 绘制锁定状态指示
    if (_settings.lockPosition) {
      final lockX = width - 70;
      const lockY = 15;
      // 简单的锁图标（用矩形表示）
      final lockBrush = CreateSolidBrush(RGB(255, 200, 0));
      final lockRect = calloc<RECT>();
      lockRect.ref.left = lockX;
      lockRect.ref.top = lockY;
      lockRect.ref.right = lockX + 20;
      lockRect.ref.bottom = lockY + 20;
      FrameRect(hdc, lockRect, lockBrush);
      calloc.free(lockRect);
      DeleteObject(lockBrush);
    }
  }

  @override
  Future<void> hide() async {
    if (!isSupported) return;

    await AppError.guard(
      () async {
        _refreshTimer?.cancel();
        _refreshTimer = null;

        if (_hwnd != 0) {
          ShowWindow(_hwnd, SW_HIDE);
        }
        _isVisible = false;
      },
      action: 'hideDesktopLyricWindowsNative',
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
    _currentLyric = currentLine?.text;
    _currentTranslation = currentLine?.translation;
    _nextLyric = nextLine?.text;
    _isPlaying = isPlaying;
    _progress = progress;

    // 窗口会通过定时器自动刷新
  }

  @override
  Future<void> updatePlayingState(bool isPlaying) async {
    _isPlaying = isPlaying;
  }

  @override
  Future<void> setPosition(ui.Offset position) async {
    if (_hwnd != 0) {
      _windowX = position.dx.toInt();
      _windowY = position.dy.toInt();
      SetWindowPos(
        _hwnd,
        HWND_TOPMOST,
        _windowX,
        _windowY,
        0,
        0,
        SWP_NOSIZE | SWP_NOACTIVATE,
      );
    }
  }

  @override
  Future<ui.Offset?> getPosition() async {
    return ui.Offset(_windowX.toDouble(), _windowY.toDouble());
  }

  @override
  Future<void> updateSettings(DesktopLyricSettings settings) async {
    _settings = settings;

    if (_hwnd != 0) {
      // 更新窗口透明度
      SetLayeredWindowAttributes(
        _hwnd,
        0,
        (_settings.opacity * 255).toInt(),
        LWA_ALPHA,
      );

      // 更新窗口大小
      SetWindowPos(
        _hwnd,
        HWND_TOPMOST,
        _windowX,
        _windowY,
        _settings.windowWidth.toInt(),
        _settings.windowHeight.toInt(),
        SWP_NOMOVE | SWP_NOACTIVATE,
      );

      _invalidateWindow();
    }
  }

  @override
  Future<void> dispose() async {
    _refreshTimer?.cancel();
    _refreshTimer = null;

    if (_hwnd != 0) {
      DestroyWindow(_hwnd);
      _hwnd = 0;
    }
    _isVisible = false;
    _isInitialized = false;
  }
}
