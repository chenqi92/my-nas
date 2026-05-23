import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/app/router/app_router.dart';
import 'package:my_nas/app/router/routes.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/platform/spotlight/spotlight_channel.dart';
import 'package:my_nas/core/platform/spotlight/spotlight_item.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/book/data/services/book_database_service.dart';
import 'package:my_nas/features/book/domain/entities/book_item.dart';
import 'package:my_nas/features/book/presentation/utils/book_navigator.dart';
import 'package:my_nas/features/comic/data/services/comic_library_cache_service.dart';
import 'package:my_nas/features/comic/presentation/pages/comic_list_page.dart';
import 'package:my_nas/features/comic/presentation/pages/comic_reader_page.dart';
import 'package:my_nas/features/reading/presentation/pages/reading_page.dart';
import 'package:my_nas/features/sources/presentation/providers/source_provider.dart';
import 'package:my_nas/features/video/data/services/video_database_service.dart';
import 'package:my_nas/features/video/presentation/pages/video_detail_page.dart';
import 'package:my_nas/nas_adapters/base/nas_file_system.dart';

/// 用户从 macOS Spotlight 结果点过来的目标，list 页可以 watch
/// 它来高亮 / 滚动到对应条目；handler 本身也会尝试自动 push 到 detail。
///
/// 值消费后由消费方调用 `state = null` 清空。
class SpotlightDeepLinkTarget {
  const SpotlightDeepLinkTarget({required this.kind, required this.rawId});

  final SpotlightItemKind kind;

  /// 原始业务 id（已 URL-decode）。视频/书/漫画/笔记/音乐通常是
  /// `<sourceId>|<filePath>`。
  final String rawId;
}

final spotlightTargetProvider =
    StateProvider<SpotlightDeepLinkTarget?>((_) => null);

/// 监听 native 的 Spotlight 点击事件并路由到对应 tab+detail。
///
/// - 应用启动时由 [_MyNasAppState._initSpotlightHandler] 触发初始化。
/// - cold-start：通过 `consumePendingDeepLink` 拉一次 native 缓存的 id。
/// - 运行时：监听 `onSpotlightOpen` callback。
///
/// 实现策略：先 `appRouter.go(/<tab>)` 切到对应 branch，再用
/// [branchNavigatorKeys] 拿到 branch 的 Navigator state 直接 push detail，
/// 避免侵入每个 list 页面。
class SpotlightDeepLinkHandler {
  SpotlightDeepLinkHandler._(this._ref) {
    _attach();
  }

  static SpotlightDeepLinkHandler? _instance;

  static SpotlightDeepLinkHandler ensureStarted(WidgetRef ref) =>
      _instance ??= SpotlightDeepLinkHandler._(ref);

  final WidgetRef _ref;

  void _attach() {
    if (!SpotlightChannel.isSupported) return;

    SpotlightChannel.channel.setMethodCallHandler((call) async {
      if (call.method == 'onSpotlightOpen') {
        final id = call.arguments as String?;
        if (id != null) _route(id);
      }
    });

    // 处理 cold-start 缓存
    AppError.fireAndForget(
      () async {
        final pending = await SpotlightChannel.consumePendingDeepLink();
        if (pending != null) _route(pending);
      }(),
      action: 'SpotlightDeepLinkHandler.consumePending',
    );
  }

