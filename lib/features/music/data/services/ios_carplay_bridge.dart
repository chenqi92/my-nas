import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:my_nas/core/errors/errors.dart';
import 'package:my_nas/core/utils/logger.dart';
import 'package:my_nas/features/music/data/services/music_browser_service.dart';

/// iOS CarPlay 桥接
///
/// 把 [MusicBrowserService] 的浏览树 + 播放回调暴露给 iOS 原生层
/// (`CarPlaySceneDelegate`)。channel name 必须与 Swift 端一致：
/// `com.kkape.mynas/carplay`。
///
/// 双向约定：
/// - Swift → Dart：`getChildren / getMediaItem / playFromMediaId / getNowPlaying`
/// - Dart → Swift：`nowPlayingChanged`（当前曲目变化时通知 CarPlay 刷新）
///
/// 非 iOS 平台调用 [init] 直接 no-op。
class IosCarPlayBridge {
  IosCarPlayBridge._();
  static final IosCarPlayBridge instance = IosCarPlayBridge._();

  static const MethodChannel _channel =
      MethodChannel('com.kkape.mynas/carplay');

  bool _initialized = false;
  StreamSubscription<MediaItem?>? _nowPlayingSub;

  /// 在 main.dart 初始化 audioHandler 之后调用。
  /// 注册 Swift→Dart 调用 handler，并订阅 audioHandler 的 mediaItem 流，
  /// 把变化反向告诉 Swift 端，让 CarPlay Now Playing 模板可以及时弹出。
  void init(BaseAudioHandler audioHandler) {
    if (!Platform.isIOS) return;
    if (_initialized) return;
    _initialized = true;

    _channel.setMethodCallHandler(_handleSwiftCall);

    _nowPlayingSub = audioHandler.mediaItem.listen((item) {
      AppError.fireAndForget(
        _channel.invokeMethod('nowPlayingChanged', _itemToMap(item)),
        action: 'carplay.nowPlayingChanged',
      );
    });

    logger.i('IosCarPlayBridge: 已注册 CarPlay 桥接通道');
  }

  /// 释放（一般不会调，进程级别单例随 App 生存）
  Future<void> dispose() async {
    await _nowPlayingSub?.cancel();
    _nowPlayingSub = null;
    _channel.setMethodCallHandler(null);
    _initialized = false;
  }

  Future<Object?> _handleSwiftCall(MethodCall call) async {
    try {
      switch (call.method) {
        case 'getChildren':
          final args = (call.arguments as Map?)?.cast<String, Object?>() ?? {};
          final parent = (args['parentMediaId'] as String?) ?? kMediaRootId;
          final children =
              await MusicBrowserService.instance.getChildren(parent);
          return [for (final m in children) _itemToMap(m)!];

        case 'getMediaItem':
          final args = (call.arguments as Map?)?.cast<String, Object?>() ?? {};
          final mediaId = (args['mediaId'] as String?) ?? '';
          final item =
              await MusicBrowserService.instance.getMediaItem(mediaId);
          return _itemToMap(item);

        case 'playFromMediaId':
          final args = (call.arguments as Map?)?.cast<String, Object?>() ?? {};
          final mediaId = (args['mediaId'] as String?) ?? '';
          if (mediaId.isNotEmpty) {
            await MusicBrowserService.instance.playFromMediaId(mediaId);
          }
          return null;

        case 'getNowPlaying':
          // Now Playing 由 nowPlayingChanged 推送给 Swift 端；这里留个查询入口
          // 给 CarPlay 启动时回填用，但当前数据由 audioHandler.mediaItem 流维护，
          // 拉一次 latest 即可——bridge 自己不持有状态，返回 null 由调用方降级
          return null;
      }
    } on Exception catch (e, st) {
      AppError.handle(e, st, 'carplay.handleCall', {'method': call.method});
    }
    return null;
  }

  /// 把 audio_service 的 [MediaItem] 转成 Swift 端约定的 Map
  Map<String, Object?>? _itemToMap(MediaItem? item) {
    if (item == null) return null;
    final playable = item.playable ?? false;
    return <String, Object?>{
      'id': item.id,
      'title': item.title,
      'subtitle': item.artist ?? item.album,
      'album': item.album,
      'isPlayable': playable,
      'isBrowsable': !playable,
      'artUri': item.artUri?.toString(),
    };
  }
}
