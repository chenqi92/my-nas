abstract final class Routes {
  // Startup
  static const String startup = '/';

  // Auth & Connection
  static const String connection = '/connection';

  // 桌面端新增 — Home / Live / Ops
  static const String home = '/home';
  static const String live = '/live';
  static const String ops = '/ops';

  // Main tabs (5 items: video, music, photo, reading, mine)
  static const String video = '/video';
  static const String music = '/music';
  static const String photo = '/photo';
  static const String reading = '/reading';
  static const String mine = '/mine';

  // 桌面端工具区 branch（仅 NavigationRail 显示，移动端走 mine 页 tile 入口）
  static const String download = '/download';
  static const String transfer = '/transfer';
  static const String sources = '/sources';
  static const String pt = '/pt';
  static const String nastool = '/nastool';

  // Legacy routes (kept for compatibility)
  static const String files = '/files';
  static const String book = '/book';
  static const String note = '/note';

  // Sub routes
  static const String videoPlayer = '/video/player';
  static const String musicPlayer = '/music/player';
  static const String photoViewer = '/photo/viewer';
  static const String comicReader = '/comic/reader';
  static const String bookReader = '/book/reader';
  static const String noteEditor = '/note/editor';
}

/// StatefulShellRoute 各 branch 的 index 命名常量。
///
/// 调用 `navigationShell.goBranch(...)` 时引用，避免硬编码数字在 14 branch
/// 重排后失配（历史上曾把「跳到设置」误写成 `goBranch(4)`，实际落到 photo）。
///
/// 这是 branch 顺序的**单一事实来源**：[branchRoutes]、`app_router.dart` 的
/// `branchNavigatorKeys` 与 `branches`、`desktop_scaffold` 的导航映射都必须与此一致，
/// `test/app/branch_index_test.dart` 会校验三者同步。
abstract final class AppBranch {
  static const int home = 0;
  static const int video = 1;
  static const int live = 2;
  static const int music = 3;
  static const int photo = 4;
  static const int reading = 5;
  static const int mine = 6;
  static const int ops = 7;
  static const int download = 8;
  static const int transfer = 9;
  static const int sources = 10;
  static const int pt = 11;
  static const int nastool = 12;
  static const int files = 13;

  /// branch 总数。
  static const int count = 14;
}

/// iOS/Android 底部 5 个主 Tab 对应的全局 branch 索引。
///
/// 原生 iOS Tab Bar 使用 0..4 的局部索引，不能直接传入
/// StatefulShellRoute 的 14 个全局 branch 索引。
const List<int> mobileMainTabBranches = <int>[
  AppBranch.video,
  AppBranch.music,
  AppBranch.photo,
  AppBranch.reading,
  AppBranch.mine,
];

/// 把全局 branch 索引转换为移动端底部 Tab 的 0..4 索引。
/// 工具页等非主 Tab branch 返回 null，保留原有选中项。
int? mobileMainTabIndexForBranch(int branchIndex) {
  final index = mobileMainTabBranches.indexOf(branchIndex);
  return index < 0 ? null : index;
}

/// branch index → 路由路径（与 [AppBranch] 同序）。供需要「按 branch index 反查
/// 路由」或「按路由查 branch index」的桌面外壳使用，避免各处各维护一份顺序表。
const List<String> branchRoutes = <String>[
  Routes.home, // 0
  Routes.video, // 1
  Routes.live, // 2
  Routes.music, // 3
  Routes.photo, // 4
  Routes.reading, // 5
  Routes.mine, // 6
  Routes.ops, // 7
  Routes.download, // 8
  Routes.transfer, // 9
  Routes.sources, // 10
  Routes.pt, // 11
  Routes.nastool, // 12
  Routes.files, // 13
];
