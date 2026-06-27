// design_tokens.dart 中按 brightness × uiStyle × preset 组合工厂构造刻意
// 放在字段后面，紧邻 lerp/copyWith 一起读更直观，因此关闭 sort_constructors_first。
// ignore_for_file: sort_constructors_first
import 'package:flutter/material.dart';
import 'package:my_nas/app/theme/color_scheme_preset.dart';
import 'package:my_nas/app/theme/ui_style.dart';

/// 桌面端重设计的视觉 token 系统。
///
/// 对应 `design/my-nas/styles.css` 中的 CSS 变量：
///   html[data-theme=dark|light][data-style=glass|classic]
///
/// 4 套材质（dark/light × glass/classic）共享同一组字段，按 `Brightness +
/// UIStyle + ColorSchemePreset` 组合生成。所有"新桌面外壳 + 桌面变体 page +
/// atoms"都从这里读，不再到处订阅 provider；ColorSchemePreset / themeMode /
/// uiStyle 在 `app.dart` 注入 `MaterialApp.theme.extensions`，一处改、全局
/// 通过 `Theme.of(c).extension<DesignTokens>()!` 取到。
@immutable
class DesignTokens extends ThemeExtension<DesignTokens> {
  const DesignTokens({
    required this.text0,
    required this.text1,
    required this.text2,
    required this.text3,
    required this.bg,
    required this.bgStrong,
    required this.panelBg,
    required this.panelBgStrong,
    required this.panelBlurSigma,
    required this.panelBorder,
    required this.cardBg,
    required this.cardBgHover,
    required this.cardBorder,
    required this.insetBg,
    required this.hairline,
    required this.chipBg,
    required this.chipBgActive,
    required this.sidebarBg,
    required this.segOnBg,
    required this.accent,
    required this.accentBright,
    required this.accentDeep,
    required this.accentContrast,
    required this.ok,
    required this.warn,
    required this.err,
    required this.info,
    required this.hot,
  });

  // ===== 文本 =====
  /// 主文本（最强）。
  final Color text0;

  /// 次级文本。
  final Color text1;

  /// 弱化文本（描述、辅助）。
  final Color text2;

  /// 极弱文本（占位、提示）。
  final Color text3;

  // ===== 背景层 =====
  /// 应用底色（最底层，可叠 ambient）。
  final Color bg;

  /// 应用强调底色（用于 sheet 后景等）。
  final Color bgStrong;

  // ===== 面板（玻璃 .panel / 经典实色）=====
  /// 一般面板背景：玻璃下半透明 + blur，经典下不透明。
  final Color panelBg;

  /// 强调面板背景（dock / drawer 等浮层用）。
  final Color panelBgStrong;

  /// 玻璃模糊半径。`0` 表示不模糊（经典模式）。
  final double panelBlurSigma;

  /// 面板描边色。
  final Color panelBorder;

  // ===== 卡片 .card =====
  final Color cardBg;
  final Color cardBgHover;
  final Color cardBorder;

  // ===== 内嵌底（input / segmented track）=====
  final Color insetBg;

  /// 极细分割线。
  final Color hairline;

  // ===== Chip =====
  final Color chipBg;
  final Color chipBgActive;

  // ===== Sidebar 专用 =====
  final Color sidebarBg;

  /// segmented control 选中态底色。
  final Color segOnBg;

  // ===== 强调色（从 ColorSchemePreset 派生）=====
  /// 主强调色。
  final Color accent;

  /// 亮一档（hover / 高亮文字）。
  final Color accentBright;

  /// 暗一档（按下 / 渐变深端）。
  final Color accentDeep;

  /// 在 accent 上的可读文字色。
  final Color accentContrast;

  // ===== 状态色 =====
  final Color ok;
  final Color warn;
  final Color err;
  final Color info;

  /// 直播 / 紧急的红，独立于 accent。
  final Color hot;

  // ===== 静态度量 / 曲线（不参与 lerp，全 token 共享）=====
  static const double railW = 76;
  static const double navW = 248;
  static const double topbarH = 56;
  static const double dockH = 72;

  static const double radiusXs = 5;
  static const double radiusSm = 7;
  static const double radius = 8;
  static const double radiusLg = 12;
  static const double radiusXl = 18;

