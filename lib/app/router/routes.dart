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
