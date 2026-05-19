import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/app/theme/app_spacing.dart';
import 'package:my_nas/app/theme/color_scheme_preset.dart';

abstract final class AppTheme {
  /// 按平台返回 CJK 字体回退链。
  /// Flutter 默认走 Roboto，Roboto 不含 CJK 字形时由系统挑选 fallback，
  /// 不同字符可能命中不同字重的字体（如 Windows 上"媒体"走雅黑、"库"走宋体），
  /// 显式指定后所有中文字符强制走同一字体。
  static List<String> get _cjkFontFallback {
    if (kIsWeb) return const [];
    if (Platform.isWindows) {
      return const ['Microsoft YaHei UI', 'Microsoft YaHei', 'Segoe UI'];
    }
    if (Platform.isMacOS) {
      return const ['PingFang SC', 'Hiragino Sans GB', '.SF NS Text'];
    }
    if (Platform.isLinux) {
      return const ['Noto Sans CJK SC', 'WenQuanYi Micro Hei', 'Source Han Sans SC'];
    }
    return const [];
  }

  /// 根据配色预设生成浅色主题
  static ThemeData lightFromPreset(ColorSchemePreset preset) {
    final colorScheme = ColorScheme.light(
      primary: preset.primary,
      primaryContainer: preset.primaryLight,
      onPrimaryContainer: preset.primaryDark,
      secondary: preset.secondary,
      onSecondary: Colors.white,
      secondaryContainer: preset.secondaryLight,
      onSecondaryContainer: preset.primaryDark,
      tertiary: preset.accent,
      onTertiary: Colors.white,
      error: AppColors.error,
      onSurface: AppColors.lightOnSurface,
      surfaceContainerHighest: AppColors.lightSurfaceVariant,
      onSurfaceVariant: AppColors.lightOnSurfaceVariant,
      outline: AppColors.lightOutline,
      outlineVariant: AppColors.lightOutlineVariant,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      fontFamilyFallback: _cjkFontFallback,
      scaffoldBackgroundColor: AppColors.lightBackground,
      appBarTheme: _lightAppBarTheme,
      cardTheme: _lightCardTheme,
      elevatedButtonTheme: _elevatedButtonTheme,
      outlinedButtonTheme: _outlinedButtonTheme,
      textButtonTheme: _textButtonTheme,
      inputDecorationTheme: _buildLightInputTheme(preset.primary),
      dividerTheme: _lightDividerTheme,
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: AppColors.lightSurface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: preset.primaryLight,
      ),
      navigationRailTheme: NavigationRailThemeData(
        elevation: 0,
        backgroundColor: AppColors.lightSurface,
        indicatorColor: preset.primaryLight,
      ),
      bottomSheetTheme: _lightBottomSheetTheme,
      dialogTheme: _lightDialogTheme,
      snackBarTheme: _snackBarTheme,
      listTileTheme: _lightListTileTheme,
      scrollbarTheme: _lightScrollbarTheme,
    );
  }

  /// 根据配色预设生成深色主题
  static ThemeData darkFromPreset(ColorSchemePreset preset) {
    final colorScheme = ColorScheme.dark(
      primary: preset.primaryLight,
      onPrimary: preset.darkBackground,
      primaryContainer: preset.primary,
      onPrimaryContainer: Colors.white,
      secondary: preset.secondaryLight,
      onSecondary: preset.darkBackground,
      secondaryContainer: preset.secondary,
      onSecondaryContainer: Colors.white,
      tertiary: preset.accent,
      onTertiary: preset.darkBackground,
      error: AppColors.errorLight,
      onError: preset.darkBackground,
      surface: preset.darkSurface,
      onSurface: AppColors.darkOnSurface,
      surfaceContainerHighest: preset.darkSurfaceVariant,
      onSurfaceVariant: AppColors.darkOnSurfaceVariant,
      outline: preset.darkOutline,
      outlineVariant: preset.darkSurfaceElevated,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      fontFamilyFallback: _cjkFontFallback,
      scaffoldBackgroundColor: preset.darkBackground,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: preset.darkSurface,
        foregroundColor: AppColors.darkOnSurface,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: preset.darkSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.borderRadiusMd,
          side: BorderSide(color: preset.darkSurfaceElevated),
        ),
      ),
      elevatedButtonTheme: _elevatedButtonTheme,
      outlinedButtonTheme: _outlinedButtonTheme,
      textButtonTheme: _textButtonTheme,
      inputDecorationTheme: _buildDarkInputTheme(preset),
      dividerTheme: DividerThemeData(
        color: preset.darkSurfaceElevated,
        thickness: 1,
        space: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: preset.darkSurface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: preset.primary,
      ),
      navigationRailTheme: NavigationRailThemeData(
        elevation: 0,
        backgroundColor: preset.darkSurface,
        indicatorColor: preset.primary,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: preset.darkSurface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: preset.darkSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.borderRadiusLg,
        ),
      ),
      snackBarTheme: _snackBarTheme,
      listTileTheme: _darkListTileTheme,
      scrollbarTheme: _darkScrollbarTheme,
    );
  }

  /// 构建浅色输入框主题
  static InputDecorationTheme _buildLightInputTheme(Color primary) => InputDecorationTheme(
      filled: true,
      fillColor: AppColors.lightSurfaceVariant,
      border: OutlineInputBorder(
        borderRadius: AppRadius.borderRadiusSm,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppRadius.borderRadiusSm,
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppRadius.borderRadiusSm,
        borderSide: BorderSide(color: primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: AppRadius.borderRadiusSm,
        borderSide: const BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: AppRadius.borderRadiusSm,
        borderSide: const BorderSide(color: AppColors.error, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
    );

  /// 构建深色输入框主题
  static InputDecorationTheme _buildDarkInputTheme(ColorSchemePreset preset) => InputDecorationTheme(
      filled: true,
      fillColor: preset.darkSurfaceVariant,
      border: OutlineInputBorder(
        borderRadius: AppRadius.borderRadiusSm,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppRadius.borderRadiusSm,
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppRadius.borderRadiusSm,
        borderSide: BorderSide(color: preset.primaryLight, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: AppRadius.borderRadiusSm,
        borderSide: const BorderSide(color: AppColors.errorLight),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: AppRadius.borderRadiusSm,
        borderSide: const BorderSide(color: AppColors.errorLight, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
    );

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: _lightColorScheme,
        scaffoldBackgroundColor: AppColors.lightBackground,
        appBarTheme: _lightAppBarTheme,
        cardTheme: _lightCardTheme,
        elevatedButtonTheme: _elevatedButtonTheme,
        outlinedButtonTheme: _outlinedButtonTheme,
        textButtonTheme: _textButtonTheme,
        inputDecorationTheme: _lightInputDecorationTheme,
        dividerTheme: _lightDividerTheme,
        navigationBarTheme: _lightNavigationBarTheme,
        navigationRailTheme: _lightNavigationRailTheme,
        bottomSheetTheme: _lightBottomSheetTheme,
        dialogTheme: _lightDialogTheme,
        snackBarTheme: _snackBarTheme,
        listTileTheme: _lightListTileTheme,
        scrollbarTheme: _lightScrollbarTheme,
      );

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: _darkColorScheme,
        scaffoldBackgroundColor: AppColors.darkBackground,
        appBarTheme: _darkAppBarTheme,
        cardTheme: _darkCardTheme,
        elevatedButtonTheme: _elevatedButtonTheme,
        outlinedButtonTheme: _outlinedButtonTheme,
        textButtonTheme: _textButtonTheme,
        inputDecorationTheme: _darkInputDecorationTheme,
        dividerTheme: _darkDividerTheme,
        navigationBarTheme: _darkNavigationBarTheme,
        navigationRailTheme: _darkNavigationRailTheme,
        bottomSheetTheme: _darkBottomSheetTheme,
        dialogTheme: _darkDialogTheme,
        snackBarTheme: _snackBarTheme,
        listTileTheme: _darkListTileTheme,
        scrollbarTheme: _darkScrollbarTheme,
      );

  // ============================================================================
  // 平台检测
  // ============================================================================

  static bool get _isDesktop =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  // Color Schemes - 使用 getter 因为 AppColors 现在是动态的
  static ColorScheme get _lightColorScheme => ColorScheme.light(
        primary: AppColors.primary,
        primaryContainer: AppColors.primaryLight,
        onPrimaryContainer: AppColors.primaryDark,
        secondary: AppColors.secondary,
        onSecondary: Colors.white,
        secondaryContainer: AppColors.secondaryLight,
        onSecondaryContainer: AppColors.secondaryDark,
        tertiary: AppColors.tertiary,
        onTertiary: Colors.white,
        tertiaryContainer: AppColors.tertiaryLight,
        onTertiaryContainer: AppColors.tertiaryDark,
        error: AppColors.error,
        onSurface: AppColors.lightOnSurface,
        surfaceContainerHighest: AppColors.lightSurfaceVariant,
        onSurfaceVariant: AppColors.lightOnSurfaceVariant,
        outline: AppColors.lightOutline,
        outlineVariant: AppColors.lightOutlineVariant,
      );

  static ColorScheme get _darkColorScheme => ColorScheme.dark(
        primary: AppColors.primaryLight,
        onPrimary: AppColors.darkBackground,
        primaryContainer: AppColors.primary,
        onPrimaryContainer: Colors.white,
        secondary: AppColors.secondaryLight,
        onSecondary: AppColors.darkBackground,
        secondaryContainer: AppColors.secondary,
        onSecondaryContainer: Colors.white,
        tertiary: AppColors.tertiaryLight,
        onTertiary: AppColors.darkBackground,
        tertiaryContainer: AppColors.tertiary,
        onTertiaryContainer: Colors.white,
        error: AppColors.errorLight,
        onError: AppColors.darkBackground,
        surface: AppColors.darkSurface,
        onSurface: AppColors.darkOnSurface,
        surfaceContainerHighest: AppColors.darkSurfaceVariant,
        onSurfaceVariant: AppColors.darkOnSurfaceVariant,
        outline: AppColors.darkOutline,
        outlineVariant: AppColors.darkOutlineVariant,
      );

  // AppBar
  static const AppBarTheme _lightAppBarTheme = AppBarTheme(
    elevation: 0,
    scrolledUnderElevation: 1,
    backgroundColor: AppColors.lightSurface,
    foregroundColor: AppColors.lightOnSurface,
    surfaceTintColor: Colors.transparent,
  );

  static AppBarTheme get _darkAppBarTheme => AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: AppColors.darkSurface,
        foregroundColor: AppColors.darkOnSurface,
        surfaceTintColor: Colors.transparent,
      );

  // Card
  static final CardThemeData _lightCardTheme = CardThemeData(
    elevation: 0,
    color: AppColors.lightSurface,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: AppRadius.borderRadiusMd,
      side: const BorderSide(color: AppColors.lightOutlineVariant),
    ),
  );

  static CardThemeData get _darkCardTheme => CardThemeData(
        elevation: 0,
        color: AppColors.darkSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.borderRadiusMd,
          side: BorderSide(color: AppColors.darkOutlineVariant),
        ),
      );

  // Buttons
  static final ElevatedButtonThemeData _elevatedButtonTheme =
      ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      elevation: 0,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.md,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadius.borderRadiusSm,
      ),
    ),
  );

  static final OutlinedButtonThemeData _outlinedButtonTheme =
      OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.md,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadius.borderRadiusSm,
      ),
    ),
  );

  static final TextButtonThemeData _textButtonTheme = TextButtonThemeData(
    style: TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadius.borderRadiusSm,
      ),
    ),
  );

  // Input
  static InputDecorationTheme get _lightInputDecorationTheme =>
      InputDecorationTheme(
        filled: true,
        fillColor: AppColors.lightSurfaceVariant,
        border: OutlineInputBorder(
          borderRadius: AppRadius.borderRadiusSm,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.borderRadiusSm,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.borderRadiusSm,
          borderSide: BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.borderRadiusSm,
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.borderRadiusSm,
          borderSide: const BorderSide(color: AppColors.error, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
      );

  static InputDecorationTheme get _darkInputDecorationTheme =>
      InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkSurfaceVariant,
        border: OutlineInputBorder(
          borderRadius: AppRadius.borderRadiusSm,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.borderRadiusSm,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.borderRadiusSm,
          borderSide: BorderSide(color: AppColors.primaryLight, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.borderRadiusSm,
          borderSide: const BorderSide(color: AppColors.errorLight),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.borderRadiusSm,
          borderSide: const BorderSide(color: AppColors.errorLight, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
      );

  // Divider
  static const DividerThemeData _lightDividerTheme = DividerThemeData(
    color: AppColors.lightOutlineVariant,
    thickness: 1,
    space: 1,
  );

  static DividerThemeData get _darkDividerTheme => DividerThemeData(
        color: AppColors.darkOutlineVariant,
        thickness: 1,
        space: 1,
      );

  // Navigation Bar (Bottom)
  static NavigationBarThemeData get _lightNavigationBarTheme =>
      NavigationBarThemeData(
        elevation: 0,
        backgroundColor: AppColors.lightSurface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.primaryLight,
      );

  static NavigationBarThemeData get _darkNavigationBarTheme =>
      NavigationBarThemeData(
        elevation: 0,
        backgroundColor: AppColors.darkSurface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.primary,
      );

  // Navigation Rail (Desktop)
  static NavigationRailThemeData get _lightNavigationRailTheme =>
      NavigationRailThemeData(
        elevation: 0,
        backgroundColor: AppColors.lightSurface,
        indicatorColor: AppColors.primaryLight,
      );

  static NavigationRailThemeData get _darkNavigationRailTheme =>
      NavigationRailThemeData(
        elevation: 0,
        backgroundColor: AppColors.darkSurface,
        indicatorColor: AppColors.primary,
      );

  // Bottom Sheet
  static final BottomSheetThemeData _lightBottomSheetTheme =
      BottomSheetThemeData(
    backgroundColor: AppColors.lightSurface,
    surfaceTintColor: Colors.transparent,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
  );

  static BottomSheetThemeData get _darkBottomSheetTheme => BottomSheetThemeData(
        backgroundColor: AppColors.darkSurface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        ),
      );

  // Dialog
  static final DialogThemeData _lightDialogTheme = DialogThemeData(
    backgroundColor: AppColors.lightSurface,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: AppRadius.borderRadiusLg,
    ),
  );

  static DialogThemeData get _darkDialogTheme => DialogThemeData(
        backgroundColor: AppColors.darkSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.borderRadiusLg,
        ),
      );

  // SnackBar
  static final SnackBarThemeData _snackBarTheme = SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(
      borderRadius: AppRadius.borderRadiusSm,
    ),
  );

  // ListTile
  static final ListTileThemeData _lightListTileTheme = ListTileThemeData(
    shape: RoundedRectangleBorder(
      borderRadius: AppRadius.borderRadiusSm,
    ),
  );

  static final ListTileThemeData _darkListTileTheme = ListTileThemeData(
    shape: RoundedRectangleBorder(
      borderRadius: AppRadius.borderRadiusSm,
    ),
  );

  // ============================================================================
  // Scrollbar - 桌面端显示滚动条，移动端隐藏
  // ============================================================================

  static ScrollbarThemeData get _lightScrollbarTheme => ScrollbarThemeData(
        thumbVisibility: WidgetStateProperty.all(_isDesktop),
        trackVisibility: WidgetStateProperty.all(_isDesktop),
        thickness: WidgetStateProperty.resolveWith((states) {
          if (!_isDesktop) return 0;
          if (states.contains(WidgetState.hovered)) return 8;
          return 6;
        }),
        radius: const Radius.circular(4),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.dragged)) {
            return AppColors.lightOnSurfaceVariant.withValues(alpha: 0.6);
          }
          if (states.contains(WidgetState.hovered)) {
            return AppColors.lightOnSurfaceVariant.withValues(alpha: 0.5);
          }
          return AppColors.lightOnSurfaceVariant.withValues(alpha: 0.3);
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered)) {
            return AppColors.lightSurfaceVariant.withValues(alpha: 0.5);
          }
          return Colors.transparent;
        }),
        trackBorderColor: WidgetStateProperty.all(Colors.transparent),
        crossAxisMargin: 2,
        mainAxisMargin: 4,
        minThumbLength: 48,
        interactive: true,
      );

  static ScrollbarThemeData get _darkScrollbarTheme => ScrollbarThemeData(
        thumbVisibility: WidgetStateProperty.all(_isDesktop),
        trackVisibility: WidgetStateProperty.all(_isDesktop),
        thickness: WidgetStateProperty.resolveWith((states) {
          if (!_isDesktop) return 0;
          if (states.contains(WidgetState.hovered)) return 8;
          return 6;
        }),
        radius: const Radius.circular(4),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.dragged)) {
            return AppColors.darkOnSurfaceVariant.withValues(alpha: 0.6);
          }
          if (states.contains(WidgetState.hovered)) {
            return AppColors.darkOnSurfaceVariant.withValues(alpha: 0.5);
          }
          return AppColors.darkOnSurfaceVariant.withValues(alpha: 0.3);
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered)) {
            return AppColors.darkSurfaceVariant.withValues(alpha: 0.5);
          }
          return Colors.transparent;
        }),
        trackBorderColor: WidgetStateProperty.all(Colors.transparent),
        crossAxisMargin: 2,
        mainAxisMargin: 4,
        minThumbLength: 48,
        interactive: true,
      );
}
