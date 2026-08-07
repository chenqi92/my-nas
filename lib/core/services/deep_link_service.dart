import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_nas/core/errors/app_error_handler.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/music/presentation/providers/music_favorites_provider.dart';
import 'package:my_nas/features/music/presentation/providers/music_player_provider.dart';

/// Trakt OAuth 回调数据
class TraktOAuthCallback {
  const TraktOAuthCallback({required this.code, this.state});
  final String code;

  /// 回调携带的 CSRF 令牌，由 provider 与发起授权时保存的值比对
  final String? state;
}

/// Trakt OAuth 回调流
final traktOAuthCallbackProvider = StreamProvider<TraktOAuthCallback>(
  (ref) => DeepLinkService()._traktCallbackController.stream,
);

/// Deep Link 服务
/// 处理来自灵动岛、Widget、OAuth 回调等的控制命令
class DeepLinkService {
  factory DeepLinkService() => _instance ??= DeepLinkService._();
  DeepLinkService._();

  static DeepLinkService? _instance;

  AppLinks? _appLinks;
  StreamSubscription<Uri>? _linkSubscription;
  WidgetRef? _ref;

  /// Trakt OAuth 回调控制器
  final _traktCallbackController =
      StreamController<TraktOAuthCallback>.broadcast();

  /// 初始化服务
  void init(WidgetRef ref) {
    _ref = ref;

    // 在移动端启用深度链接（iOS: 灵动岛 + OAuth，Android: OAuth）
    if (!Platform.isIOS && !Platform.isAndroid) return;

    try {
      _appLinks = AppLinks();

      // 监听后续的链接
      _linkSubscription = _appLinks!.uriLinkStream.listen(
        _handleDeepLink,
        onError: (Object err, StackTrace st) {
          AppError.handle(err, st, 'DeepLinkService.uriLinkStream');
        },
      );

      // 获取初始链接（如果应用是通过 deep link 启动的）
      _appLinks!.getInitialLink().then((uri) {
        if (uri != null) {
          _handleDeepLink(uri);
        }
      }).catchError((Object error, StackTrace st) {
        AppError.handle(error, st, 'DeepLinkService.getInitialLink');
      });

      logger.i('DeepLinkService: Initialized on ${Platform.operatingSystem}');
    } catch (e, st) {
      AppError.handle(e, st, 'DeepLinkService.init');
      // 清理资源
      _appLinks = null;
      _linkSubscription = null;
      rethrow; // 重新抛出异常，让上层处理
    }
  }

  /// 处理 deep link
  void _handleDeepLink(Uri uri) {
    logger.i('DeepLinkService: Received deep link: $uri');

    if (uri.scheme != 'mynas') return;

    final host = uri.host; // e.g., "music", "trakt"
    final path = uri.path; // e.g., "/toggle", "/callback"

    switch (host) {
      case 'music':
        _handleMusicCommand(path);
      case 'trakt':
        _handleTraktCallback(uri);
      default:
        logger.w('DeepLinkService: Unknown host: $host');
    }
  }

  /// 处理 Trakt OAuth 回调
  /// URL 格式: mynas://trakt/callback?code=AUTHORIZATION_CODE&state=CSRF_TOKEN
  void _handleTraktCallback(Uri uri) {
    final code = uri.queryParameters['code'];
    if (code == null || code.isEmpty) {
      logger.w('DeepLinkService: Trakt callback missing code parameter');
      return;
    }

    logger.i('DeepLinkService: Received Trakt OAuth code');
    _traktCallbackController.add(
      TraktOAuthCallback(code: code, state: uri.queryParameters['state']),
    );
  }

  /// 处理音乐控制命令
  void _handleMusicCommand(String path) {
    final ref = _ref;
    if (ref == null) {
      logger.w('DeepLinkService: WidgetRef not available');
      return;
    }

    final controller = ref.read(musicPlayerControllerProvider.notifier);

    switch (path) {
      case '/toggle':
        // 切换播放/暂停
        final isPlaying = ref.read(musicPlayerControllerProvider).isPlaying;
        if (isPlaying) {
          controller.pause();
          logger.d('DeepLinkService: Paused playback');
        } else {
          controller.resume();
          logger.d('DeepLinkService: Resumed playback');
        }

      case '/previous':
        // 上一首
        controller.playPrevious();
        logger.d('DeepLinkService: Playing previous track');

      case '/next':
        // 下一首
        controller.playNext();
        logger.d('DeepLinkService: Playing next track');

      case '/favorite':
        // 收藏当前歌曲
        final currentMusic = ref.read(currentMusicProvider);
        if (currentMusic != null) {
          ref.read(musicFavoritesProvider.notifier).toggleFavorite(currentMusic);
          logger.d('DeepLinkService: Toggled favorite for ${currentMusic.displayTitle}');
        }

      case '/player':
        // 打开播放器页面 - 这个由路由处理
        logger.d('DeepLinkService: Open player page request');

      default:
        logger.w('DeepLinkService: Unknown music command: $path');
    }
  }

  /// 释放资源
  void dispose() {
    _linkSubscription?.cancel();
    _traktCallbackController.close();
    _ref = null;
    logger.i('DeepLinkService: Disposed');
  }
}

/// DeepLinkService Provider
final deepLinkServiceProvider = Provider<DeepLinkService>((ref) => DeepLinkService());
