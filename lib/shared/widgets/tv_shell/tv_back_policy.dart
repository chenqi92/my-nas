/// TV 遥控器 BACK 键的逐级降级（escalation）策略。
///
/// 电视遥控器只有一个 BACK 键，没有手机的边缘返回手势，也没有桌面 Esc + 关窗口
/// 两条通路。因此同一个键要按栈深度依次承担「关模态 / 退详情 / 回首页 Tab /
/// 退出应用」四种语义，顺序不能错：先消费掉栈内的东西，最后才允许退出应用。
///
/// 本文件只做纯决策（输入栈状态 → 输出动作），不碰 Navigator，方便单测覆盖
/// 各种栈组合；实际执行在 [TvBackHandler]（tv_scaffold 侧）。
library;

/// BACK 键在当前栈状态下应该执行的动作。
enum TvBackAction {
  /// 关闭顶层模态（root navigator 有可 pop 的路由）。
  popRoot,

  /// 退出当前 branch 内 push 的页面（详情 / 播放器 / 工具页）。
  popBranch,

  /// 已在 branch 栈底但不在首个 Tab：先回到首个 Tab，而不是直接退出应用。
  goHomeBranch,

  /// 已在首个 Tab 的栈底：交还给系统（Android 上即退出应用）。
  exitApp,
}

/// 依据栈状态决定 BACK 的动作。
///
/// 判定顺序即降级顺序：
/// 1. [rootCanPop] —— 顶层模态（dialog / bottom sheet / 全屏 push）最先被关掉，
///    否则用户会看到底层 Tab 在模态后面切换。
/// 2. [branchCanPop] —— 当前 Tab 内 push 的详情页。
/// 3. 不在 [isHomeBranch] —— 回到首个 Tab。电视上「BACK 一路按到底应该回首页」
///    是平台惯例（Android TV 的 leanback 指南），直接退出会让用户误以为闪退。
/// 4. 兜底 [TvBackAction.exitApp]。
TvBackAction resolveTvBackAction({
  required bool rootCanPop,
  required bool branchCanPop,
  required bool isHomeBranch,
}) {
  if (rootCanPop) return TvBackAction.popRoot;
  if (branchCanPop) return TvBackAction.popBranch;
  if (!isHomeBranch) return TvBackAction.goHomeBranch;
  return TvBackAction.exitApp;
}
