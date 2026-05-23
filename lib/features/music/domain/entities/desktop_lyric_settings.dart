import 'dart:ui';

/// 桌面歌词设置模型
class DesktopLyricSettings {
  const DesktopLyricSettings({
    this.enabled = false,
    this.fontSize = 28.0,
    this.textColor = const Color(0xFFFFFFFF),
    this.highlightColor = const Color(0xFF00BFFF), // 高亮颜色（卡拉OK效果）
    this.backgroundColor = const Color(0xCC000000),
    this.opacity = 0.9,
    this.showTranslation = true,
    this.showNextLine = true,
    this.alwaysOnTop = true,
    this.lockPosition = false,
    this.showOnMinimize = false,
    this.hideOnRestore = true,
    this.showWhenPlaying = true,
    this.windowX,
    this.windowY,
    this.windowWidth = 800.0,
    this.windowHeight = 120.0,
  });

  /// 从 JSON 反序列化
  factory DesktopLyricSettings.fromJson(Map<String, dynamic> json) => DesktopLyricSettings(
      enabled: json['enabled'] as bool? ?? false,
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 28.0,
      textColor: Color(json['textColor'] as int? ?? 0xFFFFFFFF),
      highlightColor: Color(json['highlightColor'] as int? ?? 0xFF00BFFF),
      backgroundColor: Color(json['backgroundColor'] as int? ?? 0xCC000000),
      opacity: (json['opacity'] as num?)?.toDouble() ?? 0.9,
      showTranslation: json['showTranslation'] as bool? ?? true,
      showNextLine: json['showNextLine'] as bool? ?? true,
      alwaysOnTop: json['alwaysOnTop'] as bool? ?? true,
      lockPosition: json['lockPosition'] as bool? ?? false,
      showOnMinimize: json['showOnMinimize'] as bool? ?? false,
      hideOnRestore: json['hideOnRestore'] as bool? ?? true,
      showWhenPlaying: json['showWhenPlaying'] as bool? ?? true,
      windowX: (json['windowX'] as num?)?.toDouble(),
      windowY: (json['windowY'] as num?)?.toDouble(),
      windowWidth: (json['windowWidth'] as num?)?.toDouble() ?? 800.0,
      windowHeight: (json['windowHeight'] as num?)?.toDouble() ?? 120.0,
    );

  /// 是否启用桌面歌词
  final bool enabled;

  /// 歌词字体大小
  final double fontSize;

  /// 歌词文字颜色
  final Color textColor;

  /// 高亮颜色（卡拉OK效果，已唱过的歌词颜色）
  final Color highlightColor;

  /// 背景颜色（包含透明度）
  final Color backgroundColor;

  /// 窗口整体透明度 (0.0-1.0)
  final double opacity;

  /// 是否显示翻译歌词
  final bool showTranslation;

  /// 是否显示下一行歌词
  final bool showNextLine;

  /// 是否始终置顶
  final bool alwaysOnTop;

  /// 是否锁定位置（锁定后不可拖动）
  final bool lockPosition;

  /// 最小化主窗口时是否显示桌面歌词
  final bool showOnMinimize;

  /// 恢复主窗口时是否隐藏桌面歌词（仅当 showOnMinimize 为 true 时有效）
  final bool hideOnRestore;

  /// 播放音乐时是否自动显示桌面歌词
  final bool showWhenPlaying;

  /// 窗口 X 坐标（null 表示居中）
  final double? windowX;

  /// 窗口 Y 坐标（null 表示屏幕底部）
  final double? windowY;

  /// 窗口宽度
  final double windowWidth;

  /// 窗口高度
  final double windowHeight;

  /// 窗口位置是否已设置
  bool get hasPosition => windowX != null && windowY != null;

