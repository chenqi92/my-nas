import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:my_nas/app/router/app_router.dart';
import 'package:my_nas/app/router/routes.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/i18n/app_l10n.dart';
import 'package:my_nas/core/platform/jump_list_service.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/music/data/services/music_favorites_service.dart';
import 'package:my_nas/features/music/domain/entities/music_item.dart';
import 'package:my_nas/features/music/presentation/providers/music_favorites_provider.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';
import 'package:my_nas/features/video/data/services/video_history_service.dart';
import 'package:my_nas/features/video/domain/entities/video_item.dart';
import 'package:my_nas/features/video/presentation/pages/video_player_page.dart';
import 'package:my_nas/features/video/presentation/providers/video_history_provider.dart';

/// Windows JumpList 控制器：
/// - 启动时推送固定 Tasks
/// - 监听 music / video 播放历史，把最近 5 + 5 合并推到 Recent
/// - 接收来自 Jump List / secondary 实例的 deep link 并分发到对应模块
///
/// 在非 Windows 平台所有方法都是 no-op，调用方可以无判定地直接构造。
class JumpListController {
  factory JumpListController() => _instance;
  JumpListController._();

  static final JumpListController _instance = JumpListController._();

  bool _initialized = false;
  WidgetRef? _ref;
  ProviderSubscription<AsyncValue<List<VideoHistoryItem>>>? _videoSub;
  ProviderSubscription<MusicHistoryState>? _musicSub;
  StreamSubscription<String>? _deepLinkSub;
  Timer? _debounce;
  // 缓存最近一次推过的 args 列表，避免 history 抖动时无谓 IPC。
  List<String> _lastRecentArgs = const [];

