import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/features/downloader/presentation/providers/downloader_aggregate_provider.dart';
import 'package:my_nas/features/music/presentation/providers/lyric_provider.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';
import 'package:my_nas/features/video/presentation/pages/video_list_page.dart'
    show VideoListLoaded, videoListProvider;
import 'package:my_nas/features/video/presentation/widgets/cast/cast_device_sheet.dart';
import 'package:my_nas/shared/providers/cloud_sync_auto_provider.dart';
import 'package:my_nas/shared/providers/desktop_space_provider.dart';
import 'package:my_nas/shared/providers/download_notify_provider.dart';
import 'package:my_nas/shared/providers/dynamic_ambient_provider.dart';
import 'package:my_nas/shared/providers/media_counts_provider.dart';
import 'package:my_nas/shared/widgets/adaptive_sheet.dart';
import 'package:my_nas/shared/widgets/desktop_shell/activity_aggregator.dart';
import 'package:my_nas/shared/widgets/desktop_shell/activity_drawer.dart';
import 'package:my_nas/shared/widgets/desktop_shell/ambient_layer.dart';
import 'package:my_nas/shared/widgets/desktop_shell/appearance_panel.dart';
import 'package:my_nas/shared/widgets/desktop_shell/command_palette.dart';
import 'package:my_nas/shared/widgets/desktop_shell/command_registry.dart';
import 'package:my_nas/shared/widgets/desktop_shell/desktop_lyric_float.dart';
import 'package:my_nas/shared/widgets/desktop_shell/desktop_sidebar.dart';
import 'package:my_nas/shared/widgets/desktop_shell/desktop_topbar.dart';
import 'package:my_nas/shared/widgets/desktop_shell/mini_dock.dart';
import 'package:my_nas/shared/widgets/dialogs/film_detail_sheet.dart';