  DesktopLyricSettings copyWith({
    bool? enabled,
    double? fontSize,
    Color? textColor,
    Color? highlightColor,
    Color? backgroundColor,
    double? opacity,
    bool? showTranslation,
    bool? showNextLine,
    bool? alwaysOnTop,
    bool? lockPosition,
    bool? showOnMinimize,
    bool? hideOnRestore,
    bool? showWhenPlaying,
    double? windowX,
    double? windowY,
    double? windowWidth,
    double? windowHeight,
  }) => DesktopLyricSettings(
      enabled: enabled ?? this.enabled,
      fontSize: fontSize ?? this.fontSize,
      textColor: textColor ?? this.textColor,
      highlightColor: highlightColor ?? this.highlightColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      opacity: opacity ?? this.opacity,
      showTranslation: showTranslation ?? this.showTranslation,
      showNextLine: showNextLine ?? this.showNextLine,
      alwaysOnTop: alwaysOnTop ?? this.alwaysOnTop,
      lockPosition: lockPosition ?? this.lockPosition,
      showOnMinimize: showOnMinimize ?? this.showOnMinimize,
      hideOnRestore: hideOnRestore ?? this.hideOnRestore,
      showWhenPlaying: showWhenPlaying ?? this.showWhenPlaying,
      windowX: windowX ?? this.windowX,
      windowY: windowY ?? this.windowY,
      windowWidth: windowWidth ?? this.windowWidth,
      windowHeight: windowHeight ?? this.windowHeight,
    );

  /// 序列化为 JSON
  Map<String, dynamic> toJson() => {
      'enabled': enabled,
      'fontSize': fontSize,
      'textColor': textColor.toARGB32(),
      'highlightColor': highlightColor.toARGB32(),
      'backgroundColor': backgroundColor.toARGB32(),
      'opacity': opacity,
      'showTranslation': showTranslation,
      'showNextLine': showNextLine,
      'alwaysOnTop': alwaysOnTop,
      'lockPosition': lockPosition,
      'showOnMinimize': showOnMinimize,
      'hideOnRestore': hideOnRestore,
      'showWhenPlaying': showWhenPlaying,
      'windowX': windowX,
      'windowY': windowY,
      'windowWidth': windowWidth,
      'windowHeight': windowHeight,
    };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DesktopLyricSettings &&
        other.enabled == enabled &&
        other.fontSize == fontSize &&
        other.textColor == textColor &&
        other.highlightColor == highlightColor &&
        other.backgroundColor == backgroundColor &&
        other.opacity == opacity &&
        other.showTranslation == showTranslation &&
        other.showNextLine == showNextLine &&
        other.alwaysOnTop == alwaysOnTop &&
        other.lockPosition == lockPosition &&
        other.showOnMinimize == showOnMinimize &&
        other.hideOnRestore == hideOnRestore &&
        other.showWhenPlaying == showWhenPlaying &&
        other.windowX == windowX &&
        other.windowY == windowY &&
        other.windowWidth == windowWidth &&
        other.windowHeight == windowHeight;
  }

  @override
  int get hashCode => Object.hash(
      enabled,
      fontSize,
      textColor,
      highlightColor,
      backgroundColor,
      opacity,
      showTranslation,
      showNextLine,
      alwaysOnTop,
      lockPosition,
      showOnMinimize,
      hideOnRestore,
      showWhenPlaying,
      windowX,
      windowY,
      windowWidth,
      windowHeight,
    );
}

/// macOS 状态栏设置
class MenuBarSettings {
  const MenuBarSettings({
    this.enabled = true,
    this.showPlayingAnimation = true,
    this.showProgressBar = false,
  });

  factory MenuBarSettings.fromJson(Map<String, dynamic> json) => MenuBarSettings(
      enabled: json['enabled'] as bool? ?? true,
      showPlayingAnimation: json['showPlayingAnimation'] as bool? ?? true,
      showProgressBar: json['showProgressBar'] as bool? ?? false,
    );

  /// 是否启用状态栏播放器（仅 macOS）
  final bool enabled;

  /// 播放时是否显示动画图标
  final bool showPlayingAnimation;

  /// 是否在状态栏显示迷你进度条
  final bool showProgressBar;

  MenuBarSettings copyWith({
    bool? enabled,
    bool? showPlayingAnimation,
    bool? showProgressBar,
  }) => MenuBarSettings(
      enabled: enabled ?? this.enabled,
      showPlayingAnimation: showPlayingAnimation ?? this.showPlayingAnimation,
      showProgressBar: showProgressBar ?? this.showProgressBar,
    );

  Map<String, dynamic> toJson() => {
      'enabled': enabled,
      'showPlayingAnimation': showPlayingAnimation,
      'showProgressBar': showProgressBar,
    };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MenuBarSettings &&
        other.enabled == enabled &&
        other.showPlayingAnimation == showPlayingAnimation &&
        other.showProgressBar == showProgressBar;
  }

  @override
  int get hashCode => Object.hash(enabled, showPlayingAnimation, showProgressBar);
}