  /// 在 MyNasApp.build 里调用即可，幂等。
  void init(WidgetRef ref) {
    if (!Platform.isWindows) return;
    _ref = ref;

    final svc = JumpListService()..init();

    if (!_initialized) {
      _initialized = true;
      // 推送固定 Tasks。
      AppError.fireAndForget(
        svc.setTasks(_buildStaticTasks()),
        action: 'JumpList.setTasks',
      );

      // 监听运行时 deep link（WM_COPYDATA 转发的二次启动 / jump list 点击）。
      _deepLinkSub = svc.deepLinkStream.listen(
        _handleDeepLink,
        onError: (Object e, StackTrace st) =>
            AppError.handle(e, st, 'jumpList.deepLink'),
      );

      // 消费本次启动的命令行 deep link（如果 app 是被 jump list 拉起的）。
      final initial = svc.consumeInitialArg();
      if (initial != null && initial.isNotEmpty) {
        // 延后到首帧之后，确保 router 已挂载、ctx 可用。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          AppError.fireAndForget(
            _handleDeepLink(initial),
            action: 'JumpList.initialDeepLink',
          );
        });
      }
    }

    // ref 每次 build 都可能换实例，重新订阅。
    _videoSub?.close();
    _musicSub?.close();
    _videoSub = ref.listenManual<AsyncValue<List<VideoHistoryItem>>>(
      videoHistoryProvider,
      (prev, next) => _scheduleRecentRefresh(),
      fireImmediately: true,
    );
    _musicSub = ref.listenManual<MusicHistoryState>(
      musicHistoryProvider,
      (prev, next) => _scheduleRecentRefresh(),
      fireImmediately: true,
    );
  }

  void dispose() {
    _deepLinkSub?.cancel();
    _videoSub?.close();
    _musicSub?.close();
    _debounce?.cancel();
    _initialized = false;
    _ref = null;
  }

  // ---------------- Tasks ----------------

  List<JumpListItem> _buildStaticTasks() => [
        JumpListItem(
          label: appL10n.jumpListOpenMusic,
          args: 'mynas://music',
          tooltip: appL10n.jumpListOpenMusicLibrary,
        ),
        JumpListItem(
          label: appL10n.jumpListOpenVideoLibrary,
          args: 'mynas://video',
          tooltip: appL10n.jumpListOpenVideoLibrary,
        ),
        JumpListItem(
          label: appL10n.jumpListOpenFileBrowser,
          // 文件浏览器目前挂在 mine 页内；如果未来独立成路由，改这里即可。
          args: 'mynas://mine',
          tooltip: appL10n.jumpListOpenFileBrowser,
        ),
        JumpListItem(
          label: appL10n.jumpListOpenSettings,
          args: 'mynas://mine',
          tooltip: appL10n.jumpListOpenSettings,
        ),
      ];

  // ---------------- Recent ----------------

  void _scheduleRecentRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _pushRecent);
  }

  Future<void> _pushRecent() async {
    final ref = _ref;
    if (ref == null) return;

    // 读取当前 history 快照。
    final videoState = ref.read(videoHistoryProvider);
    final musicState = ref.read(musicHistoryProvider);

    final videos = videoState.maybeWhen(
      data: (list) => list,
      orElse: () => const <VideoHistoryItem>[],
    );
    final musics = musicState.history;

    // 各取 5 条（已按 watchedAt/playedAt 排序，最新在前）。
    final items = <JumpListItem>[];
    for (final v in videos.take(5)) {
      items.add(JumpListItem(
        label: v.videoName,
        args: 'mynas://video/play?path=${Uri.encodeQueryComponent(v.videoPath)}',
        tooltip: v.videoName,
      ));
    }
    for (final m in musics.take(5)) {
      final artist = (m.artist?.isNotEmpty ?? false) ? ' - ${m.artist}' : '';
      items.add(JumpListItem(
        label: '${m.musicName}$artist',
        args: 'mynas://music/play?path=${Uri.encodeQueryComponent(m.musicPath)}',
        tooltip: '${m.musicName}$artist',
      ));
    }

    final argsSnapshot = items.map((e) => e.args).toList(growable: false);
    if (_listEquals(argsSnapshot, _lastRecentArgs)) {
      return; // 无变化，跳过 IPC
    }
    _lastRecentArgs = argsSnapshot;

    await JumpListService().setRecent(items);
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // ---------------- Deep Link ----------------

  Future<void> _handleDeepLink(String url) async {
    try {
      final uri = Uri.parse(url);
      if (uri.scheme != 'mynas') return;

      final host = uri.host;
      final path = uri.path;
      final ctx = rootNavigatorKey.currentContext;

      // 简单 navigate：mynas://music / video / photo / mine
      if (path.isEmpty || path == '/') {
        final target = switch (host) {
          'music' => Routes.music,
          'video' => Routes.video,
          'photo' => Routes.photo,
          'reading' => Routes.reading,
          'mine' => Routes.mine,
          _ => null,
        };
        if (target != null && ctx != null) {
          ctx.go(target);
        }
        return;
      }

      // Recent 播放：mynas://music/play?path=...
      if (host == 'music' && path == '/play') {
        final musicPath = uri.queryParameters['path'];
        if (musicPath != null && musicPath.isNotEmpty) {
          await _playMusicByPath(musicPath);
        }
        return;
      }

      // Recent 播放：mynas://video/play?path=...
      if (host == 'video' && path == '/play') {
        final videoPath = uri.queryParameters['path'];
        if (videoPath != null && videoPath.isNotEmpty) {
          await _playVideoByPath(videoPath);
        }
        return;
      }

      logger.w('JumpListController: unhandled deep link: $url');
    } on Object catch (e, st) {
      AppError.ignore(e, st, 'JumpList._handleDeepLink');
    }
  }

  Future<void> _playMusicByPath(String musicPath) async {
    final ref = _ref;
    if (ref == null) return;

    // 从 history 缓存还原 MusicItem 并播放。
    final favSvc = MusicFavoritesService();
    await favSvc.init();
    final history = await favSvc.getRecentHistory(limit: 500);
    final hit = history.firstWhere(
      (h) => h.musicPath == musicPath,
      orElse: () => throw StateError('not found'),
    );

    final item = MusicItem(
      id: '${hit.sourceId ?? ''}_${hit.musicPath}',
      name: hit.musicName,
      path: hit.musicPath,
      url: hit.musicUrl,
      sourceId: hit.sourceId,
      title: hit.musicName,
      artist: hit.artist,
      album: hit.album,
      coverUrl: hit.coverUrl,
      duration: hit.duration,
    );

    ref.read(playQueueProvider.notifier).setQueue([item]);
    final playerNotifier = ref.read(musicPlayerControllerProvider.notifier)
      ..updateCurrentIndex(0);
    await playerNotifier.play(item);

    final ctx = rootNavigatorKey.currentContext;
    if (ctx != null) {
      // ctx 在 await 之后才从全局 navigatorKey 取值，不是跨 gap 的陈旧引用
      // ignore: use_build_context_synchronously
      ctx.go(Routes.musicPlayer);
    }
  }

  Future<void> _playVideoByPath(String videoPath) async {
    final svc = VideoHistoryService();
    await svc.init();
    final history = await svc.getHistory(limit: 500);
    final hit = history.firstWhere(
      (h) => h.videoPath == videoPath,
      orElse: () => throw StateError('not found'),
    );

    final video = VideoItem(
      name: hit.videoName,
      path: hit.videoPath,
      url: hit.videoUrl,
      sourceId: hit.sourceId,
      size: hit.size,
      duration: hit.duration,
      thumbnailUrl: hit.thumbnailUrl,
      lastPosition: hit.lastPosition,
    );

    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null) return;

    // 先回到 /video（保证 NavigationRail 在视频 tab），再 push 播放器。
    // ignore: use_build_context_synchronously — 从全局 navigatorKey 新取，非跨 gap 陈旧引用
    ctx.go(Routes.video);
    // 等一帧让 go_router 完成 navigation 再 push。
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final navCtx = rootNavigatorKey.currentContext;
    if (navCtx != null) {
      // ignore: use_build_context_synchronously — 同上，await 后重新取
      await Navigator.of(navCtx).push<void>(
        MaterialPageRoute<void>(builder: (_) => VideoPlayerPage(video: video)),
      );
    }
  }
}