  /// 与 `--ease: cubic-bezier(.22,.61,.36,1)` 对齐。
  static const Curve ease = Cubic(0.22, 0.61, 0.36, 1);

  /// 与 `--ease-out: cubic-bezier(.16,1,.3,1)` 对齐。
  static const Curve easeOut = Cubic(0.16, 1, 0.3, 1);

  /// 在任意 BuildContext 下取 token；fallback 为 dark/glass/teal 组合，
  /// 防止某些早期 build 阶段 `Theme.of` 还没装 extension 时崩溃。
  static DesignTokens of(BuildContext context) =>
      Theme.of(context).extension<DesignTokens>() ?? _fallback;

  /// 同步生成 4 套材质 × 3 套强调色之一的 token。
  ///
  /// [blurScale] / [opacityScale] / [blurEnabled] 为「玻璃材质参数」，仅影响
  /// glass 工厂；默认值保持现状（缩放 1.0、启用模糊），所有既有调用方行为不变。
  /// classic 工厂完全不受影响。
  factory DesignTokens.build({
    required Brightness brightness,
    required UIStyle uiStyle,
    required ColorSchemePreset preset,
    double blurScale = 1.0,
    double opacityScale = 1.0,
    bool blurEnabled = true,
  }) {
    final isDark = brightness == Brightness.dark;
    final isGlass = uiStyle.isGlass;

    if (isDark && isGlass) {
      return DesignTokens._darkGlass(
        preset,
        blurScale: blurScale,
        opacityScale: opacityScale,
        blurEnabled: blurEnabled,
      );
    }
    if (isDark && !isGlass) {
      return DesignTokens._darkClassic(preset);
    }
    if (!isDark && isGlass) {
      return DesignTokens._lightGlass(
        preset,
        blurScale: blurScale,
        opacityScale: opacityScale,
        blurEnabled: blurEnabled,
      );
    }
    return DesignTokens._lightClassic(preset);
  }

  /// 把玻璃材质不透明度缩放作用到面板背景色 alpha 上（clamp 0–1）。
  static Color _scaleAlpha(Color color, double opacityScale) =>
      color.withValues(alpha: (color.a * opacityScale).clamp(0.0, 1.0));

  // ---- dark × glass ----
  factory DesignTokens._darkGlass(
    ColorSchemePreset p, {
    double blurScale = 1.0,
    double opacityScale = 1.0,
    bool blurEnabled = true,
  }) => DesignTokens(
    text0: const Color(0xFFF6F6F7),
    text1: const Color(0xFFC8C8CB),
    text2: const Color(0xFF8B8B90),
    text3: const Color(0xFF5A5A60),
    bg: const Color(0xFF08080A),
    bgStrong: const Color(0xFF0E0F12),
    // rgba(27,28,33,.60)
    panelBg: _scaleAlpha(const Color(0x991B1C21), opacityScale),
    // rgba(19,20,24,.82)
    panelBgStrong: _scaleAlpha(const Color(0xD1131418), opacityScale),
    panelBlurSigma: (blurEnabled ? 30.0 : 0.0) * blurScale,
    panelBorder: const Color(0x14FFFFFF), // rgba(255,255,255,.08)
    cardBg: const Color(0x9926282E),
    cardBgHover: const Color(0xCC32343C),
    cardBorder: const Color(0x12FFFFFF),
    insetBg: const Color(0x4D000000),
    hairline: const Color(0x13FFFFFF),
    chipBg: const Color(0x0FFFFFFF),
    chipBgActive: _tint(p.primary, 0.15),
    sidebarBg: const Color(0x6B16171C),
    segOnBg: const Color(0xFF46474D),
    accent: p.primary,
    accentBright: p.primaryLight,
    accentDeep: p.primaryDark,
    accentContrast: p.accentContrast,
    ok: const Color(0xFF33C79A),
    warn: const Color(0xFFE0AD44),
    err: const Color(0xFFEC6A64),
    info: const Color(0xFF5F9BEF),
    hot: const Color(0xFFE0322E),
  );

