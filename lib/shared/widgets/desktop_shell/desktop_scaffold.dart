import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:my_nas/app/router/routes.dart';
import 'package:my_nas/app/theme/design_tokens.dart';
import 'package:my_nas/core/constants/app_constants.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/extensions/context_extensions.dart';
import 'package:my_nas/core/services/system_notification_service.dart';
import 'package:my_nas/core/services/tray_service.dart';
import 'package:my_nas/features/book/presentation/pages/book_list_page.dart'
    show BookListLoaded, bookListProvider;
import 'package:my_nas/features/comic/presentation/pages/comic_list_page.dart'
    show ComicListLoaded, comicListProvider;
import 'package:my_nas/features/downloader/presentation/providers/downloader_aggregate_provider.dart';
import 'package:my_nas/features/downloader/presentation/widgets/download_detail_sheet.dart';
import 'package:my_nas/features/file_browser/data/services/global_file_search_service.dart';
import 'package:my_nas/features/file_browser/presentation/providers/file_browser_provider.dart'
    show browsableSourcesProvider, fileListProvider, selectedSourceIdProvider;
import 'package:my_nas/features/music/presentation/pages/music_list_page.dart'
    show MusicListLoaded, musicListProvider;
import 'package:my_nas/features/music/presentation/providers/lyric_provider.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';
import 'package:my_nas/features/note/presentation/pages/note_list_page.dart'
    show NotePageLoaded, notePageProvider;
import 'package:my_nas/features/note/presentation/widgets/note_tree_widget.dart';
import 'package:my_nas/features/photo/presentation/pages/photo_list_page.dart'
    show PhotoListLoaded, photoListProvider;
import 'package:my_nas/features/reading/presentation/pages/reading_desktop_page.dart'
    show desktopReadingTabProvider;
import 'package:my_nas/features/video/presentation/pages/video_detail_page.dart';
import 'package:my_nas/features/video/presentation/pages/video_list_page.dart'
    show VideoListLoaded, videoListProvider;
import 'package:my_nas/features/video/presentation/widgets/cast/cast_device_sheet.dart';
import 'package:my_nas/l10n/app_localizations.dart';
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

/// 顶部全局搜索承诺覆盖的内容域。测试以此防止桌面外壳重构时再次退化为
/// 只有影视搜索。
@visibleForTesting
const desktopGlobalSearchDomains = <String>{
  'video',
  'music',
  'photo',
  'reading',
  'files',
  'downloads',
};

@visibleForTesting
bool desktopGlobalSearchMatches(String query, Iterable<String?> fields) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) return false;
  return fields.whereType<String>().any(
    (field) => field.toLowerCase().contains(normalized),
  );
}

