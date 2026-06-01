import 'package:flutter/material.dart';

/// 配色方案预设
///
/// 桌面端重设计后强调色精简为 teal / blue / amber 三套，对齐
/// `design/my-nas/styles.css` 的 `--accent / --accent-bright / --accent-deep
/// / --accent-contrast` CSS 变量。
///
/// `ColorSchemePreset` 的字段保持原 schema 不变（涵盖 primary 三阶 + 多彩
/// 功能色 + 深色背景一组），方便 `AppColors` / `AppTheme` 等老 callsite
/// 沿用，无需大面积重构。新 token 体系（见 `design_tokens.dart`）会从这
/// 里取 `primary / primaryLight / primaryDark` 派生出 `accent / accentBright
/// / accentDeep`。
class ColorSchemePreset {
  const ColorSchemePreset({
    required this.id,
    required this.name,
    required this.description,
    required this.iconName,
    required this.primary,
    required this.primaryLight,
    required this.primaryDark,
    required this.secondary,
    required this.secondaryLight,
    required this.accent,
    required this.accentContrast,
    required this.music,
    required this.video,
    required this.photo,
    required this.book,
    required this.download,
    required this.subscription,
    required this.ai,
    required this.control,
    required this.darkBackground,
    required this.darkSurface,
    required this.darkSurfaceVariant,
    required this.darkSurfaceElevated,
    required this.darkOutline,
  });

  factory ColorSchemePreset.fromJson(Map<String, dynamic> json) =>
      ColorSchemePreset(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String,
        iconName: json['iconName'] as String,
        primary: Color(json['primary'] as int),
        primaryLight: Color(json['primaryLight'] as int),
        primaryDark: Color(json['primaryDark'] as int),
        secondary: Color(json['secondary'] as int),
        secondaryLight: Color(json['secondaryLight'] as int),
        accent: Color(json['accent'] as int),
        accentContrast: Color((json['accentContrast'] as int?) ?? 0xFF03241F),
        music: Color(json['music'] as int),
        video: Color(json['video'] as int),
        photo: Color(json['photo'] as int),
        book: Color(json['book'] as int),
        download: Color(json['download'] as int),
        subscription: Color(json['subscription'] as int),
        ai: Color(json['ai'] as int),
        control: Color(json['control'] as int),
        darkBackground: Color(json['darkBackground'] as int),
        darkSurface: Color(json['darkSurface'] as int),
        darkSurfaceVariant: Color(json['darkSurfaceVariant'] as int),
        darkSurfaceElevated: Color(json['darkSurfaceElevated'] as int),
        darkOutline: Color(json['darkOutline'] as int),
      );

  final String id;
  final String name;
  final String description;
  final String iconName;

  final Color primary;
  final Color primaryLight;
  final Color primaryDark;

  final Color secondary;
  final Color secondaryLight;

  final Color accent;
  final Color accentContrast;

  final Color music;
  final Color video;
  final Color photo;
  final Color book;
  final Color download;
  final Color subscription;
  final Color ai;
  final Color control;

  final Color darkBackground;
  final Color darkSurface;
  final Color darkSurfaceVariant;
  final Color darkSurfaceElevated;
  final Color darkOutline;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'iconName': iconName,
        'primary': primary.toARGB32(),
        'primaryLight': primaryLight.toARGB32(),
        'primaryDark': primaryDark.toARGB32(),
        'secondary': secondary.toARGB32(),
        'secondaryLight': secondaryLight.toARGB32(),
        'accent': accent.toARGB32(),
        'accentContrast': accentContrast.toARGB32(),
        'music': music.toARGB32(),
        'video': video.toARGB32(),
        'photo': photo.toARGB32(),
        'book': book.toARGB32(),
        'download': download.toARGB32(),
        'subscription': subscription.toARGB32(),
        'ai': ai.toARGB32(),
        'control': control.toARGB32(),
        'darkBackground': darkBackground.toARGB32(),
        'darkSurface': darkSurface.toARGB32(),
        'darkSurfaceVariant': darkSurfaceVariant.toARGB32(),
        'darkSurfaceElevated': darkSurfaceElevated.toARGB32(),
        'darkOutline': darkOutline.toARGB32(),
      };
}

/// 桌面端重设计统一中性深色背景（设计稿 ink 色阶，3 个 preset 共享）。
const Color _inkBackground = Color(0xFF08080A);
const Color _inkSurface = Color(0xFF141416);
const Color _inkSurfaceVariant = Color(0xFF19191C);
const Color _inkSurfaceElevated = Color(0xFF202024);
const Color _inkOutline = Color(0xFF29292E);