  // ---- dark × classic ----
  factory DesignTokens._darkClassic(ColorSchemePreset p) => DesignTokens(
    text0: const Color(0xFFF6F6F7),
    text1: const Color(0xFFC8C8CB),
    text2: const Color(0xFF8B8B90),
    text3: const Color(0xFF5A5A60),
    bg: const Color(0xFF0B0B0E),
    bgStrong: const Color(0xFF15161B),
    panelBg: const Color(0xFF17181D),
    panelBgStrong: const Color(0xFF121216),
    panelBlurSigma: 0,
    panelBorder: const Color(0xFF292A31),
    cardBg: const Color(0xFF1B1C22),
    cardBgHover: const Color(0xFF25262E),
    cardBorder: const Color(0xFF2C2D35),
    insetBg: const Color(0xFF0D0D11),
    hairline: const Color(0xFF232429),
    chipBg: const Color(0xFF1F2026),
    chipBgActive: _tint(p.primary, 0.17),
    sidebarBg: const Color(0xFF131419),
    segOnBg: const Color(0xFF3A3B42),
    accent: p.primary,
    accentBright: p.primaryLight,
    accentDeep: p.primaryDark,
    accentContrast: p.accentContrast,
    ok: const Color(0xFF33C79A),
    warn: const Color(0xFFE0AD44),
    err: const Color(0xFFEC6A64),
    info: const Color(0xFF5F9BEF),
    hot: const Color(0xFFE0322E),
  );

  // ---- light × glass ----
  factory DesignTokens._lightGlass(
    ColorSchemePreset p, {
    double blurScale = 1.0,
    double opacityScale = 1.0,
    bool blurEnabled = true,
  }) => DesignTokens(
    text0: const Color(0xFF1B1B1F),
    text1: const Color(0xFF45454C),
    text2: const Color(0xFF6F6F78),
    text3: const Color(0xFF9C9CA4),
    bg: const Color(0xFFF3F5F7),
    bgStrong: const Color(0xFFFAFBFC),
    panelBg: _scaleAlpha(const Color(0xE6FFFFFF), opacityScale),
    panelBgStrong: _scaleAlpha(const Color(0xF7FFFFFF), opacityScale),
    panelBlurSigma: (blurEnabled ? 26.0 : 0.0) * blurScale,
    panelBorder: const Color(0x1422313F),
    cardBg: const Color(0xF2FFFFFF),
    cardBgHover: const Color(0xFFFFFFFF),
    cardBorder: const Color(0x1222313F),
    insetBg: const Color(0x0A0C1F2E),
    hairline: const Color(0x1022313F),
    chipBg: const Color(0x0A0C1F2E),
    chipBgActive: _tint(p.primaryDark, 0.10),
    sidebarBg: const Color(0xE8F0F3F6),
    segOnBg: const Color(0xFFFFFFFF),
    accent: p.primary,
    accentBright: p.primaryDark, // light 下用 deep 做可读高亮
    accentDeep: p.primaryDark,
    accentContrast: p.accentContrast,
    ok: const Color(0xFF1F9D6B),
    warn: const Color(0xFFBD7D18),
    err: const Color(0xFFCF4239),
    info: const Color(0xFF2F6FD0),
    hot: const Color(0xFFCB2D2A),
  );

  // ---- light × classic ----
  factory DesignTokens._lightClassic(ColorSchemePreset p) => DesignTokens(
    text0: const Color(0xFF1B1B1F),
    text1: const Color(0xFF45454C),
    text2: const Color(0xFF6F6F78),
    text3: const Color(0xFF9C9CA4),
    bg: const Color(0xFFF3F5F7),
    bgStrong: const Color(0xFFFAFBFC),
    panelBg: const Color(0xFFFDFEFF),
    panelBgStrong: const Color(0xFFFFFFFF),
    panelBlurSigma: 0,
    panelBorder: const Color(0xFFE6EBF0),
    cardBg: const Color(0xFFFDFEFF),
    cardBgHover: const Color(0xFFFFFFFF),
    cardBorder: const Color(0xFFE8EDF2),
    insetBg: const Color(0xFFEEF2F5),
    hairline: const Color(0xFFE8EDF2),
    chipBg: const Color(0xFFEEF2F5),
    chipBgActive: _tint(p.primaryDark, 0.10),
    sidebarBg: const Color(0xFFF0F4F7),
    segOnBg: const Color(0xFFFFFFFF),
    accent: p.primary,
    accentBright: p.primaryDark,
    accentDeep: p.primaryDark,
    accentContrast: p.accentContrast,
    ok: const Color(0xFF1F9D6B),
    warn: const Color(0xFFBD7D18),
    err: const Color(0xFFCF4239),
    info: const Color(0xFF2F6FD0),
    hot: const Color(0xFFCB2D2A),
  );

