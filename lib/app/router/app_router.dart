import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:my_nas/app/router/routes.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/connection/presentation/pages/connection_page.dart';
import 'package:my_nas/features/desktop_home/presentation/pages/home_overview_page.dart';
import 'package:my_nas/features/desktop_ops/presentation/pages/ops_overview_page.dart';
import 'package:my_nas/features/downloader/presentation/pages/downloader_list_page.dart';
import 'package:my_nas/features/downloader/presentation/pages/downloads_desktop_page.dart';
import 'package:my_nas/features/mine/presentation/pages/mine_page.dart';
import 'package:my_nas/features/music/presentation/pages/desktop_now_playing_page.dart';
import 'package:my_nas/features/music/presentation/pages/music_list_desktop_page.dart';
import 'package:my_nas/features/music/presentation/pages/music_list_page.dart';
import 'package:my_nas/features/music/presentation/pages/music_player_page.dart';
import 'package:my_nas/features/nastool/presentation/pages/nastool_desktop_page.dart';
import 'package:my_nas/features/photo/presentation/pages/photo_list_desktop_page.dart';
import 'package:my_nas/features/photo/presentation/pages/photo_list_page.dart';
import 'package:my_nas/features/pt_sites/presentation/pages/pt_sites_desktop_page.dart';
import 'package:my_nas/features/reading/presentation/pages/reading_desktop_page.dart';
import 'package:my_nas/features/reading/presentation/pages/reading_page.dart';
import 'package:my_nas/features/sources/presentation/pages/sources_desktop_page.dart';
import 'package:my_nas/features/sources/presentation/pages/sources_page.dart';
import 'package:my_nas/features/startup/presentation/pages/startup_page.dart';
import 'package:my_nas/features/transfer/presentation/pages/transfer_manager_page.dart';
import 'package:my_nas/features/video/presentation/pages/live_tv_desktop_page.dart';
import 'package:my_nas/features/video/presentation/pages/video_list_desktop_page.dart';
import 'package:my_nas/features/video/presentation/pages/video_list_page.dart';
import 'package:my_nas/shared/widgets/main_scaffold.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

/// 主 tab + 桌面端工具区各自独立的 Navigator key，由 StatefulShellRoute 管理。
/// 让每个 branch 维护自己的页面栈，切换时不互相污染。
final _homeNavigatorKey = GlobalKey<NavigatorState>(); // 桌面 home（新）
final _videoNavigatorKey = GlobalKey<NavigatorState>();
final _liveNavigatorKey = GlobalKey<NavigatorState>(); // 桌面 live（新）
final _musicNavigatorKey = GlobalKey<NavigatorState>();
final _photoNavigatorKey = GlobalKey<NavigatorState>();
final _readingNavigatorKey = GlobalKey<NavigatorState>();
final _mineNavigatorKey = GlobalKey<NavigatorState>();
final _opsNavigatorKey = GlobalKey<NavigatorState>(); // 桌面 ops（新）
// 桌面工具区 branch。移动端 BottomNavigation 不显示，但 branch 仍存在。
final _downloadNavigatorKey = GlobalKey<NavigatorState>();
final _transferNavigatorKey = GlobalKey<NavigatorState>();
final _sourcesNavigatorKey = GlobalKey<NavigatorState>();
final _ptNavigatorKey = GlobalKey<NavigatorState>(); // 桌面 PT 站点
final _nastoolNavigatorKey = GlobalKey<NavigatorState>(); // 桌面 媒体自动化

/// 按 branch index 顺序排列的 navigator keys，供 main_scaffold / desktop_scaffold
/// 引用。顺序必须与 `desktop_scaffold._routeForBranch` 完全一致：
/// 0=home 1=video 2=live 3=music 4=photo 5=reading 6=mine 7=ops
/// 8=download 9=transfer 10=sources 11=pt 12=nastool
final branchNavigatorKeys = <GlobalKey<NavigatorState>>[
  _homeNavigatorKey,
  _videoNavigatorKey,
  _liveNavigatorKey,
  _musicNavigatorKey,
  _photoNavigatorKey,
  _readingNavigatorKey,
  _mineNavigatorKey,
  _opsNavigatorKey,
  _downloadNavigatorKey,
  _transferNavigatorKey,
  _sourcesNavigatorKey,
  _ptNavigatorKey,
  _nastoolNavigatorKey,
];

