/// Shell 外壳的选择结果。
///
/// [MainScaffold] 有四条互斥的外壳分支，判定条件散在一串 if / else if 里且
/// 顺序敏感（TV 必须先于桌面判，否则在电视上按屏宽会走成桌面 Rail）。这里把
/// 「选哪个外壳」抽成纯函数，便于单测穷举组合，不用搭出真实的 GoRouter 外壳。
library;

/// 四种外壳形态。
enum ShellLayout {
  /// TV：左侧 Rail + overscan 安全区 + D-pad 焦点导航。
  tv,

  /// 桌面：sidebar + topbar + 紧凑视觉密度。
  desktop,

  /// iOS 玻璃风格：原生 UITabBar，Flutter 侧不画底栏。
  nativeTabBar,

  /// 其余情况：Flutter 自绘底部导航栏。
  bottomNav,
}

/// 依据平台 / 布局 / UI 风格选择外壳。
///
/// 判定顺序即优先级，不能重排：
/// 1. [isTvLayout] —— 电视的逻辑宽度常与桌面重合，若先判桌面会在电视上走成
///    桌面 Rail（鼠标悬停交互、无 overscan），遥控器根本用不了。
/// 2. [isDesktopLayout] —— 桌面平台（与屏宽解耦，缩窗口不退化成手机布局）。
/// 3. [useNativeTabBar] —— 仅 iOS 玻璃风格可达。
/// 4. 兜底 [ShellLayout.bottomNav]。
ShellLayout resolveShellLayout({
  required bool isTvLayout,
  required bool isDesktopLayout,
  required bool useNativeTabBar,
}) {
  if (isTvLayout) return ShellLayout.tv;
  if (isDesktopLayout) return ShellLayout.desktop;
  if (useNativeTabBar) return ShellLayout.nativeTabBar;
  return ShellLayout.bottomNav;
}

/// 该外壳是否由 Flutter 自绘底部导航栏。
///
/// TV / 桌面 / 原生 TabBar 三种外壳都不画：TV 上底栏既不可聚焦也会被电视边缘
/// 裁切，是 A7 gating 的一部分。
bool shellShowsBottomNav(ShellLayout layout) => layout == ShellLayout.bottomNav;