Iterable<NoteTreeNode> _flattenNoteNodes(Iterable<NoteTreeNode> roots) sync* {
  for (final node in roots) {
    yield node;
    yield* _flattenNoteNodes(node.children);
  }
}

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

  bool _commandsRegistered = false;

  /// 把"切换 UI 风格 / 打开设置 / 立即同步 / 添加数据源 / 跳转 PT"
  /// 等命令注入 CmdkRegistry。在 build 中调用（需要 l 取本地化文案），
  /// registerAll 按 id 去重，幂等，重复调用安全。
  void _registerCommands(AppLocalizations l) {
    if (_commandsRegistered) return;
    _commandsRegistered = true;
    CmdkRegistry.instance.registerAll([
      CmdkCommand(
        id: 'goto.settings',
        label: l.shellNavCmdOpenSettings,
        icon: Icons.settings_outlined,
        hint: '⌘,',
        run: (c) => _go('/mine'),
      ),
      CmdkCommand(
        id: 'goto.films',
        label: l.shellNavCmdFilmsLibrary,
        icon: Icons.movie_outlined,
        run: (c) => _go('/video'),
      ),
      CmdkCommand(
        id: 'goto.music',
        label: l.shellNavCmdMusic,
        icon: Icons.library_music_outlined,
        run: (c) => _go('/music'),
      ),
      CmdkCommand(
        id: 'goto.photos',
        label: l.shellNavCmdPhotos,
        icon: Icons.photo_library_outlined,
        run: (c) => _go('/photo'),
      ),
      CmdkCommand(
        id: 'goto.files',
        label: l.shellNavCmdFiles,
        icon: Icons.folder_outlined,
        keywords: [l.shellNavCmdFilesKeywordBrowse],
        run: (c) => _go('/files'),
      ),
      CmdkCommand(
        id: 'goto.ops',
        label: l.shellNavCmdOpsOverview,
        icon: Icons.dashboard_customize_outlined,
        run: (c) => _go('/ops'),
      ),
      CmdkCommand(
        id: 'goto.downloads',
        label: l.shellNavCmdDownloader,
        icon: Icons.download_rounded,
        run: (c) => _go('/download'),
      ),
      CmdkCommand(
        id: 'goto.transfers',
        label: l.shellNavCmdTransferQueue,
        icon: Icons.swap_horiz_rounded,
        run: (c) => _go('/transfer'),
      ),
      CmdkCommand(
        id: 'goto.sources',
        label: l.shellNavCmdSources,
        icon: Icons.lan_rounded,
        run: (c) => _go('/sources'),
      ),
      CmdkCommand(
        id: 'goto.pt',
        label: l.shellNavCmdPtSites,
        icon: Icons.flag_circle_outlined,
        keywords: [
          'pt',
          l.shellNavCmdPtKeywordTorrent,
          l.shellNavCmdPtKeywordResourceSite,
        ],
        run: (c) => _go('/pt'),
      ),
      CmdkCommand(
        id: 'goto.nastool',
        label: l.shellNavCmdMediaAutomation,
        icon: Icons.auto_awesome_outlined,
        keywords: [
          'nastool',
          l.shellNavCmdNastoolKeywordSubscribe,
          l.shellNavCmdNastoolKeywordFollowShow,
        ],
        run: (c) => _go('/nastool'),
      ),
    ]);
    _registerSearchers(l);
  }

  /// 注入跨域内容搜索器。query 非空时会被调用，搜索结果与静态命令一并显示。
  void _registerSearchers(AppLocalizations l) {
    // 视频：在影视库 movies / tvShowGroups / others 内按标题和路径模糊匹配。
    CmdkRegistry.instance.registerSearcher('video', (ref, query) {
      final state = ref.read(videoListProvider);
      if (state is! VideoListLoaded) return const [];
      final all = [
        ...state.movies,
        ...state.tvShowGroups.values.map((g) => g.representative),
        ...state.others,
      ];
      final hit = all
          .where(
            (m) => desktopGlobalSearchMatches(query, [
              m.title,
              m.fileName,
              m.filePath,
            ]),
          )
          .take(6);
      return [
        for (final m in hit)
          CmdkCommand(
            id: 'video.${m.sourceId}.${m.filePath}',
            label: m.title ?? m.fileName,
            icon: Icons.movie_outlined,
            group: l.shellNavGroupFilms,
            hint: m.year != null ? '${m.year}' : null,
            run: (ctx) {
              Navigator.of(ctx, rootNavigator: true).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      VideoDetailPage(metadata: m, sourceId: m.sourceId),
                ),
              );
            },
          ),
      ];
    });

    CmdkRegistry.instance.registerSearcher('music', (ref, query) {
      final state = ref.read(musicListProvider);
      if (state is! MusicListLoaded) return const [];
      final hit = state.allTracks
          .where(
            (track) => desktopGlobalSearchMatches(query, [
              track.displayTitle,
              track.displayArtist,
              track.displayAlbum,
              track.fileName,
              track.filePath,
            ]),
          )
          .take(6);
      return [
        for (final track in hit)
          CmdkCommand(
            id: 'music.${track.sourceId}.${track.filePath}',
            label: track.displayTitle,
            icon: Icons.music_note_rounded,
            group: l.shellNavGroupMyMedia,
            hint: track.displayArtist,
            run: (_) {
              ref.read(musicListProvider.notifier).setSearchQuery(query);
              _go('/music');
            },
          ),
      ];
    });

    CmdkRegistry.instance.registerSearcher('photo', (ref, query) {
      final state = ref.read(photoListProvider);
      if (state is! PhotoListLoaded) return const [];
      final hit = state.allPhotos
          .where(
            (photo) => desktopGlobalSearchMatches(query, [
              photo.fileName,
              photo.filePath,
              photo.folderName,
            ]),
          )
          .take(6);
      return [
        for (final photo in hit)
          CmdkCommand(
            id: 'photo.${photo.sourceId}.${photo.filePath}',
            label: photo.fileName,
            icon: Icons.photo_outlined,
            group: l.shellNavGroupMyMedia,
            hint: photo.folderName,
            run: (_) {
              ref.read(photoListProvider.notifier).setSearchQuery(query);
              _go('/photo');
            },
          ),
      ];
    });

    // 阅读：图书、漫画与已加载的笔记树共享一个搜索域，但点击时会落到
    // 对应桌面分区，并复用各自已有的筛选状态。
    CmdkRegistry.instance.registerSearcher('reading', (ref, query) {
      final results = <CmdkCommand>[];
      final books = ref.read(bookListProvider);
      if (books is BookListLoaded) {
        for (final book
            in books.allBooks
                .where(
                  (book) => desktopGlobalSearchMatches(query, [
                    book.displayName,
                    book.displayAuthor,
                    book.fileName,
                    book.filePath,
                  ]),
                )
                .take(4)) {
          results.add(
            CmdkCommand(
              id: 'reading.book.${book.sourceId}.${book.filePath}',
              label: book.displayName,
              icon: Icons.menu_book_outlined,
              group: l.shellNavGroupMyMedia,
              hint: book.displayAuthor,
              run: (_) {
                ref.read(bookListProvider.notifier).setSearchQuery(query);
                ref.read(desktopReadingTabProvider.notifier).state = '图书';
                _go('/reading');
              },
            ),
          );
        }
      }

      final comics = ref.read(comicListProvider);
      if (comics is ComicListLoaded) {
        for (final comic
            in comics.comics
                .where(
                  (comic) => desktopGlobalSearchMatches(query, [
                    comic.folderName,
                    comic.folderPath,
                  ]),
                )
                .take(4)) {
          results.add(
            CmdkCommand(
              id: 'reading.comic.${comic.sourceId}.${comic.folderPath}',
              label: comic.folderName,
              icon: Icons.collections_bookmark_outlined,
              group: l.shellNavGroupMyMedia,
              hint: comic.folderPath,
              run: (_) {
                ref.read(comicListProvider.notifier).setSearchQuery(query);
                ref.read(desktopReadingTabProvider.notifier).state = '漫画';
                _go('/reading');
              },
            ),
          );
        }
      }

      final notes = ref.read(notePageProvider);
      if (notes is NotePageLoaded) {
        for (final note
            in _flattenNoteNodes(notes.treeNodes)
                .where(
                  (note) => desktopGlobalSearchMatches(query, [
                    note.displayName,
                    note.name,
                    note.path,
                  ]),
                )
                .take(4)) {
          results.add(
            CmdkCommand(
              id: 'reading.note.${note.sourceId}.${note.path}',
              label: note.displayName,
              icon: note.type == NoteTreeNodeType.folder
                  ? Icons.folder_outlined
                  : Icons.note_outlined,
              group: l.shellNavGroupMyMedia,
              hint: note.path,
              run: (_) {
                ref.read(notePageProvider.notifier).setSearchQuery(query);
                ref.read(desktopReadingTabProvider.notifier).state = '笔记';
                _go('/reading');
              },
            ),
          );
        }
      }
      return results.take(8).toList(growable: false);
    });

    CmdkRegistry.instance.registerSearcher('files', (ref, query) async {
      final sources = ref.read(browsableSourcesProvider);
      final hit = await searchConnectedFileSystems(
        [
          for (final (source, connection) in sources)
            GlobalFileSearchSource(
              id: source.id,
              name: source.displayName,
              rootPath: source.initialBrowsePath,
              fileSystem: connection.fileSystem,
            ),
        ],
        query,
        maxResultsPerSource: 6,
      );
      return [
        for (final result in hit.take(12))
          CmdkCommand(
            id: 'files.${result.sourceId}.${result.file.path}',
            label: result.file.name,
            icon: result.file.isDirectory
                ? Icons.folder_outlined
                : Icons.insert_drive_file_outlined,
            group: l.shellNavGroupFoundation,
            hint: '${result.sourceName} · ${result.file.path}',
            run: (_) {
              ref.read(selectedSourceIdProvider.notifier).state =
                  result.sourceId;
              final target = result.file.isDirectory
                  ? result.file.path
                  : parentDirectoryOf(result.file.path);
              unawaited(
                ref.read(fileListProvider.notifier).loadDirectory(target),
              );
              _go('/files');
            },
          ),
      ];
    });

    CmdkRegistry.instance.registerSearcher('downloads', (ref, query) {
      final tasks = ref.read(aggregatedDownloadTasksProvider);
      final hit = tasks
          .where(
            (task) => desktopGlobalSearchMatches(query, [
              task.name,
              task.sourceName,
              task.savePath,
            ]),
          )
          .take(6);
      return [
        for (final task in hit)
          CmdkCommand(
            id: 'downloads.${task.uniqueKey}',
            label: task.name,
            icon: Icons.download_rounded,
            group: l.shellNavGroupTransferDownload,
            hint: task.sourceName,
            run: (ctx) => AppError.fireAndForget(
              showDownloadDetailDrawer(ctx, task.uniqueKey),
              action: 'openDownloadSearchResult',
            ),
          ),
      ];
    });
  }

  /// 幂等启动系统托盘（仅桌面，移动/Web 内部 no-op），并把播放控制回调绑定到
  /// 当前 musicPlayerController。每帧 build 调用安全（TrayService 内部去重）。
  void _ensureTray(AppLocalizations l) {
    AppError.fireAndForget(
      TrayService.instance.ensureStarted(
        TrayLabels(
          show: l.trayMenuShow,
          playPause: l.trayMenuPlayPause,
          previous: l.trayMenuPrevious,
          next: l.trayMenuNext,
          exit: l.trayMenuExit,
          tooltip: l.trayTooltip,
        ),
        onPlayPause: () => AppError.fireAndForget(
          ref.read(musicPlayerControllerProvider.notifier).playOrPause(),
          action: 'trayPlayPause',
        ),
        onPrevious: () => AppError.fireAndForget(
          ref.read(musicPlayerControllerProvider.notifier).playPrevious(),
          action: 'trayPrevious',
        ),
        onNext: () => AppError.fireAndForget(
          ref.read(musicPlayerControllerProvider.notifier).playNext(),
          action: 'trayNext',
        ),
      ),
      action: 'trayEnsureStarted',
    );
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
      builder: (ctx) =>
          CastDeviceSheet(onDeviceSelected: (_) => Navigator.of(ctx).pop()),
    );
  }

  void _go(String route) {
    // 跨 space 链接时自动切换 sidebar。
    final s = spaceOfRoute(route);
    if (s != null) {
      ref.read(desktopSpaceProvider.notifier).set(s);
    }
    // branchRoutes（routes.dart）是 branch 顺序的单一事实来源。
    final idx = branchRoutes.indexOf(route);
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
    final l = AppLocalizations.of(context);
    final t = DesignTokens.of(context);
    _registerCommands(l);
    _ensureTray(l);
    final persistedSpace = ref.watch(desktopSpaceProvider);
    final hasMusic = ref.watch(currentMusicProvider) != null;
    final ambientOn = ref.watch(dynamicAmbientProvider);
    final lyricFloat = ref.watch(desktopLyricFloatProvider);
    final hasActivity = ref.watch(activeActivityCountProvider) > 0;
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
        const SingleActivator(LogicalKeyboardKey.escape): const _EscapeIntent(),
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
                      mediaGroups: _mediaGroups(
                        l,
                        ref.watch(mediaCountsProvider),
                      ),
                      opsGroups: _opsGroups(l),
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
                            crumb: _crumbFor(l, currentPath),
                            activityBadge: hasActivity,
                            onToggleSidebar: () =>
                                setState(() => _collapsed = !_collapsed),
                            onOpenSearch: () =>
                                setState(() => _cmdkOpen = true),
                            onOpenActivity: () =>
                                setState(() => _activityOpen = true),
                            onOpenAppearance: () => setState(
                              () => _appearanceOpen = !_appearanceOpen,
                            ),
                          ),
                          Expanded(child: widget.navigationShell),
                        ],
                      ),
                    ),
                  ],
                ),
                if (hasMusic)
                  MiniDock(
                    onOpenNowPlaying: () =>
                        GoRouter.of(context).push('/music/player'),
                    onOpenCast: _openCast,
                  ),
                if (hasMusic && lyricFloat) const DesktopLyricFloat(),
                if (_appearanceOpen) ...[
                  // 点击空白处关闭外观浮层。
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _appearanceOpen = false),
                    ),
                  ),
                  Positioned(
                    top: DesignTokens.topbarH + 8,
                    right: 20,
                    child: AppearancePanel(
                      onClose: () => setState(() => _appearanceOpen = false),
                    ),
                  ),
                ],
                if (_cmdkOpen)
                  CommandPalette(
                    onClose: () => setState(() => _cmdkOpen = false),
                  ),
                if (_activityOpen)
                  ActivityDrawer(
                    onClose: () => setState(() => _activityOpen = false),
                    onNavigate: (route) {
                      setState(() => _activityOpen = false);
                      _go(route);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 监听聚合下载任务，新出现的「已完成」任务在开关开启时发送系统通知，
  /// 同时保留应用内 toast 作为前台反馈和原生通知不可用时的降级路径。
  /// 首帧把当前已完成项纳入基线，之后只对增量完成弹窗，并按 uniqueKey 去重。
  void _listenDownloadComplete() {
    ref.listen<List<UnifiedDownloadTask>>(aggregatedDownloadTasksProvider, (
      prev,
      next,
    ) {
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
      final l = AppLocalizations.of(context);
      for (final t in completed) {
        if (_notifiedCompleted.add(t.uniqueKey) && notify) {
          final message = l.shellNavToastDownloadComplete(t.name);
          context.showSuccessToast(message);
          AppError.fireAndForget(
            SystemNotificationService.instance
                .show(title: AppConstants.appName, body: message)
                .then<void>((_) {}),
            action: 'downloadCompleteSystemNotification',
          );
        }
      }
    });
  }

  // ---- nav items ----

  List<NavGroup> _mediaGroups(AppLocalizations l, MediaCounts counts) => [
    NavGroup(
      items: [
        NavEntry(
          id: 'home',
          route: '/home',
          label: l.shellNavEntryHome,
          icon: Icons.home_outlined,
        ),
      ],
    ),
    NavGroup(
      label: l.shellNavGroupMyMedia,
      items: [
        NavEntry(
          id: 'films',
          route: '/video',
          label: l.shellNavEntryFilms,
          icon: Icons.movie_outlined,
          count: formatCountBadge(counts.video),
        ),
        NavEntry(
          id: 'live',
          route: '/live',
          label: l.shellNavEntryLive,
          icon: Icons.cast_rounded,
          live: true,
        ),
        NavEntry(
          id: 'music',
          route: '/music',
          label: l.shellNavEntryMusic,
          icon: Icons.library_music_outlined,
          count: formatCountBadge(counts.music),
        ),
        NavEntry(
          id: 'photos',
          route: '/photo',
          label: l.shellNavEntryPhotos,
          icon: Icons.photo_library_outlined,
          count: formatCountBadge(counts.photo),
        ),
        NavEntry(
          id: 'reading',
          route: '/reading',
          label: l.shellNavEntryReading,
          icon: Icons.menu_book_outlined,
          count: formatCountBadge(counts.reading),
        ),
      ],
    ),
    NavGroup(
      label: l.shellNavGroupFoundation,
      items: [
        NavEntry(
          id: 'files',
          route: '/files',
          label: l.shellNavEntryFiles,
          icon: Icons.folder_outlined,
        ),
      ],
    ),
  ];

  List<NavGroup> _opsGroups(AppLocalizations l) => [
    NavGroup(
      items: [
        NavEntry(
          id: 'ops',
          route: '/ops',
          label: l.shellNavEntryOpsOverview,
          icon: Icons.dashboard_customize_outlined,
        ),
      ],
    ),
    NavGroup(
      label: l.shellNavGroupTransferDownload,
      items: [
        NavEntry(
          id: 'downloads',
          route: '/download',
          label: l.shellNavEntryDownloader,
          icon: Icons.download_rounded,
        ),
        NavEntry(
          id: 'transfers',
          route: '/transfer',
          label: l.shellNavEntryTransferQueue,
          icon: Icons.swap_horiz_rounded,
        ),
      ],
    ),
    NavGroup(
      label: l.shellNavGroupResourceAutomation,
      items: [
        NavEntry(
          id: 'pt',
          route: '/pt',
          label: l.shellNavEntryPtSites,
          icon: Icons.flag_circle_outlined,
        ),
        NavEntry(
          id: 'nastool',
          route: '/nastool',
          label: l.shellNavEntryMediaAutomation,
          icon: Icons.auto_awesome_outlined,
        ),
        NavEntry(
          id: 'sources',
          route: '/sources',
          label: l.shellNavEntrySources,
          icon: Icons.lan_rounded,
        ),
      ],
    ),
  ];

  List<String> _crumbFor(AppLocalizations l, String path) {
    final map = <String, List<String>>{
      '/home': [l.shellNavCrumbMedia, l.shellNavEntryHome],
      '/video': [l.shellNavCrumbMedia, l.shellNavEntryFilms],
      '/live': [l.shellNavCrumbMedia, l.shellNavEntryLive],
      '/music': [l.shellNavCrumbMedia, l.shellNavEntryMusic],
      '/photo': [l.shellNavCrumbMedia, l.shellNavEntryPhotos],
      '/reading': [l.shellNavCrumbMedia, l.shellNavEntryReading],
      '/mine': ['', l.shellNavCrumbSettings],
      '/ops': [l.shellNavCrumbConsole, l.shellNavEntryOpsOverview],
      '/download': [l.shellNavCrumbConsole, l.shellNavEntryDownloader],
      '/transfer': [l.shellNavCrumbConsole, l.shellNavEntryTransferQueue],
      '/sources': [l.shellNavCrumbConsole, l.shellNavEntrySources],
      '/pt': [l.shellNavCrumbConsole, l.shellNavEntryPtSites],
      '/nastool': [l.shellNavCrumbConsole, l.shellNavEntryMediaAutomation],
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