/// 桌面端新外壳的统一容器。仅在 `context.isDesktopLayout` 时被
/// `main_scaffold.dart` 引用，移动端继续走旧 BottomNav 分支。
///
/// 接收 `StatefulNavigationShell`（go_router）做 branch 切换；本组件
/// 不负责 router 定义，只负责导航事件分发到 navigationShell.goBranch。
class DesktopScaffold extends ConsumerStatefulWidget {
  const DesktopScaffold({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<DesktopScaffold> createState() => _DesktopScaffoldState();
}

class _DesktopScaffoldState extends ConsumerState<DesktopScaffold> {
  bool _collapsed = false;
  bool _cmdkOpen = false;
  bool _activityOpen = false;
  bool _appearanceOpen = false;

  /// 已弹过「下载完成」提示的任务 uniqueKey 集合，按 id 去重避免重复弹。
  final Set<String> _notifiedCompleted = <String>{};

  /// 首次拿到聚合任务时把当前已完成项纳入基线，避免历史完成在首帧全部弹出。
  bool _completedBaselineReady = false;

  /// 与 14 branch 路由的对应（与 `app_router.dart` 的 branchNavigatorKeys
  /// 顺序必须完全一致）。
  static const _routeForBranch = <String>[
    '/home', // 0
    '/video', // 1
    '/live', // 2
    '/music', // 3
    '/photo', // 4
    '/reading', // 5
    '/mine', // 6
    '/ops', // 7
    '/download', // 8
    '/transfer', // 9
    '/sources', // 10
    '/pt', // 11
    '/nastool', // 12
    '/files', // 13
  ];

  @override
  void initState() {
    super.initState();
    _registerCommands();
  }

  /// 把"切换 UI 风格 / 打开设置 / 立即同步 / 添加数据源 / 跳转 PT"
  /// 等命令注入 CmdkRegistry。后续每个 feature 可在自己初始化时追加。
  void _registerCommands() {
    CmdkRegistry.instance.registerAll([
      CmdkCommand(
        id: 'goto.settings',
        label: '打开设置',
        icon: Icons.settings_outlined,
        hint: '⌘,',
        run: (c) => _go('/mine'),
      ),
      CmdkCommand(
        id: 'goto.films',
        label: '影视库',
        icon: Icons.movie_outlined,
        run: (c) => _go('/video'),
      ),
      CmdkCommand(
        id: 'goto.music',
        label: '音乐',
        icon: Icons.library_music_outlined,
        run: (c) => _go('/music'),
      ),
      CmdkCommand(
        id: 'goto.photos',
        label: '照片',
        icon: Icons.photo_library_outlined,
        run: (c) => _go('/photo'),
      ),
      CmdkCommand(
        id: 'goto.files',
        label: '文件',
        icon: Icons.folder_outlined,
        keywords: const ['浏览'],
        run: (c) => _go('/files'),
      ),
      CmdkCommand(
        id: 'goto.ops',
        label: '运维总览',
        icon: Icons.dashboard_customize_outlined,
        run: (c) => _go('/ops'),
      ),
      CmdkCommand(
        id: 'goto.downloads',
        label: '下载器',
        icon: Icons.download_rounded,
        run: (c) => _go('/download'),
      ),
      CmdkCommand(
        id: 'goto.transfers',
        label: '传输队列',
        icon: Icons.swap_horiz_rounded,
        run: (c) => _go('/transfer'),
      ),
      CmdkCommand(
        id: 'goto.sources',
        label: '数据源',
        icon: Icons.lan_rounded,
        run: (c) => _go('/sources'),
      ),
      CmdkCommand(
        id: 'goto.pt',
        label: 'PT 站点',
        icon: Icons.flag_circle_outlined,
        keywords: const ['pt', '种子', '资源站'],
        run: (c) => _go('/pt'),
      ),
      CmdkCommand(
        id: 'goto.nastool',
        label: '媒体自动化',
        icon: Icons.auto_awesome_outlined,
        keywords: const ['nastool', '订阅', '追剧'],
        run: (c) => _go('/nastool'),
      ),
    ]);
    _registerSearchers();
  }

  /// 注入跨域内容搜索器。query 非空时会被调用，搜索结果与静态命令一并显示。
  void _registerSearchers() {
    // 视频：在影视库 movies / tvShowGroups / others 内按 title 模糊匹配。
    CmdkRegistry.instance.registerSearcher('video', (ref, query) {
      final state = ref.read(videoListProvider);
      if (state is! VideoListLoaded) return const [];
      final q = query.toLowerCase();
      final all = [
        ...state.movies,
        ...state.tvShowGroups.values.map((g) => g.representative),
        ...state.others,
      ];
      final hit = all.where((m) {
        final t = (m.title ?? m.fileName).toLowerCase();
        return t.contains(q);
      }).take(6);
      return [
        for (final m in hit)
          CmdkCommand(
            id: 'video.${m.sourceId}.${m.filePath}',
            label: m.title ?? m.fileName,
            icon: Icons.movie_outlined,
            group: '影视',
            hint: m.year != null ? '${m.year}' : null,
            run: (ctx) {
              showDialog<void>(
                context: ctx,
                barrierColor: Colors.black.withValues(alpha: 0.55),
                builder: (_) => FilmDetailSheet(meta: m),
              );
            },
          ),
      ];
    });
  }

  bool get _hasOverlay => _cmdkOpen || _activityOpen || _appearanceOpen;

  void _closeOverlays() {
    setState(() {
      _cmdkOpen = false;
      _activityOpen = false;
      _appearanceOpen = false;
    });
  }

  /// 迷你播放器投屏：弹出投屏设备发现/选择 sheet（复用视频侧 CastDeviceSheet）。
  void _openCast() {
    showAdaptiveModalSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CastDeviceSheet(
        onDeviceSelected: (_) => Navigator.of(ctx).pop(),
      ),
    );
  }

  void _go(String route) {
    // 跨 space 链接时自动切换 sidebar。
    final s = spaceOfRoute(route);
    if (s != null) {
      ref.read(desktopSpaceProvider.notifier).set(s);
    }
    final idx = _routeForBranch.indexOf(route);
    if (idx >= 0 && idx < widget.navigationShell.route.branches.length) {
      widget.navigationShell.goBranch(
        idx,
        initialLocation: idx == widget.navigationShell.currentIndex,
      );
    } else {
      // 不在 branch 列表里就走顶层 router push（PT / NAStool 等二级页）。
      GoRouter.of(context).go(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = DesignTokens.of(context);
    final persistedSpace = ref.watch(desktopSpaceProvider);
    final hasMusic = ref.watch(currentMusicProvider) != null;
    final ambientOn = ref.watch(dynamicAmbientProvider);
    final lyricFloat = ref.watch(desktopLyricFloatProvider);
    final hasActivity = ref.watch(activityItemsProvider).isNotEmpty;
    final currentPath = GoRouterState.of(context).uri.path;
    // sidebar 空间跟随当前路由（媒体/控制台），避免启动时持久化空间与实际
    // 页面不一致；非空间路由（如 /mine 设置）回退到持久化空间。
    final space = spaceOfRoute(currentPath) ?? persistedSpace;
    // 激活云同步自动调度器（轻量，仅在 app 运行期间持有一个 timer）。
    ref.watch(cloudSyncSchedulerProvider);
    _listenDownloadComplete();

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            const _OpenCmdkIntent(),
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            const _OpenCmdkIntent(),
        const SingleActivator(LogicalKeyboardKey.escape):
            const _EscapeIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _OpenCmdkIntent: CallbackAction<_OpenCmdkIntent>(
            onInvoke: (_) {
              setState(() => _cmdkOpen = !_cmdkOpen);
              return null;
            },
          ),
          // 仅在有浮层打开时才接管 Esc 并消费按键；没有浮层时
          // isEnabled=false，让事件冒泡到外层 DesktopShortcuts 的
          // pop 逻辑（否则 push 出的详情/播放页按 Esc 无法返回）。
          _EscapeIntent: _EscapeAction(this),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: t.bg,
            body: Stack(
              children: [
                AmbientLayer(on: hasMusic && ambientOn),
                Row(
                  children: [
                    DesktopSidebar(
                      space: space,
                      collapsed: _collapsed,
                      currentRoute: currentPath,
                      mediaGroups: _mediaGroups(ref.watch(mediaCountsProvider)),
                      opsGroups: _opsGroups(),
                      onSpaceChanged: (s) {
                        ref.read(desktopSpaceProvider.notifier).set(s);
                        // 切换 space 时跳到该 space 首项。
                        if (s == DesktopSpace.media) {
                          _go('/home');
                        } else {
                          _go('/ops');
                        }
                      },
                      onNavigate: _go,
                      onOpenSettings: () => _go('/mine'),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          DesktopTopbar(
                            crumb: _crumbFor(currentPath),
                            activityBadge: hasActivity,
                            onToggleSidebar: () =>
                                setState(() => _collapsed = !_collapsed),
                            onOpenSearch: () =>
                                setState(() => _cmdkOpen = true),
                            onOpenActivity: () =>
                                setState(() => _activityOpen = true),
                            onOpenAppearance: () => setState(
                                () => _appearanceOpen = !_appearanceOpen),
                          ),
                          Expanded(child: widget.navigationShell),
                        ],
                      ),
                    ),
                  ],
                ),
                if (hasMusic)
                  MiniDock(
                    onOpenNowPlaying: () => GoRouter.of(context).push(
                      '/music/player',
                    ),
                    onOpenCast: _openCast,
                  ),
                if (hasMusic && lyricFloat) const DesktopLyricFloat(),
                if (_appearanceOpen)
                  Positioned(
                    top: DesignTokens.topbarH + 8,
                    right: 20,
                    child: AppearancePanel(
                      onClose: () => setState(() => _appearanceOpen = false),
                    ),
                  ),
                if (_cmdkOpen)
                  CommandPalette(
                    onClose: () => setState(() => _cmdkOpen = false),
                  ),
                if (_activityOpen)
                  ActivityDrawer(
                    onClose: () => setState(() => _activityOpen = false),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 监听聚合下载任务，新出现的「已完成」任务在开关开启时弹应用内 toast。
  /// 首帧把当前已完成项纳入基线，之后只对增量完成弹窗，并按 uniqueKey 去重。
  void _listenDownloadComplete() {
    ref.listen<List<UnifiedDownloadTask>>(
      aggregatedDownloadTasksProvider,
      (prev, next) {
        final completed = next.where(
          (t) => t.status == UnifiedDownloadStatus.completed,
        );
        if (!_completedBaselineReady) {
          // 基线：首次回调把现有已完成任务标记为已见，不弹窗。
          _completedBaselineReady = true;
          _notifiedCompleted.addAll(completed.map((t) => t.uniqueKey));
          return;
        }
        final notify = ref.read(downloadNotifyProvider);
        for (final t in completed) {
          if (_notifiedCompleted.add(t.uniqueKey) && notify) {
            context.showSuccessToast('${t.name} 下载完成');
          }
        }
      },
    );
  }

  // ---- nav items ----

  List<NavGroup> _mediaGroups(MediaCounts counts) => [
        const NavGroup(items: [
          NavEntry(
            id: 'home',
            route: '/home',
            label: '概览',
            icon: Icons.home_outlined,
          ),
        ]),
        NavGroup(label: '我的媒体', items: [
          NavEntry(
            id: 'films',
            route: '/video',
            label: '影视',
            icon: Icons.movie_outlined,
            count: formatCountBadge(counts.video),
          ),
          const NavEntry(
            id: 'live',
            route: '/live',
            label: '直播',
            icon: Icons.cast_rounded,
            live: true,
          ),
          NavEntry(
            id: 'music',
            route: '/music',
            label: '音乐',
            icon: Icons.library_music_outlined,
            count: formatCountBadge(counts.music),
          ),
          NavEntry(
            id: 'photos',
            route: '/photo',
            label: '照片',
            icon: Icons.photo_library_outlined,
            count: formatCountBadge(counts.photo),
          ),
          NavEntry(
            id: 'reading',
            route: '/reading',
            label: '阅读',
            icon: Icons.menu_book_outlined,
            count: formatCountBadge(counts.reading),
          ),
        ]),
        const NavGroup(label: '底层', items: [
          NavEntry(
            id: 'files',
            route: '/files',
            label: '文件',
            icon: Icons.folder_outlined,
          ),
        ]),
      ];

  List<NavGroup> _opsGroups() => const [
        NavGroup(items: [
          NavEntry(
            id: 'ops',
            route: '/ops',
            label: '运维总览',
            icon: Icons.dashboard_customize_outlined,
          ),
        ]),
        NavGroup(label: '传输与下载', items: [
          NavEntry(
            id: 'downloads',
            route: '/download',
            label: '下载器',
            icon: Icons.download_rounded,
          ),
          NavEntry(
            id: 'transfers',
            route: '/transfer',
            label: '传输队列',
            icon: Icons.swap_horiz_rounded,
          ),
        ]),
        NavGroup(label: '资源与自动化', items: [
          NavEntry(
            id: 'pt',
            route: '/pt',
            label: 'PT 站点',
            icon: Icons.flag_circle_outlined,
          ),
          NavEntry(
            id: 'nastool',
            route: '/nastool',
            label: '媒体自动化',
            icon: Icons.auto_awesome_outlined,
          ),
          NavEntry(
            id: 'sources',
            route: '/sources',
            label: '数据源',
            icon: Icons.lan_rounded,
          ),
        ]),
      ];

  List<String> _crumbFor(String path) {
    const map = <String, List<String>>{
      '/home': ['媒体', '概览'],
      '/video': ['媒体', '影视'],
      '/live': ['媒体', '直播'],
      '/music': ['媒体', '音乐'],
      '/photo': ['媒体', '照片'],
      '/reading': ['媒体', '阅读'],
      '/mine': ['', '设置'],
      '/ops': ['控制台', '运维总览'],
      '/download': ['控制台', '下载器'],
      '/transfer': ['控制台', '传输队列'],
      '/sources': ['控制台', '数据源'],
      '/pt': ['控制台', 'PT 站点'],
      '/nastool': ['控制台', '媒体自动化'],
    };
    for (final entry in map.entries) {
      if (path.startsWith(entry.key)) {
        return entry.value.where((s) => s.isNotEmpty).toList();
      }
    }
    return const [];
  }
}

class _OpenCmdkIntent extends Intent {
  const _OpenCmdkIntent();
}

class _EscapeIntent extends Intent {
  const _EscapeIntent();
}

/// Esc 行为：仅当有浮层（cmdk / activity / appearance）打开时启用并消费按键，
/// 关闭浮层；无浮层时 isEnabled=false，按键冒泡到外层 [DesktopShortcuts]，
/// 由其 pop 当前 branch / root navigator（详情、播放器等 push 页返回）。
class _EscapeAction extends Action<_EscapeIntent> {
  _EscapeAction(this._state);

  final _DesktopScaffoldState _state;

  @override
  bool isEnabled(_EscapeIntent intent) => _state._hasOverlay;

  @override
  bool consumesKey(_EscapeIntent intent) => _state._hasOverlay;

  @override
  Object? invoke(_EscapeIntent intent) {
    _state._closeOverlays();
    return null;
  }
}