/// 多彩"功能色"在 3 套强调色之间保持稳定（音乐紫 / 视频粉 / 照片橙 / 图书蓝
/// / 漫画绿），仅用于内容类型 chip / icon 角标，不参与外壳取色。
const Color _kMusic = Color(0xFFC084FC);
const Color _kVideo = Color(0xFFEC4899);
const Color _kPhoto = Color(0xFFFB923C);
const Color _kBook = Color(0xFF60A5FA);
const Color _kDownload = Color(0xFF7DB1FF);
const Color _kSubscription = Color(0xFF8B5CF6);
const Color _kAi = Color(0xFF6366F1);
const Color _kControl = Color(0xFF60A5FA);

/// 预设配色方案集合
abstract final class ColorSchemePresets {
  /// Teal — 青绿，默认。
  /// CSS: --accent #1fbca8 / bright #57dcc9 / deep #0b6c60 / contrast #03241f
  static const teal = ColorSchemePreset(
    id: 'teal',
    name: '青绿',
    description: '清新现代，对应设计稿默认 accent',
    iconName: 'spa',
    primary: Color(0xFF1FBCA8),
    primaryLight: Color(0xFF57DCC9),
    primaryDark: Color(0xFF0B6C60),
    secondary: Color(0xFF1FBCA8),
    secondaryLight: Color(0xFF57DCC9),
    accent: Color(0xFF1FBCA8),
    accentContrast: Color(0xFF03241F),
    music: _kMusic,
    video: _kVideo,
    photo: _kPhoto,
    book: _kBook,
    download: _kDownload,
    subscription: _kSubscription,
    ai: _kAi,
    control: _kControl,
    darkBackground: _inkBackground,
    darkSurface: _inkSurface,
    darkSurfaceVariant: _inkSurfaceVariant,
    darkSurfaceElevated: _inkSurfaceElevated,
    darkOutline: _inkOutline,
  );

  /// Blue — 经典蓝。
  /// CSS: --accent #5a92f0 / bright #9cc0ff / deep #2a5ec2 / contrast #ffffff
  static const blue = ColorSchemePreset(
    id: 'blue',
    name: '海蓝',
    description: '专业稳重，对应设计稿 blue accent',
    iconName: 'water_drop',
    primary: Color(0xFF5A92F0),
    primaryLight: Color(0xFF9CC0FF),
    primaryDark: Color(0xFF2A5EC2),
    secondary: Color(0xFF5A92F0),
    secondaryLight: Color(0xFF9CC0FF),
    accent: Color(0xFF5A92F0),
    accentContrast: Color(0xFFFFFFFF),
    music: _kMusic,
    video: _kVideo,
    photo: _kPhoto,
    book: _kBook,
    download: _kDownload,
    subscription: _kSubscription,
    ai: _kAi,
    control: _kControl,
    darkBackground: _inkBackground,
    darkSurface: _inkSurface,
    darkSurfaceVariant: _inkSurfaceVariant,
    darkSurfaceElevated: _inkSurfaceElevated,
    darkOutline: _inkOutline,
  );

  /// Amber — 暖琥珀。
  /// CSS: --accent #e8a13a / bright #ffc568 / deep #a8680f / contrast #2a1801
  static const amber = ColorSchemePreset(
    id: 'amber',
    name: '琥珀',
    description: '温暖活力，对应设计稿 amber accent',
    iconName: 'wb_sunny',
    primary: Color(0xFFE8A13A),
    primaryLight: Color(0xFFFFC568),
    primaryDark: Color(0xFFA8680F),
    secondary: Color(0xFFE8A13A),
    secondaryLight: Color(0xFFFFC568),
    accent: Color(0xFFE8A13A),
    accentContrast: Color(0xFF2A1801),
    music: _kMusic,
    video: _kVideo,
    photo: _kPhoto,
    book: _kBook,
    download: _kDownload,
    subscription: _kSubscription,
    ai: _kAi,
    control: _kControl,
    darkBackground: _inkBackground,
    darkSurface: _inkSurface,
    darkSurfaceVariant: _inkSurfaceVariant,
    darkSurfaceElevated: _inkSurfaceElevated,
    darkOutline: _inkOutline,
  );

  /// 所有可选预设。
  static const List<ColorSchemePreset> all = [teal, blue, amber];

  /// 根据 ID 获取预设。旧 id（ocean/sunset/forest 等）找不到返回 null，
  /// 由 `ColorSchemePresetNotifier._loadFromStorage` 兜底回 [teal]。
  static ColorSchemePreset? getById(String id) {
    try {
      return all.firstWhere((preset) => preset.id == id);
    } catch (_) {
      return null;
    }
  }

  /// 默认预设。
  static const ColorSchemePreset defaultPreset = teal;
}
