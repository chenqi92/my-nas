import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:my_nas/app/router/routes.dart';
import 'package:my_nas/app/theme/app_colors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/connection/presentation/pages/connection_page.dart';
import 'package:my_nas/features/mine/presentation/pages/mine_page.dart';
import 'package:my_nas/features/music/presentation/pages/music_list_page.dart';
import 'package:my_nas/features/music/presentation/pages/music_player_page.dart';
import 'package:my_nas/features/photo/presentation/pages/photo_list_page.dart';
import 'package:my_nas/features/reading/presentation/pages/reading_page.dart';
import 'package:my_nas/features/startup/presentation/pages/startup_page.dart';
import 'package:my_nas/features/video/presentation/pages/video_list_page.dart';
import 'package:my_nas/shared/widgets/main_scaffold.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

/// 5 个主 tab 各自独立的 Navigator key，由 StatefulShellRoute 管理。
/// 让每个 tab 维护自己的页面栈，切 tab 时不互相污染；同时为桌面端
/// Master-Detail 在 branch navigator 内渲染 detail 铺路。
final _videoNavigatorKey = GlobalKey<NavigatorState>();
final _musicNavigatorKey = GlobalKey<NavigatorState>();
final _photoNavigatorKey = GlobalKey<NavigatorState>();
final _readingNavigatorKey = GlobalKey<NavigatorState>();
final _mineNavigatorKey = GlobalKey<NavigatorState>();

/// 按 tab index 顺序排列的 branch navigator keys，供 main_scaffold
/// 桌面端工具区按当前 currentIndex push 到对应 branch（覆盖右侧内容
/// 但保留 NavigationRail 可见）。
final branchNavigatorKeys = <GlobalKey<NavigatorState>>[
  _videoNavigatorKey,
  _musicNavigatorKey,
  _photoNavigatorKey,
  _readingNavigatorKey,
  _mineNavigatorKey,
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
            Icon(Icons.error_outline, size: 48, color: AppColors.error),
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
    GoRoute(
      path: Routes.musicPlayer,
      name: 'musicPlayer',
      builder: (context, state) => const MusicPlayerPage(),
    ),

    // Main shell with 5 tabs, each with its own Navigator stack.
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          MainScaffold(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          navigatorKey: _videoNavigatorKey,
          routes: [
            GoRoute(
              path: Routes.video,
              name: 'video',
              builder: (context, state) => const VideoListPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _musicNavigatorKey,
          routes: [
            GoRoute(
              path: Routes.music,
              name: 'music',
              builder: (context, state) => const MusicListPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _photoNavigatorKey,
          routes: [
            GoRoute(
              path: Routes.photo,
              name: 'photo',
              builder: (context, state) => const PhotoListPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _readingNavigatorKey,
          routes: [
            GoRoute(
              path: Routes.reading,
              name: 'reading',
              builder: (context, state) => const ReadingPage(),
            ),
          ],
        ),
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
      ],
    ),
  ],
);