  static Color _tint(Color base, double alpha) => base.withValues(alpha: alpha);

  @override
  DesignTokens copyWith({
    Color? text0,
    Color? text1,
    Color? text2,
    Color? text3,
    Color? bg,
    Color? bgStrong,
    Color? panelBg,
    Color? panelBgStrong,
    double? panelBlurSigma,
    Color? panelBorder,
    Color? cardBg,
    Color? cardBgHover,
    Color? cardBorder,
    Color? insetBg,
    Color? hairline,
    Color? chipBg,
    Color? chipBgActive,
    Color? sidebarBg,
    Color? segOnBg,
    Color? accent,
    Color? accentBright,
    Color? accentDeep,
    Color? accentContrast,
    Color? ok,
    Color? warn,
    Color? err,
    Color? info,
    Color? hot,
  }) => DesignTokens(
    text0: text0 ?? this.text0,
    text1: text1 ?? this.text1,
    text2: text2 ?? this.text2,
    text3: text3 ?? this.text3,
    bg: bg ?? this.bg,
    bgStrong: bgStrong ?? this.bgStrong,
    panelBg: panelBg ?? this.panelBg,
    panelBgStrong: panelBgStrong ?? this.panelBgStrong,
    panelBlurSigma: panelBlurSigma ?? this.panelBlurSigma,
    panelBorder: panelBorder ?? this.panelBorder,
    cardBg: cardBg ?? this.cardBg,
    cardBgHover: cardBgHover ?? this.cardBgHover,
    cardBorder: cardBorder ?? this.cardBorder,
    insetBg: insetBg ?? this.insetBg,
    hairline: hairline ?? this.hairline,
    chipBg: chipBg ?? this.chipBg,
    chipBgActive: chipBgActive ?? this.chipBgActive,
    sidebarBg: sidebarBg ?? this.sidebarBg,
    segOnBg: segOnBg ?? this.segOnBg,
    accent: accent ?? this.accent,
    accentBright: accentBright ?? this.accentBright,
    accentDeep: accentDeep ?? this.accentDeep,
    accentContrast: accentContrast ?? this.accentContrast,
    ok: ok ?? this.ok,
    warn: warn ?? this.warn,
    err: err ?? this.err,
    info: info ?? this.info,
    hot: hot ?? this.hot,
  );

  @override
  DesignTokens lerp(ThemeExtension<DesignTokens>? other, double t) {
    if (other is! DesignTokens) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t) ?? a;
    return DesignTokens(
      text0: l(text0, other.text0),
      text1: l(text1, other.text1),
      text2: l(text2, other.text2),
      text3: l(text3, other.text3),
      bg: l(bg, other.bg),
      bgStrong: l(bgStrong, other.bgStrong),
      panelBg: l(panelBg, other.panelBg),
      panelBgStrong: l(panelBgStrong, other.panelBgStrong),
      panelBlurSigma:
          panelBlurSigma + (other.panelBlurSigma - panelBlurSigma) * t,
      panelBorder: l(panelBorder, other.panelBorder),
      cardBg: l(cardBg, other.cardBg),
      cardBgHover: l(cardBgHover, other.cardBgHover),
      cardBorder: l(cardBorder, other.cardBorder),
      insetBg: l(insetBg, other.insetBg),
      hairline: l(hairline, other.hairline),
      chipBg: l(chipBg, other.chipBg),
      chipBgActive: l(chipBgActive, other.chipBgActive),
      sidebarBg: l(sidebarBg, other.sidebarBg),
      segOnBg: l(segOnBg, other.segOnBg),
      accent: l(accent, other.accent),
      accentBright: l(accentBright, other.accentBright),
      accentDeep: l(accentDeep, other.accentDeep),
      accentContrast: l(accentContrast, other.accentContrast),
      ok: l(ok, other.ok),
      warn: l(warn, other.warn),
      err: l(err, other.err),
      info: l(info, other.info),
      hot: l(hot, other.hot),
    );
  }

  /// 没有 `Theme.of` 装载 token 时的兜底（dark/glass/teal）。
  static final DesignTokens _fallback = DesignTokens._darkGlass(
    ColorSchemePresets.teal,
  );
}