/// 待处理的 deep link 路径
/// 当应用尚未完全初始化时，保存 deep link 路径稍后处理
String? _pendingDeepLink;

/// 获取并清除待处理的 deep link
String? consumePendingDeepLink() {
  final link = _pendingDeepLink;
  _pendingDeepLink = null;
  return link;
}

final appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: Routes.startup,
  debugLogDiagnostics: kDebugMode,
  // 错误处理 - 当导航失败时显示错误页面
  errorBuilder: (context, state) {
    logger.e('GoRouter error: ${state.error}');
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
            const SizedBox(height: 16),
            Text('导航错误: ${state.uri}'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => context.go(Routes.music),
              child: const Text('返回音乐'),
            ),
          ],
        ),
      ),
    );
  },
  // 处理深度链接 (mynas://music/player -> /music/player)
  redirect: (context, state) {
    final uri = state.uri;
    final matchedLocation = state.matchedLocation;

    logger.d('GoRouter redirect: uri=$uri, scheme=${uri.scheme}, '
        'host=${uri.host}, path=${uri.path}, matchedLocation=$matchedLocation');

    // 情况1: 完整的 URI scheme (mynas://music/player)
    // 在这种情况下：scheme=mynas, host=music, path=/player
    if (uri.scheme == 'mynas') {
      final host = uri.host; // e.g., "music"
      var path = uri.path; // e.g., "/player" 或 "/" 或 ""

      // 处理空路径或仅为 "/" 的情况
      if (path == '/' || path.isEmpty) {
        path = '';
      }

      // 组合成完整路径: /music/player
      var fullPath = host.isNotEmpty ? '/$host$path' : path;

      // 移除尾部斜杠（除非是根路径）
      if (fullPath.length > 1 && fullPath.endsWith('/')) {
        fullPath = fullPath.substring(0, fullPath.length - 1);
      }

      logger.i('GoRouter: Deep link detected, redirecting to $fullPath');
      return fullPath;
    }

    // 情况2: GoRouter 可能只收到路径部分 (music/player)
    // 没有前导斜杠的路径可能来自 deep link
    final uriString = uri.toString();
    if (!uriString.startsWith('/') &&
        !uriString.startsWith('http') &&
        uriString.contains('music/player')) {
      final path = '/$uriString';
      logger.i('GoRouter: Path without leading slash, redirecting to $path');
      return path;
    }

    return null;
  },
  routes: [
    // Startup page (handles auto-login)
    GoRoute(
      path: Routes.startup,
      name: 'startup',
      builder: (context, state) => const StartupPage(),
    ),

    // Connection page (without shell)
    GoRoute(
      path: Routes.connection,
      name: 'connection',
      builder: (context, state) => const ConnectionPage(),
    ),

    // Music player page (full screen, accessed from Deep Link / Live Activity)
    // 桌面端走重设计的 DesktopNowPlayingPage，移动端保留 MusicPlayerPage。
    GoRoute(
      path: Routes.musicPlayer,
      name: 'musicPlayer',
      builder: (context, state) => context.isDesktopLayout
          ? const DesktopNowPlayingPage()
          : const MusicPlayerPage(),
    ),

    // Main shell with 11 branches. Order matches `branchNavigatorKeys` and
    // `desktop_scaffold._routeForBranch`. Move/insert here requires updating
    // both arrays in lockstep.
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          MainScaffold(navigationShell: navigationShell),
      branches: [
        // 0 home (桌面新增)
        StatefulShellBranch(
          navigatorKey: _homeNavigatorKey,
          routes: [
            GoRoute(
              path: Routes.home,
              name: 'home',
              builder: (context, state) => const HomeOverviewPage(),
            ),
          ],
        ),
        // 1 video — 桌面端走重设计 page，移动端保留原 VideoListPage。
        StatefulShellBranch(
          navigatorKey: _videoNavigatorKey,
          routes: [
            GoRoute(
              path: Routes.video,
              name: 'video',
              builder: (context, state) => context.isDesktopLayout
                  ? const VideoListDesktopPage()
                  : const VideoListPage(),
            ),
          ],
        ),
        // 2 live (桌面新增)
        StatefulShellBranch(
          navigatorKey: _liveNavigatorKey,
          routes: [
            GoRoute(
              path: Routes.live,
              name: 'live',
              builder: (context, state) => const LiveTvDesktopPage(),
            ),
          ],
        ),
        // 3 music
        StatefulShellBranch(
          navigatorKey: _musicNavigatorKey,
          routes: [
            GoRoute(
              path: Routes.music,
              name: 'music',
              builder: (context, state) => context.isDesktopLayout
                  ? const MusicListDesktopPage()
                  : const MusicListPage(),
            ),
          ],
        ),
        // 4 photo
        StatefulShellBranch(
          navigatorKey: _photoNavigatorKey,
          routes: [
            GoRoute(
              path: Routes.photo,
              name: 'photo',
              builder: (context, state) => context.isDesktopLayout
                  ? const PhotoListDesktopPage()
                  : const PhotoListPage(),
            ),
          ],
        ),
        // 5 reading
        StatefulShellBranch(
          navigatorKey: _readingNavigatorKey,
          routes: [
            GoRoute(
              path: Routes.reading,
              name: 'reading',
              builder: (context, state) => context.isDesktopLayout
                  ? const ReadingDesktopPage()
                  : const ReadingPage(),
            ),
          ],
        ),
        // 6 mine
        StatefulShellBranch(
          navigatorKey: _mineNavigatorKey,
          routes: [
            GoRoute(
              path: Routes.mine,
              name: 'mine',
              builder: (context, state) => const MinePage(),
            ),
          ],
        ),
        // 7 ops (桌面新增)
        StatefulShellBranch(
          navigatorKey: _opsNavigatorKey,
          routes: [
            GoRoute(
              path: Routes.ops,
              name: 'ops',
              builder: (context, state) => const OpsOverviewPage(),
            ),
          ],
        ),
        // 8 download (桌面工具区) — 桌面新视觉，移动走原 DownloaderListPage
        StatefulShellBranch(
          navigatorKey: _downloadNavigatorKey,
          routes: [
            GoRoute(
              path: Routes.download,
              name: 'download',
              builder: (context, state) => context.isDesktopLayout
                  ? const DownloadsDesktopPage()
                  : const DownloaderListPage(),
            ),
          ],
        ),
        // 9 transfer (桌面工具区)
        StatefulShellBranch(
          navigatorKey: _transferNavigatorKey,
          routes: [
            GoRoute(
              path: Routes.transfer,
              name: 'transfer',
              builder: (context, state) => const TransferManagerPage(),
            ),
          ],
        ),
        // 10 sources (桌面工具区) — 桌面新视觉，移动走原 SourcesPage
        StatefulShellBranch(
          navigatorKey: _sourcesNavigatorKey,
          routes: [
            GoRoute(
              path: Routes.sources,
              name: 'sources',
              builder: (context, state) => context.isDesktopLayout
                  ? const SourcesDesktopPage()
                  : const SourcesPage(),
            ),
          ],
        ),
        // 11 pt (桌面工具区) — PT 站点聚合浏览，移动端走源详情页入口
        StatefulShellBranch(
          navigatorKey: _ptNavigatorKey,
          routes: [
            GoRoute(
              path: Routes.pt,
              name: 'pt',
              builder: (context, state) => const PtSitesDesktopPage(),
            ),
          ],
        ),
        // 12 nastool (桌面工具区) — 媒体自动化订阅管理
        StatefulShellBranch(
          navigatorKey: _nastoolNavigatorKey,
          routes: [
            GoRoute(
              path: Routes.nastool,
              name: 'nastool',
              builder: (context, state) => const NasToolDesktopPage(),
            ),
          ],
        ),
      ],
    ),
  ],
);
