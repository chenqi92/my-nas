import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/color_scheme_preset.dart';

/// 应用颜色配置
/// 支持动态配色方案切换
abstract final class AppColors {
  /// 当前配色方案 - 由 Provider 在应用启动时设置
  static ColorSchemePreset _currentPreset = ColorSchemePresets.defaultPreset;

  /// 获取当前配色方案
  static ColorSchemePreset get currentPreset => _currentPreset;

  /// 设置当前配色方案（由 Provider 调用）
  static void setPreset(ColorSchemePreset preset) {
    _currentPreset = preset;
  }

  // ============ 动态主题色（根据配色方案变化）============

  /// 主色
  static Color get primary => _currentPreset.primary;
  static Color get primaryLight => _currentPreset.primaryLight;
  static Color get primaryDark => _currentPreset.primaryDark;

  /// 次要色
  static Color get secondary => _currentPreset.secondary;
  static Color get secondaryLight => _currentPreset.secondaryLight;

  /// 强调色
  static Color get accent => _currentPreset.accent;

  /// 渐变色 - 动态
  static LinearGradient get primaryGradient => LinearGradient(
        colors: [primary, secondary],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static LinearGradient get accentGradient => LinearGradient(
        colors: [accent, primary],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  // ============ 动态深色背景（根据配色方案变化）============

  static Color get darkBackground => _currentPreset.darkBackground;
  static Color get darkSurface => _currentPreset.darkSurface;
  static Color get darkSurfaceVariant => _currentPreset.darkSurfaceVariant;
  static Color get darkSurfaceElevated => _currentPreset.darkSurfaceElevated;
  static Color get darkOutline => _currentPreset.darkOutline;
  static Color get darkOutlineVariant => _currentPreset.darkSurfaceElevated;

  static LinearGradient get darkGradient => LinearGradient(
        colors: [darkSurface, darkBackground],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      );

  // ============ 功能性颜色（根据配色方案变化）============

  /// 音乐类型颜色
  static Color get musicColor => _currentPreset.music;

  /// 视频类型颜色
  static Color get videoColor => _currentPreset.video;

  /// 照片类型颜色
  static Color get photoColor => _currentPreset.photo;

  /// 图书类型颜色
  static Color get bookColor => _currentPreset.book;

  /// 下载颜色
  static Color get downloadColor => _currentPreset.download;

  /// 订阅颜色
  static Color get subscriptionColor => _currentPreset.subscription;

  /// AI 功能颜色
  static Color get aiColor => _currentPreset.ai;

  /// 控制设置颜色
  static Color get controlColor => _currentPreset.control;

  // ============ 静态颜色（不随配色方案变化）============

  // Tertiary colors (Amber) - 暖色点缀
  static const Color tertiary = Color(0xFFF59E0B);
  static const Color tertiaryLight = Color(0xFFFBBF24);
  static const Color tertiaryDark = Color(0xFFD97706);

  // 浅色模式背景（固定）
  static const Color lightBackground = Color(0xFFF8FAFC);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceVariant = Color(0xFFF1F5F9);
  static const Color lightOnSurface = Color(0xFF1E293B);
  static const Color lightOnSurfaceVariant = Color(0xFF64748B);
  static const Color lightOutline = Color(0xFFCBD5E1);
  static const Color lightOutlineVariant = Color(0xFFE2E8F0);

  // 深色模式文字颜色（固定）
  static const Color darkOnSurface = Color(0xFFF1F5F9);
  static const Color darkOnSurfaceVariant = Color(0xFF9CA3AF);

  // 语义化颜色（固定）
  static const Color error = Color(0xFFEF4444);
  static const Color errorLight = Color(0xFFFCA5A5);
  static const Color errorDark = Color(0xFFDC2626);

  static const Color success = Color(0xFF22C55E);
  static const Color successLight = Color(0xFF86EFAC);
  static const Color successDark = Color(0xFF16A34A);

  static const Color warning = Color(0xFFF59E0B);
  static const Color warningLight = Color(0xFFFCD34D);
  static const Color warningDark = Color(0xFFD97706);

  static const Color info = Color(0xFF3B82F6);
  static const Color infoLight = Color(0xFF93C5FD);
  static const Color infoDark = Color(0xFF2563EB);

  // 禁用状态颜色
  static const Color disabled = Color(0xFF9CA3AF);
  static const Color disabledLight = Color(0xFFD1D5DB);

  // 评分颜色（固定）- 用于显示高/中/低评分
  static const Color ratingHigh = Color(0xFF22C55E);   // ≥8 分 - 绿色
  static const Color ratingMid = Color(0xFFF59E0B);    // 6-8 分 - 橙色
  static const Color ratingLow = Color(0xFFEF4444);    // <6 分 - 红色

  /// 根据评分获取对应颜色
  static Color ratingColor(double rating) {
    if (rating >= 8) return ratingHigh;
    if (rating >= 6) return ratingMid;
    return ratingLow;
  }

  // 认证/启动页背景渐变（固定）- startup_page 与 connection_page 共用
  static const List<Color> authBackgroundGradient = [
    Color(0xFF0F0F1A),
    Color(0xFF1A1A2E),
    Color(0xFF16213E),
    Color(0xFF0F0F1A),
  ];

  // 玻璃效果颜色（固定）
  static const Color glassLight = Color(0x1AFFFFFF);
  static const Color glassDark = Color(0x1A000000);
  static const Color glassStroke = Color(0x33FFFFFF);

  // 文件类型颜色（固定）
  static const Color fileFolder = Color(0xFFFBBF24);
  static const Color fileImage = Color(0xFF10B981);
  static const Color fileVideo = Color(0xFFEC4899);
  static const Color fileAudio = Color(0xFF8B5CF6);
  static const Color fileDocument = Color(0xFF3B82F6);
  static const Color fileArchive = Color(0xFFF59E0B);
  static const Color fileCode = Color(0xFF06B6D4);
  static const Color fileOther = Color(0xFF64748B);

  // ============ 兼容性：静态默认颜色（用于 const 上下文）============
  // 这些颜色用于需要 const 的地方，不会随配色方案变化

  static const Color accentLight = Color(0xFF22D3EE);
  static const Color accentDark = Color(0xFF0891B2);
  static const Color secondaryDark = Color(0xFF0891B2);
}