  /// 解析 `mynas://<kind>/<encodedRawId>` 并跳转到对应 tab + detail。
  void _route(String spotlightId) {
    try {
      final uri = Uri.parse(spotlightId);
      if (uri.scheme != 'mynas') {
        logger.w('SpotlightDeepLink: unexpected scheme: $spotlightId');
        return;
      }
      final host = uri.host;
      final kind = SpotlightItemKind.values.firstWhere(
        (k) => k.wireName == host,
        orElse: () => SpotlightItemKind.note,
      );
      final rawId = uri.pathSegments.isNotEmpty
          ? Uri.decodeComponent(uri.pathSegments.first)
          : '';

      _ref.read(spotlightTargetProvider.notifier).state =
          SpotlightDeepLinkTarget(kind: kind, rawId: rawId);

      AppError.fireAndForget(
        _navigateAndOpen(kind, rawId),
        action: 'SpotlightDeepLinkHandler.navigate.${kind.wireName}',
      );
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'SpotlightDeepLinkHandler._route');
    }
  }

  Future<void> _navigateAndOpen(SpotlightItemKind kind, String rawId) async {
    // 1) 切到对应 tab
    final dest = switch (kind) {
      SpotlightItemKind.video => Routes.video,
      SpotlightItemKind.music => Routes.music,
      SpotlightItemKind.book ||
      SpotlightItemKind.comic ||
      SpotlightItemKind.note =>
        Routes.reading,
    };

    if (rootNavigatorKey.currentContext == null) {
      // 启动太早，由 spotlightTargetProvider 兜底 list 页自行处理
      logger.d('SpotlightDeepLink: router not ready, deferring nav to $dest');
      return;
    }
    appRouter.go(dest);

    // reading 子 tab：book/comic/note → 0/1/2
    switch (kind) {
      case SpotlightItemKind.book:
        _ref.read(readingTabProvider.notifier).state = 0;
      case SpotlightItemKind.comic:
        _ref.read(readingTabProvider.notifier).state = 1;
      case SpotlightItemKind.note:
        _ref.read(readingTabProvider.notifier).state = 2;
      case SpotlightItemKind.video:
      case SpotlightItemKind.music:
        break;
    }

    // 2) 等下一帧让 branch navigator 完成挂载，再 push detail
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final parts = rawId.split('|');
    if (parts.length < 2) return;
    final sourceId = parts[0];
    final filePath = parts.sublist(1).join('|');

    switch (kind) {
      case SpotlightItemKind.video:
        await _pushVideoDetail(sourceId, filePath);
      case SpotlightItemKind.book:
        await _openBook(sourceId, filePath);
      case SpotlightItemKind.comic:
        await _pushComicReader(sourceId, filePath);
      case SpotlightItemKind.note:
      case SpotlightItemKind.music:
        // 音乐 / 笔记没有"独立 detail page"——切到 tab 后由 list 自身处理
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // 各 kind 的 detail push 实现
  // ---------------------------------------------------------------------------

  Future<void> _pushVideoDetail(String sourceId, String filePath) async {
    final key = '$sourceId|$filePath';
    final found = await VideoDatabaseService().getByKeys([key]);
    final metadata = found[key];
    if (metadata == null) {
      logger.w('SpotlightDeepLink: video not found $key');
      return;
    }
    // video branch index = 0
    final nav = branchNavigatorKeys[0].currentState;
    if (nav == null) return;
    await nav.push(MaterialPageRoute<void>(
      builder: (_) =>
          VideoDetailPage(metadata: metadata, sourceId: metadata.sourceId),
    ));
  }

  Future<void> _openBook(String sourceId, String filePath) async {
    final entity = await BookDatabaseService().get(sourceId, filePath);
    if (entity == null) {
      logger.w('SpotlightDeepLink: book not found $sourceId|$filePath');
      return;
    }
    final connections = _ref.read(activeConnectionsProvider);
    final connection = connections[sourceId];
    if (connection == null) {
      // 未连上对应数据源，停在 reading→book sub-tab 就行
      logger.w('SpotlightDeepLink: book source not connected $sourceId');
      return;
    }
    final file = FileItem(
      name: entity.fileName,
      path: entity.filePath,
      size: entity.size,
      isDirectory: false,
      modifiedTime: entity.modifiedTime,
    );
    final url = await connection.adapter.fileSystem.getFileUrl(file.path);
    final book = BookItem.fromFileItem(file, url, sourceId: sourceId);

    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null) return;
    await BookNavigator.instance.openBook(ctx, book);
  }

  Future<void> _pushComicReader(String sourceId, String filePath) async {
    final cache = ComicLibraryCacheService().getCache();
    if (cache == null) {
      logger.w('SpotlightDeepLink: comic cache empty');
      return;
    }
    ComicLibraryCacheEntry? entry;
    for (final c in cache.comics) {
      if (c.sourceId == sourceId && c.folderPath == filePath) {
        entry = c;
        break;
      }
    }
    if (entry == null) {
      logger.w('SpotlightDeepLink: comic not found $sourceId|$filePath');
      return;
    }
    final comic = ComicItem.fromCacheEntry(entry);
    // reading branch index = 3
    final nav = branchNavigatorKeys[3].currentState;
    if (nav == null) return;
    await nav.push(MaterialPageRoute<void>(
      builder: (_) => ComicReaderPage(comic: comic),
    ));
  }
}
